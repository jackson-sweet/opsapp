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

    // Bug 6aa8182e: delete / rename / merge actions for task types.
    @State private var taskTypeToDelete: TaskType? = nil
    @State private var taskTypeToMerge: TaskType? = nil
    /// Populated when delete is attempted on a type that still owns tasks —
    /// delete is blocked in that case and the alert redirects to merge.
    @State private var blockedDeleteType: TaskType? = nil
    @State private var isDeleting: Bool = false
    @State private var deleteErrorMessage: String? = nil
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .ignoresSafeArea()
            
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
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                } else if taskTypes.isEmpty {
                    // Empty state
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        
                        Text("No Task Types")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Text("Create task types to categorize work")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Button(action: createDefaultTaskTypes) {
                            Text("CREATE DEFAULT TYPES")
                                .font(OPSStyle.Typography.smallButton)
                                .foregroundColor(OPSStyle.Colors.primaryText)
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
                                TaskTypeRow(
                                    taskType: taskType,
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
                            .font(.system(size: OPSStyle.Layout.IconSize.lg))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
            }
        }
        .trackScreen("Settings.Tasks")
        .navigationBarHidden(true)
        .onAppear {
            fetchTaskTypes()
            // If no task types found, try syncing from server
            if taskTypes.isEmpty {
                syncTaskTypes()
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let taskType = selectedTaskType {
                TaskTypeSheet(mode: .edit(taskType: taskType) {
                    fetchTaskTypes()
                })
                .environmentObject(dataController)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TaskTypeDeleted"))) { _ in
            fetchTaskTypes()
        }
        .sheet(isPresented: $showingAddSheet) {
            TaskTypeSheet(mode: .create { _ in
                fetchTaskTypes()
            })
            .environmentObject(dataController)
        }
        // Merge picker — reassigns tasks to a target type then deletes source.
        .sheet(item: $taskTypeToMerge) { source in
            TaskTypeMergeSheet(
                source: source,
                allCompanyTypes: taskTypes,
                onComplete: {
                    fetchTaskTypes()
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
            let count = item.tasks.filter { $0.deletedAt == nil }.count
            Text("\(count) task\(count == 1 ? "" : "s") still use \(item.display). Merge it into another type to move the tasks before deleting.")
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
        .loadingOverlay(isPresented: $isDeleting, message: "Deleting…")
    }

    // MARK: - Delete / Merge Actions

    private func requestDelete(_ type: TaskType) {
        let activeCount = type.tasks.filter { $0.deletedAt == nil }.count
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
            dataController.triggerBackgroundSync()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            fetchTaskTypes()
            if selectedTaskType?.id == type.id {
                showingEditSheet = false
                selectedTaskType = nil
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            deleteErrorMessage = error.localizedDescription
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

    private func syncTaskTypes() {
        guard let companyId = dataController.currentUser?.companyId else { return }

        print("🔄 Syncing task types for company: \(companyId)")

        Task {
            await dataController.triggerTaskTypesSync(companyId: companyId)
            print("✅ Task types synced")

            // Refresh the list on main thread
            await MainActor.run {
                fetchTaskTypes()
            }
        }
    }
}

// MARK: - Task Type Row
struct TaskTypeRow: View {
    let taskType: TaskType
    let onTap: () -> Void
    /// Long-press action: open edit sheet focused on the name field. Currently
    /// behaves the same as onTap — the edit sheet is where rename lives.
    let onRename: () -> Void
    /// Long-press action: open the merge-target picker.
    let onMerge: () -> Void
    /// Long-press action: delete (parent gates on in-use check).
    let onDelete: () -> Void

    private var activeTaskCount: Int {
        taskType.tasks.filter { $0.deletedAt == nil }.count
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon with color
                ZStack {
                    Circle()
                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                        .frame(width: 48, height: 48)

                    Image(systemName: taskType.icon ?? "hammer.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(taskType.display)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("\(activeTaskCount) task\(activeTaskCount == 1 ? "" : "s")")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                if taskType.isDefault {
                    Text("DEFAULT")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                } else {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
        // Defaults have no edit path — tap is disabled, but context menu stays
        // available so users can still merge / delete custom types via long
        // press on their card. Default types also support context menu but
        // individual actions self-gate below.
        .disabled(taskType.isDefault)
        .contextMenu {
            // Rename — opens the edit sheet for custom types only.
            Button {
                onRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(taskType.isDefault)

            // Merge into another type — always available; the picker will
            // refuse the merge if no other types exist in the company.
            Button {
                onMerge()
            } label: {
                Label("Merge Into…", systemImage: "arrow.triangle.merge")
            }
            .disabled(taskType.isDefault)

            // Delete — custom types only. Defaults are protected.
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(taskType.isDefault)
        }
    }
}
