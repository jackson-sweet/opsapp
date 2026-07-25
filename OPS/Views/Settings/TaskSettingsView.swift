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
    @Query private var allTasks: [ProjectTask]
    
    @State private var taskTypes: [TaskType] = []
    @State private var loadState: TaskTypeLoadState = .loading
    @State private var selectedTaskType: TaskType?
    @State private var showingEditSheet = false
    @State private var showingAddSheet = false

    // Bug 6aa8182e: delete / rename / merge actions for task types.
    @State private var taskTypeToDelete: TaskType? = nil
    @State private var taskTypeToMerge: TaskType? = nil
    /// Populated when delete is attempted on a type that still owns tasks —
    /// delete is blocked in that case and the alert redirects to merge.
    @State private var blockedDeleteType: TaskType? = nil
    @State private var isDeleting: Bool = false
    @State private var deleteError: String? = nil
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Task Types",
                    trailingIcon: canAddTaskType
                        ? OPSStyle.Icons.plus
                        : nil,
                    trailingAccessibilityLabel: "Add task type",
                    onBackTapped: { dismiss() },
                    onEditTapped: { showingAddSheet = true }
                )
                .padding(.bottom, OPSStyle.Layout.spacing2)
                
                switch loadState {
                case .loading:
                    Spacer()
                    ProgressView("LOADING TASK TYPES")
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                case .failed:
                    taskTypeLoadFailure
                case .loaded:
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("\(taskTypes.count) TASK TYPE\(taskTypes.count == 1 ? "" : "S")")
                                .font(OPSStyle.Typography.metadata)
                                .monospacedDigit()
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            VStack(spacing: 0) {
                                if taskTypes.isEmpty {
                                    Text("NO TASK TYPES")
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                                } else {
                                    ForEach(Array(sortedTaskTypes.enumerated()), id: \.element.id) { index, taskType in
                                        TaskTypeRow(
                                            taskType: taskType,
                                            activeTaskCount: activeTaskCount(for: taskType),
                                            onTap: {
                                                selectedTaskType = taskType
                                                showingEditSheet = true
                                            },
                                            onRename: {
                                                selectedTaskType = taskType
                                                showingEditSheet = true
                                            },
                                            onMerge: {
                                                taskTypeToMerge = taskType
                                            },
                                            onDelete: {
                                                requestDelete(taskType)
                                            }
                                        )

                                        if index < sortedTaskTypes.count - 1 {
                                            separator
                                        }
                                    }

                                    separator
                                }

                                addTaskTypeRow
                            }
                            .glassSurface()
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    }
                }
            }
        }
        .trackScreen("Settings.Tasks")
        .navigationBarHidden(true)
        .onAppear {
            loadTaskTypes()
        }
        .sheet(isPresented: $showingEditSheet) {
            if let taskType = selectedTaskType {
                TaskTypeSheet(mode: .edit(taskType: taskType) {
                    refreshTaskTypesFromCache()
                })
                .environmentObject(dataController)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskTypeDeleted"))) { _ in
            refreshTaskTypesFromCache()
        }
        .sheet(isPresented: $showingAddSheet) {
            TaskTypeSheet(mode: .create { _ in
                refreshTaskTypesFromCache()
            })
            .environmentObject(dataController)
        }
        // Merge picker — reassigns tasks to a target type then deletes source.
        .sheet(item: $taskTypeToMerge) { source in
            TaskTypeMergeSheet(
                source: source,
                allCompanyTypes: taskTypes,
                onComplete: {
                    refreshTaskTypesFromCache()
                    // Close the edit sheet too if it was showing for this type.
                    if selectedTaskType?.id == source.id {
                        showingEditSheet = false
                        selectedTaskType = nil
                    }
                }
            )
            .environmentObject(dataController)
        }
        // Delete confirmation — only fires for types with zero active tasks.
        .alert(
            "Delete \(taskTypeToDelete?.display ?? "type")?",
            isPresented: Binding(
                get: { taskTypeToDelete != nil },
                set: { if !$0 { taskTypeToDelete = nil } }
            ),
            presenting: taskTypeToDelete
        ) { item in
            Button("Cancel", role: .cancel) { taskTypeToDelete = nil }
            Button("Delete", role: .destructive) {
                Task { await performDelete(item) }
            }
        } message: { item in
            Text("\(item.display) has no tasks using it. Delete it for good?")
        }
        // Block-when-in-use alert. Redirects the user to merge.
        .alert(
            "Can't delete \(blockedDeleteType?.display ?? "type")",
            isPresented: Binding(
                get: { blockedDeleteType != nil },
                set: { if !$0 { blockedDeleteType = nil } }
            ),
            presenting: blockedDeleteType
        ) { item in
            Button("Cancel", role: .cancel) { blockedDeleteType = nil }
            Button("Merge Into Another Type") {
                taskTypeToMerge = item
                blockedDeleteType = nil
            }
        } message: { item in
            let count = activeTaskCount(for: item)
            Text("\(count) task\(count == 1 ? "" : "s") still use \(item.display). Merge it into another type to move the tasks before deleting.")
        }
        .errorToast($deleteError, label: Feedback.Err.deleteFailed)
        .loadingOverlay(isPresented: $isDeleting, message: "Deleting…")
    }

    // MARK: - Delete / Merge Actions

    private func requestDelete(_ type: TaskType) {
        let activeCount = activeTaskCount(for: type)
        if activeCount > 0 {
            blockedDeleteType = type
        } else {
            taskTypeToDelete = type
        }
    }

    private func performDelete(_ type: TaskType) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer {
            isDeleting = false
            taskTypeToDelete = nil
        }

        do {
            try await dataController.deleteTaskType(taskTypeId: type.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            refreshTaskTypesFromCache()
            if selectedTaskType?.id == type.id {
                showingEditSheet = false
                selectedTaskType = nil
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            deleteError = error.localizedDescription
        }
    }
    
    private var sortedTaskTypes: [TaskType] {
        TaskTypeSettingsLogic.sortedTaskTypes(taskTypes)
    }

    private var canAddTaskType: Bool {
        if case .loaded = loadState {
            return true
        }
        return false
    }

    private var taskTypeLoadFailure: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()

            Text("// TASK TYPES UNAVAILABLE")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("Couldn’t load task types. Check your connection and retry.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)

            Button {
                syncTaskTypes()
            } label: {
                Text("RETRY")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(
                        minHeight: OPSStyle.Layout.touchTargetMin
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: OPSStyle.Layout.cornerRadius
                        )
                        .stroke(
                            OPSStyle.Colors.cardBorder,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    private var separator: some View {
        OPSStyle.Colors.separator
            .frame(height: OPSStyle.Layout.Border.standard)
            .padding(.leading, OPSStyle.Layout.spacing5)
    }

    private var addTaskTypeRow: some View {
        Button {
            showingAddSheet = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: OPSStyle.Icons.plus)
                    .font(.system(
                        size: OPSStyle.Layout.IconSize.sm,
                        weight: .semibold
                    ))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: OPSStyle.Layout.spacing3)

                Text("ADD TASK TYPE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add task type")
    }

    private func activeTaskCount(for taskType: TaskType) -> Int {
        TaskTypeSettingsLogic.activeTaskCount(
            for: taskType,
            in: allTasks
        )
    }

    private func loadTaskTypes() {
        loadState = .loading
        guard fetchTaskTypesFromCache() else { return }

        loadState = TaskTypeSettingsLogic.loadState(
            hasCachedTaskTypes: !taskTypes.isEmpty,
            remoteRefreshSucceeded: nil
        )
        if taskTypes.isEmpty {
            syncTaskTypes()
        }
    }

    private func refreshTaskTypesFromCache() {
        guard fetchTaskTypesFromCache() else { return }
        loadState = TaskTypeSettingsLogic.loadState(
            hasCachedTaskTypes: !taskTypes.isEmpty,
            remoteRefreshSucceeded: true
        )
    }

    @discardableResult
    private func fetchTaskTypesFromCache() -> Bool {
        guard let companyId = dataController.currentUser?.companyId else {
            print("❌ No company ID found")
            loadState = taskTypes.isEmpty ? .failed : .loaded
            return false
        }

        print("🔍 Fetching task types for company: \(companyId)")

        do {
            let predicate = #Predicate<TaskType> { taskType in
                taskType.companyId == companyId && taskType.deletedAt == nil
            }

            let descriptor = FetchDescriptor<TaskType>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.displayOrder)]
            )
            let filteredTypes = try modelContext.fetch(descriptor)
            print("✅ Filtered task types for company: \(filteredTypes.count)")

            taskTypes = TaskTypeSettingsLogic.visibleTaskTypes(filteredTypes, companyId: companyId)
            return true
        } catch {
            print("❌ Error fetching task types: \(error)")
            // Keep the last usable in-memory snapshot if SwiftData is
            // temporarily unavailable. An empty cache cannot be trusted.
            loadState = taskTypes.isEmpty ? .failed : .loaded
            return false
        }
    }
    
    private func syncTaskTypes() {
        guard let companyId = dataController.currentUser?.companyId else {
            loadState = taskTypes.isEmpty ? .failed : .loaded
            return
        }

        let hasCachedTaskTypes = !taskTypes.isEmpty
        loadState = TaskTypeSettingsLogic.loadState(
            hasCachedTaskTypes: hasCachedTaskTypes,
            remoteRefreshSucceeded: nil
        )

        print("🔄 Syncing task types for company: \(companyId)")

        Task { @MainActor in
            let refreshed = await dataController.triggerTaskTypesSync(
                companyId: companyId
            )

            guard refreshed else {
                print("❌ Task type refresh failed")
                loadState = TaskTypeSettingsLogic.loadState(
                    hasCachedTaskTypes: !taskTypes.isEmpty,
                    remoteRefreshSucceeded: false
                )
                return
            }

            guard fetchTaskTypesFromCache() else { return }
            loadState = TaskTypeSettingsLogic.loadState(
                hasCachedTaskTypes: !taskTypes.isEmpty,
                remoteRefreshSucceeded: true
            )
            print("✅ Task types refreshed")
        }
    }
}

// MARK: - Task Type Row
struct TaskTypeRow: View {
    let taskType: TaskType
    let activeTaskCount: Int
    let onTap: () -> Void
    /// Long-press action: open edit sheet focused on the name field. Currently
    /// behaves the same as onTap — the edit sheet is where rename lives.
    let onRename: () -> Void
    /// Long-press action: open the merge-target picker.
    let onMerge: () -> Void
    /// Long-press action: delete (parent gates on in-use check).
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                    .frame(
                        width: OPSStyle.Layout.spacing1,
                        height: OPSStyle.Layout.spacing4
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                            .stroke(
                                OPSStyle.Colors.cardBorder,
                                lineWidth: OPSStyle.Layout.Border.standard
                            )
                    )

                Text(taskType.display)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                if taskType.isDefault {
                    Text("DEFAULT")
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.chipRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                .stroke(
                                    OPSStyle.Colors.cardBorder,
                                    lineWidth: OPSStyle.Layout.Border.standard
                                )
                        )
                }

                Spacer(minLength: OPSStyle.Layout.spacing2)

                Text("\(activeTaskCount)")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(taskType.display), \(activeTaskCount) task\(activeTaskCount == 1 ? "" : "s")\(taskType.isDefault ? ", default" : "")"
        )
        .accessibilityHint(
            taskType.isDefault
                ? "Opens usage. Default details are read-only."
                : "Opens task type details."
        )
        .contextMenu {
            // Rename — opens the edit sheet for custom types only.
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: OPSStyle.Icons.pencil)
            }
            .disabled(taskType.isDefault)

            // Merge into another type — always available; the picker will
            // refuse the merge if no other types exist in the company.
            Button {
                onMerge()
            } label: {
                Label("Merge Into…", systemImage: OPSStyle.Icons.merge)
            }
            .disabled(taskType.isDefault)

            // Delete — custom types only. Defaults are protected.
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: OPSStyle.Icons.trash)
            }
            .disabled(taskType.isDefault)
        }
    }
}
