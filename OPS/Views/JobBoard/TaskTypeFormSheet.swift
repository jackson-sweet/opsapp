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

    private var isValid: Bool {
        !taskTypeName.isEmpty
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "New Task Type",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        // Name Field
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("TASK TYPE NAME *")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            TextField("Enter task type name", text: $taskTypeName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(12)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }

                        // Icon Selection
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("ICON")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: OPSStyle.Layout.spacing2) {
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

                        // Color Selection
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

                        // Preview
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("PREVIEW")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            HStack {
                                Circle()
                                    .fill(taskTypeColor)
                                    .frame(width: 12, height: 12)

                                Image(systemName: taskTypeIcon)
                                    .font(.system(size: 16))
                                    .foregroundColor(taskTypeColor)

                                Text(taskTypeName.isEmpty ? "Task Type Name" : taskTypeName)
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
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }

                HStack {
                    Spacer()

                    Button("SAVE") {
                        saveTaskType()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(isValid && !isSaving ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .disabled(!isValid || isSaving)

                    Spacer()
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
            }
        }
        .navigationBarHidden(true)
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
        let descriptor = FetchDescriptor<TaskType>()
        do {
            existingTaskTypes = try modelContext.fetch(descriptor)
        } catch {
            print("Error fetching task types: \(error)")
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
                        onSave(newTaskType)
                        dismiss()
                    } catch {
                        print("[TASK_TYPE_FORM] ❌ Local save failed: \(error)")
                        errorMessage = error.localizedDescription
                        showingError = true
                        isSaving = false
                    }
                }
            } catch {
                print("[TASK_TYPE_FORM] ❌ API creation failed: \(error)")
                await MainActor.run {
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
                                        isSelected ? color.opacity(0.3) : Color.white.opacity(0.1),
                                        lineWidth: 1
                                    )
                            )
                    )

                if isInUse && !isSelected {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(OPSStyle.Colors.tertiaryText)
                                .frame(width: 8, height: 8)
                                .padding(4)
                        }
                    }
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
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                    )
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.5), lineWidth: isSelected ? 5 : 0)
                    )
                    .scaleEffect(isSelected ? 1.1 : 1.0)

                if isInUse && !isSelected {
                    Circle()
                        .fill(OPSStyle.Colors.tertiaryText)
                        .frame(width: 8, height: 8)
                        .offset(x: 14, y: 14)
                }
            }
        }
    }
}