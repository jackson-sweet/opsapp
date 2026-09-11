import SwiftData
import XCTest
@testable import OPS

@MainActor
final class DataActorSuspensionTransactionTests: XCTestCase {
    func testRealRelationshipSaveStopsBetweenBoundedChunksAndResumesWithoutLosingLinks() async throws {
        let schema = Schema(OPSSchemaCurrent.models)
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let user = User(id: "suspension-crew", firstName: "Crew", lastName: "Member", role: .crew, companyId: "suspension-company")
        container.mainContext.insert(user)
        for index in 0..<70 {
            let project = Project(id: "suspension-project-\(index)", title: "Suspension fixture", status: .inProgress)
            project.companyId = "suspension-company"
            project.teamMemberIdsString = user.id
            container.mainContext.insert(project)
        }
        try container.mainContext.save()
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let scope = SyncExecutionScope()

        do {
            try await SyncExecutionContext.$scope.withValue(scope) {
                try await actor.rewireExpiringAfterFirstSave(scope)
            }
            XCTFail("Expired relationship pass reported completion")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(scope.isDrained)
        let interruptedContext = ModelContext(container)
        let interrupted = try interruptedContext.fetch(FetchDescriptor<Project>())
        let linkedCount = interrupted.filter { !$0.teamMembers.isEmpty }.count
        XCTAssertGreaterThan(linkedCount, 0, "The first committed chunk must survive interruption")
        XCTAssertLessThanOrEqual(linkedCount, 32, "The linker must release its transaction between bounded chunks")

        let resumedScope = SyncExecutionScope()
        try await SyncExecutionContext.$scope.withValue(resumedScope) { try await actor.rewireRelationships() }
        resumedScope.close()
        let reloadedContext = ModelContext(container)
        let reloaded = try reloadedContext.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(reloaded.filter { $0.teamMembers.map(\.id) == [user.id] }.count, 70)
    }

    func testExpiredScopeRejectsTheActualLinkerBeforeAnySave() async throws {
        let schema = Schema(OPSSchemaCurrent.models)
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let actor = try await DataActor.makeBackgroundConfigured(modelContainer: container)
        let scope = SyncExecutionScope()
        scope.close()
        do {
            try await SyncExecutionContext.$scope.withValue(scope) { try await actor.rewireRelationships() }
            XCTFail("Expired linker must throw")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}

private extension DataActor {
    func rewireExpiringAfterFirstSave(_ scope: SyncExecutionScope) async throws {
        let observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: modelContext, queue: nil
        ) { _ in scope.close() }
        defer { NotificationCenter.default.removeObserver(observer) }
        try await rewireRelationships()
    }
}
