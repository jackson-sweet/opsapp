# Project Management

## Overview
Complete project lifecycle management including creation, editing, scheduling mode conversion, and deletion with task management integration.

## Project List View

### Enhanced List for Management
```swift
struct JobBoardProjectListView: View {
    @State private var projects: [Project] = []
    @State private var searchText = ""
    @State private var filterStatus: Status?
    @State private var showingCreateProject = false
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Filter Bar
                ProjectFilterBar(selectedStatus: $filterStatus)
                
                // Search Bar
                SearchBar(text: $searchText)
                
                // Project List
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredProjects) { project in
                            ProjectManagementRow(project: project)
                            Divider()
                                .background(Color.white.opacity(0.1))
                        }
                    }
                }
            }
        }
        .navigationTitle("PROJECTS")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingCreateProject = true }) {
                    Image(systemName: "plus")
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .sheet(isPresented: $showingCreateProject) {
            ProjectFormSheet(mode: .create)
        }
    }
}
```

### Project Management Row
```swift
struct ProjectManagementRow: View {
    let project: Project
    @State private var showingActions = false
    
    var body: some View {
        HStack {
            // Status Indicator
            Circle()
                .fill(project.status.color)
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(project.title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    // Scheduling Mode Badge
                    SchedulingModeBadge(project: project)
                }
                
                Text(project.clientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                HStack(spacing: 12) {
                    if let startDate = project.startDate {
                        Label(
                            DateFormatter.projectDate(startDate),
                            systemImage: "calendar"
                        )
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    
                    if !project.teamMembers.isEmpty {
                        Label(
                            "\(project.teamMembers.count)",
                            systemImage: "person.2"
                        )
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            
            Spacer()
            
            // Quick Actions
            Menu {
                Button("Edit", action: editProject)
                Button("Change Status", action: changeStatus)
                Button("Convert Scheduling", action: convertScheduling)
                
                Divider()
                
                Button("Delete", role: .destructive, action: deleteProject)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
    }
}
```

## Project Creation Form

### Main Form Structure
```swift
struct ProjectFormSheet: View {
    enum Mode {
        case create
        case edit(Project)
    }
    
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    // Form State
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var notes: String = ""
    @State private var address: String = ""
    @State private var selectedClientId: String?
    @State private var schedulingMode: CalendarEventType = .project
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(86400)
    @State private var allDay: Bool = true
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var projectImages: [UIImage] = []
    
    // Client Creation
    @State private var showingCreateClient = false
    @State private var clientSearchText = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                
                Form {
                    // Client Section
                    clientSection
                    
                    // Project Details Section
                    projectDetailsSection
                    
                    // Scheduling Section
                    schedulingSection
                    
                    // Team Section
                    teamSection
                    
                    // Photos Section
                    photosSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(mode.isCreate ? "NEW PROJECT" : "EDIT PROJECT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("SAVE") { saveProject() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .disabled(!isValid)
                }
            }
        }
    }
}
```

### Client Selection Section
```swift
private var clientSection: some View {
    Section {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLIENT *")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            // Type-Ahead Search Field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                TextField("Search or create client...", text: $clientSearchText)
                    .font(OPSStyle.Typography.body)
                    .onChange(of: clientSearchText) { _ in
                        searchClients()
                    }
                
                if !clientSearchText.isEmpty {
                    Button(action: { clientSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
            .padding(12)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(8)
            
            // Search Results or Create Option
            if !clientSearchText.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    if matchingClients.isEmpty {
                        Button(action: { showingCreateClient = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                Text("Create \"\(clientSearchText)\"")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            .padding(12)
                        }
                    } else {
                        ForEach(matchingClients.prefix(3)) { client in
                            Button(action: { selectClient(client) }) {
                                HStack {
                                    Text(client.name)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Spacer()
                                    if selectedClientId == client.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                }
                                .padding(12)
                            }
                            
                            if client != matchingClients.prefix(3).last {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                            }
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(8)
            }
            
            // Selected Client Display
            if let selectedClient = selectedClient {
                SelectedClientCard(client: selectedClient)
            }
        }
    }
    .listRowBackground(OPSStyle.Colors.cardBackgroundDark)
}
```

### Scheduling Mode Section
```swift
private var schedulingSection: some View {
    Section {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCHEDULING MODE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            // Mode Selector
            HStack(spacing: 0) {
                SchedulingModeButton(
                    title: "PROJECT-BASED",
                    icon: "calendar",
                    description: "Single calendar entry",
                    isSelected: schedulingMode == .project,
                    action: { schedulingMode = .project }
                )
                
                SchedulingModeButton(
                    title: "TASK-BASED",
                    icon: "checklist",
                    description: "Individual task scheduling",
                    isSelected: schedulingMode == .task,
                    action: { schedulingMode = .task }
                )
            }
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(8)
            
            // Date Selection (for project-based)
            if schedulingMode == .project {
                VStack(spacing: 12) {
                    DatePicker(
                        "Start Date",
                        selection: $startDate,
                        displayedComponents: allDay ? .date : [.date, .hourAndMinute]
                    )
                    .font(OPSStyle.Typography.body)
                    
                    DatePicker(
                        "End Date",
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: allDay ? .date : [.date, .hourAndMinute]
                    )
                    .font(OPSStyle.Typography.body)
                    
                    Toggle(isOn: $allDay) {
                        Text("All-Day")
                            .font(OPSStyle.Typography.body)
                    }
                    .tint(OPSStyle.Colors.primaryAccent)
                }
                .padding(.top, 8)
            } else {
                Text("Add tasks after creating the project")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.top, 8)
            }
        }
    }
    .listRowBackground(OPSStyle.Colors.cardBackgroundDark)
}
```

## Scheduling Mode Conversion

### Conversion Dialog
```swift
struct SchedulingModeConversionAlert: View {
    let project: Project
    let targetMode: CalendarEventType
    let onConfirm: () async throws -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: targetMode == .task ? "checklist" : "calendar")
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            
            // Title
            Text("SWITCH SCHEDULING MODE")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            // Explanation
            VStack(alignment: .leading, spacing: 12) {
                if targetMode == .task {
                    FeaturePoint(
                        icon: "checkmark.circle",
                        text: "Each task will appear separately on calendar"
                    )
                    FeaturePoint(
                        icon: "calendar.badge.clock",
                        text: "Project dates will be determined by task dates"
                    )
                    FeaturePoint(
                        icon: "info.circle",
                        text: "Current project calendar event will be hidden"
                    )
                } else {
                    FeaturePoint(
                        icon: "calendar",
                        text: "Project will have single calendar entry"
                    )
                    FeaturePoint(
                        icon: "eye.slash",
                        text: "Individual tasks won't appear on calendar"
                    )
                    FeaturePoint(
                        icon: "clock",
                        text: "You'll set project dates directly"
                    )
                }
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            
            // Buttons
            HStack(spacing: 16) {
                Button("CANCEL") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("CONVERT") {
                    Task {
                        try await onConfirm()
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(40)
    }
}
```

### Conversion Logic
```swift
func convertSchedulingMode(
    project: Project,
    to targetMode: CalendarEventType
) async throws {
    // Update project
    project.eventType = targetMode
    
    if targetMode == .task {
        // Converting to task-based
        // 1. Deactivate project's calendar event
        if let projectEvent = project.primaryCalendarEvent {
            projectEvent.active = false
        }
        
        // 2. Activate all task calendar events
        for task in project.tasks {
            if let taskEvent = task.calendarEvent {
                taskEvent.active = true
            }
        }
        
        // 3. Update project dates based on tasks
        updateProjectDatesFromTasks(project)
        
    } else {
        // Converting to project-based
        // 1. Activate project's calendar event
        if let projectEvent = project.primaryCalendarEvent {
            projectEvent.active = true
        } else {
            // Create new calendar event if needed
            let newEvent = CalendarEvent(
                projectId: project.id,
                eventType: .project,
                startDate: project.startDate ?? Date(),
                endDate: project.endDate ?? Date().addingTimeInterval(86400),
                active: true
            )
            project.primaryCalendarEvent = newEvent
        }
        
        // 2. Deactivate all task calendar events
        for task in project.tasks {
            if let taskEvent = task.calendarEvent {
                taskEvent.active = false
            }
        }
    }
    
    // Sync to Bubble
    try await APIService.updateProjectSchedulingMode(
        projectId: project.id,
        mode: targetMode
    )
}
```

## Project Deletion

### Deletion Confirmation
```swift
struct ProjectDeletionConfirmation: View {
    let project: Project
    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Warning Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            // Title
            Text("DELETE PROJECT")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            // Project Info
            VStack(alignment: .leading, spacing: 8) {
                Text(project.title)
                    .font(OPSStyle.Typography.bodyBold)
                Text(project.clientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(8)
            
            // Warning Message
            if project.hasTasks {
                WarningCard(
                    message: "This will permanently delete \(project.tasks.count) task(s) associated with this project"
                )
            }
            
            // Buttons
            HStack(spacing: 16) {
                Button("CANCEL") {
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button(action: deleteProject) {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("DELETE")
                    }
                }
                .buttonStyle(DestructiveButtonStyle())
                .disabled(isDeleting)
            }
        }
        .padding(24)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    func deleteProject() {
        isDeleting = true
        
        Task {
            do {
                try await APIService.deleteProject(project.id)
                await dataController.deleteProject(project)
                dismiss()
            } catch {
                // Handle error
                isDeleting = false
            }
        }
    }
}
```

## Date Calculation Logic

### Task-Based Project Date Updates
```swift
func updateProjectDatesFromTasks(_ project: Project) {
    guard project.eventType == .task else { return }
    
    let taskEvents = project.tasks.compactMap { $0.calendarEvent }
    guard !taskEvents.isEmpty else {
        project.startDate = nil
        project.endDate = nil
        return
    }
    
    // Find earliest start and latest end
    let startDates = taskEvents.map { $0.startDate }
    let endDates = taskEvents.map { $0.endDate }
    
    project.startDate = startDates.min()
    project.endDate = endDates.max()
    
    // Mark for sync
    project.needsSync = true
}
```