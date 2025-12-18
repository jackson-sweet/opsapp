//
//  ProfileScreen.swift
//  OPS
//
//  Personal profile screen - name, phone, avatar.
//  Clean, focused screen with centered avatar.
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

    private var isFormValid: Bool {
        !firstName.isEmpty && !lastName.isEmpty
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
            .padding(.top, 16)

            // Title section with typing animation
            AnimatedOnboardingHeader(
                title: "YOUR INFO",
                subtitle: "Your crew will see this."
            ) {
                // Header animation complete
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 16)

            Spacer()
                .frame(height: 48)

            // Centered avatar
            VStack(spacing: 12) {
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
                    Text("ADD PHOTO")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("Optional")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Spacer()
                .frame(height: 40)

            // Form fields
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FIRST NAME")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        TextField("", text: $firstName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocapitalization(.words)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("LAST NAME")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        TextField("", text: $lastName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocapitalization(.words)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("PHONE (optional)")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    TextField("", text: $phone)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .keyboardType(.phonePad)
                        .focused($isPhoneFocused)
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
                                if isPhoneFocused {
                                    Spacer()
                                    Button("Done") {
                                        isPhoneFocused = false
                                    }
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Continue button
            Button {
                saveAndContinue()
            } label: {
                HStack {
                    Text("CONTINUE")
                        .font(OPSStyle.Typography.bodyBold)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isFormValid ? Color.white : Color.white.opacity(0.5))
            .foregroundColor(.black)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .disabled(!isFormValid)
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .onAppear {
            prefillData()
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
            manager.goToScreen(.codeEntry)
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
