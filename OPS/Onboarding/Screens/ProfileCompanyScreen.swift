//
//  ProfileCompanyScreen.swift
//  OPS
//
//  Company creator profile screen for onboarding v3.
//  3 phases: form, processing, success (with company code display).
//

import SwiftUI

struct ProfileCompanyScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    // Profile fields
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var phone: String = ""
    @State private var avatarData: Data?

    // Company fields
    @State private var companyName: String = ""
    @State private var selectedIndustry: Industry?
    @State private var selectedSize: CompanySize?
    @State private var selectedAge: CompanyAge?
    @State private var companyAddress: String = ""
    @State private var logoData: Data?

    // UI state
    @State private var showIndustryPicker = false
    @State private var industrySearchText = ""
    @State private var errorMessage: String?

    // Computed
    private var isFormValid: Bool {
        !firstName.isEmpty &&
        !lastName.isEmpty &&
        !phone.isEmpty &&
        !companyName.isEmpty &&
        selectedIndustry != nil &&
        selectedSize != nil &&
        selectedAge != nil
    }

    private var buttonText: String {
        manager.state.hasExistingCompany ? "CONTINUE" : "CREATE COMPANY"
    }

    var body: some View {
        ZStack {
            switch manager.state.profileCompanyPhase {
            case .form:
                formView
            case .processing:
                processingView
            case .success:
                successView
            }
        }
        .onAppear {
            prefillData()
        }
    }

    // MARK: - Form View

    private var formView: some View {
        OnboardingScaffold(
            title: "SET UP YOUR COMPANY",
            subtitle: "Tell us about yourself and your business",
            showBackButton: true,
            onBack: { manager.goBack() }
        ) {
            VStack(spacing: 32) {
                // Profile section
                profileSection

                // Company section
                companySection

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } footer: {
            Button {
                submitForm()
            } label: {
                Text(buttonText)
                    .font(OPSStyle.Typography.button)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isFormValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.5))
            .foregroundColor(.black)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .disabled(!isFormValid)
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Text("YOUR PROFILE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Avatar (optional)
            HStack {
                ProfileImageUploader(
                    config: ImageUploaderConfig(
                        currentImageData: avatarData,
                        placeholderText: initials,
                        size: 72,
                        shape: .circle,
                        allowDelete: true,
                        backgroundColor: OPSStyle.Colors.primaryAccent
                    ),
                    onUpload: { image in
                        avatarData = image.jpegData(compressionQuality: 0.8)
                        return "" // No URL needed during onboarding
                    },
                    onDelete: {
                        avatarData = nil
                    }
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile Photo")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(.white)
                    Text("Optional")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()
            }

            // Name fields
            HStack(spacing: 12) {
                FormField(
                    title: "First Name",
                    placeholder: "First",
                    text: $firstName
                )

                FormField(
                    title: "Last Name",
                    placeholder: "Last",
                    text: $lastName
                )
            }

            // Phone field
            FormField(
                title: "Phone",
                placeholder: "(555) 123-4567",
                text: $phone,
                keyboardType: .phonePad
            )
        }
    }

    // MARK: - Company Section

    private var companySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Text("YOUR COMPANY")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Company name
            FormField(
                title: "Company Name",
                placeholder: "Enter company name",
                text: $companyName
            )

            // Industry picker
            industryPickerField

            // Company Size - pill buttons
            LabeledPillButtonGroup(
                label: "COMPANY SIZE",
                options: CompanySize.allCases.map {
                    PillOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                },
                selection: $selectedSize
            )

            // Company Age - pill buttons
            LabeledPillButtonGroup(
                label: "COMPANY AGE",
                options: CompanyAge.allCases.map {
                    PillOption(id: $0.rawValue, title: $0.rawValue, value: $0)
                },
                selection: $selectedAge
            )

            // Address (optional)
            FormField(
                title: "Address (Optional)",
                placeholder: "Business address",
                text: $companyAddress
            )

            // Company logo (optional)
            HStack {
                ProfileImageUploader(
                    config: ImageUploaderConfig(
                        currentImageData: logoData,
                        placeholderText: companyInitials,
                        size: 56,
                        shape: .roundedSquare(cornerRadius: 12),
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Company Logo")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(.white)
                    Text("Optional")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()
            }
        }
    }

    // MARK: - Industry Picker

    private var industryPickerField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INDUSTRY")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button {
                showIndustryPicker = true
            } label: {
                HStack {
                    Text(selectedIndustry?.displayName ?? "Select industry")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(selectedIndustry != nil ? .white : OPSStyle.Colors.tertiaryText)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                )
            }
        }
        .sheet(isPresented: $showIndustryPicker) {
            IndustryPickerSheet(
                selection: $selectedIndustry,
                isPresented: $showIndustryPicker
            )
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack {
            Spacer()

            VStack(spacing: 24) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text(manager.state.hasExistingCompany ? "Updating your company..." : "Creating your company...")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Success View

    private var successView: some View {
        OnboardingScaffold(
            title: "COMPANY CREATED!",
            subtitle: "Share this code with your team",
            showBackButton: false
        ) {
            VStack(spacing: 32) {
                // Success icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(OPSStyle.Colors.successStatus)

                // Company code display
                if let code = manager.state.companyData.companyCode {
                    VStack(spacing: 16) {
                        Text("YOUR COMPANY CODE")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        CompanyCodeDisplay(code: code) {
                            // Haptic feedback on copy
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }
                    }
                }

                // Info text
                Text("Team members will use this code to join your company. You can also find it in Settings later.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        } footer: {
            Button {
                manager.goForward()
            } label: {
                Text("CONTINUE")
                    .font(OPSStyle.Typography.button)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(OPSStyle.Colors.primaryAccent)
            .foregroundColor(.black)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Helpers

    private var initials: String {
        let first = firstName.first.map { String($0) } ?? ""
        let last = lastName.first.map { String($0) } ?? ""
        return (first + last).uppercased()
    }

    private var companyInitials: String {
        let words = companyName.split(separator: " ")
        if words.count >= 2 {
            let first = words[0].first.map { String($0) } ?? ""
            let second = words[1].first.map { String($0) } ?? ""
            return (first + second).uppercased()
        }
        return String(companyName.prefix(2)).uppercased()
    }

    private func prefillData() {
        // Pre-fill from manager state (resume scenario)
        let userData = manager.state.userData
        let companyData = manager.state.companyData

        if !userData.firstName.isEmpty { firstName = userData.firstName }
        if !userData.lastName.isEmpty { lastName = userData.lastName }
        if !userData.phone.isEmpty { phone = userData.phone }
        if let data = userData.avatarData { avatarData = data }

        if !companyData.name.isEmpty { companyName = companyData.name }
        if !companyData.industry.isEmpty {
            selectedIndustry = Industry.allCases.first { $0.rawValue == companyData.industry }
        }
        if !companyData.size.isEmpty {
            selectedSize = CompanySize.allCases.first { $0.rawValue == companyData.size }
        }
        if !companyData.age.isEmpty {
            selectedAge = CompanyAge.allCases.first { $0.rawValue == companyData.age }
        }
        if !companyData.address.isEmpty { companyAddress = companyData.address }
        if let data = companyData.logoData { logoData = data }
    }

    private func submitForm() {
        guard isFormValid else { return }

        // Update manager state
        manager.state.userData.firstName = firstName
        manager.state.userData.lastName = lastName
        manager.state.userData.phone = phone
        manager.state.userData.avatarData = avatarData

        manager.state.companyData.name = companyName
        manager.state.companyData.industry = selectedIndustry?.rawValue ?? ""
        manager.state.companyData.size = selectedSize?.rawValue ?? ""
        manager.state.companyData.age = selectedAge?.rawValue ?? ""
        manager.state.companyData.address = companyAddress
        manager.state.companyData.logoData = logoData

        errorMessage = nil

        Task {
            do {
                let _ = try await manager.createCompany()
                // Phase will be updated to .success by manager
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    manager.state.profileCompanyPhase = .form
                }
            }
        }
    }
}

// MARK: - Preview

struct ProfileCompanyScreen_Previews: PreviewProvider {
    static var previews: some View {
        let dataController = DataController()
        let manager = OnboardingManager(dataController: dataController)
        manager.selectFlow(.companyCreator)

        return ProfileCompanyScreen(manager: manager)
            .environmentObject(dataController)
    }
}
