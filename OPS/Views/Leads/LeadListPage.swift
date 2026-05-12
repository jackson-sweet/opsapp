//
//  LeadListPage.swift
//  OPS
//
//  Single-stage lead list page rendered inside the LeadsTabView carousel.
//

import SwiftUI

struct LeadListPage: View {
    @ObservedObject var viewModel: PipelineViewModel
    let stage: PipelineStage
    let inCourtFilterActive: Bool
    let canManage: Bool

    var onCardTap: (Opportunity) -> Void
    var onAdvance: (Opportunity) -> Void
    var onWon: (Opportunity) -> Void
    var onLost: (Opportunity) -> Void
    var onLongPress: (Opportunity) -> Void

    @State private var pendingOfflineErrorIds: Set<String> = []

    private var leads: [Opportunity] {
        let stageLeads = viewModel.opportunities(in: stage)
        if !inCourtFilterActive { return stageLeads }
        return stageLeads.filter { viewModel.inCourtOpportunityIds.contains($0.id) }
    }

    var body: some View {
        Group {
            if leads.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(leads) { lead in
                            LeadCard(
                                opportunity: lead,
                                canManage: canManage,
                                isPendingOfflineError: pendingOfflineErrorIds.contains(lead.id),
                                onTap: { onCardTap(lead) },
                                onAdvance: { onAdvance(lead) },
                                onWon: { onWon(lead) },
                                onLost: { onLost(lead) },
                                onLongPress: { onLongPress(lead) }
                            )
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                }
                .refreshable { await viewModel.loadData() }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Text(emptyCopy)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyCopy: String {
        if inCourtFilterActive {
            return "NO IN-COURT LEADS IN \(stage.displayName)"
        }
        switch stage {
        case .won:  return "NO WINS YET — KEEP MOVING"
        case .lost: return "NO LOSSES"
        default:    return "NO LEADS IN \(stage.displayName)"
        }
    }
}
