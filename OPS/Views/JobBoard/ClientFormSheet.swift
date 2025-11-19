//
//  ClientFormSheet.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-09-26.
//

import SwiftUI
import ContactsUI

struct ClientFormSheet: View {
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
                    VStack(spacing: 24) {
                        // PREVIEW CARD
                        previewCard

                        // CLIENT DETAILS Section - ALL FIELDS IN ONE SECTION
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("CLIENT DETAILS")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Spacer()

                                // De-emphasized Import from Contacts button
                                if mode.isCreate {
                                    Button(action: { showingContactPicker = true }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "person.crop.circle")
                                                .font(.caption)
                                            Text("Import from contacts")
                                                .font(OPSStyle.Typography.caption)
                                        }
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                }
                            }

                            VStack(spacing: 16) {
                                // Avatar Uploader
                                avatarUploader

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
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .background(Color.clear)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                        )
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

                                    TextField("email@example.com", text: $email, prompt: Text("email@example.com").foregroundColor(OPSStyle.Colors.tertiaryText))
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled(true)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .background(Color.clear)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(showEmailError ? Color.red.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                        .onChange(of: email) { _, _ in
                                            showEmailError = !isValidEmail
                                        }

                                    if showEmailError {
                                        Text("Invalid email format")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(.red)
                                    }
                                }

                                // Phone Field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("PHONE")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    TextField("(555) 123-4567", text: $phone)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .keyboardType(.phonePad)
                                        .autocorrectionDisabled(true)
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .background(Color.clear)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(showPhoneError ? Color.red.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                        .onChange(of: phone) { _, _ in
                                            showPhoneError = !isValidPhone
                                        }

                                    if showPhoneError {
                                        Text("Invalid phone format")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(.red)
                                    }
                                }

                                // Address Field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ADDRESS")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    AddressSearchField(
                                        address: $address,
                                        placeholder: "Start typing address..."
                                    )
                                }

                                // Notes Field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("NOTES")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    ZStack(alignment: .topLeading) {
                                        if notes.isEmpty {
                                            Text("Add notes...")
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                .padding(.top, 20)
                                                .padding(.leading, 16)
                                        }

                                        TextEditor(text: $notes)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .frame(minHeight: 80, maxHeight: 200)
                                            .padding(12)
                                            .background(Color.clear)
                                            .scrollContentBackground(.hidden)
                                    }
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .principal) {
                    Text(mode.isCreate ? "CREATE CLIENT" : "EDIT CLIENT")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveClient) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                .scaleEffect(0.8)
                        } else {
                            Text(mode.isCreate ? "CREATE" : "SAVE")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                    }
                    .foregroundColor(isFormValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .disabled(!isFormValid || isSaving)
                }
            }
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
                    sourceType: .both,
                    selectionLimit: 1
                )
            }
        }
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
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                    } else {
                        Circle()
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "building.2")
                                    .font(.system(size: 32))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            )
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
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
                            .foregroundColor(.red.opacity(0.8))
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
        isSaving = true

        Task {
            do {
                if case .create = mode {
                    // Create new client
                    let newClient = try await createNewClient()
                    await MainActor.run {
                        // Success haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)

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
    
    private func createNewClient() async throws -> Client {
        guard let companyId = dataController.currentUser?.companyId else {
            throw ClientError.noCompanyId
        }

        print("[CLIENT_CREATE] Creating client...")

        // Create local client with temporary UUID
        let tempId = UUID().uuidString
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

        // Set profile image URL if uploaded
        if let imageURL = profileImageURL {
            tempClient.profileImageURL = imageURL
        }

        // Create in Bubble API
        print("[CLIENT_CREATE] Creating client in Bubble...")
        let bubbleId = try await dataController.apiService.createClient(tempClient)
        print("[CLIENT_CREATE] ✅ Client created in Bubble with ID: \(bubbleId)")

        // Update local client with Bubble ID
        tempClient.id = bubbleId
        tempClient.needsSync = false
        tempClient.lastSyncedAt = Date()

        // Link client to company's Client list
        print("[CLIENT_CREATE] Linking client to company...")
        try await dataController.apiService.linkClientToCompany(companyId: companyId, clientId: bubbleId)

        // Save to data controller
        await MainActor.run {
            dataController.saveClient(tempClient)
        }

        return tempClient
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
            HStack(alignment: .top, spacing: 12) {
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
                            .font(.system(size: 11))
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
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                    } else if !name.isEmpty {
                        // Show initials if name exists but no image
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(String(name.prefix(1)).uppercased())
                                    .font(.custom("Mohave-Bold", size: 20))
                                    .foregroundColor(.white)
                            )
                    } else {
                        // Placeholder
                        Circle()
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "building.2")
                                    .font(.system(size: 20))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            )
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.7))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
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
                .font(.system(size: 16))
            
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
                .fill(Color.orange.opacity(0.1))
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
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
