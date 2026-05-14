//
//  ProjectActionBarLayoutTests.swift
//  OPSTests
//
//  Layout contract for the Home ProjectActionBar once MEASURE is visible.
//

import XCTest
@testable import OPS

final class ProjectActionBarLayoutTests: XCTestCase {
    private let baseLabels = ["NAVIGATE", "COMPLETE", "RECEIPT", "DETAILS", "PHOTO"]
    private let labelsWithMeasure = ["NAVIGATE", "COMPLETE", "RECEIPT", "DETAILS", "PHOTO", "MEASURE"]

    func test_measureActionUsesThreeColumnGridOnNarrowHomeWidths() {
        for screenWidth in [CGFloat(320), CGFloat(375), CGFloat(390)] {
            let plan = ProjectActionBarLayout.plan(
                availableWidth: screenWidth,
                labels: labelsWithMeasure
            )

            XCTAssertEqual(plan.arrangement, .grid(columns: 3), "width \(screenWidth)")
            XCTAssertEqual(plan.rowCounts, [3, 3], "width \(screenWidth)")
            XCTAssertGreaterThanOrEqual(plan.minimumButtonWidth, ProjectActionBarLayout.preferredButtonWidth)
            XCTAssertTrue(plan.labelsFit, "width \(screenWidth)")
        }
    }

    func test_measureActionCanUseSingleRowWhenPreferredWidthFits() {
        let plan = ProjectActionBarLayout.plan(
            availableWidth: 450,
            labels: labelsWithMeasure
        )

        XCTAssertEqual(plan.arrangement, .singleRow)
        XCTAssertEqual(plan.rowCounts, [6])
        XCTAssertGreaterThanOrEqual(plan.minimumButtonWidth, ProjectActionBarLayout.preferredButtonWidth)
        XCTAssertTrue(plan.labelsFit)
    }

    func test_baseActionsKeepMinimumTouchTargetAtCompactWidth() {
        let plan = ProjectActionBarLayout.plan(
            availableWidth: 320,
            labels: baseLabels
        )

        XCTAssertEqual(plan.arrangement, .grid(columns: 3))
        XCTAssertEqual(plan.rowCounts, [3, 2])
        XCTAssertGreaterThanOrEqual(plan.minimumButtonWidth, ProjectActionBarLayout.minimumButtonWidth)
        XCTAssertTrue(plan.labelsFit)
    }

    func test_longActiveTaskLabelDropsToTwoColumnsInsteadOfWrapping() {
        let labels = ["NAVIGATE", "COMPLETE PUNCHLIST", "RECEIPT", "DETAILS", "PHOTO", "MEASURE"]
        let plan = ProjectActionBarLayout.plan(
            availableWidth: 320,
            labels: labels
        )

        XCTAssertEqual(plan.arrangement, .grid(columns: 2))
        XCTAssertEqual(plan.rowCounts, [2, 2, 2])
        XCTAssertGreaterThanOrEqual(plan.minimumButtonWidth, ProjectActionBarLayout.preferredButtonWidth)
        XCTAssertTrue(plan.labelsFit)
    }
}
