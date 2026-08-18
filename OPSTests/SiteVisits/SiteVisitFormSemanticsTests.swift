//
//  SiteVisitFormSemanticsTests.swift
//  OPSTests
//
//  Pure form-order contract for the bound lead summary shown during capture.
//

import Foundation
import XCTest

#if canImport(OPS)
@testable import OPS
#endif

final class SiteVisitFormSemanticsTests: XCTestCase {
    func testNonblankBoundLeadSummarySitsBetweenIdentityAndChecklist() throws {
        let sections = SiteVisitPrimaryFormSemantics.orderedSections(
            boundLeadSummary: "  Measure the existing deck.\nConfirm railing scope.  "
        )

        XCTAssertEqual(
            sections,
            [
                .identity,
                .leadSummary(
                    SiteVisitLeadSummaryPresentation(
                        text: "Measure the existing deck.\nConfirm railing scope."
                    )
                ),
                .checklist,
                .notes
            ]
        )

        guard case .leadSummary(let presentation) = sections[1] else {
            return XCTFail("Expected the lead summary immediately after identity")
        }
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Lead summary. Measure the existing deck. Confirm railing scope."
        )
    }

    func testMissingOrWhitespaceOnlyBoundLeadSummaryAddsNoSection() {
        let expected: [SiteVisitPrimaryFormSection] = [.identity, .checklist, .notes]

        XCTAssertEqual(
            SiteVisitPrimaryFormSemantics.orderedSections(boundLeadSummary: nil),
            expected
        )
        XCTAssertEqual(
            SiteVisitPrimaryFormSemantics.orderedSections(boundLeadSummary: ""),
            expected
        )
        XCTAssertEqual(
            SiteVisitPrimaryFormSemantics.orderedSections(boundLeadSummary: " \n\t "),
            expected
        )
    }

    // MARK: - Item 886f1a02 — the band must survive a lead the agent has not written up

    func testLeadDescriptionBacksTheBandWhenNoAgentSummaryExists() throws {
        let sections = SiteVisitPrimaryFormSemantics.orderedSections(
            boundLeadSummary: "  \n ",
            leadDescription: "  Wants the back deck re-boarded before the long weekend.  "
        )

        XCTAssertEqual(
            sections,
            [
                .identity,
                .leadSummary(
                    SiteVisitLeadSummaryPresentation(
                        text: "Wants the back deck re-boarded before the long weekend.",
                        source: .leadDescription
                    )
                ),
                .checklist,
                .notes
            ]
        )

        guard case .leadSummary(let presentation) = sections[1] else {
            return XCTFail("Expected the lead description to back the band")
        }
        XCTAssertEqual(presentation.source.label, "LEAD DETAILS")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Lead details. Wants the back deck re-boarded before the long weekend."
        )
    }

    func testAgentSummaryOutranksTheLeadDescription() throws {
        let sections = SiteVisitPrimaryFormSemantics.orderedSections(
            boundLeadSummary: "Measure the existing deck.",
            leadDescription: "Raw inbound inquiry text."
        )

        guard case .leadSummary(let presentation) = sections[1] else {
            return XCTFail("Expected the lead summary immediately after identity")
        }
        XCTAssertEqual(presentation.text, "Measure the existing deck.")
        XCTAssertEqual(presentation.source, .agentSummary)
        XCTAssertEqual(presentation.source.label, "LEAD SUMMARY")
    }

    func testNeitherSourceAddsNoSection() {
        XCTAssertEqual(
            SiteVisitPrimaryFormSemantics.orderedSections(
                boundLeadSummary: nil,
                leadDescription: " \n\t "
            ),
            [.identity, .checklist, .notes]
        )
    }
}
