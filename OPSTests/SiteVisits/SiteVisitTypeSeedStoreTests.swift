import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitTypeSeedStoreTests: XCTestCase {
    private var containers: [ModelContainer] = []
    override func tearDown() { containers.removeAll(); super.tearDown() }

    func test_entrySeedingKeepsOtherVisitPendingOnSuccessFailureAndNoOp() throws {
        for fail in [false, true] {
            let context = try makeContext()
            let visit = SiteVisit(companyId: "company", createdBy: "actor")
            visit.notes = "Stored note"
            context.insert(visit); try context.save()
            visit.notes = "Unfinished note"
            let draft = SiteVisitIdentityDraft(siteVisitId: visit.id, companyId: "company", notes: "Unfinished draft")
            context.insert(draft)
            do {
                let result = try SiteVisitTypeSeedStore.seed(from: context, companyId: "company",
                    deckBuilderEnabled: true, canManageTemplates: true,
                    validateCommit: { if fail { throw URLError(.cannotWriteToFile) } })
                XCTAssertFalse(fail)
                XCTAssertTrue(result.didChange)
                XCTAssertTrue(result.queuedWork)
            } catch { XCTAssertTrue(fail) }
            XCTAssertEqual(visit.notes, "Unfinished note")
            XCTAssertEqual(draft.notes, "Unfinished draft")
            XCTAssertTrue(context.hasChanges)
            let fresh = ModelContext(context.container)
            XCTAssertEqual(try fresh.fetch(FetchDescriptor<SiteVisit>()).first?.notes, "Stored note")
            XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<SiteVisitIdentityDraft>()), 0)
            let types = try fresh.fetch(FetchDescriptor<SiteVisitType>())
            let operations = try fresh.fetch(FetchDescriptor<SyncOperation>())
            XCTAssertEqual(types.isEmpty, fail)
            XCTAssertEqual(operations.isEmpty, fail)
            if !fail {
                for type in types { type.lastSyncedAt = Date(); type.needsSync = false }
                for operation in operations { operation.status = "completed" }
                try fresh.save()
                let noOp = try SiteVisitTypeSeedStore.seed(from: context, companyId: "company",
                    deckBuilderEnabled: true, canManageTemplates: true,
                    validateCommit: { XCTFail("No-op entry must not save") })
                XCTAssertFalse(noOp.didChange)
                XCTAssertFalse(noOp.queuedWork)
                XCTAssertEqual(visit.notes, "Unfinished note")
                XCTAssertTrue(context.hasChanges)
            }
        }
    }

    func test_permissionsAndStoppedTemplateOwnersArePreserved() throws {
        let context = try makeContext()
        _ = try SiteVisitTypeSeedStore.seed(from: context, companyId: "company",
            deckBuilderEnabled: false, canManageTemplates: false)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SyncOperation>()), 0)
        _ = try SiteVisitTypeSeedStore.seed(from: context, companyId: "company",
            deckBuilderEnabled: false, canManageTemplates: true)
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertFalse(operations.isEmpty)
        for operation in operations { operation.status = "declined"; operation.retryCount = 4 }
        try context.save()
        let result = try SiteVisitTypeSeedStore.seed(from: context, companyId: "company",
            deckBuilderEnabled: false, canManageTemplates: true)
        XCTAssertFalse(result.queuedWork)
        let fresh = try ModelContext(context.container).fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(fresh.count, operations.count)
        XCTAssertTrue(fresh.allSatisfy { $0.status == "declined" && $0.retryCount == 4 })
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([SiteVisit.self, SiteVisitIdentityDraft.self, SiteVisitType.self, SyncOperation.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        containers.append(container)
        return container.mainContext
    }
}
