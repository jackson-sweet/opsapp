//
//  LeadsTabView.swift
//  OPS
//
//  Root view for the LEADS top-level tab. Composes:
//    AppHeader(.leads)
//    LeadsHeaderCarousel  (collapses on scroll)
//    BallInCourtBar       (hidden when count == 0)
//    LeadStageStrip       (sticky; temporary name, renamed to StageStripView
//                          in P1-3 after Books Reconstruction lands)
//    TabView(selection:)  (paged per-stage lists)
//

import SwiftUI

private struct HeaderBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct LeadsTabView: View {
    @StateObject private var viewModel: PipelineViewModel
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    init(viewModel: PipelineViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? PipelineViewModel())
    }

    @State private var headerCollapsed = false
    @State private var inCourtFilterActive = false
    @State private var showClosedStages = false
    @State private var detailDestination: Opportunity?
    @State private var actionSheetOpportunity: Opportunity?
    @State private var lostReasonOpportunity: Opportunity?
    @State private var showForecastBreakdown = false

    private var canManage: Bool { permissionStore.can("pipeline.manage") }
    private var isOffline: Bool { !dataController.isConnected }

    private var activePerStage: [(stage: PipelineStage, count: Int)] {
        let active: [PipelineStage] = [.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]
        return active.map { ($0, viewModel.count(in: $0)) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppHeader(headerType: .leads)
                    .padding(.bottom, 8)

                if headerCollapsed {
                    LeadStageStrip(
                        selectedStage: $viewModel.selectedStage,
                        showClosed: $showClosedStages,
                        countProvider: { viewModel.count(in: $0) }
                    )
                    .background(OPSStyle.Colors.background)
                    .transition(.opacity)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        LeadsHeaderCarousel(
                            weightedForecast: viewModel.weightedForecastValue,
                            weightedForecastDelta: nil,
                            activeLeadCount: viewModel.activeLeadCount,
                            activePerStage: activePerStage,
                            closeRate: viewModel.closeRate(periodDays: 90),
                            closeRateWonCount: viewModel.count(in: .won),
                            closeRateLostCount: viewModel.count(in: .lost),
                            avgVelocityDays: nil,
                            avgVelocityDelta: nil,
                            staleLeadsCount: viewModel.staleLeadsCount,
                            staleLeadsTotalValue: viewModel.staleLeadsTotalValue,
                            oldestStaleDescription: viewModel.oldestStaleDescription,
                            onForecastTap: { showForecastBreakdown = true },
                            onActivePipelineTap: {
                                if let largest = activePerStage.max(by: { $0.count < $1.count })?.stage {
                                    withAnimation(OPSStyle.Animation.standard) {
                                        viewModel.selectedStage = largest
                                    }
                                }
                            },
                            onStaleRiskTap: {
                                withAnimation(OPSStyle.Animation.standard) {
                                    inCourtFilterActive = true
                                }
                            }
                        )
                        .padding(.bottom, OPSStyle.Layout.spacing3)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: HeaderBottomKey.self,
                                    value: geo.frame(in: .named("scroll")).maxY
                                )
                            }
                        )

                        BallInCourtBar(
                            count: viewModel.inCourtCount,
                            buckets: viewModel.inCourtBuckets,
                            totalValue: viewModel.inCourtTotalValue,
                            filterActive: inCourtFilterActive,
                            isOffline: isOffline,
                            onToggleFilter: {
                                withAnimation(OPSStyle.Animation.standard) {
                                    inCourtFilterActive.toggle()
                                }
                            }
                        )
                        .padding(.bottom, OPSStyle.Layout.spacing2)

                        if !headerCollapsed {
                            LeadStageStrip(
                                selectedStage: $viewModel.selectedStage,
                                showClosed: $showClosedStages,
                                countProvider: { viewModel.count(in: $0) }
                            )
                        }

                        carouselContent
                            .frame(minHeight: 400)
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(HeaderBottomKey.self) { bottomY in
                    let shouldCollapse = bottomY < 0
                    if shouldCollapse != headerCollapsed {
                        withAnimation(OPSStyle.Animation.fast) {
                            headerCollapsed = shouldCollapse
                        }
                    }
                }
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
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
                        Task { try? await viewModel.moveToStage(opportunityId: lead.id, to: stage, userId: dataController.currentUser?.id) }
                    },
                    onEdit:        { detailDestination = lead },
                    onLogActivity: { detailDestination = lead },
                    onAddFollowUp: { detailDestination = lead },
                    onOpenDetail:  { detailDestination = lead },
                    onArchive:     { Task { try? await viewModel.archive(opportunityId: lead.id) } },
                    onDelete:      { Task { try? await viewModel.softDelete(opportunityId: lead.id) } }
                )
            }
            .sheet(item: $lostReasonOpportunity) { lead in
                LostReasonSheet(opportunityTitle: lead.title ?? lead.contactName) { reason, notes in
                    Task { try? await viewModel.markLost(opportunityId: lead.id, reason: reason, notes: notes, userId: dataController.currentUser?.id) }
                }
            }
            .sheet(isPresented: $showForecastBreakdown) {
                ForecastBreakdownSheet(opportunities: viewModel.allOpportunities) { opp in
                    detailDestination = opp
                }
            }
        }
        .trackScreen("Leads")
        .task {
            if let companyId = dataController.currentUser?.companyId {
                viewModel.setup(companyId: companyId, currentUserId: dataController.currentUser?.id)
                await viewModel.loadData()
            }
        }
        .onAppear {
            inCourtFilterActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadCreatedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
    }

    @ViewBuilder
    private var carouselContent: some View {
        let pages = pagesToRender
        TabView(selection: $viewModel.selectedStage) {
            ForEach(pages, id: \.self) { stage in
                LeadListPage(
                    viewModel: viewModel,
                    stage: stage,
                    inCourtFilterActive: inCourtFilterActive,
                    canManage: canManage,
                    onCardTap: { detailDestination = $0 },
                    onAdvance: { lead in
                        guard let next = lead.stage.next else { return }
                        Task { try? await viewModel.moveToStage(opportunityId: lead.id, to: next, userId: dataController.currentUser?.id) }
                    },
                    onWon:  { lead in
                        Task { try? await viewModel.markWon(opportunityId: lead.id, actualValue: lead.estimatedValue, projectId: nil, userId: dataController.currentUser?.id) }
                    },
                    onLost: { lead in lostReasonOpportunity = lead },
                    onLongPress: { lead in actionSheetOpportunity = lead }
                )
                .tag(stage)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(OPSStyle.Animation.standard, value: viewModel.selectedStage)
    }

    private var pagesToRender: [PipelineStage] {
        let active: [PipelineStage] = [.newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation]
        if showClosedStages {
            return active + [.won, .lost]
        }
        return active
    }
}

#if DEBUG
#Preview("LeadsTabView / loaded") {
    LeadsTabView(viewModel: .previewLoaded())
        .leadsPreviewEnvironment()
}

#Preview("LeadsTabView / empty") {
    LeadsTabView(viewModel: .previewLoaded(opportunities: []))
        .leadsPreviewEnvironment()
}
#endif
