//
//  ProfileJoinScreen.swift
//  OPS
//
//  Employee profile screen for onboarding v3.
//  2 phases: form (profile + company code), joining (loading).
//

import SwiftUI
import SwiftData

struct ProfileJoinScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    // Profile fields
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var phone: String = ""
    @State private var avatarData: Data?

    // Company code
    @State private var companyCode: String = ""

    // UI state
    @State private var showHelpSheet = false
    @State private var errorMessage: String?

    // Computed
    private var isFormValid: Bool {
        let hasProfile = !firstName.isEmpty && !lastName.isEmpty && !phone.isEmpty
        let hasCompanyAccess = manager.state.hasExistingCompany || !companyCode.isEmpty
        return hasProfile && hasCompanyAccess
    }

    private var buttonText: String {
        manager.state.hasExistingCompany ? "CONTINUE" : "JOIN CREW"
    }

    var body: some View {
        ZStack {
            switch manager.state.profileJoinPhase {
            case .form:
                formView
            case .joining:
                joiningView
            }
        }
        .onAppear {
            prefillData()
        }
    }

    // MARK: - Form View

    private var formView: some View {
        OnboardingScaffold(
            title: "JOIN YOUR CREW",
            subtitle: "Enter the code your boss gave you.",
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

                // Help button
                OnboardingHelpButton(
                    title: "NEED THE CODE?",
                    description: "Your company admin has it. If you're the admin, go back and choose \"Run a Crew\" instead.",
                    alternateActionTitle: "I'M THE ADMIN →",
                    onAlternateAction: {
                        switchToCompanyCreator()
                    }
                )
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
            Text("YOUR INFO")
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
                        return ""
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
            Text("CREW CODE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if manager.state.hasExistingCompany {
                // Already has company - show read-only
                existingCompanyView
            } else {
                // Need to enter company code
                CompanyCodeSection(
                    label: "CREW CODE",
                    inputCode: $companyCode,
                    isEditable: true
                )

                Text("Got this from your company admin or crew lead.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }

    // MARK: - Existing Company View

    private var existingCompanyView: some View {
        HStack {
            // Company icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: "building.2.fill")
                    .font(.system(size: 20))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Already joined")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                if let companyName = getCompanyName() {
                    Text(companyName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                } else {
                    Text("Your Company")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(OPSStyle.Colors.successStatus)
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Joining View

    private var joiningView: some View {
        VStack {
            Spacer()

            VStack(spacing: 24) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text("Joining...")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Helpers

    private var initials: String {
        let first = firstName.first.map { String($0) } ?? ""
        let last = lastName.first.map { String($0) } ?? ""
        return (first + last).uppercased()
    }

    private func getCompanyName() -> String? {
        // Try to get from state first
        if !manager.state.companyData.name.isEmpty {
            return manager.state.companyData.name
        }

        // Try to get from dataController
        if let companyId = dataController.currentUser?.companyId,
           let context = dataController.modelContext {
            let targetId = companyId
            let descriptor = FetchDescriptor<Company>(predicate: #Predicate<Company> { company in
                company.id == targetId
            })
            if let company = try? context.fetch(descriptor).first {
                return company.name
            }
        }

        return nil
    }

    private func prefillData() {
        // Pre-fill from manager state (resume scenario)
        let userData = manager.state.userData

        if !userData.firstName.isEmpty { firstName = userData.firstName }
        if !userData.lastName.isEmpty { lastName = userData.lastName }
        if !userData.phone.isEmpty { phone = userData.phone }
        if let data = userData.avatarData { avatarData = data }

        // Pre-fill company code if exists
        if let code = manager.state.companyData.companyCode {
            companyCode = code
        }
    }

    private func submitForm() {
        guard isFormValid else { return }

        // Update manager state
        manager.state.userData.firstName = firstName
        manager.state.userData.lastName = lastName
        manager.state.userData.phone = phone
        manager.state.userData.avatarData = avatarData

        errorMessage = nil

        Task {
            do {
                if manager.state.hasExistingCompany {
                    // Just save profile and continue
                    manager.goForward()
                } else {
                    // Join company
                    try await manager.joinCompany(code: companyCode)
                    await MainActor.run {
                        manager.goForward()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    manager.state.profileJoinPhase = .form
                }
            }
        }
    }

    private func switchToCompanyCreator() {
        Task {
            await manager.switchFlow(to: .companyCreator)
        }
    }
}

// MARK: - Preview

struct ProfileJoinScreen_Previews: PreviewProvider {
    static var previews: some View {
        let dataController = DataController()
        let manager = OnboardingManager(dataController: dataController)
        manager.selectFlow(.employee)

        return ProfileJoinScreen(manager: manager)
            .environmentObject(dataController)
    }
}
