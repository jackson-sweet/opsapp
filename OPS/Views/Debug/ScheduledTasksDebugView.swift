//
//  CalendarEventsDebugView.swift
//  OPS
//
//  Debug view for displaying scheduled tasks with full field details
//  (Renamed from CalendarEventsDebugView after CalendarEvent model was removed)
//

import SwiftUI
import SwiftData

/// Debug view renamed from CalendarEventsDebugView.
/// Now displays ProjectTask scheduling info instead of CalendarEvent entities.
struct ScheduledTasksDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @State private var tasks: [ProjectTask] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTask: ProjectTask?
    @State private var searchText: String = ""
    @State private var showUnscheduledOnly: Bool = false
    @State private var showScheduledOnly: Bool = false
    @State private var showingTaskSearchSheet = false

    var filteredTasks: [ProjectTask] {
        var filtered = tasks

        // Filter by scheduled status
        if showScheduledOnly {
            filtered = filtered.filter { $0.startDate != nil }
        }
        if showUnscheduledOnly {
            filtered = filtered.filter { $0.startDate == nil }
        }

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { task in
                task.id.localizedCaseInsensitiveContains(searchText) ||
                task.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                task.projectId.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                OPSScreenHeader(
                    "Scheduled Tasks Debug",
                    leading: {
                        Button(action: { dismiss() }) {
                            Image(systemName: OPSStyle.Icons.close)
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    },
                    trailing: {
                        Button(action: fetchTasks) {
                            Image(systemName: OPSStyle.Icons.sync)
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                )
                .background(OPSStyle.Colors.background)

                // Search bar
                HStack {
                    HStack {
                        Image(systemName: OPSStyle.Icons.search)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        TextField("Search by ID, title, or project...", text: $searchText)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                    }
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                    )

                    Button(action: { showingTaskSearchSheet = true }) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal)

                // Filter chips
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    EventFilterChip(
                        title: "Scheduled",
                        isSelected: showScheduledOnly,
                        action: {
                            showScheduledOnly.toggle()
                            if showScheduledOnly { showUnscheduledOnly = false }
                        }
                    )

                    EventFilterChip(
                        title: "Unscheduled",
                        isSelected: showUnscheduledOnly,
                        action: {
                            showUnscheduledOnly.toggle()
                            if showUnscheduledOnly { showScheduledOnly = false }
                        }
                    )

                    Spacer()
                }
                .padding(.horizontal)

                if isLoading {
                    Spacer()
                    ProgressView("Loading tasks...")
                        .foregroundColor(.white)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        Image(systemName: OPSStyle.Icons.alert)
                            .font(.system(size: 50))
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                        Text("Error")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        Text(error)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else if filteredTasks.isEmpty {
                    Spacer()
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 50))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("No Tasks Found")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        Text("No tasks match the current filters")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing2_5) {
                            ForEach(filteredTasks, id: \.id) { task in
                                ScheduledTaskDetailCard(task: task)
                                    .onTapGesture {
                                        selectedTask = task
                                    }
                            }
                        }
                        .padding()
                    }
                }

                // Summary bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total: \(tasks.count) tasks")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        let scheduledCount = tasks.filter { $0.startDate != nil }.count
                        Text("\(scheduledCount) scheduled, \(tasks.count - scheduledCount) unscheduled")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()

                    Button("Sync Tasks") {
                        syncTasksFromAPI()
                    }
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding()
                .background(OPSStyle.Colors.background)
            }
        }
        .onAppear {
            fetchTasks()
        }
        .sheet(item: $selectedTask) { task in
            ScheduledTaskDetailSheet(task: task)
        }
        .sheet(isPresented: $showingTaskSearchSheet) {
            TaskSearchSheet(dataController: dataController)
        }
    }

    private func fetchTasks() {
        isLoading = true
        errorMessage = nil

        do {
            let descriptor = FetchDescriptor<ProjectTask>(
                sortBy: [SortDescriptor(\.startDate)]
            )
            tasks = try modelContext.fetch(descriptor)
            isLoading = false
        } catch {
            errorMessage = "Failed to fetch tasks: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func syncTasksFromAPI() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                // Sync tasks via Supabase
                await dataController.triggerTasksSync()

                await MainActor.run {
                    errorMessage = "Synced tasks from Supabase"
                    fetchTasks()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "API sync failed: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

// Event filter chip component (kept for reuse)
struct EventFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, 6)
                .background(isSelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.chipRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .stroke(isSelected ? OPSStyle.Colors.primaryText : Color.clear, lineWidth: 1)
                )
        }
    }
}

// Scheduled task detail card
struct ScheduledTaskDetailCard: View {
    let task: ProjectTask

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Header
            HStack {
                if let icon = task.taskType?.icon {
                    Image(systemName: icon)
                        .foregroundColor(task.swiftUIColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.displayTitle)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)

                    Text(task.project?.title ?? "No project")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Circle()
                        .fill(task.swiftUIColor)
                        .frame(width: 8, height: 8)

                    Text(task.status.displayName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.chipRadius)
            }

            Divider()
                .background(OPSStyle.Colors.line)

            // Fields grid
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                FieldRow(label: "ID", value: task.id)
                FieldRow(label: "Project ID", value: task.projectId)
                FieldRow(label: "Company ID", value: task.companyId)
                FieldRow(label: "Task Type", value: task.taskType?.display ?? "Unknown")
                FieldRow(label: "Color", value: task.effectiveColor)
                FieldRow(label: "Duration", value: "\(task.duration) days")
                FieldRow(label: "Start Date", value: task.startDate.map { formatDate($0) } ?? "nil")
                FieldRow(label: "End Date", value: task.endDate.map { formatDate($0) } ?? "nil")
                FieldRow(label: "Multi-Day", value: task.isMultiDay ? "Yes" : "No")
                FieldRow(label: "Spanned Days", value: "\(task.spannedDates.count)")
                FieldRow(label: "Team Members", value: task.getTeamMemberIds().joined(separator: ", ").isEmpty ? "none" : task.getTeamMemberIds().joined(separator: ", "))
                FieldRow(label: "Needs Sync", value: task.needsSync ? "Yes" : "No")
                FieldRow(label: "Last Synced", value: task.lastSyncedAt?.formatted() ?? "Never")
            }
            .font(OPSStyle.Typography.smallCaption)
        }
        .padding()
        .glassSurface()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Detailed sheet for a single scheduled task
struct ScheduledTaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: ProjectTask

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        // Date Range
                        DebugSection("Date Range") {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                FieldRow(label: "Start", value: task.startDate.map { formatDateTime($0) } ?? "nil")
                                FieldRow(label: "End", value: task.endDate.map { formatDateTime($0) } ?? "nil")
                                FieldRow(label: "Duration", value: "\(task.duration) days")

                                if task.isMultiDay {
                                    Text("Spanned Dates:")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                                    ForEach(task.spannedDates, id: \.self) { date in
                                        Text("- \(formatDate(date))")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .padding(.leading, OPSStyle.Layout.spacing2)
                                    }
                                }
                            }
                            .padding()
                            .glassSurface()
                        }

                        // Project Info
                        if let project = task.project {
                            DebugSection("Project") {
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                    FieldRow(label: "Title", value: project.title)
                                    FieldRow(label: "Status", value: project.status.displayName)
                                    FieldRow(label: "Client", value: project.effectiveClientName)
                                    FieldRow(label: "Address", value: project.address ?? "No address")

                                    if let notes = project.notes, !notes.isEmpty {
                                        Text("Notes:")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        Text(notes)
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                    }
                                }
                                .padding()
                                .glassSurface()
                            }
                        }

                        // Task Details
                        DebugSection("Task Info") {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                FieldRow(label: "Title", value: task.displayTitle)
                                FieldRow(label: "Status", value: task.status.displayName)
                                FieldRow(label: "Type", value: task.taskType?.display ?? "Unknown")
                                FieldRow(label: "Color", value: task.effectiveColor)

                                if let notes = task.taskNotes, !notes.isEmpty {
                                    Text("Notes:")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    Text(notes)
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                            }
                            .padding()
                            .glassSurface()
                        }

                        // Team Members
                        if !task.teamMembers.isEmpty {
                            DebugSection("Team Members") {
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                    ForEach(task.teamMembers, id: \.id) { member in
                                        HStack {
                                            Text(member.fullName)
                                                .foregroundColor(.white)
                                            Spacer()
                                            Text(member.role.displayName)
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                    }
                                }
                                .padding()
                                .glassSurface()
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Task Schedule Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Task search sheet - search by ID
struct TaskSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let dataController: DataController

    @State private var taskId: String = ""
    @State private var localTask: ProjectTask?
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                        // Search input
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("TASK ID")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            HStack {
                                TextField("Enter task ID", text: $taskId)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(OPSStyle.Layout.spacing2_5)
                                    .background(OPSStyle.Colors.surfaceInput)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                                    )

                                if !taskId.isEmpty {
                                    Button(action: { taskId = "" }) {
                                        Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }
                                }
                            }

                            Button(action: searchTask) {
                                HStack {
                                    Image(systemName: OPSStyle.Icons.search)
                                    Text("Search Local")
                                }
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                            }
                            .disabled(taskId.isEmpty || isSearching)
                        }

                        if let error = errorMessage {
                            HStack {
                                Image(systemName: OPSStyle.Icons.alert)
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                                Text(error)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                            }
                            .padding()
                            .glassSurface()
                        }

                        if isSearching {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                Text("Searching...")
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }

                        // Local SwiftData result
                        if let local = localTask {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                                Label("LOCAL SWIFTDATA", systemImage: "cylinder.fill")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.successStatus)

                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                    FieldRow(label: "ID", value: local.id)
                                    FieldRow(label: "Title", value: local.displayTitle)
                                    FieldRow(label: "Status", value: local.status.displayName)
                                    FieldRow(label: "Project ID", value: local.projectId)
                                    FieldRow(label: "Company ID", value: local.companyId)
                                    FieldRow(label: "Task Type", value: local.taskType?.display ?? "Unknown")
                                    FieldRow(label: "Color", value: local.effectiveColor)
                                    FieldRow(label: "Start Date", value: local.startDate?.formatted() ?? "nil")
                                    FieldRow(label: "End Date", value: local.endDate?.formatted() ?? "nil")
                                    FieldRow(label: "Duration", value: "\(local.duration) days")
                                    FieldRow(label: "Last Synced", value: local.lastSyncedAt?.formatted() ?? "Never")
                                    FieldRow(label: "Needs Sync", value: local.needsSync ? "Yes" : "No")
                                }
                                .font(OPSStyle.Typography.smallCaption)
                            }
                            .padding()
                            .glassSurface()
                        } else if !isSearching && !taskId.isEmpty {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Label("LOCAL SWIFTDATA", systemImage: "cylinder.fill")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                Text("Task not found in local SwiftData")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding()
                            .glassSurface()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Search Task by ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func searchTask() {
        isSearching = true
        errorMessage = nil
        localTask = nil

        let searchId = taskId
        let localDescriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.id == searchId }
        )
        do {
            let localResults = try modelContext.fetch(localDescriptor)
            localTask = localResults.first
        } catch {
            errorMessage = "Local search error: \(error.localizedDescription)"
        }

        isSearching = false
    }
}

// Section helper for debug sheets (avoids conflict with SwiftUI Section)
private struct DebugSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            content
        }
    }
}
