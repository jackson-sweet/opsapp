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
//      │  [LeadTriageCard]   ← stale-first, 8pt gaps    │
//      │  [LeadTriageCard]                              │
//      │  …                                             │
//      └────────────────────────────────────────────────┘
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
//  In practice the by-stage strip only opens OPEN stages, so this is defensive.
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
    @State private var discardTarget: Opportunity?
    /// Lead whose comeback date is being adjusted (ComebackChooserSheet).
    @State private var comebackTarget: Opportunity?
    /// Pending ARCHIVE confirmation (OPSConfirm).
    @State private var archiveConfirm: OPSConfirmConfig?

    /// This stage's leads — already sorted stale-first by the view model.
    private var leads: [Opportunity] { viewModel.opportunities(in: stage) }
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
        .opsConfirm($archiveConfirm)
        .sheet(item: $comebackTarget) { lead in
            ComebackChooserSheet(lead: lead, viewModel: viewModel)
        }
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(stage.displayName)
                .font(OPSStyle.Typography.screenTitle(for: stage.displayName))
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
            StageEmpty(stage: stage)
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

    /// ARCHIVE — guarded by the standardized confirm (spec §6).
    private func requestArchive(_ lead: Opportunity) {
        guard canEdit(lead) else { return }
        archiveConfirm = OPSConfirmConfig(
            title: "ARCHIVE LEAD?",
            message: "It leaves the queue. Restore any time from the by-stage list.",
            verb: "ARCHIVE"
        ) {
            Task {
                do {
                    try await viewModel.archive(opportunityId: lead.id)
                    ToastCenter.shared.present(Feedback.Lead.archived)
                } catch {
                    ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
                }
            }
        }
    }

    // MARK: - Helpers

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
