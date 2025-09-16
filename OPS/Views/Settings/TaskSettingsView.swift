//
//  TaskSettingsView.swift
//  OPS
//
//  Task type management for office crews and admins
//

import SwiftUI
import SwiftData

struct TaskSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var taskTypes: [TaskType] = []
    @State private var isLoading = true
    @State private var selectedTaskType: TaskType?
    @State private var showingEditSheet = false
    @State private var showingAddSheet = false
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Task Types",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading task types...")
                        .foregroundColor(.white)
                    Spacer()
                } else if taskTypes.isEmpty {
                    // Empty state
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 60))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        
                        Text("No Task Types")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        
                        Text("Create task types to categorize work")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Button(action: createDefaultTaskTypes) {
                            Text("CREATE DEFAULT TYPES")
                                .font(OPSStyle.Typography.smallButton)
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                    }
                    Spacer()
                } else {
                    // Task types list
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(taskTypes.sorted { $0.displayOrder < $1.displayOrder }) { taskType in
                                TaskTypeRow(taskType: taskType) {
                                    selectedTaskType = taskType
                                    showingEditSheet = true
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
                
                // Bottom action bar
                HStack {
                    Text("\(taskTypes.count) task types")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Spacer()
                    
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
            }
        }
        .navigationBarHidden(true)
        .onAppear { fetchTaskTypes() }
        .sheet(isPresented: $showingEditSheet) {
            if let taskType = selectedTaskType {
                EditTaskTypeSheet(taskType: taskType) {
                    fetchTaskTypes()
                }
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddTaskTypeSettingsSheet {
                fetchTaskTypes()
            }
            .environmentObject(dataController)
        }
    }
    
    private func fetchTaskTypes() {
        isLoading = true
        
        do {
            let descriptor = FetchDescriptor<TaskType>(
                sortBy: [SortDescriptor(\.displayOrder)]
            )
            taskTypes = try modelContext.fetch(descriptor)
            isLoading = false
        } catch {
            print("Failed to fetch task types: \(error)")
            isLoading = false
        }
    }
    
    private func createDefaultTaskTypes() {
        guard let companyId = dataController.currentUser?.companyId else { return }
        
        let defaults = TaskType.createDefaults(companyId: companyId)
        for taskType in defaults {
            modelContext.insert(taskType)
        }
        
        do {
            try modelContext.save()
            fetchTaskTypes()
        } catch {
            print("Failed to create defaults: \(error)")
        }
    }
}

// MARK: - Task Type Row
struct TaskTypeRow: View {
    let taskType: TaskType
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon with color
                ZStack {
                    Circle()
                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: taskType.icon ?? "hammer.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(taskType.display)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 12) {
                        if taskType.isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(OPSStyle.Colors.primaryAccent.opacity(0.3))
                                .cornerRadius(4)
                        }
                        
                        Text("\(taskType.tasks.count) tasks")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Edit Task Type Sheet
struct EditTaskTypeSheet: View {
    let taskType: TaskType
    let onSave: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var selectedIcon: String
    
    let availableIcons = [
        // Construction & Tools
        "hammer.fill",
        "wrench.fill",
        "wrench.and.screwdriver.fill",
        "screwdriver.fill",
        "paintbrush.fill",
        "paintbrush.pointed.fill",
        "ruler.fill",
        "level.fill",
        "hammer.circle.fill",
        "wrench.adjustable.fill",
        
        // Electrical & Plumbing
        "bolt.fill",
        "bolt.circle.fill",
        "powerplug.fill",
        "lightbulb.fill",
        "lightbulb.led.fill",
        "drop.fill",
        "drop.circle.fill",
        "humidity.fill",
        "drop.triangle.fill",
        "flame.fill",
        
        // Documents & Planning
        "clipboard.fill",
        "doc.text.fill",
        "doc.on.clipboard.fill",
        "checklist",
        "list.clipboard.fill",
        "pencil.and.ruler.fill",
        "square.and.pencil",
        "tablecells.fill",
        
        // Building & Structure
        "house.fill",
        "house.circle.fill",
        "building.fill",
        "building.2.fill",
        "rectangle.portrait.split.2x1.fill",
        "door.left.hand.closed",
        "square.split.2x2.fill",
        "rectangle.split.3x3.fill",
        
        // Safety & Equipment
        "cone.fill",
        "exclamationmark.triangle.fill",
        "shield.fill",
        "cross.case.fill",
        "eyeglasses",
        "figure.walk",
        "ant.fill",
        
        // Inspection & Measurement
        "magnifyingglass",
        "magnifyingglass.circle.fill",
        "camera.fill",
        "thermometer.medium",
        "gauge.open.with.lines.needle.33percent",
        "speedometer",
        "ruler.fill",
        
        // Materials & Supplies
        "shippingbox.fill",
        "cube.box.fill",
        "archivebox.fill",
        "tray.full.fill",
        "cart.fill",
        "truck.box.fill",
        
        // Communication
        "phone.fill",
        "envelope.fill",
        "message.fill",
        "bubble.left.and.bubble.right.fill",
        "megaphone.fill",
        
        // Status & Completion
        "checkmark.circle.fill",
        "checkmark.square.fill",
        "clock.fill",
        "clock.arrow.circlepath",
        "hourglass",
        "calendar",
        "flag.fill",
        "star.fill"
    ]
    
    init(taskType: TaskType, onSave: @escaping () -> Void) {
        self.taskType = taskType
        self.onSave = onSave
        _selectedIcon = State(initialValue: taskType.icon ?? "hammer.fill")
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Preview card
                        VStack(spacing: 16) {
                            Text("PREVIEW")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                        .frame(width: 56, height: 56)
                                    
                                    Image(systemName: selectedIcon)
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(taskType.display)
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(.white)
                                    
                                    if taskType.isDefault {
                                        Text("DEFAULT TYPE")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                    
                                    Text("\(taskType.tasks.count) tasks using this type")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                                
                                Spacer()
                            }
                            .padding(20)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        
                        // Icon selection
                        VStack(alignment: .leading, spacing: 12) {
                            Label("SELECT ICON", systemImage: "star.square")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                                ForEach(availableIcons, id: \.self) { iconName in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedIcon = iconName
                                        }
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(selectedIcon == iconName ? 
                                                     OPSStyle.Colors.primaryAccent.opacity(0.2) : 
                                                     OPSStyle.Colors.cardBackgroundDark)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(selectedIcon == iconName ? 
                                                               OPSStyle.Colors.primaryAccent : 
                                                               Color.clear, lineWidth: 2)
                                                )
                                            
                                            Image(systemName: iconName)
                                                .font(.system(size: 24))
                                                .foregroundColor(selectedIcon == iconName ? 
                                                               OPSStyle.Colors.primaryAccent : 
                                                               OPSStyle.Colors.primaryText)
                                        }
                                        .frame(height: 56)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Change Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }
    
    private func saveChanges() {
        taskType.icon = selectedIcon
        taskType.needsSync = true
        
        do {
            try modelContext.save()
            onSave()
            dismiss()
        } catch {
            print("Failed to save task type icon change: \(error)")
        }
    }
}

// MARK: - Add Task Type Sheet
struct AddTaskTypeSettingsSheet: View {
    let onSave: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var displayName = ""
    @State private var selectedIcon = "hammer.fill"
    @State private var selectedColor = "#59779F"
    
    // Same available icons and colors as EditTaskTypeSheet
    let availableIcons = [
        "hammer.fill", "wrench.fill", "paintbrush.fill", "ruler.fill",
        "clipboard.fill", "doc.text.fill", "shippingbox.fill", "checkmark.circle.fill",
        "bolt.fill", "drop.fill", "house.fill", "magnifyingglass",
        "camera.fill", "phone.fill", "envelope.fill", "cart.fill"
    ]
    
    let availableColors = [
        "#59779F", "#A5B368", "#C4A868", "#931A32",
        "#7B68A6", "#EC4899", "#F97316", "#6B7280",
        "#10B981", "#8B5CF6", "#F59E0B", "#14B8A6"
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Preview
                        VStack(spacing: 16) {
                            Text("PREVIEW")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: selectedColor) ?? OPSStyle.Colors.primaryAccent)
                                        .frame(width: 56, height: 56)
                                    
                                    Image(systemName: selectedIcon)
                                        .font(.system(size: 28))
                                        .foregroundColor(.white)
                                }
                                
                                Text(displayName.isEmpty ? "New Task Type" : displayName)
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(.white)
                                
                                Spacer()
                            }
                            .padding(20)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        
                        // Form fields (similar to EditTaskTypeSheet)
                        VStack(alignment: .leading, spacing: 12) {
                            Label("DISPLAY NAME", systemImage: "textformat")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            TextField("Task Type Name", text: $displayName)
                                .textFieldStyle(OPSTextFieldStyle())
                        }
                        
                        // Icon grid
                        VStack(alignment: .leading, spacing: 12) {
                            Label("ICON", systemImage: "star.square")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                                ForEach(availableIcons, id: \.self) { iconName in
                                    Button {
                                        selectedIcon = iconName
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(selectedIcon == iconName ? 
                                                     OPSStyle.Colors.primaryAccent.opacity(0.2) : 
                                                     OPSStyle.Colors.cardBackgroundDark)
                                            
                                            Image(systemName: iconName)
                                                .font(.system(size: 24))
                                                .foregroundColor(selectedIcon == iconName ? 
                                                               OPSStyle.Colors.primaryAccent : 
                                                               OPSStyle.Colors.primaryText)
                                        }
                                        .frame(height: 48)
                                    }
                                }
                            }
                        }
                        
                        // Color grid
                        VStack(alignment: .leading, spacing: 12) {
                            Label("COLOR", systemImage: "paintpalette")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                                ForEach(availableColors, id: \.self) { hexColor in
                                    Button {
                                        selectedColor = hexColor
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: hexColor) ?? Color.gray)
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Circle()
                                                    .stroke(selectedColor == hexColor ? Color.white : Color.clear, lineWidth: 2)
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Task Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addTaskType()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(displayName.isEmpty)
                }
            }
        }
    }
    
    private func addTaskType() {
        guard let companyId = dataController.currentUser?.companyId else { return }
        
        // Get max display order
        let maxOrder = (try? modelContext.fetch(FetchDescriptor<TaskType>()))?
            .map { $0.displayOrder }
            .max() ?? 0
        
        let taskType = TaskType(
            id: UUID().uuidString,
            display: displayName,
            color: selectedColor,
            companyId: companyId,
            isDefault: false,
            icon: selectedIcon
        )
        taskType.displayOrder = maxOrder + 1
        
        modelContext.insert(taskType)
        
        do {
            try modelContext.save()
            onSave()
            dismiss()
        } catch {
            print("Failed to add task type: \(error)")
        }
    }
}
