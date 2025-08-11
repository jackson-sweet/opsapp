//
//  SubClientEditSheet.swift
//  OPS
//
//  Sheet for creating or editing sub-client information
//

import SwiftUI
import ContactsUI

struct SubClientEditSheet: View {
    let client: Client
    let subClient: SubClient?  // nil for new sub-client
    let onSave: (String, String?, String?, String?, String?) async -> Void
    @Binding var isPresented: Bool
    
    @State private var name: String = ""
    @State private var title: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var address: String = ""
    @State private var isSaving: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingContactPicker = false
    @State private var showingCompanyConfirmation = false
    @State private var pendingCompanyName: String = ""
    @State private var showingImportConflictDialog = false
    @State private var pendingImportData: (name: String, email: String?, phone: String?, address: String?, title: String?) = ("", nil, nil, nil, nil)
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, title, email, phone, address
    }
    
    var isCreating: Bool {
        subClient == nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                OPSStyle.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Form fields
                        VStack(spacing: 16) {
                            // Name field (required)
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Name *", systemImage: "person")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                TextField("Enter name", text: $name)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .focused($focusedField, equals: .name)
                            }
                            
                            // Title field
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Title", systemImage: "briefcase")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                TextField("Enter title", text: $title)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .focused($focusedField, equals: .title)
                            }
                            
                            // Email field
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Email", systemImage: "envelope")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                TextField("Enter email", text: $email)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .focused($focusedField, equals: .email)
                            }
                            
                            // Phone field
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Phone", systemImage: "phone")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                TextField("Enter phone number", text: $phone)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .keyboardType(.phonePad)
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .focused($focusedField, equals: .phone)
                            }
                            
                            // Address field with autocomplete
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Address", systemImage: "location")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                AddressSearchField(address: $address, placeholder: "Enter address")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)
                        
                        // Required field note
                        Text("* Required field")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        
                        Spacer(minLength: 100)
                        
                        Button(action: {
                            showingContactPicker = true
                        }) {

                                HStack(spacing: 4) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                    Text("Import from Contacts")

                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                
                            }
                                
                        }
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .navigationTitle(isCreating ? "New Sub Contact" : subClient?.name ?? "Edit Sub Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveSubClient) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Import Conflicts Found", isPresented: $showingImportConflictDialog) {
                Button("Keep Current Data") {
                    // Do nothing
                }
                Button("Replace with Imported") {
                    // Replace all fields with imported data
                    if !pendingImportData.name.isEmpty {
                        name = pendingImportData.name
                    }
                    if let emailVal = pendingImportData.email {
                        email = emailVal
                    }
                    if let phoneVal = pendingImportData.phone {
                        phone = phoneVal
                    }
                    if let addressVal = pendingImportData.address {
                        address = addressVal
                    }
                    if let titleVal = pendingImportData.title {
                        title = titleVal
                    }
                }
                Button("Merge (Keep Non-Empty)", role: .destructive) {
                    // Only replace empty fields
                    if name.isEmpty && !pendingImportData.name.isEmpty {
                        name = pendingImportData.name
                    }
                    if email.isEmpty, let emailVal = pendingImportData.email {
                        email = emailVal
                    }
                    if phone.isEmpty, let phoneVal = pendingImportData.phone {
                        phone = phoneVal
                    }
                    if address.isEmpty, let addressVal = pendingImportData.address {
                        address = addressVal
                    }
                    if title.isEmpty, let titleVal = pendingImportData.title {
                        title = titleVal
                    }
                }
            } message: {
                Text("Some fields already have data. How would you like to handle the imported information?")
            }
            .alert("Company Name Found", isPresented: $showingCompanyConfirmation) {
                Button("Keep Current", role: .cancel) {
                    pendingCompanyName = ""
                }
                Button("Replace") {
                    // This would need to update the parent client's name
                    // For now, we'll just clear it as we can't modify parent from here
                    pendingCompanyName = ""
                }
            } message: {
                Text("The contact has a company name '\(pendingCompanyName)'. Would you like to replace the parent client's name '\(client.name)' with this company name?")
            }
            .onAppear {
                loadSubClientData()
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPicker(
                    onContactSelected: { contact in
                        // Prepare imported data
                        let importedName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                        let importedEmail = contact.emailAddresses.first?.value as String?
                        let importedPhone = contact.phoneNumbers.first?.value.stringValue
                        let importedTitle = contact.jobTitle.isEmpty ? nil : contact.jobTitle
                        
                        var importedAddress: String? = nil
                        if let postalAddress = contact.postalAddresses.first?.value {
                            let addressComponents = [
                                postalAddress.street,
                                postalAddress.city,
                                postalAddress.state,
                                postalAddress.postalCode
                            ].filter { !$0.isEmpty }
                            importedAddress = addressComponents.joined(separator: ", ")
                        }
                        
                        // Check for conflicts
                        let hasConflicts = (!name.isEmpty && name != importedName) ||
                                         (!email.isEmpty && importedEmail != nil && email != importedEmail) ||
                                         (!phone.isEmpty && importedPhone != nil && phone != importedPhone) ||
                                         (!address.isEmpty && importedAddress != nil && address != importedAddress) ||
                                         (!title.isEmpty && importedTitle != nil && title != importedTitle)
                        
                        if hasConflicts {
                            // Store pending data and show conflict dialog
                            pendingImportData = (importedName, importedEmail, importedPhone, importedAddress, importedTitle)
                            showingImportConflictDialog = true
                        } else {
                            // No conflicts, update fields
                            if !importedName.isEmpty {
                                name = importedName
                            }
                            if let emailVal = importedEmail {
                                email = emailVal
                            }
                            if let phoneVal = importedPhone {
                                phone = phoneVal
                            }
                            if let addressVal = importedAddress {
                                address = addressVal
                            }
                            if let titleVal = importedTitle {
                                title = titleVal
                            }
                        }
                        
                        // Check if contact has a company name (after handling other fields)
                        if !contact.organizationName.isEmpty {
                            pendingCompanyName = contact.organizationName
                            showingCompanyConfirmation = true
                        }
                    },
                    onDismiss: {
                        showingContactPicker = false
                    }
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadSubClientData() {
        if let subClient = subClient {
            name = subClient.name
            title = subClient.title ?? ""
            email = subClient.email ?? ""
            phone = subClient.phoneNumber ?? ""
            address = subClient.address ?? ""
        }
    }
    
    private func saveSubClient() {
        // Validate name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required"
            showError = true
            return
        }
        
        // Extract phone digits only
        let cleanedPhone = phone.isEmpty ? nil : phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        isSaving = true
        
        Task {
            await onSave(
                trimmedName,
                title.isEmpty ? nil : title,
                email.isEmpty ? nil : email,
                cleanedPhone,
                address.isEmpty ? nil : address
            )
            
            await MainActor.run {
                isSaving = false
                isPresented = false
            }
        }
    }
    
}
