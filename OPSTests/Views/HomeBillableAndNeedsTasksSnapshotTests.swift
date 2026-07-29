//
//  HomeBillableAndNeedsTasksSnapshotTests.swift
//  OPSTests
//
//  Visual-verification harness for the Home dashboard fixes (workstream I4):
//    • Bug 5137414e — "Billable this week" expands to show ALL jobs (no 3-row
//      cap); renders a 6-job rollup with every row present.
//    • Bug 588b3e19 — $0 ≠ no data: a rollup whose projects carry no value
//      shows the em-dash empty state ("—"), not a lying "$0", in the header
//      total AND per-row amount slot.
//    • Bug 465332fa — the invisible-helpfulness "NEEDS TASKS" strip.
//
//  Renders the REAL `HomeBillableThisWeekCard` / `HomeNeedsTasksStrip` via
//  `UIHostingController` + `UIWindow` + `drawHierarchy` (NOT `ImageRenderer`,
//  which can't resolve asset-catalog colors and skips `onAppear` — the card's
//  expanded state is seeded through onAppear via @AppStorage).
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/HomeBillableAndNeedsTasksSnapshotTests \
//          -clonedSourcePackagesDirPath .spm-local -derivedDataPath .dd-local
//  Extract: xcrun xcresulttool export attachments --path <dd>/Logs/Test/*.xcresult ...
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class HomeBillableAndNeedsTasksSnapshotTests: XCTestCase {

    private let deviceWidth: CGFloat = 393

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-home-i4-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func hostSnapshot<V: View>(_ name: String, height: CGFloat, @ViewBuilder _ content: () -> V) {
        let size = CGSize(width: deviceWidth, height: height)
        let host = UIHostingController(rootView:
            ZStack(alignment: .top) {
                OPSStyle.Colors.background
                content()
                    .padding(OPSStyle.Layout.spacing3_5)
            }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
            // A UIWindow inherits the device safe-area insets whatever its
            // frame — without this the content renders displaced and
            // bottom-clipped (same correction as DaySheetRowSnapshotTests).
            .ignoresSafeArea()
        )
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // Let onAppear (expanded-state restore) + layout settle.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        host.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name)@\(Int(image.scale))x.png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name) (\(Int(image.size.width))×\(Int(image.size.height))pt)")
    }

    // MARK: - Fixtures

    private func candidate(
        _ id: String,
        title: String,
        section: HomeBillableRollupSection,
        tasks: Int,
        amount: Double?
    ) -> HomeBillableProjectCandidate {
        HomeBillableProjectCandidate(
            id: "\(section.rawValue)-\(id)",
            projectId: id,
            title: title,
            section: section,
            taskCount: tasks,
            amount: amount,
            invoiceId: amount != nil ? "inv-\(id)" : nil,
            estimateId: nil,
            latestTaskEnd: nil
        )
    }

    /// Four valued jobs in ONE section — the direct anti-regression fixture for
    /// bug 5137414e: the old code capped each section at `prefix(3)`, so the
    /// 4th ("1075 Pandora Ave") would have been invisible. projectCount == 4
    /// hits the inline (non-scroll) branch, so all four rows render at once and
    /// the snapshot proves nothing is hidden.
    private var fourClosingJobs: HomeBillableThisWeekRollup {
        HomeBillableThisWeekRollup(
            weekStart: Date(timeIntervalSince1970: 1_780_000_000),
            weekEnd: Date(timeIntervalSince1970: 1_780_500_000),
            closingThisWeek: [
                candidate("c1", title: "972 Lyall St", section: .closingThisWeek, tasks: 3, amount: 8_400),
                candidate("c2", title: "3040 Cedar Hill Rd", section: .closingThisWeek, tasks: 2, amount: 12_600),
                candidate("c3", title: "88 King St W", section: .closingThisWeek, tasks: 1, amount: 4_200),
                candidate("c4", title: "1075 Pandora Ave", section: .closingThisWeek, tasks: 5, amount: 21_000)
            ],
            readyToBill: []
        )
    }

    /// Jobs with NO attached value — every amount is nil. Proves the header and
    /// rows render "—", not "$0" (bug 588b3e19).
    private var unvaluedJobs: HomeBillableThisWeekRollup {
        HomeBillableThisWeekRollup(
            weekStart: Date(timeIntervalSince1970: 1_780_000_000),
            weekEnd: Date(timeIntervalSince1970: 1_780_500_000),
            closingThisWeek: [
                candidate("u1", title: "972 Lyall St", section: .closingThisWeek, tasks: 3, amount: nil),
                candidate("u2", title: "3040 Cedar Hill Rd", section: .closingThisWeek, tasks: 2, amount: nil)
            ],
            readyToBill: [
                candidate("u3", title: "2003 Hawkins Pl", section: .readyToBill, tasks: 1, amount: nil)
            ]
        )
    }

    // MARK: - Tests

    /// Sanity assertions alongside the visual capture (the rollup semantics the
    /// card renders), so this file also fails loudly if the model regresses.
    func testBillableSemantics() {
        XCTAssertTrue(fourClosingJobs.hasKnownAmounts)
        XCTAssertEqual(fourClosingJobs.projectCount, 4)
        XCTAssertEqual(fourClosingJobs.totalKnownAmount, 46_200, accuracy: 0.001)

        XCTAssertFalse(unvaluedJobs.hasKnownAmounts)
        XCTAssertEqual(unvaluedJobs.projectCount, 3)
        XCTAssertEqual(unvaluedJobs.totalKnownAmount, 0)
    }

    // MARK: - Empty-money rendering (bug 8c7fdb9e)

    /// A week where nothing carries a value renders the hero as "$—". The bare
    /// "—" it used to render reads as a dead slot rather than empty money —
    /// the reader can't tell "no dollars recorded" from "this field is
    /// broken". "$0" stays banned: it claims a real zero.
    func testHeroTotalIsEmptyMoneyTokenWhenNothingIsValued() {
        XCTAssertEqual(
            HomeBillableThisWeekCard.totalText(for: unvaluedJobs),
            "$—"
        )
    }

    /// A valued week still renders the whole-dollar canon, unchanged.
    func testHeroTotalIsWholeDollarCanonWhenValued() {
        XCTAssertEqual(
            HomeBillableThisWeekCard.totalText(for: fourClosingJobs),
            "$46,200"
        )
    }

    /// Per-row amounts follow the hero: an unvalued job's amount slot reads
    /// "$—", so the amount column scans as one money column top to bottom.
    func testRowAmountIsEmptyMoneyTokenWhenUnvalued() {
        let unvalued = candidate("u1", title: "972 Lyall St", section: .closingThisWeek, tasks: 3, amount: nil)
        XCTAssertEqual(HomeBillableThisWeekCard.amountText(for: unvalued), "$—")
    }

    func testRowAmountIsWholeDollarCanonWhenValued() {
        let valued = candidate("c2", title: "3040 Cedar Hill Rd", section: .closingThisWeek, tasks: 2, amount: 12_600)
        XCTAssertEqual(HomeBillableThisWeekCard.amountText(for: valued), "$12,600")
    }

    func testRenderBillableExpandedAllJobs() {
        UserDefaults.standard.set(true, forKey: "homeBillableThisWeekExpanded")
        hostSnapshot("home_billable_expanded_all_jobs", height: 380) {
            HomeBillableThisWeekCard(rollup: fourClosingJobs, onSelect: { _ in })
        }
    }

    func testRenderBillableNoDataEmDash() {
        UserDefaults.standard.set(true, forKey: "homeBillableThisWeekExpanded")
        hostSnapshot("home_billable_no_data_emdash", height: 300) {
            HomeBillableThisWeekCard(rollup: unvaluedJobs, onSelect: { _ in })
        }
    }

    func testRenderNeedsTasksStrip() {
        hostSnapshot("home_needs_tasks_strip", height: 140) {
            HomeNeedsTasksStrip(count: 3, onOpen: {})
        }
    }
}
#endif
