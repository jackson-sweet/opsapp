//
//  OpportunityDetailView.swift
//  OPS
//
//  Full detail view for a pipeline opportunity — details, activity, and follow-ups tabs.
//

import SwiftUI

struct OpportunityDetailView: View {
    var opportunity: Opportunity
    @ObservedObject var viewModel: PipelineViewModel
    @StateObject private var detailVM = OpportunityDetailViewModel()
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: DetailTab = .details
    @State private var showActivitySheet = false
    @State private var showLostSheet = false
    @State private var showEditSheet = false
    @State private var showOverflowMenu = false

    enum DetailTab: String, CaseIterable {
        case details   = "DETAILS"
        case activity  = "ACTIVITY"
        case followUps = "FOLLOW-UPS"
    }

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    advanceAction
                    tabSelector
                    tabContent
                }
            }
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
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
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
        .alert("Error", isPresented: Binding(
            get: { detailVM.error != nil },
            set: { if !$0 { detailVM.error = nil } }
        )) {
            Button("OK") { detailVM.error = nil }
        } message: {
            Text(detailVM.error ?? "")
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

                // Monochromatic stage indicator
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Circle()
                        .fill(OPSStyle.Colors.pipelineStageColor(for: opportunity.stage))
                        .frame(width: 6, height: 6)
                    Text(opportunity.stage.displayName)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Text("day \(opportunity.daysInStage)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                if opportunity.isStale {
                    Image(systemName: OPSStyle.Icons.stale)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    // MARK: - Advance Action

    private var advanceAction: some View {
        Group {
            if !opportunity.stage.isTerminal, let nextStage = opportunity.stage.next {
                VStack(spacing: 0) {
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(OPSStyle.Colors.separator)

                    Button {
                        Task { await viewModel.advanceStage(opportunity: opportunity) }
                    } label: {
                        Label("ADVANCE TO \(nextStage.displayName)", systemImage: OPSStyle.Icons.stageAdvance)
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .opsPrimaryButtonStyle()
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                }
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        SegmentedControl(selection: $selectedTab, options: [
            (.details, "DETAILS"),
            (.activity, "ACTIVITY"),
            (.followUps, "FOLLOW-UPS")
        ])
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .details:
            detailsTab
        case .activity:
            activityTab
        case .followUps:
            followUpsTab
        }
    }

    // MARK: - Details Tab

    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // CONTACT section
            if hasContactInfo {
                sectionHeader("CONTACT")

                VStack(spacing: 0) {
                    if let phone = opportunity.contactPhone, !phone.isEmpty {
                        contactRow(
                            icon: "phone.fill",
                            title: "PHONE",
                            value: phone,
                            action: {
                                if let url = URL(string: "tel:\(phone)") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        )
                    }

                    if hasPhone && hasEmail {
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundColor(OPSStyle.Colors.cardBorder)
                    }

                    if let email = opportunity.contactEmail, !email.isEmpty {
                        contactRow(
                            icon: "envelope.fill",
                            title: "EMAIL",
                            value: email,
                            action: {
                                if let url = URL(string: "mailto:\(email)") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        )
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }

            // DEAL INFO section
            sectionHeader("DEAL INFO")

            VStack(spacing: 0) {
                infoRow(icon: "dollarsign.circle", title: "ESTIMATED VALUE",
                        value: opportunity.estimatedValue.map {
                            currencyFormatter.string(from: NSNumber(value: $0)) ?? "—"
                        } ?? "—")

                infoDivider

                infoRow(icon: "chart.bar", title: "WEIGHTED VALUE",
                        value: currencyFormatter.string(from: NSNumber(value: opportunity.weightedValue)) ?? "—")

                infoDivider

                infoRow(icon: "tag", title: "SOURCE",
                        value: opportunity.source ?? "—")

                infoDivider

                infoRow(icon: "calendar", title: "CREATED",
                        value: opportunity.createdAt.formatted(date: .abbreviated, time: .omitted))

                infoDivider

                infoRow(icon: "clock", title: "LAST ACTIVITY",
                        value: lastActivityLabel)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    private var hasContactInfo: Bool {
        hasPhone || hasEmail
    }

    private var hasPhone: Bool {
        if let phone = opportunity.contactPhone, !phone.isEmpty { return true }
        return false
    }

    private var hasEmail: Bool {
        if let email = opportunity.contactEmail, !email.isEmpty { return true }
        return false
    }

    private var lastActivityLabel: String {
        guard let lastActivity = detailVM.activities.first else { return "—" }
        let interval = Date().timeIntervalSince(lastActivity.createdAt)
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(max(minutes, 1))m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)hr ago" }
        let days = hours / 24
        if days == 1 { return "yesterday" }
        return "\(days) days ago"
    }

    // MARK: - Details Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func contactRow(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: icon)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: OPSStyle.Layout.IconSize.sm)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(value)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: icon)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: OPSStyle.Layout.IconSize.sm)

            Text(title)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Spacer()

            Text(value)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private var infoDivider: some View {
        Rectangle()
            .frame(height: 0.5)
            .foregroundColor(OPSStyle.Colors.cardBorder)
    }

    // MARK: - Activity Tab

    private var activityTab: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            if detailVM.isLoading && detailVM.activities.isEmpty {
                HStack { Spacer(); TacticalLoadingBarAnimated(); Spacer() }
                    .padding(.top, OPSStyle.Layout.spacing4)
            } else if detailVM.activities.isEmpty {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("NO ACTIVITY YET")
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("Log the first note to start tracking.")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
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
                            Rectangle()
                                .frame(height: 0.5)
                                .foregroundColor(OPSStyle.Colors.cardBorder)
                        }
                    }

                    if detailVM.activities.count > 5 {
                        Text("\(detailVM.activities.count - 5) MORE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing3)
            }
        }
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    // MARK: - Follow-Ups Tab

    private var followUpsTab: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            if detailVM.followUps.isEmpty {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "bell")
                        .font(OPSStyle.Typography.heading)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("NO FOLLOW-UPS")
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("Schedule your first reminder.")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, OPSStyle.Layout.spacing5)
            } else {
                VStack(spacing: 0) {
                    ForEach(detailVM.followUps) { fu in
                        FollowUpRowView(followUp: fu)
                        if fu.id != detailVM.followUps.last?.id {
                            Rectangle()
                                .frame(height: 0.5)
                                .foregroundColor(OPSStyle.Colors.cardBorder)
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing3)
            }
        }
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }
}
