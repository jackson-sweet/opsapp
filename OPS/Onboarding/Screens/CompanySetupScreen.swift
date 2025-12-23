//
//  CompanySetupScreen.swift
//  OPS
//
//  Company setup screen - page 1: name, logo, email, phone.
//  Part of the company creator flow.
//  Uses phased animation system for entrance effects.
//

import SwiftUI

struct CompanySetupScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    @State private var companyName: String = ""
    @State private var officeEmail: String = ""
    @State private var officePhone: String = ""
    @State private var logoData: Data?
    @FocusState private var focusedField: Field?

    // Animation coordinator
    @StateObject private var animationCoordinator = OnboardingAnimationCoordinator()

    enum Field {
        case name, email, phone
    }

    private var isFormValid: Bool {
        !companyName.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back and sign out
            OnboardingHeader(
                showBack: true,
                onBack: { manager.goToScreen(.profile) },
                onSignOut: { manager.signOut() }
            )
            .padding(.horizontal, 40)
            .padding(.top, 16)

            // Title section with phased typing animation
            PhasedOnboardingHeader(
                title: "YOUR COMPANY",
                subtitle: "This is how you'll appear to your crew.",
                coordinator: animationCoordinator
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 16)

            Spacer()
                .frame(height: 32)

            // Content section - fades in upward
            PhasedContent(coordinator: animationCoordinator) {
                VStack(spacing: 0) {
                    // Company logo
                    VStack(spacing: 12) {
                        ProfileImageUploader(
                            config: ImageUploaderConfig(
                                currentImageData: logoData,
                                placeholderText: companyInitials,
                                size: 100,
                                shape: .roundedSquare(cornerRadius: 16),
                                allowDelete: true,
                                backgroundColor: OPSStyle.Colors.cardBackgroundDark
                            ),
                            onUpload: { image in
                                logoData = image.jpegData(compressionQuality: 0.8)
                                return ""
                            },
                            onDelete: {
                                logoData = nil
                            }
                        )

                        VStack(spacing: 2) {
                            PhasedLabel("COMPANY LOGO", index: 0, coordinator: animationCoordinator)
                            Text("Optional")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }

                    Spacer()
                        .frame(height: 32)

                    // Form fields
                    VStack(spacing: 20) {
                        // Company name
                        VStack(alignment: .leading, spacing: 8) {
                            PhasedLabel("COMPANY NAME", index: 1, coordinator: animationCoordinator)

                            TextField("", text: $companyName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .autocapitalization(.words)
                                .focused($focusedField, equals: .name)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }

                        // Office email
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                PhasedLabel("OFFICE EMAIL", index: 2, coordinator: animationCoordinator)

                                Spacer()

                                if !manager.state.userData.email.isEmpty && officeEmail != manager.state.userData.email {
                                    Button {
                                        officeEmail = manager.state.userData.email
                                    } label: {
                                        Text("Use mine")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                }
                            }

                            TextField("", text: $officeEmail)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .focused($focusedField, equals: .email)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }

                        // Office phone
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                PhasedLabel("OFFICE PHONE", index: 3, isLast: true, coordinator: animationCoordinator)

                                Spacer()

                                if !manager.state.userData.phone.isEmpty && officePhone != manager.state.userData.phone {
                                    Button {
                                        officePhone = manager.state.userData.phone
                                    } label: {
                                        Text("Use mine")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                }
                            }

                            TextField("", text: $officePhone)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.phonePad)
                                .focused($focusedField, equals: .phone)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        if focusedField == .phone {
                                            Spacer()
                                            Button {
                                                focusedField = nil
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Text("Enter")
                                                    Image(systemName: "return")
                                                }
                                            }
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                        }
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Continue button with phased animation
            PhasedPrimaryButton(
                "CONTINUE",
                isEnabled: isFormValid,
                coordinator: animationCoordinator
            ) {
                saveAndContinue()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .onAppear {
            prefillData()
            animationCoordinator.start()
        }
    }

    // MARK: - Computed Properties

    private var companyInitials: String {
        let words = companyName.split(separator: " ")
        if words.count >= 2 {
            let first = words[0].first.map { String($0) } ?? ""
            let second = words[1].first.map { String($0) } ?? ""
            return (first + second).uppercased()
        } else if let first = companyName.first {
            return String(first).uppercased()
        }
        return ""
    }

    // MARK: - Actions

    private func prefillData() {
        let companyData = manager.state.companyData
        if !companyData.name.isEmpty { companyName = companyData.name }
        if !companyData.email.isEmpty { officeEmail = companyData.email }
        if !companyData.phone.isEmpty { officePhone = companyData.phone }
        if let data = companyData.logoData { logoData = data }
    }

    private func saveAndContinue() {
        // Save to state
        manager.state.companyData.name = companyName
        manager.state.companyData.email = officeEmail
        manager.state.companyData.phone = officePhone
        manager.state.companyData.logoData = logoData
        manager.state.save()

        // Navigate to details page
        manager.goToScreen(.companyDetails)
    }
}

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)
    manager.selectFlow(.companyCreator)

    return CompanySetupScreen(manager: manager)
        .environmentObject(dataController)
}
