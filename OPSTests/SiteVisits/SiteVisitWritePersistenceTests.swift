import XCTest
import SwiftData
@testable import OPS

final class SiteVisitWritePersistenceTests: XCTestCase {
    @MainActor
    func testOriginalBaseAndResolutionSurviveDiskReopenAndAnotherContext() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([SiteVisitType.self, SiteVisitChecklistAnswer.self, SyncOperation.self])
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("phone.store"))
        let operationID: UUID
        let command: SiteVisitWriteCommand
        let resolution = SiteVisitWriteResolution(id: UUID(), choice: "current", current: [.object(["write_revision": .number(9)])])
        do {
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)
            let answer = SiteVisitChecklistAnswer(siteVisitId: "visit", companyId: "company", opportunityId: nil,
                siteVisitTypeId: nil, fieldId: "measurement", label: "Measurement", kind: .measurement,
                required: false, sortOrder: 1, answerValue: .text("original"))
            answer.writeState = .init(revision: 4)
            context.insert(answer)
            answer.answerValue = .text("pending")
            command = SiteVisitWriteModels.command(answer)
            XCTAssertEqual(command.rows[0].baseRevision, 4)
            XCTAssertEqual(command.rows[0].before["answer_value"]?["text"], .string("original"))
            let operation = SyncOperation(entityType: "siteVisitChecklistAnswer", entityId: answer.id,
                operationType: "siteVisitWrite", payload: try JSONEncoder().encode(command), changedFields: ["answer_value"])
            operationID = operation.id
            operation.siteVisitWriteActorId = "actor-a"
            operation.siteVisitWriteAttemptedAt = Date(timeIntervalSince1970: 1_000)
            operation.siteVisitWriteResolutionData = try JSONEncoder().encode(resolution)
            context.insert(operation)
            try context.save()
            let second = ModelContext(container)
            let independentlyRead = try XCTUnwrap(second.fetch(FetchDescriptor<SyncOperation>()).first)
            XCTAssertEqual(independentlyRead.siteVisitWriteActorId, "actor-a")
            XCTAssertEqual(independentlyRead.siteVisitWriteResolutionData, operation.siteVisitWriteResolutionData)
        }
        let reopened = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(reopened)
        let operation = try XCTUnwrap(context.fetch(FetchDescriptor<SyncOperation>()).first)
        XCTAssertEqual(operation.id, operationID)
        XCTAssertEqual(try JSONDecoder().decode(SiteVisitWriteCommand.self, from: operation.payload), command)
        XCTAssertEqual(try JSONDecoder().decode(SiteVisitWriteResolution.self, from: XCTUnwrap(operation.siteVisitWriteResolutionData)), resolution)
        XCTAssertEqual(operation.siteVisitWriteAttemptedAt, Date(timeIntervalSince1970: 1_000))
        let answer = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).first)
        answer.answerValue = .text("newer local value")
        XCTAssertEqual(answer.writeState.baseRevision, 4)
        XCTAssertEqual(answer.writeState.baseRow?["answer_value"]?["text"], .string("original"))
        XCTAssertEqual(try JSONDecoder().decode(SiteVisitWriteCommand.self, from: operation.payload), command)
    }

    @MainActor
    func testTemplateDraftFreezesBaseBeforeRemoteMutation() {
        let type = SiteVisitType(companyId: "company", slug: "scope", name: "Original")
        type.writeState = .init(revision: 2)
        let draft = SiteVisitTypeDraft(type: type)
        type.name = "Server changed"
        type.writeState = .init(revision: 3)
        XCTAssertEqual(draft.originalWriteState?.baseRevision, 2)
        XCTAssertEqual(draft.originalWriteState?.baseRow?["name"], .string("Original"))
    }

    @MainActor
    func testPendingDeletionKeepsOriginalTimestampAcrossRebuild() {
        let type = SiteVisitType(companyId: "company", slug: "scope", name: "Original")
        type.writeState = .init(revision: 2)
        type.beginVersionedEdit()
        let timestamp = Date(timeIntervalSince1970: 100)
        type.deletedAt = timestamp
        let command = try! SiteVisitWriteModels.command([type])
        type.writeState.remoteRow = .object(["write_revision": .number(3)])
        let replay = try! SiteVisitWriteModels.command([type])
        XCTAssertEqual(command, replay)
        XCTAssertEqual(replay.rows[0].before["deleted_at"], .null)
        XCTAssertEqual(replay.rows[0].values["deleted_at"], .string(SupabaseDate.format(timestamp)))
    }
}
