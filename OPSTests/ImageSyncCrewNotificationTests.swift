//
//  ImageSyncCrewNotificationTests.swift
//  OPSTests
//
//  The crew "photos added" rail must cross the narrow server RPC
//  (`notify_project_photos_added`), never a client-side `notifications` insert —
//  the 2026-07-15 notification-creation hardening revoked app-role INSERT, so
//  the old per-recipient insert loop 42501'd on every upload and the rail went
//  silently dead while the push still fired.
//
//  What these tests pin:
//    1. Exactly one server call per upload, carrying the project id and photo
//       count verbatim — no per-recipient fan-out on the client.
//    2. Nothing to announce (zero photos) never touches the server.
//    3. The SERVER decides recipients: an empty local crew list, or a crew list
//       containing only the uploader, must still cross the seam. The old code
//       short-circuited both locally, so a project whose crew was only known
//       server-side never notified anyone.
//    4. An empty server result (no new rail rows) completes cleanly — that is
//       the push-skip branch. The push is unreachable unless `created` is
//       non-empty, so rail and push can no longer disagree.
//    5. A throwing server call stays contained: best-effort notification must
//       never surface an error into the upload path.
//
//  OneSignal itself is a singleton with no injection seam, so the push is not
//  asserted directly — the branch is structural (guarded on a non-empty server
//  list). Where a test does drive the non-empty path, the returned id is the
//  stubbed `currentUserId`, which `OneSignalService.notifyPhotosAdded`
//  self-filters away before any network work — the suite stays hermetic.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class ImageSyncCrewNotificationTests: XCTestCase {

    // MARK: - Spy

    /// Records every server call and plays back a scripted result. The manager
    /// makes one call per notification, sequentially, so plain storage is
    /// race-free.
    private final class PhotosAddedSpy: ProjectPhotosAddedNotifying {
        struct Call: Equatable {
            let projectId: String
            let photoCount: Int
        }

        private(set) var calls: [Call] = []
        /// User ids the server reports as having received NEW rail rows.
        var created: [String] = []
        var failure: Error?

        func notifyProjectPhotosAdded(projectId: String, photoCount: Int) async throws -> [String] {
            calls.append(Call(projectId: projectId, photoCount: photoCount))
            if let failure = failure {
                throw failure
            }
            return created
        }
    }

    // MARK: - Fixture state

    private let operatorID = "operator-self"
    private let uploaderID = "uploader-1"

    /// Containers outlive the contexts they vend, for the whole test case. A
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData
    /// (uncatchable EXC_BREAKPOINT) — the test dies before its first assertion.
    private var retainedContainers: [ModelContainer] = []

    /// `OneSignalService.notifyPhotosAdded` drops recipients equal to the
    /// stored `currentUserId`; stubbing it keeps the push path inert in tests.
    private var savedCurrentUserId: String?

    override func setUp() {
        super.setUp()
        savedCurrentUserId = UserDefaults.standard.string(forKey: "currentUserId")
        UserDefaults.standard.set(operatorID, forKey: "currentUserId")
    }

    override func tearDown() {
        if let saved = savedCurrentUserId {
            UserDefaults.standard.set(saved, forKey: "currentUserId")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentUserId")
        }
        retainedContainers.removeAll()
        super.tearDown()
    }

    // MARK: - 1. Project id + count forwarded verbatim, once

    func test_notifyCrewForwardsProjectIdAndPhotoCountVerbatim() async throws {
        let context = try makeContext()
        let project = seedProject(
            id: "p-photos-1",
            title: "South deck rebuild",
            crew: [uploaderID, "crew-a", "crew-b"],
            in: context
        )
        seedUploader(in: context)

        let manager = makeManager(context: context)
        let spy = PhotosAddedSpy()
        // Server reports one new rail row; the id is the stubbed operator, so
        // OneSignal self-filters it and no push HTTP is attempted.
        spy.created = [operatorID]
        manager.photosAddedSyncer = spy

        let task = manager.notifyCrewOfAddedPhotos(
            project: project,
            uploaderId: uploaderID,
            photoCount: 3,
            firstURL: "https://ops-app.s3.amazonaws.com/photo-1.jpg"
        )
        XCTAssertNotNil(task, "a real upload must produce a notification task")
        await task?.value

        XCTAssertEqual(
            spy.calls,
            [.init(projectId: "p-photos-1", photoCount: 3)],
            "Exactly one server call, carrying the project id and count verbatim — three crew members must not become three client writes, and recipients + copy are the server's job"
        )
    }

    // MARK: - 2. Nothing to announce never reaches the server

    func test_zeroPhotoCountNeverCallsTheServer() async throws {
        let context = try makeContext()
        let project = seedProject(
            id: "p-photos-empty",
            title: "Fence line",
            crew: [uploaderID, "crew-a"],
            in: context
        )
        seedUploader(in: context)

        let manager = makeManager(context: context)
        let spy = PhotosAddedSpy()
        spy.created = [operatorID]
        manager.photosAddedSyncer = spy

        let task = manager.notifyCrewOfAddedPhotos(
            project: project,
            uploaderId: uploaderID,
            photoCount: 0,
            firstURL: nil
        )
        await task?.value

        XCTAssertNil(task, "Zero photos -> no notification task at all")
        XCTAssertTrue(spy.calls.isEmpty, "Zero photos -> nothing reported to the server")
    }

    // MARK: - 3. The server decides recipients, not the client

    func test_serverIsCalledEvenWhenLocalCrewIsEmptyOrUploaderOnly() async throws {
        let context = try makeContext()
        // No crew ids on the local row at all — the crew may exist only in the
        // server's copy of the project.
        let unknownCrew = seedProject(
            id: "p-crew-unknown",
            title: "Ridge cap",
            crew: [],
            in: context
        )
        // Crew is exactly the uploader — the old client-side filter emptied this
        // list and returned before writing anything.
        let uploaderOnly = seedProject(
            id: "p-crew-uploader-only",
            title: "Garage slab",
            crew: [uploaderID],
            in: context
        )
        seedUploader(in: context)

        let manager = makeManager(context: context)
        let spy = PhotosAddedSpy()
        manager.photosAddedSyncer = spy

        await manager.notifyCrewOfAddedPhotos(
            project: unknownCrew,
            uploaderId: uploaderID,
            photoCount: 1,
            firstURL: nil
        )?.value
        await manager.notifyCrewOfAddedPhotos(
            project: uploaderOnly,
            uploaderId: uploaderID,
            photoCount: 2,
            firstURL: nil
        )?.value

        XCTAssertEqual(
            spy.calls,
            [
                .init(projectId: "p-crew-unknown", photoCount: 1),
                .init(projectId: "p-crew-uploader-only", photoCount: 2),
            ],
            "The local crew list no longer gates the call — the server owns recipient derivation"
        )
    }

    // MARK: - 4. Empty server result — the push-skip branch

    func test_emptyServerRecipientListCompletesWithoutPush() async throws {
        let context = try makeContext()
        let project = seedProject(
            id: "p-photos-dedupe",
            title: "Back steps",
            crew: [uploaderID, "crew-a"],
            in: context
        )
        seedUploader(in: context)

        let manager = makeManager(context: context)
        let spy = PhotosAddedSpy()
        // No new rail rows: no crew to reach, or a repeat inside the server's
        // dedupe window. The push must not fire against a stale local list.
        spy.created = []
        manager.photosAddedSyncer = spy

        let task = manager.notifyCrewOfAddedPhotos(
            project: project,
            uploaderId: uploaderID,
            photoCount: 4,
            firstURL: "https://ops-app.s3.amazonaws.com/photo-4.jpg"
        )
        await task?.value

        XCTAssertEqual(
            spy.calls,
            [.init(projectId: "p-photos-dedupe", photoCount: 4)],
            "The server is still asked — it is the only thing that knows whether a row is new"
        )
        XCTAssertEqual(
            task?.isCancelled,
            false,
            "The empty-result path returns before the push and ends normally — no cancellation, no error escaping the upload"
        )
    }

    // MARK: - 5. Transport failure stays contained

    func test_throwingServerCallStaysContained() async throws {
        let context = try makeContext()
        let project = seedProject(
            id: "p-photos-offline",
            title: "Soffit repair",
            crew: [uploaderID, "crew-a"],
            in: context
        )
        seedUploader(in: context)

        let manager = makeManager(context: context)
        let spy = PhotosAddedSpy()
        spy.created = [operatorID]
        spy.failure = URLError(.notConnectedToInternet)
        manager.photosAddedSyncer = spy

        let task = manager.notifyCrewOfAddedPhotos(
            project: project,
            uploaderId: uploaderID,
            photoCount: 2,
            firstURL: nil
        )
        // A `Task<Void, Never>` cannot rethrow — awaiting it here proves the
        // failure was swallowed rather than surfaced into the upload path.
        await task?.value

        XCTAssertEqual(
            spy.calls,
            [.init(projectId: "p-photos-offline", photoCount: 2)],
            "The failing call was attempted exactly once — notification failure is best-effort, never retried into the upload"
        )
    }

    // MARK: - Fixture

    private func makeManager(context: ModelContext) -> ImageSyncManager {
        ImageSyncManager(modelContext: context, connectivity: ConnectivityManager())
    }

    @discardableResult
    private func seedProject(id: String, title: String, crew: [String], in context: ModelContext) -> Project {
        let project = Project(id: id, title: title, status: .inProgress)
        project.companyId = "co-photos"
        project.setTeamMemberIds(crew)
        context.insert(project)
        try? context.save()
        return project
    }

    /// The uploader's roster row — the display name it carries dresses the push
    /// copy, and seeding it exercises the `TeamMember` name lookup rather than
    /// leaving it on the "A teammate" fallback.
    @discardableResult
    private func seedUploader(in context: ModelContext) -> TeamMember {
        let member = TeamMember(
            id: uploaderID,
            firstName: "Marcus",
            lastName: "Hale",
            role: "Crew"
        )
        context.insert(member)
        try? context.save()
        return member
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            ProjectPhoto.self,
            SyncOperation.self,
            Company.self,
            TeamMember.self,
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return ModelContext(container)
    }
}
