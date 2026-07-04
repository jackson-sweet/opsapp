//
//  PipelineViewModelMergeTests.swift
//  OPSTests
//
//  Covers the identity-preserving merge that backs the LEADS auto-refresh
//  (bug 0b7e9b17). The reload merges server rows into the EXISTING Opportunity
//  instances by id so the pushed LeadDetailView updates in place and list
//  identity stays stable. Also asserts Opportunity.apply(_:) copies every
//  triage-critical field — a field missed there silently never refreshes.
//

import XCTest
@testable import OPS

final class PipelineViewModelMergeTests: XCTestCase {

    // MARK: - Factory
    //
    // Builds an in-memory Opportunity the same way OpportunityDTO.toModel()
    // does: the convenience init for the required fields, then property
    // assignment for the rest. Self-contained (no DEBUG preview scaffolding)
    // so every stored property can be set to a distinct sentinel for the
    // apply() field-copy assertions.
    private func makeOpportunity(
        id: String,
        companyId: String = "company-1",
        title: String? = nil,
        contactName: String = "Contact",
        contactEmail: String? = nil,
        contactPhone: String? = nil,
        descriptionText: String? = nil,
        address: String? = nil,
        stage: PipelineStage = .newLead,
        stageEnteredAt: Date = Date(timeIntervalSince1970: 1_000_000),
        stageManuallySet: Bool = false,
        assignedTo: String? = nil,
        priority: String? = nil,
        source: String? = nil,
        quoteDeliveryMethod: QuoteDeliveryMethod? = nil,
        estimatedValue: Double? = nil,
        actualValue: Double? = nil,
        winProbabilityOverride: Int? = nil,
        expectedCloseDate: Date? = nil,
        actualCloseDate: Date? = nil,
        nextFollowUpAt: Date? = nil,
        lastActivityAt: Date? = nil,
        projectId: String? = nil,
        clientId: String? = nil,
        lostReason: String? = nil,
        lostNotes: String? = nil,
        deletedAt: Date? = nil,
        archivedAt: Date? = nil,
        tags: [String] = [],
        sourceEmailId: String? = nil,
        correspondenceCount: Int = 0,
        outboundCount: Int = 0,
        inboundCount: Int = 0,
        lastInboundAt: Date? = nil,
        lastOutboundAt: Date? = nil,
        lastMessageDirection: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> Opportunity {
        let opp = Opportunity(
            id: id,
            companyId: companyId,
            contactName: contactName,
            stage: stage,
            stageEnteredAt: stageEnteredAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        opp.title = title
        opp.contactEmail = contactEmail
        opp.contactPhone = contactPhone
        opp.descriptionText = descriptionText
        opp.address = address
        opp.stageManuallySet = stageManuallySet
        opp.assignedTo = assignedTo
        opp.priority = priority
        opp.source = source
        opp.quoteDeliveryMethod = quoteDeliveryMethod
        opp.estimatedValue = estimatedValue
        opp.actualValue = actualValue
        opp.winProbabilityOverride = winProbabilityOverride
        opp.expectedCloseDate = expectedCloseDate
        opp.actualCloseDate = actualCloseDate
        opp.nextFollowUpAt = nextFollowUpAt
        opp.lastActivityAt = lastActivityAt
        opp.projectId = projectId
        opp.clientId = clientId
        opp.lostReason = lostReason
        opp.lostNotes = lostNotes
        opp.deletedAt = deletedAt
        opp.archivedAt = archivedAt
        opp.tags = tags
        opp.sourceEmailId = sourceEmailId
        opp.correspondenceCount = correspondenceCount
        opp.outboundCount = outboundCount
        opp.inboundCount = inboundCount
        opp.lastInboundAt = lastInboundAt
        opp.lastOutboundAt = lastOutboundAt
        opp.lastMessageDirection = lastMessageDirection
        return opp
    }

    // MARK: - merge

    // 1. Existing id → SAME instance survives (===) with fields updated.
    func testMergeUpdatesExistingInstanceInPlace() {
        let current = makeOpportunity(id: "a", contactName: "Old Name", stage: .newLead)
        let fresh   = makeOpportunity(id: "a", contactName: "New Name", stage: .quoted)
        let merged  = PipelineViewModel.merge(existing: [current], incoming: [fresh])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0] === current)          // identity preserved
        XCTAssertEqual(merged[0].stage, .quoted)      // field applied
        XCTAssertEqual(merged[0].contactName, "New Name")
    }

    // 2. New id → appended as the incoming instance.
    func testMergeInsertsNewLead() {
        let current = makeOpportunity(id: "a", contactName: "A")
        let existingB = makeOpportunity(id: "b", contactName: "B-incoming")
        let merged = PipelineViewModel.merge(existing: [current], incoming: [current, existingB])
        XCTAssertEqual(merged.map(\.id), ["a", "b"])
        // The new id resolves to the incoming instance itself.
        XCTAssertTrue(merged[1] === existingB)
    }

    // 3. Missing id → dropped from result (server-deleted/merged lead disappears).
    func testMergeDropsRemovedLead() {
        let keep = makeOpportunity(id: "keep")
        let gone = makeOpportunity(id: "gone")
        let freshKeep = makeOpportunity(id: "keep")
        let merged = PipelineViewModel.merge(existing: [keep, gone], incoming: [freshKeep])
        XCTAssertEqual(merged.map(\.id), ["keep"])
        XCTAssertFalse(merged.contains { $0.id == "gone" })
        // Surviving id keeps the existing instance (identity), not the incoming.
        XCTAssertTrue(merged[0] === keep)
    }

    // 4. Result preserves INCOMING order (server sort = created_at desc).
    func testMergePreservesIncomingOrder() {
        let a = makeOpportunity(id: "a")
        let b = makeOpportunity(id: "b")
        let c = makeOpportunity(id: "c")
        // existing in one order; incoming in a different order → result follows incoming.
        let merged = PipelineViewModel.merge(existing: [a, b, c], incoming: [c, a, b])
        XCTAssertEqual(merged.map(\.id), ["c", "a", "b"])
    }

    // 5. apply(_:) copies every stored property (id excluded).
    func testApplyCopiesTriageFields() {
        // `target` starts as an all-defaults NEW LEAD; `source` sets a distinct
        // sentinel into EVERY stored property. After apply, target must equal
        // source field-for-field (except id, which apply never touches).
        let target = makeOpportunity(id: "target")

        let d1 = Date(timeIntervalSince1970: 2_000_000)
        let d2 = Date(timeIntervalSince1970: 2_100_000)
        let d3 = Date(timeIntervalSince1970: 2_200_000)
        let d4 = Date(timeIntervalSince1970: 2_300_000)
        let d5 = Date(timeIntervalSince1970: 2_400_000)
        let d6 = Date(timeIntervalSince1970: 2_500_000)
        let d7 = Date(timeIntervalSince1970: 2_600_000)
        let d8 = Date(timeIntervalSince1970: 2_700_000)
        let d9 = Date(timeIntervalSince1970: 2_800_000)
        let d10 = Date(timeIntervalSince1970: 2_900_000)

        let source = makeOpportunity(
            id: "source",                       // must NOT be copied
            companyId: "company-2",
            title: "Fresh Title",
            contactName: "Fresh Contact",
            contactEmail: "fresh@example.com",
            contactPhone: "555-0101",
            descriptionText: "Fresh description",
            address: "123 Fresh St",
            stage: .negotiation,
            stageEnteredAt: d1,
            stageManuallySet: true,
            assignedTo: "user-fresh",
            priority: "high",
            source: "referral",
            quoteDeliveryMethod: .email,
            estimatedValue: 12_345,
            actualValue: 11_000,
            winProbabilityOverride: 65,
            expectedCloseDate: d2,
            actualCloseDate: d3,
            nextFollowUpAt: d4,
            lastActivityAt: d5,
            projectId: "project-fresh",
            clientId: "client-fresh",
            lostReason: "budget",
            lostNotes: "went cheaper",
            deletedAt: d6,
            archivedAt: d7,
            tags: ["urgent", "vip"],
            sourceEmailId: "email-fresh",
            correspondenceCount: 9,
            outboundCount: 5,
            inboundCount: 4,
            lastInboundAt: d8,
            lastOutboundAt: d9,
            lastMessageDirection: "in",
            createdAt: d10,
            updatedAt: d1
        )

        target.apply(source)

        // id is NEVER copied — the whole point of identity preservation.
        XCTAssertEqual(target.id, "target")

        // High-risk / triage-critical fields asserted individually.
        XCTAssertEqual(target.stage, .negotiation)
        XCTAssertEqual(target.stageEnteredAt, d1)
        XCTAssertEqual(target.nextFollowUpAt, d4)
        XCTAssertEqual(target.lastActivityAt, d5)
        XCTAssertEqual(target.lastMessageDirection, "in")
        XCTAssertEqual(target.correspondenceCount, 9)
        XCTAssertEqual(target.inboundCount, 4)
        XCTAssertEqual(target.outboundCount, 5)
        XCTAssertEqual(target.lastInboundAt, d8)
        XCTAssertEqual(target.lastOutboundAt, d9)
        XCTAssertEqual(target.estimatedValue, 12_345)
        XCTAssertEqual(target.actualValue, 11_000)
        XCTAssertEqual(target.projectId, "project-fresh")
        XCTAssertEqual(target.archivedAt, d7)
        XCTAssertEqual(target.deletedAt, d6)
        XCTAssertEqual(target.updatedAt, d1)
        XCTAssertEqual(target.stageManuallySet, true)
        XCTAssertEqual(target.priority, "high")
        XCTAssertEqual(target.winProbabilityOverride, 65)

        // Remaining stored properties — every one must be copied.
        XCTAssertEqual(target.companyId, "company-2")
        XCTAssertEqual(target.title, "Fresh Title")
        XCTAssertEqual(target.contactName, "Fresh Contact")
        XCTAssertEqual(target.contactEmail, "fresh@example.com")
        XCTAssertEqual(target.contactPhone, "555-0101")
        XCTAssertEqual(target.descriptionText, "Fresh description")
        XCTAssertEqual(target.address, "123 Fresh St")
        XCTAssertEqual(target.assignedTo, "user-fresh")
        XCTAssertEqual(target.source, "referral")
        XCTAssertEqual(target.quoteDeliveryMethod, .email)
        XCTAssertEqual(target.expectedCloseDate, d2)
        XCTAssertEqual(target.actualCloseDate, d3)
        XCTAssertEqual(target.clientId, "client-fresh")
        XCTAssertEqual(target.lostReason, "budget")
        XCTAssertEqual(target.lostNotes, "went cheaper")
        XCTAssertEqual(target.tags, ["urgent", "vip"])
        XCTAssertEqual(target.sourceEmailId, "email-fresh")
        XCTAssertEqual(target.createdAt, d10)
    }

    // 6. apply() also clears fields the incoming row no longer has (nil-out).
    //    A follow-up completed on the web sets next_follow_up_at back to null;
    //    the refresh must reflect that, not keep the stale non-nil value.
    func testApplyClearsNilledFields() {
        let target = makeOpportunity(
            id: "t",
            nextFollowUpAt: Date(timeIntervalSince1970: 5_000_000),
            lastMessageDirection: "in"
        )
        let source = makeOpportunity(id: "t")   // both fields nil
        target.apply(source)
        XCTAssertNil(target.nextFollowUpAt)
        XCTAssertNil(target.lastMessageDirection)
    }
}
