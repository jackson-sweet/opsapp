//
//  ContactDetailView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI
import MapKit

/// Detail view for displaying contact information for users, team members, and clients
struct ContactDetailView: View {
    // Can accept either a User, TeamMember, or Client
    let user: User?
    let teamMember: TeamMember?
    let client: Client?
    let project: Project? // Optional project reference for client updates
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var dataController: DataController
    
    @State private var showFullContact = false // For animating contact display
    @State private var showingClientEdit = false
    @State private var showingClientDeletion = false

    // Sub-client editing states
    @State private var subClientToEdit: SubClient? = nil  // Single state for both data and presentation
    @State private var subClientsRefreshKey = UUID()  // Force refresh of sub-clients view
    @State private var isParentContactExpanded = true  // Start expanded by default
    @State private var showingCreateContact = false  // For creating a contact from client data
    @State private var showingContactExportOptions = false  // For choosing export method
    @State private var showingAddToExistingContact = false  // For adding to existing contact
    @State private var showingImportConflictDialog = false  // For resolving import conflicts
    @State private var pendingImportData: (name: String, email: String?, phone: String?, address: String?) = ("", nil, nil, nil)
    @State private var selectedProject: Project? = nil  // For showing project details
    @State private var showingCreateProject = false  // For creating a new project
    @State private var isProjectListExpanded = false  // For expanding project list

    // Constants for styling
    private let avatarSize: CGFloat = 80
    private let contactIconSize: CGFloat = 36
    
    // Convenience initializers
    init(user: User) {
        self.user = user
        self.teamMember = nil
        self.client = nil
        self.project = nil
    }
    
    init(teamMember: TeamMember) {
        self.user = nil
        self.teamMember = teamMember
        self.client = nil
        self.project = nil
    }
    
    init(client: Client, project: Project? = nil) {
        self.user = nil
        self.teamMember = nil
        self.client = client
        self.project = project
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background - extend to cover entire sheet
                OPSStyle.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Fixed Navigation Bar at top
                    customNavigationBar
                        .padding(.top, 30) // Account for status bar
                        .background(OPSStyle.Colors.background)
                    
                    // Scrollable content
                    ScrollView {
                        VStack(spacing: 6) {
                            // Profile header with avatar
                            profileHeader
                                .padding(.top, 16)
                            
                            // Contact information - collapsible for clients with sub-clients
                            if isClient && client?.subClients.isEmpty == false {
                            // Collapsible parent client contact when sub-clients exist
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            isParentContactExpanded.toggle()
                                        }
                                    }) {
                                        HStack(spacing: 8) {
                                            Text("CONTACT INFORMATION")
                                                .font(OPSStyle.Typography.captionBold)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                            
                                            Image(systemName: isParentContactExpanded ? "chevron.up" : "chevron.down")
                                                .font(OPSStyle.Typography.smallBody)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Spacer()

                                    // Edit button only when expanded
                                    if isParentContactExpanded && canEditClient {
                                        Button(action: {
                                            showingClientEdit = true
                                        }) {
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
                                }
                                .padding(.horizontal)
                                
                                if isParentContactExpanded {
                                    VStack(spacing: 0) {
                                        contactSection
                                            .padding(.vertical, 14)
                                            .padding(.horizontal, 16)
                                        
                                        
                                        
                                        // Save and Share buttons inside the card
                                        saveShareButtons
                                            .padding(.horizontal, 16)
                                            .padding(.bottom, 20)
                                    }
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .padding(.horizontal)
                                    .transition(.asymmetric(
                                        insertion: .push(from: .top),
                                        removal: .push(from: .bottom)
                                    ))
                                }
                            }
                            .padding(.top, 8)
                        } else {
                            // Normal contact display for non-clients or clients without sub-clients - also collapsible
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Button(action: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            isParentContactExpanded.toggle()
                                        }
                                    }) {
                                        HStack(spacing: 8) {
                                            Text("CONTACT INFORMATION")
                                                .font(OPSStyle.Typography.captionBold)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                            
                                            Image(systemName: isParentContactExpanded ? "chevron.up" : "chevron.down")
                                                .font(OPSStyle.Typography.smallBody)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    Spacer()

                                    // Edit button only when expanded
                                    if isParentContactExpanded && isClient && canEditClient {
                                        Button(action: {
                                            showingClientEdit = true
                                        }) {
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
                                }
                                .padding(.horizontal)
                                
                                if isParentContactExpanded {
                                    VStack(spacing: 0) {
                                        contactSection
                                            .padding(.vertical, 14)
                                            .padding(.horizontal, 16)
                                        
                                        
                                        // Save and Share buttons inside the card
                                        saveShareButtons
                                            .padding(.horizontal, 16)
                                            .padding(.bottom, 20)
                                    }
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .padding(.horizontal)
                                    .transition(.asymmetric(
                                        insertion: .push(from: .top),
                                        removal: .push(from: .bottom)
                                    ))
                                }
                            }
                            .padding(.top, 8)
                        }
                        
                        // Role information with improved card styling
                        // Only show role section if not a client
                        if !isClient {
                            roleSection
                                .padding(.horizontal)
                                .padding(.top, 16)
                        }

                        // Sub-contacts section (for clients only) - positioned ABOVE projects
                        if isClient, let client = client {
                            SubClientListView(
                                client: client,
                                isEditing: false,
                                onEditSubClient: { subClient in
                                    subClientToEdit = subClient  // This will trigger the sheet
                                },
                                onCreateSubClient: {
                                    // Use a special marker SubClient with empty ID to indicate new creation
                                    let tempSubClient = SubClient(
                                        id: UUID().uuidString,  // Temporary ID
                                        name: ""  // Empty name indicates new subclient
                                    )
                                    subClientToEdit = tempSubClient
                                },
                                onDeleteSubClient: { subClient in
                                    deleteSubClient(subClient)
                                }
                            )
                            .padding(.horizontal)
                            .padding(.top, 16)
                            .id(subClientsRefreshKey)  // Force refresh when key changes
                        }

                        // Projects section
                        projectsSection
                            .padding(.horizontal)
                            .padding(.top, 16)

                        // Delete button at bottom (for clients only)
                        if isClient && canEditClient {
                            Button(action: {
                                showingClientDeletion = true
                            }) {
                                Text("Delete Client")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.errorStatus, lineWidth: 1.5)
                                    )
                            }
                            .padding(.horizontal)
                            .padding(.top, 32)
                            .padding(.bottom, 32)
                        }

                            // Spacer for bottom padding
                            Spacer(minLength: 100) // Extra space for bottom buttons
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                // Animate contact info appearing
                withAnimation(.easeInOut.delay(0.3)) {
                    showFullContact = true
                }
            }
        }
        .sheet(item: $subClientToEdit) { subClientToEdit in
            if let client = client {
                SubClientEditSheet(
                    client: client,
                    subClient: subClientToEdit.name.isEmpty ? nil : subClientToEdit,  // Check if it's a new subclient
                    onSave: { name, title, email, phone, address in
                        await saveSubClient(name: name, title: title, email: email, phone: phone, address: address)
                    }
                )
            }
        }
        .sheet(isPresented: $showingClientEdit) {
            if let client = client {
                ClientEditSheet(
                    client: client,
                    onSave: { name, email, phone, address in
                        await saveClientChanges(name: name, email: email, phone: phone, address: address)
                    },
                    isPresented: $showingClientEdit
                )
            }
        }
        .sheet(isPresented: $showingCreateContact) {
            // For now, this only handles the main client
            // Sub-clients are handled separately
            ContactCreatorView(
                name: fullName,
                email: email,
                phone: phone,
                address: address,
                jobTitle: "Client",  // Main clients are always marked as "Client"
                organization: nil     // No company for main clients
            )
        }
        .sheet(isPresented: $showingAddToExistingContact) {
            ContactUpdater(
                name: fullName,
                email: email,
                phone: phone,
                address: address,
                jobTitle: "Client",
                organization: nil,
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
        .alert("Import Conflicts Found", isPresented: $showingImportConflictDialog) {
            Button("Keep Current Data") {
                // Do nothing, keep existing data
            }
            Button("Replace with Imported") {
                // Replace with imported data - functionality removed since we're using sheet editing
            }
            Button("Merge (Keep Non-Empty)", role: .destructive) {
                // Merge - functionality removed since we're using sheet editing
            }
        } message: {
            Text("Some fields already have data. How would you like to handle the imported information?")
        }
        .sheet(item: $selectedProject) { project in
            NavigationView {
                ProjectDetailsView(project: project)
            }
        }
        .sheet(isPresented: $showingCreateProject) {
            if let client = client {
                ProjectFormSheet(mode: .create, preselectedClient: client) { newProject in
                    // Project created successfully - the list will refresh automatically
                }
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingClientDeletion) {
            if let client = client {
                ClientDeletionSheet(client: client)
                    .onDisappear {
                        if let modelContext = dataController.modelContext,
                           modelContext.model(for: client.id) == nil {
                            dismiss()
                        }
                    }
            }
        }
    }
    
    // MARK: - Custom Navigation Bar
    
    private var customNavigationBar: some View {
        HStack {
            // Back button
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            
            Spacer()
            
            // Title
            Text(isClient ? "CLIENT" : "TEAM MEMBER")
                .font(OPSStyle.Typography.title)
                .foregroundColor(.white)
            
            Spacer()

            // Empty space to balance the layout
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        HStack(spacing: 36) {
            // Profile image - using unified UserAvatar component
            Group {
                if let user = user {
                    UserAvatar(user: user, size: avatarSize)
                } else if let teamMember = teamMember {
                    UserAvatar(teamMember: teamMember, size: avatarSize)
                } else if let client = client {
                    UserAvatar(client: client, size: avatarSize)
                } else {
                    UserAvatar(firstName: "", lastName: "", size: avatarSize)
                }
            }
            .overlay(
                Circle()
                    .stroke(OPSStyle.Colors.primaryText, lineWidth: 3)
            )
            
            // Name and role on one row
            VStack(alignment: .leading, spacing: 8) {
                Text(fullName.uppercased())
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(role)
                    .font(OPSStyle.Typography.cardSubtitle)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 32)
    }
    
    // MARK: - Contact Buttons
    
    private var contactButtons: some View {
        HStack(spacing: 20) {
            // Call Button
            if let phone = self.phone, !phone.isEmpty {
                Button(action: {
                    let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    if let phoneURL = URL(string: "tel:\(cleaned)") {
                        openURL(phoneURL)
                    }
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: "phone")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        
                        Text("Call")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(width: 65, height: 65)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                    )
                }
            }
            
            // Message Button
            if let phone = self.phone, !phone.isEmpty {
                Button(action: {
                    let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    if let smsURL = URL(string: "sms:\(cleaned)") {
                        openURL(smsURL)
                    }
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: "message")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        
                        Text("Message")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(width: 65, height: 65)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                    )
                }
            }
            
            // Email Button
            if let email = self.email, !email.isEmpty {
                Button(action: {
                    if let emailURL = URL(string: "mailto:\(email)") {
                        openURL(emailURL)
                    }
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: "envelope")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        
                        Text("Email")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(width: 65, height: 65)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                    )
                }
            }
            
        }
        .padding(.vertical, 4)
        .opacity(showFullContact ? 1 : 0)
        .offset(y: showFullContact ? 0 : 20)
        .animation(.easeInOut(duration: 0.4), value: showFullContact)
    }
    
    // MARK: - Contact Section
    
    private var contactSection: some View {
        VStack(spacing: 20) {
                
                // Email
                if let email = self.email, !email.isEmpty {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(OPSStyle.Colors.cardBackground)
                                .frame(width: contactIconSize, height: contactIconSize)
                            
                            Image(systemName: "envelope")
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
                                .textSelection(.enabled)  // Allow text selection for copy
                        }
                        
                        Spacer()
                        
                        // Email button
                        Button(action: {
                            if let emailURL = URL(string: "mailto:\(email)") {
                                openURL(emailURL)
                            }
                        }) {
                            Image(systemName: "envelope.fill")
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
                } else {
                    // No email available
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(OPSStyle.Colors.cardBackground)
                                .frame(width: contactIconSize, height: contactIconSize)
                            
                            Image(systemName: "envelope")
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
                }
                
                // Phone
                if let phone = self.phone, !phone.isEmpty {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(OPSStyle.Colors.cardBackground)
                                .frame(width: contactIconSize, height: contactIconSize)
                            
                            Image(systemName: "phone")
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
                                .textSelection(.enabled)  // Allow text selection for copy
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            // Call button
                            Button(action: {
                                let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                                if let phoneURL = URL(string: "tel:\(cleaned)") {
                                    openURL(phoneURL)
                                }
                            }) {
                                Image(systemName: "phone.fill")
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
                            Button(action: {
                                let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                                if let smsURL = URL(string: "sms:\(cleaned)") {
                                    openURL(smsURL)
                                }
                            }) {
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
                } else {
                    // No phone available
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(OPSStyle.Colors.cardBackground)
                                .frame(width: contactIconSize, height: contactIconSize)
                            
                            Image(systemName: "phone")
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
                }
                
                // Address (for clients only)
                if isClient {
                    if let address = self.address, !address.isEmpty {
                        Button(action: {
                            // Open address in Maps
                            let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let mapsURL = URL(string: "maps://?q=\(encodedAddress)") {
                                openURL(mapsURL)
                            }
                        }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(OPSStyle.Colors.cardBackground)
                                        .frame(width: contactIconSize, height: contactIconSize)
                                    
                                    Image(systemName: "location")
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
                                        .lineLimit(2)
                                        .textSelection(.enabled)  // Allow text selection for copy
                                }
                                
                                Spacer()
                                
                                // Map button
                                Button(action: {
                                    let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                    if let mapsURL = URL(string: "maps://?q=\(encodedAddress)") {
                                        openURL(mapsURL)
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
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // No address available
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                                    .frame(width: contactIconSize, height: contactIconSize)
                                
                                Image(systemName: "location.slash")
                                    .font(OPSStyle.Typography.smallBody)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Address")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text("No address available")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .italic()
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
        }
    
    // MARK: - Save and Share Buttons
    
    private var saveShareButtons: some View {
        Group {
            if isClient {
                if let client = client {
                    HStack(spacing: 12) {
                        // Save to Contacts button
                        Button(action: {
                            showingContactExportOptions = true
                        }) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(OPSStyle.Typography.body)
                                Text("Save to Contacts")
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
                            var shareText = "Contact: \(client.name)\n"
                            if let email = client.email {
                                shareText += "Email: \(email)\n"
                            }
                            if let phone = client.phoneNumber {
                                shareText += "Phone: \(formatPhoneNumber(phone))\n"
                            }
                            if let address = client.address {
                                shareText += "Address: \(address)\n"
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
                    .padding(.top, 16)
                }
            }
        }
    }
    
    // MARK: - Projects Section

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Get relevant projects
            let projects = relevantProjects

            // Section title with count and add button
            HStack {
                Text("PROJECTS (\(projects.count))")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                // Add Project button - only for clients with admin/office permissions
                if isClient && canEditClient {
                    Button(action: {
                        showingCreateProject = true
                    }) {
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
            .padding(.bottom, 4)

            if !projects.isEmpty {

                // Projects list card
                VStack(spacing: 0) {
                    ForEach(Array((isProjectListExpanded ? projects : Array(projects.prefix(5))).enumerated()), id: \.element.id) { index, project in
                        Button(action: {
                            // Set selected project to show details
                            selectedProject = project
                        }) {
                            HStack {
                                // Status indicator
                                Circle()
                                    .fill(project.status.color)
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.title)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .lineLimit(1)

                                    if let startDate = project.startDate {
                                        Text(DateFormatter.localizedString(from: startDate, dateStyle: .short, timeStyle: .none))
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                }

                                Spacer()

                                // Status badge
                                Text(project.status.displayName.uppercased())
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(project.status.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(project.status.color.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(project.status.color.opacity(0.3), lineWidth: 1)
                                    )

                                // Chevron
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        let displayedProjects = isProjectListExpanded ? projects : Array(projects.prefix(5))
                        if index < displayedProjects.count - 1 {
                            Divider()
                                .background(OPSStyle.Colors.secondaryText.opacity(0.2))
                        }
                    }

                    // Show more/less button if there are more than 5 projects
                    if projects.count > 5 {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isProjectListExpanded.toggle()
                            }
                        }) {
                            HStack {
                                Spacer()
                                Text(isProjectListExpanded ? "SHOW LESS" : "+ \(projects.count - 5) MORE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .opacity(showFullContact ? 1 : 0)
                .offset(y: showFullContact ? 0 : 20)
                .animation(.easeInOut(duration: 0.5).delay(0.3), value: showFullContact)
            } else if isClient && canEditClient {
                // Empty state for clients with no projects (admin/office only)
                Button(action: {
                    showingCreateProject = true
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        VStack(spacing: 4) {
                            Text("No projects yet")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Text("Create one?")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                .buttonStyle(PlainButtonStyle())
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .opacity(showFullContact ? 1 : 0)
                .offset(y: showFullContact ? 0 : 20)
                .animation(.easeInOut(duration: 0.5).delay(0.3), value: showFullContact)
            }
        }
    }

    // MARK: - Role Section

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title
            Text("ROLE INFORMATION")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.bottom, 4)
            
            // Role info card with improved styling
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.cardBackground)
                        .frame(width: contactIconSize, height: contactIconSize)
                    
                    Image(systemName: isClient ? "building.2" : "person.badge.shield.checkmark")
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isClient ? "Type" : "Employee Type")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(role)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .opacity(showFullContact ? 1 : 0)
            .offset(y: showFullContact ? 0 : 20)
            .animation(.easeInOut(duration: 0.5).delay(0.2), value: showFullContact)
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Helper Computed Properties
    
    private var isClient: Bool {
        // Check if we have a client object or if the role indicates this is a client
        if client != nil {
            return true
        }
        if let teamMember = teamMember {
            return teamMember.role.lowercased() == "client"
        }
        return false
    }
    
    private var canEditClient: Bool {
        // Only office crew and admin can edit client info
        guard let currentUser = dataController.currentUser else { return false }
        return currentUser.role == UserRole.admin || currentUser.role == UserRole.officeCrew
    }
    
    private var fullName: String {
        if let user = user {
            return "\(user.firstName) \(user.lastName)"
        } else if let teamMember = teamMember {
            return teamMember.fullName
        } else if let client = client {
            return client.name
        } else {
            return "Unknown User"
        }
    }
    
    private var initials: String {
        if let user = user {
            let firstInitial = user.firstName.first?.uppercased() ?? ""
            let lastInitial = user.lastName.first?.uppercased() ?? ""
            return "\(firstInitial)\(lastInitial)"
        } else if let teamMember = teamMember {
            return teamMember.initials
        } else if let client = client {
            let names = client.name.components(separatedBy: " ")
            let firstInitial = names.first?.first?.uppercased() ?? ""
            let lastInitial = names.last?.first?.uppercased() ?? ""
            return "\(firstInitial)\(lastInitial)"
        } else {
            return "??"
        }
    }
    
    private var role: String {
        if let user = user {
            return user.role.displayName
        } else if let teamMember = teamMember {
            return teamMember.role
        } else if client != nil {
            return "Client"
        } else {
            return "Unknown Role"
        }
    }
    
    private var email: String? {
        if let user = user {
            return user.email
        } else if let teamMember = teamMember {
            return teamMember.email
        } else if let client = client {
            return client.email
        } else {
            return nil
        }
    }
    
    private var address: String? {
        if let client = client {
            return client.address
        }
        return nil
    }
    
    private var phone: String? {
        if let user = user {
            return user.phone
        } else if let teamMember = teamMember {
            return teamMember.phone
        } else if let client = client {
            return client.phoneNumber
        } else {
            return nil
        }
    }

    private var relevantProjects: [Project] {
        if let client = client {
            // For clients, show their projects
            return Array(client.projects).sorted {
                ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast)
            }
        } else if let user = user {
            // For team members, show projects they're assigned to
            return dataController.getAllProjects().filter { project in
                project.teamMembers.contains(where: { $0.id == user.id })
            }.sorted {
                ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast)
            }
        } else if let teamMember = teamMember {
            // For legacy team members (without User object), check by ID
            return dataController.getAllProjects().filter { project in
                project.getTeamMemberIds().contains(teamMember.id)
            }.sorted {
                ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast)
            }
        } else {
            return []
        }
    }
    
    // MARK: - Helper Methods
    
    private func saveClientChanges(name: String, email: String?, phone: String?, address: String?) async {
        guard let client = client else { return }
        
        do {
            // Call the API to update client
            guard let syncManager = dataController.syncManager else {
                return
            }
            
            // Extract only digits from phone number
            let cleanedPhone: String?
            if let phone = phone, !phone.isEmpty {
                let digitsOnly = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                cleanedPhone = digitsOnly.isEmpty ? nil : digitsOnly
            } else {
                cleanedPhone = nil
            }
            
            // Update the client via API (client is updated in place)
            try await syncManager.updateClientContact(
                clientId: client.id,
                name: name,
                email: email,
                phone: cleanedPhone,
                address: address
            )

            // Client object is already updated by the sync manager
            // No need to manually update UI as client is passed by reference
            
        } catch {
        }
    }
    
    private func saveSubClient(name: String, title: String?, email: String?, phone: String?, address: String?) async {
        guard let client = client else { return }
        guard let syncManager = dataController.syncManager else { 
            return 
        }
        
        do {
            if let editingSubClient = subClientToEdit, !editingSubClient.name.isEmpty {
                // Edit existing sub-client (updates local model automatically)
                try await syncManager.editSubClient(
                    subClientId: editingSubClient.id,
                    name: name,
                    title: title,
                    email: email,
                    phone: phone,
                    address: address
                )

                // Refresh UI
                await MainActor.run {
                    // Force refresh of the sub-clients view
                    subClientsRefreshKey = UUID()
                    // Clear the editing state
                    subClientToEdit = nil
                }
                
            } else {
                // Create new sub-client - try API first, fall back to local if offline/error
                let newSubClient: SubClient
                var syncSucceeded = false

                do {
                    // createSubClient now returns SubClient model directly, not DTO
                    newSubClient = try await syncManager.createSubClient(
                        clientId: client.id,
                        name: name,
                        title: title,
                        email: email,
                        phone: phone,
                        address: address
                    )

                    syncSucceeded = true
                    print("✅ Sub-client created on server successfully")
                } catch {
                    print("⚠️ Failed to create sub-client on server: \(error)")
                    print("📱 Creating sub-client locally and queuing for sync")

                    // Create locally with temporary ID
                    newSubClient = SubClient(
                        id: UUID().uuidString,
                        name: name
                    )
                    newSubClient.title = title
                    newSubClient.email = email
                    newSubClient.phoneNumber = phone
                    newSubClient.address = address
                    newSubClient.needsSync = true  // Mark for sync
                }

                // Set the parent relationship
                newSubClient.client = client

                // Add the new sub-client to the client's array
                await MainActor.run {
                    client.subClients.append(newSubClient)

                    // Force the client to update by modifying a property
                    client.lastSyncedAt = Date()

                    // Force refresh of the sub-clients view
                    subClientsRefreshKey = UUID()
                    // Clear the editing state
                    subClientToEdit = nil
                }

                // Save to SwiftData context
                let modelContext = syncManager.modelContext
                modelContext.insert(newSubClient)
                try modelContext.save()

                // If sync succeeded, refresh client
                if syncSucceeded {
                    await MainActor.run {
                        client.lastSyncedAt = nil
                    }
                    try? await syncManager.refreshSingleClient(clientId: client.id)
                }
            }
            
        } catch {
        }
    }
    
    private func deleteSubClient(_ subClient: SubClient) {
        Task {
            do {
                // Call the API to delete the sub-client
                try await dataController.syncManager.deleteSubClient(subClientId: subClient.id)
                
                // Remove from parent client's array
                await MainActor.run {
                    if let index = client?.subClients.firstIndex(where: { $0.id == subClient.id }) {
                        client?.subClients.remove(at: index)
                    }
                    
                    // Force refresh of the sub-clients view
                    subClientsRefreshKey = UUID()
                }
                
                // Delete from SwiftData context
                let modelContext = dataController.syncManager.modelContext
                modelContext.delete(subClient)
                try modelContext.save()
                
            } catch {
            }
        }
    }
    
    /// Format phone number for display (US format)
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
            let areaCode = cleaned.dropFirst().prefix(3)
            let prefix = cleaned.dropFirst(4).prefix(3)
            let number = cleaned.dropFirst(7)
            return "+\(countryCode) (\(areaCode)) \(prefix)-\(number)"
        }
        
        // If not a standard format, return as is with some basic formatting
        return phoneNumber
    }
    
}

// MARK: - Preview

struct ContactDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let user = User(id: "123", firstName: "John", lastName: "Doe", role: .fieldCrew, companyId: "company123")
        user.email = "john.doe@example.com"
        user.phone = "555-123-4567"
        
        let teamMember = TeamMember(
            id: "456",
            firstName: "Jane",
            lastName: "Smith",
            role: "Office Crew",
            avatarURL: nil,
            email: "jane.smith@example.com",
            phone: "555-987-6543"
        )
        
        // Create a mock DataController for preview
        let dataController = DataController()
        
        return Group {
            ContactDetailView(user: user)
                .environmentObject(dataController)
                .preferredColorScheme(.dark)
            
            ContactDetailView(teamMember: teamMember)
                .environmentObject(dataController)
                .preferredColorScheme(.dark)
        }
    }
}
