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
                    VStack(spacing: 24) {
                        // Contact Preview Card
                        subClientPreviewCard
                            .padding(.horizontal)
                            .padding(.top, 16)

                        // Contact Details Section
                        SectionCard(
                            icon: "person.text.rectangle",
                            title: "Contact Details"
                        ) {
                            VStack(spacing: 16) {
                                // Name field (required)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("NAME *")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    TextField("Enter name", text: $viewModel.name)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .autocorrectionDisabled(true)
                                        .textInputAutocapitalization(.words)
                                        .padding(12)
                                        .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .focused($focusedField, equals: .name)
                                }

                                // Title field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("TITLE")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    TextField("Enter title", text: $viewModel.title)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .autocorrectionDisabled(true)
                                        .textInputAutocapitalization(.words)
                                        .padding(12)
                                        .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .focused($focusedField, equals: .title)
                                }

                                // Email field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("EMAIL")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    TextField("Enter email", text: $viewModel.email)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled(true)
                                        .padding(12)
                                        .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .focused($focusedField, equals: .email)
                                }

                                // Phone field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("PHONE")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    TextField("Enter phone number", text: $viewModel.phone)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .keyboardType(.phonePad)
                                        .autocorrectionDisabled(true)
                                        .padding(12)
                                        .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .focused($focusedField, equals: .phone)
                                }

                                // Address field with autocomplete
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ADDRESS")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    AddressSearchField(address: $viewModel.address, placeholder: "Enter address")
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Import from Contacts button at bottom
                        Button(action: {
                            showingContactPicker = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: OPSStyle.Icons.addContact)
                                    .font(.system(size: 18))
                                Text("Import from Contacts")
                                    .font(OPSStyle.Typography.button)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                            )
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .standardSheetToolbar(
                title: isCreating ? "New Sub Contact" : "Edit Sub Contact",
                actionText: "Save",
                actionColor: OPSStyle.Colors.primaryAccent,
                isActionEnabled: !viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                isSaving: isSaving,
                onCancel: { dismiss() },
                onAction: saveSubClient
            )
            .loadingOverlay(isPresented: $isSaving, message: "Saving...")
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

    // MARK: - View Components

    private var subClientPreviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    // Name
                    Text(viewModel.name.isEmpty ? "SUB CONTACT NAME" : viewModel.name.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(viewModel.name.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    // Email or Phone
                    if !viewModel.email.isEmpty {
                        Text(viewModel.email)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    } else if !viewModel.phone.isEmpty {
                        Text(viewModel.phone)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    } else {
                        Text("NO CONTACT INFO")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }

                    // Address or Title
                    if !viewModel.address.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle")
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(viewModel.address.components(separatedBy: ",").first ?? viewModel.address)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    } else if !viewModel.title.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "briefcase")
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(viewModel.title)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    } else {
                        Text("NO TITLE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                Spacer()

                // Placeholder avatar on right side (56x56)
                Circle()
                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(viewModel.name.isEmpty ? "?" : String(viewModel.name.prefix(1)).uppercased())
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    )
                    .overlay(
                        Circle()
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 2)
                    )
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.7))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
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
                // Success haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                isSaving = false

                // Brief delay for graceful dismissal
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            }
        }
    }
    
}