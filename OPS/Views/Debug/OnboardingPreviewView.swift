//
//  OnboardingPreviewView.swift
//  OPS
//
//  Developer tool for previewing onboarding flow with pre-filled company data.
//

import SwiftUI

struct OnboardingPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @State private var selectedFlow: OnboardingFlow = .companyCreator
    @State private var selectedScreen: OnboardingScreen = .welcome
    @State private var showOnboarding = false
    @State private var previewManager: OnboardingManager?

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                ZStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: OPSStyle.Icons.close)
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }

                        Spacer()
                    }

                    Text("Onboarding Preview")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Flow Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("FLOW TYPE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            HStack(spacing: 12) {
                                FlowButton(
                                    title: "COMPANY",
                                    isSelected: selectedFlow == .companyCreator,
                                    action: { selectedFlow = .companyCreator }
                                )

                                FlowButton(
                                    title: "EMPLOYEE",
                                    isSelected: selectedFlow == .employee,
                                    action: { selectedFlow = .employee }
                                )
                            }
                        }

                        // Starting Screen Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("STARTING SCREEN")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            let screens = selectedFlow == .companyCreator ? companyScreens : employeeScreens

                            ForEach(screens, id: \.self) { screen in
                                ScreenRow(
                                    screen: screen,
                                    isSelected: selectedScreen == screen,
                                    action: { selectedScreen = screen }
                                )
                            }
                        }

                        // Prefilled Data Info
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PREFILLED DATA")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            VStack(alignment: .leading, spacing: 8) {
                                if let user = dataController.currentUser {
                                    PrefilledRow(label: "Name", value: user.fullName)
                                    PrefilledRow(label: "Email", value: user.email ?? "—")
                                    PrefilledRow(label: "Phone", value: user.phone ?? "—")
                                }

                                if let company = dataController.getCurrentUserCompany() {
                                    PrefilledRow(label: "Company", value: company.name)
                                    PrefilledRow(label: "Code", value: company.externalId ?? "—")
                                }
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }

                        Spacer()
                            .frame(height: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }

                // Launch Button
                Button(action: launchPreview) {
                    Text("LAUNCH PREVIEW")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(Color.white)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            if let manager = previewManager {
                OnboardingContainer(manager: manager, onComplete: {
                    showOnboarding = false
                })
                .environmentObject(dataController)
                .environmentObject(SubscriptionManager.shared)
            }
        }
        .onChange(of: selectedFlow) { _, _ in
            // Reset to appropriate first screen when flow changes
            selectedScreen = .welcome
        }
    }

    // Company flow screens
    private var companyScreens: [OnboardingScreen] {
        [.welcome, .credentials, .profileCompany, .ready]
    }

    // Employee flow screens
    private var employeeScreens: [OnboardingScreen] {
        [.welcome, .credentials, .profileJoin, .ready]
    }

    private func launchPreview() {
        // Create fresh manager
        let manager = OnboardingManager(dataController: dataController)

        // Set the flow
        manager.selectFlow(selectedFlow)

        // Set the starting screen
        manager.goToScreen(selectedScreen)

        previewManager = manager
        showOnboarding = true
    }
}

// MARK: - Supporting Views

private struct FlowButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.button)
                .foregroundColor(isSelected ? .black : OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? Color.white : Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(isSelected ? Color.clear : OPSStyle.Colors.primaryAccent, lineWidth: 1)
                )
        }
    }
}

private struct ScreenRow: View {
    let screen: OnboardingScreen
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(screen.title.uppercased())
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct PrefilledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineLimit(1)
        }
    }
}

#Preview {
    OnboardingPreviewView()
        .environmentObject(DataController())
}
