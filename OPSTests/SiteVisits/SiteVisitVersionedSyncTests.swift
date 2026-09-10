import XCTest
import SwiftData
@testable import OPS

final class SiteVisitVersionedSyncTests: XCTestCase {
    @MainActor
    func testAcknowledgementPreservesEditCommittedByAnotherContext() throws {
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let outbound = ModelContext(container)
        let type = SiteVisitType(companyId: "company", slug: "scope", name: "Sent name")
        type.id = type.id.uppercased() // A persisted template created by an older client.
        type.writeState = .init(revision: 4)
        outbound.insert(type)
        let command = try SiteVisitWriteModels.command([type])
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitType.rawValue, entityId: type.id,
            operationType: "siteVisitWrite", payload: try JSONEncoder().encode(command), changedFields: ["name"])
        operation.siteVisitWriteActorId = "actor"
        operation.siteVisitWriteAttemptedAt = Date()
        outbound.insert(operation); try outbound.save()
        let editor = ModelContext(container)
        let edited = try XCTUnwrap(editor.fetch(FetchDescriptor<SiteVisitType>()).first)
        edited.name = "Newer edit while request was in flight"
        edited.needsSync = true
        try editor.save()
        guard case .object(var values) = command.rows[0].values else { return XCTFail("Expected object") }
        values["write_revision"] = .number(5)
        let receipt = SiteVisitWriteReceipt(commandId: operation.id, entity: "template", outcome: "saved", reason: nil, rows: [.object(values)])
        try SiteVisitVersionedSync.applyReceipt(receipt, to: operation, command: command, resolutionData: nil,
            context: outbound, companyId: "company", actorId: "actor")
        try outbound.save()
        let verifier = ModelContext(container)
        let preserved = try XCTUnwrap(verifier.fetch(FetchDescriptor<SiteVisitType>()).first)
        XCTAssertEqual(preserved.name, "Newer edit while request was in flight")
        XCTAssertTrue(preserved.needsSync)
        XCTAssertEqual(preserved.writeState.baseRevision, 4)
        XCTAssertEqual(preserved.writeState.remoteRow?["write_revision"], .number(5))
        XCTAssertNotNil(try verifier.fetch(FetchDescriptor<SyncOperation>()).first(where: { $0.id == operation.id })?.siteVisitWriteReceiptData)
    }

    @MainActor
    func testExactAcknowledgementUpdatesRegisteredUnattemptedDescendant() throws {
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let outbound = ModelContext(container)
        let type = SiteVisitType(companyId: "company", slug: "scope", name: "Sent name")
        type.writeState = .init(revision: 4)
        outbound.insert(type)
        let command = try SiteVisitWriteModels.command([type])
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitType.rawValue, entityId: type.id,
            operationType: "siteVisitWrite", payload: try JSONEncoder().encode(command), changedFields: ["name"])
        operation.siteVisitWriteActorId = "actor"
        operation.siteVisitWriteAttemptedAt = Date()
        outbound.insert(operation); try outbound.save()
        let descendant = SyncOperation(entityType: SyncEntityType.siteVisitType.rawValue, entityId: type.id,
            operationType: "siteVisitWrite", payload: try JSONEncoder().encode(command), changedFields: ["name"],
            dependsOnId: operation.id.uuidString.lowercased())
        descendant.siteVisitWriteActorId = "actor"
        outbound.insert(descendant); try outbound.save()
        let editor = ModelContext(container)
        let edited = try XCTUnwrap(editor.fetch(FetchDescriptor<SiteVisitType>()).first)
        edited.name = "Newer edit while request was in flight"
        edited.needsSync = true
        try editor.save()
        guard case .object(var values) = command.rows[0].values else { return XCTFail("Expected object") }
        values["write_revision"] = .number(5)
        let receipt = SiteVisitWriteReceipt(commandId: operation.id, entity: "template", outcome: "saved", reason: nil, rows: [.object(values)])
        try SiteVisitVersionedSync.applyReceipt(receipt, to: operation, command: command, resolutionData: nil,
            context: outbound, companyId: "company", actorId: "actor")
        try outbound.save()
        let verifier = ModelContext(container)
        let preserved = try XCTUnwrap(verifier.fetch(FetchDescriptor<SiteVisitType>()).first)
        XCTAssertEqual(preserved.name, "Newer edit while request was in flight")
        XCTAssertTrue(preserved.needsSync)
        XCTAssertEqual(preserved.writeState.baseRevision, 5)
        XCTAssertEqual(SiteVisitVersionedSync.command(descendant)?.rows[0].baseRevision, 5)
        XCTAssertNil(descendant.siteVisitWriteAttemptedAt)
        XCTAssertEqual(preserved.writeState.remoteRow?["write_revision"], .number(5))
        XCTAssertNotNil(try verifier.fetch(FetchDescriptor<SyncOperation>()).first(where: { $0.id == operation.id })?.siteVisitWriteReceiptData)
    }

    @MainActor
    func testInboundLowercaseReceiptFindsLegacyTemplateWithoutDuplicateOrOverwrite() throws {
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let type = SiteVisitType(companyId: "company", slug: "scope", name: "My pending version")
        type.id = type.id.uppercased()
        type.writeState = .init(revision: 4)
        context.insert(type)
        type.beginVersionedEdit()
        try context.save()
        var dto = SiteVisitTypeDTO(id: type.id.lowercased(), companyId: "company", slug: "scope", name: "Server version",
            descriptionText: nil, isSystemTemplate: false, isDefault: false, sortOrder: 0, fields: [],
            createdAt: nil, updatedAt: nil, deletedAt: nil)
        dto.writeRevision = 5
        XCTAssertTrue(try SiteVisitTypeServerMerge.merge(dto: dto, accepting: SiteVisitTypeServerMerge.mutableFields,
            hasPendingLocalOperation: false, context: context))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<SiteVisitType>()).count, 1)
        XCTAssertEqual(type.name, "My pending version")
        XCTAssertEqual(type.writeState.baseRevision, 4)
        XCTAssertEqual(type.writeState.remoteRow?["write_revision"], .number(5))
    }

    @MainActor
    func testOldResponseCannotCrossNewResolutionOrActorBinding() throws {
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let outbound = ModelContext(container)
        let type = SiteVisitType(companyId: "company", slug: "scope", name: "Sent name")
        outbound.insert(type)
        let command = try SiteVisitWriteModels.command([type])
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitType.rawValue, entityId: type.id,
            operationType: "siteVisitWrite", payload: try JSONEncoder().encode(command), changedFields: ["name"])
        operation.siteVisitWriteActorId = "actor"
        outbound.insert(operation); try outbound.save()
        let editor = ModelContext(container)
        let latest = try XCTUnwrap(editor.fetch(FetchDescriptor<SyncOperation>()).first)
        let choice = try JSONEncoder().encode(SiteVisitWriteResolution(id: UUID(), choice: "current", current: []))
        latest.siteVisitWriteResolutionData = choice
        try editor.save()
        let receipt = SiteVisitWriteReceipt(commandId: operation.id, entity: "template", outcome: "conflict", reason: "stale", rows: [])
        XCTAssertThrowsError(try SiteVisitVersionedSync.applyReceipt(receipt, to: operation, command: command, resolutionData: nil,
            context: outbound, companyId: "company", actorId: "actor"))
        latest.siteVisitWriteResolutionData = nil
        latest.siteVisitWriteActorId = "different-actor"
        try editor.save()
        XCTAssertThrowsError(try SiteVisitVersionedSync.applyReceipt(receipt, to: operation, command: command, resolutionData: nil,
            context: outbound, companyId: "company", actorId: "actor"))
        XCTAssertNil(latest.siteVisitWriteReceiptData)
    }
}
