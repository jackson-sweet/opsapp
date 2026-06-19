//
//  ContactDetailView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI
import SwiftData
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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Query private var allClients: [Client]

    @State private var showFullContact = false // For animating contact display
    @State private var showingClientEdit = false
    @State private var showingClientDeletion = false

    // Bug c0ed9969 — long-press any client-contact field to edit it
    // inline without opening the full ClientSheet editor. Gated below
    // on `isClient && canEditClient` so crew without edit-client
    // permission never see the affordance.
    @State private var inlineEditField: InlineEditField? = nil
    @State private var inlineEditValue: String = ""
    @State private var inlineEditSaving = false
    @FocusState private var inlineEditFocused: Bool

    // Sub-client editing states
    @State private var subClientToEdit: SubClient? = nil  // Single state for both data and presentation
    @State private var subClientsRefreshKey = UUID()  // Force refresh of sub-clients view
    @State private var expandedSubClientId: String? = nil  // Track which sub-client row is expanded
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

    /// Identifies which contact-section field the operator is editing
    /// inline (bug c0ed9969). Email / phone / address only — name is
    /// edited from the header avatar card via the existing ClientSheet.
    private enum InlineEditField: String, Identifiable {
        case email, phone, address, notes
        var id: String { rawValue }
    }
    
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
                        VStack(spacing: OPSStyle.Layout.spacing3) {
                            // Contact preview card (replaces profile header)
                            contactPreviewCard
                                .padding(.horizontal)
                                .padding(.top, OPSStyle.Layout.spacing3)
                            
                            // Contact information section
                            SectionCard(
                                icon: "person.text.rectangle",
                                title: "Contact Information",
                                actionIcon: (isClient && canEditClient) ? "pencil.circle" : nil,
                                actionLabel: (isClient && canEditClient) ? "Edit" : nil,
                                onAction: (isClient && canEditClient) ? { showingClientEdit = true } : nil
                            ) {
                                VStack(spacing: OPSStyle.Layout.spacing3) {
                                    contactSection

                                    // Save and Share buttons inside the card
                                    saveShareButtons
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, OPSStyle.Layout.spacing2)

                        // Role information with improved card styling
                        // Only show role section if not a client
                        if !isClient {
                            roleSection
                                .padding(.horizontal)
                                .padding(.top, OPSStyle.Layout.spacing3)
                        }

                        // Sub-contacts section (for clients only) - positioned ABOVE projects
                        if isClient, let client = client {
                            SectionCard(
                                icon: "person.2.fill",
                                title: "Sub Contacts (\(client.subClients.count))",
                                actionIcon: canEditClient ? OPSStyle.Icons.plus : nil,
                                actionLabel: canEditClient ? "Add" : nil,
                                onAction: canEditClient ? {
                                    // Create new sub-client
                                    let tempSubClient = SubClient(
                                        id: UUID().uuidString,
                                        name: ""
                                    )
                                    subClientToEdit = tempSubClient
                                } : nil
                            ) {
                                VStack(spacing: OPSStyle.Layout.spacing3) {
                                    // Sub-client list or empty state
                                    if client.subClients.isEmpty {
                                        // Empty state
                                        VStack(spacing: OPSStyle.Layout.spacing2_5) {
                                            Image(systemName: OPSStyle.Icons.subClient)
                                                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                                            Text("No sub-contacts yet")
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, OPSStyle.Layout.spacing5)
                                        .nestedCard()
                                    } else {
                                        // Sub-client rows
                                        VStack(spacing: OPSStyle.Layout.spacing2) {
                                            ForEach(client.subClients, id: \.id) { subClient in
                                                SubClientRow(
                                                    subClient: subClient,
                                                    isExpanded: expandedSubClientId == subClient.id,
                                                    isEditing: false,
                                                    onTap: {
                                                        withAnimation(OPSStyle.Animation.standard) {
                                                            if expandedSubClientId == subClient.id {
                                                                expandedSubClientId = nil
                                                            } else {
                                                                expandedSubClientId = subClient.id
                                                            }
                                                        }
                                                    },
                                                    onEdit: {
                                                        subClientToEdit = subClient
                                                    },
                                                    onDelete: {
                                                        deleteSubClient(subClient)
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
                                .id(subClientsRefreshKey)
                            }
                            .padding(.horizontal)
                            .padding(.top, OPSStyle.Layout.spacing3)
                        }

                        // Projects section
                        projectsSection
                            .padding(.horizontal)
                            .padding(.top, OPSStyle.Layout.spacing3)

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
                                            .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.standard)
                                    )
                            }
                            .padding(.horizontal)
                            .padding(.top, OPSStyle.Layout.spacing5)
                            .padding(.bottom, OPSStyle.Layout.spacing5)
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
                ClientSheet(mode: .edit(client)) { _ in
                    // Client is already updated by ClientSheet
                    showingClientEdit = false
                }
                .environmentObject(dataController)
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
            .interactiveDismissDisabled(true)
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
                DeletionSheet(
                    item: client,
                    itemType: "Client",
                    childItems: client.activeProjects.sorted { $0.title < $1.title },
                    childType: "Project",
                    availableReassignments: allClients,
                    getItemDisplay: { client in
                        AnyView(
                            Text(client.name)
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        )
                    },
                    filterAvailableItems: { clients in
                        clients.filter {
                            $0.id != client.id &&
                            !$0.id.contains("-") // Filter out UUIDs - only show legacy-synced clients
                        }
                    },
                    getChildId: { $0.id },
                    getReassignmentId: { $0.id },
                    renderReassignmentRow: { project, selectedId, markedForDeletion, available, onToggleDelete in
                        AnyView(
                            ProjectReassignmentRow(
                                project: project,
                                selectedClientId: selectedId,
                                markedForDeletion: markedForDeletion,
                                availableClients: available,
                                onToggleDelete: onToggleDelete
                            )
                        )
                    },
                    renderSearchField: { selectedId, available in
                        AnyView(
                            SearchField(
                                selectedId: selectedId,
                                items: available,
                                placeholder: "Search for client",
                                leadingIcon: OPSStyle.Icons.client,
                                getId: { $0.id },
                                getDisplayText: { $0.name },
                                getSubtitle: { client in
                                    client.activeProjects.count > 0
                                        ? "\(client.activeProjects.count) project\(client.activeProjects.count == 1 ? "" : "s")"
                                        : nil
                                }
                            )
                        )
                    },
                    onDelete: { client, reassignments, deletions in
                        // Step 1: Handle projects (reassign or delete via Supabase)
                        let clientProjects = client.activeProjects.sorted { $0.title < $1.title }
                        let availableClients = allClients.filter {
                            $0.id != client.id &&
                            !$0.id.contains("-")
                        }

                        // Bulk mode check - if all assignments are the same
                        let uniqueAssignments = Set(reassignments.values)
                        if uniqueAssignments.count == 1, let bulkClientId = uniqueAssignments.first {
                            // Bulk reassignment
                            if let newClient = availableClients.first(where: { $0.id == bulkClientId }) {
                                print("🔄 Bulk reassigning \(clientProjects.count) projects to client: \(newClient.name) (\(bulkClientId))")

                                for project in clientProjects {
                                    print("  📋 Updating project: \(project.title) (\(project.id))")
                                    try await dataController.updateProjectFields(
                                        projectId: project.id,
                                        fields: ["client_id": .string(bulkClientId)]
                                    )
                                    print("  ✅ Project \(project.title) updated successfully")
                                    project.client = newClient
                                    project.clientId = newClient.id
                                    project.needsSync = false
                                    project.lastSyncedAt = Date()
                                }

                                print("✅ All \(clientProjects.count) projects reassigned")
                            }
                        } else if deletions.count == clientProjects.count {
                            // Bulk delete all
                            for project in clientProjects {
                                try await dataController.deleteProject(project)
                            }
                        } else {
                            // Individual mode
                            for project in clientProjects {
                                if deletions.contains(project.id) {
                                    try await dataController.deleteProject(project)
                                } else if let newClientId = reassignments[project.id],
                                   let newClient = availableClients.first(where: { $0.id == newClientId }) {
                                    print("  📋 Individual: Updating project \(project.title) to client \(newClient.name)")
                                    try await dataController.updateProjectFields(
                                        projectId: project.id,
                                        fields: ["client_id": .string(newClientId)]
                                    )
                                    print("  ✅ Project \(project.title) updated successfully")
                                    project.client = newClient
                                    project.clientId = newClient.id
                                    project.needsSync = false
                                    project.lastSyncedAt = Date()
                                }
                            }
                        }

                        // Step 2: Save project changes locally
                        try modelContext.save()

                        // Step 3: Delete the client
                        try await dataController.deleteClient(client)

                        // Step 4: Trigger sync
                        print("🔄 Triggering sync to refresh client/project relationships")
                        try? await dataController.triggerManualFullSync()
                        print("✅ Sync completed")
                    }
                )
                .environmentObject(dataController)
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
        OPSScreenHeader(
            isClient ? "CLIENT" : "TEAM MEMBER",
            leading: {
                // Back button
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .frame(width: 44, height: 44)
                .background(OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        )
    }
    
    // MARK: - Contact Preview Card

    private var contactPreviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2_5) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    // Name
                    Text(fullName.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    // Email or phone
                    if let email = self.email, !email.isEmpty {
                        Text(email)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    } else if let phone = self.phone, !phone.isEmpty {
                        Text(formatPhoneNumber(phone))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    } else {
                        Text("NO CONTACT INFO")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }

                    // Address (for clients) or Role (for team members)
                    if let address = self.address, !address.isEmpty {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: "mappin.circle")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(address.components(separatedBy: ",").first ?? address)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    } else {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: "person.badge.shield.checkmark")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(role)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Avatar on right side (56x56)
                Group {
                    if let user = user {
                        UserAvatar(user: user, size: 56)
                    } else if let teamMember = teamMember {
                        TeamMemberAvatar(teamMember: teamMember, size: 56)
                    } else if let client = client {
                        UserAvatar(client: client, size: 56)
                    } else {
                        UserAvatar(firstName: "", lastName: "", size: 56)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.thick)
                )
            }
            .padding(.vertical, 14)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .glassSurface()
        }
    }
    
    // MARK: - Contact Buttons
    
    private var contactButtons: some View {
        HStack(spacing: OPSStyle.Layout.spacing3_5) {
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
                    .nestedCard(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.thick)
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
                    .nestedCard(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.thick)
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
                    .nestedCard(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.thick)
                    )
                }
            }
            
        }
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .opacity(showFullContact ? 1 : 0)
        .offset(y: showFullContact ? 0 : 20)
        .animation(.easeInOut(duration: 0.4), value: showFullContact)
    }
    
    // MARK: - Contact Section

    private var contactSection: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {

                // Email field
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                    Text("EMAIL")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    if inlineEditField == .email {
                        inlineEditRow(
                            field: .email,
                            icon: OPSStyle.Icons.envelope,
                            placeholder: "name@example.com",
                            keyboard: .emailAddress,
                            autocapitalize: false
                        )
                    } else if let email = self.email, !email.isEmpty {
                        Button(action: {
                            if let emailURL = URL(string: "mailto:\(email)") {
                                openURL(emailURL)
                            }
                        }) {
                            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                                Image(systemName: OPSStyle.Icons.envelope)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .frame(width: 24)

                                Text(email)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .textSelection(.enabled)

                                Spacer()

                                Image(systemName: OPSStyle.Icons.envelopeFill)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .background(Color.clear)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(longPressGesture(for: .email))
                    } else {
                        HStack(spacing: OPSStyle.Layout.spacing2_5) {
                            Image(systemName: OPSStyle.Icons.envelope)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .frame(width: 24)

                            Text("No email available")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .italic()

                            Spacer()
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .background(Color.clear)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .contentShape(Rectangle())
                        .simultaneousGesture(longPressGesture(for: .email))
                    }
                }
                
                // Phone field
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                    Text("PHONE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    if inlineEditField == .phone {
                        inlineEditRow(
                            field: .phone,
                            icon: OPSStyle.Icons.phone,
                            placeholder: "(555) 555-5555",
                            keyboard: .phonePad,
                            autocapitalize: false
                        )
                    } else if let phone = self.phone, !phone.isEmpty {
                        HStack(spacing: OPSStyle.Layout.spacing2_5) {
                            Image(systemName: OPSStyle.Icons.phone)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(width: 24)

                            Text(formatPhoneNumber(phone))
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .textSelection(.enabled)

                            Spacer()

                            // Call button
                            Button(action: {
                                let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                                if let phoneURL = URL(string: "tel:\(cleaned)") {
                                    openURL(phoneURL)
                                }
                            }) {
                                Image(systemName: OPSStyle.Icons.phoneFill)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }

                            // Message button
                            Button(action: {
                                let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                                if let smsURL = URL(string: "sms:\(cleaned)") {
                                    openURL(smsURL)
                                }
                            }) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .background(Color.clear)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .contentShape(Rectangle())
                        .simultaneousGesture(longPressGesture(for: .phone))
                    } else {
                        HStack(spacing: OPSStyle.Layout.spacing2_5) {
                            Image(systemName: OPSStyle.Icons.phone)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .frame(width: 24)

                            Text("No phone available")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .italic()

                            Spacer()
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .background(Color.clear)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .contentShape(Rectangle())
                        .simultaneousGesture(longPressGesture(for: .phone))
                    }
                }
                
                // Address field (for clients only)
                if isClient {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                        Text("ADDRESS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        if inlineEditField == .address {
                            inlineEditRow(
                                field: .address,
                                icon: OPSStyle.Icons.address,
                                placeholder: "Street, City, State",
                                keyboard: .default,
                                autocapitalize: true
                            )
                        } else if let address = self.address, !address.isEmpty {
                            Button(action: {
                                // Open address in Maps
                                let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                if let mapsURL = URL(string: "maps://?q=\(encodedAddress)") {
                                    openURL(mapsURL)
                                }
                            }) {
                                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                                    Image(systemName: OPSStyle.Icons.address)
                                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        .frame(width: 24)

                                    Text(address)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .lineLimit(2)
                                        .textSelection(.enabled)

                                    Spacer()

                                    Image(systemName: "map.fill")
                                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .background(Color.clear)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .simultaneousGesture(longPressGesture(for: .address))
                        } else {
                            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                                Image(systemName: "location.slash")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .frame(width: 24)

                                Text("No address available")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .italic()

                                Spacer()
                            }
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .background(Color.clear)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .contentShape(Rectangle())
                            .simultaneousGesture(longPressGesture(for: .address))
                        }
                    }
                }

                // Notes field (clients only). Shown to everyone who can view the
                // contact — field crew rely on the gate code / site access / "dog
                // in the yard" that lives here. Editing is gated on clients.edit
                // (beginInlineEdit re-checks), so crew see notes but can't change
                // them. Empty + no edit permission → omitted entirely.
                if isClient {
                    notesField
                }
            }
        }

    /// Free-form client notes — multi-line display, long-press to edit (gated).
    @ViewBuilder
    private var notesField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("NOTES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if inlineEditField == .notes {
                inlineEditRow(
                    field: .notes,
                    icon: "note.text",
                    placeholder: "Site access, gate codes, anything the crew needs",
                    keyboard: .default,
                    autocapitalize: true
                )
            } else if let notes = client?.notes, !notes.isEmpty {
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
                    Image(systemName: "note.text")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: 24)

                    Text(notes)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .contentShape(Rectangle())
                .simultaneousGesture(longPressGesture(for: .notes))
            } else if canEditClient {
                Button(action: { beginInlineEdit(.notes) }) {
                    HStack(spacing: OPSStyle.Layout.spacing2_5) {
                        Image(systemName: "note.text")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(width: 24)

                        Text("Add notes")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                        Spacer()
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Inline Edit (bug c0ed9969)

    /// Long-press gesture wired into each contact-section row. Gated on
    /// `isClient && canEditClient`, so crew without edit permission feel
    /// no haptic and see no edit affordance.
    private func longPressGesture(for field: InlineEditField) -> some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            .onEnded { _ in beginInlineEdit(field) }
    }

    private func beginInlineEdit(_ field: InlineEditField) {
        guard isClient, canEditClient, let _ = client else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        inlineEditValue = currentValue(for: field) ?? ""
        inlineEditField = field
        // Defer focus to the next runloop tick so SwiftUI has placed the
        // TextField before we try to focus it.
        DispatchQueue.main.async {
            inlineEditFocused = true
        }
    }

    private func cancelInlineEdit() {
        inlineEditField = nil
        inlineEditValue = ""
        inlineEditFocused = false
    }

    private func currentValue(for field: InlineEditField) -> String? {
        switch field {
        case .email:   return client?.email
        case .phone:   return client?.phoneNumber
        case .address: return client?.address
        case .notes:   return client?.notes
        }
    }

    /// Writes the staged value through `DataController.updateClientContact`.
    /// Preserves every other field by passing the existing values through.
    /// Trimmed-empty values normalise to `nil` so the operator can clear a
    /// field by long-pressing and saving blank.
    private func saveInlineEdit() async {
        guard let client = client, let field = inlineEditField else { return }
        let trimmed = inlineEditValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalised = trimmed.isEmpty ? nil : trimmed

        await MainActor.run { inlineEditSaving = true }
        defer { Task { @MainActor in inlineEditSaving = false } }

        do {
            if field == .notes {
                try await dataController.updateClientNotes(
                    clientId: client.id,
                    notes: normalised
                )
            } else {
                try await dataController.updateClientContact(
                    clientId: client.id,
                    name: client.name,
                    email:   field == .email   ? normalised : client.email,
                    phone:   field == .phone   ? normalised : client.phoneNumber,
                    address: field == .address ? normalised : client.address
                )
            }
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(Feedback.Contact.fieldUpdated)
                cancelInlineEdit()
            }
        } catch {
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            print("[CONTACT_DETAIL] inline edit save failed for \(field.rawValue): \(error)")
        }
    }

    @ViewBuilder
    private func inlineEditRow(
        field: InlineEditField,
        icon: String,
        placeholder: String,
        keyboard: UIKeyboardType,
        autocapitalize: Bool
    ) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 24)

            TextField(placeholder, text: $inlineEditValue, axis: .vertical)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalize ? .sentences : .never)
                .autocorrectionDisabled(!autocapitalize)
                .focused($inlineEditFocused)
                .submitLabel(.done)
                .onSubmit { Task { await saveInlineEdit() } }
                .disabled(inlineEditSaving)

            if inlineEditSaving {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    .scaleEffect(0.8)
            } else {
                Button(action: cancelInlineEdit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { Task { await saveInlineEdit() } }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .background(Color.clear)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Save and Share Buttons

    private var saveShareButtons: some View {
        Group {
            if isClient {
                if let client = client {
                    HStack(spacing: OPSStyle.Layout.spacing2_5) {
                        // Save to Contacts button
                        Button(action: {
                            showingContactExportOptions = true
                        }) {
                            HStack {
                                Image(systemName: OPSStyle.Icons.addContact)
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
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
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
                            VStack(spacing: OPSStyle.Layout.spacing1) {
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
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                    }
                    .padding(.top, OPSStyle.Layout.spacing3)
                }
            }
        }
    }
    
    // MARK: - Projects Section

    private var projectsSection: some View {
        // Get relevant projects
        let projects = relevantProjects

        return SectionCard(
            icon: "folder.fill",
            title: "Projects (\(projects.count))",
            actionIcon: (isClient && canEditClient) ? OPSStyle.Icons.plus : nil,
            actionLabel: (isClient && canEditClient) ? "Add" : nil,
            onAction: (isClient && canEditClient) ? { showingCreateProject = true } : nil,
            contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        ) {

            if !projects.isEmpty {
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
                                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                                    .padding(.vertical, OPSStyle.Layout.spacing1)
                                    .background(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                            .fill(project.status.color.opacity(0.1))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                            .stroke(project.status.color.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
                                    )

                                // Chevron
                                Image(systemName: "chevron.right")
                                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
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
                            withAnimation(OPSStyle.Animation.standard) {
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
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else if isClient && canEditClient {
                // Empty state for clients with no projects (admin/office only)
                Button(action: {
                    showingCreateProject = true
                }) {
                    VStack(spacing: OPSStyle.Layout.spacing2_5) {
                        Image(systemName: OPSStyle.Icons.addProject)
                            .font(.system(size: OPSStyle.Layout.IconSize.xl))
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        VStack(spacing: OPSStyle.Layout.spacing1) {
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
            } else {
                // Empty state for non-clients or field crew (just text, no action)
                VStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Image(systemName: "folder")
                        .font(.system(size: OPSStyle.Layout.IconSize.xl))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Text("No projects")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
        .opacity(showFullContact ? 1 : 0)
        .offset(y: showFullContact ? 0 : 20)
        .animation(.easeInOut(duration: 0.5).delay(0.3), value: showFullContact)
    }

    // MARK: - Role Section

    @State private var isChangingRole = false

    private var canEditRole: Bool {
        guard let user = user else { return false }
        let isCurrentUser = user.id == dataController.currentUser?.id
        return !isCurrentUser && !isClient && permissionStore.can("team.manage")
    }

    private var roleSection: some View {
        SectionCard(
            icon: isClient ? "building.2" : "person.badge.shield.checkmark",
            title: "Role"
        ) {
            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                HStack {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text("CURRENT ROLE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Text(role.uppercased())
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    Spacer()

                    if canEditRole {
                        Menu {
                            ForEach(UserRole.allCases.filter { $0 != .owner }.sorted(by: { $0.hierarchy < $1.hierarchy }), id: \.rawValue) { menuRole in
                                Button {
                                    Task { await changeUserRole(to: menuRole) }
                                } label: {
                                    HStack {
                                        Text(menuRole.displayName)
                                        if user?.role == menuRole {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                if isChangingRole {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                        .scaleEffect(0.7)
                                } else {
                                    Text("CHANGE")
                                        .font(OPSStyle.Typography.captionBold)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                }
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        .disabled(isChangingRole)
                    }
                }

                if let userRole = user?.role {
                    Text(userRole.roleDescription)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .opacity(showFullContact ? 1 : 0)
        .offset(y: showFullContact ? 0 : 20)
        .animation(.easeInOut(duration: 0.5).delay(0.2), value: showFullContact)
    }

    private func changeUserRole(to newRole: UserRole) async {
        guard let user = user else { return }

        await MainActor.run { isChangingRole = true }

        do {
            let roleId = try await PermissionAdminService.resolveRoleId(for: newRole)
            try await PermissionAdminService.assignUserRole(userId: user.id, roleId: roleId)

            try await dataController.updateUserFields(
                userId: user.id,
                fields: ["role": .string(newRole.rawValue)]
            )

            await MainActor.run {
                user.role = newRole
                try? dataController.modelContext?.save()
                isChangingRole = false

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                ToastCenter.shared.present(Feedback.Contact.roleUpdated)
            }

            print("[CONTACT_DETAIL] Updated \(user.fullName) role to \(newRole.displayName)")

        } catch {
            await MainActor.run {
                isChangingRole = false
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
            print("[CONTACT_DETAIL] Error changing role: \(error)")
        }
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
        permissionStore.can("clients.edit")
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
            return ProjectListOrdering.activeFirst(client.projects)
        } else if let user = user {
            // For team members, show projects they're assigned to
            let projects = dataController.getAllProjects().filter { project in
                project.teamMembers.contains(where: { $0.id == user.id })
            }
            return ProjectListOrdering.activeFirst(projects)
        } else if let teamMember = teamMember {
            // For legacy team members (without User object), check by ID
            let projects = dataController.getAllProjects().filter { project in
                project.getTeamMemberIds().contains(teamMember.id)
            }
            return ProjectListOrdering.activeFirst(projects)
        } else {
            return []
        }
    }
    
    // MARK: - Helper Methods
    
    private func saveClientChanges(name: String, email: String?, phone: String?, address: String?) async {
        guard let client = client else { return }

        do {
            // Extract only digits from phone number
            let cleanedPhone: String?
            if let phone = phone, !phone.isEmpty {
                let digitsOnly = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                cleanedPhone = digitsOnly.isEmpty ? nil : digitsOnly
            } else {
                cleanedPhone = nil
            }

            // Update the client via DataController
            try await dataController.updateClientContact(
                clientId: client.id,
                name: name,
                email: email,
                phone: cleanedPhone,
                address: address
            )
        } catch {
        }
    }
    
    private func saveSubClient(name: String, title: String?, email: String?, phone: String?, address: String?) async {
        guard let client = client else { return }

        do {
            if let editingSubClient = subClientToEdit, !editingSubClient.name.isEmpty {
                // Edit existing sub-client via DataController
                try await dataController.editSubClient(
                    subClientId: editingSubClient.id,
                    name: name,
                    title: title,
                    email: email,
                    phone: phone,
                    address: address
                )

                // Refresh UI
                await MainActor.run {
                    ToastCenter.shared.present(Feedback.Contact.subSaved)
                    subClientsRefreshKey = UUID()
                    subClientToEdit = nil
                }

            } else {
                // Create new sub-client via DataController (local-first)
                let companyId = client.companyId ?? dataController.currentUser?.companyId ?? ""
                let newSubClient = try await dataController.createSubClient(
                    clientId: client.id,
                    name: name,
                    title: title,
                    email: email,
                    phone: phone,
                    address: address,
                    companyId: companyId
                )

                // Set the parent relationship
                newSubClient.client = client

                // Add the new sub-client to the client's array
                await MainActor.run {
                    client.subClients.append(newSubClient)
                    client.lastSyncedAt = Date()
                    ToastCenter.shared.present(Feedback.Contact.subSaved)
                    subClientsRefreshKey = UUID()
                    subClientToEdit = nil
                }
            }

        } catch {
        }
    }
    
    private func deleteSubClient(_ subClient: SubClient) {
        Task {
            do {
                // Delete via DataController (local-first with SyncEngine)
                try await dataController.deleteSubClient(subClientId: subClient.id)

                // Remove from parent client's array
                await MainActor.run {
                    if let index = client?.subClients.firstIndex(where: { $0.id == subClient.id }) {
                        client?.subClients.remove(at: index)
                    }
                    ToastCenter.shared.present(Feedback.Contact.subDeleted)
                    subClientsRefreshKey = UUID()
                }
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
        let user = User(id: "123", firstName: "John", lastName: "Doe", role: .crew, companyId: "company123")
        user.email = "john.doe@example.com"
        user.phone = "555-123-4567"
        
        let teamMember = TeamMember(
            id: "456",
            firstName: "Jane",
            lastName: "Smith",
            role: "Office",
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
