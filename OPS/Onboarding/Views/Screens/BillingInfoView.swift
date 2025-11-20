//
//  BillingInfoView.swift
//  OPS
//
//  Shows billing information during onboarding with two variations:
//  1. Company Creator: Shows trial info, pricing tiers, and upgrade options
//  2. Employee: Shows company plan status and seat assignment info
//

import SwiftUI

struct BillingInfoView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var selectedPlan: SubscriptionPlan = .starter
    @State private var showPlanSelection = false
    @State private var isRefreshing = false
    @State private var refreshTrigger = false // Toggle to force view refresh

    // Optional closure to call when continue is tapped (for use in WelcomeGuideView)
    var onContinue: (() -> Void)? = nil

    // Determine if current user is the company creator
    private var isCompanyCreator: Bool {
        onboardingViewModel.selectedUserType == .company
    }

    // Get trial end date
    private var trialEndDate: Date? {
        guard let company = dataController.getCurrentUserCompany() else { return nil }
        return company.trialEndDate
    }

    // Get current user's seated status
    private var isSeated: Bool {
        let _ = refreshTrigger // Force dependency on refresh trigger
        guard let company = dataController.getCurrentUserCompany(),
              let userId = dataController.currentUser?.id else { return false }
        return company.getSeatedEmployeeIds().contains(userId)
    }

    // Get seat count
    private var seatsInfo: (used: Int, total: Int) {
        let _ = refreshTrigger // Force dependency on refresh trigger
        guard let company = dataController.getCurrentUserCompany() else { return (0, 10) }
        return (company.getSeatedEmployeeIds().count, company.maxSeats)
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 32) {
                // Content
                if isCompanyCreator {
                    companyCreatorView
                } else {
                    employeeView
                }

                Spacer()

                // Bottom buttons
                if isCompanyCreator {
                    // Company: Upgrade (1/3) and Continue Trial (2/3)
                    HStack(spacing: 12) {
                        // Upgrade button (1/3 width)
                        Button(action: {
                            showPlanSelection = true
                        }) {
                            Text("UPGRADE")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                )
                        }
                        .frame(width: UIScreen.main.bounds.width * 0.25)

                        // Continue Trial button (2/3 width)
                        Button(action: {
                            if let onContinue = onContinue {
                                onContinue()
                            } else {
                                onboardingViewModel.moveToNextStep()
                            }
                        }) {
                            Text("CONTINUE TRIAL")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.white)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                } else {
                    // Employee - Continue button (matches NEXT button styling)
                    Button(action: {
                        if let onContinue = onContinue {
                            onContinue()
                        } else {
                            onboardingViewModel.moveToNextStep()
                        }
                    }) {
                        Text("NEXT")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                            )
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 34)
        }
        .sheet(isPresented: $showPlanSelection) {
            PlanSelectionView()
                .environmentObject(dataController)
                .environmentObject(subscriptionManager)
                .onDisappear {
                    // If they completed payment, move to next step
                    if let company = dataController.getCurrentUserCompany(),
                       company.subscriptionStatus != "trial" {
                        onboardingViewModel.moveToNextStep()
                    }
                }
        }
        .onAppear {
            // For employees, refresh company data to get latest seat assignment
            if !isCompanyCreator {
                refreshCompanyData()
            }
        }
    }

    // MARK: - Helper Methods

    private func refreshCompanyData() {
        guard !isRefreshing else {
            print("[BILLING_INFO] Refresh already in progress")
            return
        }

        isRefreshing = true

        Task {
            // First, check data health
            let healthManager = await DataHealthManager(
                dataController: dataController,
                authManager: AuthManager()  // Create a temporary instance
            )

            let (healthState, recoveryAction) = await healthManager.performHealthCheck()

            if !healthState.isHealthy {
                print("[BILLING_INFO] ⚠️ Data health check failed: \(healthState)")
                print("[BILLING_INFO] 🔧 Executing recovery action: \(recoveryAction)")
                await healthManager.executeRecoveryAction(recoveryAction)
                await MainActor.run {
                    isRefreshing = false
                }
                return
            }

            // Data is healthy, proceed with sync
            guard let syncManager = dataController.syncManager else {
                print("[BILLING_INFO] ❌ SyncManager still nil after health check")
                await MainActor.run {
                    isRefreshing = false
                }
                return
            }

            do {
                // Fetch latest company data from API
                print("[BILLING_INFO] 🔄 Refreshing company data for seat info...")
                try await syncManager.syncCompany()

                await MainActor.run {
                    isRefreshing = false
                    print("[BILLING_INFO] ✅ Company data refreshed")

                    // Log seat info for debugging
                    if let company = dataController.getCurrentUserCompany() {
                        let seatedIds = company.getSeatedEmployeeIds()
                        let isSeated = seatedIds.contains(dataController.currentUser?.id ?? "")
                        print("[BILLING_INFO]    - Seats used: \(seatedIds.count)/\(company.maxSeats)")
                        print("[BILLING_INFO]    - User is seated: \(isSeated)")
                    }

                    // Toggle refresh trigger to force view update
                    refreshTrigger.toggle()
                    print("[BILLING_INFO] 🔄 Triggered view refresh")
                }
            } catch {
                print("[BILLING_INFO] ⚠️ Failed to refresh company data: \(error)")
                await MainActor.run {
                    isRefreshing = false
                }
            }
        }
    }

    // MARK: - Company Creator View

    private var companyCreatorView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR TRIAL")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if let endDate = trialEndDate {
                    Text("Expires \(formatDate(endDate))")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                } else {
                    Text("30 days free access")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Trial benefits
            VStack(alignment: .leading, spacing: 8) {
                FeatureBullet(text: "Full access to all features")
                FeatureBullet(text: "Up to 10 team members")
                FeatureBullet(text: "No credit card required")
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            Divider()
                .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Pricing tiers header
            VStack(alignment: .leading, spacing: 4) {
                Text("UPGRADE ANYTIME")
                    .font(OPSStyle.Typography.cardSubtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Choose a plan that fits your team")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Plan cards
            VStack(spacing: 8) {
                PlanSummaryCard(
                    plan: .starter,
                    isSelected: selectedPlan == .starter,
                    onTap: { selectedPlan = .starter }
                )

                PlanSummaryCard(
                    plan: .team,
                    isSelected: selectedPlan == .team,
                    onTap: { selectedPlan = .team }
                )

                PlanSummaryCard(
                    plan: .business,
                    isSelected: selectedPlan == .business,
                    onTap: { selectedPlan = .business }
                )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Employee View

    private var employeeView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("COMPANY SUBSCRIPTION")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if let company = dataController.getCurrentUserCompany() {
                    Text(company.name)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Current plan info
            if let company = dataController.getCurrentUserCompany(),
               let planStr = company.subscriptionPlan,
               let plan = SubscriptionPlan(rawValue: planStr) {

                VStack(alignment: .leading, spacing: 12) {
                    // Plan name
                    HStack {
                        Text("Current Plan:")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        Text(plan.displayName.uppercased())
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)

                    // Trial expiry (if on trial)
                    if plan == .trial, let endDate = trialEndDate {
                        HStack(spacing: 10) {
                            Image(systemName: "clock")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Trial expires")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Text(formatDate(endDate))
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                        }
                        .padding(12)
                        .background(OPSStyle.Colors.warningStatus.opacity(0.1))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }

            Divider()
                .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Seat information
            VStack(alignment: .leading, spacing: 12) {
                Text("SEAT ASSIGNMENT")
                    .font(OPSStyle.Typography.cardSubtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                // Seat status
                HStack(spacing: 12) {
                    Image(systemName: isSeated ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isSeated ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isSeated ? "You have a seat" : "No seat assigned")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("\(seatsInfo.used) of \(seatsInfo.total) seats used")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                .padding(12)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)

                // Contact admin section (if no seat)
                if !isSeated {
                    VStack(spacing: 24) {
                        // Simple message
                        Text("You don't have a seat in your company's OPS subscription. Contact your administrator to request access.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)

                        // Admin contact info
                        if let company = dataController.getCurrentUserCompany(),
                           let adminIds = company.getAdminIds().first,
                           let admin = dataController.getUser(id: adminIds) {

                            VStack(spacing: 20) {
                                // Admin info - no background, no avatar
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(admin.firstName) \(admin.lastName)")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    Text("ADMINISTRATOR")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }

                                // Contact buttons
                                HStack(spacing: 12) {
                                    if let phone = admin.phone {
                                        Button(action: {
                                            if let url = URL(string: "tel://\(phone)") {
                                                UIApplication.shared.open(url)
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "phone.fill")
                                                    .font(.system(size: 12))
                                                Text("CALL")
                                                    .font(OPSStyle.Typography.captionBold)
                                            }
                                            .foregroundColor(.black)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.white)
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        }
                                    }

                                    if let email = admin.email {
                                        Button(action: {
                                            if let url = URL(string: "mailto:\(email)?subject=OPS%20App%20Access%20Request") {
                                                UIApplication.shared.open(url)
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "envelope.fill")
                                                    .font(.system(size: 12))
                                                Text("EMAIL")
                                                    .font(OPSStyle.Typography.captionBold)
                                            }
                                            .foregroundColor(.black)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.white)
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct PlanSummaryCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let onTap: () -> Void

    private var monthlyPrice: String {
        String(format: "$%.0f", Double(plan.monthlyPrice) / 100.0)
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayName.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("\(plan.maxSeats) seats")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(monthlyPrice)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("/MONTH")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText.opacity(0.5))
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(isSelected ? OPSStyle.Colors.subtleBackground : OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FeatureBullet: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }
}

// MARK: - Preview

#Preview("Company Creator") {
    PreviewWrapper(userType: .company)
}

#Preview("Employee") {
    PreviewWrapper(userType: .employee)
}

// Helper view for previews
private struct PreviewWrapper: View {
    let userType: UserType
    @StateObject private var viewModel: OnboardingViewModel
    @StateObject private var dataController: DataController

    init(userType: UserType) {
        self.userType = userType
        let dc = OnboardingPreviewHelpers.createPreviewDataController()
        _dataController = StateObject(wrappedValue: dc)

        let vm = OnboardingViewModel()
        vm.selectedUserType = userType
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        BillingInfoView()
            .environmentObject(viewModel)
            .environmentObject(dataController)
            .environmentObject(SubscriptionManager.shared)
    }
}
