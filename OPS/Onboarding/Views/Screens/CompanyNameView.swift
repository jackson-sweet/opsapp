//
//  CompanyNameView.swift
//  OPS
//
//  Collects company name after authentication in the A/B/C onboarding flow.
//  Creates the company via OnboardingManager and returns the crew code.
//

import SwiftUI

struct CompanyNameView: View {
    @ObservedObject var onboardingManager: OnboardingManager
    let variant: OnboardingVariant
    let onComplete: (String) -> Void  // passes crew code

    @State private var companyName = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - Header with logo
                    HStack(alignment: .bottom) {
                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .padding(.bottom, 8)
                        Text("OPS")
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()
                    }
                    .padding(.leading, 4)

                    Spacer().frame(height: 40)

                    // MARK: - Headline
                    HStack {
                        Text("NAME YOUR COMPANY")
                            .font(OPSStyle.Typography.heading)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                    }

                    Spacer().frame(height: 12)

                    HStack {
                        Text("This is how your crew will find you on OPS.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                    }

                    Spacer().frame(height: 40)

                    // MARK: - Company name field
                    VStack(spacing: 8) {
                        TextField("", text: $companyName, prompt: Text("Company Name").foregroundColor(OPSStyle.Colors.secondaryText))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .textContentType(.organizationName)
                            .autocapitalization(.words)
                            .disableAutocorrection(false)

                        Rectangle()
                            .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                            .frame(height: 1)
                    }

                    Spacer().frame(height: 32)

                    // MARK: - Error message
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 12)
                    }

                    // MARK: - Continue button
                    Button(action: handleContinue) {
                        ZStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                            } else {
                                Text("CONTINUE")
                                    .font(OPSStyle.Typography.button)
                                    .foregroundColor(OPSStyle.Colors.invertedText)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.primaryText)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            HStack {
                                Spacer()
                                if !isLoading {
                                    Image(OPSStyle.Icons.arrowRight)
                                        .foregroundColor(OPSStyle.Colors.invertedText)
                                        .font(OPSStyle.Typography.caption.weight(.semibold))
                                        .padding(.trailing, 20)
                                }
                            }
                        )
                    }
                    .disabled(isLoading)

                    Spacer().frame(height: 20)
                }
                .padding(40)
            }
        }
        .onAppear { OnboardingSupabaseAnalytics.shared.trackStepView("company_name") }
    }

    // MARK: - Actions

    private func handleContinue() {
        let trimmed = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter your company name."
            return
        }

        isLoading = true
        errorMessage = ""

        // Set company name in onboarding state
        onboardingManager.state.companyData.name = trimmed

        Task { @MainActor in
            do {
                let crewCode = try await onboardingManager.createCompany()
                isLoading = false
                onComplete(crewCode)
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
