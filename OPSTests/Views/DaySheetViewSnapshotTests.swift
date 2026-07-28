//
//  DaySheetViewSnapshotTests.swift
//  OPSTests
//
//  Visual verification of the assembled day sheet — the surface an `assigned`
//  operator gets instead of the triage console. One render per state in spec
//  §3.5: a populated day spanning all three groups (YOUR MOVE / NEW / WAITING,
//  each with its own urgency vocabulary), the empty sheet with its CTA, the
//  loading skeletons, offline-with-cache, error-with-no-cache, and the case
//  that proves the error does not preempt a cache it has.
//
//  Harness is DaySheetCardSnapshotTests' verbatim, including the safe-area fix
//  (a UIWindow inherits the device insets whatever its frame, which would push
//  the sheet down and clip it). A rendering harness, not an assertion.
//
//  Rows render COLLAPSED, which is the sheet's resting state — the expanded
//  card is proven card-side, and collapsed rows keep the deck resolver (and its
//  ModelContainer dependency) out of a bare UIWindow host.
//
//  Run:  xcodebuild test -scheme OPS \
//          -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
//          -only-testing:OPSTests/DaySheetViewSnapshotTests
//

#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import OPS

@MainActor
final class DaySheetViewSnapshotTests: XCTestCase {

    private var outDir: URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ops-day-sheet-view-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func snapshot<V: View>(_ name: String, size: CGSize, @ViewBuilder _ content: () -> V) {
        let host = UIHostingController(rootView: content().ignoresSafeArea())
        host.overrideUserInterfaceStyle = .dark
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.backgroundColor = .black

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { XCTFail("render \(name)"); return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? data.write(to: outDir.appendingPathComponent("\(name).png"))
        print("📸 SNAPSHOT \(name)")
    }

    // MARK: - Fixtures

    private static let sheetWidth: CGFloat = 390

    /// A delegate's day: two leads waiting on him (one missed, one due today),
    /// one that landed this morning, and one parked with the customer. Every
    /// lead is assigned to the preview operator, so the policy's row filter
    /// keeps them all.
    private func assignedDay() -> [Opportunity] {
        let overdue = Opportunity.preview(
            title: "Rivera siding job", contactName: "Sam Rivera",
            stage: .quoted, estimatedValue: 14_800,
            daysInStage: 6, lastActivityDaysAgo: 4, nextFollowUpDaysFromNow: -3
        )
        overdue.address = "1841 Beckwith Ave, Burnaby BC"
        overdue.contactPhone = "604-555-0142"

        let dueToday = Opportunity.preview(
            title: "Hilltop pool deck", contactName: "Anna Patel",
            stage: .quoting, estimatedValue: 22_400,
            daysInStage: 2, lastActivityDaysAgo: 1, nextFollowUpDaysFromNow: 0
        )
        dueToday.address = "9 Hilltop Rd, Coquitlam BC"
        dueToday.contactPhone = "604-555-0177"

        let fresh = Opportunity.preview(
            title: "Smith deck addition", contactName: "Mike Smith",
            stage: .newLead, estimatedValue: 8_500,
            daysInStage: 0
        )
        fresh.address = "22 Fraser St, New Westminster BC"
        fresh.contactPhone = "604-555-0110"
        // Whole-day fixtures land on "NOW"; back it off so the NEW group shows
        // its hours vocabulary instead.
        fresh.createdAt = Calendar.current.date(byAdding: .hour, value: -3, to: Date()) ?? Date()

        let waiting = Opportunity.preview(
            title: "Cedar Ridge rail replacement", contactName: "Cedar Ridge HOA",
            stage: .negotiation, estimatedValue: 31_000,
            daysInStage: 4, lastActivityDaysAgo: 1, nextFollowUpDaysFromNow: 3
        )
        waiting.address = "700 Cedar Ridge Way, Surrey BC"

        return [overdue, dueToday, fresh, waiting]
    }

    /// The delegate grant: `assigned` view + edit, no convert, and — for the
    /// populated sheet — no create, so no nav CTA is implied.
    private func delegateStore(canCreate: Bool = false) -> PermissionStore {
        PermissionStore.previewWithAssignedAccess(canCreate: canCreate)
    }

    /// `isLoading` / `loadError` / `lastSyncLabel` are the three inputs the
    /// sheet's state branch reads (spec §3.5). Set here rather than through a
    /// fetch: the branch is what is under test, not the loader that trips it.
    @ViewBuilder
    private func hosted(
        _ opportunities: [Opportunity],
        store: PermissionStore,
        canCreate: Bool,
        isLoading: Bool = false,
        loadError: String? = nil,
        lastSyncLabel: String? = nil
    ) -> some View {
        DaySheetHost(
            viewModel: {
                let viewModel = PipelineViewModel.previewLoaded(opportunities: opportunities)
                viewModel.isLoading = isLoading
                viewModel.loadError = loadError
                return viewModel
            }(),
            committer: .preview(),
            canCreate: canCreate,
            lastSyncLabel: lastSyncLabel
        )
        .frame(width: Self.sheetWidth)
        .environmentObject(store)
    }

    // MARK: - Renders

    /// All three groups, each collapsed to the rows that belong in it: the
    /// count line, `// YOUR MOVE · 2` over a late and a due-today lead, `// NEW`
    /// over the one that just landed, `// WAITING` over the parked one.
    func testRenderPopulatedDaySheet() {
        snapshot("day_sheet_populated", size: CGSize(width: Self.sheetWidth, height: 760)) {
            hosted(assignedDay(), store: delegateStore(), canCreate: false)
        }
    }

    /// Nothing assigned: the zero, the label, and — because this operator can
    /// create — the one CTA that resolves it.
    func testRenderEmptyDaySheet() {
        snapshot("day_sheet_empty", size: CGSize(width: Self.sheetWidth, height: 420)) {
            hosted([], store: delegateStore(canCreate: true), canCreate: true)
        }
    }

    /// First launch, fetch in flight: three row-shaped skeletons at the height
    /// the real cards land at, so the sheet does not reflow when it answers.
    /// Skeletons show ONLY while there is nothing yet — a refresh over live
    /// rows updates them in place (`loadData(silent:)`).
    func testRenderLoadingDaySheet() {
        snapshot("day_sheet_loading", size: CGSize(width: Self.sheetWidth, height: 420)) {
            hosted([], store: delegateStore(), canCreate: false, isLoading: true)
        }
    }

    /// Offline with a cache: the whole day still renders, headed by
    /// `SYS :: OFFLINE — LAST SYNC 07:12` in tan. Nothing is withheld and
    /// nothing is disabled — the reads are real, they are just not this
    /// minute's copy.
    func testRenderOfflineDaySheet() {
        snapshot("day_sheet_offline_sys", size: CGSize(width: Self.sheetWidth, height: 760)) {
            hosted(assignedDay(),
                   store: delegateStore(),
                   canCreate: false,
                   lastSyncLabel: "07:12")
        }
    }

    /// The fetch failed and there is nothing cached — the one dead end on this
    /// surface, and it ships with the way out.
    func testRenderErrorDaySheet() {
        snapshot("day_sheet_error", size: CGSize(width: Self.sheetWidth, height: 420)) {
            hosted([],
                   store: delegateStore(),
                   canCreate: false,
                   loadError: "The request timed out.")
        }
    }

    /// The fetch failed but the cache holds: the error must NOT preempt the
    /// day. Same render as offline — rows plus the `SYS ::` line — with no
    /// trace of `// ERROR — LEADS UNAVAILABLE`.
    func testRenderErrorWithCacheDaySheet() {
        snapshot("day_sheet_error_with_cache", size: CGSize(width: Self.sheetWidth, height: 760)) {
            hosted(assignedDay(),
                   store: delegateStore(),
                   canCreate: false,
                   loadError: "The request timed out.",
                   lastSyncLabel: "07:12")
        }
    }
}

// MARK: - Host

/// Owns the bindings the sheet reads (one open card, one scroll target) so the
/// view under test is constructed exactly as `LeadsTabView` constructs it.
private struct DaySheetHost: View {

    let viewModel: PipelineViewModel
    let committer: LeadMilestoneCommitter
    let canCreate: Bool
    /// The tab computes this (offline, or a failed fetch, with a stamp to
    /// name); the sheet only renders it.
    var lastSyncLabel: String?

    @State private var expandedLeadId: String?
    @State private var scrollTarget: String?

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            LeadDaySheetView(
                viewModel: viewModel,
                committer: committer,
                expandedLeadId: $expandedLeadId,
                scrollTarget: $scrollTarget,
                operatorId: "preview-user",
                lastSyncLabel: lastSyncLabel,
                onFullLead: { _ in },
                onOpenDeck: { _, _ in },
                onStage: { _, _ in },
                onWon: { _ in },
                onLost: { _ in },
                onArchive: { _ in },
                onDiscard: { _ in },
                onAddLead: canCreate ? {} : nil
            )
        }
    }
}
#endif
