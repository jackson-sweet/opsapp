//
//  SiteVisitOrphanRecoveryTests.swift
//  OPSTests
//
//  Legacy site-visit children must never drain without their cloud parent.
//

import XCTest
import SwiftData
@testable import OPS

final class SiteVisitOrphanRecoveryTests: XCTestCase {
    private let companyID = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let userID = "310fbd03-4ffd-4432-b502-e20aff43d548"
    private let visitID = "d6ec5372-607f-4dc1-8733-c52f14e2d4e2"

    @MainActor
    func test_sameCompanyChildrenReconstructOneCanonicalParentAndParentFirstQueue() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let later = Date(timeIntervalSince1970: 200)
        let earlier = Date(timeIntervalSince1970: 100)

        let mixedCaseArtifact = makeArtifact(siteVisitID: visitID, capturedAt: later)
        mixedCaseArtifact.siteVisitId = visitID.uppercased()
        mixedCaseArtifact.companyId = companyID.uppercased()
        context.insert(mixedCaseArtifact)
        context.insert(makeAnswer(siteVisitID: visitID, createdAt: earlier))
        context.insert(makeDraft(siteVisitID: visitID.uppercased(), createdAt: later))
        try context.save()

        let result = try SiteVisitOrphanRecovery.recover(
            in: context,
            activeUserId: userID,
            activeCompanyId: companyID,
            quarantine: { _ in XCTFail("same-company work must not quarantine") }
        )

        XCTAssertEqual(result.reconstructedVisitIds, [visitID])
        let visit = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisit>()).first)
        XCTAssertEqual(visit.id, visitID)
        XCTAssertEqual(visit.companyId, companyID)
        XCTAssertEqual(visit.status, .inProgress)
        XCTAssertEqual(visit.scheduledAt, earlier)
        XCTAssertEqual(visit.createdAt, earlier)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let parent = try XCTUnwrap(operations.first {
            $0.entityType == SyncEntityType.siteVisit.rawValue
                && $0.operationType == "create"
        })
        let children = operations.filter {
            $0.entityType != SyncEntityType.siteVisit.rawValue
                && $0.operationType != SiteVisitSyncOperation.mediaOperationType
        }
        XCTAssertFalse(children.isEmpty)
        XCTAssertTrue(children.allSatisfy { $0.dependsOnId != nil })
        XCTAssertTrue(
            children.contains { $0.dependsOnId == parent.id.uuidString.lowercased() },
            "the first child must wait for the reconstructed parent"
        )
    }

    @MainActor
    func test_completionOperationIsTheOnlyEvidenceThatReconstructsCompleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let completedAt = Date(timeIntervalSince1970: 300)
        context.insert(makeArtifact(siteVisitID: visitID, capturedAt: Date(timeIntervalSince1970: 100)))
        let payload = SiteVisitSyncOperation.Payload(
            companyId: companyID,
            siteVisitId: visitID,
            entityId: visitID,
            completion: SiteVisitCompletionPayload(
                notes: nil,
                measurements: nil,
                photos: [],
                internalNotes: nil
            )
        )
        let completion = SyncOperation(
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: visitID,
            operationType: SiteVisitSyncOperation.completionOperationType,
            payload: try JSONEncoder().encode(payload),
            changedFields: ["status"],
            priority: 0
        )
        completion.createdAt = completedAt
        context.insert(completion)
        try context.save()

        _ = try SiteVisitOrphanRecovery.recover(
            in: context,
            activeUserId: userID,
            activeCompanyId: companyID,
            quarantine: { _ in }
        )

        let visit = try XCTUnwrap(context.fetch(FetchDescriptor<SiteVisit>()).first)
        XCTAssertEqual(visit.status, .completed)
        XCTAssertEqual(visit.completedAt, completedAt)
    }

    @MainActor
    func test_foreignAndMalformedGroupsQuarantineWithoutUploadOrDeletion() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let foreignCompany = "foreign-company"
        let foreign = makeArtifact(
            siteVisitID: visitID,
            companyID: foreignCompany,
            capturedAt: Date(timeIntervalSince1970: 100)
        )
        let malformed = makeAnswer(
            siteVisitID: "legacy-visit-id",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(foreign)
        context.insert(malformed)
        try context.save()
        var quarantined: [SiteVisitOrphanQuarantine] = []

        let result = try SiteVisitOrphanRecovery.recover(
            in: context,
            activeUserId: userID,
            activeCompanyId: companyID,
            quarantine: { quarantined.append($0) }
        )

        XCTAssertTrue(result.reconstructedVisitIds.isEmpty)
        XCTAssertEqual(Set(quarantined.map(\.reason)), Set([.foreignCompany, .malformedIdentity]))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOperation>()).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteVisitCaptureArtifact>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteVisitChecklistAnswer>()), 1)
    }

    @MainActor
    func test_conflictingOpportunityBindingsQuarantineAsAmbiguous() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = makeArtifact(siteVisitID: visitID, capturedAt: Date(timeIntervalSince1970: 100))
        first.opportunityId = "0d4e783f-bc3a-4fa0-8aa5-b84c4fd9b850"
        let second = makeDraft(siteVisitID: visitID, createdAt: Date(timeIntervalSince1970: 200))
        second.opportunityId = "96f12a26-d7af-4215-85ca-04f94520c36e"
        context.insert(first)
        context.insert(second)
        try context.save()
        var quarantined: [SiteVisitOrphanQuarantine] = []

        _ = try SiteVisitOrphanRecovery.recover(
            in: context,
            activeUserId: userID,
            activeCompanyId: companyID,
            quarantine: { quarantined.append($0) }
        )

        XCTAssertEqual(quarantined.map(\.reason), [.ambiguousBinding])
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
    }

    @MainActor
    func test_quarantinedGroupParksEveryExistingPacketOperationOutsideGenericRetry() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let malformedVisitID = "legacy-visit-id"
        context.insert(
            makeAnswer(
                siteVisitID: malformedVisitID,
                createdAt: Date(timeIntervalSince1970: 100)
            )
        )
        let payload = SiteVisitSyncOperation.Payload(
            companyId: companyID,
            siteVisitId: malformedVisitID,
            entityId: malformedVisitID,
            completion: SiteVisitCompletionPayload(
                notes: nil,
                measurements: nil,
                photos: [],
                internalNotes: nil
            )
        )
        let completion = SyncOperation(
            entityType: SyncEntityType.siteVisit.rawValue,
            entityId: malformedVisitID,
            operationType: SiteVisitSyncOperation.completionOperationType,
            payload: try JSONEncoder().encode(payload),
            changedFields: ["status"]
        )
        context.insert(completion)
        try context.save()

        _ = try SiteVisitOrphanRecovery.recover(
            in: context,
            activeUserId: userID,
            activeCompanyId: companyID,
            quarantine: { _ in }
        )

        XCTAssertEqual(completion.status, "quarantined")
        XCTAssertNil(completion.lastAttemptedAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SiteVisit>()).isEmpty)
    }

    @MainActor
    func test_recoveryIsIdempotentAcrossLaunches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(makeArtifact(siteVisitID: visitID.uppercased(), capturedAt: Date(timeIntervalSince1970: 100)))
        try context.save()

        for _ in 0..<2 {
            _ = try SiteVisitOrphanRecovery.recover(
                in: context,
                activeUserId: userID,
                activeCompanyId: companyID,
                quarantine: { _ in }
            )
        }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SiteVisit>()), 1)
        let parentOps = try context.fetch(FetchDescriptor<SyncOperation>()).filter {
            $0.entityType == SyncEntityType.siteVisit.rawValue
                && $0.operationType == "create"
        }
        XCTAssertEqual(parentOps.count, 1)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self,
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    private func makeArtifact(
        siteVisitID: String,
        companyID: String? = nil,
        capturedAt: Date
    ) -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            siteVisitId: siteVisitID,
            companyId: companyID ?? self.companyID,
            kind: .photo,
            source: .camera,
            localAssetURL: "local://project_images/orphan.jpg",
            capturedAt: capturedAt,
            createdBy: userID,
            createdAt: capturedAt
        )
    }

    private func makeAnswer(siteVisitID: String, createdAt: Date) -> SiteVisitChecklistAnswer {
        SiteVisitChecklistAnswer(
            siteVisitId: siteVisitID,
            companyId: companyID,
            opportunityId: nil,
            siteVisitTypeId: "estimate",
            fieldId: "scope",
            label: "Scope",
            kind: .shortText,
            required: true,
            sortOrder: 1,
            answerValue: SiteVisitChecklistValue(text: "Replace railing"),
            createdBy: userID,
            createdAt: createdAt
        )
    }

    private func makeDraft(siteVisitID: String, createdAt: Date) -> SiteVisitIdentityDraft {
        SiteVisitIdentityDraft(
            siteVisitId: siteVisitID,
            companyId: companyID,
            contactName: "Taylor",
            address: "123 Main St",
            createdBy: userID,
            createdAt: createdAt
        )
    }
}
