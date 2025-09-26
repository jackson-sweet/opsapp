# Task Management

## Overview
Task creation, editing, and management within projects, including task type customization and team assignment capabilities.

## Quick Task Creation (from Dashboard)

### Task Creation Flow
```swift
struct QuickTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    // Step 1: Project Selection
    @State private var selectedProject: Project?
    @State private var showingConversionAlert = false
    
    // Step 2: Task Details
    @State private var selectedTaskTypeId: String?
    @State private var taskNotes: String = ""
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var allDay: Bool = false
    @State private var duration: Int = 1 // in hours
    
    // Task Type Creation
    @State private var showingCreateTaskType = false
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                
                if selectedProject == nil {
                    projectSelectionView
                } else {
                    taskDetailsForm
                }
            }
            .navigationTitle("CREATE TASK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                if selectedProject != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("CREATE") { createTask() }
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .disabled(!isValid)
                    }
                }
            }
            .alert("Switch to Task-Based Scheduling?", isPresented: $showingConversionAlert) {
                Button("CANCEL", role: .cancel) {
                    selectedProject = nil
                }
                Button("CONVERT") {
                    convertProjectScheduling()
                }
            } message: {
                Text("This project uses project-based scheduling. Converting will make individual tasks appear on the calendar.")
            }
        }
    }
}
```

### Project Selection View
```swift
private var projectSelectionView: some View {
    VStack(spacing: 0) {
        // Header
        Text("SELECT PROJECT")
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        
        // Project List
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(availableProjects) { project in
                    ProjectSelectionRow(
                        project: project,
                        onSelect: { selectProject(project) }
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
            }
        }
    }
}

struct ProjectSelectionRow: View {
    let project: Project
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text(project.clientName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                // Scheduling Mode Indicator
                SchedulingModeBadge(project: project)
                
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

### Scheduling Mode Badge
```swift
struct SchedulingModeBadge: View {
    let project: Project
    
    var badgeText: String {
        if project.eventType == .project {
            return "PROJECT-BASED"
        } else {
            let taskCount = project.tasks.count
            return taskCount == 0 ? "NO TASKS" : "\(taskCount) TASK\(taskCount == 1 ? "" : "S")"
        }
    }
    
    var badgeColor: Color {
        project.eventType == .project 
            ? Color.orange 
            : OPSStyle.Colors.primaryAccent
    }
    
    var body: some View {
        Text(badgeText)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor)
            .cornerRadius(4)
    }
}
```

### Task Details Form
```swift
private var taskDetailsForm: some View {
    Form {
        // Task Type Section
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("TASK TYPE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Menu {
                    Button("Create New Type") {
                        showingCreateTaskType = true
                    }
                    
                    Divider()
                    
                    ForEach(availableTaskTypes) { taskType in
                        Button(action: { selectedTaskTypeId = taskType.id }) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                    .frame(width: 10, height: 10)
                                
                                if let icon = taskType.icon {
                                    Image(systemName: icon)
                                        .foregroundColor(Color(hex: taskType.color))
                                }
                                
                                Text(taskType.display)
                                
                                if selectedTaskTypeId == taskType.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        if let selectedType = selectedTaskType {
                            TaskTypeDisplay(taskType: selectedType)
                        } else {
                            Text("Select task type")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(8)
                }
            }
        }
        .listRowBackground(OPSStyle.Colors.cardBackgroundDark)
        
        // Notes Section
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTES")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                TextEditor(text: $taskNotes)
                    .font(OPSStyle.Typography.body)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(8)
            }
        }
        .listRowBackground(OPSStyle.Colors.cardBackgroundDark)
        
        // Team Section
        teamSelectionSection
        
        // Schedule Section
        scheduleSection
    }
    .scrollContentBackground(.hidden)
}
```

### Schedule Section
```swift
private var scheduleSection: some View {
    Section {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCHEDULE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            Toggle(isOn: $allDay) {
                Text("All-Day Task")
                    .font(OPSStyle.Typography.body)
            }
            .tint(OPSStyle.Colors.primaryAccent)
            
            if !allDay {
                DatePicker(
                    "Start",
                    selection: $startDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(OPSStyle.Typography.body)
                
                DatePicker(
                    "End",
                    selection: $endDate,
                    in: startDate...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(OPSStyle.Typography.body)
                .onChange(of: endDate) { _ in
                    calculateDuration()
                }
                
                // Auto-calculated duration
                HStack {
                    Text("Duration")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    Text(formattedDuration)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 8)
            } else {
                DatePicker(
                    "Date",
                    selection: $startDate,
                    displayedComponents: .date
                )
                .font(OPSStyle.Typography.body)
            }
        }
    }
    .listRowBackground(OPSStyle.Colors.cardBackgroundDark)
}
```

## Task Type Management

### Task Type List View
```swift
struct TaskTypeManagementView: View {
    @State private var taskTypes: [TaskType] = []
    @State private var showingCreateTaskType = false
    @State private var editingTaskType: TaskType?
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Default Task Types
                    TaskTypeSection(
                        title: "DEFAULT TYPES",
                        taskTypes: taskTypes.filter { $0.isDefault },
                        canEdit: false
                    )
                    
                    // Custom Task Types
                    TaskTypeSection(
                        title: "CUSTOM TYPES",
                        taskTypes: taskTypes.filter { !$0.isDefault },
                        canEdit: true,
                        onEdit: { editingTaskType = $0 },
                        onDelete: deleteTaskType
                    )
                    
                    // Create Button
                    Button(action: { showingCreateTaskType = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("CREATE NEW TYPE")
                        }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("TASK TYPES")
        .sheet(isPresented: $showingCreateTaskType) {
            TaskTypeFormSheet(mode: .create)
        }
        .sheet(item: $editingTaskType) { taskType in
            TaskTypeFormSheet(mode: .edit(taskType))
        }
    }
}
```

### Task Type Creation Form
```swift
struct TaskTypeFormSheet: View {
    enum Mode {
        case create
        case edit(TaskType)
    }
    
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedColor: String = "#59779F"
    @State private var selectedIcon: String = "hammer.fill"
    
    let availableColors = [
        "#A5B368", // Green
        "#59779F", // Blue
        "#C4A868", // Amber
        "#931A32", // Red
        "#7B68A6", // Purple
        "#4A4A4A", // Gray
        "#FF6B35", // Orange
        "#2E86AB", // Teal
    ]
    
    let availableIcons = TaskType.predefinedIcons
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                
                Form {
                    // Name Section
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TYPE NAME")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            TextField("e.g., Installation", text: $name)
                                .font(OPSStyle.Typography.body)
                                .padding(12)
                                .background(OPSStyle.Colors.cardBackground)
                                .cornerRadius(8)
                        }
                    }
                    .listRowBackground(OPSStyle.Colors.cardBackgroundDark)
                    
                    // Color Section
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("COLOR")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                                ForEach(availableColors, id: \.self) { color in
                                    ColorSelectionButton(
                                        color: color,
                                        isSelected: selectedColor == color,
                                        action: { selectedColor = color }
                                    )
                                }
                            }
                        }
                    }
                    .listRowBackground(OPSStyle.Colors.cardBackgroundDark)
                    
                    // Icon Section
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ICON")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                                ForEach(availableIcons, id: \.self) { icon in
                                    IconSelectionButton(
                                        icon: icon,
                                        color: selectedColor,
                                        isSelected: selectedIcon == icon,
                                        action: { selectedIcon = icon }
                                    )
                                }
                            }
                        }
                    }
                    .listRowBackground(OPSStyle.Colors.cardBackgroundDark)
                    
                    // Preview Section
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PREVIEW")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: selectedColor) ?? OPSStyle.Colors.primaryAccent)
                                    .frame(width: 10, height: 10)
                                
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 20))
                                    .foregroundColor(Color(hex: selectedColor))
                                
                                Text(name.isEmpty ? "Task Type Name" : name)
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(8)
                        }
                    }
                    .listRowBackground(OPSStyle.Colors.cardBackgroundDark)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(mode.isCreate ? "NEW TASK TYPE" : "EDIT TASK TYPE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("SAVE") { saveTaskType() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .disabled(name.isEmpty)
                }
            }
        }
    }
}
```

## Task Type Deletion

### Deletion with Reassignment
```swift
struct TaskTypeDeletionSheet: View {
    let taskType: TaskType
    let affectedTasks: [ProjectTask]
    @State private var replacementTaskTypeId: String?
    @State private var showingCreateTaskType = false
    @State private var isDeleting = false
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Warning
                    WarningCard(
                        message: "\(affectedTasks.count) task(s) use this type and must be reassigned"
                    )
                    
                    // Replacement Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("REASSIGN TO")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Menu {
                            Button("Create New Type") {
                                showingCreateTaskType = true
                            }
                            
                            Divider()
                            
                            ForEach(availableReplacementTypes) { type in
                                Button(action: { replacementTaskTypeId = type.id }) {
                                    TaskTypeMenuRow(
                                        taskType: type,
                                        isSelected: replacementTaskTypeId == type.id
                                    )
                                }
                            }
                        } label: {
                            HStack {
                                if let selectedType = selectedReplacementType {
                                    TaskTypeDisplay(taskType: selectedType)
                                } else {
                                    Text("Select replacement type")
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding(12)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                    }
                    
                    Spacer()
                    
                    // Delete Button
                    Button(action: performDeletion) {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("DELETE TYPE")
                        }
                    }
                    .buttonStyle(DestructiveButtonStyle())
                    .disabled(replacementTaskTypeId == nil || isDeleting)
                }
                .padding(20)
            }
            .navigationTitle("DELETE TASK TYPE")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```