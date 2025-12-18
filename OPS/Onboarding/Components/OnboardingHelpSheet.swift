//
//  OnboardingHelpSheet.swift
//  OPS
//
//  Help modal sheet for onboarding v3 flow.
//  Provides contextual help with optional alternate action.
//

import SwiftUI

struct OnboardingHelpSheet: View {
    let title: String
    let description: String
    let alternateActionTitle: String?
    let onAlternateAction: (() -> Void)?
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        description: String,
        alternateActionTitle: String? = nil,
        onAlternateAction: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.title = title
        self.description = description
        self.alternateActionTitle = alternateActionTitle
        self.onAlternateAction = onAlternateAction
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 24) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(OPSStyle.Colors.tertiaryText)
                .frame(width: 40, height: 5)
                .padding(.top, 12)

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(title)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)

                // Description
                Text(description)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)

            Spacer()

            // Actions
            VStack(spacing: 16) {
                // Alternate action (if provided)
                if let alternateTitle = alternateActionTitle, let alternateAction = onAlternateAction {
                    Button {
                        alternateAction()
                        dismiss()
                    } label: {
                        Text(alternateTitle)
                            .font(OPSStyle.Typography.button)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.clear)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                            )
                    }
                }

                // Dismiss button
                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("GOT IT")
                        .font(OPSStyle.Typography.button)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(OPSStyle.Colors.primaryAccent)
                        .foregroundColor(.black)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(OPSStyle.Colors.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden) // We have our own
    }
}

// MARK: - Help Button

/// A help button that triggers a help sheet
struct OnboardingHelpButton: View {
    @State private var showHelp = false

    let title: String
    let description: String
    let alternateActionTitle: String?
    let onAlternateAction: (() -> Void)?

    init(
        title: String,
        description: String,
        alternateActionTitle: String? = nil,
        onAlternateAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.description = description
        self.alternateActionTitle = alternateActionTitle
        self.onAlternateAction = onAlternateAction
    }

    var body: some View {
        Button {
            showHelp = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: OPSStyle.Icons.info)
                    .font(.system(size: 14))
                Text("Need help?")
                    .font(OPSStyle.Typography.caption)
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
        .sheet(isPresented: $showHelp) {
            OnboardingHelpSheet(
                title: title,
                description: description,
                alternateActionTitle: alternateActionTitle,
                onAlternateAction: onAlternateAction
            )
        }
    }
}

// MARK: - Specific Help Sheets

/// Pre-configured help sheet for company code issues
struct CompanyCodeHelpSheet: View {
    let onCreateCompany: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        OnboardingHelpSheet(
            title: "NEED HELP?",
            description: "The company code is a unique identifier shared by your company admin. Ask them for the code, or if you're the admin, create your own company.",
            alternateActionTitle: "CREATE COMPANY INSTEAD?",
            onAlternateAction: onCreateCompany,
            onDismiss: onDismiss
        )
    }
}

/// Pre-configured help sheet for employees wanting to switch to company creator
struct SwitchToCompanyHelpSheet: View {
    let onSwitchToCompany: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        OnboardingHelpSheet(
            title: "CREATE A COMPANY?",
            description: "If you're starting a new company or are the company admin, you can create a company instead of joining one. This will let you invite team members using your own company code.",
            alternateActionTitle: "CREATE COMPANY",
            onAlternateAction: onSwitchToCompany,
            onDismiss: onDismiss
        )
    }
}

/// Pre-configured help sheet for company creators wanting to switch to employee
struct SwitchToEmployeeHelpSheet: View {
    let onSwitchToEmployee: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        OnboardingHelpSheet(
            title: "JOIN A COMPANY?",
            description: "If you've been invited to join an existing company, you can switch to the employee flow. You'll need the company code from your admin.",
            alternateActionTitle: "JOIN COMPANY",
            onAlternateAction: onSwitchToEmployee,
            onDismiss: onDismiss
        )
    }
}

// MARK: - Previews

#Preview("Basic Help Sheet") {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            OnboardingHelpSheet(
                title: "NEED HELP?",
                description: "The company code is a unique identifier shared by your company admin. Ask them for the code, or if you're the admin, create your own company."
            )
        }
}

#Preview("Help Sheet with Alternate Action") {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            OnboardingHelpSheet(
                title: "NEED HELP?",
                description: "The company code is a unique identifier shared by your company admin. Ask them for the code, or if you're the admin, create your own company.",
                alternateActionTitle: "CREATE COMPANY INSTEAD?",
                onAlternateAction: { print("Create company") }
            )
        }
}

#Preview("Help Button") {
    VStack {
        Spacer()
        OnboardingHelpButton(
            title: "NEED HELP?",
            description: "This is helpful information about the current screen.",
            alternateActionTitle: "TRY SOMETHING ELSE?",
            onAlternateAction: { print("Alternate action") }
        )
        .padding(.bottom, 40)
    }
    .frame(maxWidth: .infinity)
    .background(OPSStyle.Colors.background)
}
