//
//  TaskTypeSheet.swift
//  OPS
//
//  Unified sheet for creating and editing task types
//  Replaces TaskTypeFormSheet and TaskTypeEditSheet
//

import SwiftUI
import SwiftData

struct TaskTypeSheet: View {
    // MARK: - Mode Configuration

    enum Mode {
        case create(onSave: (TaskType) -> Void)
        case edit(taskType: TaskType, onSave: () -> Void)

        var title: String {
            switch self {
            case .create: return "CREATE TASK TYPE"
            case .edit: return "EDIT TASK TYPE"
            }
        }

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    // MARK: - Properties

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    // Form State
    @State private var taskTypeName: String = ""
    @State private var taskTypeIcon: String = "checklist"
    @State private var taskTypeColor: Color = Color(hex: "93A17C")!
    @State private var taskTypeColorHex: String = "93A17C"
    @State private var isDefault: Bool = false

    // Loading state
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var existingTaskTypes: [TaskType] = []

    private let availableIcons = [
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

    private let availableColors: [(color: Color, hex: String)] = [
        // Reds/Pinks
        (Color(hex: "ceb4b4")!, "ceb4b4"),
        (Color(hex: "b59090")!, "b59090"),
        (Color(hex: "8c6868")!, "8c6868"),
        (Color(hex: "ceb4bb")!, "ceb4bb"),
        (Color(hex: "b5909a")!, "b5909a"),
        (Color(hex: "8c6871")!, "8c6871"),
        // Oranges
        (Color(hex: "cebbb4")!, "cebbb4"),
        (Color(hex: "b59a90")!, "b59a90"),
        (Color(hex: "8c7168")!, "8c7168"),
        (Color(hex: "cec1b4")!, "cec1b4"),
        (Color(hex: "b5a390")!, "b5a390"),
        (Color(hex: "8c7a68")!, "8c7a68"),
        // Yellows/Tans
        (Color(hex: "cec8b4")!, "cec8b4"),
        (Color(hex: "b5ac90")!, "b5ac90"),
        (Color(hex: "8c8368")!, "8c8368"),
        (Color(hex: "ceceb4")!, "ceceb4"),
        (Color(hex: "b5b590")!, "b5b590"),
        (Color(hex: "8c8c68")!, "8c8c68"),
        // Yellow-Greens
        (Color(hex: "c8ceb4")!, "c8ceb4"),
        (Color(hex: "acb590")!, "acb590"),
        (Color(hex: "838c68")!, "838c68"),
        (Color(hex: "c1ceb4")!, "c1ceb4"),
        (Color(hex: "a3b590")!, "a3b590"),
        (Color(hex: "7a8c68")!, "7a8c68"),
        // Greens
        (Color(hex: "bbceb4")!, "bbceb4"),
        (Color(hex: "9ab590")!, "9ab590"),
        (Color(hex: "718c68")!, "718c68"),
        (Color(hex: "b4ceb4")!, "b4ceb4"),
        (Color(hex: "90b590")!, "90b590"),
        (Color(hex: "688c68")!, "688c68"),
        // Green-Cyans
        (Color(hex: "b4cebb")!, "b4cebb"),
        (Color(hex: "90b59a")!, "90b59a"),
        (Color(hex: "688c71")!, "688c71"),
        (Color(hex: "b4cec1")!, "b4cec1"),
        (Color(hex: "90b5a3")!, "90b5a3"),
        (Color(hex: "688c7a")!, "688c7a"),
        // Cyans
        (Color(hex: "b4cec8")!, "b4cec8"),
        (Color(hex: "90b5ac")!, "90b5ac"),
        (Color(hex: "688c83")!, "688c83"),
        (Color(hex: "b4cece")!, "b4cece"),
        (Color(hex: "90b5b5")!, "90b5b5"),
        (Color(hex: "688c8c")!, "688c8c"),
        // Cyan-Blues
        (Color(hex: "b4c8ce")!, "b4c8ce"),
        (Color(hex: "90acb5")!, "90acb5"),
        (Color(hex: "68838c")!, "68838c"),
        (Color(hex: "b4c1ce")!, "b4c1ce"),
        (Color(hex: "90a3b5")!, "90a3b5"),
        (Color(hex: "687a8c")!, "687a8c"),
        // Blues
        (Color(hex: "b4bbce")!, "b4bbce"),
        (Color(hex: "909ab5")!, "909ab5"),
        (Color(hex: "68718c")!, "68718c"),
        (Color(hex: "b4b4ce")!, "b4b4ce"),
        (Color(hex: "9090b5")!, "9090b5"),
        (Color(hex: "68688c")!, "68688c"),
        // Blue-Purples
        (Color(hex: "bbb4ce")!, "bbb4ce"),
        (Color(hex: "9a90b5")!, "9a90b5"),
        (Color(hex: "71688c")!, "71688c"),
        (Color(hex: "c1b4ce")!, "c1b4ce"),
        (Color(hex: "a390b5")!, "a390b5"),
        (Color(hex: "7a688c")!, "7a688c"),
        // Purples
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

    private var isValid: Bool {
        !taskTypeName.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Preview card at top
                        previewCard

                        // Task Type Details section
                        ExpandableSection(
                            title: "TASK TYPE DETAILS",
                            icon: "tag.fill",
                            isExpanded: .constant(true),
                            onDelete: nil
                        ) {
                            VStack(spacing: 16) {
                                // Name Field
                                nameField

                                // Icon Selection
                                iconField

                                // Color Selection
                                colorField
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 100)
                }

                if isSaving {
                    savingOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                ToolbarItem(placement: .principal) {
                    Text(mode.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("SAVE") {
                        saveTaskType()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(isValid && !isSaving ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .disabled(!isValid || isSaving)
                }
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            // Load existing data if editing
            if case .edit(let taskType, _) = mode {
                taskTypeName = taskType.display
                taskTypeIcon = taskType.icon ?? "checklist"
                taskTypeColorHex = taskType.color
                if let color = Color(hex: taskType.color) {
                    taskTypeColor = color
                }
            }
            loadExistingTaskTypes()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    // MARK: - View Components

    private var previewCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: taskTypeIcon)
                    .font(.system(size: 28))
                    .foregroundColor(taskTypeColor)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(taskTypeColor.opacity(0.2))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("PREVIEW")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(taskTypeName.isEmpty ? "Task Type Name" : taskTypeName)
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                Spacer()
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField("Enter task type name", text: $taskTypeName)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                )
        }
    }

    private var iconField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ICON")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(availableIcons, id: \.self) { icon in
                    IconOption(
                        icon: icon,
                        isSelected: taskTypeIcon == icon,
                        color: taskTypeColor,
                        isInUse: existingTaskTypes.contains(where: { $0.icon == icon }),
                        action: {
                            taskTypeIcon = icon
                        }
                    )
                }
            }
        }
    }

    private var colorField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COLOR")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 8), spacing: 12) {
                ForEach(availableColors.indices, id: \.self) { index in
                    let colorPair = availableColors[index]
                    ColorOption(
                        color: colorPair.color,
                        isSelected: taskTypeColorHex == colorPair.hex,
                        isInUse: existingTaskTypes.contains(where: { $0.color == colorPair.hex }),
                        action: {
                            taskTypeColor = colorPair.color
                            taskTypeColorHex = colorPair.hex
                        }
                    )
                }
            }
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(OPSStyle.Colors.primaryAccent)

                Text("Saving...")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .padding(32)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Methods

    private func loadExistingTaskTypes() {
        guard let companyId = dataController.currentUser?.companyId else {
            print("[TASK_TYPE_SHEET] ⚠️ No company ID found, cannot load existing task types")
            return
        }

        // Fetch only non-deleted task types for the current company
        var descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { taskType in
                taskType.companyId == companyId && taskType.deletedAt == nil
            }
        )

        do {
            existingTaskTypes = try modelContext.fetch(descriptor)
            print("[TASK_TYPE_SHEET] 📋 Loaded \(existingTaskTypes.count) existing task types")
            print("[TASK_TYPE_SHEET] 📋 Icons in use: \(existingTaskTypes.compactMap { $0.icon })")
            print("[TASK_TYPE_SHEET] 📋 Colors in use: \(existingTaskTypes.map { $0.color })")
        } catch {
            print("[TASK_TYPE_SHEET] ❌ Error fetching task types: \(error)")
        }
    }

    private func saveTaskType() {
        switch mode {
        case .create(let onSave):
            saveNewTaskType(onSave: onSave)

        case .edit(let taskType, let onSave):
            saveEditedTaskType(taskType: taskType, onSave: onSave)
        }
    }

    private func saveNewTaskType(onSave: @escaping (TaskType) -> Void) {
        guard let companyId = dataController.currentUser?.companyId else {
            print("[TASK_TYPE_SHEET] ❌ No company ID found")
            errorMessage = "No company ID found"
            showingError = true
            return
        }

        print("[TASK_TYPE_SHEET] 🔵 Starting task type creation")
        print("[TASK_TYPE_SHEET] Name: \(taskTypeName)")
        print("[TASK_TYPE_SHEET] Color: \(taskTypeColorHex)")
        print("[TASK_TYPE_SHEET] Icon: \(taskTypeIcon)")
        print("[TASK_TYPE_SHEET] Company ID: \(companyId)")

        isSaving = true

        Task {
            do {
                // Create task type on Bubble API first to get the real ID
                let tempTaskType = TaskTypeDTO(
                    id: UUID().uuidString,
                    color: taskTypeColorHex,
                    display: taskTypeName,
                    isDefault: false,
                    createdDate: nil,
                    modifiedDate: nil
                )

                print("[TASK_TYPE_SHEET] 📤 Sending to Bubble API...")
                let createdTaskType = try await dataController.apiService.createTaskType(tempTaskType)
                print("[TASK_TYPE_SHEET] ✅ Bubble created task type with ID: \(createdTaskType.id)")

                // Link task type to company
                print("[TASK_TYPE_SHEET] 🔗 Linking task type to company...")
                try await dataController.apiService.linkTaskTypeToCompany(
                    companyId: companyId,
                    taskTypeId: createdTaskType.id
                )
                print("[TASK_TYPE_SHEET] ✅ Task type linked to company")

                // Now create locally with the Bubble ID
                await MainActor.run {
                    let newTaskType = TaskType(
                        id: createdTaskType.id,
                        display: taskTypeName,
                        color: taskTypeColorHex,
                        companyId: companyId,
                        isDefault: false,
                        icon: taskTypeIcon
                    )

                    print("[TASK_TYPE_SHEET] 💾 Saving to local database...")
                    modelContext.insert(newTaskType)

                    do {
                        try modelContext.save()
                        print("[TASK_TYPE_SHEET] ✅ Local save successful")
                        print("[TASK_TYPE_SHEET] 🎉 Task type created: \(createdTaskType.id)")

                        // Success haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)

                        onSave(newTaskType)

                        // Brief delay for graceful dismissal
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    } catch {
                        print("[TASK_TYPE_SHEET] ❌ Local save failed: \(error)")

                        // Error haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.error)

                        errorMessage = error.localizedDescription
                        showingError = true
                        isSaving = false
                    }
                }
            } catch {
                await MainActor.run {
                    print("[TASK_TYPE_SHEET] ❌ Failed to create task type: \(error)")

                    // Error haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)

                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
            }
        }
    }

    private func saveEditedTaskType(taskType: TaskType, onSave: @escaping () -> Void) {
        isSaving = true

        Task {
            await MainActor.run {
                taskType.display = taskTypeName
                taskType.icon = taskTypeIcon
                taskType.color = taskTypeColorHex
                taskType.needsSync = true

                do {
                    try modelContext.save()

                    // Success haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    onSave()

                    // Brief delay for graceful dismissal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                } catch {
                    // Error haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)

                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
            }

            dataController.syncManager?.triggerBackgroundSync()
        }
    }
}

// MARK: - Supporting Views

struct IconOption: View {
    let icon: String
    let isSelected: Bool
    let color: Color
    var isInUse: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? color : OPSStyle.Colors.secondaryText)
                    .opacity(isInUse && !isSelected ? 0.3 : 1.0)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isSelected ? color.opacity(0.1) : OPSStyle.Colors.cardBackgroundDark)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isSelected ? color.opacity(0.3) : (isInUse && !isSelected ? Color.white : OPSStyle.Colors.cardBorder),
                                        lineWidth: isInUse && !isSelected ? 2 : 1
                                    )
                            )
                    )

                if isInUse && !isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color.white)
                                .background(
                                    Circle()
                                        .fill(OPSStyle.Colors.background)
                                        .frame(width: 14, height: 14)
                                )
                        }
                        Spacer()
                    }
                    .padding(2)
                }
            }
        }
    }
}

struct ColorOption: View {
    let color: Color
    let isSelected: Bool
    var isInUse: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .opacity(isInUse && !isSelected ? 0.3 : 1.0)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
                    )
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.5), lineWidth: isSelected ? 4 : 0)
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                isInUse && !isSelected ? Color.white : Color.clear,
                                lineWidth: isInUse && !isSelected ? 2 : 0
                            )
                    )
                    .scaleEffect(isSelected ? 1.1 : 1.0)

                if isInUse && !isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color.white)
                                .background(
                                    Circle()
                                        .fill(OPSStyle.Colors.background)
                                        .frame(width: 12, height: 12)
                                )
                        }
                        Spacer()
                    }
                    .padding(1)
                }
            }
        }
    }
}
