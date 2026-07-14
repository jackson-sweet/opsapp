//
//  LeadShareSummaryBuilderTests.swift
//  OPSTests
//
//  The share summary is recipient-facing text — deterministic, plain
//  English, empty sections omitted, activity capped with an honest
//  "(+ N earlier)" tail.
//

import XCTest
@testable import OPS

final class LeadShareSummaryBuilderTests: XCTestCase {

    private func opportunity() -> Opportunity {
        let opp = Opportunity(
            id: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            companyId: "11111111-2222-3333-4444-555555555555",
            contactName: "Helen Calloway"
        )
        opp.contactPhone = "(555) 123-4567"
        opp.contactEmail = "helen@example.com"
        opp.address = "1240 Maple Ave, Victoria"
        opp.title = "Roof tear-off, 28 sq"
        opp.estimatedValue = 14_200
        opp.descriptionText = "Gate code 4411. Dog in yard."
        return opp
    }

    private func activity(daysAgo: Int, subject: String?, type: ActivityType = .note) -> Activity {
        let act = Activity(
            id: UUID().uuidString.lowercased(),
            opportunityId: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            companyId: "11111111-2222-3333-4444-555555555555",
            type: type,
            createdAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        )
        act.subject = subject
        return act
    }

    func test_FullSummary_containsEverySection_inOrder() {
        let text = LeadShareSummaryBuilder.summaryText(
            for: opportunity(),
            activities: [activity(daysAgo: 1, subject: "Quote sent")]
        )

        XCTAssertTrue(text.hasPrefix("LEAD — Helen Calloway\nL-D7E8F9"))
        for header in ["CONTACT", "SITE", "JOB", "NOTES", "ACTIVITY"] {
            XCTAssertTrue(text.contains("\n\n\(header)\n"), "missing section \(header)")
        }
        XCTAssertTrue(text.contains("Estimated value: $14,200"))
        XCTAssertTrue(text.contains("Quote sent"))

        // Recipient-facing: no tactical chrome.
        XCTAssertFalse(text.contains("//"))
    }

    func test_EmptySections_areOmitted() {
        let opp = Opportunity(
            id: "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
            companyId: "11111111-2222-3333-4444-555555555555",
            contactName: "Helen Calloway"
        )
        let text = LeadShareSummaryBuilder.summaryText(for: opp, activities: [])

        XCTAssertFalse(text.contains("SITE"))
        XCTAssertFalse(text.contains("JOB"))
        XCTAssertFalse(text.contains("NOTES"))
        XCTAssertFalse(text.contains("ACTIVITY"))
        XCTAssertTrue(text.contains("CONTACT"))   // name always present
    }

    func test_ActivityLines_capAtFive_withHonestTail() {
        let activities = (0..<8).map { activity(daysAgo: $0, subject: "Touch \($0)") }
        let lines = LeadShareSummaryBuilder.activityLines(from: activities)

        XCTAssertEqual(lines.count, 6)                 // 5 entries + tail
        XCTAssertTrue(lines[0].contains("Touch 0"))    // newest first
        XCTAssertEqual(lines.last, "(+ 3 earlier)")
    }

    func test_ActivityLabel_fallsBackToReadableType() {
        let act = activity(daysAgo: 0, subject: nil, type: .note)
        XCTAssertEqual(LeadShareSummaryBuilder.label(for: act), "Note")
    }

    func test_MoneyFormatting_groupsThousands_noDecimals() {
        XCTAssertEqual(LeadShareSummaryBuilder.formatMoney(14_200), "$14,200")
        XCTAssertEqual(LeadShareSummaryBuilder.formatMoney(950), "$950")
        XCTAssertEqual(LeadShareSummaryBuilder.formatMoney(1_250_000), "$1,250,000")
    }
}
