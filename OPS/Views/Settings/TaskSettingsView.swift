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
                            ForEach(sortedTaskTypes) { taskType in
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
                        Image(systemName: OPSStyle.Icons.plusCircleFill)
                            .font(.system(size: 24))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            fetchTaskTypes()
            // If no task types found, try syncing from Bubble
            if taskTypes.isEmpty {
                syncTaskTypesFromBubble()
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let taskType = selectedTaskType {
                EditTaskTypeSheet(taskType: taskType) {
                    fetchTaskTypes()
                }
                .environmentObject(dataController)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskTypeDeleted"))) { _ in
            fetchTaskTypes()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddTaskTypeSettingsSheet {
                fetchTaskTypes()
            }
            .environmentObject(dataController)
        }
    }
    
    private var sortedTaskTypes: [TaskType] {
        let nonDefault = taskTypes.filter { !$0.isDefault }.sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
        let defaultTypes = taskTypes.filter { $0.isDefault }.sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
        return nonDefault + defaultTypes
    }

    private func fetchTaskTypes() {
        isLoading = true

        guard let companyId = dataController.currentUser?.companyId else {
            print("❌ No company ID found")
            isLoading = false
            return
        }

        print("🔍 Fetching task types for company: \(companyId)")

        do {
            // Fetch ALL task types first to see what's in the database
            let allDescriptor = FetchDescriptor<TaskType>()
            let allTaskTypes = try modelContext.fetch(allDescriptor)
            print("📊 Total task types in database: \(allTaskTypes.count)")
            for taskType in allTaskTypes {
                print("  - \(taskType.display) (companyId: \(taskType.companyId), isDefault: \(taskType.isDefault))")
            }

            // Now filter by company
            let predicate = #Predicate<TaskType> { taskType in
                taskType.companyId == companyId
            }

            let descriptor = FetchDescriptor<TaskType>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.displayOrder)]
            )
            let filteredTypes = try modelContext.fetch(descriptor)
            print("✅ Filtered task types for company: \(filteredTypes.count)")

            taskTypes = filteredTypes
            isLoading = false
        } catch {
            print("❌ Error fetching task types: \(error)")
            taskTypes = []
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
        }
    }

    private func syncTaskTypesFromBubble() {
        guard let companyId = dataController.currentUser?.companyId else { return }

        print("🔄 Syncing task types from Bubble for company: \(companyId)")

        Task {
            do {
                try await dataController.syncManager.syncCompanyTaskTypes(companyId: companyId)
                print("✅ Task types synced from Bubble")

                // Refresh the list on main thread
                await MainActor.run {
                    fetchTaskTypes()
                }
            } catch {
                print("❌ Failed to sync task types: \(error)")
            }
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

                    Text("\(taskType.tasks.count) tasks")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                if taskType.isDefault {
                    Text("DEFAULT")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(taskType.isDefault)
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
    @State private var taskTypeColor: Color
    @State private var taskTypeColorHex: String
    @State private var showingDeletionSheet = false
    @State private var existingTaskTypes: [TaskType] = []

    let availableIcons = [
        "checklist",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "paintbrush.fill",
        "ruler.fill",
        "level.fill",
        "screwdriver.fill",
        "wrench.fill",
        "eyedropper.halffull",
        "camera.fill",
        "doc.text.fill",
        "pencil.and.ruler.fill",
        "cpu.fill",
        "bolt.fill",
        "gear",
        "scissors",
        "trash.fill",
        "archivebox.fill",
        "shippingbox.fill",
        "cube.box.fill",
        "lightbulb.fill",
        "leaf.fill",
        "flame.fill",
        "drop.fill",
        "house.fill",
        "building.2.fill",
        "car.fill",
        "truck.box.fill",
        "ladybug.fill",
        "tree.fill",
        "photo.fill",
        "person.2.fill",
        "phone.fill",
        "envelope.fill",
        "calendar",
        "clock.fill",
        "tag.fill",
        "folder.fill",
        "checkmark.seal.fill",
        "exclamationmark.triangle.fill"
    ]

    let availableColors: [(color: Color, hex: String)] = [
        (Color(hex: "ceb4b4")!, "ceb4b4"),
        (Color(hex: "b59090")!, "b59090"),
        (Color(hex: "8c6868")!, "8c6868"),
        (Color(hex: "cebbb4")!, "cebbb4"),
        (Color(hex: "b59a90")!, "b59a90"),
        (Color(hex: "8c7168")!, "8c7168"),
        (Color(hex: "cec1b4")!, "cec1b4"),
        (Color(hex: "b5a390")!, "b5a390"),
        (Color(hex: "8c7a68")!, "8c7a68"),
        (Color(hex: "cec8b4")!, "cec8b4"),
        (Color(hex: "b5ac90")!, "b5ac90"),
        (Color(hex: "8c8368")!, "8c8368"),
        (Color(hex: "ceceb4")!, "ceceb4"),
        (Color(hex: "b5b590")!, "b5b590"),
        (Color(hex: "8c8c68")!, "8c8c68"),
        (Color(hex: "c8ceb4")!, "c8ceb4"),
        (Color(hex: "acb590")!, "acb590"),
        (Color(hex: "838c68")!, "838c68"),
        (Color(hex: "c1ceb4")!, "c1ceb4"),
        (Color(hex: "a3b590")!, "a3b590"),
        (Color(hex: "7a8c68")!, "7a8c68"),
        (Color(hex: "bbceb4")!, "bbceb4"),
        (Color(hex: "9ab590")!, "9ab590"),
        (Color(hex: "718c68")!, "718c68"),
        (Color(hex: "b4ceb4")!, "b4ceb4"),
        (Color(hex: "90b590")!, "90b590"),
        (Color(hex: "688c68")!, "688c68"),
        (Color(hex: "b4cebb")!, "b4cebb"),
        (Color(hex: "90b59a")!, "90b59a"),
        (Color(hex: "688c71")!, "688c71"),
        (Color(hex: "b4cec1")!, "b4cec1"),
        (Color(hex: "90b5a3")!, "90b5a3"),
        (Color(hex: "688c7a")!, "688c7a"),
        (Color(hex: "b4cec8")!, "b4cec8"),
        (Color(hex: "90b5ac")!, "90b5ac"),
        (Color(hex: "688c83")!, "688c83"),
        (Color(hex: "b4cece")!, "b4cece"),
        (Color(hex: "90b5b5")!, "90b5b5"),
        (Color(hex: "688c8c")!, "688c8c"),
        (Color(hex: "b4c8ce")!, "b4c8ce"),
        (Color(hex: "90acb5")!, "90acb5"),
        (Color(hex: "68838c")!, "68838c"),
        (Color(hex: "b4c1ce")!, "b4c1ce"),
        (Color(hex: "90a3b5")!, "90a3b5"),
        (Color(hex: "687a8c")!, "687a8c"),
        (Color(hex: "b4bbce")!, "b4bbce"),
        (Color(hex: "909ab5")!, "909ab5"),
        (Color(hex: "68718c")!, "68718c"),
        (Color(hex: "b4b4ce")!, "b4b4ce"),
        (Color(hex: "9090b5")!, "9090b5"),
        (Color(hex: "68688c")!, "68688c"),
        (Color(hex: "bbb4ce")!, "bbb4ce"),
        (Color(hex: "9a90b5")!, "9a90b5"),
        (Color(hex: "71688c")!, "71688c"),
        (Color(hex: "c1b4ce")!, "c1b4ce"),
        (Color(hex: "a390b5")!, "a390b5"),
        (Color(hex: "7a688c")!, "7a688c"),
        (Color(hex: "c8b4ce")!, "c8b4ce"),
        (Color(hex: "ac90b5")!, "ac90b5"),
        (Color(hex: "83688c")!, "83688c"),
        (Color(hex: "ceb4ce")!, "ceb4ce"),
        (Color(hex: "b590b5")!, "b590b5"),
        (Color(hex: "8c688c")!, "8c688c"),
        (Color(hex: "ceb4c8")!, "ceb4c8"),
        (Color(hex: "b590ac")!, "b590ac"),
        (Color(hex: "8c6883")!, "8c6883"),
        (Color(hex: "ceb4c1")!, "ceb4c1"),
        (Color(hex: "b590a3")!, "b590a3"),
        (Color(hex: "8c687a")!, "8c687a"),
        (Color(hex: "ceb4bb")!, "ceb4bb"),
        (Color(hex: "b5909a")!, "b5909a"),
        (Color(hex: "8c6871")!, "8c6871")
    ]

    init(taskType: TaskType, onSave: @escaping () -> Void) {
        self.taskType = taskType
        self.onSave = onSave
        _selectedIcon = State(initialValue: taskType.icon ?? "checklist")
        _taskTypeColorHex = State(initialValue: taskType.color)
        _taskTypeColor = State(initialValue: Color(hex: taskType.color) ?? Color(hex: "93A17C")!)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("PREVIEW")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            HStack {
                                Circle()
                                    .fill(taskTypeColor)
                                    .frame(width: 12, height: 12)

                                Image(systemName: selectedIcon)
                                    .font(.system(size: 16))
                                    .foregroundColor(taskTypeColor)

                                Text(taskType.display)
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                Spacer()
                            }
                            .padding(OPSStyle.Layout.spacing3)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(taskTypeColor.opacity(0.3), lineWidth: 1)
                            )
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("ICON")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: OPSStyle.Layout.spacing2) {
                                    ForEach(availableIcons, id: \.self) { icon in
                                        IconOption(
                                            icon: icon,
                                            isSelected: selectedIcon == icon,
                                            color: taskTypeColor,
                                            isInUse: existingTaskTypes.filter { $0.id != taskType.id }.contains { $0.icon == icon }
                                        ) {
                                            withAnimation(.spring(response: 0.3)) {
                                                selectedIcon = icon
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("COLOR")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: OPSStyle.Layout.spacing2) {
                                ForEach(availableColors, id: \.hex) { colorOption in
                                    ColorOption(
                                        color: colorOption.color,
                                        isSelected: taskTypeColorHex == colorOption.hex,
                                        isInUse: existingTaskTypes.filter { $0.id != taskType.id }.contains { $0.color == colorOption.hex }
                                    ) {
                                        withAnimation(.spring(response: 0.3)) {
                                            taskTypeColor = colorOption.color
                                            taskTypeColorHex = colorOption.hex
                                        }
                                    }
                                }
                            }
                        }

                        if !taskType.isDefault {
                            Button(action: { showingDeletionSheet = true }) {
                                HStack {
                                    Image(systemName: OPSStyle.Icons.trash)
                                        .font(.system(size: 16))
                                    Text("DELETE TASK TYPE")
                                        .font(OPSStyle.Typography.bodyBold)
                                }
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .frame(maxWidth: .infinity)
                                .padding(OPSStyle.Layout.spacing3)
                                .background(OPSStyle.Colors.errorStatus.opacity(0.1))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.errorStatus.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .padding(.top, OPSStyle.Layout.spacing3)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("EDIT TASK TYPE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("SAVE") { saveChanges() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .onAppear {
                loadExistingTaskTypes()
            }
        }
        .sheet(isPresented: $showingDeletionSheet) {
            TaskTypeDeletionSheet(
                taskType: taskType,
                onDeletionStarted: {
                    dismiss()
                }
            )
            .environmentObject(dataController)
        }
    }

    private func loadExistingTaskTypes() {
        let descriptor = FetchDescriptor<TaskType>()
        do {
            existingTaskTypes = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching task types: \(error)")
        }
    }

    private func saveChanges() {
        print("[TASK_TYPE_SAVE] 💾 Saving task type changes...")
        print("[TASK_TYPE_SAVE] Task Type: \(taskType.display)")

        // Track what changed
        let colorChanged = taskType.color != taskTypeColorHex
        let iconChanged = taskType.icon != selectedIcon

        print("[TASK_TYPE_SAVE] Color changed: \(colorChanged) (old: \(taskType.color), new: \(taskTypeColorHex))")
        print("[TASK_TYPE_SAVE] Icon changed: \(iconChanged) (old: \(taskType.icon ?? "nil"), new: \(selectedIcon))")

        // Update local values
        taskType.icon = selectedIcon
        taskType.color = taskTypeColorHex

        do {
            try modelContext.save()
            print("[TASK_TYPE_SAVE] ✅ Saved to local database")

            // Sync to Bubble immediately
            Task {
                do {
                    // Update task type in Bubble
                    print("[TASK_TYPE_SAVE] 📡 Updating task type in Bubble...")
                    try await dataController.apiService.updateTaskType(
                        id: taskType.id,
                        display: nil,  // Don't change display name
                        color: taskTypeColorHex,
                        icon: nil  // Icon doesn't exist in Bubble
                    )
                    print("[TASK_TYPE_SAVE] ✅ Task type updated in Bubble")

                    // If color changed, cascade update to all calendar events
                    if colorChanged {
                        print("[TASK_TYPE_SAVE] 🎨 Color changed - updating all task calendar events...")
                        try await updateCalendarEventsForTaskTypeColor(
                            taskTypeId: taskType.id,
                            newColor: taskTypeColorHex
                        )
                        print("[TASK_TYPE_SAVE] ✅ All calendar events updated")
                    }

                    await MainActor.run {
                        taskType.needsSync = false
                        try? modelContext.save()
                        print("[TASK_TYPE_SAVE] ✅ Sync complete")
                    }
                } catch {
                    print("[TASK_TYPE_SAVE] ❌ Failed to sync: \(error)")
                    await MainActor.run {
                        taskType.needsSync = true
                        try? modelContext.save()
                    }
                }
            }

            onSave()
            dismiss()
        } catch {
            print("[TASK_TYPE_SAVE] ❌ Failed to save locally: \(error)")
        }
    }

    private func updateCalendarEventsForTaskTypeColor(taskTypeId: String, newColor: String) async throws {
        print("[TASK_TYPE_COLOR_CASCADE] 🔍 Finding all tasks with task type: \(taskTypeId)")

        // Find all tasks that use this task type
        let taskDescriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate<ProjectTask> { task in
                task.taskType?.id == taskTypeId
            }
        )

        let tasks = try modelContext.fetch(taskDescriptor)
        print("[TASK_TYPE_COLOR_CASCADE] Found \(tasks.count) tasks using this task type")

        // Collect all calendar event IDs that need updating
        var calendarEventIds: [String] = []
        var calendarEventsToUpdate: [CalendarEvent] = []

        for task in tasks {
            if let calendarEvent = task.calendarEvent {
                calendarEventIds.append(calendarEvent.id)
                calendarEventsToUpdate.append(calendarEvent)
                print("[TASK_TYPE_COLOR_CASCADE] - Task '\(task.taskType?.display ?? "Unknown")' has calendar event: \(calendarEvent.id)")
            }
        }

        guard !calendarEventIds.isEmpty else {
            print("[TASK_TYPE_COLOR_CASCADE] No calendar events to update")
            return
        }

        print("[TASK_TYPE_COLOR_CASCADE] 📡 Updating \(calendarEventIds.count) calendar events in Bubble...")

        // Update each calendar event in Bubble
        for eventId in calendarEventIds {
            do {
                let colorWithHash = newColor.hasPrefix("#") ? newColor : "#\(newColor)"

                try await dataController.apiService.updateCalendarEvent(
                    id: eventId,
                    updates: [BubbleFields.CalendarEvent.color: colorWithHash]
                )
                print("[TASK_TYPE_COLOR_CASCADE] ✅ Updated calendar event: \(eventId)")
            } catch {
                print("[TASK_TYPE_COLOR_CASCADE] ⚠️ Failed to update calendar event \(eventId): \(error)")
            }
        }

        // Update local calendar events
        await MainActor.run {
            for calendarEvent in calendarEventsToUpdate {
                calendarEvent.color = newColor
                calendarEvent.needsSync = false
            }
            try? modelContext.save()
            print("[TASK_TYPE_COLOR_CASCADE] ✅ Updated \(calendarEventsToUpdate.count) local calendar events")
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
    @State private var selectedIcon = "checklist"
    @State private var taskTypeColor: Color = Color(hex: "93A17C")!
    @State private var taskTypeColorHex: String = "93A17C"
    @State private var existingTaskTypes: [TaskType] = []

    let availableIcons = [
        "checklist",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "paintbrush.fill",
        "ruler.fill",
        "level.fill",
        "screwdriver.fill",
        "wrench.fill",
        "eyedropper.halffull",
        "camera.fill",
        "doc.text.fill",
        "pencil.and.ruler.fill",
        "cpu.fill",
        "bolt.fill",
        "gear",
        "scissors",
        "trash.fill",
        "archivebox.fill",
        "shippingbox.fill",
        "cube.box.fill",
        "lightbulb.fill",
        "leaf.fill",
        "flame.fill",
        "drop.fill",
        "house.fill",
        "building.2.fill",
        "car.fill",
        "truck.box.fill",
        "ladybug.fill",
        "tree.fill",
        "photo.fill",
        "person.2.fill",
        "phone.fill",
        "envelope.fill",
        "calendar",
        "clock.fill",
        "tag.fill",
        "folder.fill",
        "checkmark.seal.fill",
        "exclamationmark.triangle.fill"
    ]

    let availableColors: [(color: Color, hex: String)] = [
        (Color(hex: "ceb4b4")!, "ceb4b4"),
        (Color(hex: "b59090")!, "b59090"),
        (Color(hex: "8c6868")!, "8c6868"),
        (Color(hex: "cebbb4")!, "cebbb4"),
        (Color(hex: "b59a90")!, "b59a90"),
        (Color(hex: "8c7168")!, "8c7168"),
        (Color(hex: "cec1b4")!, "cec1b4"),
        (Color(hex: "b5a390")!, "b5a390"),
        (Color(hex: "8c7a68")!, "8c7a68"),
        (Color(hex: "cec8b4")!, "cec8b4"),
        (Color(hex: "b5ac90")!, "b5ac90"),
        (Color(hex: "8c8368")!, "8c8368"),
        (Color(hex: "ceceb4")!, "ceceb4"),
        (Color(hex: "b5b590")!, "b5b590"),
        (Color(hex: "8c8c68")!, "8c8c68"),
        (Color(hex: "c8ceb4")!, "c8ceb4"),
        (Color(hex: "acb590")!, "acb590"),
        (Color(hex: "838c68")!, "838c68"),
        (Color(hex: "c1ceb4")!, "c1ceb4"),
        (Color(hex: "a3b590")!, "a3b590"),
        (Color(hex: "7a8c68")!, "7a8c68"),
        (Color(hex: "bbceb4")!, "bbceb4"),
        (Color(hex: "9ab590")!, "9ab590"),
        (Color(hex: "718c68")!, "718c68"),
        (Color(hex: "b4ceb4")!, "b4ceb4"),
        (Color(hex: "90b590")!, "90b590"),
        (Color(hex: "688c68")!, "688c68"),
        (Color(hex: "b4cebb")!, "b4cebb"),
        (Color(hex: "90b59a")!, "90b59a"),
        (Color(hex: "688c71")!, "688c71"),
        (Color(hex: "b4cec1")!, "b4cec1"),
        (Color(hex: "90b5a3")!, "90b5a3"),
        (Color(hex: "688c7a")!, "688c7a"),
        (Color(hex: "b4cec8")!, "b4cec8"),
        (Color(hex: "90b5ac")!, "90b5ac"),
        (Color(hex: "688c83")!, "688c83"),
        (Color(hex: "b4cece")!, "b4cece"),
        (Color(hex: "90b5b5")!, "90b5b5"),
        (Color(hex: "688c8c")!, "688c8c"),
        (Color(hex: "b4c8ce")!, "b4c8ce"),
        (Color(hex: "90acb5")!, "90acb5"),
        (Color(hex: "68838c")!, "68838c"),
        (Color(hex: "b4c1ce")!, "b4c1ce"),
        (Color(hex: "90a3b5")!, "90a3b5"),
        (Color(hex: "687a8c")!, "687a8c"),
        (Color(hex: "b4bbce")!, "b4bbce"),
        (Color(hex: "909ab5")!, "909ab5"),
        (Color(hex: "68718c")!, "68718c"),
        (Color(hex: "b4b4ce")!, "b4b4ce"),
        (Color(hex: "9090b5")!, "9090b5"),
        (Color(hex: "68688c")!, "68688c"),
        (Color(hex: "bbb4ce")!, "bbb4ce"),
        (Color(hex: "9a90b5")!, "9a90b5"),
        (Color(hex: "71688c")!, "71688c"),
        (Color(hex: "c1b4ce")!, "c1b4ce"),
        (Color(hex: "a390b5")!, "a390b5"),
        (Color(hex: "7a688c")!, "7a688c"),
        (Color(hex: "c8b4ce")!, "c8b4ce"),
        (Color(hex: "ac90b5")!, "ac90b5"),
        (Color(hex: "83688c")!, "83688c"),
        (Color(hex: "ceb4ce")!, "ceb4ce"),
        (Color(hex: "b590b5")!, "b590b5"),
        (Color(hex: "8c688c")!, "8c688c"),
        (Color(hex: "ceb4c8")!, "ceb4c8"),
        (Color(hex: "b590ac")!, "b590ac"),
        (Color(hex: "8c6883")!, "8c6883"),
        (Color(hex: "ceb4c1")!, "ceb4c1"),
        (Color(hex: "b590a3")!, "b590a3"),
        (Color(hex: "8c687a")!, "8c687a"),
        (Color(hex: "ceb4bb")!, "ceb4bb"),
        (Color(hex: "b5909a")!, "b5909a"),
        (Color(hex: "8c6871")!, "8c6871")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 32) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("PREVIEW")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            HStack {
                                Circle()
                                    .fill(taskTypeColor)
                                    .frame(width: 12, height: 12)

                                Image(systemName: selectedIcon)
                                    .font(.system(size: 16))
                                    .foregroundColor(taskTypeColor)

                                Text(displayName.isEmpty ? "Task Type Name" : displayName)
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                Spacer()
                            }
                            .padding(OPSStyle.Layout.spacing3)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(taskTypeColor.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("TASK TYPE NAME *")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            TextField("Enter task type name", text: $displayName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("ICON")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: OPSStyle.Layout.spacing2) {
                                    ForEach(availableIcons, id: \.self) { icon in
                                        IconOption(
                                            icon: icon,
                                            isSelected: selectedIcon == icon,
                                            color: taskTypeColor,
                                            isInUse: existingTaskTypes.contains { $0.icon == icon }
                                        ) {
                                            withAnimation(.spring(response: 0.3)) {
                                                selectedIcon = icon
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("COLOR")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: OPSStyle.Layout.spacing2) {
                                ForEach(availableColors, id: \.hex) { colorOption in
                                    ColorOption(
                                        color: colorOption.color,
                                        isSelected: taskTypeColorHex == colorOption.hex,
                                        isInUse: existingTaskTypes.contains { $0.color == colorOption.hex }
                                    ) {
                                        withAnimation(.spring(response: 0.3)) {
                                            taskTypeColor = colorOption.color
                                            taskTypeColorHex = colorOption.hex
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("NEW TASK TYPE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("SAVE") { addTaskType() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .disabled(displayName.isEmpty)
                }
            }
            .onAppear {
                loadExistingTaskTypes()
            }
        }
    }

    private func loadExistingTaskTypes() {
        let descriptor = FetchDescriptor<TaskType>()
        do {
            existingTaskTypes = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching task types: \(error)")
        }
    }

    private func addTaskType() {
        guard let companyId = dataController.currentUser?.companyId else { return }

        let maxOrder = (try? modelContext.fetch(FetchDescriptor<TaskType>()))?
            .map { $0.displayOrder }
            .max() ?? 0

        let taskType = TaskType(
            id: UUID().uuidString,
            display: displayName,
            color: taskTypeColorHex,
            companyId: companyId,
            isDefault: false,
            icon: selectedIcon
        )
        taskType.displayOrder = maxOrder + 1

        modelContext.insert(taskType)

        do {
            try modelContext.save()

            Task {
                do {
                    let colorWithHash = taskType.color.hasPrefix("#") ? taskType.color : "#\(taskType.color)"

                    let dto = TaskTypeDTO(
                        id: taskType.id,
                        color: colorWithHash,
                        display: taskType.display,
                        isDefault: taskType.isDefault,
                        createdDate: nil,
                        modifiedDate: nil
                    )

                    let createdDTO = try await dataController.apiService.createTaskType(dto)

                    await MainActor.run {
                        taskType.id = createdDTO.id
                        taskType.needsSync = false
                        try? modelContext.save()
                    }

                    try await dataController.apiService.linkTaskTypeToCompany(
                        companyId: companyId,
                        taskTypeId: createdDTO.id
                    )
                } catch {
                    await MainActor.run {
                        taskType.needsSync = true
                        try? modelContext.save()
                    }
                }
            }

            onSave()
            dismiss()
        } catch {
        }
    }
}
