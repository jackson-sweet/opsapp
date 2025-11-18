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

                        // Import from Contacts button (only in create mode)
                        if mode.isCreate {
                            Button(action: { showingContactPicker = true }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 16))
                                    Text("IMPORT FROM CONTACTS")
                                        .font(OPSStyle.Typography.bodyBold)
                                }
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }

                        // Name Field with Duplicate Detection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CLIENT NAME")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            TextField("Enter client name", text: $name)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.words)
                                .padding()
                                .background(Color.clear)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                        VStack(alignment: .leading, spacing: 12) {
                            Text("EMAIL")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            TextField("Enter email address", text: $email)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .autocorrectionDisabled(true)
                                .padding()
                                .background(Color.clear)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }

                        // Phone Field
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PHONE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            TextField("Enter phone number", text: $phone)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.phonePad)
                                .autocorrectionDisabled(true)
                                .padding()
                                .background(Color.clear)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }

                        // Address Field
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ADDRESS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            AddressSearchField(
                                address: $address,
                                placeholder: "Enter client address"
                            )
                        }

                        // Notes Field
                        VStack(alignment: .leading, spacing: 12) {
                            Text("NOTES")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            TextEditor(text: $notes)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .frame(minHeight: 80)
                                .padding(12)
                                .background(Color.clear)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .scrollContentBackground(.hidden)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                    .padding()
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
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
                            Text("Save")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                    }
                    .foregroundColor(name.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                    .disabled(name.isEmpty || isSaving)
                }
            }
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
                }, onDismiss: nil)
            }
        }
    }
    
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

        print("[CLIENT_CREATE] Creating client in Bubble...")

        // Create local client with temporary UUID
        let tempClient = Client(
            id: UUID().uuidString,
            name: name,
            email: email.isEmpty ? nil : email,
            phoneNumber: phone.isEmpty ? nil : phone,
            address: address.isEmpty ? nil : address,
            companyId: companyId,
            notes: notes.isEmpty ? nil : notes
        )

        // Create in Bubble API first
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
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
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
                        }

                        Spacer()
                    }

                    // Metadata row
                    HStack(spacing: 12) {
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

                        Spacer()
                    }
                }
                .padding(14)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
        .opacity(0.7) // Slightly faded to indicate it's a preview
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
