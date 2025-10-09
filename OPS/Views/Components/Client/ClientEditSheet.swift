//
//  ClientEditSheet.swift
//  OPS
//
//  Sheet for editing client information
//

import SwiftUI
import ContactsUI

struct ClientEditSheet: View {
    let client: Client
    let onSave: (String, String?, String?, String?) async -> Void
    @Binding var isPresented: Bool
    
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var address: String = ""
    @State private var isSaving: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingContactPicker = false
    @State private var showingImportConflictDialog = false
    @State private var pendingImportData: (name: String, email: String?, phone: String?, address: String?) = ("", nil, nil, nil)
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, email, phone, address
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
                        
                        // Import from Contacts button
                        Button(action: {
                            showingContactPicker = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                Text("Import from Contacts")
                            }
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1.5)
                            )
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .navigationTitle(client.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .disabled(isSaving)
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
                    .foregroundColor(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
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
                }
            } message: {
                Text("Some fields already have data. How would you like to handle the imported information?")
            }
            .onAppear {
                loadClientData()
            }
            .sheet(isPresented: $showingContactPicker) {
                ContactPicker(
                    onContactSelected: handleContactImport,
                    onDismiss: {
                        showingContactPicker = false
                    }
                )
            }
        }
    }
    
    private func loadClientData() {
        name = client.name
        email = client.email ?? ""
        phone = client.phoneNumber ?? ""
        address = client.address ?? ""
    }
    
    private func saveClient() {
        isSaving = true
        
        Task {
            await onSave(
                name,
                email.isEmpty ? nil : email,
                phone.isEmpty ? nil : phone,
                address.isEmpty ? nil : address
            )
            
            await MainActor.run {
                isSaving = false
                isPresented = false
            }
        }
    }
    
    private func handleContactImport(contact: CNContact) {
        let importedName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        let importedEmail = contact.emailAddresses.first?.value as String?
        let importedPhone = contact.phoneNumbers.first?.value.stringValue
        
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
        
        // Check if there are conflicts with existing data
        let hasConflicts = (!name.isEmpty && name != importedName) ||
                         (!email.isEmpty && importedEmail != nil && email != importedEmail) ||
                         (!phone.isEmpty && importedPhone != nil && phone != importedPhone) ||
                         (!address.isEmpty && importedAddress != nil && address != importedAddress)
        
        if hasConflicts {
            // Store pending data and show conflict dialog
            pendingImportData = (importedName, importedEmail, importedPhone, importedAddress)
            showingImportConflictDialog = true
        } else {
            // No conflicts, just update the fields
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
        }
    }
}