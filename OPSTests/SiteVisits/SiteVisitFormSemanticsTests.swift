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
}
