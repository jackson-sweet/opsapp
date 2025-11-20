//
//  SubClientListView.swift
//  OPS
//
//  Expandable list view for displaying and editing sub-clients
//

import SwiftUI
import MapKit

struct SubClientListView: View {
    let client: Client
    let isEditing: Bool
    let onEditSubClient: (SubClient) -> Void
    let onCreateSubClient: () -> Void
    let onDeleteSubClient: (SubClient) -> Void
    
    @State private var expandedSubClientId: String? = nil
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var dataController: DataController
    
    // Check if current user can add sub-contacts (admin or office crew only)
    private var canAddSubContacts: Bool {
        guard let currentUser = dataController.currentUser else { return false }
        return currentUser.role == .admin || currentUser.role == .officeCrew
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with count and add button
            HStack {
                Text("SUB CONTACTS (\(client.subClients.count))")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                if canAddSubContacts {
                    Button(action: onCreateSubClient) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(OPSStyle.Typography.smallCaption)
                            Text("Add")
                                .font(OPSStyle.Typography.smallCaption)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                    }
                }
            }

            // Sub-client list or empty state
            if client.subClients.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: OPSStyle.Icons.subClient)
                        .font(.system(size: 32))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Text("No sub-contacts yet")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
            } else {
                // Sub-client list
                VStack(spacing: 8) {
                    ForEach(client.subClients, id: \.id) { subClient in
                        SubClientRow(
                            subClient: subClient,
                            isExpanded: expandedSubClientId == subClient.id,
                            isEditing: isEditing,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    if expandedSubClientId == subClient.id {
                                        expandedSubClientId = nil
                                    } else {
                                        expandedSubClientId = subClient.id
                                    }
                                }
                            },
                            onEdit: {
                                onEditSubClient(subClient)
                            },
                            onDelete: {
                                onDeleteSubClient(subClient)
                            },
                            onCall: {
                                if let phone = subClient.phoneNumber {
                                    let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                                    if let phoneURL = URL(string: "tel:\(cleaned)") {
                                        openURL(phoneURL)
                                    }
                                }
                            },
                            onMessage: {
                                if let phone = subClient.phoneNumber {
                                    let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                                    if let smsURL = URL(string: "sms:\(cleaned)") {
                                        openURL(smsURL)
                                    }
                                }
                            },
                            onEmail: {
                                if let email = subClient.email {
                                    if let emailURL = URL(string: "mailto:\(email)") {
                                        openURL(emailURL)
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isEditing)
    }
}

// MARK: - Sub-Client Row Component
struct SubClientRow: View {
    let subClient: SubClient
    let isExpanded: Bool
    let isEditing: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCall: () -> Void
    let onMessage: () -> Void
    let onEmail: () -> Void
    
    @State private var showingCreateContact = false
    @State private var showingContactExportOptions = false
    @State private var showingAddToExistingContact = false
    @State private var showingDeleteConfirmation = false
    @EnvironmentObject private var dataController: DataController
    
    // Check if current user can edit sub-contacts (admin or office crew only)
    private var canEditSubContacts: Bool {
        guard let currentUser = dataController.currentUser else { return false }
        return currentUser.role == .admin || currentUser.role == .officeCrew
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row - always visible
            HStack(spacing: 12) {
                // Avatar with initials
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.2))
                        .frame(width: 36, height: 36)
                    
                    Text(subClient.initials)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                // Name and title
                VStack(alignment: .leading, spacing: 2) {
                    Text(subClient.name)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    if let title = subClient.title, !title.isEmpty {
                        Text(title)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Spacer()
                
                // Contact availability icons
                HStack(spacing: 8) {
                    if subClient.phoneNumber != nil {
                        Image(systemName: OPSStyle.Icons.phone)
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Image(systemName: OPSStyle.Icons.phone)
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.3))
                    }

                    if subClient.email != nil {
                        Image(systemName: OPSStyle.Icons.envelope)
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Image(systemName: OPSStyle.Icons.envelope)
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.3))
                    }
                }
                
                // Edit button when expanded (only for admin/office crew, not in parent edit mode)
                if isExpanded && !isEditing && canEditSubContacts {
                    Button(action: onEdit) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(OPSStyle.Typography.smallCaption)
                            Text("Edit")
                                .font(OPSStyle.Typography.smallCaption)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Expand/collapse chevron (only show if not editing or not expanded)
                if !isExpanded || isEditing {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .animation(.easeInOut(duration: 0.3), value: isExpanded)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .contentShape(Rectangle())
            .onTapGesture {
                if !isEditing {
                    onTap()
                }
            }
            
            // Expanded content - match parent contact layout
            if isExpanded {
                VStack(alignment: .leading, spacing: 20) {
                    // Email row
                    if let email = subClient.email, !email.isEmpty {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: OPSStyle.Icons.envelope)
                                    .font(OPSStyle.Typography.smallBody)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Email")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text(email)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .textSelection(.enabled)  // Allow text selection for copy/paste
                            }
                            
                            Spacer()
                            
                            // Email button
                            Button(action: onEmail) {
                                Image(systemName: OPSStyle.Icons.envelopeFill)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(Color.white, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        // No email available
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: OPSStyle.Icons.envelope)
                                    .font(OPSStyle.Typography.smallBody)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Email")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text("No email available")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .italic()
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Phone row
                    if let phone = subClient.phoneNumber, !phone.isEmpty {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: OPSStyle.Icons.phone)
                                    .font(OPSStyle.Typography.smallBody)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Phone")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text(formatPhoneNumber(phone))
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .textSelection(.enabled)  // Allow text selection for copy/paste
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                // Call button
                                Button(action: onCall) {
                                    Image(systemName: OPSStyle.Icons.phoneFill)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(Color.white, lineWidth: 1)
                                        )
                                }
                                
                                // Message button
                                Button(action: onMessage) {
                                    Image(systemName: "message.fill")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(Color.white, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        // No phone available
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: OPSStyle.Icons.phone)
                                    .font(OPSStyle.Typography.smallBody)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Phone")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text("No phone available")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .italic()
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Address row (if available)
                    if let address = subClient.address, !address.isEmpty {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: OPSStyle.Icons.address)
                                    .font(OPSStyle.Typography.smallBody)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Address")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text(address)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .textSelection(.enabled)  // Allow text selection for copy/paste
                                    .multilineTextAlignment(.leading)
                            }
                            
                            Spacer()
                            
                            // Map button
                            Button(action: {
                                let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                if let mapsURL = URL(string: "maps://?q=\(encodedAddress)") {
                                    UIApplication.shared.open(mapsURL)
                                }
                            }) {
                                Image(systemName: "map.fill")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(Color.white, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    
                    HStack(spacing: 12) {
                        // Save to Contacts button
                        Button(action: {
                            showingContactExportOptions = true
                        }) {
                            HStack {
                                Image(systemName: OPSStyle.Icons.addContact)
                                    .font(OPSStyle.Typography.body)
                                Text("Save \(subClient.name)")
                                    .font(OPSStyle.Typography.button)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1.5)
                            )
                        }
                        
                        // Share Contact button
                        Button(action: {
                            // Create contact info to share
                            var shareText = "Contact: \(subClient.name)\n"
                            if let title = subClient.title {
                                shareText += "Title: \(title)\n"
                            }
                            if let email = subClient.email {
                                shareText += "Email: \(email)\n"
                            }
                            if let phone = subClient.phoneNumber {
                                shareText += "Phone: \(phone)\n"
                            }
                            if let address = subClient.address {
                                shareText += "Address: \(address)\n"
                            }
                            if let clientName = subClient.client?.name {
                                shareText += "Company: \(clientName)\n"
                            }
                            
                            let activityVC = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                            
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let window = windowScene.windows.first {
                                var topController = window.rootViewController
                                while let presented = topController?.presentedViewController {
                                    topController = presented
                                }
                                topController?.present(activityVC, animated: true)
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(OPSStyle.Typography.body)
                                Text("Share")
                                    .font(OPSStyle.Typography.smallCaption)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(width: 80, height: 50)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1.5)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 20)
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
        .sheet(isPresented: $showingCreateContact) {
            ContactCreatorView(
                name: subClient.name,
                email: subClient.email,
                phone: subClient.phoneNumber,
                address: subClient.address,
                jobTitle: subClient.title,  // Sub-client's title goes to job title
                organization: subClient.client?.name  // Parent client name goes to company
            )
        }
        .sheet(isPresented: $showingAddToExistingContact) {
            ContactUpdater(
                name: subClient.name,
                email: subClient.email,
                phone: subClient.phoneNumber,
                address: subClient.address,
                jobTitle: subClient.title,
                organization: subClient.client?.name,
                onDismiss: {
                    showingAddToExistingContact = false
                }
            )
        }
        .confirmationDialog("Save Contact", isPresented: $showingContactExportOptions) {
            Button("Create New Contact") {
                showingCreateContact = true
            }
            Button("Add to Existing Contact") {
                showingAddToExistingContact = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("How would you like to save this contact information?")
        }
        .alert("Delete Sub-Contact", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \(subClient.name)? This action cannot be undone.")
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        let cleaned = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        // Format based on length
        if cleaned.count == 10 {
            let areaCode = cleaned.prefix(3)
            let prefix = cleaned.dropFirst(3).prefix(3)
            let number = cleaned.dropFirst(6)
            return "(\(areaCode)) \(prefix)-\(number)"
        } else if cleaned.count == 11 && cleaned.first == "1" {
            let countryCode = cleaned.prefix(1)
            let areaCode = cleaned.dropFirst(1).prefix(3)
            let prefix = cleaned.dropFirst(4).prefix(3)
            let number = cleaned.dropFirst(7)
            return "\(countryCode) (\(areaCode)) \(prefix)-\(number)"
        } else if cleaned.count == 7 {
            let prefix = cleaned.prefix(3)
            let number = cleaned.dropFirst(3)
            return "\(prefix)-\(number)"
        } else {
            // Return original if it doesn't match expected formats
            return phoneNumber
        }
    }
}
