//
//  PipelineStageListView.swift
//  OPS
//
//  Filtered single-stage lead list — pushed from the LEADS-tab pipeline
//  footer ("// BY STAGE"). Fulfils the per-stage drill committed in
//  design-intent §23 #5 and closes audit CRITICAL #6 (the footer's dead
//  drill-down) for both open AND closed (won/lost) stages.
//
//  Composition (top → bottom):
//
//      Atmosphere(tone: derivedFromStage)
//      ┌────────────────────────────────────────────────┐
//      │  ← LEADS                                       │ ← StageListNavBar
//      ├────────────────────────────────────────────────┤
//      │  QUOTING                              04 LEADS │ ← titleRow
//      │                                                │
//      │  [LeadActionCard]   ← stale-first, 8pt gaps    │
//      │  [LeadActionCard]                              │
//      │  …                                             │
//      └────────────────────────────────────────────────┘
//
//  A row tap routes up to LeadsTabView's single LeadDetail destination.
//  LeadDetailView's mark-lost / edit / convert closures present sheets owned
//  by LeadsTabView's `activeSheet`, so they are routed up through
//  `onRequestSheet`. The LOG / MORE / ADVANCE quick-glyphs mirror the
//  LeadsTabView triage-queue wiring, gated by permissions and terminal stage.
//
//  Won/Lost caveat: PipelineViewModel.bucketOf / verbFor / toneFor classify
//  OPEN leads only — a closed lead would fall through to "CHECK IN" /
//  neutral. For a terminal stage the row verb is the stage status (WON /
//  LOST) at neutral tone.
//
//  Plan:   docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §2.1 Q2
//  Intent: docs/superpowers/specs/2026-05-19-leads-tab-design-intent.md §23 #5
//

import SwiftUI

struct PipelineStageListView: View {
    let stage: PipelineStage
    @ObservedObject var viewModel: PipelineViewModel

    /// Routes a row tap up to LeadsTabView's root `detailLead` destination.
    /// Keeping one LeadDetail destination avoids nested SwiftUI shadowing.
    var onLeadTap: (Opportunity) -> Void = { _ in }
    /// Routes a sheet request up to LeadsTabView, which owns `activeSheet`.
    /// Backs the LOG glyph and LeadDetailView's mark-lost / edit / convert
    /// closures — all of those present a `LeadsSheet`.
    var onRequestSheet: (LeadsSheet) -> Void = { _ in }

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss

    /// Drives the MORE confirmation dialog.
    @State private var moreForLead: Opportunity?

    /// This stage's leads — already sorted stale-first by the view model.
    private var leads: [Opportunity] { viewModel.opportunities(in: stage) }
    private var canManage: Bool { permissionStore.can("pipeline.manage") }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()
            Atmosphere(tone: atmosphereTone)

            VStack(spacing: 0) {
                StageListNavBar(onBack: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                })

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
        .confirmationDialog(
            "Actions",
            isPresented: moreSheetPresented,
            presenting: moreForLead
        ) { lead in
            if canManage {
                Button("MARK WON →") { onRequestSheet(.convert(lead)) }
                Button("MARK LOST", role: .destructive) { onRequestSheet(.lost(lead)) }
                Button("EDIT") { onRequestSheet(.edit(lead)) }
                Button("ARCHIVE") {
                    Task { try? await viewModel.archive(opportunityId: lead.id) }
                }
            }
            Button("CANCEL", role: .cancel) {}
        }
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(stage.displayName)
                .font(OPSStyle.Typography.display)
                .foregroundColor(OPSStyle.Colors.text)
                .textCase(.uppercase)

            Spacer()

            Text("\(String(format: "%02d", leads.count)) LEADS")
                .font(.custom("JetBrainsMono-Regular", size: 9.5))
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
            StageEmpty(stage: stage)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(leads) { lead in
                    LeadActionCard(
                        opportunity: lead,
                        verb: verb(for: lead),
                        tone: tone(for: lead),
                        showsLog: canManage,
                        showsMore: canManage && !stage.isTerminal,
                        showsAdvance: canManage && !stage.isTerminal,
                        onTap:     { onLeadTap(lead) },
                        onLog:     { onRequestSheet(.log(lead)) },
                        onMore:    { moreForLead = lead },
                        onAdvance: { advance(lead) }
                    )
                }
            }
        }
    }

    // MARK: - Per-lead verb + tone
    //
    // PipelineViewModel.verbFor / toneFor are correct only for OPEN leads —
    // they bucketise by urgency. A won/lost lead would misclassify as
    // "CHECK IN" / neutral, so a terminal stage uses the stage status as the
    // row verb at neutral tone.

    private func verb(for lead: Opportunity) -> String {
        stage.isTerminal ? stage.displayName : viewModel.verbFor(lead, bucket: .all)
    }

    private func tone(for lead: Opportunity) -> PipelineViewModel.UrgencyTone {
        stage.isTerminal ? .neutral : viewModel.toneFor(.all, lead: lead)
    }

    // MARK: - Actions

    /// Advances a lead to the next stage. No-op for terminal stages — mirrors
    /// `LeadsTabView.advance`.
    private func advance(_ lead: Opportunity) {
        guard canManage, !lead.stage.isTerminal, let next = lead.stage.next else { return }
        Task {
            try? await viewModel.moveToStage(
                opportunityId: lead.id,
                to: next,
                userId: dataController.currentUser?.id
            )
        }
    }

    // MARK: - Helpers

    private var moreSheetPresented: Binding<Bool> {
        Binding(
            get: { moreForLead != nil },
            set: { if !$0 { moreForLead = nil } }
        )
    }

    /// Atmosphere hue per stage — mirrors `LeadDetailView.atmosphereTone`.
    private var atmosphereTone: Atmosphere.Tone {
        switch stage {
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
                        .font(.custom("JetBrainsMono-Regular", size: 10))
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
#Preview("PipelineStageListView / quoting") {
    NavigationStack {
        PipelineStageListView(stage: .quoting, viewModel: .previewLoaded())
    }
    .leadsPreviewEnvironment()
}

#Preview("PipelineStageListView / won") {
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
