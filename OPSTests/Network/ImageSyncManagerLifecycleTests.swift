import XCTest
import SwiftData
import UIKit
import Supabase
@testable import OPS

@MainActor
final class ImageSyncManagerLifecycleTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var suites: [String] = []
    private var managers: [ImageSyncManager] = []

    override func tearDown() {
        for manager in managers { manager.invalidate() }
        managers = []
        containers = []
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        suites = []
        super.tearDown()
    }

    private struct Fixture {
        let context: ModelContext
        let project: Project
        let defaults: UserDefaults
        let scheduler: ManualImageSyncScheduler
        let identity: ImageSyncTestIdentity
        let manager: ImageSyncManager
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "ImageSyncManagerLifecycleTests.\(UUID().uuidString)"
        suites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    private func fixture(seedMirror: Bool = true, seedUpload: Bool = false, initialAccount: CaptureAccountIdentity? = .init(companyID: "company-a", userID: "user-a")) throws -> Fixture {
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        containers.append(container)
        let context = ModelContext(container)
        let project = Project(id: "project-a", title: "Saved roof", status: .inProgress)
        project.companyId = "company-a"
        context.insert(project)
        try context.save()
        let defaults = try isolatedDefaults()
        defaults.set("user-a", forKey: "currentUserId")
        defaults.set("company-a", forKey: "currentCompanyId")
        let mirror = PendingPortalMirror(url: "https://example.test/photo.jpg", projectId: project.id, companyId: project.companyId, uploadedBy: "user-a", source: "in_progress", takenAt: Date(timeIntervalSince1970: 1))
        if seedMirror { defaults.set(try JSONEncoder().encode([mirror]), forKey: ImageSyncManager.pendingPortalMirrorsKey) }
        if seedUpload {
            let upload = PendingImageUpload(localURL: "local://project_images/lifecycle-fixture.jpg", projectId: project.id, companyId: project.companyId, timestamp: Date(timeIntervalSince1970: 4))
            defaults.set(try JSONEncoder().encode([upload]), forKey: "pendingImageUploads")
        }
        let identity = ImageSyncTestIdentity()
        identity.value = initialAccount
        let scheduler = ManualImageSyncScheduler()
        let manager = ImageSyncManager(modelContext: context, connectivity: ConnectivityManager(), defaults: defaults,
            currentAccount: { identity.value }, isConnected: { true }, scheduler: scheduler)
        // Any unexpected branch must remain synthetic; these ports never send.
        manager.strandedMirrorReader = EmptyLifecycleMirrorReader()
        manager.projectServerStateProbe = ActiveLifecycleProjectProbe()
        manager.portalMirrorInserter = AcceptingLifecycleMirrorInserter()
        manager.portalMirrorReporter = SilentLifecycleReporter()
        manager.projectImageUpload = { _, _, _ in [] }
        manager.photoSoftDelete = { _, _ in }
        manager.photosAddedPush = { _ in }
        manager.photosAddedSyncer = EmptyLifecyclePhotosAddedSyncer()
        managers.append(manager)
        return Fixture(context: context, project: project, defaults: defaults, scheduler: scheduler, identity: identity, manager: manager)
    }

    func testDelayedMirrorSuccessCannotOverwriteReplacementQueueAfterInvalidation() async throws {
        let f = try fixture()
        let suspended = SuspendedLifecycleMirrorInserter()
        f.manager.portalMirrorInserter = suspended
        let delivery = Task { await f.manager.drainPendingPortalMirrors() }
        await suspended.waitUntilStarted()
        f.manager.invalidate()
        let replacement = PendingPortalMirror(url: "https://example.test/new-manager.jpg", projectId: "project-b", companyId: "company-a", uploadedBy: "user-a", source: "in_progress", takenAt: Date(timeIntervalSince1970: 2))
        var persisted = try JSONDecoder().decode([PendingPortalMirror].self, from: XCTUnwrap(f.defaults.data(forKey: ImageSyncManager.pendingPortalMirrorsKey)))
        persisted.append(replacement)
        let replacementBytes = try JSONEncoder().encode(persisted)
        f.defaults.set(replacementBytes, forKey: ImageSyncManager.pendingPortalMirrorsKey)
        await suspended.finish()
        await delivery.value
        XCTAssertEqual(f.defaults.data(forKey: ImageSyncManager.pendingPortalMirrorsKey), replacementBytes)
        XCTAssertEqual(f.manager.getPendingPortalMirrors().map(\.url), ["https://example.test/photo.jpg"])
        XCTAssertNil(f.project.deletedAt)
    }

    func testSuspendedDeletionProbeCannotTombstoneRetiredContext() async throws {
        let f = try fixture()
        let probe = SuspendedLifecycleProjectProbe()
        f.manager.projectServerStateProbe = probe
        let task = Task { await f.manager.projectIsSettledAsDeleted(f.project) }
        await probe.waitUntilStarted()
        f.manager.invalidate()
        await probe.finish()
        let settled = await task.value
        XCTAssertFalse(settled)
        XCTAssertNil(f.project.deletedAt)
        XCTAssertNil(try ModelContext(f.context.container).fetch(FetchDescriptor<Project>()).first?.deletedAt)
        XCTAssertTrue(f.manager.hasQueuedDeliveryWork)
    }

    func testNewMirrorIsDurableBeforeItsRequestSuspends() async throws {
        let f = try fixture(seedMirror: false)
        let suspended = SuspendedLifecycleMirrorInserter()
        f.manager.portalMirrorInserter = suspended
        let work = Task {
            await f.manager.deliverPortalMirror(urls: ["https://example.test/new.jpg"], project: f.project, uploadedBy: "user-a", source: "in_progress")
        }
        await suspended.waitUntilStarted()
        let bytes = try XCTUnwrap(f.defaults.data(forKey: ImageSyncManager.pendingPortalMirrorsKey))
        let pending = try JSONDecoder().decode([PendingPortalMirror].self, from: bytes)
        XCTAssertEqual(pending.map(\.url), ["https://example.test/new.jpg"])
        f.manager.invalidate()
        await suspended.finish()
        let result = await work.value
        XCTAssertEqual(result, .retryQueued)
        XCTAssertEqual(f.defaults.data(forKey: ImageSyncManager.pendingPortalMirrorsKey), bytes)
    }

    func testDelayedRejectionCannotStartFollowUpProbeAfterInvalidation() async throws {
        let f = try fixture()
        let suspended = SuspendedLifecycleMirrorInserter()
        let probe = CountingLifecycleProjectProbe()
        f.manager.portalMirrorInserter = suspended
        f.manager.projectServerStateProbe = probe
        let work = Task { await f.manager.drainPendingPortalMirrors() }
        await suspended.waitUntilStarted()
        let bytes = f.defaults.data(forKey: ImageSyncManager.pendingPortalMirrorsKey)
        f.manager.invalidate()
        await suspended.finish(success: false)
        await work.value
        let calls = await probe.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(f.defaults.data(forKey: ImageSyncManager.pendingPortalMirrorsKey), bytes)
    }

    func testDelayedRailResponseCannotSendPushAfterInvalidationOrAccountChange() async throws {
        for invalidate in [true, false] {
            let f = try fixture()
            let rail = SuspendedLifecyclePhotosAddedSyncer()
            f.manager.photosAddedSyncer = rail
            var pushCalls = 0
            f.manager.photosAddedPush = { _ in pushCalls += 1 }
            let work = try XCTUnwrap(f.manager.notifyCrewOfAddedPhotos(project: f.project, uploaderId: "user-a", photoCount: 1, firstURL: nil))
            await rail.gate.waitUntilStarted()
            if invalidate { f.manager.invalidate() }
            else { f.identity.value = .init(companyID: "company-b", userID: "user-b") }
            await rail.gate.finish(["recipient-a"])
            await work.value
            XCTAssertEqual(pushCalls, 0)
        }
    }

    func testFirstAccountAssignmentCanDrainWithoutRecreatingManager() async throws {
        let f = try fixture(initialAccount: nil)
        let inserter = CountingLifecycleMirrorInserter()
        f.manager.portalMirrorInserter = inserter
        f.identity.value = .init(companyID: "company-a", userID: "user-a")
        await f.manager.syncPendingImages()
        let calls = await inserter.calls
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(f.manager.getPendingPortalMirrors().isEmpty)
    }

    func testAccountSwitchStopsDelayedUploadModelWritesAndFollowUp() async throws {
        let f = try fixture()
        let upload = LifecycleResponseGate<Bool>()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        f.manager.projectImageUpload = { _, _, _ in
            _ = await upload.hold()
            return [.success(image: image, filename: "new.jpg", url: "https://example.test/new.jpg")]
        }
        let work = Task { await f.manager.saveImages([image], for: f.project) }
        await upload.waitUntilStarted()
        f.identity.value = .init(companyID: "company-b", userID: "user-b")
        await upload.finish(true)
        let returned = await work.value
        XCTAssertTrue(returned.isEmpty)
        XCTAssertTrue(f.project.getProjectImages().isEmpty)
        XCTAssertEqual(f.manager.getPendingPortalMirrors().map(\.url), ["https://example.test/photo.jpg"])
    }

    func testInvalidationCancelsTriggersAndQueuedTriggerCannotReenter() async throws {
        let f = try fixture(seedUpload: true)
        let inserter = CountingLifecycleMirrorInserter()
        f.manager.portalMirrorInserter = inserter
        XCTAssertTrue(f.scheduler.hasStartup)
        XCTAssertTrue(f.scheduler.hasRetry)
        XCTAssertTrue(f.scheduler.hasConnectivity)
        let bytes = f.defaults.data(forKey: ImageSyncManager.pendingPortalMirrorsKey)
        let uploadBytes = f.defaults.data(forKey: "pendingImageUploads")
        f.manager.invalidate()
        f.manager.invalidate()
        XCTAssertTrue(f.scheduler.allCancelled)
        // Simulate callbacks already dispatched when cancellation occurred.
        f.scheduler.fireEvenIfCancelled()
        await f.manager.syncPendingImages()
        await f.manager.drainPendingPortalMirrors()
        f.manager.clearAllPendingUploads()
        let calls = await inserter.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(f.defaults.data(forKey: ImageSyncManager.pendingPortalMirrorsKey), bytes)
        XCTAssertEqual(f.defaults.data(forKey: "pendingImageUploads"), uploadBytes)
        XCTAssertEqual(f.manager.getPendingUploads().count, 1)
        XCTAssertTrue(f.manager.hasQueuedDeliveryWork)
    }

    func testOverlappingDrainsClaimOwnershipBeforeFirstAwait() async throws {
        let f = try fixture()
        f.project.setProjectImageURLs(["https://example.test/local-gallery.jpg"])
        try f.context.save()
        let reader = SuspendedLifecycleMirrorReader()
        f.manager.strandedMirrorReader = reader
        let first = Task { await f.manager.syncPendingImages() }
        await reader.waitUntilStarted()
        await f.manager.syncPendingImages()
        let calls = await reader.calls
        XCTAssertEqual(calls, 1)
        f.manager.invalidate()
        await reader.finish()
        await first.value
        XCTAssertTrue(f.manager.hasQueuedDeliveryWork)
    }

    func testDelayedSoftDeleteKeepsTombstonePendingAfterInvalidation() async throws {
        let f = try fixture(seedMirror: false)
        let row = ProjectPhoto(id: "photo-a", projectId: f.project.id, companyId: f.project.companyId, url: "https://example.test/deleted.jpg", uploadedBy: "user-a")
        row.deletedAt = Date(timeIntervalSince1970: 3)
        row.needsSync = true
        f.context.insert(row)
        try f.context.save()
        let gate = LifecycleResponseGate<Bool>()
        f.manager.photoSoftDelete = { _, _ in _ = await gate.hold() }
        let work = Task { await f.manager.syncPendingImages() }
        await gate.waitUntilStarted()
        f.manager.invalidate()
        await gate.finish(true)
        await work.value
        let persisted = try XCTUnwrap(ModelContext(f.context.container).fetch(FetchDescriptor<ProjectPhoto>()).first)
        XCTAssertTrue(persisted.needsSync)
        XCTAssertEqual(persisted.deletedAt, Date(timeIntervalSince1970: 3))
    }

    func testManagerRetainsContainerUntilInvalidatedOwnerIsReleased() throws {
        var container: ModelContainer? = try ModelContainer(for: ProjectPhoto.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        weak var weakContainer = container
        let context = try XCTUnwrap(container).mainContext
        let scheduler = ManualImageSyncScheduler()
        var manager: ImageSyncManager? = ImageSyncManager(modelContext: context, connectivity: ConnectivityManager(), defaults: try isolatedDefaults(), currentAccount: { nil }, isConnected: { false }, scheduler: scheduler)
        container = nil
        XCTAssertNotNil(weakContainer)
        manager?.invalidate()
        XCTAssertNotNil(weakContainer, "Old references stay valid until their owner is released")
        manager = nil
        XCTAssertNil(weakContainer)
    }
}

@MainActor
private final class ImageSyncTestIdentity {
    var value: CaptureAccountIdentity? = .init(companyID: "company-a", userID: "user-a")
}

@MainActor
private final class ManualImageSyncScheduler: ImageSyncScheduling {
    private struct Entry { let kind: String; let action: @MainActor () -> Void; var cancelled = false }
    private var entries: [UUID: Entry] = [:]
    var hasStartup: Bool { entries.values.contains { $0.kind == "startup" } }
    var hasRetry: Bool { entries.values.contains { $0.kind == "retry" } }
    var hasConnectivity: Bool { entries.values.contains { $0.kind == "connectivity" } }
    var allCancelled: Bool { !entries.isEmpty && entries.values.allSatisfy(\.cancelled) }
    func schedule(after: TimeInterval, repeating: Bool, action: @escaping @MainActor () -> Void) -> ImageSyncCancellation {
        register(kind: repeating ? "retry" : "startup", action: action)
    }
    func observeConnectivity(action: @escaping @MainActor () -> Void) -> ImageSyncCancellation { register(kind: "connectivity", action: action) }
    private func register(kind: String, action: @escaping @MainActor () -> Void) -> ImageSyncCancellation {
        let id = UUID(); entries[id] = Entry(kind: kind, action: action)
        return ImageSyncCancellation { [weak self] in self?.entries[id]?.cancelled = true }
    }
    func fireEvenIfCancelled() { for entry in entries.values { entry.action() } }
}

private actor LifecycleResponseGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var started = false
    func hold() async -> Value {
        await withCheckedContinuation { continuation in
            self.continuation = continuation; started = true
            observer?.resume(); observer = nil
        }
    }
    func waitUntilStarted() async { if started { return }; await withCheckedContinuation { observer = $0 } }
    func finish(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
}

private actor SuspendedLifecycleMirrorInserter: ProjectPhotoMirrorInserting {
    let gate = LifecycleResponseGate<Bool>()
    func insertProjectPhotoRows(_ rows: [ProjectPhotoMirrorRow]) async throws {
        guard await gate.hold() else { throw PostgrestError(code: "42501", message: "new row violates row-level security policy") }
    }
    func waitUntilStarted() async { await gate.waitUntilStarted() }
    func finish(success: Bool = true) async { await gate.finish(success) }
}
private actor CountingLifecycleMirrorInserter: ProjectPhotoMirrorInserting {
    private(set) var calls = 0
    func insertProjectPhotoRows(_ rows: [ProjectPhotoMirrorRow]) async throws { calls += 1 }
}
private struct AcceptingLifecycleMirrorInserter: ProjectPhotoMirrorInserting {
    func insertProjectPhotoRows(_ rows: [ProjectPhotoMirrorRow]) async throws {}
}
private struct ActiveLifecycleProjectProbe: ProjectServerStateProbing {
    func isProjectVisible(projectId: String) async throws -> Bool { true }
    func projectServerState(projectId: String) async throws -> SyncOperationReconcilers.ProjectServerState? { .active }
}
private actor CountingLifecycleProjectProbe: ProjectServerStateProbing {
    private(set) var calls = 0
    func isProjectVisible(projectId: String) async throws -> Bool { calls += 1; return false }
    func projectServerState(projectId: String) async throws -> SyncOperationReconcilers.ProjectServerState? { calls += 1; return .deleted }
}
private struct EmptyLifecyclePhotosAddedSyncer: ProjectPhotosAddedNotifying {
    func notifyProjectPhotosAdded(projectId: String, photoCount: Int) async throws -> [String] { [] }
}
private actor SuspendedLifecyclePhotosAddedSyncer: ProjectPhotosAddedNotifying {
    let gate = LifecycleResponseGate<[String]>()
    func notifyProjectPhotosAdded(projectId: String, photoCount: Int) async throws -> [String] { await gate.hold() }
}
private actor SuspendedLifecycleProjectProbe: ProjectServerStateProbing {
    let gate = LifecycleResponseGate<Bool>()
    func isProjectVisible(projectId: String) async throws -> Bool { false }
    func projectServerState(projectId: String) async throws -> SyncOperationReconcilers.ProjectServerState? { _ = await gate.hold(); return .deleted }
    func waitUntilStarted() async { await gate.waitUntilStarted() }
    func finish() async { await gate.finish(true) }
}
private struct EmptyLifecycleMirrorReader: StrandedPortalMirrorReading {
    func serverProjectImages(projectIds: [String]) async throws -> [String: [String]] { [:] }
    func serverPhotoURLs(projectIds: [String]) async throws -> [String: Set<String>] { [:] }
}
private actor SuspendedLifecycleMirrorReader: StrandedPortalMirrorReading {
    private(set) var calls = 0
    let gate = LifecycleResponseGate<Bool>()
    func serverProjectImages(projectIds: [String]) async throws -> [String: [String]] { calls += 1; _ = await gate.hold(); return [:] }
    func serverPhotoURLs(projectIds: [String]) async throws -> [String: Set<String>] { [:] }
    func waitUntilStarted() async { await gate.waitUntilStarted() }
    func finish() async { await gate.finish(true) }
}
private struct SilentLifecycleReporter: PortalMirrorIncidentReporting {
    func reportPortalMirrorIncident(errorCode: String, summary: String, metadata: [String: Any]) async {}
}
