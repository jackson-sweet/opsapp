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
        guard let company = dataController.getCurrentUserCompany(),
              let userId = dataController.currentUser?.id else { return false }
        return company.getSeatedEmployeeIds().contains(userId)
    }

    // Get seat count
    private var seatsInfo: (used: Int, total: Int) {
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
                    // Employee - just Continue button (full width, but hidden since we don't show next button)
                    EmptyView()
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

                // Explanation
                if !isSeated {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("About Seats")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Text("To access the app, your company admin needs to assign you a seat. Contact your manager if you don't have access.")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Helper Methods

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
            .background(isSelected ? Color.white.opacity(0.05) : OPSStyle.Colors.cardBackground)
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
