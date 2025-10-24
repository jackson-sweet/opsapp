//
//  SubClientEditSheet.swift
//  OPS
//
//  Sheet for creating or editing sub-client information
//

import SwiftUI
import ContactsUI

// View Model for SubClient editing
class SubClientEditViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var title: String = ""
    @Published var email: String = ""
    @Published var phone: String = ""
    @Published var address: String = ""
    
    func loadFromSubClient(_ subClient: SubClient?) {
        if let subClient = subClient {
            self.name = subClient.name
            self.title = subClient.title ?? ""
            self.email = subClient.email ?? ""
            self.phone = subClient.phoneNumber ?? ""
            self.address = subClient.address ?? ""
        } else {
            // Reset for new sub-client
            self.name = ""
            self.title = ""
            self.email = ""
            self.phone = ""
            self.address = ""
        }
    }
}

struct SubClientEditSheet: View {
    let client: Client
    let subClient: SubClient?  // nil for new sub-client
    let onSave: (String, String?, String?, String?, String?) async -> Void
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var viewModel = SubClientEditViewModel()
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
                                
                                TextField("Enter name", text: $viewModel.name)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.words)
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
                                
                                TextField("Enter title", text: $viewModel.title)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.words)
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
                                
                                TextField("Enter email", text: $viewModel.email)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled(true)
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
                                
                                TextField("Enter phone number", text: $viewModel.phone)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .keyboardType(.phonePad)
                                    .autocorrectionDisabled(true)
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
                                
                                AddressSearchField(address: $viewModel.address, placeholder: "Enter address")
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
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveSubClient) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                .scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                    }
                    .foregroundColor(viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                    .disabled(viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
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
                        viewModel.name = pendingImportData.name
                    }
                    if let emailVal = pendingImportData.email {
                        viewModel.email = emailVal
                    }
                    if let phoneVal = pendingImportData.phone {
                        viewModel.phone = phoneVal
                    }
                    if let addressVal = pendingImportData.address {
                        viewModel.address = addressVal
                    }
                    if let titleVal = pendingImportData.title {
                        viewModel.title = titleVal
                    }
                }
                Button("Merge (Keep Non-Empty)", role: .destructive) {
                    // Only replace empty fields
                    if viewModel.name.isEmpty && !pendingImportData.name.isEmpty {
                        viewModel.name = pendingImportData.name
                    }
                    if viewModel.email.isEmpty, let emailVal = pendingImportData.email {
                        viewModel.email = emailVal
                    }
                    if viewModel.phone.isEmpty, let phoneVal = pendingImportData.phone {
                        viewModel.phone = phoneVal
                    }
                    if viewModel.address.isEmpty, let addressVal = pendingImportData.address {
                        viewModel.address = addressVal
                    }
                    if viewModel.title.isEmpty, let titleVal = pendingImportData.title {
                        viewModel.title = titleVal
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
                // Load data when the sheet appears
                viewModel.loadFromSubClient(subClient)
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
                        let hasConflicts = (!viewModel.name.isEmpty && viewModel.name != importedName) ||
                                         (!viewModel.email.isEmpty && importedEmail != nil && viewModel.email != importedEmail) ||
                                         (!viewModel.phone.isEmpty && importedPhone != nil && viewModel.phone != importedPhone) ||
                                         (!viewModel.address.isEmpty && importedAddress != nil && viewModel.address != importedAddress) ||
                                         (!viewModel.title.isEmpty && importedTitle != nil && viewModel.title != importedTitle)
                        
                        if hasConflicts {
                            // Store pending data and show conflict dialog
                            pendingImportData = (importedName, importedEmail, importedPhone, importedAddress, importedTitle)
                            showingImportConflictDialog = true
                        } else {
                            // No conflicts, update fields
                            if !importedName.isEmpty {
                                viewModel.name = importedName
                            }
                            if let emailVal = importedEmail {
                                viewModel.email = emailVal
                            }
                            if let phoneVal = importedPhone {
                                viewModel.phone = phoneVal
                            }
                            if let addressVal = importedAddress {
                                viewModel.address = addressVal
                            }
                            if let titleVal = importedTitle {
                                viewModel.title = titleVal
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
    
    private func saveSubClient() {
        // Validate name
        let trimmedName = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required"
            showError = true
            return
        }
        
        // Extract phone digits only
        let cleanedPhone = viewModel.phone.isEmpty ? nil : viewModel.phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        isSaving = true
        
        Task {
            await onSave(
                trimmedName,
                viewModel.title.isEmpty ? nil : viewModel.title,
                viewModel.email.isEmpty ? nil : viewModel.email,
                cleanedPhone,
                viewModel.address.isEmpty ? nil : viewModel.address
            )
            
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
    
}