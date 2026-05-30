//
//  CrewCodeShareView.swift
//  OPS
//
//  Standalone crew code display shown immediately after signup
//  in all A/B/C onboarding variants. Not tied to OnboardingViewModel.
//

import SwiftUI

struct CrewCodeShareView: View {
    let crewCode: String
    let companyName: String
    let companyId: String
    let variant: OnboardingVariant  // for analytics
    let onContinue: () -> Void

    @State private var showCopyFeedback = false
    @State private var showInviteSheet = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Main scrollable content
                ScrollView {
                    VStack(spacing: 32) {
                        // 1. Logo + brand
                        HStack(alignment: .bottom) {
                            Image("LogoWhite")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 44, height: 44)
                                .padding(.bottom, 8)
                            Text("OPS")
                                .font(OPSStyle.Typography.largeTitle.weight(.bold))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)

                        // 2. Headline
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOU'RE SET UP.")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Text("\(companyName) is ready.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // 3. Code display box
                        VStack(spacing: 24) {
                            // Label row with inline copy button
                            HStack {
                                Text("CREW CODE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Spacer()

                                Button(action: copyCode) {
                                    HStack(spacing: 4) {
                                        Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                        Text(showCopyFeedback ? "COPIED!" : "COPY")
                                            .font(OPSStyle.Typography.smallCaption)
                                    }
                                    .foregroundColor(showCopyFeedback ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)
                                }
                            }

                            // Code text in box
                            HStack {
                                Text(crewCode.uppercased())
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .tracking(2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)

                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }

                        // 4. Share this with your crew
                        Text("Share this with your crew so they can join.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // 5. Invite crew button
                        Button {
                            showInviteSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image("ops.sub-client")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                                Text("INVITE CREW")
                                    .font(OPSStyle.Typography.bodyBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.tertiaryText.opacity(0.5), lineWidth: 1)
                            )
                        }

                        // 6. Info text
                        Text("You'll find this code in Settings anytime.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.bottom, 120)
                }

                // 7. Continue button pinned at bottom
                VStack(spacing: 16) {
                    Button(action: handleContinue) {
                        Text("CONTINUE")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .background(OPSStyle.Colors.primaryText)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                HStack {
                                    Spacer()
                                    Image("ops.arrow-right")
                                        .foregroundColor(OPSStyle.Colors.invertedText)
                                        .font(OPSStyle.Typography.caption.weight(.semibold))
                                        .padding(.trailing, 20)
                                }
                            )
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, 34)
                .background(
                    Rectangle()
                        .fill(OPSStyle.Colors.background)
                        .shadow(color: Color.black, radius: 8, x: 0, y: -4)
                )
            }
        }
        .onAppear { OnboardingSupabaseAnalytics.shared.trackStepView("crew_code") }
        .sheet(isPresented: $showInviteSheet) {
            InviteTeamSheet(
                companyCode: crewCode,
                companyName: companyName,
                companyId: companyId,
                isPresented: $showInviteSheet
            )
        }
    }

    // MARK: - Actions

    private func copyCode() {
        UIPasteboard.general.string = crewCode

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        withAnimation(OPSStyle.Animation.fast) {
            showCopyFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(OPSStyle.Animation.fast) {
                showCopyFeedback = false
            }
        }
        AnalyticsManager.shared.trackCrewCodeAction(variant: variant.rawValue, action: "copied")
    }

    private func handleContinue() {
        AnalyticsManager.shared.trackCrewCodeAction(variant: variant.rawValue, action: "continued")
        onContinue()
    }
}

// MARK: - Preview

#Preview("Crew Code Share") {
    CrewCodeShareView(
        crewCode: "ABCD1234",
        companyName: "Acme Construction",
        companyId: "test-company-id",
        variant: .A,
        onContinue: {}
    )
    .environment(\.colorScheme, .dark)
}

#Preview("Crew Code Share - Variant B") {
    CrewCodeShareView(
        crewCode: "XYZ98765",
        companyName: "Smith Roofing",
        companyId: "test-company-id-2",
        variant: .B,
        onContinue: {}
    )
    .environment(\.colorScheme, .dark)
}
