//
//  LeadDetailView.swift
//  OPS
//
//  Full record for one lead. Pushed from a triage row tap on LeadsTabView.
//  Phase 3 of the LEADS tab rebuild — replaces the placeholder that shipped
//  in Phase 2.
//
//  Composition (top → bottom):
//
//      Atmosphere(tone: derivedFromStage)
//      ┌────────────────────────────────────────────────┐
//      │  ← LEADS                                       │ ← DetailNavBar
//      ├────────────────────────────────────────────────┤
//      │  // L-XXXXXX                       9D IN STAGE │
//      │  [STAGE]   60% WIN PROB                        │
//      │  Helen Calloway                                │ ← DetailHero
//      │  Roof tear-off, 28 sq                          │
//      │  ┌──────┬──────┬──────┐                        │
//      │  │VALUE │WEIGHT│SOURCE│                        │
//      │  └──────┴──────┴──────┘                        │
//      │                                                │
//      │  [40] Helen Calloway                           │ ← ContactCard
//      │       (555) … · 1240 Maple Ave                 │
//      │  [CALL][TEXT][EMAIL][MAP]                      │
//      │                                                │
//      │  // WON · NOT CONVERTED   [conditional]        │ ← WonNotConvertedCard
//      │  Promote this lead into a project.             │
//      │  [CONVERT → PROJECT]                           │
//      │                                                │
//      │  // NEXT FOLLOW-UP                             │ ← FollowUpsCard
//      │  ● 2D OVERDUE                          AUTO    │
//      │  Chase quote response                          │
//      │                                                │
//      │  // RECENT ACTIVITY                  04        │ ← ActivityTimeline
//      │  [↓ Inbound call         5D ]                  │
//      │  …                                             │
//      │                                                │
//      │  // STAGE HISTORY                              │ ← StageTimeline
//      │  14D  NEW LEAD                                 │
//      │   0D  QUOTING → QUOTED                         │
//      └────────────────────────────────────────────────┘
//      [×]   [EDIT]   [MARK WON →]                       ← StickyActionBar
//
//  Sticky action bar is hidden when `opportunity.stage.isTerminal`.
//  Action closures route up to LeadsTabView which presents the matching
//  LeadsSheet (.lost / .edit / .convert) via its `.sheet(item:)` binding.
//
//  Plan: docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §7
//

import SwiftUI

struct LeadDetailView: View {
    let opportunity: Opportunity

    /// Routes to `LeadsSheet.lost(opportunity)` in the parent.
    var onMarkLost: () -> Void = {}
    /// Routes to `LeadsSheet.edit(opportunity)` in the parent.
    var onEdit:     () -> Void = {}
    /// Routes to `LeadsSheet.convert(opportunity)` in the parent.
    /// Also bound to the WON · NOT CONVERTED card's primary button.
    var onMarkWon:  () -> Void = {}

    @StateObject private var vm: LeadDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    init(
        opportunity: Opportunity,
        onMarkLost: @escaping () -> Void = {},
        onEdit:     @escaping () -> Void = {},
        onMarkWon:  @escaping () -> Void = {}
    ) {
        self.opportunity = opportunity
        self.onMarkLost = onMarkLost
        self.onEdit = onEdit
        self.onMarkWon = onMarkWon
        _vm = StateObject(wrappedValue: LeadDetailViewModel(
            opportunityId: opportunity.id,
            companyId: opportunity.companyId
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()
            Atmosphere(tone: atmosphereTone)

            VStack(spacing: 0) {
                DetailNavBar(onBack: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                })

                ScrollView {
                    VStack(spacing: 0) {
                        DetailHero(opportunity: opportunity)

                        ContactCard(opportunity: opportunity)
                            .padding(.top, 4)

                        if showWonNotConverted {
                            WonNotConvertedCard(onConvert: onMarkWon)
                                .padding(.top, 22)
                        }

                        if let nextFU = nextFollowUp {
                            FollowUpsCard(followUp: nextFU)
                                .padding(.top, 22)
                        }

                        ActivityTimeline(activities: sortedActivities)
                            .padding(.top, 22)

                        StageTimeline(transitions: sortedStageTransitions)
                            .padding(.top, 22)
                    }
                    .padding(.bottom, 200)   // clears the sticky action bar
                }
                .scrollIndicators(.hidden)
            }

            if !opportunity.stage.isTerminal {
                StickyActionBar(
                    onMarkLost: onMarkLost,
                    onEdit:     onEdit,
                    onMarkWon:  onMarkWon
                )
                .padding(.bottom, 49)   // clears the custom tab bar (49pt)
            }
        }
        .navigationBarHidden(true)
        .task {
            await vm.loadAll()
        }
    }

    // MARK: - Derived state

    private var atmosphereTone: Atmosphere.Tone {
        switch opportunity.stage {
        case .won:                                   return .olive
        case .lost:                                  return .rose
        case .quoted, .followUp, .negotiation:       return .tan
        case .newLead, .qualifying, .quoting:        return .steel
        }
    }

    private var showWonNotConverted: Bool {
        opportunity.stage == .won && opportunity.projectId == nil
    }

    /// Soonest unfinished follow-up (status != .completed), ascending by dueAt.
    private var nextFollowUp: FollowUp? {
        vm.followUps
            .filter { $0.status != .completed }
            .sorted { $0.dueAt < $1.dueAt }
            .first
    }

    /// Activities ordered newest first — ActivityTimeline trims to its maxItems.
    private var sortedActivities: [Activity] {
        vm.activities.sorted { $0.createdAt > $1.createdAt }
    }

    /// Stage transitions ordered oldest first — StageTimeline reads them in
    /// that order so the chain reads left-to-right top-to-bottom.
    private var sortedStageTransitions: [StageTransition] {
        vm.stageTransitions.sorted { $0.transitionedAt < $1.transitionedAt }
    }
}

// MARK: - DetailNavBar (private)

/// Minimal nav bar above the scroll view. Custom back chevron + LEADS label.
/// Right side is intentionally empty in Phase 3 — archive lives in
/// EditLeadSheet's danger zone (Phase 4) and per-row actions are reachable
/// from the sticky action bar. Swipe-back gesture is preserved by the
/// NavigationStack.
private struct DetailNavBar: View {
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(OPSStyle.Icons.chevronLeft)
                        .font(.system(size: 16, weight: .regular))
                    Text("LEADS")
                        .font(.custom("JetBrainsMono-Regular", size: 10))
                        .fontWeight(.semibold)
                        .kerning(1.4)
                        .textCase(.uppercase)
                }
                .foregroundColor(OPSStyle.Colors.text2)
                .padding(.leading, 4)
                .padding(.trailing, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Back to leads")

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

// MARK: - WonNotConvertedCard (private)

/// L1 card rendered only when `stage == .won && projectId == nil`. Olive
/// border + olive-tinted eyebrow signal "this is good, but it's incomplete."
/// CONVERT → PROJECT uses the same `onMarkWon` closure as the sticky bar so
/// the parent routes to the same `LeadsSheet.convert` case.
private struct WonNotConvertedCard: View {
    let onConvert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("WON · NOT CONVERTED")
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
            }
            .font(.custom("JetBrainsMono-Regular", size: 10))
            .fontWeight(.semibold)
            .kerning(1.6)
            .textCase(.uppercase)

            Text("Promote this lead into a project.")
                .font(.custom("Mohave-Medium", size: 14.5))
                .foregroundColor(OPSStyle.Colors.text)

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onConvert()
            }) {
                Text("CONVERT → PROJECT")
                    .font(.custom("CakeMono-Light", size: 13.5))
                    .kerning(0.27)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .fill(OPSStyle.Colors.opsAccent)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.oliveLineM, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("LeadDetailView / quoted") {
    NavigationStack {
        LeadDetailView(opportunity: {
            let o = Opportunity.preview(
                title: "Roof tear-off, 28 sq",
                contactName: "Helen Calloway",
                stage: .quoted,
                estimatedValue: 14_200,
                daysInStage: 9
            )
            o.contactPhone = "(555) 123-4567"
            o.contactEmail = "helen@example.com"
            o.address = "1240 Maple Ave"
            o.source = "referral"
            return o
        }())
    }
    .leadsPreviewEnvironment()
}

#Preview("LeadDetailView / won not converted") {
    NavigationStack {
        LeadDetailView(opportunity: {
            let o = Opportunity.preview(
                title: "Maple Lane porch",
                contactName: "Tom Liu",
                stage: .won,
                estimatedValue: 11_200,
                daysInStage: 12
            )
            o.contactPhone = "(555) 234-5678"
            o.address = "880 Maple Lane"
            o.source = "manual"
            return o
        }())
    }
    .leadsPreviewEnvironment()
}

#Preview("LeadDetailView / lost") {
    NavigationStack {
        LeadDetailView(opportunity: {
            let o = Opportunity.preview(
                title: "Beacon Hill addition",
                contactName: "Beacon Hill LLC",
                stage: .lost,
                estimatedValue: 26_500,
                daysInStage: 20
            )
            o.contactPhone = "(555) 999-0000"
            o.source = "web_form"
            o.lostReason = "price"
            return o
        }())
    }
    .leadsPreviewEnvironment()
}
#endif
