//
//  TaskTypesDebugView.swift
//  OPS
//
//  Debug view for managing task types
//

import SwiftUI
import SwiftData

struct TaskTypesDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var taskTypes: [TaskType] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingAddTaskType = false
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    
                    Spacer()
                    
                    Text("Task Types")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { showingAddTaskType = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading task types...")
                        .foregroundColor(.white)
                    Spacer()
                } else if taskTypes.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 50))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("No Task Types")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        Text("Tap + to create default task types")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(taskTypes.sorted { $0.displayOrder < $1.displayOrder }) { taskType in
                                TaskTypeCard(taskType: taskType)
                            }
                        }
                        .padding()
                    }
                }
                
                // Action bar
                HStack {
                    Text("\(taskTypes.count) task types")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Spacer()
                    
                    Button("Create Defaults") {
                        createDefaultTaskTypes()
                    }
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
            }
        }
        .onAppear {
            fetchTaskTypes()
        }
        .sheet(isPresented: $showingAddTaskType) {
            AddTaskTypeSheet()
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
            errorMessage = "Failed to fetch task types: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func createDefaultTaskTypes() {
        guard let companyId = dataController.currentUser?.companyId else {
            errorMessage = "No company ID found"
            return
        }
        
        let defaults = TaskType.createDefaults(companyId: companyId)
        for taskType in defaults {
            modelContext.insert(taskType)
        }
        
        do {
            try modelContext.save()
            fetchTaskTypes()
        } catch {
            errorMessage = "Failed to create defaults: \(error.localizedDescription)"
        }
    }
}

// Task type card
struct TaskTypeCard: View {
    let taskType: TaskType
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon and color
            ZStack {
                Circle()
                    .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                    .frame(width: 40, height: 40)
                
                if let icon = taskType.icon {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(taskType.display)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Text("ID: \(taskType.id)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                    
                    if taskType.isDefault {
                        Text("DEFAULT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            Text("\(taskType.tasks.count) tasks")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// Add task type sheet
struct AddTaskTypeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var display = ""
    @State private var color = "#59779F"
    @State private var icon = "hammer.fill"
    
    let availableIcons = [
        "hammer.fill",
        "wrench.fill",
        "paintbrush.fill",
        "ruler.fill",
        "clipboard.fill",
        "doc.text.fill",
        "shippingbox.fill",
        "checkmark.circle.fill"
    ]
    
    let availableColors = [
        "#59779F", // Blue
        "#A5B368", // Green
        "#C4A868", // Amber
        "#931A32", // Red
        "#8B5CF6", // Purple
        "#EC4899", // Pink
        "#F97316", // Orange
        "#6B7280"  // Gray
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Display name
                        VStack(alignment: .leading, spacing: 8) {
                            Label("NAME", systemImage: "textformat")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            TextField("Task Type Name", text: $display)
                                .textFieldStyle(OPSTextFieldStyle())
                        }
                        
                        // Color selection
                        VStack(alignment: .leading, spacing: 8) {
                            Label("COLOR", systemImage: "paintpalette")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                                ForEach(availableColors, id: \.self) { hexColor in
                                    Button {
                                        color = hexColor
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: hexColor) ?? Color.gray)
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Circle()
                                                    .stroke(color == hexColor ? Color.white : Color.clear, lineWidth: 2)
                                            )
                                    }
                                }
                            }
                        }
                        
                        // Icon selection
                        VStack(alignment: .leading, spacing: 8) {
                            Label("ICON", systemImage: "star.square")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                                ForEach(availableIcons, id: \.self) { iconName in
                                    Button {
                                        icon = iconName
                                    } label: {
                                        Image(systemName: iconName)
                                            .font(.system(size: 24))
                                            .foregroundColor(icon == iconName ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)
                                            .frame(width: 40, height: 40)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(icon == iconName ? OPSStyle.Colors.cardBackground : OPSStyle.Colors.cardBackgroundDark)
                                            )
                                    }
                                }
                            }
                        }
                        
                        // Preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PREVIEW")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: color) ?? OPSStyle.Colors.primaryAccent)
                                        .frame(width: 48, height: 48)
                                    
                                    Image(systemName: icon)
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                }
                                
                                Text(display.isEmpty ? "Task Type Name" : display)
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(.white)
                                
                                Spacer()
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                    }
                    .padding()
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
                    .disabled(display.isEmpty)
                }
            }
        }
    }
    
    private func addTaskType() {
        guard let companyId = dataController.currentUser?.companyId else { return }
        
        let taskType = TaskType(
            id: UUID().uuidString,
            display: display,
            color: color,
            companyId: companyId,
            isDefault: false,
            icon: icon
        )
        
        modelContext.insert(taskType)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving task type: \(error)")
        }
    }
}

// OPS text field style
struct OPSTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .foregroundColor(.white)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

#Preview {
    TaskTypesDebugView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}