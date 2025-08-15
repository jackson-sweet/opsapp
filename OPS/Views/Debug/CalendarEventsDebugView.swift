//
//  CalendarEventsDebugView.swift
//  OPS
//
//  Debug view for displaying all calendar events with full field details
//

import SwiftUI
import SwiftData

struct CalendarEventsDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var events: [CalendarEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedEvent: CalendarEvent?
    @State private var filterType: CalendarEventType? = nil
    
    var filteredEvents: [CalendarEvent] {
        if let filterType = filterType {
            return events.filter { $0.type == filterType }
        }
        return events
    }
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    
                    Spacer()
                    
                    Text("Calendar Events Debug")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: fetchEvents) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                
                // Filter chips
                HStack(spacing: 12) {
                    EventFilterChip(
                        title: "All",
                        isSelected: filterType == nil,
                        action: { filterType = nil }
                    )
                    
                    EventFilterChip(
                        title: "Projects",
                        isSelected: filterType == .project,
                        action: { filterType = .project }
                    )
                    
                    EventFilterChip(
                        title: "Tasks",
                        isSelected: filterType == .task,
                        action: { filterType = .task }
                    )
                }
                .padding()
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading events...")
                        .foregroundColor(.white)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
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
                } else if filteredEvents.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 50))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("No Events Found")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        Text(filterType != nil ? "No \(filterType!.rawValue) events found" : "No calendar events in the database")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(filteredEvents, id: \.id) { event in
                                CalendarEventDetailCard(event: event)
                                    .onTapGesture {
                                        selectedEvent = event
                                    }
                            }
                        }
                        .padding()
                    }
                }
                
                // Summary bar with sync options
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total: \(events.count) events")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        HStack(spacing: 8) {
                            Text("Projects: \(events.filter { $0.type == .project }.count)")
                            Text("Tasks: \(events.filter { $0.type == .task }.count)")
                        }
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button("Sync from API") {
                            syncEventsFromAPI()
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                        
                        Button("Generate from Projects") {
                            generateEventsFromProjects()
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
            }
        }
        .onAppear {
            fetchEvents()
        }
        .sheet(item: $selectedEvent) { event in
            CalendarEventDetailSheet(event: event)
        }
    }
    
    private func fetchEvents() {
        isLoading = true
        errorMessage = nil
        
        do {
            let descriptor = FetchDescriptor<CalendarEvent>(
                sortBy: [SortDescriptor(\.startDate)]
            )
            events = try modelContext.fetch(descriptor)
            isLoading = false
        } catch {
            errorMessage = "Failed to fetch events: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func syncEventsFromAPI() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                guard let companyId = dataController.currentUser?.companyId else {
                    await MainActor.run {
                        errorMessage = "No company ID found"
                        isLoading = false
                    }
                    return
                }
                
                // Fetch from API
                let apiEvents = try await dataController.apiService.fetchCompanyCalendarEvents(companyId: companyId)
                
                await MainActor.run {
                    // Convert and save
                    var syncedCount = 0
                    for dto in apiEvents {
                        if let event = dto.toModel() {
                            // Check if exists
                            let existing = events.first { $0.id == event.id }
                            if existing == nil {
                                modelContext.insert(event)
                                syncedCount += 1
                            }
                        }
                    }
                    
                    do {
                        try modelContext.save()
                        errorMessage = "Synced \(syncedCount) new events from API"
                    } catch {
                        errorMessage = "Failed to save events: \(error.localizedDescription)"
                    }
                    
                    fetchEvents()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "API sync failed: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    private func generateEventsFromProjects() {
        isLoading = true
        
        do {
            // Fetch all projects
            let projectDescriptor = FetchDescriptor<Project>()
            let projects = try modelContext.fetch(projectDescriptor)
            
            var generatedCount = 0
            
            for project in projects {
                // Skip if project has no dates
                guard project.startDate != nil else { continue }
                
                // Check if event already exists
                let eventId = "project-\(project.id)"
                let existingEvent = events.first { $0.id == eventId }
                
                if existingEvent == nil {
                    // Generate event from project
                    if let event = CalendarEvent.fromProject(project, companyDefaultColor: "#59779F") {
                        modelContext.insert(event)
                        generatedCount += 1
                    }
                }
            }
            
            try modelContext.save()
            
            if generatedCount > 0 {
                errorMessage = "Generated \(generatedCount) new events"
            } else {
                errorMessage = "No new events to generate"
            }
            
            fetchEvents()
            
        } catch {
            errorMessage = "Failed to generate events: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

// Event filter chip component
struct EventFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(isSelected ? .black : OPSStyle.Colors.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(16)
        }
    }
}

// Calendar event detail card
struct CalendarEventDetailCard: View {
    let event: CalendarEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                if let icon = event.displayIcon {
                    Image(systemName: icon)
                        .foregroundColor(event.swiftUIColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                    
                    Text(event.subtitle)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(event.swiftUIColor)
                        .frame(width: 8, height: 8)
                    
                    Text(event.type.rawValue.capitalized)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(6)
            }
            
            Divider()
                .background(OPSStyle.Colors.tertiaryText)
            
            // Fields grid
            VStack(alignment: .leading, spacing: 4) {
                FieldRow(label: "ID", value: event.id)
                FieldRow(label: "Type", value: event.type.rawValue)
                FieldRow(label: "Project ID", value: event.projectId)
                FieldRow(label: "Task ID", value: event.taskId ?? "nil")
                FieldRow(label: "Company ID", value: event.companyId)
                FieldRow(label: "Color", value: event.color)
                FieldRow(label: "Duration", value: "\(event.duration) days")
                FieldRow(label: "Start Date", value: formatDate(event.startDate))
                FieldRow(label: "End Date", value: formatDate(event.endDate))
                FieldRow(label: "Multi-Day", value: event.isMultiDay ? "Yes" : "No")
                FieldRow(label: "Spanned Days", value: "\(event.spannedDates.count)")
                FieldRow(label: "Team Members", value: event.getTeamMemberIds().joined(separator: ", ").isEmpty ? "none" : event.getTeamMemberIds().joined(separator: ", "))
                FieldRow(label: "Needs Sync", value: event.needsSync ? "Yes" : "No")
                FieldRow(label: "Last Synced", value: event.lastSyncedAt?.formatted() ?? "Never")
            }
            .font(OPSStyle.Typography.smallCaption)
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Detailed sheet for a single event
struct CalendarEventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Date Range
                        Section("Date Range") {
                            VStack(alignment: .leading, spacing: 8) {
                                FieldRow(label: "Start", value: formatDateTime(event.startDate))
                                FieldRow(label: "End", value: formatDateTime(event.endDate))
                                FieldRow(label: "Duration", value: "\(event.duration) days")
                                
                                if event.isMultiDay {
                                    Text("Spanned Dates:")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    
                                    ForEach(event.spannedDates, id: \.self) { date in
                                        Text("• \(formatDate(date))")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .padding(.leading, 8)
                                    }
                                }
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(8)
                        }
                        
                        // Project Info
                        if let project = event.project {
                            Section("Project") {
                                VStack(alignment: .leading, spacing: 8) {
                                    FieldRow(label: "Title", value: project.title)
                                    FieldRow(label: "Status", value: project.status.displayName)
                                    FieldRow(label: "Client", value: project.effectiveClientName)
                                    FieldRow(label: "Address", value: project.address)
                                    
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
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(8)
                            }
                        }
                        
                        // Task Info
                        if let task = event.task {
                            Section("Task") {
                                VStack(alignment: .leading, spacing: 8) {
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
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(8)
                            }
                        }
                        
                        // Team Members
                        if !event.teamMembers.isEmpty {
                            Section("Team Members") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(event.teamMembers, id: \.id) { member in
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
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Event Details")
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