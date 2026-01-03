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
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var showPlanSelection = false
    @State private var isRefreshing = false
    @State private var refreshTrigger = false // Toggle to force view refresh

    // Animation states
    @State private var showTitle = false
    @State private var showContent = false
    @State private var animationKey = UUID()

    // Whether this page is currently active (for triggering animations)
    var isActive: Bool = true

    // Optional closure to call when continue is tapped (for use in WelcomeGuideView)
    var onContinue: (() -> Void)? = nil

    // User type passed in (defaults to checking current user)
    var userType: UserType?

    // Determine if current user is the company creator
    private var isCompanyCreator: Bool {
        if let type = userType {
            return type == .company
        }
        // Fallback: check current user's type
        return dataController.currentUser?.userType == .company
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
        VStack(spacing: 0) {
            // Content - fills available space, button handled by ReadyScreen
            if isCompanyCreator {
                companyCreatorView
            } else {
                employeeView
            }

            Spacer()
        }
        .sheet(isPresented: $showPlanSelection) {
            PlanSelectionView()
                .environmentObject(dataController)
                .environmentObject(subscriptionManager)
                .onDisappear {
                    // If they completed payment, move to next step
                    if let company = dataController.getCurrentUserCompany(),
                       company.subscriptionStatus != "trial" {
                        onContinue?()
                    }
                }
        }
        .onChange(of: isActive) { _, nowActive in
            if nowActive {
                startAnimations()
            }
        }
        .onAppear {
            // Start animations if already active
            if isActive {
                startAnimations()
            }

            // For employees, refresh company data to get latest seat assignment
            if !isCompanyCreator {
                refreshCompanyData()
            }
        }
    }

    private func startAnimations() {
        // Reset state
        showTitle = false
        showContent = false
        animationKey = UUID()

        // Start title typing after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showTitle = true
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

            let (healthState, recoveryAction) = await healthManager.performHealthCheck(duringOnboarding: true)

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
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: 60)

            // Header with typewriter animation
            HStack(spacing: 0) {
                if showTitle {
                    TypewriterText(
                        "30 DAYS FREE",
                        font: OPSStyle.Typography.title,
                        color: OPSStyle.Colors.primaryText,
                        typingSpeed: 28
                    ) {
                        // Show content after title completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeOut(duration: 0.4)) {
                                showContent = true
                            }
                        }
                    }
                    .id(animationKey)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 16)

            Spacer()
                .frame(height: 48)

            // Content with fade-in animation
            VStack(alignment: .leading, spacing: 16) {
                Text("Full access. No card required.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()
                    .frame(height: 8)

                VStack(alignment: .leading, spacing: 0) {
                    trialBenefitRow(text: "Every feature unlocked", index: 0)
                    trialBenefitRow(text: "Up to 10 team members", index: 1)
                    trialBenefitRow(text: "Unlimited projects", index: 2, isLast: true)
                }

                Spacer()
                    .frame(height: 24)

                Button {
                    showPlanSelection = true
                } label: {
                    HStack(spacing: 8) {
                        Text("SEE PLANS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
        }
    }

    private func trialBenefitRow(text: String, index: Int, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("→")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text(text)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .padding(.vertical, 12)

            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Employee View

    private var employeeView: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)

            // Header with typewriter animation
            HStack(spacing: 0) {
                if showTitle {
                    TypewriterText(
                        "YOU'RE IN.",
                        font: OPSStyle.Typography.title,
                        color: OPSStyle.Colors.primaryText,
                        typingSpeed: 28
                    ) {
                        // Show content after title completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.easeOut(duration: 0.4)) {
                                showContent = true
                            }
                        }
                    }
                    .id(animationKey)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 48)

            // Content with fade-in animation
            VStack(alignment: .leading, spacing: 16) {
                if let company = dataController.getCurrentUserCompany() {
                    Text(company.name)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR SEAT")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    HStack(spacing: 12) {
                        Image(systemName: isSeated ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(isSeated ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isSeated ? "You have a seat." : "No seat assigned yet.")
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

                    if !isSeated {
                        VStack(alignment: .leading, spacing: 16) {
                            // Show warning if no seats available
                            if seatsInfo.used >= seatsInfo.total {
                                Text("You will not be able to use the app until your administrator gives you access.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                            } else {
                                Text("Contact your admin to get access.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }

                            if let company = dataController.getCurrentUserCompany(),
                               let adminId = company.getAdminIds().first,
                               let admin = dataController.getUser(id: adminId) {

                                VStack(alignment: .leading, spacing: 12) {
                                    Text("\(admin.firstName) \(admin.lastName)")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    HStack(spacing: 12) {
                                        if let phone = admin.phone {
                                            Button {
                                                if let url = URL(string: "tel://\(phone)") {
                                                    UIApplication.shared.open(url)
                                                }
                                            } label: {
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
                                            Button {
                                                if let url = URL(string: "mailto:\(email)?subject=OPS%20App%20Access%20Request") {
                                                    UIApplication.shared.open(url)
                                                }
                                            } label: {
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
            }
            .padding(.horizontal, 40)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Company Creator") {
    BillingInfoView(userType: .company)
        .environmentObject(DataController())
        .environmentObject(SubscriptionManager.shared)
}

#Preview("Employee") {
    BillingInfoView(userType: .employee)
        .environmentObject(DataController())
        .environmentObject(SubscriptionManager.shared)
}
