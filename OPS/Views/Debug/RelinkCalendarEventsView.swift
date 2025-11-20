//
//  RelinkCalendarEventsView.swift
//  OPS
//
//  Developer tool to re-link calendar events to tasks/projects
//  and ensure they're all in company's calendar events list
//

import SwiftUI
import SwiftData

struct RelinkCalendarEventsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    @State private var isProcessing = false
    @State private var progressMessage = ""
    @State private var logs: [LogEntry] = []
    @State private var stats = RelinkStats()
    @State private var allCalendarEvents: [CalendarEvent] = []
    @State private var selectedEvent: CalendarEvent? = nil
    @State private var showingEventDetail = false

    struct LogEntry: Identifiable {
        let id = UUID()
        let message: String
        let type: LogType
        let timestamp = Date()

        enum LogType {
            case info, success, warning, error

            var color: Color {
                switch self {
                case .info: return OPSStyle.Colors.primaryText
                case .success: return OPSStyle.Colors.successStatus
                case .warning: return OPSStyle.Colors.warningStatus
                case .error: return OPSStyle.Colors.errorStatus
                }
            }

            var icon: String {
                switch self {
                case .info: return "info.circle"
                case .success: return "checkmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .error: return "xmark.circle.fill"
                }
            }
        }
    }

    struct RelinkStats {
        var totalEvents = 0
        var eventsProcessed = 0
        var tasksLinked = 0
        var projectsLinked = 0
        var titlesUpdated = 0
        var companiesUpdated = 0
        var orphanedEvents = 0
        var errors = 0
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                headerView

                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        // Stats Card
                        statsCard
                            .padding(.horizontal)
                            .padding(.top)

                        // Instructions
                        if !isProcessing && logs.isEmpty {
                            instructionsCard
                                .padding(.horizontal)
                        }

                        // Calendar Events List
                        if !allCalendarEvents.isEmpty {
                            calendarEventsListSection
                                .padding(.horizontal)
                        }

                        // Logs
                        if !logs.isEmpty {
                            logsSection
                                .padding(.horizontal)
                        }

                        // Action Button
                        if !isProcessing {
                            Button(action: startRelinking) {
                                HStack {
                                    Image(systemName: "link.circle.fill")
                                    Text("Start Re-linking")
                                }
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.cyan)
                                .cornerRadius(OPSStyle.Layout.buttonRadius)
                            }
                            .padding(.horizontal)
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                                .padding()
                        }

                        if !progressMessage.isEmpty {
                            Text(progressMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            loadCalendarEvents()
        }
        .sheet(isPresented: $showingEventDetail) {
            if let event = selectedEvent {
                EventDetailWithDeleteSheet(
                    event: event,
                    onDelete: {
                        deleteEvent(event)
                    }
                )
                .environmentObject(dataController)
            }
        }
    }

    private var headerView: some View {
        ZStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: OPSStyle.Icons.close)
                        .font(.system(size: 20))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                Spacer()
            }

            Text("Re-link Calendar Events")
                .font(OPSStyle.Typography.title)
                .foregroundColor(.white)
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("STATISTICS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatRow(label: "Total Events", value: "\(stats.totalEvents)")
                StatRow(label: "Processed", value: "\(stats.eventsProcessed)")
                StatRow(label: "Tasks Linked", value: "\(stats.tasksLinked)")
                StatRow(label: "Projects Linked", value: "\(stats.projectsLinked)")
                StatRow(label: "Titles Updated", value: "\(stats.titlesUpdated)")
                StatRow(label: "Companies Updated", value: "\(stats.companiesUpdated)")
                StatRow(label: "Orphaned", value: "\(stats.orphanedEvents)", color: OPSStyle.Colors.warningStatus)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What This Tool Does", systemImage: "info.circle.fill")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(Color.cyan)

            VStack(alignment: .leading, spacing: 8) {
                BulletPoint(text: "Re-links all calendar events to their tasks/projects")
                BulletPoint(text: "Updates all event titles to use client names")
                BulletPoint(text: "Updates company calendar events lists in Bubble")
                BulletPoint(text: "Identifies orphaned events (no task/project)")
                BulletPoint(text: "Syncs all changes to Bubble backend")
            }

            Text("⚠️ This may take a few minutes for large datasets")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.warningStatus)
                .padding(.top, 8)
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOGS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 8) {
                ForEach(logs.reversed()) { log in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: log.type.icon)
                            .foregroundColor(log.type.color)
                            .font(.system(size: 12))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.message)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Text(formatTime(log.timestamp))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackground.opacity(0.5))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private var calendarEventsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CALENDAR EVENTS (\(allCalendarEvents.count))")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 8) {
                ForEach(allCalendarEvents.sorted(by: { $0.title < $1.title })) { event in
                    Button(action: {
                        selectedEvent = event
                        showingEventDetail = true
                    }) {
                        HStack(spacing: 12) {
                            // Color indicator
                            Circle()
                                .fill(event.swiftUIColor)
                                .frame(width: 12, height: 12)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                HStack(spacing: 12) {
                                    Label("Task", systemImage: "checklist")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    if let startDate = event.startDate {
                                        Label(formatDate(startDate), systemImage: "calendar")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    } else {
                                        Label("Unscheduled", systemImage: "calendar.badge.exclamationmark")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.warningStatus)
                                    }
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .padding(12)
                        .background(OPSStyle.Colors.cardBackground.opacity(0.5))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Helper Views

    struct StatRow: View {
        let label: String
        let value: String
        var color: Color = OPSStyle.Colors.primaryText

        var body: some View {
            VStack(spacing: 4) {
                Text(value)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(color)

                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
    }

    struct BulletPoint: View {
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundColor(Color.cyan)
                Text(text)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
            }
        }
    }

    // MARK: - Re-linking Logic

    private func startRelinking() {
        isProcessing = true
        logs.removeAll()
        stats = RelinkStats()

        Task {
            await performRelinking()

            await MainActor.run {
                isProcessing = false
                progressMessage = ""
            }
        }
    }

    private func performRelinking() async {
        await log("🔵 Starting calendar event re-linking process", type: .info)

        // STEP 1: Fetch all calendar events
        await updateProgress("Fetching calendar events...")
        guard let allEvents = await fetchAllCalendarEvents() else {
            await log("❌ Failed to fetch calendar events", type: .error)
            return
        }

        await MainActor.run {
            stats.totalEvents = allEvents.count
        }
        await log("✅ Found \(allEvents.count) calendar events", type: .success)

        // STEP 2: Fetch all tasks and projects
        await updateProgress("Fetching tasks and projects...")
        guard let (allTasks, allProjects) = await fetchTasksAndProjects() else {
            await log("❌ Failed to fetch tasks and projects", type: .error)
            return
        }

        await log("✅ Found \(allTasks.count) tasks and \(allProjects.count) projects", type: .success)

        // STEP 3: Re-link events to tasks and projects
        await updateProgress("Re-linking events...")
        await relinkEvents(events: allEvents, tasks: allTasks, projects: allProjects)

        // STEP 4: Update all event titles with client names
        await updateProgress("Updating event titles...")
        await updateEventTitles(events: allEvents, projects: allProjects)

        // STEP 5: Update company calendar events lists
        await updateProgress("Updating company lists...")
        await updateCompanyCalendarEventLists(events: allEvents)

        await log("✅ Re-linking complete!", type: .success)
        await updateProgress("Complete!")
    }

    private func fetchAllCalendarEvents() async -> [CalendarEvent]? {
        let descriptor = FetchDescriptor<CalendarEvent>()

        return await MainActor.run {
            do {
                return try modelContext.fetch(descriptor)
            } catch {
                return nil
            }
        }
    }

    private func fetchTasksAndProjects() async -> ([ProjectTask], [Project])? {
        return await MainActor.run {
            do {
                let tasks = try modelContext.fetch(FetchDescriptor<ProjectTask>())
                let projects = try modelContext.fetch(FetchDescriptor<Project>())
                return (tasks, projects)
            } catch {
                return nil
            }
        }
    }

    private func relinkEvents(events: [CalendarEvent], tasks: [ProjectTask], projects: [Project]) async {
        for event in events {
            await MainActor.run {
                stats.eventsProcessed += 1
            }

            // All events are task events now
            if let taskId = event.taskId {
                // Find and link to task
                if let task = tasks.first(where: { $0.id == taskId }) {
                    await MainActor.run {
                        task.calendarEvent = event
                        task.calendarEventId = event.id
                        stats.tasksLinked += 1
                    }
                    await log("🔗 Linked event '\(event.title)' to task", type: .info)
                } else {
                    await log("⚠️ Orphaned task event: \(event.title) (task \(taskId) not found)", type: .warning)
                    await MainActor.run {
                        stats.orphanedEvents += 1
                    }
                }
            } else {
                await log("⚠️ Event has no task ID: \(event.title)", type: .warning)
                await MainActor.run {
                    stats.orphanedEvents += 1
                }
            }
        }

        // Save changes
        await MainActor.run {
            do {
                try modelContext.save()
            } catch {
                stats.errors += 1
            }
        }
    }

    private func updateEventTitles(events: [CalendarEvent], projects: [Project]) async {
        await log("📝 Updating calendar event titles with client names", type: .info)

        for event in events {
            // Find the associated project
            guard let project = projects.first(where: { $0.id == event.projectId }) else {
                await log("⚠️ No project found for event: \(event.title)", type: .warning)
                continue
            }

            // Get the client name from the project
            let clientName = project.effectiveClientName

            // Skip if no client name or if title is already correct
            if clientName.isEmpty {
                await log("⚠️ No client name for project: \(project.title)", type: .warning)
                continue
            }

            if event.title == clientName {
                // Title already correct, skip
                continue
            }

            // Update the title
            let oldTitle = event.title
            await MainActor.run {
                event.title = clientName
                stats.titlesUpdated += 1
            }

            await log("📝 Updated '\(oldTitle)' → '\(clientName)'", type: .info)

            // Update in Bubble
            do {
                let updateData: [String: Any] = [
                    BubbleFields.CalendarEvent.title: clientName
                ]
                try await dataController.apiService.updateCalendarEvent(
                    id: event.id,
                    updates: updateData
                )
            } catch {
                await log("❌ Failed to update title for event \(event.id): \(error.localizedDescription)", type: .error)
                await MainActor.run {
                    stats.errors += 1
                }
            }
        }

        // Save local changes
        await MainActor.run {
            do {
                try modelContext.save()
            } catch {
                stats.errors += 1
            }
        }

        await log("✅ Updated \(stats.titlesUpdated) event titles", type: .success)
    }

    private func updateCompanyCalendarEventLists(events: [CalendarEvent]) async {
        // Group events by company
        let eventsByCompany = Dictionary(grouping: events, by: { $0.companyId })

        for (companyId, companyEvents) in eventsByCompany {
            await log("📊 Updating company \(companyId) with \(companyEvents.count) events", type: .info)

            // Update in Bubble
            let eventIds = companyEvents.map { $0.id }
            let updateData: [String: Any] = [
                BubbleFields.Company.calendarEventsList: eventIds
            ]

            do {
                let bodyData = try JSONSerialization.data(withJSONObject: updateData)

                let _: EmptyResponse = try await dataController.apiService.executeRequest(
                    endpoint: "api/1.1/obj/\(BubbleFields.Types.company)/\(companyId)",
                    method: "PATCH",
                    body: bodyData,
                    requiresAuth: false
                )

                await MainActor.run {
                    stats.companiesUpdated += 1
                }
                await log("✅ Updated company \(companyId) calendar events list in Bubble", type: .success)
            } catch {
                await log("❌ Failed to update company \(companyId): \(error.localizedDescription)", type: .error)
                await MainActor.run {
                    stats.errors += 1
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func log(_ message: String, type: LogEntry.LogType) async {
        await MainActor.run {
            logs.append(LogEntry(message: message, type: type))
            print("[RELINK] \(message)")
        }
    }

    private func updateProgress(_ message: String) async {
        await MainActor.run {
            progressMessage = message
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func loadCalendarEvents() {
        let descriptor = FetchDescriptor<CalendarEvent>()
        do {
            allCalendarEvents = try modelContext.fetch(descriptor)
            stats.totalEvents = allCalendarEvents.count
        } catch {
            print("[RELINK] Failed to load calendar events: \(error)")
        }
    }

    private func deleteEvent(_ event: CalendarEvent) {
        Task {
            // Delete from Bubble first
            do {
                try await dataController.apiService.deleteCalendarEvent(id: event.id)
                await log("✅ Deleted event '\(event.title)' from Bubble", type: .success)

                // Delete locally
                await MainActor.run {
                    modelContext.delete(event)
                    do {
                        try modelContext.save()
                        // Remove from local list
                        allCalendarEvents.removeAll { $0.id == event.id }
                        stats.totalEvents = allCalendarEvents.count
                        showingEventDetail = false
                    } catch {
                        logs.append(LogEntry(message: "Failed to delete locally: \(error.localizedDescription)", type: .error))
                    }
                }
            } catch {
                await log("❌ Failed to delete from Bubble: \(error.localizedDescription)", type: .error)
            }
        }
    }
}

// MARK: - Event Detail With Delete Sheet

struct EventDetailWithDeleteSheet: View {
    let event: CalendarEvent
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                ZStack {
                    HStack {
                        Button("Close") {
                            dismiss()
                        }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .font(OPSStyle.Typography.body)

                        Spacer()

                        Button("Delete") {
                            showingDeleteConfirmation = true
                        }
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .font(OPSStyle.Typography.body)
                    }

                    Text("Event Details")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)

                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Title
                        DetailRow(label: "Title", value: event.title)

                        // ID
                        DetailRow(label: "ID", value: event.id, monospaced: true)

                        // Type
                        DetailRow(label: "Type", value: "Task")

                        // Color
                        HStack {
                            Text("Color")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(width: 100, alignment: .leading)

                            HStack(spacing: 8) {
                                Circle()
                                    .fill(event.swiftUIColor)
                                    .frame(width: 20, height: 20)

                                Text(event.color)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)

                        // Dates
                        if let startDate = event.startDate {
                            DetailRow(label: "Start Date", value: formatFullDate(startDate))
                        } else {
                            DetailRow(label: "Start Date", value: "Not set", color: OPSStyle.Colors.warningStatus)
                        }

                        if let endDate = event.endDate {
                            DetailRow(label: "End Date", value: formatFullDate(endDate))
                        } else {
                            DetailRow(label: "End Date", value: "Not set", color: OPSStyle.Colors.warningStatus)
                        }

                        // Duration
                        DetailRow(label: "Duration", value: "\(event.duration) day\(event.duration == 1 ? "" : "s")")

                        // Task-only scheduling migration: 'active' property removed

                        // Company ID
                        DetailRow(label: "Company ID", value: event.companyId, monospaced: true)

                        // Project ID
                        DetailRow(label: "Project ID", value: event.projectId, monospaced: true)

                        // Task ID
                        if let taskId = event.taskId {
                            DetailRow(label: "Task ID", value: taskId, monospaced: true)
                        } else {
                            DetailRow(label: "Task ID", value: "None", color: OPSStyle.Colors.tertiaryText)
                        }

                        // Team Members
                        let teamMemberIds = event.getTeamMemberIds()
                        if !teamMemberIds.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Team Members (\(teamMemberIds.count))")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(teamMemberIds, id: \.self) { memberId in
                                        Text(memberId)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        } else {
                            DetailRow(label: "Team Members", value: "None", color: OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .padding()
                }
            }
        }
        .alert("Delete Event?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("This will permanently delete the calendar event '\(event.title)' from both the local database and Bubble. This action cannot be undone.")
        }
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false
    var color: Color = OPSStyle.Colors.primaryText

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : OPSStyle.Typography.body)
                .foregroundColor(color)

            Spacer()
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

#Preview("Event Detail") {
    let event = CalendarEvent(
        id: "test123",
        projectId: "proj123",
        companyId: "comp123",
        title: "Test Event",
        startDate: Date(),
        endDate: Date().addingTimeInterval(86400),
        color: "#59779F"
    )
    EventDetailWithDeleteSheet(event: event, onDelete: {})
        .preferredColorScheme(.dark)
}

#Preview {
    RelinkCalendarEventsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
