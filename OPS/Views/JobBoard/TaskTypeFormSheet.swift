//
//  TaskTypeFormSheet.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//

import SwiftUI
import SwiftData

struct TaskTypeFormSheet: View {
    let onSave: (TaskType) -> Void

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
        // Purple-Pinks
        (Color(hex: "ceb4c8")!, "ceb4c8"),
        (Color(hex: "b590ac")!, "b590ac"),
        (Color(hex: "8c6883")!, "8c6883"),
        (Color(hex: "ceb4c1")!, "ceb4c1"),
        (Color(hex: "b590a3")!, "b590a3"),
        (Color(hex: "8c687a")!, "8c687a")
    ]

    private var isValid: Bool {
        !taskTypeName.isEmpty
    }

    // MARK: - Preview Card
    private var previewCard: some View {
        ZStack {
            HStack(spacing: 0) {
                // Colored left border (4pt width)
                Rectangle()
                    .fill(taskTypeColor)
                    .frame(width: 4)

                // Main content area
                VStack(alignment: .leading, spacing: 8) {
                    // Task type name (title)
                    Text(taskTypeName.isEmpty ? "ENTER TASK TYPE NAME" : taskTypeName.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(taskTypeName.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Metadata row
                    HStack(spacing: 12) {
                        // Calendar icon + dash
                        HStack(spacing: 4) {
                            Image(systemName: OPSStyle.Icons.calendar)
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("—")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }

                        // Team icon + 0
                        HStack(spacing: 4) {
                            Image(systemName: OPSStyle.Icons.personTwo)
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("0")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }

                        Spacer()
                    }
                }
                .padding(14)
            }

            // Status badge overlay - top right
            VStack {
                HStack {
                    Spacer()

                    Text("BOOKED")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(OPSStyle.Colors.primaryAccent.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                        .padding(.trailing, 8)
                        .padding(.top, 8)
                }
                Spacer()
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TASK TYPE NAME")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField("Enter task type name", text: $taskTypeName)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.words)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        }
    }

    private var iconField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ICON")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableIcons, id: \.self) { icon in
                        IconOption(
                            icon: icon,
                            isSelected: taskTypeIcon == icon,
                            color: taskTypeColor,
                            isInUse: existingTaskTypes.contains { $0.icon == icon }
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                taskTypeIcon = icon
                            }
                        }
                    }
                }
            }
        }
    }

    private var colorField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COLOR")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
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

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text("Creating Task Type...")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

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
                    Text("CREATE TASK TYPE")
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
            loadExistingTaskTypes()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    private func loadExistingTaskTypes() {
        guard let companyId = dataController.currentUser?.companyId else {
            print("[TASK_TYPE_FORM] ⚠️ No company ID found, cannot load existing task types")
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
            print("[TASK_TYPE_FORM] 📋 Loaded \(existingTaskTypes.count) existing task types")
            print("[TASK_TYPE_FORM] 📋 Icons in use: \(existingTaskTypes.compactMap { $0.icon })")
            print("[TASK_TYPE_FORM] 📋 Colors in use: \(existingTaskTypes.map { $0.color })")
        } catch {
            print("[TASK_TYPE_FORM] ❌ Error fetching task types: \(error)")
        }
    }

    private func saveTaskType() {
        guard let companyId = dataController.currentUser?.companyId else {
            print("[TASK_TYPE_FORM] ❌ No company ID found")
            errorMessage = "No company ID found"
            showingError = true
            return
        }

        print("[TASK_TYPE_FORM] 🔵 Starting task type creation")
        print("[TASK_TYPE_FORM] Name: \(taskTypeName)")
        print("[TASK_TYPE_FORM] Color: \(taskTypeColorHex)")
        print("[TASK_TYPE_FORM] Icon: \(taskTypeIcon)")
        print("[TASK_TYPE_FORM] Company ID: \(companyId)")

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

                print("[TASK_TYPE_FORM] 📤 Sending to Bubble API...")
                let createdTaskType = try await dataController.apiService.createTaskType(tempTaskType)
                print("[TASK_TYPE_FORM] ✅ Bubble created task type with ID: \(createdTaskType.id)")

                // Link task type to company
                print("[TASK_TYPE_FORM] 🔗 Linking task type to company...")
                try await dataController.apiService.linkTaskTypeToCompany(
                    companyId: companyId,
                    taskTypeId: createdTaskType.id
                )
                print("[TASK_TYPE_FORM] ✅ Task type linked to company")

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

                    print("[TASK_TYPE_FORM] 💾 Saving to local database...")
                    modelContext.insert(newTaskType)

                    do {
                        try modelContext.save()
                        print("[TASK_TYPE_FORM] ✅ Local save successful")
                        print("[TASK_TYPE_FORM] 🎉 Task type created: \(createdTaskType.id)")

                        // Success haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)

                        onSave(newTaskType)

                        // Brief delay for graceful dismissal
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    } catch {
                        print("[TASK_TYPE_FORM] ❌ Local save failed: \(error)")

                        // Error haptic feedback
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.error)

                        errorMessage = error.localizedDescription
                        showingError = true
                        isSaving = false
                    }
                }
            } catch {
                print("[TASK_TYPE_FORM] ❌ API creation failed: \(error)")
                await MainActor.run {
                    // Error haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)

                    errorMessage = "Failed to create task type: \(error.localizedDescription)"
                    showingError = true
                    isSaving = false
                }
            }
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
                                        isSelected ? color.opacity(0.3) : (isInUse && !isSelected ? Color.white : Color.white.opacity(0.1)),
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