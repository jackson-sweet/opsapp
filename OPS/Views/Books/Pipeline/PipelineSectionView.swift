//
//  PipelineSectionView.swift
//  OPS
//
//  Pipeline segment root — composes StageStripView + lead list +
//  empty/loading/error states.
//

import SwiftUI

struct PipelineSectionView: View {
    @StateObject private var viewModel = PipelineViewModel()
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    @State private var actionSheetOpportunity: Opportunity?
    @State private var lostReasonOpportunity: Opportunity?
    @State private var detailDestination: Opportunity?

    private var canManage: Bool { permissionStore.can("pipeline.manage") }
    private var userId: String? { dataController.currentUser?.id }

    var body: some View {
        VStack(spacing: 0) {
            StageStripView(
                selectedStage: $viewModel.selectedStage,
                countProvider: { viewModel.count(in: $0) }
            )

            if viewModel.isLoading {
                Spacer()
                TacticalLoadingBarAnimated()
                Spacer()
            } else if let error = viewModel.loadError {
                errorState(error)
            } else if viewModel.isPipelineEmpty {
                pipelineEmptyState
            } else {
                let leads = viewModel.opportunities(in: viewModel.selectedStage)
                if leads.isEmpty {
                    stageEmptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(leads) { lead in
                                LeadCardView(
                                    opportunity: lead,
                                    canManage: canManage,
                                    onTap: { detailDestination = lead },
                                    onAdvance: {
                                        guard let next = lead.stage.next else { return }
                                        Task { try? await viewModel.moveToStage(opportunityId: lead.id, to: next, userId: userId) }
                                    },
                                    onWon: {
                                        Task { try? await viewModel.markWon(opportunityId: lead.id, actualValue: lead.estimatedValue, projectId: nil, userId: userId) }
                                    },
                                    onLost: { lostReasonOpportunity = lead },
                                    onMore: { actionSheetOpportunity = lead }
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
        .background(OPSStyle.Colors.background)
        .task {
            if let companyId = dataController.currentUser?.companyId {
                viewModel.setup(companyId: companyId)
                await viewModel.loadData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadCreatedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .navigationDestination(item: $detailDestination) { lead in
            LeadDetailView(opportunity: lead, pipelineVM: viewModel)
                .environmentObject(dataController)
                .environmentObject(permissionStore)
        }
        .sheet(item: $actionSheetOpportunity) { lead in
            LeadActionSheet(
                opportunity: lead,
                canManage: canManage,
                onMoveToStage: { stage in
                    Task { try? await viewModel.moveToStage(opportunityId: lead.id, to: stage, userId: userId) }
                },
                onEdit: { detailDestination = lead /* opens detail; user taps edit there */ },
                onLogActivity: { detailDestination = lead },
                onAddFollowUp: { detailDestination = lead },
                onOpenDetail: { detailDestination = lead },
                onArchive: { Task { try? await viewModel.archive(opportunityId: lead.id) } },
                onDelete: { Task { try? await viewModel.softDelete(opportunityId: lead.id) } }
            )
        }
        .sheet(item: $lostReasonOpportunity) { lead in
            LostReasonSheet(opportunityTitle: lead.title ?? lead.contactName) { reason, notes in
                Task { try? await viewModel.markLost(opportunityId: lead.id, reason: reason, notes: notes, userId: userId) }
            }
        }
    }

    // MARK: - States

    private var pipelineEmptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("NO LEADS YET")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Tap + to add your first lead")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stageEmptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Text(emptyCopy(for: viewModel.selectedStage))
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyCopy(for stage: PipelineStage) -> String {
        switch stage {
        case .won:  return "NO WINS YET — KEEP MOVING"
        case .lost: return "NO LOSSES"
        default:    return "NO LEADS IN \(stage.displayName)"
        }
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.warningStatus)
            Text("COULD NOT LOAD LEADS")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(error)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Button("TAP TO RETRY") { Task { await viewModel.loadData() } }
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
