//
//  LeadDetailView.swift
//  OPS
//
//  Full-screen lead detail (NavigationLink push). Header + quick actions +
//  stage actions + activity log + follow-ups + stage history.
//

import SwiftUI

struct LeadDetailView: View {
    @StateObject private var viewModel: LeadDetailViewModel
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    @ObservedObject var pipelineVM: PipelineViewModel
    let opportunity: Opportunity

    @State private var showLogActivity = false
    @State private var showAddFollowUp = false
    @State private var showLostReason = false
    @State private var showEditSheet = false

    private var canManage: Bool { permissionStore.can("pipeline.manage") }
    private var userId: String? { dataController.currentUser?.id }

    init(opportunity: Opportunity, pipelineVM: PipelineViewModel) {
        self.opportunity = opportunity
        self.pipelineVM = pipelineVM
        _viewModel = StateObject(wrappedValue: LeadDetailViewModel(
            opportunityId: opportunity.id,
            companyId: opportunity.companyId
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                header
                if canManage { quickActions }
                if canManage && !opportunity.stage.isTerminal { stageActions }
                activitySection
                followUpsSection
                stageHistorySection
            }
            .padding(OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .navigationTitle("LEAD")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadAll() }
        .sheet(isPresented: $showLogActivity) {
            LeadLogActivitySheet { type, subject, body in
                Task {
                    try? await viewModel.logActivity(type: type, subject: subject, body: body)
                }
            }
        }
        .sheet(isPresented: $showAddFollowUp) {
            AddFollowUpSheet { title, desc, type, dueAt, reminderAt in
                Task {
                    try? await viewModel.addFollowUp(
                        title: title, description: desc, type: type,
                        dueAt: dueAt, reminderAt: reminderAt, assignedTo: userId
                    )
                }
            }
        }
        .sheet(isPresented: $showLostReason) {
            LostReasonSheet(opportunityTitle: opportunity.title ?? opportunity.contactName) { reason, notes in
                Task {
                    try? await pipelineVM.markLost(opportunityId: opportunity.id, reason: reason, notes: notes, userId: userId)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditLeadSheet(opportunity: opportunity, pipelineVM: pipelineVM)
                .environmentObject(dataController)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(opportunity.title ?? opportunity.contactName)
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text(opportunity.contactName.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                stagePill
                if let v = opportunity.estimatedValue {
                    Text(formatCurrency(v))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                if opportunity.isStale {
                    Text("⚠ STALE")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                }
            }
        }
    }

    private var stagePill: some View {
        Text(opportunity.stage.displayName)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.invertedText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 4)
            .background(OPSStyle.Colors.primaryAccent)
            .clipShape(Capsule())
    }

    private var quickActions: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            if let phone = opportunity.contactPhone, let url = URL(string: "tel:\(phone)") {
                quickAction(icon: "phone.fill", label: "CALL") { UIApplication.shared.open(url) }
                quickAction(icon: "message.fill", label: "TEXT") {
                    if let smsURL = URL(string: "sms:\(phone)") { UIApplication.shared.open(smsURL) }
                }
            }
            if let email = opportunity.contactEmail, let url = URL(string: "mailto:\(email)") {
                quickAction(icon: "envelope.fill", label: "EMAIL") { UIApplication.shared.open(url) }
            }
        }
    }

    @ViewBuilder
    private func quickAction(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        }
    }

    private var stageActions: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("STAGE ACTIONS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let next = opportunity.stage.next {
                    actionButton("→ \(next.displayName)", tint: OPSStyle.Colors.primaryAccent, fill: true) {
                        Task { try? await pipelineVM.moveToStage(opportunityId: opportunity.id, to: next, userId: userId) }
                    }
                }
                actionButton("WON", tint: OPSStyle.Colors.successStatus, fill: true) {
                    Task { try? await pipelineVM.markWon(opportunityId: opportunity.id, actualValue: opportunity.estimatedValue, projectId: nil, userId: userId) }
                }
                actionButton("LOST", tint: OPSStyle.Colors.tertiaryText, fill: false) {
                    showLostReason = true
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ label: String, tint: Color, fill: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(fill ? OPSStyle.Colors.invertedText : tint)
                .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard)
                .background(fill ? tint : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(fill ? Color.clear : tint, lineWidth: OPSStyle.Layout.Border.standard))
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("ACTIVITY")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                if canManage {
                    Button("+ LOG") { showLogActivity = true }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            if viewModel.activities.isEmpty {
                Text("No activity yet")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                ForEach(viewModel.activities) { act in
                    activityRow(act)
                }
            }
        }
    }

    @ViewBuilder
    private func activityRow(_ act: Activity) -> some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: act.type.icon)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                if let s = act.subject, !s.isEmpty {
                    Text(s).font(OPSStyle.Typography.bodyBold).foregroundColor(OPSStyle.Colors.primaryText)
                }
                if let body = act.displayBody {
                    Text(body).font(OPSStyle.Typography.body).foregroundColor(OPSStyle.Colors.secondaryText).lineLimit(3)
                }
                Text(formatDate(act.createdAt))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
    }

    private var followUpsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("FOLLOW-UPS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                if canManage {
                    Button("+ ADD") { showAddFollowUp = true }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            if viewModel.followUps.isEmpty {
                Text("No follow-ups").font(OPSStyle.Typography.body).foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                ForEach(viewModel.followUps) { fu in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fu.title).font(OPSStyle.Typography.bodyBold).foregroundColor(OPSStyle.Colors.primaryText)
                            Text(formatDate(fu.dueAt)).font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(fu.isOverdue ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.secondaryText)
                        }
                        Spacer()
                        Text(fu.status.rawValue.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                }
            }
        }
    }

    private var stageHistorySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("STAGE HISTORY")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            if viewModel.stageTransitions.isEmpty {
                Text("No transitions").font(OPSStyle.Typography.body).foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                ForEach(viewModel.stageTransitions) { st in
                    HStack {
                        Text("\(st.fromStage?.displayName ?? "—") → \(st.toStage.displayName)")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                        Text(formatDate(st.transitionedAt))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .padding(OPSStyle.Layout.spacing2)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mma"
        return f.string(from: d)
    }
}
