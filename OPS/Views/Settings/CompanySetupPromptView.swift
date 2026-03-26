//
//  CompanySetupPromptView.swift
//  OPS
//
//  Prompt shown on 2nd+ app launch to encourage completing company profile.
//  Collects missing fields: logo, website, phone, email, address.
//  Pre-fills any data already available from onboarding.
//

import SwiftUI
import SwiftData

struct CompanySetupPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let company: Company

    // MARK: - Form State

    @State private var editedPhone: String = ""
    @State private var editedEmail: String = ""
    @State private var editedWebsite: String = ""
    @State private var editedAddress: String = ""
    @State private var companyImage: UIImage?

    // Logo display state (existing logo from company)
    @State private var existingLogoData: Data?
    @State private var existingLogoURL: String?

    // Address autocomplete activation
    @State private var isAddressFieldActive: Bool = false

    // Saving
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    // Image picker
    @State private var showImagePicker: Bool = false

    // Focus
    @FocusState private var focusedField: SetupField?

    enum SetupField: Hashable {
        case phone
        case email
        case website
        case address
    }

    // MARK: - Computed Properties

    /// True if at least one field that was empty has been filled in
    private var hasNewData: Bool {
        let phoneProvided = !editedPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (company.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let emailProvided = !editedEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (company.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let websiteProvided = !editedWebsite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (company.website ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let addressProvided = !editedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (company.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let logoProvided = companyImage != nil && company.logoData == nil && (company.logoURL ?? "").isEmpty

        return phoneProvided || emailProvided || websiteProvided || addressProvided || logoProvided
    }

    /// True if any field value differs from the original company data
    private var hasChanges: Bool {
        let phoneChanged = editedPhone.trimmingCharacters(in: .whitespacesAndNewlines) !=
            (company.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let emailChanged = editedEmail.trimmingCharacters(in: .whitespacesAndNewlines) !=
            (company.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let websiteChanged = editedWebsite.trimmingCharacters(in: .whitespacesAndNewlines) !=
            (company.website ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let addressChanged = editedAddress.trimmingCharacters(in: .whitespacesAndNewlines) !=
            (company.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let logoChanged = companyImage != nil

        return phoneChanged || emailChanged || websiteChanged || addressChanged || logoChanged
    }

    /// Header text depends on whether some data already exists
    private var headerTitle: String {
        let hasAnyData = !(company.phone ?? "").isEmpty ||
            !(company.email ?? "").isEmpty ||
            !(company.website ?? "").isEmpty ||
            !(company.address ?? "").isEmpty ||
            company.logoData != nil ||
            !(company.logoURL ?? "").isEmpty
        return hasAnyData ? "FINISH SETTING UP YOUR COMPANY" : "SET UP YOUR COMPANY"
    }

    private var headerSubtitle: String {
        "Clients and crew will see this info. Takes 30 seconds."
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header bar
                headerBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Title section
                        VStack(alignment: .leading, spacing: 8) {
                            Text(headerTitle)
                                .font(OPSStyle.Typography.headingBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Text(headerSubtitle)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.top, 8)

                        // Logo section
                        logoSection

                        // Form fields
                        VStack(spacing: 16) {
                            // Website
                            if (company.website ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                formField(
                                    label: "WEBSITE",
                                    text: $editedWebsite,
                                    placeholder: "www.yourcompany.com",
                                    keyboardType: .URL,
                                    field: .website
                                )
                            }

                            // Phone
                            if (company.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                formField(
                                    label: "PHONE",
                                    text: $editedPhone,
                                    placeholder: "(555) 123-4567",
                                    keyboardType: .phonePad,
                                    field: .phone
                                )
                            }

                            // Email
                            if (company.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                formField(
                                    label: "EMAIL",
                                    text: $editedEmail,
                                    placeholder: "contact@yourcompany.com",
                                    keyboardType: .emailAddress,
                                    field: .email
                                )
                            }

                            // Address
                            if (company.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                addressField
                            }
                        }

                        // Pre-filled fields (read-only display)
                        prefilledSection

                        // Error message
                        if let error = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.errorStatus)

                                Text(error)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            }
                        }

                        // Save button
                        Button {
                            Task { await saveChanges() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                                        .scaleEffect(0.8)
                                }
                                Text(isSaving ? "SAVING..." : "SAVE")
                                    .font(OPSStyle.Typography.bodyBold)
                            }
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(hasChanges ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.4))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .disabled(!hasChanges || isSaving)

                        // Skip button
                        Button {
                            skipForNow()
                        } label: {
                            Text("Skip for now")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .disabled(isSaving)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            loadExistingData()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(
                images: Binding(
                    get: { companyImage.map { [$0] } ?? [] },
                    set: { images in
                        companyImage = images.first
                    }
                ),
                allowsEditing: true,
                sourceType: .photoLibrary,
                selectionLimit: 1
            )
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Spacer()
            Button {
                skipForNow()
            } label: {
                Image(systemName: OPSStyle.Icons.xmark)
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        let hasExistingLogo = company.logoData != nil ||
            !(company.logoURL ?? "").isEmpty

        return Group {
            if !hasExistingLogo {
                HStack(spacing: 16) {
                    // Logo circle
                    Button(action: { showImagePicker = true }) {
                        ZStack {
                            if let image = companyImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.thick)
                                    )
                            } else {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackgroundDark)
                                    .frame(width: 72, height: 72)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: OPSStyle.Layout.IconSize.lg))
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.thick)
                                    )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(companyImage == nil ? "ADD COMPANY LOGO" : "CHANGE LOGO")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Text("Appears on projects and estimates")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Address Field

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADDRESS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if isAddressFieldActive {
                AddressAutocompleteField(
                    address: $editedAddress,
                    placeholder: "Enter company address",
                    onAddressSelected: { fullAddress, _ in
                        editedAddress = fullAddress
                        isAddressFieldActive = false
                    }
                )
            } else {
                Button(action: {
                    isAddressFieldActive = true
                }) {
                    HStack {
                        Text(editedAddress.isEmpty ? "Enter company address" : editedAddress)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(editedAddress.isEmpty ? OPSStyle.Colors.placeholderText : OPSStyle.Colors.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
            }
        }
    }

    // MARK: - Pre-filled Section

    /// Shows already-filled fields as read-only so the user knows what's done
    @ViewBuilder
    private var prefilledSection: some View {
        let prefilledItems: [(String, String)] = {
            var items: [(String, String)] = []
            if let phone = company.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(("Phone", phone))
            }
            if let email = company.email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(("Email", email))
            }
            if let website = company.website, !website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(("Website", website))
            }
            if let address = company.address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(("Address", address))
            }
            return items
        }()

        if !prefilledItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.successStatus)

                    Text("ALREADY ON FILE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                ForEach(prefilledItems, id: \.0) { label, value in
                    HStack {
                        Text(label)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: 70, alignment: .leading)

                        Text(value)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
            )
        }
    }

    // MARK: - Form Field

    private func formField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType,
        field: SetupField
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField("", text: text)
                .placeholder(when: text.wrappedValue.isEmpty) {
                    Text(placeholder)
                        .foregroundColor(OPSStyle.Colors.placeholderText)
                }
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(keyboardType == .emailAddress || keyboardType == .URL ? .never : .words)
                .focused($focusedField, equals: field)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            focusedField == field ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
    }

    // MARK: - Data Loading

    private func loadExistingData() {
        // Pre-fill with existing data
        editedPhone = company.phone ?? ""
        editedEmail = company.email ?? ""
        editedWebsite = company.website ?? ""
        editedAddress = company.address ?? ""
        existingLogoData = company.logoData
        existingLogoURL = company.logoURL
    }

    // MARK: - Actions

    private func skipForNow() {
        // Dismiss without saving — user can come back from settings
        dismiss()
    }

    @MainActor
    private func saveChanges() async {
        isSaving = true
        errorMessage = nil

        // Haptic: light impact on save start
        let lightImpact = UIImpactFeedbackGenerator(style: .light)
        lightImpact.impactOccurred()

        do {
            // Upload logo if provided
            if let image = companyImage {
                _ = try await dataController.uploadCompanyLogo(image, for: company)
            }

            // Build fields to update
            var fieldsToUpdate: [String: String] = [:]

            let newPhone = editedPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            if newPhone != (company.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines) && !newPhone.isEmpty {
                fieldsToUpdate["phone"] = newPhone
                company.phone = newPhone
            }

            let newEmail = editedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            if newEmail != (company.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines) && !newEmail.isEmpty {
                fieldsToUpdate["email"] = newEmail
                company.email = newEmail
            }

            let newWebsite = editedWebsite.trimmingCharacters(in: .whitespacesAndNewlines)
            if newWebsite != (company.website ?? "").trimmingCharacters(in: .whitespacesAndNewlines) && !newWebsite.isEmpty {
                fieldsToUpdate["website"] = newWebsite
                company.website = newWebsite
            }

            let newAddress = editedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            if newAddress != (company.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines) && !newAddress.isEmpty {
                fieldsToUpdate["address"] = newAddress
                company.address = newAddress
            }

            try dataController.modelContext?.save()

            // Sync to Supabase if connected and there are field changes
            if dataController.isConnected && !fieldsToUpdate.isEmpty {
                try await dataController.updateCompanyFields(
                    companyId: company.id,
                    fields: fieldsToUpdate
                )
            }

            // Mark as completed so prompt doesn't show again
            UserDefaults.standard.set(true, forKey: "hasCompletedCompanySetup")

            // Success haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            print("[COMPANY_SETUP] Successfully saved company profile data")

            dismiss()

        } catch {
            // Error haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            errorMessage = "Failed to save. Try again or skip for now."
            print("[COMPANY_SETUP] Error saving changes: \(error)")
        }

        isSaving = false
    }

    // MARK: - Static Helpers

    /// Determines whether the company setup prompt should be shown.
    /// Criteria:
    /// 1. User is authenticated and has a company
    /// 2. User has the `settings.company` permission
    /// 3. This is the 2nd+ app launch
    /// 4. User hasn't dismissed/completed setup before
    /// 5. Company profile is actually incomplete (missing website, phone, email, address, or logo)
    static func shouldShowPrompt(company: Company?) -> Bool {
        guard let company = company else { return false }

        // Only users with company settings permission should see this prompt
        guard PermissionStore.shared.can("settings.company") else {
            return false
        }

        // Check if already completed/dismissed
        if UserDefaults.standard.bool(forKey: "hasCompletedCompanySetup") {
            return false
        }

        // Check launch count — only on 2nd+ launch
        let launchCount = UserDefaults.standard.integer(forKey: "appLaunchCount")
        if launchCount < 2 {
            return false
        }

        // Check if any key fields are missing
        let missingWebsite = (company.website ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingPhone = (company.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingEmail = (company.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingAddress = (company.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingLogo = company.logoData == nil && (company.logoURL ?? "").isEmpty

        let hasIncompleteProfile = missingWebsite || missingPhone || missingEmail || missingAddress || missingLogo

        return hasIncompleteProfile
    }
}
