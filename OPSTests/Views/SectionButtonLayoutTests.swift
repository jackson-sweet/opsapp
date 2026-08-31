//
//  SectionButtonLayoutTests.swift
//  OPSTests
//
//  Bug 4c8a95f0 — the COMPLETED (29) footer button wrapped mid-word beside
//  CANCELLED (4). Buttons never wrap: the label reports its full one-line
//  width (lineLimit(1) + fixedSize), and the pair falls back to stacked
//  full-width rows when side-by-side genuinely does not fit.
//

import SwiftUI
import XCTest
@testable import OPS

@MainActor
final class SectionButtonLayoutTests: XCTestCase {

    private func fittingSize<V: View>(_ view: V, width: CGFloat) -> CGSize {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(
            in: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
    }

    private func completedButton() -> SectionButton {
        SectionButton(
            title: "COMPLETED",
            count: 29,
            color: TaskStatus.completed.color
        ) {}
    }

    private func cancelledButton() -> SectionButton {
        SectionButton(
            title: "CANCELLED",
            count: 4,
            color: TaskStatus.cancelled.color
        ) {}
    }

    /// One line at any offered width: a single button's fitting height must
    /// not grow when the width is squeezed to the reported-bug geometry
    /// (half a 390pt sheet minus gutters). Growth == a wrapped second line.
    func testSectionButtonHeightIsWidthInvariant() {
        let wide = fittingSize(completedButton(), width: 600)
        let narrow = fittingSize(completedButton(), width: 170)
        XCTAssertEqual(
            narrow.height, wide.height, accuracy: 1,
            "A squeezed SectionButton must keep its one-line height, not wrap."
        )
    }

    /// The task-footer pair on the bug's own geometry: at 390pt the pair may
    /// render side-by-side or stacked, but never taller than two full rows —
    /// and each row stays one-line high.
    func testCompletedCancelledPairNeverExceedsTwoOneLineRows() {
        let pair = SectionButtonPair {
            completedButton()
            cancelledButton()
        }
        let single = fittingSize(completedButton(), width: 600)
        let pairSize = fittingSize(pair, width: 390)
        let stackedCeiling = single.height * 2 + OPSStyle.Layout.spacing2_5 + 1
        XCTAssertLessThanOrEqual(
            pairSize.height, stackedCeiling,
            "The pair adapts by stacking whole rows — a wrapped label (3+ text lines) blows past two one-line rows."
        )
    }

    /// The projects-list sibling pair carries shorter labels but the identical
    /// trap; it must obey the same ceiling.
    func testClosedArchivedPairNeverExceedsTwoOneLineRows() {
        let pair = SectionButtonPair {
            SectionButton(title: "CLOSED", count: 12, color: Status.closed.color) {}
            SectionButton(title: "ARCHIVED", count: 3, color: Status.archived.color) {}
        }
        let single = fittingSize(completedButton(), width: 600)
        let pairSize = fittingSize(pair, width: 390)
        XCTAssertLessThanOrEqual(
            pairSize.height,
            single.height * 2 + OPSStyle.Layout.spacing2_5 + 1,
            "CLOSED / ARCHIVED must adapt the same way COMPLETED / CANCELLED does."
        )
    }

    /// A lone button (one section empty) still fills the row — the pair adds no
    /// stacking penalty when there is nothing to stack against.
    func testLoneSectionButtonKeepsOneRow() {
        let pair = SectionButtonPair { completedButton() }
        let single = fittingSize(completedButton(), width: 390)
        let pairSize = fittingSize(pair, width: 390)
        XCTAssertEqual(
            pairSize.height, single.height, accuracy: 1,
            "One button is always side-by-side-shaped: a single one-line row."
        )
    }
}
