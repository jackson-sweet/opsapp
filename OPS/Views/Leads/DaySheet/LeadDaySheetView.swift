//
//  LeadDaySheetView.swift
//  OPS
//
//  The delegate's LEADS surface: his leads, in the order whose-move-is-it puts
//  them, each one openable in place. It is what an `assigned` view scope gets
//  instead of the owner's triage console — a day sheet, not a command center.
//
//  This screen owns NO data. `LeadsTabView` still runs the one `.task` load,
//  the nine `Lead*Success` listeners, realtime and the foreground catch-up
//  against the SHARED `PipelineViewModel`; the day sheet consumes that view
//  model and re-derives its three groups through `DaySheetViewModel.groups`.
//  There is exactly one fetch, one cadence engine, and one set of buckets on
//  the LEADS tab whichever surface is rendering.
//
//  ── The freeze ──────────────────────────────────────────────────────────────
//  While a milestone's 5-second undo window is open the sheet renders from the
//  groups it held at PRESS time (`LeadMilestoneCommitter`'s documented
//  contract). The stage flip is optimistic and immediate, so a sheet that
//  re-derived on every change would slide the card out of YOUR MOVE the instant
//  the thumb lifted and take UNDO with it. Captured before the press, released
//  when `pending` clears.
//  ───────────────────────────────────────────────────────────────────────────
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §3
//

import SwiftUI
import UIKit

struct LeadDaySheetView: View {

    /// The tab's view model — the one loader for the whole LEADS tab.
    @ObservedObject var viewModel: PipelineViewModel
    /// The one open undo window, shared by every card on the sheet.
    @ObservedObject var committer: LeadMilestoneCommitter
    /// One card open at a time; the tab holds it so a deep link can set it.
    @Binding var expandedLeadId: String?
    /// A lead to reveal (deep link). Consumed on arrival: expand, scroll, clear.
    @Binding var scrollTarget: String?

    /// Operator identity for the milestone stamp's activity row.
    var operatorId: String?
    /// `SYS :: OFFLINE — LAST SYNC <T>` when non-nil — set by the tab when the
    /// sheet is backed by the cache rather than a fetch that just succeeded.
    var lastSyncLabel: String?

    var onFullLead: (Opportunity) -> Void
    /// The lead rides along so the full-screen builder can be titled with the
    /// job it belongs to.
    var onOpenDeck: (Opportunity, DeckDesign) -> Void
    var onStage: (Opportunity, PipelineStage) -> Void
    var onWon: (Opportunity) -> Void
    var onLost: (Opportunity) -> Void
    var onArchive: (Opportunity) -> Void
    var onDiscard: (Opportunity) -> Void
    /// Nil when this operator cannot create leads — the empty state then has no
    /// CTA rather than a button that refuses.
    var onAddLead: (() -> Void)?

    /// Read the INJECTED store, never `PermissionStore.shared`: the shared one
    /// fails closed before hydration, which would empty the sheet on a
    /// cold-launch race and in every preview.
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Non-nil for the length of an undo window — see the freeze note above.
    @State private var frozenGroups: DaySheetViewModel.Groups?

    // MARK: - Groups

    private var policy: LeadAccessPolicy { permissionStore.leadAccessPolicy }

    private var liveGroups: DaySheetViewModel.Groups {
        DaySheetViewModel.groups(from: viewModel.triageBuckets,
                                 policy: policy,
                                 now: Date())
    }

    private var groups: DaySheetViewModel.Groups { frozenGroups ?? liveGroups }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    headerZone
                    content
                }
                // `spacing3`, not the console's `spacing3_5`: the day-sheet row
                // carries a 56pt tile and two 44pt verbs the triage card does
                // not, and those four points are the difference between a stage
                // chip that renders and one the fit ladder has to drop.
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing1)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                // Same silent merge reload the realtime / foreground triggers
                // use — rows update in place, no skeleton over live content.
                await viewModel.loadData(silent: true)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                reveal(target, using: proxy)
            }
        }
        .onChange(of: committer.pending) { _, pending in
            // The window closed (expired, undone, or refused) — the sheet is
            // free to re-derive, which is when a stamped card finds its new
            // group.
            if pending == nil { frozenGroups = nil }
        }
    }

    // MARK: - Header zone

    private var headerZone: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            countLine
            if let lastSyncLabel {
                offlineLine(lastSyncLabel)
            }
        }
        .padding(.bottom, OPSStyle.Layout.spacing1)
    }

    /// `// N LEADS · M YOUR MOVE` (spec §8). The YOUR MOVE half is dropped when
    /// nothing is waiting on him — a count of zero is not news.
    private var countLine: some View {
        HStack(spacing: 0) {
            Text("// ")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text("\(groups.total)")
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.text)
            Text(" LEADS")
                .foregroundColor(OPSStyle.Colors.text)
            if groups.yourMoveCount > 0 {
                Text(" · ")
                    .foregroundColor(OPSStyle.Colors.text3)
                Text("\(groups.yourMoveCount)")
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.text3)
                Text(" YOUR MOVE")
                    .foregroundColor(OPSStyle.Colors.text3)
            }
        }
        .font(OPSStyle.Typography.miniLabelBold)
        .tracking(1.6)
        .accessibilityElement(children: .combine)
    }

    /// `SYS :: OFFLINE — LAST SYNC 07:12` (spec §3.5). Tan, not rose: the sheet
    /// in front of him is real work, just not this minute's copy of it.
    private func offlineLine(_ label: String) -> some View {
        Text("SYS :: OFFLINE — LAST SYNC \(label)")
            .font(OPSStyle.Typography.miniLabel)
            .tracking(1.2)
            .foregroundColor(OPSStyle.Colors.tan)
            .monospacedDigit()
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && groups.total == 0 {
            skeleton
        } else if groups.total == 0 && viewModel.loadError != nil && lastSyncLabel == nil {
            errorState
        } else if groups.total == 0 {
            emptyState
        } else {
            groupSections
        }
    }

    /// Empty groups collapse ENTIRELY, header included (spec §3.2). There is no
    /// all-caught-up state — a day with nothing but parked leads is simply a
    /// sheet that starts at `// WAITING`.
    @ViewBuilder
    private var groupSections: some View {
        section("YOUR MOVE", rows: groups.yourMove)
        section("NEW", rows: groups.new)
        section("WAITING", rows: groups.waiting)
    }

    @ViewBuilder
    private func section(_ label: String, rows: [DaySheetViewModel.Row]) -> some View {
        if !rows.isEmpty {
            sectionHeader(label, count: rows.count)
            ForEach(rows) { row in
                card(for: row)
                    .id(row.id)
            }
        }
    }

    /// The console's queue-header geometry, in the day sheet's quieter voice:
    /// label, rule, count. Neutral throughout — urgency is the row's job, and a
    /// colored header would shout it twice.
    private func sectionHeader(_ label: String, count: Int) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(label)
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .font(OPSStyle.Typography.nanoLabel)
            .fontWeight(.semibold)
            .tracking(1.4)

            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: OPSStyle.Layout.Border.standard)

            Text("\(count)")
                .font(OPSStyle.Typography.nanoLabel)
                .fontWeight(.semibold)
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()
        }
        .padding(.top, OPSStyle.Layout.spacing1)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Card

    private func card(for row: DaySheetViewModel.Row) -> some View {
        let lead = row.lead
        let canEdit = policy.can(.edit, assignedTo: lead.assignedTo)
        let canConvert = policy.can(.convert, assignedTo: lead.assignedTo)
        return DaySheetLeadCard(
            row: stampable(row, canConvert: canConvert),
            canEdit: canEdit,
            canConvert: canConvert,
            isExpanded: expandedLeadId == row.id,
            onExpand: { toggleExpansion(row.id) },
            onMilestone: { milestone in
                press(milestone, on: lead, canEdit: canEdit)
            },
            committer: committer,
            onFullLead: { onFullLead(lead) },
            onOpenDeck: { onOpenDeck(lead, $0) },
            onStage: { onStage(lead, $0) },
            onWon: { onWon(lead) },
            onLost: { onLost(lead) },
            onArchive: { onArchive(lead) },
            onDiscard: { onDiscard(lead) }
        )
    }

    /// WON is a conversion, not a stamp: the iOS repository refuses a direct
    /// `.won` stage write and the server's conversion RPC refuses an actor
    /// without convert scope. So an edit-only delegate gets no WON button —
    /// his stamped run of the sheet ends at QUOTE SENT, and the win is closed
    /// by whoever holds the grant. Showing a button that can only fail would be
    /// worse than not showing it.
    private func stampable(
        _ row: DaySheetViewModel.Row,
        canConvert: Bool
    ) -> DaySheetViewModel.Row {
        guard row.milestone == .won, !canConvert else { return row }
        return DaySheetViewModel.Row(lead: row.lead, urgency: row.urgency, milestone: nil)
    }

    // MARK: - Interaction

    /// One card open at a time — opening a second closes the first, so the
    /// sheet never becomes a wall of expanded cards to scroll past.
    private func toggleExpansion(_ id: String) {
        if expandedLeadId == id {
            expandedLeadId = nil
        } else {
            expandedLeadId = id
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// The one write on this screen. WON routes out to the guarded conversion
    /// flow; everything else stamps through the committer, which owns the
    /// haptic, the queue and the undo window.
    private func press(_ milestone: LeadMilestone, on lead: Opportunity, canEdit: Bool) {
        guard milestone != .won else {
            onWon(lead)
            return
        }
        // Freeze BEFORE the press: the stage flip lands before `pending`
        // publishes, so a snapshot taken any later has already moved the card.
        frozenGroups = liveGroups
        Task {
            let outcome = await committer.press(
                milestone,
                lead: lead,
                userId: operatorId,
                canEdit: canEdit
            )
            switch outcome {
            case .committed, .queued:
                // The window is open; `pending` clearing releases the freeze.
                break
            case .refused, .requiresWonFlow:
                frozenGroups = nil
            }
        }
    }

    /// Deep link: open the lead in place rather than pushing a screen over the
    /// sheet — the row he tapped a notification for is the row he lands on.
    private func reveal(_ id: String, using proxy: ScrollViewProxy) {
        expandedLeadId = id
        withAnimation(OPSStyle.Animation.page) {
            proxy.scrollTo(id, anchor: .top)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scrollTarget = nil
    }

    // MARK: - States

    /// Three rows of row-shaped nothing (MOBILE.md §10): same 80pt height and
    /// panel radius the real cards land at, so the sheet does not reflow when
    /// the fetch answers.
    private var skeleton: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonRow(reduceMotion: reduceMotion)
            }
        }
        .padding(.top, OPSStyle.Layout.spacing1)
        .accessibilityLabel("Loading leads")
    }

    /// `0` + `// NO LEADS ASSIGNED` (spec §3.5). No illustration, no coaching.
    /// The CTA appears only for an operator who can actually resolve it.
    private var emptyState: some View {
        VStack(spacing: 0) {
            // No `.monospacedDigit()`: it substitutes a mono face and the
            // Mohave figure MOBILE.md §10 asks for never renders. A lone `0`
            // has nothing to align with anyway.
            Text("0")
                .font(OPSStyle.Typography.emptyStateFigure)
                .foregroundColor(OPSStyle.Colors.text3)

            Text("// NO LEADS ASSIGNED")
                .font(OPSStyle.Typography.miniLabel)
                .tracking(1.6)
                .foregroundColor(OPSStyle.Colors.textMute)
                .padding(.top, OPSStyle.Layout.spacing2_5)

            if let onAddLead {
                OutlinedActionButton(label: "NEW LEAD",
                                     tone: OPSStyle.Colors.opsAccent,
                                     action: onAddLead)
                    .padding(.top, OPSStyle.Layout.spacing4)
                    .frame(maxWidth: OPSStyle.Layout.emptyStateActionWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.vertical, OPSStyle.Layout.emptyStatePadding)
    }

    /// Nothing fetched and nothing cached — the only true dead end on this
    /// surface, and it ships with the way out (spec §3.5, MOBILE.md §10).
    private var errorState: some View {
        VStack(spacing: 0) {
            Text("// ERROR — LEADS UNAVAILABLE")
                .font(OPSStyle.Typography.miniLabel)
                .tracking(1.4)
                .foregroundColor(OPSStyle.Colors.rose)
                .multilineTextAlignment(.center)

            OutlinedActionButton(label: "RETRY", tone: OPSStyle.Colors.rose) {
                Task { await viewModel.loadData() }
            }
            .padding(.top, OPSStyle.Layout.spacing4)
            .frame(maxWidth: OPSStyle.Layout.emptyStateActionWidth)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.vertical, OPSStyle.Layout.emptyStatePadding)
    }
}

// MARK: - Skeleton row

/// One pulsing row-shaped placeholder. MOBILE.md §10: white 0.06 → 0.03,
/// 1.5s ease-in-out, radius of the element being loaded. Reduced motion holds
/// it still rather than swapping in a different animation.
private struct SkeletonRow: View {

    let reduceMotion: Bool

    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
            .fill(OPSStyle.Colors.fillNeutralDim)
            .frame(height: DaySheetLeadRow.minHeight)
            .opacity(dim ? OPSStyle.Animation.skeletonPulseOpacity : 1)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: OPSStyle.Animation.durationSkeletonPulse)
                        .repeatForever(autoreverses: true),
                value: dim
            )
            .onAppear { dim = true }
    }
}

// MARK: - Outlined action button

/// The one CTA shape this screen uses — outlined, tinted, 48pt. DESIGN.md's
/// primary button in its accent form for NEW LEAD and its rose form for RETRY
/// (MOBILE.md §10 error pattern).
private struct OutlinedActionButton: View {

    let label: String
    let tone: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(OPSStyle.Typography.buttonLabel)
                .kerning(0.27)
                .textCase(.uppercase)
                .foregroundColor(tone)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.inputHeight)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(tone.opacity(OPSStyle.Layout.Opacity.subtle))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(tone, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Previews

#if DEBUG
private struct LeadDaySheetPreview: View {

    let opportunities: [Opportunity]
    let canCreate: Bool

    @State private var expandedLeadId: String?
    @State private var scrollTarget: String?

    var body: some View {
        let viewModel = PipelineViewModel.previewLoaded(opportunities: opportunities)
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            LeadDaySheetView(
                viewModel: viewModel,
                committer: LeadMilestoneCommitter.preview(),
                expandedLeadId: $expandedLeadId,
                scrollTarget: $scrollTarget,
                operatorId: "preview-user",
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
        .environmentObject(PermissionStore.previewWithAssignedAccess())
        .environmentObject(DataController())
        .environmentObject(AppState())
        .environmentObject(LocationManager())
        .preferredColorScheme(.dark)
    }
}

#Preview("LeadDaySheetView / populated") {
    LeadDaySheetPreview(opportunities: Opportunity.previewMix, canCreate: false)
}

#Preview("LeadDaySheetView / empty") {
    LeadDaySheetPreview(opportunities: [], canCreate: true)
}
#endif
