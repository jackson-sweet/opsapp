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
    @State private var keyboardVisible = false

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
        return hasAnyData ? "COMPLETE YOUR PROFILE" : "YOUR COMPANY PROFILE"
    }

    private var headerSubtitle: String {
        "This shows up on estimates, invoices, and shared projects."
    }

    /// How many of the 5 profile fields are already filled
    private var completionCount: Int {
        var count = 0
        if !(company.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editedPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !(company.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editedEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !(company.website ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editedWebsite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !(company.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if company.logoData != nil || !(company.logoURL ?? "").isEmpty || companyImage != nil { count += 1 }
        return count
    }

    private let totalFields = 5

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(headerTitle)
                        .font(OPSStyle.Typography.headingBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Button { skipForNow() } label: {
                        Image(systemName: OPSStyle.Icons.xmark)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    }
                    .disabled(isSaving)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3)

                // Subtitle + counter
                HStack {
                    Text(headerSubtitle)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text("\(completionCount)/\(totalFields)")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(completionCount == totalFields ? OPSStyle.Colors.successStatus : OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing1)
                .padding(.bottom, OPSStyle.Layout.spacing4)

                // Field cards
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing2) {

                        // LOGO
                        if !(company.logoData != nil || !(company.logoURL ?? "").isEmpty) {
                            fieldCard(isComplete: companyImage != nil) {
                                HStack(spacing: OPSStyle.Layout.spacing3) {
                                    // Preview circle
                                    Button(action: { showImagePicker = true }) {
                                        if let image = companyImage {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 48, height: 48)
                                                .clipShape(Circle())
                                        } else {
                                            Circle()
                                                .fill(OPSStyle.Colors.background)
                                                .frame(width: 48, height: 48)
                                                .overlay(
                                                    Image(systemName: "camera.fill")
                                                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                )
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                        Text("COMPANY LOGO")
                                            .font(OPSStyle.Typography.captionBold)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                        Text("Clients see this on every estimate")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }

                                    Spacer()

                                    Button(action: { showImagePicker = true }) {
                                        Text(companyImage == nil ? "ADD" : "CHANGE")
                                            .font(OPSStyle.Typography.captionBold)
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                }
                            }
                        }

                        // WEBSITE
                        if (company.website ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            inputFieldCard(
                                label: "WEBSITE",
                                text: $editedWebsite,
                                placeholder: "www.yourcompany.com",
                                keyboardType: .URL,
                                field: .website
                            )
                        }

                        // PHONE
                        if (company.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            inputFieldCard(
                                label: "PHONE",
                                text: $editedPhone,
                                placeholder: "(555) 123-4567",
                                keyboardType: .phonePad,
                                field: .phone,
                                useMineValue: dataController.currentUser?.phone
                            )
                        }

                        // EMAIL
                        if (company.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            inputFieldCard(
                                label: "EMAIL",
                                text: $editedEmail,
                                placeholder: "contact@yourcompany.com",
                                keyboardType: .emailAddress,
                                field: .email,
                                useMineValue: dataController.currentUser?.email
                            )
                        }

                        // ADDRESS
                        if (company.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            fieldCard(isComplete: !editedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
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
                                        Button(action: { isAddressFieldActive = true }) {
                                            HStack {
                                                Text(editedAddress.isEmpty ? "Enter company address" : editedAddress)
                                                    .font(OPSStyle.Typography.body)
                                                    .foregroundColor(editedAddress.isEmpty ? OPSStyle.Colors.placeholderText : OPSStyle.Colors.primaryText)
                                                    .lineLimit(1)
                                                Spacer()
                                                Image(systemName: OPSStyle.Icons.chevronRight)
                                                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            }
                                            .padding(OPSStyle.Layout.spacing2_5)
                                            .background(OPSStyle.Colors.background)
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        }
                                    }
                                }
                            }
                        }

                        // ALREADY ON FILE — completed fields shown as locked cards
                        if hasPrefilledFields {
                            Text("ON FILE")
                                .font(OPSStyle.Typography.microLabel)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .tracking(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, OPSStyle.Layout.spacing2)
                                .padding(.horizontal, OPSStyle.Layout.spacing1)

                            ForEach(prefilledItems, id: \.0) { label, value in
                                completedFieldCard(label: label, value: value)
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing4)
                }

                Spacer(minLength: 0)

                // Bottom action area — hidden when keyboard is up
                if !keyboardVisible {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    // Error message
                    if let error = errorMessage {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                            Text(error)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    }

                    // Save
                    Button {
                        Task { await saveChanges() }
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                                    .scaleEffect(0.8)
                            }
                            Text(isSaving ? "SAVING..." : "DONE")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(hasChanges ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.3))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .disabled(!hasChanges || isSaving)

                    // Skip
                    Button { skipForNow() } label: {
                        Text("Later")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                    }
                    .disabled(isSaving)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing4)
                } // end keyboard guard
            }
        }
        .ignoresSafeArea(.keyboard)
        .interactiveDismissDisabled(isSaving)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
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

    // MARK: - Card Components

    /// Container card for each field — left accent bar shows completion state
    private func fieldCard<Content: View>(isComplete: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            // Left accent bar — 3pt wide, green when complete, subtle border color when not
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isComplete ? OPSStyle.Colors.successStatus : OPSStyle.Colors.cardBorder)
                .frame(width: 3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .animation(OPSStyle.Animation.fast, value: isComplete)

            content()
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorderSubtle, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    /// Input field card — label, inset text field, optional USE MINE button
    private func inputFieldCard(
        label: String,
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType,
        field: SetupField,
        useMineValue: String? = nil
    ) -> some View {
        let isFilled = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return fieldCard(isComplete: isFilled) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                HStack {
                    Text(label)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()

                    if let value = useMineValue,
                       !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            text.wrappedValue = value
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text("USE MINE")
                                .font(OPSStyle.Typography.microLabel)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .padding(.horizontal, OPSStyle.Layout.spacing2)
                                .padding(.vertical, OPSStyle.Layout.spacing1)
                                .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                        }
                    }
                }

                // Inset input — darker background signals "type here"
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
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.background)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(
                                focusedField == field ? OPSStyle.Colors.primaryAccent : Color.clear,
                                lineWidth: OPSStyle.Layout.Border.standard
                            )
                    )
            }
        }
    }

    /// Read-only card for already-filled fields
    private func completedFieldCard(label: String, value: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(OPSStyle.Colors.successStatus.opacity(0.5))
                .frame(width: 3)
                .padding(.vertical, OPSStyle.Layout.spacing2)

            HStack {
                Text(label)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Spacer()

                Text(value)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
        }
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    }

    // MARK: - Pre-filled Data

    private var hasPrefilledFields: Bool {
        !prefilledItems.isEmpty
    }

    private var prefilledItems: [(String, String)] {
        var items: [(String, String)] = []
        if let phone = company.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(("PHONE", phone))
        }
        if let email = company.email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(("EMAIL", email))
        }
        if let website = company.website, !website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(("WEBSITE", website))
        }
        if let address = company.address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(("ADDRESS", address))
        }
        if company.logoData != nil || !(company.logoURL ?? "").isEmpty {
            items.append(("LOGO", "On file"))
        }
        return items
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

            errorMessage = "Couldn't save. Check your connection and try again."
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
