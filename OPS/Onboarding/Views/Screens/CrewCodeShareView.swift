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
    let variant: OnboardingVariant  // for analytics
    let onContinue: () -> Void

    @State private var showCopyFeedback = false
    @State private var showShareSheet = false

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
                        Text("YOUR CREW CODE")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // 3. Subtext
                        Text("Share this code with your team so they can join your company on OPS.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // 4. Code display box
                        VStack(spacing: 24) {
                            // Label row with inline copy button
                            HStack {
                                Text("COMPANY CODE")
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

                        // 5. Share via text button (outline style)
                        Button(action: shareCode) {
                            HStack(spacing: 12) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                                Text("SHARE VIA TEXT")
                                    .font(OPSStyle.Typography.button)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.tertiaryText.opacity(0.5), lineWidth: 1)
                            )
                        }

                        // 7. Info box
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: OPSStyle.Icons.info)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .font(OPSStyle.Typography.body)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("HOW IT WORKS")
                                        .font(OPSStyle.Typography.cardSubtitle)
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    Text("Your crew uses this code to join your company.")
                                        .font(OPSStyle.Typography.cardBody)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                            }

                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "shield")
                                    .foregroundColor(OPSStyle.Colors.successStatus)
                                    .font(OPSStyle.Typography.body)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("KEEP IT SECURE")
                                        .font(OPSStyle.Typography.cardSubtitle)
                                        .fontWeight(.semibold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    Text("Only share with crew you trust.")
                                        .font(OPSStyle.Typography.cardBody)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                            }
                        }
                        .padding(OPSStyle.Layout.spacing3)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(OPSStyle.Colors.primaryAccent.opacity(0.1))
                        )
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.bottom, 120)
                }

                // 6. Continue button pinned at bottom
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
                                    Image(systemName: "arrow.right")
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
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
                )
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewControllerWrapper(
                activityItems: [shareMessage]
            )
        }
    }

    // MARK: - Computed

    private var shareMessage: String {
        "Join my company on OPS! Use crew code: \(crewCode). Download OPS: [app store link placeholder]"
    }

    // MARK: - Actions

    private func copyCode() {
        UIPasteboard.general.string = crewCode
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

    private func shareCode() {
        showShareSheet = true
        AnalyticsManager.shared.trackCrewCodeAction(variant: variant.rawValue, action: "shared")
    }

    private func handleContinue() {
        AnalyticsManager.shared.trackCrewCodeAction(variant: variant.rawValue, action: "skipped")
        onContinue()
    }
}

// MARK: - UIActivityViewController Wrapper

/// Wraps UIActivityViewController for SwiftUI share sheet presentation.
private struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview("Crew Code Share") {
    CrewCodeShareView(
        crewCode: "ABCD1234",
        variant: .A,
        onContinue: {}
    )
    .environment(\.colorScheme, .dark)
}

#Preview("Crew Code Share - Variant B") {
    CrewCodeShareView(
        crewCode: "XYZ98765",
        variant: .B,
        onContinue: {}
    )
    .environment(\.colorScheme, .dark)
}
