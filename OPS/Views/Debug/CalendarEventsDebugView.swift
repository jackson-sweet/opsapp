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
    @State private var searchText: String = ""
    @State private var showDeleted: Bool = false
    @State private var showingEventSearchSheet = false
    
    var filteredEvents: [CalendarEvent] {
        var filtered = events

        // Filter by deleted status
        if !showDeleted {
            filtered = filtered.filter { $0.deletedAt == nil }
        }

        // Filter by type
        if let filterType = filterType {
            filtered = filtered.filter { $0.type == filterType }
        }

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { event in
                event.id.localizedCaseInsensitiveContains(searchText) ||
                event.title.localizedCaseInsensitiveContains(searchText) ||
                event.projectId.localizedCaseInsensitiveContains(searchText) ||
                (event.taskId?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return filtered
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
                
                // Search bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        TextField("Search by ID, title, or project...", text: $searchText)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                    }
                    .padding(8)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(8)

                    Button(action: { showingEventSearchSheet = true }) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(8)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)

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

                    Spacer()

                    EventFilterChip(
                        title: showDeleted ? "Hide Deleted" : "Show Deleted",
                        isSelected: showDeleted,
                        action: { showDeleted.toggle() }
                    )
                }
                .padding(.horizontal)
                
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
        .sheet(isPresented: $showingEventSearchSheet) {
            EventSearchSheet(dataController: dataController)
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
                FieldRow(label: "Start Date", value: event.startDate.map { formatDate($0) } ?? "nil")
                FieldRow(label: "End Date", value: event.endDate.map { formatDate($0) } ?? "nil")
                FieldRow(label: "Multi-Day", value: event.isMultiDay ? "Yes" : "No")
                FieldRow(label: "Spanned Days", value: "\(event.spannedDates.count)")
                FieldRow(label: "Team Members", value: event.getTeamMemberIds().joined(separator: ", ").isEmpty ? "none" : event.getTeamMemberIds().joined(separator: ", "))
                FieldRow(label: "Active", value: event.active ? "Yes" : "No")
                FieldRow(label: "Should Display", value: event.shouldDisplay ? "Yes" : "No")
                FieldRow(label: "Needs Sync", value: event.needsSync ? "Yes" : "No")
                FieldRow(label: "Last Synced", value: event.lastSyncedAt?.formatted() ?? "Never")
                FieldRow(label: "Deleted At", value: event.deletedAt?.formatted() ?? "Not deleted")
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
                                FieldRow(label: "Start", value: event.startDate.map { formatDateTime($0) } ?? "nil")
                                FieldRow(label: "End", value: event.endDate.map { formatDateTime($0) } ?? "nil")
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

// Event search sheet - search by ID and fetch from Bubble
struct EventSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let dataController: DataController

    @State private var eventId: String = ""
    @State private var localEvent: CalendarEvent?
    @State private var bubbleEventDTO: CalendarEventDTO?
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Search input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EVENT ID")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            HStack {
                                TextField("Enter event ID (e.g., 1762212616726x338849986229004860)", text: $eventId)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(12)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(8)

                                if !eventId.isEmpty {
                                    Button(action: { eventId = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }
                                }
                            }

                            Button(action: searchEvent) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text("Search Local & Bubble")
                                }
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(8)
                            }
                            .disabled(eventId.isEmpty || isSearching)
                        }

                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                                Text(error)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(8)
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
                        if let local = localEvent {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("LOCAL SWIFTDATA", systemImage: "cylinder.fill")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.successStatus)

                                VStack(alignment: .leading, spacing: 8) {
                                    FieldRow(label: "ID", value: local.id)
                                    FieldRow(label: "Title", value: local.title)
                                    FieldRow(label: "Type", value: local.type.rawValue)
                                    FieldRow(label: "Project ID", value: local.projectId)
                                    FieldRow(label: "Task ID", value: local.taskId ?? "nil")
                                    FieldRow(label: "Company ID", value: local.companyId)
                                    FieldRow(label: "Color", value: local.color)
                                    FieldRow(label: "Start Date", value: local.startDate?.formatted() ?? "nil")
                                    FieldRow(label: "End Date", value: local.endDate?.formatted() ?? "nil")
                                    FieldRow(label: "Duration", value: "\(local.duration) days")
                                    FieldRow(label: "Active", value: local.active ? "Yes" : "No")
                                    FieldRow(label: "Should Display", value: local.shouldDisplay ? "Yes" : "No")
                                    FieldRow(label: "Deleted At", value: local.deletedAt?.formatted() ?? "Not deleted")
                                    FieldRow(label: "Last Synced", value: local.lastSyncedAt?.formatted() ?? "Never")
                                    FieldRow(label: "Needs Sync", value: local.needsSync ? "Yes" : "No")
                                }
                                .font(OPSStyle.Typography.smallCaption)
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(8)
                        } else if !isSearching && !eventId.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("LOCAL SWIFTDATA", systemImage: "cylinder.fill")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                Text("Event not found in local SwiftData")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(8)
                        }

                        // Bubble API result
                        if let bubble = bubbleEventDTO {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("BUBBLE API", systemImage: "cloud.fill")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                                VStack(alignment: .leading, spacing: 8) {
                                    FieldRow(label: "ID", value: bubble.id)
                                    FieldRow(label: "Title", value: bubble.title ?? "nil")
                                    FieldRow(label: "Type", value: bubble.type ?? "nil")
                                    FieldRow(label: "Project ID", value: bubble.projectId ?? "nil")
                                    FieldRow(label: "Task ID", value: bubble.taskId ?? "nil")
                                    FieldRow(label: "Company ID", value: bubble.companyId ?? "nil")
                                    FieldRow(label: "Color", value: bubble.color ?? "nil")
                                    FieldRow(label: "Start Date", value: bubble.startDate ?? "nil")
                                    FieldRow(label: "End Date", value: bubble.endDate ?? "nil")
                                    FieldRow(label: "Duration", value: bubble.duration.map { "\($0)" } ?? "nil")
                                    FieldRow(label: "Active", value: bubble.active.map { $0 ? "Yes" : "No" } ?? "nil")
                                    FieldRow(label: "Deleted At", value: bubble.deletedAt ?? "nil")
                                    FieldRow(label: "Team Members", value: bubble.teamMembers?.joined(separator: ", ") ?? "nil")

                                    Divider()
                                        .background(OPSStyle.Colors.tertiaryText)

                                    // DTO conversion test
                                    if let modelFromDTO = bubble.toModel() {
                                        Label("DTO Conversion: SUCCESS", systemImage: "checkmark.circle.fill")
                                            .font(OPSStyle.Typography.captionBold)
                                            .foregroundColor(OPSStyle.Colors.successStatus)
                                    } else {
                                        Label("DTO Conversion: FAILED", systemImage: "xmark.circle.fill")
                                            .font(OPSStyle.Typography.captionBold)
                                            .foregroundColor(OPSStyle.Colors.errorStatus)
                                        Text("This event will fail to sync because DTO cannot be converted to model.")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }
                                }
                                .font(OPSStyle.Typography.smallCaption)
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(8)
                        } else if !isSearching && !eventId.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("BUBBLE API", systemImage: "cloud.fill")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                Text("Event not found in Bubble API")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Search Event by ID")
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

    private func searchEvent() {
        isSearching = true
        errorMessage = nil
        localEvent = nil
        bubbleEventDTO = nil

        Task {
            // Search local SwiftData
            let localDescriptor = FetchDescriptor<CalendarEvent>(
                predicate: #Predicate { $0.id == eventId }
            )
            do {
                let localResults = try modelContext.fetch(localDescriptor)
                await MainActor.run {
                    localEvent = localResults.first
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Local search error: \(error.localizedDescription)"
                }
            }

            // Search Bubble API
            do {
                let bubbleDTO = try await dataController.apiService.fetchCalendarEvent(id: eventId)
                await MainActor.run {
                    bubbleEventDTO = bubbleDTO
                }
            } catch {
                await MainActor.run {
                    if errorMessage == nil {
                        errorMessage = "Bubble API error: \(error.localizedDescription)"
                    } else {
                        errorMessage = (errorMessage ?? "") + "\nBubble API error: \(error.localizedDescription)"
                    }
                }
            }

            await MainActor.run {
                isSearching = false
            }
        }
    }
}