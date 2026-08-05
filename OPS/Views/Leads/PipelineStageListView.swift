//
//  PipelineStageListView.swift
//  OPS
//
//  The stage browser — pushed from the LEADS command band's stage bar
//  (BY STAGE ▸). The band picks the entry stage; from there the operator
//  browses every stage IN PLACE, without going back and pushing again.
//
//  Composition (top → bottom):
//
//      Atmosphere(tone: derivedFromSelectedStage)
//      ┌────────────────────────────────────────────────┐
//      │  ← LEADS                                       │ ← StageListNavBar
//      │  NEW LEAD · 3  QUALIFYING · 1  QUOTING · 4  …  │ ← stage tab row
//      ├────────────────────────────────────────────────┤
//      │  QUOTING                              04 LEADS │ ← titleRow
//      │                                                │
//      │  [LeadTriageCard]   ← stale-first, 8pt gaps    │
//      │  [LeadTriageCard]                              │
//      │  …                                             │
//      └────────────────────────────────────────────────┘
//
//  The tab row (console redesign 2026-08-05, spec §7 / MOBILE.md §4.2) carries
//  the six open stages and then WON and LOST — the archive was previously
//  unreachable on iOS at all, though the card has always known how to render a
//  closed lead. Active tab: `text` plus a 2pt white underline, never accent.
//
//  The row is the SAME LeadTriageCard the LeadsTabView chase queue renders, so
//  a lead looks identical wherever it surfaces. A row tap routes up to
//  LeadsTabView's single LeadDetail destination; the on-card LOG / ADVANCE /
//  WON / LOST actions and the long-press EDIT / ARCHIVE menu route their sheets
//  up through `onRequestSheet` / `onLeadTap`, gated by permission + stage.
//
//  Won/Lost caveat: PipelineViewModel.bucketOf / verbFor / toneFor classify
//  OPEN leads only. The card is handed `bucket: .all` (per-lead urgency) and
//  handles terminal stages itself — a won/lost lead renders its outcome strip
//  and hides the mutating quick actions rather than misclassifying as a verb.
//
//  Plan:   docs/plans/2026-08-05-leads-console-redesign.md Task 8
//  Spec:   docs/superpowers/specs/2026-08-05-leads-console-redesign-design.md §7
//

import SwiftUI

struct PipelineStageListView: View {
    @ObservedObject var viewModel: PipelineViewModel

    /// Routes a row tap up to LeadsTabView's root `detailLead` destination.
    /// Keeping one LeadDetail destination avoids nested SwiftUI shadowing.
    var onLeadTap: (Opportunity) -> Void = { _ in }
    /// Routes a sheet request up to LeadsTabView, which owns `activeSheet`.
    /// Backs the LOG glyph and LeadDetailView's mark-lost / edit / convert
    /// closures — all of those present a `LeadsSheet`.
    var onRequestSheet: (LeadsSheet) -> Void = { _ in }
    /// Assignee tokens by lead id, resolved by the console from its roster —
    /// one source for the whole surface, so a lead reads the same name here as
    /// it does in the queue. Empty when the assignment gate is closed.
    var assigneeIndex: [String: String] = [:]

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss
    @State private var discardTarget: Opportunity?
    /// Lead whose comeback date is being adjusted (ComebackChooserSheet).
    @State private var comebackTarget: Opportunity?
    /// Pending ARCHIVE confirmation (OPSConfirm).
    @State private var archiveTarget: Opportunity?

    /// The stage on screen. Seeded from the pushed stage, then owned here — a
    /// tab switch swaps the list in place rather than pushing a second screen,
    /// so browsing eight stages costs one navigation, not eight.
    @State private var selectedStage: PipelineStage

    init(
        stage: PipelineStage,
        viewModel: PipelineViewModel,
        onLeadTap: @escaping (Opportunity) -> Void = { _ in },
        onRequestSheet: @escaping (LeadsSheet) -> Void = { _ in },
        assigneeIndex: [String: String] = [:]
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.onLeadTap = onLeadTap
        self.onRequestSheet = onRequestSheet
        self.assigneeIndex = assigneeIndex
        _selectedStage = State(initialValue: stage)
    }

    /// Every stage the browser can reach: the open funnel, then the archive.
    private static let browsableStages: [PipelineStage] = PipelineStage.openStages + [.won, .lost]

    /// The selected stage's leads. Open stages keep the view model's
    /// stale-first order — staleness is the thing to act on. A closed stage is
    /// an archive, where nothing is stale and the only useful order is the one
    /// that puts the most recent result first.
    private var leads: [Opportunity] {
        let rows = viewModel.opportunities(in: selectedStage)
        guard selectedStage.isTerminal else { return rows }
        return rows.sorted { lhs, rhs in
            let left = lhs.actualCloseDate ?? lhs.createdAt
            let right = rhs.actualCloseDate ?? rhs.createdAt
            if left != right { return left > right }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var leadAccessPolicy: LeadAccessPolicy { permissionStore.leadAccessPolicy }
    private func canEdit(_ lead: Opportunity) -> Bool {
        leadAccessPolicy.can(.edit, assignedTo: lead.assignedTo)
    }
    private func canConvert(_ lead: Opportunity) -> Bool {
        leadAccessPolicy.can(.convert, assignedTo: lead.assignedTo)
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()
            Atmosphere(tone: atmosphereTone)

            VStack(spacing: 0) {
                StageListNavBar(onBack: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                })

                stageTabs

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleRow
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.top, OPSStyle.Layout.spacing2_5)
                            .padding(.bottom, 14)

                        listContent
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, 100)   // clears the tab bar
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarHidden(true)
        .leadDiscardFlow(
            target: $discardTarget
        )
        .leadArchiveFlow(target: $archiveTarget)
        .sheet(item: $comebackTarget) { lead in
            ComebackChooserSheet(lead: lead, viewModel: viewModel)
        }
    }

    // MARK: - Stage tabs (spec §7)

    /// Pinned under the nav bar — the row stays put while the list scrolls, so
    /// the operator never loses their place in the funnel.
    private var stageTabs: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Self.browsableStages, id: \.self) { stage in
                            stageTab(stage).id(stage)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                }
                // Fades both ends so a half-shown tab reads as "there is more"
                // instead of a clipped word.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.05),
                            .init(color: .black, location: 0.95),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .onAppear { proxy.scrollTo(selectedStage, anchor: .center) }
                .onChange(of: selectedStage) { _, stage in
                    withAnimation(OPSStyle.Animation.standard) {
                        proxy.scrollTo(stage, anchor: .center)
                    }
                }
            }

            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: 1)
        }
    }

    private func stageTab(_ stage: PipelineStage) -> some View {
        let isActive = stage == selectedStage
        let count = viewModel.count(in: stage)
        return Button {
            select(stage)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text(stage.displayName)
                    Text("·").foregroundColor(OPSStyle.Colors.textMute)
                    Text("\(count)").monospacedDigit()
                }
                .font(.custom("JetBrainsMono-Medium", size: 10))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundColor(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)

                // White, never accent (MOBILE.md §4.2).
                Rectangle()
                    .fill(isActive ? OPSStyle.Colors.text : Color.clear)
                    .frame(height: OPSStyle.Layout.Border.thick)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.displayName), \(count) leads")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func select(_ stage: PipelineStage) {
        guard stage != selectedStage else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(OPSStyle.Animation.standard) { selectedStage = stage }
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(selectedStage.displayName)
                .font(OPSStyle.Typography.screenTitle(for: selectedStage.displayName))
                .foregroundColor(OPSStyle.Colors.text)
                .textCase(.uppercase)

            Spacer()

            Text("\(String(format: "%02d", leads.count)) LEADS")
                .font(OPSStyle.Typography.nanoLabel)
                .foregroundColor(OPSStyle.Colors.text3)
                .kerning(0.8)
                .textCase(.uppercase)
                .monospacedDigit()
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        if leads.isEmpty {
            StageEmpty(stage: selectedStage)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(leads) { lead in
                    card(for: lead)
                }
            }
        }
    }

    /// The unified chase-queue card — same component as the LeadsTabView queue.
    /// `bucket: .all` lets the card derive each lead's own urgency tone / verb /
    /// due tag from its state; a terminal stage (won/lost) renders its outcome
    /// and hides the mutating quick actions. Edit + archive live in the
    /// long-press context menu, matching the queue's per-card affordances.
    private func card(for lead: Opportunity) -> some View {
        LeadTriageCard(
            lead: lead,
            viewModel: viewModel,
            bucket: .all,
            canEdit: canEdit(lead),
            canConvert: canConvert(lead),
            assigneeLabel: assigneeIndex[lead.id],
            onTap:     { onLeadTap(lead) },
            onLog:     { onRequestSheet(.log(lead)) },
            onHandled: { markHandled(lead) },
            onSendFollowUp: { sendFollowUp(lead) },
            onAdjust:  { comebackTarget = lead },
            onStage:   { stage in setStage(lead, to: stage) },
            onWon:     { onRequestSheet(.convert(lead)) },
            onLost:    { onRequestSheet(.lost(lead)) },
            onArchive: { requestArchive(lead) },
            onDiscard: { discardTarget = lead }
        )
        .contextMenu {
            LeadCardContextMenu(
                lead: lead,
                canManage: canEdit(lead),
                onEdit: { onRequestSheet(.edit(lead)) },
                onArchive: { requestArchive(lead) },
                onDiscard: { discardTarget = lead }
            )
        }
    }

    // MARK: - Actions (mirror LeadsTabView — one chase grammar everywhere)

    /// HANDLED ✓ — flip the ball; the toast voices the comeback with ADJUST.
    private func markHandled(_ lead: Opportunity) {
        guard canEdit(lead) else { return }
        Task {
            do {
                let comeback = try await viewModel.markHandled(opportunityId: lead.id)
                ToastCenter.shared.present(Toast(
                    label: "// HANDLED · BACK \(LeadChaseStrip.comebackLabel(comeback))",
                    tone: .success,
                    autoDismissAfter: 6,
                    action: ToastAction(label: "ADJUST", accessibilityLabel: "Adjust comeback date") {
                        comebackTarget = lead
                    }
                ))
            } catch {
                ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            }
        }
    }

    /// Provider-backed stock reply for a due/overdue lead. No optimistic
    /// HANDLED mutation: the canonical server result owns the visible move.
    private func sendFollowUp(_ lead: Opportunity) {
        guard canEdit(lead), viewModel.canSendFollowUp(for: lead) else { return }
        Task {
            let outcome = await viewModel.sendFollowUp(opportunityId: lead.id)
            ToastCenter.shared.present(
                Feedback.Lead.followUpResult(outcome) {
                    comebackTarget = lead
                }
            )
        }
    }

    /// Direct stage pick from the status menu (open stages only).
    private func setStage(_ lead: Opportunity, to stage: PipelineStage) {
        guard canEdit(lead), stage != lead.stage else { return }
        Task {
            do {
                try await viewModel.moveToStage(
                    opportunityId: lead.id,
                    to: stage,
                    userId: dataController.currentUser?.id
                )
                ToastCenter.shared.present(Feedback.Lead.stageSet)
            } catch {
                ToastCenter.shared.present(
                    Toast(label: Feedback.Err.saveFailed, tone: .error)
                )
            }
        }
    }

    /// ARCHIVE — hands off to the shared archive flow (spec §6). All three
    /// lead surfaces raise the same sheet, write the same contract, and offer
    /// the same undo.
    private func requestArchive(_ lead: Opportunity) {
        guard canEdit(lead) else { return }
        archiveTarget = lead
    }

    // MARK: - Helpers

    /// Atmosphere hue per stage — mirrors `LeadDetailView.atmosphereTone`.
    /// Re-derives on every tab switch, so the screen's whole temperature
    /// follows the stage the operator is standing in.
    private var atmosphereTone: Atmosphere.Tone {
        switch selectedStage {
        case .won:                              return .olive
        case .lost:                             return .rose
        case .quoted, .followUp, .negotiation:  return .tan
        case .newLead, .qualifying, .quoting, .discarded:  return .steel
        }
    }
}

// MARK: - StageListNavBar (private)

/// Compact nav bar above the scroll view. Custom back chevron + LEADS label,
/// matching `LeadDetailView`'s `DetailNavBar`. The stage name is the screen
/// title, rendered in the scrolling content (`titleRow`) per the LEADS-tab
/// header idiom. Swipe-back is preserved by the NavigationStack.
private struct StageListNavBar: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .regular))
                    Text("LEADS")
                        .font(OPSStyle.Typography.miniLabel)
                        .fontWeight(.semibold)
                        .kerning(1.4)
                        .textCase(.uppercase)
                }
                .foregroundColor(OPSStyle.Colors.text2)
                .padding(.leading, OPSStyle.Layout.spacing1)
                .padding(.trailing, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 44)   // meet the 44pt touch floor (review W-10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Back to leads")

            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(height: 52)
    }
}

// MARK: - StageEmpty (private)

/// Empty-stage state — `00` + `// — NO …` mono caption. Mirrors the
/// `BucketEmpty` treatment on `LeadsTabView`.
private struct StageEmpty: View {
    let stage: PipelineStage

    var body: some View {
        VStack(spacing: 10) {
            Text("00")
                .font(.custom("Mohave-Light", size: 32))
                .foregroundColor(OPSStyle.Colors.text3)
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(message)
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
            .font(OPSStyle.Typography.metadata)
            .kerning(1.8)
            .textCase(.uppercase)
        }
    }

    private var message: String {
        switch stage {
        case .won:  return "— NO WINS YET"
        case .lost: return "— NO LOST LEADS"
        default:    return "— NO LEADS IN \(stage.displayName)"
        }
    }
}

// MARK: - Previews

#if DEBUG
/// Entered at QUOTING — the tab row centres the active stage, steel atmosphere.
#Preview("PipelineStageListView / quoting tab") {
    NavigationStack {
        PipelineStageListView(stage: .quoting, viewModel: .previewLoaded())
    }
    .leadsPreviewEnvironment()
}

/// Entered at WON — the archive, newly reachable: olive atmosphere, outcome
/// strips on every card, close-date order.
#Preview("PipelineStageListView / won tab") {
    NavigationStack {
        PipelineStageListView(stage: .won, viewModel: .previewLoaded())
    }
    .leadsPreviewEnvironment()
}

#Preview("PipelineStageListView / empty") {
    NavigationStack {
        PipelineStageListView(stage: .negotiation, viewModel: .previewLoaded(opportunities: []))
    }
    .leadsPreviewEnvironment()
}
#endif
