//
//  OpportunityDetailView.swift
//  OPS
//
//  Full detail view for a pipeline opportunity — activity timeline, follow-ups, and tabbed content.
//

import SwiftUI

struct OpportunityDetailView: View {
    var opportunity: Opportunity
    @ObservedObject var viewModel: PipelineViewModel
    @StateObject private var detailVM = OpportunityDetailViewModel()
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: DetailTab = .activity
    @State private var showActivitySheet = false
    @State private var showLostSheet = false
    @State private var showEditSheet = false
    @State private var showOverflowMenu = false

    enum DetailTab: String, CaseIterable {
        case activity  = "ACTIVITY"
        case estimates = "ESTIMATES"
        case invoices  = "INVOICES"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    quickActions
                    tabSelector
                    tabContent
                }
                .padding(.bottom, 80)
            }

            // FAB
            detailFAB
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showOverflowMenu = true } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .confirmationDialog("", isPresented: $showOverflowMenu) {
            Button("Edit Deal") { showEditSheet = true }
            Button("Mark as Won") {
                Task { await viewModel.markWon(opportunity: opportunity) }
            }
            Button("Mark as Lost") { showLostSheet = true }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteOpportunity(opportunity)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showActivitySheet) {
            ActivityFormSheet(
                opportunityId: opportunity.id,
                companyId: dataController.currentUser?.companyId ?? "",
                detailVM: detailVM
            )
        }
        .sheet(isPresented: $showLostSheet) {
            MarkLostSheet(opportunity: opportunity) { reason in
                Task { await viewModel.markLost(opportunity: opportunity, reason: reason) }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            OpportunityFormSheet(viewModel: viewModel, editing: opportunity)
        }
        .task {
            if let companyId = dataController.currentUser?.companyId {
                detailVM.setup(companyId: companyId)
                await detailVM.loadDetails(for: opportunity.id)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(opportunity.contactName.uppercased())
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)

            if let desc = opportunity.jobDescription {
                Text(desc)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let value = opportunity.estimatedValue {
                    Text(value, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                stageBadge

                Text("[\(opportunity.daysInStage == 1 ? "day 1" : "day \(opportunity.daysInStage)")]")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                if opportunity.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    private var stageBadge: some View {
        let color = OPSStyle.Colors.pipelineStageColor(for: opportunity.stage)
        return Text(opportunity.stage.displayName)
            .font(OPSStyle.Typography.smallCaption)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .overlay(Capsule().stroke(color, lineWidth: 1))
            .clipShape(Capsule())
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.15))

            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let phone = opportunity.contactPhone, !phone.isEmpty {
                    Button {
                        if let url = URL(string: "tel:\(phone)") { UIApplication.shared.open(url) }
                    } label: {
                        Label("CALL", systemImage: "phone.fill")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .opsSecondaryButtonStyle()
                }

                if let email = opportunity.contactEmail, !email.isEmpty {
                    Button {
                        if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                    } label: {
                        Label("EMAIL", systemImage: "envelope.fill")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .opsSecondaryButtonStyle()
                }

                if !opportunity.stage.isTerminal {
                    Button {
                        Task { await viewModel.advanceStage(opportunity: opportunity) }
                    } label: {
                        Label("ADVANCE", systemImage: OPSStyle.Icons.stageAdvance)
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .opsSecondaryButtonStyle()
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        VStack(spacing: 4) {
                            Text(tab.rawValue)
                                .font(OPSStyle.Typography.smallCaption)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                                .foregroundColor(
                                    selectedTab == tab
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.tertiaryText
                                )
                            Rectangle()
                                .frame(height: 2)
                                .foregroundColor(
                                    selectedTab == tab
                                    ? OPSStyle.Colors.primaryAccent
                                    : Color.clear
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.4))

            Divider().background(Color.white.opacity(0.15))
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .activity:
            activityTab
        case .estimates:
            placeholderTab(title: "ESTIMATES", icon: OPSStyle.Icons.estimateDoc, message: "Coming in Sprint 3")
        case .invoices:
            placeholderTab(title: "INVOICES", icon: OPSStyle.Icons.invoiceReceipt, message: "Coming in Sprint 4")
        }
    }

    private var activityTab: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Activities
            if detailVM.isLoading && detailVM.activities.isEmpty {
                HStack { Spacer(); TacticalLoadingBarAnimated(); Spacer() }
                    .padding(.top, OPSStyle.Layout.spacing4)
            } else if detailVM.activities.isEmpty {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("NO ACTIVITY YET")
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Button("LOG THE FIRST NOTE") { showActivitySheet = true }
                        .opsPrimaryButtonStyle()
                        .padding(.horizontal, OPSStyle.Layout.spacing4)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, OPSStyle.Layout.spacing5)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(detailVM.activities.prefix(5).enumerated()), id: \.element.id) { index, activity in
                        ActivityRowView(activity: activity)
                        if index < min(4, detailVM.activities.count - 1) {
                            Divider().background(Color.white.opacity(0.1))
                        }
                    }

                    if detailVM.activities.count > 5 {
                        Button("[VIEW ALL \(detailVM.activities.count) EVENTS]") {
                            // TODO: expand or navigate
                        }
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing3)
            }

            // Follow-ups section
            if !detailVM.followUps.isEmpty {
                followUpsSection
            }
        }
    }

    private var followUpsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("FOLLOW-UPS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            VStack(spacing: 0) {
                ForEach(detailVM.followUps) { fu in
                    FollowUpRowView(followUp: fu)
                    if fu.id != detailVM.followUps.last?.id {
                        Divider().background(Color.white.opacity(0.1))
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    private func placeholderTab(title: String, icon: String, message: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(title)
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text(message)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    // MARK: - FAB

    private var detailFAB: some View {
        Button {
            showActivitySheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .frame(width: OPSStyle.Layout.touchTargetLarge, height: OPSStyle.Layout.touchTargetLarge)
                .background(OPSStyle.Colors.primaryAccent)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .padding(OPSStyle.Layout.spacing3)
        .accessibilityLabel("Log Activity")
    }
}
