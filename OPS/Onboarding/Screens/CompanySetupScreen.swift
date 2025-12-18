//
//  CompanySetupScreen.swift
//  OPS
//
//  Company setup screen - page 1: name, logo, email, phone.
//  Part of the company creator flow.
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

            // Title section with typing animation
            AnimatedOnboardingHeader(
                title: "YOUR COMPANY",
                subtitle: "This is how you'll appear to your crew."
            ) {
                // Header animation complete
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 16)

            Spacer()
                .frame(height: 32)

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
                    Text("COMPANY LOGO")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
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
                    Text("COMPANY NAME")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

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
                        Text("OFFICE EMAIL")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

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
                        Text("OFFICE PHONE")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

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
                                    Button("Done") {
                                        focusedField = nil
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
