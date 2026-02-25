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
                            .font(.system(size: OPSStyle.Layout.IconSize.lg))
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
            do {
                try await dataController.syncManager.syncCompanyTaskTypes(companyId: companyId)
                print("✅ Task types synced from server")

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
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(taskType.display)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

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
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
                        )
                } else {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
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
