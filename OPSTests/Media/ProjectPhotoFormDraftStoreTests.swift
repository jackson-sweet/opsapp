import XCTest
@testable import OPS

final class ProjectPhotoFormDraftStoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func draft() -> ProjectPhotoFormDraft {
        ProjectPhotoFormDraft(id: UUID().uuidString.lowercased(), projectID: UUID().uuidString.lowercased(), companyID: "company-a", userID: "user-a",
            fields: .init(title: "Roof", titleIsAuto: false, clientID: "client-a", address: "10 Test Street", description: "", notes: "Gate code", status: "rfq", startDate: nil, endDate: nil),
            batchIDs: [UUID().uuidString.lowercased()], updatedAt: Date())
    }

    func testReopenKeepsReservedProjectAndExactAccountAndRejectsOlderFieldSave() async throws {
        let store = ProjectPhotoFormDraftStore(root: root)
        let first = draft()
        try await store.save(first)
        var updated = first
        updated.fields.title = "New name"
        updated.updatedAt = first.updatedAt.addingTimeInterval(1)
        try await store.save(updated)
        try await store.save(first)
        let reopened = ProjectPhotoFormDraftStore(root: root)
        let recovered = try await reopened.pending(companyID: "COMPANY-A", userID: "USER-A")
        XCTAssertEqual(recovered, [updated])
        XCTAssertEqual(recovered.first?.owner.contextID, "project-draft:\(first.projectID)")
        let foreign = try await reopened.pending(companyID: "company-a", userID: "user-b")
        XCTAssertTrue(foreign.isEmpty)
    }

    func testCompletedDraftCannotBeRecreatedByDelayedSaveOrInterruptedRemoval() async throws {
        let store = ProjectPhotoFormDraftStore(root: root)
        let value = draft()
        try await store.save(value)
        try await store.remove(value)
        do { try await store.save(value); XCTFail("A completed draft cannot be resurrected") }
        catch CaptureStagingError.closedDraft {} catch { XCTFail("Unexpected error: \(error)") }
        // Simulate interruption after the completion marker but before unlink.
        let oldFile = root.appendingPathComponent(value.id).appendingPathExtension("json")
        try JSONEncoder().encode(value).write(to: oldFile)
        let reopened = try await ProjectPhotoFormDraftStore(root: root).pending(companyID: value.companyID, userID: value.userID)
        XCTAssertTrue(reopened.isEmpty)
    }

    func testUnreadableDraftIsNotOverwrittenOrReportedAsEmpty() async throws {
        let store = ProjectPhotoFormDraftStore(root: root)
        let value = draft()
        let url = root.appendingPathComponent(value.id).appendingPathExtension("json")
        let corrupt = Data("invalid-json".utf8)
        try corrupt.write(to: url)
        do { _ = try await store.pending(companyID: value.companyID, userID: value.userID); XCTFail("Expected read failure") } catch {}
        do { try await store.save(value); XCTFail("Cannot replace unreadable custody") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }
}
