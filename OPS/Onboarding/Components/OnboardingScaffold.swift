//
//  OnboardingScaffold.swift
//  OPS
//
//  Base screen wrapper for new onboarding v3 screens.
//  Provides consistent layout with title, subtitle, back button, content, and footer areas.
//

import SwiftUI

struct OnboardingScaffold<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let showBackButton: Bool
    let onBack: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    // Standard horizontal padding for onboarding screens (40pt per spec)
    private let horizontalPadding: CGFloat = 40

    init(
        title: String,
        subtitle: String? = nil,
        showBackButton: Bool = true,
        onBack: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showBackButton = showBackButton
        self.onBack = onBack
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header area with back button and title
            headerSection

            // Main content area (no scroll)
            VStack(spacing: 20) {
                content()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 24)

            Spacer()

            // Footer area (fixed at bottom)
            footerSection
        }
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Back button row
            HStack {
                if showBackButton {
                    Button {
                        onBack?()
                    } label: {
                        Image(systemName: OPSStyle.Icons.back)
                            .font(.title2.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                } else {
                    // Placeholder for alignment
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }

            // Title
            Text(title)
                .font(OPSStyle.Typography.title)
                .foregroundColor(.white)

            // Subtitle (optional)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 16) {
            footer()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 40)
        .background(
            // Gradient fade from bottom
            LinearGradient(
                colors: [
                    OPSStyle.Colors.background.opacity(0),
                    OPSStyle.Colors.background.opacity(0.8),
                    OPSStyle.Colors.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .offset(y: -60)
            .allowsHitTesting(false),
            alignment: .top
        )
    }
}

// MARK: - Convenience Initializer (No Footer)

extension OnboardingScaffold where Footer == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        showBackButton: Bool = true,
        onBack: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showBackButton = showBackButton
        self.onBack = onBack
        self.content = content
        self.footer = { EmptyView() }
    }
}

// MARK: - Preview

#Preview("With Footer") {
    OnboardingScaffold(
        title: "CREATE YOUR ACCOUNT",
        subtitle: "Set up your business account to get started",
        showBackButton: true,
        onBack: { print("Back tapped") }
    ) {
        // Content
        VStack(spacing: 16) {
            Text("Content goes here")
                .foregroundColor(.white)

            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 8)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .frame(height: 56)
                    .overlay(
                        Text("Field \(i + 1)")
                            .foregroundColor(.white)
                    )
            }
        }
    } footer: {
        Button {
            print("Continue tapped")
        } label: {
            Text("CONTINUE")
                .font(OPSStyle.Typography.button)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(OPSStyle.Colors.primaryAccent)
                .foregroundColor(.black)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
}

#Preview("No Back Button") {
    OnboardingScaffold(
        title: "WELCOME",
        subtitle: "Operations Made Simple",
        showBackButton: false
    ) {
        VStack {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 80))
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            Text("Get started with OPS")
                .foregroundColor(.white)
        }
    } footer: {
        VStack(spacing: 12) {
            Button {
                print("Create company")
            } label: {
                Text("CREATE A COMPANY")
                    .font(OPSStyle.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(OPSStyle.Colors.primaryAccent)
                    .foregroundColor(.black)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }

            Button {
                print("Join company")
            } label: {
                Text("JOIN A COMPANY")
                    .font(OPSStyle.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.clear)
                    .foregroundColor(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                    )
            }
        }
    }
}
