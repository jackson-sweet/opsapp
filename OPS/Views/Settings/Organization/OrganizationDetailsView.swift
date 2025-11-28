//
//  OrganizationDetailsView.swift
//  OPS
//
//  Organization details view matching ClientSheet styling pattern
//

import SwiftUI

struct OrganizationDetailsView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Editable fields
    @State private var editedPhone: String = ""
    @State private var editedEmail: String = ""
    @State private var editedWebsite: String = ""
    @State private var editedAddress: String = ""

    // Logo
    @State private var companyImage: UIImage?
    @State private var showImagePicker = false

    // Track if any changes have been made
    @State private var hasChanges = false

    // Section expansion
    @State private var isDetailsExpanded = true

    // Focus states
    @FocusState private var focusedField: OrganizationFormField?

    // Company code info popover
    @State private var showingCompanyCodeInfo = false

    // Address field activation (prevent dropdown on load)
    @State private var isAddressFieldActive = false

    enum OrganizationFormField: Hashable {
        case phone
        case email
        case website
        case address
    }

    private var company: Company? {
        dataController.getCurrentUserCompany()
    }

    private var isCompanyAdmin: Bool {
        dataController.currentUser?.isCompanyAdmin == true || dataController.currentUser?.role == .admin
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            if isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // PREVIEW CARD (live updating)
                        previewCard
                            .padding(.horizontal, 20)

                        // LOGO UPLOADER (if admin)
                        if isCompanyAdmin {
                            logoUploader
                                .padding(.horizontal, 20)
                        }

                        // ORGANIZATION DETAILS Section
                        ExpandableSection(
                            title: "ORGANIZATION DETAILS",
                            icon: "building.2",
                            isExpanded: $isDetailsExpanded,
                            onDelete: nil
                        ) {
                            VStack(spacing: 16) {
                                // Phone Field
                                formField(
                                    label: "PHONE",
                                    text: $editedPhone,
                                    placeholder: "Enter phone number",
                                    keyboardType: .phonePad,
                                    field: .phone
                                )

                                // Email Field
                                formField(
                                    label: "EMAIL",
                                    text: $editedEmail,
                                    placeholder: "Enter email address",
                                    keyboardType: .emailAddress,
                                    field: .email
                                )

                                // Website Field
                                formField(
                                    label: "WEBSITE",
                                    text: $editedWebsite,
                                    placeholder: "Enter website URL",
                                    keyboardType: .URL,
                                    field: .website
                                )

                                // Address Field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ADDRESS")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    if isCompanyAdmin {
                                        // Only show autocomplete when field is tapped
                                        if isAddressFieldActive {
                                            AddressAutocompleteField(
                                                address: $editedAddress,
                                                placeholder: "Enter company address",
                                                onAddressSelected: { fullAddress, _ in
                                                    editedAddress = fullAddress
                                                    isAddressFieldActive = false
                                                    checkForChanges()
                                                }
                                            )
                                            .onChange(of: editedAddress) { _, _ in
                                                checkForChanges()
                                            }
                                        } else {
                                            // Show as tappable field that activates autocomplete
                                            Button(action: {
                                                isAddressFieldActive = true
                                            }) {
                                                HStack {
                                                    Text(editedAddress.isEmpty ? "Enter company address" : editedAddress)
                                                        .font(OPSStyle.Typography.body)
                                                        .foregroundColor(editedAddress.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
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
                                                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                                                )
                                            }
                                        }
                                    } else {
                                        Text(editedAddress.isEmpty ? "NO ADDRESS" : editedAddress)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(editedAddress.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.clear)
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                                            )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // COMPANY CODE Section (non-editable, copyable)
                        companyCodeSection
                            .padding(.horizontal, 20)

                        // Save/Cancel buttons (only show if changes made and admin)
                        if hasChanges && isCompanyAdmin {
                            actionButtons
                                .padding(.horizontal, 20)
                        }

                        // Error message
                        if let error = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(OPSStyle.Colors.errorStatus)

                                Text(error)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .standardSheetToolbar(
            title: "Organization Details",
            actionText: "Save",
            isActionEnabled: hasChanges && isCompanyAdmin,
            isSaving: isSaving,
            onCancel: { dismiss() },
            onAction: { Task { await saveChanges() } }
        )
        .loadingOverlay(isPresented: $isSaving, message: "Saving...")
        .onAppear {
            loadOrganizationData()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(
                images: Binding(
                    get: { companyImage.map { [$0] } ?? [] },
                    set: { images in
                        companyImage = images.first
                        checkForChanges()
                    }
                ),
                allowsEditing: true,
                sourceType: .photoLibrary,
                selectionLimit: 1
            )
        }
    }

    // MARK: - Preview Card (Live Updating)

    private var previewCard: some View {
        CompanyContactCard(
            name: company?.name ?? "",
            logoURL: company?.logoURL,
            logoData: company?.logoData,
            logoImage: companyImage,
            email: editedEmail,
            phone: editedPhone,
            address: editedAddress,
            website: editedWebsite,
            teamMemberCount: company?.teamMembers.count ?? 0,
            showTeamCount: true
        )
    }

    // MARK: - Company Code Section

    private var companyCodeSection: some View {
        // Use company's externalId (companyID from Bubble) as the company code
        let companyCode = company?.externalId ?? ""

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COMPANY CODE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Button(action: {
                    showingCompanyCodeInfo = true
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .popover(isPresented: $showingCompanyCodeInfo, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What is this?")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("Share this code with your employees so they can join your organization when signing up for OPS. They'll enter this code during registration to automatically connect to your company.")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(width: 280)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .presentationCompactAdaptation(.popover)
                }

                Spacer()
            }

            // Standard input field styling (read-only with copy button)
            HStack {
                if companyCode.isEmpty {
                    Text("NO CODE AVAILABLE")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                } else {
                    Text(companyCode.uppercased())
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                Spacer()

                if !companyCode.isEmpty {
                    Button(action: {
                        UIPasteboard.general.string = companyCode.uppercased()
                        // Haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                            Text("COPY")
                                .font(OPSStyle.Typography.smallCaption)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Logo Uploader

    private var logoUploader: some View {
        HStack(spacing: 16) {
            // Logo square
            Button(action: { showImagePicker = true }) {
                ZStack {
                    if let image = companyImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 2)
                            )
                    } else if let data = company?.logoData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 2)
                            )
                    } else if let urlString = company?.logoURL,
                              !urlString.isEmpty,
                              let url = normalizedLogoURL(urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 2)
                                    )
                            default:
                                logoPlaceholder
                            }
                        }
                    } else {
                        logoPlaceholder
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(companyImage == nil && company?.logoURL == nil && company?.logoData == nil ? "TAP TO ADD LOGO" : "CHANGE LOGO")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                if companyImage != nil || company?.logoURL != nil || company?.logoData != nil {
                    Button(action: {
                        companyImage = nil
                        // Mark for deletion on save
                        checkForChanges()
                    }) {
                        Text("Remove logo")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
            }

            Spacer()
        }
    }

    private var logoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(OPSStyle.Colors.cardBackgroundDark)
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "building.2")
                    .font(.system(size: 32))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 2)
            )
    }

    /// Normalizes logo URL by adding https: scheme for protocol-relative URLs
    private func normalizedLogoURL(_ urlString: String) -> URL? {
        let fixedURLString = urlString.hasPrefix("//") ? "https:\(urlString)" : urlString
        return URL(string: fixedURLString)
    }

    // MARK: - Form Field

    private func formField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        keyboardType: UIKeyboardType,
        field: OrganizationFormField
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if isCompanyAdmin {
                TextField(placeholder, text: text)
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
                                lineWidth: 1
                            )
                    )
                    .onChange(of: text.wrappedValue) { _, _ in
                        checkForChanges()
                    }
            } else {
                Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(text.wrappedValue.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Cancel button
            Button(action: {
                resetChanges()
            }) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            }
            .disabled(isSaving)

            // Save button
            Button(action: {
                Task {
                    await saveChanges()
                }
            }) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.8)
                    }
                    Text(isSaving ? "SAVING..." : "SAVE CHANGES")
                        .font(OPSStyle.Typography.captionBold)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .disabled(isSaving)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.2)

            Text("Loading organization...")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadOrganizationData() {
        guard let companyID = dataController.currentUser?.companyId else {
            isLoading = false
            return
        }

        Task {
            if dataController.isConnected {
                await MainActor.run { isRefreshing = true }

                do {
                    try await dataController.forceRefreshCompany(id: companyID)
                } catch {
                    print("[ORG_DETAILS] Error refreshing company: \(error)")
                }

                await MainActor.run { isRefreshing = false }
            }

            await MainActor.run {
                // Initialize editable fields with current values
                if let company = company {
                    editedPhone = company.phone ?? ""
                    editedEmail = company.email ?? ""
                    editedWebsite = company.website ?? ""
                    editedAddress = company.address ?? ""
                }
                isLoading = false
            }
        }
    }

    // MARK: - Change Detection

    private func hasFieldChanged(_ current: String, _ original: String?) -> Bool {
        let originalTrimmed = (original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return currentTrimmed != originalTrimmed
    }

    private func checkForChanges() {
        guard let company = company else {
            hasChanges = false
            return
        }

        let fieldsChanged = hasFieldChanged(editedPhone, company.phone) ||
                           hasFieldChanged(editedEmail, company.email) ||
                           hasFieldChanged(editedWebsite, company.website) ||
                           hasFieldChanged(editedAddress, company.address)

        let logoChanged = companyImage != nil

        hasChanges = fieldsChanged || logoChanged
    }

    private func resetChanges() {
        guard let company = company else { return }

        editedPhone = company.phone ?? ""
        editedEmail = company.email ?? ""
        editedWebsite = company.website ?? ""
        editedAddress = company.address ?? ""
        companyImage = nil
        hasChanges = false
        errorMessage = nil
    }

    // MARK: - Save Changes

    @MainActor
    private func saveChanges() async {
        guard let company = company else { return }

        isSaving = true
        errorMessage = nil

        do {
            // Upload logo if changed
            if let image = companyImage {
                _ = try await dataController.uploadCompanyLogo(image, for: company)
            }

            // Build fields to update
            var fieldsToUpdate: [String: Any] = [:]

            if hasFieldChanged(editedPhone, company.phone) {
                let newValue = editedPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                fieldsToUpdate["phone"] = newValue
                company.phone = newValue.isEmpty ? nil : newValue
            }
            if hasFieldChanged(editedEmail, company.email) {
                let newValue = editedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                fieldsToUpdate["email"] = newValue
                company.email = newValue.isEmpty ? nil : newValue
            }
            if hasFieldChanged(editedWebsite, company.website) {
                let newValue = editedWebsite.trimmingCharacters(in: .whitespacesAndNewlines)
                fieldsToUpdate["website"] = newValue
                company.website = newValue.isEmpty ? nil : newValue
            }
            if hasFieldChanged(editedAddress, company.address) {
                let newValue = editedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                fieldsToUpdate["address"] = newValue
                company.address = newValue.isEmpty ? nil : newValue
            }

            try dataController.modelContext?.save()

            // Update in Bubble if connected and there are field changes
            if dataController.isConnected && !fieldsToUpdate.isEmpty {
                try await dataController.apiService.updateCompanyFields(
                    companyId: company.id,
                    fields: fieldsToUpdate
                )
            }

            // Success haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            hasChanges = false
            companyImage = nil
            print("[ORG_DETAILS] Successfully saved changes")

        } catch {
            // Error haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)

            errorMessage = "Failed to save changes"
            print("[ORG_DETAILS] Error saving changes: \(error)")
        }

        isSaving = false
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        OrganizationDetailsView()
            .environmentObject(DataController())
    }
    .preferredColorScheme(.dark)
}
