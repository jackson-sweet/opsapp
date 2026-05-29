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

    // Linked products state — bug 4dadd96c. Surfaces every product whose
    // `task_type_ref` points at this task type so the operator can see and
    // manage the link from the type side instead of having to chase it
    // through every product detail. Edit-mode only because the row needs a
    // persisted id before products can pin to it.
    @State private var linkedProducts: [Product] = []
    @State private var isLoadingLinkedProducts: Bool = false
    @State private var showingAttachProductSheet: Bool = false
    @State private var showingNewLinkedProductSheet: Bool = false
    @State private var linkedProductsExpanded: Bool = true

    // Default sub-tasks (task_templates) state — same bug. Edit-mode only
    // for the same reason; templates carry a FK back to the parent task
    // type via task_type_ref and the row needs to exist first.
    @State private var subTasks: [TaskTemplate] = []
    @State private var isLoadingSubTasks: Bool = false
    @State private var showingNewSubTaskSheet: Bool = false
    @State private var editingSubTask: TaskTemplate? = nil
    @State private var subTasksExpanded: Bool = true

    // Bug 6aa8182e — delete/merge from inside the edit sheet. When the type
    // is in use, deleting is blocked and the alert routes to the merge sheet.
    @State private var showDeleteConfirmation = false
    @State private var showBlockedDeleteAlert = false
    @State private var showMergeSheet = false
    @State private var isDeleting = false
    @State private var deleteErrorMessage: String? = nil
    @State private var existingTaskTypesForMerge: [TaskType] = []

    // Curated OPS color palette — 35 desaturated pastels for task type labels
    // Grouped by family. Names from the job site — materials, weather, textures.
    // Matches OPS-Web: src/lib/data/curated-colors.ts
    private struct CuratedColor {
        let hex: String
        let name: String
        let family: String
    }

    private let curatedColors: [CuratedColor] = [
        // Warm (reds, terracotta, brown) — demolition, excavation, site prep
        CuratedColor(hex: "C79A95", name: "Fired Clay", family: "warm"),
        CuratedColor(hex: "A0837F", name: "Worn Saddle", family: "warm"),
        CuratedColor(hex: "8B534E", name: "Rust", family: "warm"),
        CuratedColor(hex: "A47864", name: "Terra", family: "warm"),
        CuratedColor(hex: "B7788D", name: "Dusk", family: "warm"),
        CuratedColor(hex: "7A6455", name: "Timber", family: "warm"),
        CuratedColor(hex: "716354", name: "Ironbark", family: "warm"),
        // Neutral (sand, olive, gold) — planning, permitting, admin
        CuratedColor(hex: "E7CCB8", name: "Sandstone", family: "neutral"),
        CuratedColor(hex: "C4B2A2", name: "Limestone", family: "neutral"),
        CuratedColor(hex: "C4A998", name: "Adobe", family: "neutral"),
        CuratedColor(hex: "A79473", name: "Rawhide", family: "neutral"),
        CuratedColor(hex: "97896A", name: "Field Sage", family: "neutral"),
        CuratedColor(hex: "948674", name: "Quarry", family: "neutral"),
        CuratedColor(hex: "8B8A77", name: "Lichen", family: "neutral"),
        // Earth (greens, teals) — landscaping, mechanical, HVAC
        CuratedColor(hex: "B9BEAA", name: "Morning Fog", family: "earth"),
        CuratedColor(hex: "BBBE9F", name: "New Growth", family: "earth"),
        CuratedColor(hex: "73806E", name: "Patina", family: "earth"),
        CuratedColor(hex: "6F9587", name: "Verdigris", family: "earth"),
        CuratedColor(hex: "636F65", name: "Deep Forest", family: "earth"),
        CuratedColor(hex: "7B8070", name: "Moss", family: "earth"),
        CuratedColor(hex: "48929B", name: "Oxidized Copper", family: "earth"),
        // Cool (blues, lavenders) — electrical, plumbing, finish work
        CuratedColor(hex: "89C3EB", name: "Clear Sky", family: "cool"),
        CuratedColor(hex: "5D8CAE", name: "Steel Blue", family: "cool"),
        CuratedColor(hex: "7E9EA0", name: "Weathered Zinc", family: "cool"),
        CuratedColor(hex: "90A0A6", name: "Overcast", family: "cool"),
        CuratedColor(hex: "8595AA", name: "Blue Haze", family: "cool"),
        CuratedColor(hex: "8990A3", name: "Drift", family: "cool"),
        CuratedColor(hex: "89729E", name: "Last Light", family: "cool"),
        // Muted (grays, stone) — inspection, testing, cleanup
        CuratedColor(hex: "979CA0", name: "Pewter", family: "muted"),
        CuratedColor(hex: "949495", name: "Raw Concrete", family: "muted"),
        CuratedColor(hex: "748284", name: "Gunmetal", family: "muted"),
        CuratedColor(hex: "807F79", name: "Gravel", family: "muted"),
        CuratedColor(hex: "AF9C8B", name: "Mortar", family: "muted"),
        CuratedColor(hex: "847B77", name: "Flint", family: "muted"),
        CuratedColor(hex: "7A8E8D", name: "Slate", family: "muted"),
    ]

    private let colorFamilies: [(label: String, family: String)] = [
        ("WARM", "warm"),
        ("NEUTRAL", "neutral"),
        ("EARTH", "earth"),
        ("COOL", "cool"),
        ("MUTED", "muted"),
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

                        // Linked Products + Default Sub-Tasks live in
                        // edit mode only — both pin to the persisted task
                        // type id, which doesn't exist until first save.
                        if case .edit(let taskType, _) = mode {
                            linkedProductsSection(for: taskType)
                            subTasksSection(for: taskType)
                        }

                        // Delete — edit mode only, and only for non-default
                        // types. Default types ship with the app and can't be
                        // removed (would orphan tasks across every company).
                        if case .edit(let taskType, _) = mode, !taskType.isDefault {
                            deleteTypeSection(for: taskType)
                        }
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
                loadLinkedProducts(taskTypeId: taskType.id)
                loadSubTasks(taskTypeId: taskType.id)
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
        .alert(
            "Delete this type?",
            isPresented: $showDeleteConfirmation,
            presenting: editTaskType
        ) { type in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await performDelete(type) }
            }
        } message: { type in
            Text("\(type.display) has no tasks using it. Delete it for good?")
        }
        .alert(
            "Can't delete — still in use",
            isPresented: $showBlockedDeleteAlert,
            presenting: editTaskType
        ) { type in
            Button("Cancel", role: .cancel) {}
            Button("Merge Into Another Type") {
                showMergeSheet = true
            }
        } message: { type in
            let count = type.tasks.filter { $0.deletedAt == nil }.count
            Text("\(count) task\(count == 1 ? "" : "s") still use \(type.display). Merge it into another type to move the tasks before deleting.")
        }
        .alert(
            "Delete failed",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            ),
            presenting: deleteErrorMessage
        ) { _ in
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $showMergeSheet) {
            if let source = editTaskType {
                TaskTypeMergeSheet(
                    source: source,
                    allCompanyTypes: existingTaskTypesForMerge,
                    onComplete: {
                        // Merge sheet already soft-deleted the source — bubble
                        // up so parent can refresh, then close this edit sheet.
                        if case .edit(_, let onSave) = mode {
                            onSave()
                        }
                        dismiss()
                    }
                )
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingAttachProductSheet) {
            if let taskType = editTaskType {
                LinkedProductsAttachSheet(
                    targetTaskTypeId: taskType.id,
                    targetTaskTypeName: taskType.display,
                    onAttach: { _ in
                        // Re-read the local store rather than mutating the
                        // in-memory array — keeps display order + soft-delete
                        // filtering consistent with the page load path.
                        loadLinkedProducts(taskTypeId: taskType.id)
                    }
                )
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingNewLinkedProductSheet) {
            if let taskType = editTaskType {
                NewLinkedProductSheet(
                    taskTypeId: taskType.id,
                    companyId: companyId,
                    onSave: { _ in
                        loadLinkedProducts(taskTypeId: taskType.id)
                    }
                )
                .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingNewSubTaskSheet) {
            if let taskType = editTaskType {
                TaskTemplateEditSheet(
                    mode: .create(
                        taskTypeId: taskType.id,
                        companyId: companyId,
                        onSave: { _ in
                            loadSubTasks(taskTypeId: taskType.id)
                        }
                    )
                )
                .environmentObject(dataController)
            }
        }
        .sheet(item: $editingSubTask) { template in
            TaskTemplateEditSheet(
                mode: .edit(template: template, onSave: {
                    if let taskType = editTaskType {
                        loadSubTasks(taskTypeId: taskType.id)
                    }
                })
            )
            .environmentObject(dataController)
        }
        .loadingOverlay(isPresented: $isSaving, message: "Saving...")
        .loadingOverlay(isPresented: $isDeleting, message: "Deleting…")
    }

    // MARK: - Delete Section (edit mode)

    /// The TaskType currently being edited, if the sheet is in edit mode.
    private var editTaskType: TaskType? {
        if case .edit(let t, _) = mode { return t }
        return nil
    }

    private func deleteTypeSection(for taskType: TaskType) -> some View {
        VStack(spacing: 10) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                requestDelete(taskType)
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    Text("DELETE TYPE")
                        .font(OPSStyle.Typography.bodyBold)
                        .tracking(1.2)
                }
                .foregroundColor(OPSStyle.Colors.errorStatus)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }

            // Helper copy — reinforces what delete actually does so a distracted
            // user doesn't realize mid-undo that every task got removed.
            let activeCount = taskType.tasks.filter { $0.deletedAt == nil }.count
            if activeCount > 0 {
                Text("\(activeCount) task\(activeCount == 1 ? "" : "s") use this type — delete is blocked. Merge into another type first.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No tasks are using this type. Delete is permanent.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    private func requestDelete(_ type: TaskType) {
        // Refresh existingTaskTypesForMerge in case the user added more types
        // between sheet open and this tap.
        loadExistingTaskTypes()
        let activeCount = type.tasks.filter { $0.deletedAt == nil }.count
        if activeCount > 0 {
            showBlockedDeleteAlert = true
        } else {
            showDeleteConfirmation = true
        }
    }

    private func performDelete(_ type: TaskType) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await dataController.deleteTaskType(taskTypeId: type.id)
            dataController.triggerBackgroundSync()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if case .edit(_, let onSave) = mode {
                onSave()
            }
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            deleteErrorMessage = error.localizedDescription
        }
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
        let inUse = colorsInUse

        return VStack(alignment: .leading, spacing: 16) {
            Text("COLOR")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            // Color families
            ForEach(colorFamilies, id: \.family) { group in
                let familyColors = curatedColors.filter { $0.family == group.family }

                VStack(alignment: .leading, spacing: 8) {
                    Text(group.label)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    // Wrap colors in a flowing grid
                    FlowLayout(spacing: 8) {
                        ForEach(familyColors, id: \.hex) { curated in
                            let used = inUse.contains(curated.hex.lowercased())
                            let isSelected = taskTypeColorHex.lowercased() == curated.hex.lowercased()

                            ColorOption(
                                color: Color(hex: curated.hex) ?? OPSStyle.Colors.primaryAccent,
                                isSelected: isSelected,
                                isInUse: used,
                                usedByName: used ? taskTypeUsingColor(curated.hex) : nil,
                                action: {
                                    taskTypeColor = Color(hex: curated.hex) ?? OPSStyle.Colors.primaryAccent
                                    taskTypeColorHex = curated.hex
                                }
                            )
                        }
                    }
                }
            }

            // Show selected color name
            if let selected = curatedColors.first(where: { $0.hex.lowercased() == taskTypeColorHex.lowercased() }) {
                Text(selected.name.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
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

    // MARK: - Linked Products Section (bug 4dadd96c)

    @ViewBuilder
    private func linkedProductsSection(for taskType: TaskType) -> some View {
        ExpandableSection(
            title: "LINKED PRODUCTS · \(linkedProducts.count)",
            icon: "shippingbox.fill",
            isExpanded: $linkedProductsExpanded,
            onDelete: nil,
            collapsible: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if isLoadingLinkedProducts {
                    HStack(spacing: 8) {
                        ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        Text("LOADING…")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if linkedProducts.isEmpty {
                    Text("No products linked yet — products tagged with this task type will appear here.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(linkedProducts, id: \.id) { product in
                        linkedProductRow(product)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingAttachProductSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link.badge.plus")
                            Text("ATTACH EXISTING")
                        }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingNewLinkedProductSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("NEW PRODUCT")
                        }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 4)
            }
        }
    }

    private func linkedProductRow(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(product.name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                Text("• \(product.type.rawValue.uppercased())")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            HStack(spacing: 8) {
                Text(formatLinkedProductPrice(product))
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                if !product.isActive {
                    Text("· INACTIVE")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
                Spacer()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func formatLinkedProductPrice(_ product: Product) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        let priceStr = f.string(from: NSNumber(value: product.basePrice)) ?? "$\(product.basePrice)"
        return "\(priceStr)/\(product.pricingUnit.rawValue)".uppercased()
    }

    // MARK: - Default Sub-Tasks Section (bug 4dadd96c)

    @ViewBuilder
    private func subTasksSection(for taskType: TaskType) -> some View {
        ExpandableSection(
            title: "DEFAULT SUB-TASKS · \(subTasks.count)",
            icon: "list.bullet.indent",
            isExpanded: $subTasksExpanded,
            onDelete: nil,
            collapsible: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if isLoadingSubTasks {
                    HStack(spacing: 8) {
                        ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        Text("LOADING…")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if subTasks.isEmpty {
                    Text("No sub-tasks yet — when an estimate approves, one generic task will be created. Add sub-tasks to break work into steps.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(subTasks, id: \.id) { template in
                        subTaskRow(template)
                    }
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingNewSubTaskSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("ADD SUB-TASK")
                    }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
        }
    }

    private func subTaskRow(_ template: TaskTemplate) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            editingSubTask = template
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    if let hours = template.estimatedHours, hours > 0 {
                        Text("\(formatSubTaskHours(hours)) HR ESTIMATE".uppercased())
                            .font(OPSStyle.Typography.metadata)
                            .monospacedDigit()
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    if let desc = template.templateDescription, !desc.isEmpty {
                        Text(desc)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Edit sub-task \(template.title)")
    }

    private func formatSubTaskHours(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - Loaders for linked products + sub-tasks

    private func loadLinkedProducts(taskTypeId: String) {
        let descriptor = FetchDescriptor<Product>(
            predicate: #Predicate<Product> { product in
                (product.taskTypeRef == taskTypeId || product.taskTypeId == taskTypeId)
                && product.companyId == companyId
            },
            sortBy: [SortDescriptor(\.name)]
        )
        if let local = try? modelContext.fetch(descriptor) {
            linkedProducts = local
        }

        guard !companyId.isEmpty else { return }
        isLoadingLinkedProducts = true
        Task {
            defer { Task { @MainActor in isLoadingLinkedProducts = false } }
            let repo = ProductRepository(companyId: companyId)
            if let remote = try? await repo.fetchForTaskType(taskTypeId, includeInactive: true) {
                await MainActor.run {
                    for dto in remote {
                        let id = dto.id
                        let existingDescriptor = FetchDescriptor<Product>(
                            predicate: #Predicate<Product> { $0.id == id }
                        )
                        if let existing = try? modelContext.fetch(existingDescriptor).first {
                            existing.taskTypeId = dto.taskTypeId
                            existing.taskTypeRef = dto.taskTypeRef
                        } else {
                            modelContext.insert(dto.toModel())
                        }
                    }
                    try? modelContext.save()
                    if let merged = try? modelContext.fetch(descriptor) {
                        linkedProducts = merged
                    }
                }
            }
        }
    }

    private func loadSubTasks(taskTypeId: String) {
        let descriptor = FetchDescriptor<TaskTemplate>(
            predicate: #Predicate<TaskTemplate> { template in
                (template.taskTypeRef == taskTypeId || template.taskTypeId == taskTypeId)
                && template.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.title)]
        )
        if let local = try? modelContext.fetch(descriptor) {
            subTasks = local
        }

        guard !companyId.isEmpty else { return }
        isLoadingSubTasks = true
        Task {
            defer { Task { @MainActor in isLoadingSubTasks = false } }
            let repo = TaskTemplateRepository(companyId: companyId)
            if let remote = try? await repo.fetchForTaskType(taskTypeId) {
                await MainActor.run {
                    for dto in remote {
                        let id = dto.id
                        let existingDescriptor = FetchDescriptor<TaskTemplate>(
                            predicate: #Predicate<TaskTemplate> { $0.id == id }
                        )
                        if let existing = try? modelContext.fetch(existingDescriptor).first {
                            existing.title = dto.title
                            existing.templateDescription = dto.description
                            existing.estimatedHours = dto.estimatedHours
                            existing.displayOrder = dto.displayOrder
                        } else {
                            modelContext.insert(dto.toModel())
                        }
                    }
                    try? modelContext.save()
                    if let merged = try? modelContext.fetch(descriptor) {
                        subTasks = merged
                    }
                }
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

    /// After-end gap presets (days) for the snap slider in `after_end` mode.
    private let afterEndGapSteps: [Int] = [0, 1, 3, 7, 14, 21, 28]

    /// Weekday segments for after_end mode. ISO 1=Mon ... 7=Sun. nil = no constraint.
    private let weekdayOptions: [(label: String, value: Int?)] = [
        ("ANY", nil),
        ("M",  1),
        ("T",  2),
        ("W",  3),
        ("TH", 4),
        ("F",  5),
        ("SA", 6),
        ("SU", 7)
    ]

    // MARK: - Dependency Row

    @ViewBuilder
    private func dependencyRow(dep: TaskTypeDependency, index: Int) -> some View {
        let isEditing = editingDependencyId == dep.dependsOnTaskTypeId
        let depColor = depTaskTypeColor(for: dep.dependsOnTaskTypeId)
        let depName = taskTypeName(for: dep.dependsOnTaskTypeId)
        let mode = dep.overlapMode
        let isConstant = mode == "constant"
        let isAfterEnd = mode == "after_end"
        let overlapFraction = overlapToFraction(dep)

        VStack(spacing: 14) {
            // Visualization bars (always visible) — EDIT button top-right in view mode
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    if isAfterEnd {
                        afterEndBars(dep: dep, depColor: depColor, depName: depName)
                    } else {
                        overlapBars(fraction: overlapFraction, depColor: depColor, depName: depName)
                    }

                    // Description text
                    Text(overlapDescription(dep))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .animation(.none, value: dep.overlapPercentage)

                    // Auto-create badge in view mode — quick signal that this
                    // dependency carries pair behavior beyond pure scheduling.
                    if dep.autoCreate && !isEditing {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            Text("AUTO-CREATED FROM \(depName.uppercased())")
                                .font(OPSStyle.Typography.smallCaption)
                                .tracking(0.3)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
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
                // Mode toggle (sliding underline tabs) — 3-way
                overlapModeToggle(dep: dep, index: index, mode: mode)

                // Mode-specific controls
                if isAfterEnd {
                    afterEndControls(dep: dep, index: index)
                        .id("after-end-\(dep.dependsOnTaskTypeId)")
                } else if isConstant {
                    let currentIdx = constantOverlapSteps.firstIndex(where: { $0.days == dep.overlapConstantDays }) ?? 0
                    snapSlider(
                        stepCount: constantOverlapSteps.count,
                        currentIndex: currentIdx,
                        startLabel: "1 DAY",
                        endLabel: "2 WEEKS"
                    ) { newIndex in
                        dependencies[index] = updatedDependency(
                            from: dep,
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
                        dependencies[index] = updatedDependency(
                            from: dep,
                            overlapPercentage: newIndex * 10,
                            overlapMode: "percentage"
                        )
                    }
                    .id("percentage-\(dep.dependsOnTaskTypeId)")
                }

                // Pair behavior toggles — shown for every mode.
                pairToggles(dep: dep, index: index, predecessorName: depName)

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
        switch dep.overlapMode {
        case "after_end":
            // Visualization fraction is 0 for after_end (predecessor leads, no overlap).
            // The afterEndBars() variant renders gap explicitly.
            return 0
        case "constant":
            return CGFloat(min(dep.overlapConstantDays / 14.0, 1.0))
        default:
            return CGFloat(dep.overlapPercentage) / 100.0
        }
    }

    // MARK: - Helper: Update dependency preserving fields not changed by callers

    /// Returns a new `TaskTypeDependency` based on `original`, applying any of
    /// the named overrides. Used by mode-switch buttons + slider callbacks so
    /// changing one field never silently zeroes the others (pair toggles,
    /// after_end fields, etc.). Weekday updates use a dedicated helper since
    /// the field is itself optional and a double-optional would muddle the API.
    private func updatedDependency(
        from original: TaskTypeDependency,
        overlapPercentage: Int? = nil,
        overlapMode: String? = nil,
        overlapConstantDays: Double? = nil,
        autoCreate: Bool? = nil,
        inheritCrew: Bool? = nil,
        minGapDaysAfterEnd: Int? = nil
    ) -> TaskTypeDependency {
        TaskTypeDependency(
            dependsOnTaskTypeId: original.dependsOnTaskTypeId,
            overlapPercentage: overlapPercentage ?? original.overlapPercentage,
            overlapMode: overlapMode ?? original.overlapMode,
            overlapConstantDays: overlapConstantDays ?? original.overlapConstantDays,
            autoCreate: autoCreate ?? original.autoCreate,
            inheritCrew: inheritCrew ?? original.inheritCrew,
            minGapDaysAfterEnd: minGapDaysAfterEnd ?? original.minGapDaysAfterEnd,
            weekdayConstraint: original.weekdayConstraint
        )
    }

    /// Update only the weekday constraint, preserving all other fields.
    private func updatedDependencyWeekday(
        from original: TaskTypeDependency,
        weekdayConstraint: Int?
    ) -> TaskTypeDependency {
        TaskTypeDependency(
            dependsOnTaskTypeId: original.dependsOnTaskTypeId,
            overlapPercentage: original.overlapPercentage,
            overlapMode: original.overlapMode,
            overlapConstantDays: original.overlapConstantDays,
            autoCreate: original.autoCreate,
            inheritCrew: original.inheritCrew,
            minGapDaysAfterEnd: original.minGapDaysAfterEnd,
            weekdayConstraint: weekdayConstraint
        )
    }

    // MARK: - After-End Visualization

    /// Bars for `after_end` mode — predecessor on the left, a hairline-and-arrow
    /// gap in the middle showing the wait, then the dependent on the right.
    /// Highlights the weekday constraint if one is set.
    private func afterEndBars(dep: TaskTypeDependency, depColor: Color, depName: String) -> some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let barWidth: CGFloat = totalWidth * 0.38
            let barHeight: CGFloat = 22

            HStack(spacing: 0) {
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

                // Gap visualization — dashed hairline + day count
                ZStack {
                    Rectangle()
                        .stroke(OPSStyle.Colors.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(height: 1)
                    Text("+\(dep.minGapDaysAfterEnd)D")
                        .font(OPSStyle.Typography.smallCaption)
                        .tracking(0.3)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.horizontal, 4)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                }
                .frame(maxWidth: .infinity)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(taskTypeColor.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(taskTypeColor.opacity(0.4), lineWidth: 1)
                        )
                    let label: String = {
                        let base = (taskTypeName.isEmpty ? "This task" : taskTypeName).uppercased()
                        if let wd = dep.weekdayConstraint,
                           let entry = weekdayOptions.first(where: { $0.value == wd }) {
                            return "\(entry.label) · \(base)"
                        }
                        return base
                    }()
                    Text(label)
                        .font(OPSStyle.Typography.tagLabel)
                        .tracking(0.3)
                        .foregroundColor(taskTypeColor)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }
                .frame(width: barWidth, height: barHeight)
            }
        }
        .frame(height: 48)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: dep.minGapDaysAfterEnd)
    }

    // MARK: - After-End Controls

    /// Snap-slider for gap days + segmented picker for weekday constraint.
    @ViewBuilder
    private func afterEndControls(dep: TaskTypeDependency, index: Int) -> some View {
        let currentGapIdx = afterEndGapSteps.firstIndex(of: dep.minGapDaysAfterEnd) ?? closestGapIndex(to: dep.minGapDaysAfterEnd)

        VStack(alignment: .leading, spacing: 14) {
            // Gap days
            Text("// GAP AFTER PREDECESSOR ENDS")
                .font(OPSStyle.Typography.smallCaption)
                .tracking(0.3)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            snapSlider(
                stepCount: afterEndGapSteps.count,
                currentIndex: currentGapIdx,
                startLabel: "0 DAYS",
                endLabel: "4 WEEKS"
            ) { newIndex in
                dependencies[index] = updatedDependency(
                    from: dep,
                    overlapMode: "after_end",
                    minGapDaysAfterEnd: afterEndGapSteps[newIndex]
                )
            }

            // Weekday constraint
            Text("// WEEKDAY")
                .font(OPSStyle.Typography.smallCaption)
                .tracking(0.3)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, 4)

            HStack(spacing: 4) {
                ForEach(weekdayOptions.indices, id: \.self) { i in
                    let entry = weekdayOptions[i]
                    let isSelected = entry.value == dep.weekdayConstraint
                    Button {
                        withAnimation(OPSStyle.Animation.springFast) {
                            dependencies[index] = updatedDependencyWeekday(from: dep, weekdayConstraint: entry.value)
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    } label: {
                        Text(entry.label)
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? OPSStyle.Colors.primaryAccent.opacity(0.25) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    /// Find the gap-preset index nearest to an arbitrary day count. Used when
    /// a stored value (e.g. legacy migrated data) doesn't match a preset.
    private func closestGapIndex(to days: Int) -> Int {
        guard !afterEndGapSteps.isEmpty else { return 0 }
        var bestIdx = 0
        var bestDist = Int.max
        for (i, step) in afterEndGapSteps.enumerated() {
            let dist = abs(step - days)
            if dist < bestDist {
                bestDist = dist
                bestIdx = i
            }
        }
        return bestIdx
    }

    // MARK: - Pair Behavior Toggles

    /// Two toggles for the pair behavior: auto-create the owning task when
    /// the predecessor is created, and inherit the predecessor's crew. The
    /// crew toggle is disabled when auto-create is off (nothing to inherit).
    @ViewBuilder
    private func pairToggles(dep: TaskTypeDependency, index: Int, predecessorName: String) -> some View {
        let inheritEnabled = dep.autoCreate

        VStack(alignment: .leading, spacing: 10) {
            Text("// PAIR BEHAVIOR")
                .font(OPSStyle.Typography.smallCaption)
                .tracking(0.3)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            // AUTO-CREATE
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AUTO-CREATE THIS TASK")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("when \(predecessorName) is created")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { dep.autoCreate },
                    set: { newValue in
                        withAnimation(OPSStyle.Animation.spring) {
                            dependencies[index] = updatedDependency(from: dep, autoCreate: newValue)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                ))
                .labelsHidden()
                .tint(OPSStyle.Colors.text)
            }

            // INHERIT CREW
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INHERIT CREW FROM \(predecessorName.uppercased())")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(inheritEnabled ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    Text(inheritEnabled
                         ? "spawn copies predecessor's team_member_ids"
                         : "enable auto-create to use")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { dep.inheritCrew },
                    set: { newValue in
                        dependencies[index] = updatedDependency(from: dep, inheritCrew: newValue)
                    }
                ))
                .labelsHidden()
                .tint(OPSStyle.Colors.text)
                .disabled(!inheritEnabled)
                .opacity(inheritEnabled ? 1.0 : 0.4)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Mode Toggle (Sliding Underline) — 3-way

    private func overlapModeToggle(dep: TaskTypeDependency, index: Int, mode: String) -> some View {
        let modes: [(label: String, value: String)] = [
            ("PERCENTAGE", "percentage"),
            ("CONSTANT",   "constant"),
            ("AFTER END",  "after_end")
        ]
        let selectedIndex = modes.firstIndex(where: { $0.value == mode }) ?? 0

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(modes.indices, id: \.self) { i in
                    let entry = modes[i]
                    let isSelected = i == selectedIndex
                    Button {
                        withAnimation(OPSStyle.Animation.springFast) {
                            // Switching INTO a mode applies a sensible default
                            // value while preserving the other modes' fields so
                            // toggling back doesn't lose user input.
                            let switched: TaskTypeDependency
                            switch entry.value {
                            case "constant":
                                let days = dep.overlapConstantDays > 0 ? dep.overlapConstantDays : 1
                                switched = updatedDependency(from: dep, overlapMode: "constant", overlapConstantDays: days)
                            case "after_end":
                                // Default to 7-day gap on first entry to give
                                // users a meaningful starting point.
                                let gap = dep.minGapDaysAfterEnd > 0 ? dep.minGapDaysAfterEnd : 7
                                switched = updatedDependency(from: dep, overlapMode: "after_end", minGapDaysAfterEnd: gap)
                            default:
                                switched = updatedDependency(from: dep, overlapMode: "percentage")
                            }
                            dependencies[index] = switched
                        }
                    } label: {
                        Text(entry.label)
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Sliding underline
            GeometryReader { geo in
                let segW = geo.size.width / CGFloat(modes.count)
                Rectangle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: segW, height: 2)
                    .offset(x: segW * CGFloat(selectedIndex))
            }
            .frame(height: 2)

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

        switch dep.overlapMode {
        case "after_end":
            return afterEndDescription(dep: dep, depName: depName, thisName: thisName)
        case "constant":
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
        default:
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

    private func afterEndDescription(dep: TaskTypeDependency, depName: String, thisName: String) -> String {
        let gap = dep.minGapDaysAfterEnd
        let weekday = dep.weekdayConstraint.flatMap { wd in
            weekdayOptions.first(where: { $0.value == wd })?.label
        }

        let gapText: String
        switch gap {
        case 0:  gapText = "the day after \(depName) ends"
        case 1:  gapText = "1 day after \(depName) ends"
        case 7:  gapText = "1 week after \(depName) ends"
        case 14: gapText = "2 weeks after \(depName) ends"
        case 21: gapText = "3 weeks after \(depName) ends"
        case 28: gapText = "4 weeks after \(depName) ends"
        default: gapText = "\(gap) days after \(depName) ends"
        }

        let weekdayPhrase: String
        if let wd = weekday, wd != "ANY" {
            weekdayPhrase = ", on first \(weekdayLong(wd))"
        } else {
            weekdayPhrase = ""
        }

        let autoPhrase = dep.autoCreate ? " · auto-created" : ""
        return "\(thisName) starts \(gapText)\(weekdayPhrase)\(autoPhrase)"
    }

    private func weekdayLong(_ short: String) -> String {
        switch short {
        case "M":  return "Monday"
        case "T":  return "Tuesday"
        case "W":  return "Wednesday"
        case "TH": return "Thursday"
        case "F":  return "Friday"
        case "SA": return "Saturday"
        case "SU": return "Sunday"
        default:   return short
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
            // Same fetch doubles as the pool the merge sheet picks from.
            existingTaskTypesForMerge = existingTaskTypes
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
        guard !isSaving else { return }
        guard let companyId = dataController.currentUser?.companyId else {
            errorMessage = "No company ID found"
            showingError = true
            return
        }

        isSaving = true

        // Snapshot form state synchronously so async work can't observe torn writes
        // (matches the TaskFormSheet.saveTask pattern that resolved an iOS 18
        // crash vector plus duplicate-insert race). Capturing strings/value types
        // keeps the closure Sendable; the @Model is looked up inside the actor.
        let newTaskTypeId = UUID().uuidString
        let capturedName = taskTypeName
        let capturedColor = taskTypeColorHex
        let capturedIcon = taskTypeIcon
        let capturedDependencies = dependencies

        Task { @MainActor in
            // ----- Phase 1: Local SwiftData write (MainActor) -----
            let newTaskType = TaskType(
                id: newTaskTypeId,
                display: capturedName,
                color: capturedColor,
                companyId: companyId,
                isDefault: false,
                icon: capturedIcon
            )

            // Insert BEFORE wiring dependencies so SwiftData never sees a
            // half-managed model being referenced by managed objects (iOS 18
            // crash vector — same root cause TaskFormSheet fixed in 2c1cd1c).
            modelContext.insert(newTaskType)
            newTaskType.dependencies = capturedDependencies
            newTaskType.needsSync = true

            do {
                try modelContext.save()
            } catch {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
                errorMessage = "Failed to save task type locally: \(error.localizedDescription)"
                showingError = true
                isSaving = false
                return
            }

            // ----- Phase 2: Queue sync operation (MainActor) -----
            // DataController.createTaskType is idempotent via id lookup — it
            // finds the row we just inserted and only records the sync op.
            // Keep this @MainActor hop explicit so DataActor paths never see
            // a mid-flight context mutation.
            let dto = SupabaseTaskTypeDTO(
                id: newTaskTypeId,
                bubbleId: nil,
                companyId: companyId,
                display: capturedName,
                color: capturedColor,
                icon: capturedIcon,
                isDefault: false,
                displayOrder: nil,
                dependencies: capturedDependencies.isEmpty ? nil : capturedDependencies,
                defaultTeamMemberIds: nil,
                defaultDuration: nil,
                deletedAt: nil
            )

            do {
                _ = try await dataController.createTaskType(dto: dto)
            } catch {
                // Local insert already succeeded; sync will retry. Surface the
                // message but do not roll back — the UI must show the new type.
                print("[TASK_TYPE_SHEET] ⚠️ Sync op enqueue failed, will retry: \(error)")
            }

            // ----- Phase 3: Success path (MainActor) -----
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            isSaving = false
            onSave(newTaskType)
            dismiss()
        }
    }

    private func saveEditedTaskType(taskType: TaskType, onSave: @escaping () -> Void) {
        guard !isSaving else { return }
        isSaving = true

        // Snapshot form state so a late edit can't tear the write mid-flight.
        let capturedName = taskTypeName
        let capturedIcon = taskTypeIcon
        let capturedColorHex = taskTypeColorHex
        let capturedDependencies = dependencies

        Task { @MainActor in
            taskType.display = capturedName
            taskType.icon = capturedIcon
            taskType.color = capturedColorHex
            taskType.dependencies = capturedDependencies
            taskType.needsSync = true

            do {
                try modelContext.save()
            } catch {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
                errorMessage = error.localizedDescription
                showingError = true
                isSaving = false
                return
            }

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            isSaving = false
            onSave()
            dismiss()

            dataController.triggerBackgroundSync()
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
