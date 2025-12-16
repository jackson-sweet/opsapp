//
//  UserInfoView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-06.
//

import SwiftUI

// Function to format phone number
func formatPhoneNumber(_ phoneNumber: String) -> String {
    // Filter out non-numeric characters
    let digits = phoneNumber.filter { $0.isNumber }
    
    // Format according to pattern (XXX) XXX-XXXX
    var formattedPhone = ""
    
    for (index, digit) in digits.prefix(10).enumerated() {
        if index == 0 {
            formattedPhone.append("(\(digit)")
        } else if index == 2 {
            formattedPhone.append("\(digit)) ")
        } else if index == 5 {
            formattedPhone.append("\(digit)-")
        } else {
            formattedPhone.append(String(digit))
        }
    }
    
    return formattedPhone
}

struct UserInfoView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var currentPhase: UserInfoPhase = .firstName
    @State private var hasCheckedExistingData = false
    
    enum UserInfoPhase: Int, CaseIterable {
        case firstName = 0
        case lastName = 1
        case phoneNumber = 2
        case profilePicture = 3
    }
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 3
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 7 }
        return OnboardingStep.totalSteps(for: userType)
    }
    
    var body: some View {
        ZStack {
            // Background color - conditional theming
            (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top navigation
                HStack {
                    Button(action: {
                        if currentPhase == .firstName {
                            if !viewModel.isSignedUp {
                                viewModel.moveToPreviousStep()
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPhase = UserInfoPhase(rawValue: currentPhase.rawValue - 1) ?? .firstName
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(OPSStyle.Typography.caption.weight(.semibold))
                            Text("Back")
                                .font(OPSStyle.Typography.button)
                        }
                        .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                    }
                    .opacity(currentPhase == .firstName && viewModel.isSignedUp ? 0 : 1)
                    .disabled(currentPhase == .firstName && viewModel.isSignedUp)

                    Spacer()

                    Button(action: {
                        viewModel.logoutAndReturnToLogin()
                    }) {
                        Text("Cancel")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                    }
                }

                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ?
                                (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText) :
                                (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.3) : OPSStyle.Colors.secondaryText.opacity(0.3)))
                            .frame(height: 2)
                    }
                }
                .padding(.top, 16)

                Spacer()

                // Phase content
                Group {
                    switch currentPhase {
                    case .firstName:
                        FirstNamePhaseView(
                            firstName: $viewModel.firstName,
                            viewModel: viewModel,
                            onContinue: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentPhase = .lastName
                                }
                            }
                        )
                    case .lastName:
                        LastNamePhaseView(
                            lastName: $viewModel.lastName,
                            viewModel: viewModel,
                            onContinue: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentPhase = .phoneNumber
                                }
                            }
                        )
                    case .phoneNumber:
                        PhoneNumberPhaseView(
                            phoneNumber: $viewModel.phoneNumber,
                            viewModel: viewModel,
                            onContinue: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentPhase = .profilePicture
                                }
                            }
                        )
                    case .profilePicture:
                        ProfilePicturePhaseView(
                            profileImage: $viewModel.profileImage,
                            viewModel: viewModel,
                            onContinue: {
                                viewModel.moveToNextStep()
                            },
                            onSkip: {
                                viewModel.profileImage = nil
                                viewModel.moveToNextStep()
                            }
                        )
                    }
                }
                .transition(.opacity)

                Spacer()
            }
            .padding(40)
        }
        .dismissKeyboardOnTap()
        .onAppear {
            checkAndSkipIfDataExists()
        }
    }
    
    private func checkAndSkipIfDataExists() {
        guard !hasCheckedExistingData else { return }
        hasCheckedExistingData = true

        // Set the phase to the first missing field
        if viewModel.firstName.isEmpty {
            currentPhase = .firstName
        } else if viewModel.lastName.isEmpty {
            currentPhase = .lastName
        } else if viewModel.phoneNumber.isEmpty {
            currentPhase = .phoneNumber
        } else {
            // Start at profile picture phase if all other info exists
            currentPhase = .profilePicture
        }
    }
}

// MARK: - Phase Views

struct FirstNamePhaseView: View {
    @Binding var firstName: String
    @ObservedObject var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    private var primaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }

    private var secondaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("WHAT'S YOUR")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(primaryTextColor)
                Text("FIRST NAME?")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(primaryTextColor)
            }

            // First name input
            UnderlineTextField(
                placeholder: "First name",
                text: $firstName,
                keyboardType: .default,
                autocapitalization: .words,
                viewModel: viewModel
            )

            Spacer()

            // Continue button
            StandardContinueButton(
                isDisabled: firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onTap: onContinue
            )
            .padding(.bottom, 20)
        }
    }
}

struct LastNamePhaseView: View {
    @Binding var lastName: String
    @ObservedObject var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    private var primaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("AND YOUR")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(primaryTextColor)
                Text("LAST NAME?")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(primaryTextColor)
            }

            // Last name input
            UnderlineTextField(
                placeholder: "Last name",
                text: $lastName,
                keyboardType: .default,
                autocapitalization: .words,
                viewModel: viewModel
            )

            Spacer()

            // Continue button
            StandardContinueButton(
                isDisabled: lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onTap: onContinue
            )
            .padding(.bottom, 20)
        }
    }
}

struct PhoneNumberPhaseView: View {
    @Binding var phoneNumber: String
    @ObservedObject var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    private var primaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }

    private var secondaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }

    private var isPhoneValid: Bool {
        let digits = phoneNumber.filter { $0.isNumber }
        return digits.count >= 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("PHONE")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(primaryTextColor)
                Text("NUMBER")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(primaryTextColor)
            }
            .padding(.bottom, 8)

            Text("This will be used to update your team contact information.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(secondaryTextColor)

            // Phone number input
            UnderlineTextField(
                placeholder: "(___) ___-____",
                text: $phoneNumber,
                keyboardType: .phonePad,
                viewModel: viewModel,
                onChange: { newValue in
                    let digits = newValue.filter { $0.isNumber }
                    if digits.count <= 10 {
                        phoneNumber = formatPhoneNumber(newValue)
                    }
                }
            )

            Spacer()

            // Continue button
            StandardContinueButton(
                isDisabled: !isPhoneValid,
                onTap: onContinue
            )
            .padding(.bottom, 20)
        }
    }
}

struct ProfilePicturePhaseView: View {
    @Binding var profileImage: UIImage?
    @ObservedObject var viewModel: OnboardingViewModel
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var imageData: Data?

    private var primaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText
    }

    private var secondaryTextColor: Color {
        viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("ADD A")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(primaryTextColor)
                Text("PROFILE PHOTO")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(primaryTextColor)
            }
            .padding(.bottom, 8)

            Text("Your photo helps your team recognize you.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(secondaryTextColor)

            // Use ProfileImageUploader
            ProfileImageUploader(
                config: ImageUploaderConfig(
                    currentImageURL: nil,
                    currentImageData: imageData,
                    placeholderText: "",
                    size: 120,
                    shape: .circle,
                    allowDelete: false,
                    backgroundColor: OPSStyle.Colors.cardBackgroundDark
                ),
                onUpload: { image in
                    profileImage = image
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        imageData = data
                    }
                    return ""
                },
                onDelete: nil
            )

            Spacer()

            // Continue/Skip buttons
            VStack(spacing: 12) {
                StandardContinueButton(
                    isDisabled: profileImage == nil,
                    onTap: onContinue
                )

                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(secondaryTextColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                }
            }
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Preview
#Preview("User Info Screen") {
    let viewModel = OnboardingViewModel()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    
    return UserInfoView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}
