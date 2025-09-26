# Client Management

## Overview
Complete client lifecycle management from creation through deletion, with duplicate detection and project reassignment capabilities.

## Client List View

### Layout Structure
```swift
struct ClientListView: View {
    @State private var searchText = ""
    @State private var clients: [Client] = []
    @State private var isLoading = false
    @State private var showingCreateClient = false
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search Bar
                SearchBar(text: $searchText)
                
                // Client List
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredClients) { client in
                            ClientRow(client: client)
                            Divider()
                                .background(Color.white.opacity(0.1))
                        }
                    }
                }
            }
        }
        .navigationTitle("CLIENTS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCreateClient = true }) {
                    Image(systemName: "plus")
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .sheet(isPresented: $showingCreateClient) {
            ClientFormSheet(mode: .create)
        }
    }
}
```

### Client Row Component
```swift
struct ClientRow: View {
    let client: Client
    
    var body: some View {
        NavigationLink(destination: ClientDetailsView(client: client)) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.name.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    if let email = client.email {
                        Text(email)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    Text("\(client.projects.count) projects")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                
                Spacer()
                
                // Contact Icons
                HStack(spacing: 12) {
                    if client.phoneNumber != nil {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    if client.email != nil {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        }
    }
}
```

## Client Details View

### Layout Structure
```swift
struct ClientDetailsView: View {
    let client: Client
    @State private var showingEditClient = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Contact Information
                    ClientInfoCard(client: client)
                    
                    // Projects Section
                    ProjectsCard(client: client)
                    
                    // Sub-Clients Section
                    if !client.subClients.isEmpty {
                        SubClientsCard(client: client)
                    }
                    
                    // Notes Section
                    if let notes = client.notes, !notes.isEmpty {
                        NotesCard(notes: notes)
                    }
                    
                    // Delete Button
                    DeleteClientButton()
                }
                .padding(20)
            }
        }
        .navigationTitle(client.name.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("EDIT") {
                    showingEditClient = true
                }
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
    }
}
```

## Client Creation Flow

### Form Structure
```swift
struct ClientFormSheet: View {
    enum Mode {
        case create
        case edit(Client)
    }
    
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    
    // Form Fields
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var address: String = ""
    @State private var notes: String = ""
    
    // Duplicate Detection
    @State private var duplicateCheckResult: DuplicateCheckResult?
    @State private var showingDuplicateAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                
                Form {
                    Section {
                        // Name Field with Duplicate Detection
                        VStack(alignment: .leading) {
                            TextField("Client Name *", text: $name)
                                .font(OPSStyle.Typography.body)
                                .onChange(of: name) { _ in
                                    checkForDuplicates()
                                }
                            
                            if let duplicate = duplicateCheckResult {
                                DuplicateWarning(duplicate: duplicate)
                            }
                        }
                        
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                        
                        TextField("Phone", text: $phone)
                            .keyboardType(.phonePad)
                        
                        AddressSearchField(address: $address)
                        
                        TextField("Notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    .listRowBackground(OPSStyle.Colors.cardBackgroundDark)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(mode.isCreate ? "NEW CLIENT" : "EDIT CLIENT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("SAVE") { saveClient() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .disabled(name.isEmpty)
                }
            }
        }
    }
}
```

### Duplicate Detection Component
```swift
struct DuplicateWarning: View {
    let duplicate: DuplicateCheckResult
    @State private var showingUseExisting = false
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            VStack(alignment: .leading) {
                Text("Possible duplicate")
                    .font(OPSStyle.Typography.captionBold)
                
                Text(duplicate.clientName)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            Button("USE EXISTING") {
                showingUseExisting = true
            }
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
```

### Duplicate Check Logic
```swift
func checkForDuplicates() {
    guard name.count >= 3 else {
        duplicateCheckResult = nil
        return
    }
    
    Task {
        let result = await APIService.checkDuplicateClient(
            name: name,
            email: email
        )
        
        await MainActor.run {
            if let similar = result.similarClients.first,
               similar.similarity >= 0.8 {
                duplicateCheckResult = DuplicateCheckResult(
                    isDuplicate: true,
                    clientId: similar.id,
                    clientName: similar.name,
                    similarity: similar.similarity
                )
            } else {
                duplicateCheckResult = nil
            }
        }
    }
}
```

## Client Deletion Flow

### Delete Confirmation
```swift
struct ClientDeletionSheet: View {
    let client: Client
    let projects: [Project]
    @State private var reassignments: [String: String] = [:] // projectId: newClientId
    @State private var selectedBulkClient: String?
    @State private var isDeleting = false
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Warning Message
                    WarningCard(
                        message: "Deleting \(client.name) requires reassigning \(projects.count) project(s)"
                    )
                    
                    // Bulk Reassignment Option
                    if projects.count > 1 {
                        BulkReassignmentCard(
                            selectedClient: $selectedBulkClient,
                            onApply: applyBulkReassignment
                        )
                    }
                    
                    // Individual Project Reassignments
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(projects) { project in
                                ProjectReassignmentRow(
                                    project: project,
                                    selectedClientId: binding(for: project.id)
                                )
                            }
                        }
                    }
                    
                    // Delete Button
                    Button(action: performDeletion) {
                        if isDeleting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("DELETE CLIENT")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!allProjectsReassigned || isDeleting)
                }
                .padding(20)
            }
            .navigationTitle("DELETE CLIENT")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    var allProjectsReassigned: Bool {
        projects.allSatisfy { project in
            reassignments[project.id] != nil
        }
    }
}
```

### Reassignment Row
```swift
struct ProjectReassignmentRow: View {
    let project: Project
    @Binding var selectedClientId: String?
    @State private var showingCreateClient = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Menu {
                Button("Create New Client") {
                    showingCreateClient = true
                }
                
                Divider()
                
                ForEach(availableClients) { client in
                    Button(action: { selectedClientId = client.id }) {
                        HStack {
                            Text(client.name)
                            if selectedClientId == client.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedClientName ?? "Select Client")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(
                            selectedClientId != nil 
                                ? OPSStyle.Colors.primaryText 
                                : OPSStyle.Colors.tertiaryText
                        )
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(12)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .sheet(isPresented: $showingCreateClient) {
            ClientFormSheet(mode: .create) { newClientId in
                selectedClientId = newClientId
            }
        }
    }
}
```

## API Integration

### Create Client
```swift
func createClient() async throws {
    let clientData = ClientCreateRequest(
        name: name,
        email: email.isEmpty ? nil : email,
        phone: phone.isEmpty ? nil : phone,
        address: address.isEmpty ? nil : address,
        notes: notes.isEmpty ? nil : notes,
        companyId: dataController.currentUser?.companyId ?? ""
    )
    
    let newClient = try await APIService.createClient(clientData)
    await dataController.saveClient(newClient)
}
```

### Update Client
```swift
func updateClient(_ client: Client) async throws {
    let updateData = ClientUpdateRequest(
        name: name,
        email: email,
        phone: phone,
        address: address,
        notes: notes
    )
    
    let updated = try await APIService.updateClient(client.id, data: updateData)
    await dataController.updateClient(updated)
}
```

### Delete Client
```swift
func deleteClient(
    _ client: Client,
    reassignments: [String: String]
) async throws {
    // First reassign all projects
    for (projectId, newClientId) in reassignments {
        try await APIService.reassignProject(projectId, toClient: newClientId)
    }
    
    // Then delete the client
    try await APIService.deleteClient(client.id)
    await dataController.deleteClient(client.id)
}
```