//
//  SiteVisitActivityPostTests.swift
//  OPSTests
//
//  Completion is a durable database command. The guarded server RPC creates
//  and returns the single timeline activity; the phone never posts one itself.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitActivityPostTests: XCTestCase {
    private var liveContainers: [ModelContainer] = []

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    func test_completionQueuesDatabaseCommandBehindCapturedRows() async throws {
        let context = try makeContext()
        let opportunity = Opportunity(
            id: "opp-1",
            companyId: "company-1",
            contactName: "Eric Devlin",
            stage: .quoting
        )
        context.insert(opportunity)
        try context.save()
        let viewModel = makeViewModel(opportunity: opportunity, context: context)
        viewModel.loadOrCreateVisit()
        viewModel.noteDraft = "Confirm stair landing."
        viewModel.addNote()

        let result = await viewModel.completeVisit()
        XCTAssertTrue(result.isCommitted)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let completion = try XCTUnwrap(operations.first {
            $0.operationType == SiteVisitSyncOperation.completionOperationType
        })
        XCTAssertEqual(completion.entityType, SyncEntityType.siteVisit.rawValue)
        XCTAssertNotNil(completion.dependsOnId)
        let operationsById = Dictionary(
            uniqueKeysWithValues: operations.map {
                ($0.id.uuidString.lowercased(), $0)
            }
        )
        var dependencyId = completion.dependsOnId
        var dependencyTypes: [String] = []
        while let currentId = dependencyId,
              let dependency = operationsById[currentId.lowercased()] {
            dependencyTypes.append(dependency.entityType)
            dependencyId = dependency.dependsOnId
        }
        XCTAssertTrue(dependencyTypes.contains(SyncEntityType.siteVisitArtifact.rawValue))
    }

    func test_repeatedCompletionNeverFoldsIntoParentCrud() async throws {
        let context = try makeContext()
        let viewModel = makeViewModel(opportunity: nil, context: context)
        viewModel.loadOrCreateVisit()
        viewModel.noteDraft = "Gate code 4812."
        viewModel.addNote()

        let firstResult = await viewModel.completeVisit()
        let secondResult = await viewModel.completeVisit()
        XCTAssertTrue(firstResult.isCommitted)
        XCTAssertTrue(secondResult.isCommitted)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(
            operations.filter {
                $0.operationType == SiteVisitSyncOperation.completionOperationType
            }.count,
            2
        )
        XCTAssertEqual(
            operations.filter {
                $0.entityType == SyncEntityType.siteVisit.rawValue
                    && $0.operationType != SiteVisitSyncOperation.completionOperationType
            }.count,
            1
        )
    }

    func test_completionPayloadCarriesCurrentVisitSummaryForServerActivity() async throws {
        let context = try makeContext()
        let viewModel = makeViewModel(opportunity: nil, context: context)
        viewModel.loadOrCreateVisit()
        viewModel.noteDraft = "Client wants black rail."
        viewModel.addNote()

        let result = await viewModel.completeVisit()
        XCTAssertTrue(result.isCommitted)

        let operation = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SyncOperation>()).first {
                $0.operationType == SiteVisitSyncOperation.completionOperationType
            }
        )
        let payload = try JSONDecoder().decode(
            SiteVisitSyncOperation.Payload.self,
            from: operation.payload
        )
        XCTAssertEqual(payload.completion?.notes, "Client wants black rail.")
    }

    private func makeViewModel(
        opportunity: Opportunity?,
        context: ModelContext
    ) -> SiteVisitCaptureViewModel {
        SiteVisitCaptureViewModel(
            opportunity: opportunity,
            companyId: "company-1",
            userId: "user-operator-1",
            modelContext: context
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitType.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self,
            Opportunity.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        liveContainers.append(container)
        return container.mainContext
    }
}
