//
//  ManageSubscriptionView.swift
//  OPS
//
//  Subscription management view with tactical dashboard style
//

import SwiftUI

struct ManageSubscriptionView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var showSeatManagement = false
    @State private var showPlanSelection = false
    @State private var showCancelConfirmation = false
    @State private var cancellationReason = ""
    @State private var cancelPriorityToo = false
    @State private var isCancelling = false
    @State private var errorMessage: String?

    private var company: Company? {
        dataController.getCurrentUserCompany()
    }

    private var isCompanyAdmin: Bool {
        dataController.currentUser?.isCompanyAdmin == true || dataController.currentUser?.role == .admin
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Subscription",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let company = company {
                            // Tactical dashboard header
                            subscriptionDashboard(company)

                            // Action cards
                            actionCardsSection

                            // Billing info card
                            billingInfoSection(company)

                            // Cancel subscription (admin only)
                            if isCompanyAdmin {
                                cancelSubscriptionSection
                            }

                            // Error message
                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(OPSStyle.Colors.errorStatus)

                                    Text(error)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.errorStatus)
                                }
                                .padding(.horizontal, 20)
                            }
                        } else {
                            // No company
                            EmptyStateView(
                                icon: "creditcard",
                                title: "No subscription",
                                message: "Subscription information is not available."
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 16)
                    .tabBarPadding()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showSeatManagement) {
            SeatManagementView()
                .environmentObject(dataController)
                .environmentObject(subscriptionManager)
        }
        .sheet(isPresented: $showPlanSelection) {
            PlanSelectionView()
                .environmentObject(dataController)
                .environmentObject(subscriptionManager)
        }
        .sheet(isPresented: $showCancelConfirmation) {
            cancelSubscriptionSheet
        }
    }

    // MARK: - Subscription Dashboard

    private func subscriptionDashboard(_ company: Company) -> some View {
        VStack(spacing: 0) {
            // Status row
            HStack(alignment: .center) {
                // Plan name and status
                VStack(alignment: .leading, spacing: 4) {
                    if let plan = company.subscriptionPlan,
                       let planEnum = SubscriptionPlan(rawValue: plan) {
                        Text(planEnum.displayName.uppercased())
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Text("NO PLAN")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    if let status = company.subscriptionStatus,
                       let statusEnum = SubscriptionStatus(rawValue: status) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor(for: statusEnum))
                                .frame(width: 8, height: 8)

                            Text(statusEnum.displayName.uppercased())
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(statusColor(for: statusEnum))
                        }
                    }
                }

                Spacer()

                // Price display
                if let plan = company.subscriptionPlan,
                   let planEnum = SubscriptionPlan(rawValue: plan) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatPrice(planEnum.monthlyPrice))
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text(company.subscriptionPeriod ?? "Monthly")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Divider
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1)
                .padding(.horizontal, 20)

            // Warning banners
            warningBanners(company)

            // Seat usage row
            seatUsageRow(company)
        }
    }

    private func warningBanners(_ company: Company) -> some View {
        Group {
            if let status = company.subscriptionStatus,
               let statusEnum = SubscriptionStatus(rawValue: status) {
                if statusEnum == .trial, let trialEnd = company.trialEndDate {
                    let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
                    warningBanner(
                        icon: days > 0 ? "info.circle.fill" : "exclamationmark.triangle.fill",
                        message: days > 0 ? "Trial ends in \(days) day\(days == 1 ? "" : "s")" : "Trial expired",
                        color: days > 0 ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.errorStatus
                    )
                } else if statusEnum == .grace, let days = company.daysRemainingInGracePeriod {
                    warningBanner(
                        icon: "exclamationmark.triangle.fill",
                        message: days > 0 ? "Grace period ends in \(days) day\(days == 1 ? "" : "s")" : "Grace period expired",
                        color: days > 0 ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.errorStatus
                    )
                }
            }
        }
    }

    private func warningBanner(icon: String, message: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)

            Text(message.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(color)

            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.1))
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func seatUsageRow(_ company: Company) -> some View {
        let seatedCount = company.seatedEmployeeIds
            .split(separator: ",")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        let maxSeats = company.maxSeats
        let percentage = Double(seatedCount) / Double(maxSeats)
        let isAtLimit = seatedCount >= maxSeats

        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SEATS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(seatedCount)")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(isAtLimit ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryText)

                        Text("/ \(maxSeats)")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                Spacer()

                // Progress indicator
                ZStack {
                    Circle()
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 4)
                        .frame(width: 44, height: 44)

                    Circle()
                        .trim(from: 0, to: CGFloat(min(percentage, 1.0)))
                        .stroke(
                            isAtLimit ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryAccent,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(percentage * 100))%")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }

            // Warning if at limit
            if isAtLimit {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.warningStatus)

                    Text("SEAT LIMIT REACHED")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Action Cards Section

    private var actionCardsSection: some View {
        VStack(spacing: 12) {
            // Manage Seats button
            Button(action: {
                showSeatManagement = true
            }) {
                actionRow(
                    icon: "person.badge.plus",
                    title: "Manage Seats",
                    subtitle: "Add or remove team member access"
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Change Plan button
            Button(action: {
                showPlanSelection = true
            }) {
                actionRow(
                    icon: "arrow.up.circle",
                    title: "Change Plan",
                    subtitle: "Upgrade or modify subscription"
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
    }

    private func actionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(subtitle)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Billing Info Section

    private func billingInfoSection(_ company: Company) -> some View {
        SectionCard(
            icon: "doc.text.fill",
            title: "Billing"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Next billing date")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()

                    Text("—")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                HStack {
                    Text("Payment method")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()

                    Text("Not configured")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                if company.hasPrioritySupport {
                    HStack {
                        Text("Priority support")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.successStatus)

                            Text("Active")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.successStatus)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Cancel Subscription Section

    private var cancelSubscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                showCancelConfirmation = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))

                    Text("CANCEL SUBSCRIPTION")
                        .font(OPSStyle.Typography.captionBold)
                }
                .foregroundColor(OPSStyle.Colors.errorStatus)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // MARK: - Cancel Subscription Sheet

    @ViewBuilder
    private var cancelSubscriptionSheet: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Warning header
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(OPSStyle.Colors.errorStatus)

                                Text("CANCEL SUBSCRIPTION")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }

                            Text("Your team will lose access to OPS at the end of your billing period.")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.horizontal, 20)

                        // Reason input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("REASON FOR CANCELLATION")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            TextEditor(text: $cancellationReason)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .frame(minHeight: 100)
                                .padding(12)
                                .background(OPSStyle.Colors.subtleBackground)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .scrollContentBackground(.hidden)
                        }
                        .padding(.horizontal, 20)

                        // Priority support toggle (if applicable)
                        if company?.hasPrioritySupport == true {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $cancelPriorityToo) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Also cancel priority support")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)

                                        Text("Your priority support add-on will be cancelled")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.errorStatus))
                            }
                            .padding(.horizontal, 20)
                        }

                        Spacer()

                        // Action buttons
                        VStack(spacing: 12) {
                            // Cancel subscription button
                            Button(action: {
                                Task {
                                    await cancelSubscription()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    if isCancelling {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    }
                                    Text(isCancelling ? "CANCELLING..." : "CONFIRM CANCELLATION")
                                        .font(OPSStyle.Typography.captionBold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(OPSStyle.Colors.errorStatus)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            .disabled(isCancelling)

                            // Keep subscription button
                            Button(action: {
                                showCancelConfirmation = false
                            }) {
                                Text("KEEP SUBSCRIPTION")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                                    )
                            }
                            .disabled(isCancelling)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Cancel Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        showCancelConfirmation = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(isCancelling)
                }
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func cancelSubscription() async {
        guard let company = company,
              let userId = dataController.currentUser?.id,
              let plan = company.subscriptionPlanEnum else {
            errorMessage = "Unable to cancel subscription"
            return
        }

        isCancelling = true
        errorMessage = nil

        do {
            try await BubbleSubscriptionService.shared.cancelSubscription(
                userId: userId,
                companyId: company.id,
                reason: cancellationReason.isEmpty ? "No reason provided" : cancellationReason,
                cancelPriority: cancelPriorityToo,
                plan: plan
            )

            // Update local state
            company.subscriptionStatus = SubscriptionStatus.cancelled.rawValue
            try? dataController.modelContext?.save()

            showCancelConfirmation = false
            print("[SUBSCRIPTION] Subscription cancelled successfully")

        } catch {
            errorMessage = "Failed to cancel subscription"
            print("[SUBSCRIPTION] Error cancelling: \(error)")
        }

        isCancelling = false
    }

    // MARK: - Helpers

    private func statusColor(for status: SubscriptionStatus) -> Color {
        switch status {
        case .trial:
            return OPSStyle.Colors.primaryAccent
        case .active:
            return OPSStyle.Colors.successStatus
        case .grace:
            return OPSStyle.Colors.warningStatus
        case .expired, .cancelled:
            return OPSStyle.Colors.errorStatus
        }
    }

    private func formatPrice(_ cents: Int) -> String {
        if cents == 0 {
            return "Free"
        }
        let dollars = Double(cents) / 100.0
        return String(format: "$%.0f", dollars)
    }
}

// MARK: - Preview

#Preview {
    ManageSubscriptionView()
        .environmentObject(DataController())
        .environmentObject(SubscriptionManager.shared)
        .preferredColorScheme(.dark)
}
