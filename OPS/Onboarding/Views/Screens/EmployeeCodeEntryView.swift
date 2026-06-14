//
//  EmployeeCodeEntryView.swift
//  OPS
//
//  Standalone crew code entry for the employee onboarding flow.
//  Looks up company by code and passes info to confirmation screen.
//

import SwiftUI

struct EmployeeCodeEntryView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    let onCompanyFound: (_ companyName: String, _ companyLogoURL: String?) -> Void
    var onBack: (() -> Void)? = nil
    var onSignOut: (() -> Void)? = nil
    var initialCode: String? = nil

    @State private var companyCode: String = ""
    @State private var errorMessage: String?
    @State private var isLooking = false
    @FocusState private var isInputFocused: Bool

    private var isFormValid: Bool {
        !companyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with sign out button
            HStack {
                Spacer()
                if let signOut = onSignOut {
                    Button {
                        signOut()
                    } label: {
                        Text("SIGN OUT")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                } else if let back = onBack {
                    // Legacy fallback if onBack is provided
                    Button {
                        back()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, OPSStyle.Layout.spacing3)

            // Title
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("JOIN YOUR CREW")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Enter the code your boss gave you.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, OPSStyle.Layout.spacing5)

            Spacer()

            // Code input
            VStack(spacing: 0) {
                ExpandingBracketInput(
                    text: $companyCode,
                    isFocused: _isInputFocused,
                    placeholder: "CODE"
                )

                if let error = errorMessage {
                    Text(error)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .padding(.top, OPSStyle.Layout.spacing3)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Bottom button
            VStack(spacing: OPSStyle.Layout.spacing3) {
                Button {
                    lookupCompany()
                } label: {
                    ZStack {
                        if isLooking {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                        } else {
                            HStack {
                                Text("JOIN CREW")
                                    .font(OPSStyle.Typography.bodyBold)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            }
                        }
                    }
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(isFormValid ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(!isFormValid || isLooking)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .onTapGesture { isInputFocused = false }
        .onAppear {
            if let code = initialCode, !code.isEmpty, companyCode.isEmpty {
                companyCode = code
            }
            OnboardingSupabaseAnalytics.shared.trackStepView("code_entry")
        }
    }

    // MARK: - Lookup

    private func lookupCompany() {
        guard isFormValid else { return }
        isLooking = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let companyDTO = try await onboardingManager.lookupCompanyByCode(companyCode)
                isLooking = false

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                onCompanyFound(companyDTO.name, companyDTO.logoUrl)
            } catch {
                isLooking = false
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)

                if let onboardingError = error as? OnboardingManagerError {
                    switch onboardingError {
                    case .invalidCompanyCode:
                        errorMessage = "No company found with that code. Check with your boss."
                    default:
                        errorMessage = error.localizedDescription
                    }
                } else {
                    errorMessage = "Something went wrong. Try again."
                }
            }
        }
    }
}
