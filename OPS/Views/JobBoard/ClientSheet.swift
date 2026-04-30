//
//  ClientSheet.swift
//  OPS
//
//  Unified sheet for creating and editing clients
//  Replaces ClientFormSheet and ClientEditSheet
//

import SwiftUI
import SwiftData
import ContactsUI

struct ClientSheet: View {
    enum Mode {
        case create
        case edit(Client)
        
        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }
        
        var client: Client? {
            if case .edit(let client) = self { return client }
            return nil
        }
    }
    
    let mode: Mode
    let onSave: (Client) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    // Wizard state so the project-lifecycle banner + instruction bar stay
    // visible when this sheet is presented over the root view.
    @Environment(\.wizardStateManager) private var wizardStateManager

    // Form Fields
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var address: String = ""
    @State private var notes: String = ""

    // Avatar
    @State private var clientImage: UIImage?
    @State private var clientImageURL: String?
    @State private var showImagePicker = false

    // Duplicate Detection
    @State private var duplicateCheckResult: DuplicateCheckResult?
    @State private var showingDuplicateAlert = false
    @State private var checkingDuplicate = false

    // Loading state
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false

    // Contact Import
    @State private var showingContactPicker = false

    // Validation
    @State private var showEmailError = false
    @State private var showPhoneError = false

    // Focus states for input fields
    @FocusState private var focusedField: ClientFormField?

    // Temporary state for notes editing
    @State private var tempNotes: String = ""

    // Section expansion
    @State private var isClientDetailsExpanded = true

    enum ClientFormField: Hashable {
        case name
        case email
        case phone
        case address
        case notes
    }

    init(mode: Mode, prefilledName: String? = nil, onSave: @escaping (Client) -> Void) {
        self.mode = mode
        self.onSave = onSave

        // Pre-populate fields if editing
        if case .edit(let client) = mode {
            _name = State(initialValue: client.name)
            _email = State(initialValue: client.email ?? "")
            _phone = State(initialValue: client.phoneNumber ?? "")
            _address = State(initialValue: client.address ?? "")
            _notes = State(initialValue: client.notes ?? "")
            _clientImageURL = State(initialValue: client.profileImageURL)
        } else if let prefilledName = prefilledName {
            _name = State(initialValue: prefilledName)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    ScrollViewReader { proxy in
                    VStack(spacing: 24) {
                        // PREVIEW CARD
                        previewCard

                        // AVATAR PICKER (above section)
                        avatarUploader

                        // CLIENT DETAILS Section - ALL FIELDS IN ONE SECTION
                        ExpandableSection(
                            title: "CLIENT DETAILS",
                            icon: "person.text.rectangle",
                            isExpanded: $isClientDetailsExpanded,
                            onDelete: nil
                        ) {
                            VStack(spacing: 16) {
                                // Name Field with Duplicate Detection
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("CLIENT NAME")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    TextField("Client name", text: $name)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .autocorrectionDisabled(true)
                                        .textInputAutocapitalization(.words)
                                        .focused($focusedField, equals: .name)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .background(Color.clear)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(
                                                    focusedField == .name ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder,
                                                    lineWidth: OPSStyle.Layout.Border.standard
                                                )
                                        )
                                        .wizardTarget("fill_client_name", style: .input)
                                        .onChange(of: name) { _, newValue in
                                            if mode.isCreate {
                                                checkForDuplicates()
                                            }
                                        }

                                    if let duplicate = duplicateCheckResult {
                                        DuplicateWarning(duplicate: duplicate) {
                                            // Use existing client
                                            if let existingClient = dataController.getAllClients(for: dataController.currentUser?.companyId ?? "").first(where: { $0.id == duplicate.clientId }) {
                                                dismiss()
                                                onSave(existingClient)
                                            }
                                        }
                                    }
                                }

                                // Email Field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("EMAIL")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    TextField("Email Address", text: $email)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled(true)
                                        .focused($focusedField, equals: .email)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .background(Color.clear)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(
                                                    showEmailError ? OPSStyle.Colors.errorStatus.opacity(0.5) : (focusedField == .email ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder),
                                                    lineWidth: OPSStyle.Layout.Border.standard
                                                )
                                        )
                                        .onChange(of: email) { _, _ in
                                            showEmailError = !isValidEmail
                                        }

                                    if showEmailError {
                                        Text("Invalid email format")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.errorStatus)
                                    }
                                }

                                // Phone Field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("PHONE")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    TextField("Phone Number", text: $phone)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .keyboardType(.phonePad)
                                        .autocorrectionDisabled(true)
                                        .focused($focusedField, equals: .phone)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .background(Color.clear)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(
                                                    showPhoneError ? OPSStyle.Colors.errorStatus.opacity(0.5) : (focusedField == .phone ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder),
                                                    lineWidth: OPSStyle.Layout.Border.standard
                                                )
                                        )
                                        .onChange(of: phone) { _, _ in
                                            showPhoneError = !isValidPhone
                                        }

                                    if showPhoneError {
                                        Text("Invalid phone format")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.errorStatus)
                                    }
                                }

                                // Address Field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ADDRESS")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    AddressAutocompleteField(
                                        address: $address,
                                        placeholder: "Client Address",
                                        onAddressSelected: { fullAddress, _ in
                                            address = fullAddress
                                        }
                                    )
                                }

                                // Notes Field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("NOTES")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    VStack(spacing: 12) {
                                        ZStack(alignment: .topLeading) {
                                            if (focusedField == .notes ? tempNotes : notes).isEmpty {
                                                Text("Add notes...")
                                                    .font(OPSStyle.Typography.body)
                                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                    .padding(.top, 20)
                                                    .padding(.leading, 16)
                                            }

                                            TextEditor(text: focusedField == .notes ? $tempNotes : $notes)
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                                .frame(minHeight: 80, maxHeight: 200)
                                                .padding(12)
                                                .background(Color.clear)
                                                .scrollContentBackground(.hidden)
                                                .focused($focusedField, equals: .notes)
                                                .onTapGesture {
                                                    if focusedField != .notes {
                                                        tempNotes = notes
                                                        focusedField = .notes
                                                    }
                                                }
                                        }
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(
                                                    focusedField == .notes ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder,
                                                    lineWidth: OPSStyle.Layout.Border.standard
                                                )
                                        )

                                        if focusedField == .notes {
                                            HStack(spacing: 16) {
                                                Spacer()

                                                Button("CANCEL") {
                                                    tempNotes = ""
                                                    focusedField = nil
                                                }
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)

                                                Button("SAVE") {
                                                    notes = tempNotes
                                                    focusedField = nil
                                                }
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // IMPORT FROM CONTACTS BUTTON (at bottom) - available in both create and edit modes
                        Button(action: { showingContactPicker = true }) {
                            HStack {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                Text("IMPORT FROM CONTACTS")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                    // Wizard system: scroll to the target element when a wizard step activates
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardScrollToTarget"))) { notification in
                        guard let stepId = notification.userInfo?["stepId"] as? String else { return }
                        let wizardId = "wizard_active_\(stepId)"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation {
                                proxy.scrollTo(wizardId, anchor: .top)
                            }
                        }
                    }
                    }
                }
            }
            .standardSheetToolbar(
                title: mode.isCreate ? "Create Client" : "Edit Client",
                actionText: mode.isCreate ? "Create" : "Save",
                isActionEnabled: isFormValid,
                isSaving: isSaving,
                onCancel: { dismiss() },
                onAction: { saveClient() }
            )
            .loadingOverlay(isPresented: $isSaving, message: "Saving...")
            .interactiveDismissDisabled()
            .alert("Error", isPresented: $showingError) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPicker(onContactSelected: { contact in
                    // Populate form fields with contact data
                    name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)

                    // Get first email
                    if let email = contact.emailAddresses.first {
                        self.email = email.value as String
                    }

                    // Get first phone
                    if let phone = contact.phoneNumbers.first {
                        self.phone = phone.value.stringValue
                    }

                    // Get address
                    if let address = contact.postalAddresses.first {
                        let value = address.value
                        var addressComponents: [String] = []
                        if !value.street.isEmpty { addressComponents.append(value.street) }
                        if !value.city.isEmpty { addressComponents.append(value.city) }
                        if !value.state.isEmpty { addressComponents.append(value.state) }
                        if !value.postalCode.isEmpty { addressComponents.append(value.postalCode) }
                        self.address = addressComponents.joined(separator: ", ")
                    }

                    // Get contact photo if available
                    if let imageData = contact.imageData {
                        self.clientImage = UIImage(data: imageData)
                    }
                }, onDismiss: nil)
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(
                    images: Binding(
                        get: { clientImage.map { [$0] } ?? [] },
                        set: { images in
                            clientImage = images.first
                        }
                    ),
                    allowsEditing: true,
                    sourceType: .photoLibrary,
                    selectionLimit: 1
                )
            }
            .onAppear {
                // Track screen view for analytics
                AnalyticsManager.shared.trackScreenView(screenName: .clientForm, screenClass: "ClientSheet")
                AnalyticsService.shared.trackScreenView(screenName: "client_form")
            }
            .onDisappear {
                AnalyticsService.shared.endScreenView(screenName: "client_form")
                NotificationCenter.default.post(
                    name: Notification.Name("WizardScreenDismissed"),
                    object: nil,
                    userInfo: ["screen": "ClientForm"]
                )
            }
        }
        // Sheets present above the root view where wizardBanner / wizardOverlay
        // live, so the project-lifecycle guide is invisible here unless the
        // sheet re-attaches the wizard UI itself.
        .wizardBannerIfAvailable(stateManager: wizardStateManager)
        .wizardOverlayIfAvailable(stateManager: wizardStateManager)
    }

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        !name.isEmpty && isValidEmail && isValidPhone
    }

    private var isValidEmail: Bool {
        if email.isEmpty { return true } // Optional field
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private var isValidPhone: Bool {
        if phone.isEmpty { return true } // Optional field
        let phoneRegex = "^[0-9+\\s()\\-]{7,}$"
        let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return phonePredicate.evaluate(with: phone)
    }

    // MARK: - Avatar Uploader

    private var avatarUploader: some View {
        HStack(spacing: 16) {
            // Avatar circle
            Button(action: { showImagePicker = true }) {
                ZStack {
                    if let image = clientImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.thick))
                    } else {
                        Circle()
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "building.2")
                                    .font(.system(size: OPSStyle.Layout.IconSize.xl))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            )
                            .overlay(Circle().stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.thick))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(clientImage == nil ? "TAP TO ADD PHOTO" : "CHANGE PHOTO")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                if clientImage != nil {
                    Button(action: {
                        clientImage = nil
                        clientImageURL = nil
                    }) {
                        Text("Remove photo")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Helper Functions

    private func checkForDuplicates() {
        guard name.count >= 3 else {
            duplicateCheckResult = nil
            return
        }
        
        checkingDuplicate = true
        
        // Check for duplicates locally
        guard let companyId = dataController.currentUser?.companyId else { return }
        let existingClients = dataController.getAllClients(for: companyId)
        
        // Simple similarity check
        let similarClient = existingClients.first { client in
            let similarity = calculateSimilarity(name, client.name)
            return similarity >= 0.8 && client.id != mode.client?.id
        }
        
        if let similar = similarClient {
            duplicateCheckResult = DuplicateCheckResult(
                clientId: similar.id,
                clientName: similar.name,
                similarity: 0.8
            )
        } else {
            duplicateCheckResult = nil
        }
        
        checkingDuplicate = false
    }
    
    private func calculateSimilarity(_ str1: String, _ str2: String) -> Double {
        let s1 = str1.lowercased()
        let s2 = str2.lowercased()
        
        if s1 == s2 { return 1.0 }
        if s1.contains(s2) || s2.contains(s1) { return 0.8 }
        
        // Simple character matching
        let set1 = Set(s1)
        let set2 = Set(s2)
        let intersection = set1.intersection(set2)
        let union = set1.union(set2)
        
        return Double(intersection.count) / Double(union.count)
    }
    
    private func saveClient() {
        guard !isSaving else { return }
        isSaving = true

        Task {
            do {
                if case .create = mode {
                    // Create new client (and the matching pipeline lead, best-effort)
                    let result = try await createNewClient()
                    let newClient = result.client
                    let leadCreated = result.leadCreated
                    await MainActor.run {
                        // Success haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)

                        // Track client creation for analytics
                        AnalyticsManager.shared.trackClientCreated(
                            hasEmail: !email.isEmpty,
                            hasPhone: !phone.isEmpty,
                            hasAddress: !address.isEmpty,
                            importMethod: .manual
                        )
                        AnalyticsService.shared.track(
                            eventType: .action,
                            eventName: "client_created",
                            properties: [
                                "has_email": !email.isEmpty,
                                "has_phone": !phone.isEmpty,
                                "has_address": !address.isEmpty,
                                "import_method": ClientImportMethod.manual.rawValue,
                                "lead_created": leadCreated
                            ]
                        )

                        // Bug 321e65c8 — surface the auto-created pipeline lead
                        // in the success banner so the user knows new clients
                        // are now trackable in the sales pipeline. The toast in
                        // ContentView decides the wording based on this flag.
                        var userInfo: [AnyHashable: Any] = [
                            "clientName": name,
                            "clientId": newClient.id,
                            "leadCreated": leadCreated
                        ]
                        if let oppId = result.opportunityId {
                            userInfo["opportunityId"] = oppId
                        }

                        // Post notification for success message overlay
                        NotificationCenter.default.post(
                            name: Notification.Name("ClientCreatedSuccess"),
                            object: nil,
                            userInfo: userInfo
                        )

                        // Wizard system: notify client saved
                        NotificationCenter.default.post(
                            name: Notification.Name("WizardClientSaved"),
                            object: nil
                        )

                        onSave(newClient)

                        // Brief delay for graceful dismissal
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    }
                } else if case .edit(let client) = mode {
                    // Update existing client
                    try await updateExistingClient(client)
                    await MainActor.run {
                        // Success haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)

                        // Track client edit for analytics
                        AnalyticsManager.shared.trackClientEdited(clientId: client.id)

                        onSave(client)

                        // Brief delay for graceful dismissal
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    // Error haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)

                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
            }
        }
    }
    
    /// Result of the create-client flow. The lead may not be created if the
    /// client itself fell back to a pure-local insert (no SyncEngine) or if
    /// the opportunity insert failed for any reason — the client save is
    /// still considered successful and the user is told the lead is pending.
    private struct CreateClientResult {
        let client: Client
        let leadCreated: Bool
        let opportunityId: String?
    }

    private func createNewClient() async throws -> CreateClientResult {
        guard let companyId = dataController.currentUser?.companyId else {
            throw ClientError.noCompanyId
        }

        print("[CLIENT_CREATE] Creating client...")

        // Create local client with temporary UUID.
        // Bug b873deb7 — canonicalize to lowercase so the local id matches
        // Postgres (uuid columns are lowercase). Uppercase UUIDs from
        // Swift's UUID().uuidString caused fetch-by-id in InboundProcessor /
        // RealtimeProcessor to miss the realtime echo, inserting a second
        // row. Mirrors the project-create canonicalization in
        // ProjectFormSheet.swift (bug f86cf554).
        let tempId = UUID().uuidString.lowercased()
        var profileImageURL: String? = nil

        // Upload avatar image if provided
        if let image = clientImage {
            do {
                print("[CLIENT_CREATE] Uploading client profile image...")
                profileImageURL = try await S3UploadService.shared.uploadClientProfileImage(image, clientId: tempId, companyId: companyId)
                print("[CLIENT_CREATE] ✅ Profile image uploaded: \(profileImageURL ?? "")")
            } catch {
                print("[CLIENT_CREATE] ⚠️ Failed to upload profile image: \(error.localizedDescription)")
                // Continue with client creation even if image upload fails
            }
        }

        // Create local client
        let tempClient = Client(
            id: tempId,
            name: name,
            email: email.isEmpty ? nil : email,
            phoneNumber: phone.isEmpty ? nil : phone,
            address: address.isEmpty ? nil : address,
            companyId: companyId,
            notes: notes.isEmpty ? nil : notes
        )

        // Create via DataController (local-first with SyncEngine) — single source of truth
        let dto = SupabaseClientDTO(
            id: tempClient.id,
            bubbleId: nil,
            companyId: companyId,
            name: tempClient.name,
            email: tempClient.email,
            phoneNumber: tempClient.phoneNumber,
            address: tempClient.address,
            latitude: nil,
            longitude: nil,
            notes: tempClient.notes,
            profileImageUrl: profileImageURL,
            deletedAt: nil
        )

        let savedClient: Client

        do {
            let _ = try await dataController.createClient(dto: dto)
            print("[CLIENT_CREATE] ✅ Client created via DataController: \(tempClient.id)")

            // Return the context-managed client inserted by createClient
            if let created = dataController.getAllClients(for: companyId).first(where: { $0.id == tempClient.id }) {
                savedClient = created
            } else {
                savedClient = tempClient
            }
        } catch {
            print("[CLIENT_CREATE] ⚠️ DataController create failed, inserting locally: \(error)")
            // Fallback: insert directly so client is at least available locally
            if let imageURL = profileImageURL { tempClient.profileImageURL = imageURL }
            tempClient.needsSync = true
            await MainActor.run {
                dataController.saveClient(tempClient)
            }
            dataController.triggerBackgroundSync()
            // Skip lead creation when the client itself didn't reach Supabase —
            // the foreign key would 404 and create a noisy failure. The
            // background sync will pick the client up; if Jackson wants the
            // lead created retroactively we can wire a follow-up sync later.
            return CreateClientResult(client: tempClient, leadCreated: false, opportunityId: nil)
        }

        // Bug 321e65c8 — every new client is automatically tracked in the
        // pipeline as a "New Lead" so the user can move it through quoting,
        // follow-up, and won/lost without a separate lead-creation step.
        // Failure here is non-fatal: the client is still saved, and the user
        // is told the pipeline link is pending.
        let opportunityId = await createMatchingLead(for: savedClient, companyId: companyId)
        return CreateClientResult(
            client: savedClient,
            leadCreated: opportunityId != nil,
            opportunityId: opportunityId
        )
    }

    /// Creates a Pipeline Opportunity tied to a freshly-saved client.
    /// Returns the new opportunity id on success, or nil if creation failed
    /// (offline, network error, RLS denial). The caller treats nil as a
    /// "lead pending" state — the client is still considered saved.
    ///
    /// We create the opportunity via Supabase directly (mirrors
    /// LogActivityViewModel.save()). Opportunities are NOT registered as a
    /// SyncEntityType, so there's no SyncEngine route — direct API is the
    /// canonical pattern. Local SwiftData is updated in the same step so the
    /// pipeline view reflects the new lead immediately.
    private func createMatchingLead(for client: Client, companyId: String) async -> String? {
        let trimmedName = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            print("[LEAD_AUTOCREATE] Skipping — client has empty name")
            return nil
        }

        let dto = CreateOpportunityDTO(
            companyId: companyId,
            contactName: trimmedName,
            contactEmail: client.email,
            contactPhone: client.phoneNumber,
            description: nil,
            estimatedValue: nil,
            source: "client_created",
            quoteDeliveryMethod: nil,
            clientId: client.id
        )

        let repository = OpportunityRepository(companyId: companyId)
        do {
            let created = try await repository.create(dto)
            print("[LEAD_AUTOCREATE] ✅ Lead created for client \(client.id): opportunity \(created.id)")

            // Insert into local SwiftData so pipeline UI reflects the lead immediately.
            // Mirrors the pattern used in LogActivityViewModel.save().
            await MainActor.run {
                let model = created.toModel()
                if let context = dataController.modelContext {
                    // Avoid duplicate insert if a realtime echo beat us here.
                    let oppId = created.id
                    let descriptor = FetchDescriptor<Opportunity>(
                        predicate: #Predicate<Opportunity> { $0.id == oppId }
                    )
                    let existing = (try? context.fetch(descriptor)) ?? []
                    if existing.isEmpty {
                        context.insert(model)
                        try? context.save()
                    }
                }
            }

            return created.id
        } catch {
            print("[LEAD_AUTOCREATE] ⚠️ Failed to create lead for client \(client.id): \(error)")
            return nil
        }
    }
    
    private func updateExistingClient(_ client: Client) async throws {
        guard let companyId = dataController.currentUser?.companyId else {
            throw ClientError.noCompanyId
        }

        // Upload new avatar image if changed
        if let image = clientImage, clientImageURL != client.profileImageURL {
            do {
                print("[CLIENT_UPDATE] Uploading updated client profile image...")
                let newImageURL = try await S3UploadService.shared.uploadClientProfileImage(image, clientId: client.id, companyId: companyId)
                print("[CLIENT_UPDATE] ✅ Profile image uploaded: \(newImageURL)")

                await MainActor.run {
                    client.profileImageURL = newImageURL
                }
            } catch {
                print("[CLIENT_UPDATE] ⚠️ Failed to upload profile image: \(error.localizedDescription)")
                // Continue with client update even if image upload fails
            }
        }

        // Update client properties
        await MainActor.run {
            client.name = name
            client.email = email.isEmpty ? nil : email
            client.phoneNumber = phone.isEmpty ? nil : phone
            client.address = address.isEmpty ? nil : address
            client.notes = notes.isEmpty ? nil : notes
        }

        // Use centralized function for immediate sync
        try await dataController.updateClient(client: client)
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    // Client name
                    Text(name.isEmpty ? "CLIENT NAME" : name.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(name.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    // Email or phone
                    if !email.isEmpty {
                        Text(email)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    } else if !phone.isEmpty {
                        Text(phone)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    } else {
                        Text("NO CONTACT INFO")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }

                    // Address
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text(address.isEmpty ? "NO ADDRESS" : address.components(separatedBy: ",").first ?? address)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Avatar on right side
                ZStack {
                    if let image = clientImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.thick))
                    } else if !name.isEmpty {
                        // Show initials if name exists but no image
                        Circle()
                            .stroke(OPSStyle.Colors.primaryText, lineWidth: OPSStyle.Layout.Border.thick)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(String(name.prefix(1)).uppercased())
                                    .font(OPSStyle.Typography.headingBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            )
                    } else {
                        // Placeholder
                        Circle()
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "building.2")
                                    .font(.system(size: OPSStyle.Layout.IconSize.lg))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            )
                            .overlay(Circle().stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.thick))
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.7))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }
}

// MARK: - Duplicate Warning View
struct DuplicateWarning: View {
    let duplicate: DuplicateCheckResult
    let onUseExisting: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Possible duplicate")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.orange)
                
                Text(duplicate.clientName)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            Button("USE EXISTING") {
                onUseExisting()
            }
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.warningStatus.opacity(0.1))
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

// MARK: - Supporting Types
struct DuplicateCheckResult {
    let clientId: String
    let clientName: String
    let similarity: Double
}

enum ClientError: LocalizedError {
    case noCompanyId
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .noCompanyId:
            return "No company ID found"
        case .saveFailed:
            return "Failed to save client"
        }
    }
}
