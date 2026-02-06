//
//  PostTutorialCTAScreen.swift
//  OPS
//
//  Transition screen after pre-signup tutorial.
//  Motivates user to create their account after seeing the product.
//

import SwiftUI

struct PostTutorialCTAScreen: View {
    @ObservedObject var manager: OnboardingManager

    // Animation states
    @State private var showTitle = false
    @State private var showSubtitle = false
    @State private var showButton = false
    @State private var showButtonText = false
    @State private var showButtonIcon = false

    /// Subtitle varies by selected flow
    private var subtitle: String {
        switch manager.state.flow {
        case .companyCreator:
            return "Set up your company and start managing real projects."
        case .employee:
            return "Join your crew and start tracking real work."
        case .none:
            return "Create your account to get started."
        }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Title with typewriter
                ZStack(alignment: .leading) {
                    Text("NOW LET'S MAKE IT REAL.")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.clear)

                    if showTitle {
                        TypewriterText(
                            "NOW LET'S MAKE IT REAL.",
                            font: OPSStyle.Typography.title,
                            color: OPSStyle.Colors.primaryText,
                            typingSpeed: 28
                        ) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    showSubtitle = true
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)

                // Subtitle
                ZStack(alignment: .leading) {
                    Text(subtitle)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(.clear)
                        .lineSpacing(4)

                    if showSubtitle {
                        TypewriterText(
                            subtitle,
                            font: OPSStyle.Typography.body,
                            color: OPSStyle.Colors.secondaryText,
                            typingSpeed: 40
                        ) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    showButton = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    showButtonText = true
                                }
                            }
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 40)

                Spacer()

                // CTA button
                Button {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    manager.goForward()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(Color.white)
                            .frame(height: 56)

                        HStack {
                            ZStack(alignment: .leading) {
                                Text("CREATE YOUR ACCOUNT")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(.clear)

                                if showButtonText {
                                    TypewriterText(
                                        "CREATE YOUR ACCOUNT",
                                        font: OPSStyle.Typography.bodyBold,
                                        color: .black,
                                        typingSpeed: 25
                                    ) {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation(.easeOut(duration: 0.4)) {
                                                showButtonIcon = true
                                            }
                                        }
                                    }
                                }
                            }

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                                .opacity(showButtonIcon ? 1 : 0)
                                .offset(x: showButtonIcon ? 0 : -10)
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(height: 56)
                }
                .disabled(!showButton)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 20)
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showTitle = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)
    manager.selectFlow(.companyCreator)

    return PostTutorialCTAScreen(manager: manager)
        .environmentObject(dataController)
}
