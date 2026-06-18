//
//  ProfileScreen.swift
//  OPS
//
//  Personal profile screen - name, phone, avatar.
//  Clean, focused screen with centered avatar.
//  Uses phased animation system for entrance effects.
//

import SwiftUI

struct ProfileScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var phone: String = ""
    @State private var avatarData: Data?
    @FocusState private var isPhoneFocused: Bool

    // Animation coordinator
    @StateObject private var animationCoordinator = OnboardingAnimationCoordinator()

    private var isEmployeeFlow: Bool {
        manager.state.flow == .employee
    }

    private var isFormValid: Bool {
        if isEmployeeFlow {
            // Employees MUST provide name and phone
            return !firstName.isEmpty && !lastName.isEmpty && !phone.isEmpty
        } else {
            return !firstName.isEmpty && !lastName.isEmpty
        }
    }

    private var initials: String {
        let first = firstName.first.map { String($0) } ?? ""
        let last = lastName.first.map { String($0) } ?? ""
        return (first + last).uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with sign out (no back button on first screen)
            OnboardingHeader(
                showBack: false,
                onBack: nil,
                onSignOut: { manager.signOut() }
            )
            .padding(.horizontal, 40)
            .padding(.top, OPSStyle.Layout.spacing3)

            // Title section with phased typing animation
            PhasedOnboardingHeader(
                title: "YOUR INFO",
                subtitle: "Your crew will see this.",
                coordinator: animationCoordinator
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, OPSStyle.Layout.spacing3)

            Spacer()
                .frame(height: 48)

            // Content section - fades in upward
            PhasedContent(coordinator: animationCoordinator) {
                VStack(spacing: 0) {
                    // Centered avatar
                    VStack(spacing: OPSStyle.Layout.spacing2_5) {
                        ProfileImageUploader(
                            config: ImageUploaderConfig(
                                currentImageData: avatarData,
                                placeholderText: initials,
                                size: 120,
                                shape: .circle,
                                allowDelete: true,
                                backgroundColor: OPSStyle.Colors.cardBackgroundDark
                            ),
                            onUpload: { image in
                                avatarData = image.jpegData(compressionQuality: 0.8)
                                return ""
                            },
                            onDelete: {
                                avatarData = nil
                            }
                        )

                        VStack(spacing: 2) {
                            PhasedLabel("ADD PHOTO", index: 0, coordinator: animationCoordinator)
                            Text("Optional")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }

                    Spacer()
                        .frame(height: 40)

                    // Form fields
                    VStack(spacing: OPSStyle.Layout.spacing3_5) {
                        HStack(spacing: OPSStyle.Layout.spacing2_5) {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                PhasedLabel("FIRST NAME", index: 1, coordinator: animationCoordinator)

                                TextField("", text: $firstName)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .autocapitalization(.words)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                    )
                            }

                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                PhasedLabel("LAST NAME", index: 2, coordinator: animationCoordinator)

                                TextField("", text: $lastName)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .autocapitalization(.words)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                    )
                            }
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            PhasedLabel(isEmployeeFlow ? "PHONE" : "PHONE (optional)", index: 3, isLast: true, coordinator: animationCoordinator)

                            TextField("", text: $phone)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.phonePad)
                                .focused($isPhoneFocused)
                                .padding(.vertical, 14)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        if isPhoneFocused {
                                            Spacer()
                                            Button {
                                                isPhoneFocused = false
                                            } label: {
                                                HStack(spacing: OPSStyle.Layout.spacing1) {
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

    private func prefillData() {
        let userData = manager.state.userData
        if !userData.firstName.isEmpty { firstName = userData.firstName }
        if !userData.lastName.isEmpty { lastName = userData.lastName }
        if !userData.phone.isEmpty { phone = userData.phone }
        if let data = userData.avatarData { avatarData = data }
    }

    private func saveAndContinue() {
        manager.state.userData.firstName = firstName
        manager.state.userData.lastName = lastName
        manager.state.userData.phone = phone

        // If no photo uploaded, generate initials image
        if avatarData == nil && !initials.isEmpty {
            let generatedImage = InitialsImageGenerator.generateImage(
                initials: initials,
                size: 200,
                backgroundColor: UIColor(OPSStyle.Colors.primaryAccent)
            )
            avatarData = generatedImage?.jpegData(compressionQuality: 0.8)
        }

        manager.state.userData.avatarData = avatarData
        manager.state.save()

        // Navigate based on flow
        if manager.state.flow == .companyCreator {
            manager.goToScreen(.companySetup)
        } else {
            // Employee flow: emergency contact screen (skippable) before code entry
            manager.goToScreen(.emergencyContact)
        }
    }
}

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)
    manager.selectFlow(.companyCreator)

    return ProfileScreen(manager: manager)
        .environmentObject(dataController)
}
