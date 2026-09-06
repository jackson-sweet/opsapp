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
        XCTAssertThrowsError(try StagedPhotoDestinations.persistProjectDeliveries([delivery], context: context, save: { _ in throw CocoaError(.fileWriteOutOfSpace) }))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<ProjectPhoto>()).first?.url, item.localURL)
        XCTAssertEqual(project.notes, "Unrelated draft edit")
        try StagedPhotoDestinations.persistProjectDeliveries([delivery], context: context)
        let row = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<ProjectPhoto>()).first)
        XCTAssertEqual(row.url, delivery.remoteURL)
        XCTAssertFalse(row.needsSync)
        XCTAssertNotNil(row.lastSyncedAt)
    }

    func testCanonicalReceiptMustMatchPhotoDestinationAndUploader() throws {
        let row = ProjectPhoto(id: "photo-a", projectId: "project-a", companyId: companyID, url: "local://photo", uploadedBy: userID)
        func receipt(_ company: String = "company-a", _ user: String = "user-a", _ deleted: String? = nil) -> ProjectPhotoDTO {
            ProjectPhotoDTO(id: "photo-a", projectId: "project-a", companyId: company, url: "https://example.test/canonical.jpg",
                thumbnailURL: nil, renderedURL: nil, source: nil, siteVisitId: nil, uploadedBy: user, caption: nil,
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
        var batch = try await store.create(owner: owner)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).pngData { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 40)) }
        let item = try await store.stage(data: data, batchID: batch.id)
        batch.items = [item]
        let accepted = await accept(batch, project: project, context: context)
        XCTAssertTrue(accepted)
        try await store.acknowledge(batchID: batch.id, itemIDs: [item.id])
        try await StagedPhotoDestinations.retireDeliveredProjectCaptures(owner: owner, projectID: project.id, context: context, store: store)
        let before = await store.originalData(for: item)
        XCTAssertEqual(before, data)
        try StagedPhotoDestinations.persistProjectDeliveries([.init(id: item.id, projectID: project.id, companyID: companyID,
            uploadedBy: userID, localURL: item.localURL, remoteURL: "https://example.test/delivered.jpg")], context: context)
        try await StagedPhotoDestinations.retireDeliveredProjectCaptures(owner: owner, projectID: project.id, context: context, store: store)
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
}
