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

    // Dependencies state
    @State private var dependencies: [TaskTypeDependency] = []
    @State private var showingDependencyPicker = false
    @State private var editingDependencyId: String?

    // Colors organized in groups of 3: light, medium, dark per hue
    // 28 hue families x 3 shades = 84 colors
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
        (Color(hex: "8c687a")!, "8c687a")
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
                        // Preview — blown-up task type badge
                        previewCard

                        // Task Type Details
                        ExpandableSection(
                            title: "TASK TYPE DETAILS",
                            icon: "tag.fill",
                            isExpanded: .constant(true),
                            onDelete: nil,
                            collapsible: false
                        ) {
                            VStack(spacing: 16) {
                                nameField
                                colorField
                            }
                        }

                        // Dependencies section
                        dependenciesSection
                    }
                    .padding()
                    .padding(.bottom, 100)
                }
            }
            .standardSheetToolbar(
                title: mode.title,
                actionText: "Save",
                isActionEnabled: isValid,
                isSaving: isSaving,
                showProgressOnSave: false,
                onCancel: { dismiss() },
                onAction: { saveTaskType() }
            )
            .interactiveDismissDisabled()
        }
        .onAppear {
            if case .edit(let taskType, _) = mode {
                taskTypeName = taskType.display
                taskTypeIcon = taskType.icon ?? "checklist"
                taskTypeColorHex = normalizeHex(taskType.color)
                if let color = Color(hex: taskType.color) {
                    taskTypeColor = color
                }
                dependencies = taskType.dependencies
            }
            loadExistingTaskTypes()
        }
        .sheet(isPresented: $showingDependencyPicker) {
            DependencyPickerSheet(
                currentTaskTypeId: editingTaskTypeId,
                existingDependencies: dependencies,
                companyId: companyId,
                onSelect: { selectedTypeId in
                    dependencies.append(TaskTypeDependency(
                        dependsOnTaskTypeId: selectedTypeId,
                        overlapPercentage: 0
                    ))
                }
            )
            .environmentObject(dataController)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .loadingOverlay(isPresented: $isSaving, message: "Saving...")
    }

    // MARK: - Preview Card (Blown-Up Task Type Badge)

    private var previewCard: some View {
        VStack(spacing: 10) {
            Text("PREVIEW")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text((taskTypeName.isEmpty ? "Task Type Name" : taskTypeName).uppercased())
                .font(OPSStyle.Typography.previewLabel)
                .tracking(0.6)
                .foregroundColor(taskTypeColor)
                .lineLimit(1)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(taskTypeColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(taskTypeColor, lineWidth: 1.5)
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Name Field

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
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    // MARK: - Color Field (3-Row Horizontal Scroll)

    /// Normalize hex by stripping leading # if present
    private func normalizeHex(_ hex: String) -> String {
        hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    }

    /// Colors used by OTHER task types (excludes the one being edited)
    private var colorsInUse: Set<String> {
        let editingId = editingTaskTypeId
        return Set(
            existingTaskTypes
                .filter { $0.id != editingId }
                .map { normalizeHex($0.color).lowercased() }
        )
    }

    /// Find which task type is using a given color hex
    private func taskTypeUsingColor(_ hex: String) -> String? {
        let normalized = hex.lowercased()
        let editingId = editingTaskTypeId
        return existingTaskTypes.first(where: {
            $0.id != editingId && normalizeHex($0.color).lowercased() == normalized
        })?.display
    }

    private var colorField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COLOR")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                let columnCount = availableColors.count / 3
                let inUse = colorsInUse

                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<columnCount, id: \.self) { col in
                                let index = col * 3 + row
                                if index < availableColors.count {
                                    let colorPair = availableColors[index]
                                    let used = inUse.contains(colorPair.hex.lowercased())
                                    ColorOption(
                                        color: colorPair.color,
                                        isSelected: taskTypeColorHex.lowercased() == colorPair.hex.lowercased(),
                                        isInUse: used,
                                        usedByName: used ? taskTypeUsingColor(colorPair.hex) : nil,
                                        action: {
                                            taskTypeColor = colorPair.color
                                            taskTypeColorHex = colorPair.hex
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Computed Helpers

    private var editingTaskTypeId: String? {
        if case .edit(let taskType, _) = mode { return taskType.id }
        return nil
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    // MARK: - Dependencies Section

    private var dependenciesSection: some View {
        ExpandableSection(
            title: "DEPENDENCIES",
            icon: "arrow.triangle.branch",
            isExpanded: .constant(true),
            onDelete: nil,
            collapsible: false
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if dependencies.isEmpty {
                    Text("No dependencies — this task can start anytime")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                } else {
                    ForEach(dependencies.indices, id: \.self) { index in
                        dependencyRow(dep: dependencies[index], index: index)
                    }
                }

                Button(action: { showingDependencyPicker = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Dependency")
                    }
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(.top, 4)
            }
        }
    }

    // Constant overlap presets: (label, days)
    private let constantOverlapSteps: [(label: String, days: Double)] = [
        ("1 DAY", 1),
        ("2 DAYS", 2),
        ("3 DAYS", 3),
        ("5 DAYS", 5),
        ("1 WEEK", 7),
        ("2 WEEKS", 14)
    ]

    // MARK: - Dependency Row

    @ViewBuilder
    private func dependencyRow(dep: TaskTypeDependency, index: Int) -> some View {
        let isEditing = editingDependencyId == dep.dependsOnTaskTypeId
        let depColor = depTaskTypeColor(for: dep.dependsOnTaskTypeId)
        let depName = taskTypeName(for: dep.dependsOnTaskTypeId)
        let isConstant = dep.overlapMode == "constant"
        let overlapFraction = overlapToFraction(dep)

        VStack(spacing: 14) {
            // Overlap visualization bars (always visible) — EDIT button top-right in view mode
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    overlapBars(fraction: overlapFraction, depColor: depColor, depName: depName)

                    // Description text
                    Text(overlapDescription(dep))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .animation(.none, value: dep.overlapPercentage)
                }

                if !isEditing {
                    Spacer()
                    Button {
                        withAnimation(OPSStyle.Animation.spring) {
                            editingDependencyId = dep.dependsOnTaskTypeId
                        }
                    } label: {
                        Text("EDIT")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if isEditing {
                // Mode toggle (sliding underline tabs)
                overlapModeToggle(dep: dep, index: index, isConstant: isConstant)

                // Custom snap slider
                if isConstant {
                    let currentIdx = constantOverlapSteps.firstIndex(where: { $0.days == dep.overlapConstantDays }) ?? 0
                    snapSlider(
                        stepCount: constantOverlapSteps.count,
                        currentIndex: currentIdx,
                        startLabel: "1 DAY",
                        endLabel: "2 WEEKS"
                    ) { newIndex in
                        dependencies[index] = TaskTypeDependency(
                            dependsOnTaskTypeId: dep.dependsOnTaskTypeId,
                            overlapPercentage: dep.overlapPercentage,
                            overlapMode: "constant",
                            overlapConstantDays: constantOverlapSteps[newIndex].days
                        )
                    }
                    .id("constant-\(dep.dependsOnTaskTypeId)")
                } else {
                    snapSlider(
                        stepCount: 11,
                        currentIndex: dep.overlapPercentage / 10,
                        startLabel: "0%",
                        endLabel: "100%"
                    ) { newIndex in
                        dependencies[index] = TaskTypeDependency(
                            dependsOnTaskTypeId: dep.dependsOnTaskTypeId,
                            overlapPercentage: newIndex * 10,
                            overlapMode: "percentage",
                            overlapConstantDays: dep.overlapConstantDays
                        )
                    }
                    .id("percentage-\(dep.dependsOnTaskTypeId)")
                }

                // Edit mode buttons: DONE + REMOVE DEPENDENCY
                HStack(spacing: 12) {
                    Button {
                        withAnimation(OPSStyle.Animation.spring) {
                            editingDependencyId = nil
                        }
                    } label: {
                        Text("DONE")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        withAnimation(OPSStyle.Animation.spring) {
                            editingDependencyId = nil
                            let _ = dependencies.remove(at: index)
                        }
                    } label: {
                        Text("REMOVE DEPENDENCY")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(OPSStyle.Colors.errorStatus.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(
                    isEditing ? OPSStyle.Colors.primaryAccent.opacity(0.3) : OPSStyle.Colors.cardBorder,
                    lineWidth: 1
                )
        )
        .animation(OPSStyle.Animation.spring, value: isEditing)
    }

    // MARK: - Overlap Visualization

    /// Two labeled bars showing predecessor and dependent task overlap
    private func overlapBars(fraction: CGFloat, depColor: Color, depName: String) -> some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let barWidth = totalWidth * 0.55
            let barHeight: CGFloat = 22
            let secondBarOffset = barWidth * (1.0 - fraction)

            VStack(alignment: .leading, spacing: 4) {
                // Predecessor bar with label
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(depColor.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(depColor.opacity(0.4), lineWidth: 1)
                        )
                    Text(depName.uppercased())
                        .font(OPSStyle.Typography.tagLabel)
                        .tracking(0.3)
                        .foregroundColor(depColor)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
                .frame(width: barWidth, height: barHeight)

                // This task bar with label (shifts left as overlap increases)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(taskTypeColor.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(taskTypeColor.opacity(0.4), lineWidth: 1)
                        )
                    Text((taskTypeName.isEmpty ? "This Task" : taskTypeName).uppercased())
                        .font(OPSStyle.Typography.tagLabel)
                        .tracking(0.3)
                        .foregroundColor(taskTypeColor)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
                .frame(width: barWidth, height: barHeight)
                .offset(x: secondBarOffset)
            }
        }
        .frame(height: 48)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: fraction)
    }

    private func overlapToFraction(_ dep: TaskTypeDependency) -> CGFloat {
        if dep.overlapMode == "constant" {
            return CGFloat(min(dep.overlapConstantDays / 14.0, 1.0))
        } else {
            return CGFloat(dep.overlapPercentage) / 100.0
        }
    }

    // MARK: - Mode Toggle (Sliding Underline)

    private func overlapModeToggle(dep: TaskTypeDependency, index: Int, isConstant: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    withAnimation(OPSStyle.Animation.springFast) {
                        dependencies[index] = TaskTypeDependency(
                            dependsOnTaskTypeId: dep.dependsOnTaskTypeId,
                            overlapPercentage: dep.overlapPercentage,
                            overlapMode: "percentage",
                            overlapConstantDays: dep.overlapConstantDays
                        )
                    }
                } label: {
                    Text("PERCENTAGE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(!isConstant ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    withAnimation(OPSStyle.Animation.springFast) {
                        dependencies[index] = TaskTypeDependency(
                            dependsOnTaskTypeId: dep.dependsOnTaskTypeId,
                            overlapPercentage: dep.overlapPercentage,
                            overlapMode: "constant",
                            overlapConstantDays: dep.overlapConstantDays > 0 ? dep.overlapConstantDays : 1
                        )
                    }
                } label: {
                    Text("CONSTANT")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(isConstant ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Sliding underline
            GeometryReader { geo in
                let halfW = geo.size.width / 2
                Rectangle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: halfW, height: 2)
                    .offset(x: isConstant ? halfW : 0)
            }
            .frame(height: 2)

            // Divider below
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    // MARK: - Custom Snap Slider

    /// Draggable slider with tick marks, haptic snapping, and spring animation
    private func snapSlider(
        stepCount: Int,
        currentIndex: Int,
        startLabel: String,
        endLabel: String,
        onSnap: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let totalW = geo.size.width
                let thumbR: CGFloat = 11
                let trackW = totalW - thumbR * 2
                let maxIdx = CGFloat(stepCount - 1)
                let fraction = maxIdx > 0 ? CGFloat(currentIndex) / maxIdx : 0
                let thumbCenterX = thumbR + fraction * trackW

                ZStack {
                    // Track background
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)
                        .padding(.horizontal, thumbR)

                    // Filled track
                    let fillW = fraction * trackW
                    if fillW > 0 {
                        Capsule()
                            .fill(OPSStyle.Colors.primaryAccent.opacity(0.4))
                            .frame(width: fillW, height: 3)
                            .position(x: thumbR + fillW / 2, y: geo.size.height / 2)
                    }

                    // Tick marks
                    ForEach(0..<stepCount, id: \.self) { i in
                        let tickFraction = maxIdx > 0 ? CGFloat(i) / maxIdx : 0
                        let tickX = thumbR + tickFraction * trackW
                        Circle()
                            .fill(i <= currentIndex
                                  ? OPSStyle.Colors.primaryAccent
                                  : Color.white.opacity(0.12))
                            .frame(width: 5, height: 5)
                            .position(x: tickX, y: geo.size.height / 2)
                    }

                    // Thumb with glow
                    ZStack {
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 22, height: 22)
                            .shadow(color: OPSStyle.Colors.primaryAccent.opacity(0.35), radius: 8, y: 2)
                    }
                    .position(x: thumbCenterX, y: geo.size.height / 2)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: currentIndex)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = value.location.x - thumbR
                            let dragFraction = max(0, min(1, x / trackW))
                            let nearest = Int(round(dragFraction * maxIdx))
                            let clamped = max(0, min(stepCount - 1, nearest))
                            if clamped != currentIndex {
                                onSnap(clamped)
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                )
            }
            .frame(height: 44)

            // End labels
            HStack {
                Text(startLabel)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                Text(endLabel)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Overlap Description

    private func overlapDescription(_ dep: TaskTypeDependency) -> String {
        let depName = taskTypeName(for: dep.dependsOnTaskTypeId)
        let thisName = taskTypeName.isEmpty ? "This task" : taskTypeName

        if dep.overlapMode == "constant" {
            let days = dep.overlapConstantDays
            if days <= 0 {
                return "\(depName) must finish before \(thisName) starts"
            } else if days == 1 {
                return "\(thisName) can start 1 day before \(depName) finishes"
            } else if days == 7 {
                return "\(thisName) can start 1 week before \(depName) finishes"
            } else if days == 14 {
                return "\(thisName) can start 2 weeks before \(depName) finishes"
            } else {
                return "\(thisName) can start \(Int(days)) days before \(depName) finishes"
            }
        } else {
            let pct = dep.overlapPercentage
            if pct == 0 {
                return "\(depName) must finish before \(thisName) starts"
            } else if pct == 100 {
                return "\(thisName) can fully overlap with \(depName)"
            } else {
                return "\(thisName) can start when \(depName) is \(pct)% complete"
            }
        }
    }

    private func taskTypeName(for taskTypeId: String) -> String {
        existingTaskTypes.first(where: { $0.id == taskTypeId })?.display ?? "Task Type"
    }

    private func depTaskTypeColor(for taskTypeId: String) -> Color {
        if let hex = existingTaskTypes.first(where: { $0.id == taskTypeId })?.color {
            return Color(hex: hex) ?? OPSStyle.Colors.primaryAccent
        }
        return OPSStyle.Colors.primaryAccent
    }

    // MARK: - Methods

    private func loadExistingTaskTypes() {
        guard let companyId = dataController.currentUser?.companyId else {
            print("[TASK_TYPE_SHEET] No company ID found, cannot load existing task types")
            return
        }

        let descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { taskType in
                taskType.companyId == companyId && taskType.deletedAt == nil
            }
        )

        do {
            existingTaskTypes = try modelContext.fetch(descriptor)
        } catch {
            print("[TASK_TYPE_SHEET] Error fetching task types: \(error)")
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
            errorMessage = "No company ID found"
            showingError = true
            return
        }

        isSaving = true

        Task {
            do {
                let newTaskTypeId = UUID().uuidString

                let newTaskType = await MainActor.run {
                    let newTaskType = TaskType(
                        id: newTaskTypeId,
                        display: taskTypeName,
                        color: taskTypeColorHex,
                        companyId: companyId,
                        isDefault: false,
                        icon: taskTypeIcon
                    )
                    newTaskType.dependencies = dependencies
                    newTaskType.needsSync = true
                    modelContext.insert(newTaskType)
                    try? modelContext.save()
                    return newTaskType
                }

                if let syncManager = dataController.syncManager {
                    let dto = SupabaseTaskTypeDTO(
                        id: newTaskTypeId,
                        bubbleId: nil,
                        companyId: companyId,
                        display: taskTypeName,
                        color: taskTypeColorHex,
                        icon: taskTypeIcon,
                        isDefault: false,
                        displayOrder: nil,
                        dependencies: dependencies.isEmpty ? nil : dependencies,
                        defaultTeamMemberIds: nil,
                        deletedAt: nil
                    )
                    let _ = try await syncManager.createTaskType(dto: dto)
                    await MainActor.run {
                        newTaskType.needsSync = false
                        newTaskType.lastSyncedAt = Date()
                        try? modelContext.save()
                    }
                }

                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    onSave(newTaskType)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
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
                taskType.dependencies = dependencies
                taskType.needsSync = true

                do {
                    try modelContext.save()

                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    onSave()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                } catch {
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

struct ColorOption: View {
    let color: Color
    let isSelected: Bool
    var isInUse: Bool = false
    var usedByName: String? = nil
    let action: () -> Void

    @State private var showingUsedBy = false

    var body: some View {
        Button {
            if isInUse && !isSelected {
                withAnimation(OPSStyle.Animation.fast) {
                    showingUsedBy.toggle()
                }
            } else {
                action()
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(color)
                        .opacity(isInUse && !isSelected ? 0.35 : 1.0)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(OPSStyle.Colors.primaryText, lineWidth: isSelected ? 2 : 0)
                        )
                        .overlay(
                            Circle()
                                .stroke(color.opacity(0.5), lineWidth: isSelected ? 4 : 0)
                        )
                        .scaleEffect(isSelected ? 1.1 : 1.0)

                    // Diagonal line for in-use colors
                    if isInUse && !isSelected {
                        GeometryReader { geo in
                            Path { path in
                                path.move(to: CGPoint(x: geo.size.width * 0.2, y: geo.size.height * 0.8))
                                path.addLine(to: CGPoint(x: geo.size.width * 0.8, y: geo.size.height * 0.2))
                            }
                            .stroke(OPSStyle.Colors.primaryText, lineWidth: 2)
                        }
                        .frame(width: 32, height: 32)
                    }
                }

                // "USED BY" label on tap
                if showingUsedBy, let name = usedByName {
                    Text(name)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                        .frame(width: 48)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
