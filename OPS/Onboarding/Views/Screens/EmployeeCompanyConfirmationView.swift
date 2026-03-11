//
//  EmployeeCompanyConfirmationView.swift
//  OPS
//
//  Confirmation screen shown after employee enters crew code.
//  Shows company name/logo so they can verify they joined the right one.
//

import SwiftUI

struct EmployeeCompanyConfirmationView: View {
    let companyName: String
    let companyLogoURL: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with logo
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
                .padding(.horizontal, 40)
                .padding(.top, 60)

                Spacer()

                // Company confirmation content
                VStack(spacing: 20) {
                    // Company logo or initial
                    if let logoURL = companyLogoURL, let url = URL(string: logoURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                            default:
                                companyInitialCircle
                            }
                        }
                        .opacity(logoOpacity)
                    } else {
                        companyInitialCircle
                            .opacity(logoOpacity)
                    }

                    // Welcome text
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WELCOME TO")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .tracking(2)

                        Text(companyName.uppercased())
                            .font(OPSStyle.Typography.largeTitle.weight(.bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(textOpacity)
                }
                .padding(.horizontal, 40)

                Spacer()

                // Bottom buttons
                VStack(spacing: 16) {
                    Button(action: onCancel) {
                        Text("NOT YOUR COMPANY?")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(minHeight: 44)
                    }

                    Button(action: onConfirm) {
                        HStack {
                            Text("CONTINUE")
                                .font(OPSStyle.Typography.bodyBold)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        }
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(OPSStyle.Colors.primaryText)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
                .opacity(buttonOpacity)
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            startAnimations()
            OnboardingSupabaseAnalytics.shared.trackStepView("confirmation")
        }
    }

    private var companyInitialCircle: some View {
        ZStack {
            Circle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            Text(String(companyName.prefix(1)).uppercased())
                .font(OPSStyle.Typography.title.weight(.bold))
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    private func startAnimations() {
        withAnimation(Animation.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) {
            logoOpacity = 1.0
        }
        withAnimation(Animation.easeIn(duration: 0.6).delay(0.5)) {
            textOpacity = 1.0
        }
        withAnimation(Animation.easeIn(duration: 0.5).delay(0.9)) {
            buttonOpacity = 1.0
        }
    }
}

// MARK: - Preview

#Preview("Employee Company Confirmation") {
    EmployeeCompanyConfirmationView(
        companyName: "Apex Roofing Co.",
        companyLogoURL: nil,
        onConfirm: {},
        onCancel: {}
    )
    .environment(\.colorScheme, .dark)
}

#Preview("Employee Company Confirmation - With Logo") {
    EmployeeCompanyConfirmationView(
        companyName: "Apex Roofing Co.",
        companyLogoURL: "https://example.com/logo.png",
        onConfirm: {},
        onCancel: {}
    )
    .environment(\.colorScheme, .dark)
}
