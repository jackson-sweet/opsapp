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
    @State private var taskTypeColor: Color = OPSStyle.Colors.primaryAccent
    @State private var taskTypeColorHex: String = "#59779F"
    @State private var isDefault: Bool = false

    // Loading state
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private let availableIcons = [
        "checklist",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "paintbrush.fill",
        "ruler.fill",
        "level.fill",
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
        "cube.box.fill"
    ]

    private let availableColors: [Color] = [
        OPSStyle.Colors.primaryAccent,
        .blue,
        .green,
        .orange,
        .red,
        .purple,
        .pink,
        .yellow,
        .cyan,
        .indigo,
        .mint,
        .brown
    ]

    private var isValid: Bool {
        !taskTypeName.isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

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
                                            color: taskTypeColor
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
                                ForEach(availableColors, id: \.self) { color in
                                    ColorOption(
                                        color: color,
                                        isSelected: taskTypeColor == color
                                    ) {
                                        withAnimation(.spring(response: 0.3)) {
                                            taskTypeColor = color
                                            taskTypeColorHex = color.toHex() ?? "#59779F"
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
                    Button("SAVE") { saveTaskType() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .disabled(!isValid || isSaving)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }

    private func saveTaskType() {
        guard let companyId = dataController.currentUser?.companyId else {
            errorMessage = "No company ID found"
            showingError = true
            return
        }

        isSaving = true

        Task {
            let newTaskType = TaskType(
                id: UUID().uuidString,
                display: taskTypeName,
                color: taskTypeColorHex,
                companyId: companyId,
                isDefault: false,
                icon: taskTypeIcon
            )

            await MainActor.run {
                modelContext.insert(newTaskType)

                do {
                    try modelContext.save()
                    onSave(newTaskType)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
            }

            // Trigger sync to create in backend
            dataController.syncManager?.triggerBackgroundSync()
        }
    }
}

// MARK: - Supporting Views

struct IconOption: View {
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isSelected ? color : OPSStyle.Colors.secondaryText)
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
        }
    }
}

struct ColorOption: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
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
        }
    }
}

// MARK: - Color Extension
extension Color {
    func toHex() -> String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let rgb = Int(red * 255) << 16 | Int(green * 255) << 8 | Int(blue * 255)
        return String(format: "#%06x", rgb)
    }
}