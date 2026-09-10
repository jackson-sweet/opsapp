import XCTest
import SwiftData
import UIKit
@testable import OPS

@MainActor
final class StagedPhotoDestinationsTests: XCTestCase {
    private var container: ModelContainer!
    private let companyID = "company-a"
    private let userID = "user-a"

    private func context() throws -> ModelContext {
        let schema = Schema([Project.self, ProjectTask.self, TaskType.self, TaskTypeReminder.self,
            TaskReminder.self, User.self, Client.self, SubClient.self, ProjectNote.self, ProjectPhoto.self,
            SyncOperation.self, ProjectVinylOrderMarker.self, ProjectPrimaryContactSelection.self, Opportunity.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func project(in context: ModelContext) throws -> Project {
        let project = Project(id: UUID().uuidString.lowercased(), title: "Test roof", status: .rfq)
        project.companyId = companyID
        context.insert(project)
        try context.save()
        return project
    }

    private func batch(for project: Project, kind: String = "project") -> StagedCaptureBatch {
        let id = UUID().uuidString.lowercased()
        return StagedCaptureBatch(id: UUID().uuidString.lowercased(), owner: StagedPhotoDestinations.owner(companyID: companyID, userID: userID, kind: kind, id: project.id),
            items: [.init(id: id, localURL: "local://project_images/capture_\(id).jpg", originalLocalURL: "local://project_images/capture_\(id).original", capturedAt: Date(), pixelWidth: 80, pixelHeight: 40)])
    }

    private func persist(_ deliveries: [StagedPhotoDestinations.ProjectDelivery], context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let account = CaptureAccountIdentity(companyID: companyID, userID: userID)
        try StagedPhotoDestinations.persistProjectDeliveries(deliveries, context: context, account: account, currentAccount: { account }, save: save)
    }

    private func accept(_ batch: StagedCaptureBatch, project: Project, context: ModelContext, activeUser: String = "user-a") async -> Bool {
        await StagedPhotoDestinations.acceptProject(batch, project: project, userID: userID, context: context,
            imageSyncManager: nil, activeUserID: { activeUser }, activeCompanyID: { self.companyID })
    }

    func testProjectReceiptPersistsStableRowsWithoutImageDecodeAndReplayDoesNotDuplicate() async throws {
        let context = try context()
        let project = try project(in: context)
        let batch = batch(for: project)
        let wrongAccount = await accept(batch, project: project, context: context, activeUser: "user-b")
        XCTAssertFalse(wrongAccount)
        let accepted = await accept(batch, project: project, context: context)
        XCTAssertTrue(accepted)
        let replayed = await accept(batch, project: project, context: context)
        XCTAssertTrue(replayed)
        let reopened = ModelContext(container)
        let rows = try reopened.fetch(FetchDescriptor<ProjectPhoto>())
        XCTAssertEqual(rows.map(\.id), batch.items.map(\.id))
        XCTAssertEqual(rows.first?.url, batch.items[0].localURL)
        XCTAssertEqual(rows.first?.uploadedBy, userID)
        XCTAssertEqual(rows.first?.needsSync, true)
        let savedProject = try XCTUnwrap(reopened.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(savedProject.getProjectImages(), batch.items.map(\.localURL))
        // No file exists at these references: the destination transfer is metadata only.
        XCTAssertTrue(try StagedPhotoDestinations.unclaimedDraftItems(batch, context: context).isEmpty)
    }

    func testDraftParentRequiresDurableCreateAndUsesSameReservedID() async throws {
        let context = try context()
        let project = try project(in: context)
        let batch = batch(for: project, kind: "project-draft")
        let withoutParentReceipt = await accept(batch, project: project, context: context)
        XCTAssertFalse(withoutParentReceipt)
        let json: [String: Any] = ["id": project.id, "company_id": companyID, "title": project.title, "status": "rfq"]
        let dto = try JSONDecoder().decode(SupabaseProjectDTO.self, from: JSONSerialization.data(withJSONObject: json))
        let first = try StagedPhotoDestinations.ensureParentCreate(project: project, dto: dto, context: context)
        let replay = try StagedPhotoDestinations.ensureParentCreate(project: project, dto: dto, context: context)
        XCTAssertEqual(first.id, replay.id)
        try context.save()
        let accepted = await accept(batch, project: project, context: context)
        XCTAssertTrue(accepted)
        let operations = try ModelContext(container).fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.entityId, project.id)
        XCTAssertEqual(operations.first?.operationType, "create")
    }

    func testProjectHealingFailureLeavesPersistedLocalURLAndUnrelatedUnsavedEdit() async throws {
        let context = try context()
        let project = try project(in: context)
        let batch = batch(for: project)
        let accepted = await accept(batch, project: project, context: context)
        XCTAssertTrue(accepted)
        project.notes = "Unrelated draft edit"
        let item = batch.items[0]
        let delivery = StagedPhotoDestinations.ProjectDelivery(id: item.id, projectID: project.id, companyID: companyID,
            uploadedBy: userID, localURL: item.localURL, remoteURL: "https://example.test/canonical.jpg")
        XCTAssertThrowsError(try persist([delivery], context: context, save: { _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProjectPhoto>()).first?.url, item.localURL)
        XCTAssertEqual(project.notes, "Unrelated draft edit")
        try persist([delivery], context: context)
        let row = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ProjectPhoto>()).first)
        XCTAssertEqual(row.url, delivery.remoteURL)
        XCTAssertFalse(row.needsSync)
        XCTAssertNotNil(row.lastSyncedAt)
    }

    func testCanonicalReceiptMustMatchPhotoDestinationAndUploader() throws {
        let row = ProjectPhoto(id: "photo-a", projectId: "project-a", companyId: companyID, url: "local://photo", uploadedBy: userID)
        func receipt(_ company: String = "company-a", _ user: String = "user-a", _ deleted: String? = nil) -> ProjectPhotoDTO {
            ProjectPhotoDTO(id: "photo-a", projectId: "project-a", companyId: company, url: "https://example.test/canonical.jpg",
                thumbnailURL: nil, renderedURL: nil, source: nil, siteVisitId: nil, taskId: nil, uploadedBy: user, caption: nil,
                isClientVisible: nil, takenAt: nil, createdAt: nil, updatedAt: nil, deletedAt: deleted)
        }
        XCTAssertNil(StagedPhotoDestinations.canonicalCaptureURL(for: row, receipts: [receipt("foreign")]))
        XCTAssertNil(StagedPhotoDestinations.canonicalCaptureURL(for: row, receipts: [receipt("company-a", "foreign")]))
        XCTAssertNil(StagedPhotoDestinations.canonicalCaptureURL(for: row, receipts: [receipt("company-a", "user-a", "deleted")]))
        XCTAssertEqual(StagedPhotoDestinations.canonicalCaptureURL(for: row, receipts: [receipt()]), "https://example.test/canonical.jpg")
    }

    func testReopenRetiresOriginalOnlyAfterPersistedRemoteRow() async throws {
        let context = try context()
        let project = try project(in: context)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DurableCaptureStore(root: root.appendingPathComponent("Journal"), images: root.appendingPathComponent("Images"))
        let owner = StagedPhotoDestinations.owner(companyID: companyID, userID: userID, kind: "project", id: project.id)
        let account = CaptureAccountIdentity(companyID: companyID, userID: userID)
        var batch = try await store.create(owner: owner)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).pngData { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 40)) }
        let item = try await store.stage(data: data, batchID: batch.id)
        batch.items = [item]
        let accepted = await accept(batch, project: project, context: context)
        XCTAssertTrue(accepted)
        try await store.acknowledge(batchID: batch.id, itemIDs: [item.id])
        try await StagedPhotoDestinations.retireDeliveredProjectCaptures(owner: owner, projectID: project.id, context: context, store: store, currentAccount: { account })
        let before = await store.originalData(for: item)
        XCTAssertEqual(before, data)
        try persist([.init(id: item.id, projectID: project.id, companyID: companyID,
            uploadedBy: userID, localURL: item.localURL, remoteURL: "https://example.test/delivered.jpg")], context: context)
        try await StagedPhotoDestinations.retireDeliveredProjectCaptures(owner: owner, projectID: project.id, context: context, store: store, currentAccount: { account })
        let after = await store.originalData(for: item)
        XCTAssertNil(after)
    }

    func testLeadDeliveryCannotRetireOnFailedLocalHealingOrWrongOwner() throws {
        let context = try context()
        let opportunity = Opportunity(id: "lead-a", companyId: companyID, contactName: "Test")
        context.insert(opportunity)
        try context.save()
        let remote = "https://example.test/lead.jpg"
        let payload: [String: Any] = ["id": "lead-a", "company_id": companyID, "stage": "new", "stage_entered_at": "2026-09-06T00:00:00Z",
            "created_at": "2026-09-06T00:00:00Z", "updated_at": "2026-09-06T00:00:00Z", "assignment_version": 0, "images": [remote]]
        let dto = try JSONDecoder().decode(OpportunityDTO.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertThrowsError(try StagedPhotoDestinations.persistLeadDelivery(dto, opportunityID: "lead-a", companyID: "foreign", remoteURL: remote, context: context))
        XCTAssertThrowsError(try StagedPhotoDestinations.persistLeadDelivery(dto, opportunityID: "lead-a", companyID: companyID, remoteURL: remote, context: context, save: { _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Opportunity>()).first?.images, [])
        try StagedPhotoDestinations.persistLeadDelivery(dto, opportunityID: "lead-a", companyID: companyID, remoteURL: remote, context: context)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Opportunity>()).first?.images, [remote])
    }

    func testFormRecoveryPreservesValidPreviewAndFailedSiblingThroughTransfer() async throws {
        let context = try context()
        let project = try project(in: context)
        project.lastSyncedAt = Date()
        try context.save()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DurableCaptureStore(root: root.appendingPathComponent("Journal"), images: root.appendingPathComponent("Images"))
        var draft = ProjectPhotoFormDraft(id: UUID().uuidString.lowercased(), projectID: project.id, companyID: companyID, userID: userID,
            fields: .init(title: "Roof", titleIsAuto: false, clientID: nil, address: "", description: "", notes: "", status: "rfq", startDate: nil, endDate: nil), batchIDs: [], updatedAt: Date())
        let batch = try await store.create(owner: draft.owner)
        draft.batchIDs = [batch.id]
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).pngData { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 40)) }
        let good = try await store.stage(data: data, batchID: batch.id)
        let badID = UUID().uuidString.lowercased()
        do { _ = try await store.stage(data: Data("bad-original".utf8), batchID: batch.id, itemID: badID); XCTFail("Expected decode failure") } catch {}
        // This is the same retained-draft loader used by form reopen AND transfer.
        let reopened = try await StagedPhotoDestinations.loadDraftCaptures(draft, store: store)
        let result = try XCTUnwrap(reopened.first)
        XCTAssertEqual(result.batch.items, [good])
        XCTAssertEqual(result.failedItems.map(\.id), [badID])
        let preview = await store.thumbnail(for: good)
        XCTAssertNotNil(preview)
        let accepted = await accept(result.batch, project: project, context: context)
        XCTAssertTrue(accepted)
        try await store.acknowledge(batchID: batch.id, itemIDs: [good.id])
        let retried = try await StagedPhotoDestinations.loadDraftCaptures(draft, store: store)
        XCTAssertEqual(retried.first?.batch.items.map(\.id), [good.id])
        XCTAssertEqual(retried.first?.failedItems.map(\.id), [badID])
        let original = await store.originalData(for: good)
        let failedOriginal = await store.originalData(for: result.failedItems[0])
        XCTAssertEqual(original, data)
        XCTAssertEqual(failedOriginal, Data("bad-original".utf8))
    }

    func testAccountSwitchDuringSuspendedReadCannotHealOrRetireOriginalAccountCapture() async throws {
        let context = try context()
        let project = try project(in: context)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = CaptureAccountIdentity(companyID: companyID, userID: userID)
        let current = CaptureAccountTestState(account)
        let store = DurableCaptureStore(root: root.appendingPathComponent("Journal"), images: root.appendingPathComponent("Images"), currentAccount: { current.get() })
        let owner = StagedPhotoDestinations.owner(companyID: companyID, userID: userID, kind: "project", id: project.id)
        var batch = try await store.create(owner: owner)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).pngData { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 40)) }
        let item = try await store.stage(data: data, batchID: batch.id)
        batch.items = [item]
        let accepted = await accept(batch, project: project, context: context)
        XCTAssertTrue(accepted)
        let delivery = StagedPhotoDestinations.ProjectDelivery(id: item.id, projectID: project.id, companyID: companyID,
            uploadedBy: userID, localURL: item.localURL, remoteURL: "https://example.test/canonical.jpg")
        current.set(.init(companyID: "company-b", userID: "user-b"))
        XCTAssertThrowsError(try StagedPhotoDestinations.persistProjectDeliveries([delivery], context: context, account: account, currentAccount: { current.get() }))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProjectPhoto>()).first?.url, item.localURL)
        do { try await store.recordDelivered(localURLs: [item.localURL], account: account); XCTFail("Actor must revalidate before deleting") } catch {}
        current.set(account)
        try persist([delivery], context: context)
        let gate = CaptureReadTestGate()
        let retirement = Task {
            try await StagedPhotoDestinations.retireDeliveredProjectCaptures(owner: owner, projectID: project.id, context: context,
                store: store, currentAccount: { current.get() }, readBatches: { owner in
                    let batches = try await store.retainedBatches(owner: owner)
                    await gate.hold()
                    return batches
                })
        }
        await gate.waitUntilHeld()
        current.set(.init(companyID: "company-b", userID: "user-b"))
        await gate.release()
        do { try await retirement.value; XCTFail("A suspended read cannot resume in another account") } catch {}
        let retained = await store.originalData(for: item)
        XCTAssertEqual(retained, data)
        let pending = try await store.retainedBatches(owner: owner)
        XCTAssertEqual(pending.flatMap(\.items).map(\.id), [item.id])
        current.set(account)
        try await StagedPhotoDestinations.retireDeliveredProjectCaptures(owner: owner, projectID: project.id, context: context, store: store, currentAccount: { current.get() })
        let retired = await store.originalData(for: item)
        XCTAssertNil(retired)
    }
}

private final class CaptureAccountTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CaptureAccountIdentity
    init(_ value: CaptureAccountIdentity) { self.value = value }
    func get() -> CaptureAccountIdentity { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: CaptureAccountIdentity) { lock.lock(); defer { lock.unlock() }; self.value = value }
}

private actor CaptureReadTestGate {
    private var held = false
    private var onHeld: CheckedContinuation<Void, Never>?
    private var onRelease: CheckedContinuation<Void, Never>?
    func hold() async {
        await withCheckedContinuation { continuation in
            onRelease = continuation
            held = true
            onHeld?.resume(); onHeld = nil
        }
    }
    func waitUntilHeld() async {
        if held { return }
        await withCheckedContinuation { onHeld = $0 }
    }
    func release() { onRelease?.resume(); onRelease = nil }
}
