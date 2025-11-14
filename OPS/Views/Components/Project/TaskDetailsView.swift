//
//  TaskDetailsView.swift
//  OPS
//
//  Detailed view for a specific task within a project
//

import SwiftUI
import SwiftData
import MapKit

struct TaskDetailsView: View {
    @State var task: ProjectTask
    let project: Project
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Query private var users: [User]
    
    @State private var taskNotes: String
    @State private var originalTaskNotes: String
    @State private var showingUnsavedChangesAlert = false
    @State private var showingSaveNotification = false
    @State private var notificationTimer: Timer?
    @State private var showingClientContact = false
    @State private var showingProjectDetails = false
    @State private var loadedTeamMembers: [User] = []
    @State private var selectedTeamMember: User? = nil
    @State private var showingTeamMemberDetails = false
    @State private var isEditingTeam = false
    @State private var triggerTeamSave = false
    @State private var showingProjectCompletionAlert = false
    @State private var showingScheduler = false
    @State private var refreshTrigger = false  // Toggle to force view refresh
    @State private var isNotesExpanded = false

    init(task: ProjectTask, project: Project) {
        self._task = State(initialValue: task)
        self.project = project
        let notes = task.taskNotes ?? ""
        _taskNotes = State(initialValue: notes)
        _originalTaskNotes = State(initialValue: notes)
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            Color.black
                .edgesIgnoringSafeArea(.all)
            
            // Main content
            VStack(spacing: 0) {
                // Modern header with frosted glass effect (matching ProjectDetailsView)
                ZStack {
                    // Blurred background
                    BlurView(style: .dark)
                        .edgesIgnoringSafeArea(.top)
                    
                    // Header content
                    VStack(spacing: 8) {
                        // Top row with status and buttons
                        HStack {
                            // Status badge
                            Text(task.status.displayName.uppercased())
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(task.status.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(task.status.color.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(task.status.color, lineWidth: 1)
                                )
                            
                            Spacer()
                            
                            // Done button
                            Button("Done") {
                                checkForUnsavedChanges()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white)
                            .foregroundColor(Color.black)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                            .font(OPSStyle.Typography.bodyBold)
                        }
                        
                        // Breadcrumb navigation
                        HStack {
                            Button(action: { 
                                showingProjectDetails = true
                            }) {
                                Text(project.title)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .lineLimit(1)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            
                            Text(task.taskType?.display ?? "Task")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 90)
                .background(task.status == .completed ? 
                           OPSStyle.Colors.cardBackgroundDark : 
                           Color.black)
                
                // Color stripe at bottom of header
                Rectangle()
                    .fill(Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent)
                    .frame(height: 3)
                
                // Main scrollable content
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // Location map - matching ProjectDetailsView style
                        locationSection
                        
                        // Task info sections - matching ProjectDetailsView card style
                        infoSection
                        
                        // Team members section - matching ProjectDetailsView
                        teamSection
                        
                        // Status update section
                        statusUpdateSection
                        
                        // Navigation cards
                        navigationSection
                        
                        // Bottom padding
                        Spacer()
                            .frame(height: 80)
                    }
                    .padding(.top, 16)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            loadTaskTeamMembers()
            logTaskTeamMemberData()
        }
        .sheet(isPresented: $showingTeamMemberDetails) {
            if let selectedMember = selectedTeamMember {
                ContactDetailView(user: selectedMember)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.medium, .large])
            }
        }
        .overlay(saveNotificationOverlay)
        .confirmationDialog(
            "Unsaved Changes",
            isPresented: $showingUnsavedChangesAlert,
            titleVisibility: .visible
        ) {
            Button("Save Changes", role: .none) {
                saveTaskNotes()
                dismiss()
            }
            
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes to your notes. Would you like to save them before leaving?")
        }
        .sheet(isPresented: $showingProjectDetails) {
            ProjectDetailsView(project: project)
                .environmentObject(dataController)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingTeamMemberDetails) {
            if let member = selectedTeamMember {
                ContactDetailView(user: member)
                    .presentationDragIndicator(.visible)
                    .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingClientContact) {
            // Pass the actual Client object if available, otherwise create a temporary one
            if let client = project.client {
                ContactDetailView(client: client, project: project)
                    .presentationDragIndicator(.visible)
                    .environmentObject(dataController)
            } else {
                // Fallback: Create a temporary TeamMember for client contact
                let clientTeamMember = TeamMember(
                    id: "client-\(project.id)",
                    firstName: project.effectiveClientName.components(separatedBy: " ").first ?? project.effectiveClientName,
                    lastName: project.effectiveClientName.components(separatedBy: " ").dropFirst().joined(separator: " "),
                    role: "Client",
                    avatarURL: nil,
                    email: project.effectiveClientEmail,
                    phone: project.effectiveClientPhone
                )

                ContactDetailView(teamMember: clientTeamMember)
                    .presentationDragIndicator(.visible)
                    .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingScheduler) {
            CalendarSchedulerSheet(
                isPresented: $showingScheduler,
                itemType: .task(task),
                currentStartDate: task.scheduledDate,
                currentEndDate: task.completionDate,
                onScheduleUpdate: { startDate, endDate in
                    handleScheduleUpdate(startDate: startDate, endDate: endDate)
                },
                onClearDates: {
                    handleClearDates()
                }
            )
            .environmentObject(dataController)
        }
        .onAppear {
            logTaskTeamMemberData()
        }
        .onDisappear {
            notificationTimer?.invalidate()
            notificationTimer = nil
        }
        .alert("Complete Project?", isPresented: $showingProjectCompletionAlert) {
            Button("Complete Project", role: .destructive) {
                completeProject()
            }
            Button("Keep Project Active", role: .cancel) { }
        } message: {
            Text("All tasks in this project are now complete. Would you like to mark the entire project as completed?")
        }
    }
    
    // MARK: - Location Section (matching ProjectDetailsView)
    
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Location section label
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text("LOCATION")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                Button(action: {
                    openInMaps()
                }) {
                    Text("Get Directions")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                }
            }
            .padding(.horizontal)
            
            // Address text
            Text(project.address ?? "No address")
                .font(OPSStyle.Typography.body)
                .foregroundColor(.white)
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            // Map view - larger and more prominent
            ZStack(alignment: .bottomTrailing) {
                MiniMapView(
                    coordinate: project.coordinate,
                    address: project.address ?? ""
                ) {
                    openInMaps()
                }
                .frame(height: 180)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                
                // Directions button on map
                Button(action: { openInMaps() }) {
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 14))
                        
                        Text("Directions")
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                }
                .padding(12)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Info Section (matching ProjectDetailsView card style)
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Card-based info items
            VStack(spacing: 1) {
                // Client card with tap interaction
                Button(action: {
                    showingClientContact = true
                }) {
                    HStack {
                        infoRow(
                            icon: "person",
                            title: "CLIENT",
                            value: project.effectiveClientName.uppercased(),
                            valueColor: OPSStyle.Colors.primaryText,
                            showChevron: true
                        )
                        
                        // Contact indicators
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 18))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .opacity(project.effectiveClientPhone != nil ? 1.0 : 0.2)
                            
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 18))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .opacity(project.effectiveClientEmail != nil ? 1.0 : 0.2)
                        }
                        .padding(.trailing, 12)
                        
                    }.background(OPSStyle.Colors.cardBackgroundDark)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Task dates - make tappable for admin/office crew
                Button(action: {
                    if dataController.currentUser?.role == .admin || dataController.currentUser?.role == .officeCrew {
                        showingScheduler = true
                    }
                }) {
                    HStack(spacing: 0) {
                        // Scheduled date
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("SCHEDULED")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                if let date = task.scheduledDate {
                                    Text(formatDate(date))
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                } else if let calendarEvent = task.calendarEvent, let start = calendarEvent.startDate, let end = calendarEvent.endDate {
                                    Text(formatDateRange(start, end))
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                } else {
                                    Text("Tap to Schedule")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Completion date if completed
                        if task.status == .completed,
                           let completionDate = task.completionDate {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar.badge.checkmark")
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("COMPLETED")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    Text(formatDate(completionDate))
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Chevron indicator for admin/office crew to show it's tappable
                        if dataController.currentUser?.role == .admin || dataController.currentUser?.role == .officeCrew {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.trailing, 12)
                        }
                    }
                    .padding()
                    .background(OPSStyle.Colors.cardBackgroundDark)
                }
                .buttonStyle(PlainButtonStyle())
                .id(refreshTrigger)  // Force refresh when dates change
                .disabled(!(dataController.currentUser?.role == .admin || dataController.currentUser?.role == .officeCrew))
                
                // Task notes section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "note.text")
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 24)

                        Text("TASK NOTES")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        Image(systemName: isNotesExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isNotesExpanded.toggle()
                        }
                    }

                    // Expandable notes view
                    ExpandableNotesView(
                        notes: task.taskNotes ?? "",
                        isExpanded: $isNotesExpanded,
                        editedNotes: $taskNotes,
                        onSave: saveTaskNotes
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OPSStyle.Colors.cardBackgroundDark)
            }
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
    
    // MARK: - Team Section (matching ProjectDetailsView)
    
    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section heading outside the card
            HStack {
                Image(systemName: "person.2")
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("TEAM MEMBERS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                if canModify {
                    Button(action: {
                        if isEditingTeam {
                            // Trigger save when Done is pressed
                            triggerTeamSave.toggle()
                            // Exit edit mode after triggering save
                            isEditingTeam = false
                        } else {
                            isEditingTeam.toggle()
                        }
                    }) {
                        Text(isEditingTeam ? "Done" : "Edit")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal)

            // Team members content - using TaskTeamView
            TaskTeamView(task: task, isEditing: $isEditingTeam, triggerSave: $triggerTeamSave)
                .environmentObject(dataController)
                .padding(.horizontal)
        }
    }

    // MARK: - Status Update Section
    
    private var statusUpdateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section heading
            HStack {
                Image(systemName: "flag")
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text("UPDATE STATUS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Tactical status list
            VStack(spacing: 1) {
                ForEach(availableStatuses, id: \.self) { status in
                    Button(action: {
                        updateTaskStatus(to: status)
                    }) {
                        HStack(spacing: 16) {
                            // Status indicator - checkmark for current, circle for others
                            ZStack {
                                if task.status == status {
                                    Circle()
                                        .fill(statusColor(for: status))
                                        .frame(width: 24, height: 24)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                } else {
                                    Circle()
                                        .stroke(OPSStyle.Colors.tertiaryText.opacity(0.3), lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                }
                            }
                            
                            // Status icon and text
                            Image(systemName: statusIcon(for: status))
                                .font(.system(size: 16))
                                .foregroundColor(task.status == status ?
                                               OPSStyle.Colors.primaryText :
                                               OPSStyle.Colors.secondaryText)
                                .frame(width: 20)
                            
                            Text(status.displayName.uppercased())
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(task.status == status ?
                                               OPSStyle.Colors.primaryText :
                                               OPSStyle.Colors.secondaryText)
                            
                            Spacer()
                            
                            // Status color accent bar
                            Rectangle()
                                .fill(statusColor(for: status))
                                .frame(width: 3, height: 30)
                                .opacity(task.status == status ? 1.0 : 0.3)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(task.status == status ? 
                                  OPSStyle.Colors.cardBackgroundDark.opacity(0.8) :
                                  OPSStyle.Colors.cardBackgroundDark)
                    }
                    .disabled(task.status == status)
                }
            }
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
    
    // MARK: - Navigation Section
    
    private var navigationSection: some View {
        VStack(spacing: 12) {
            // Sort tasks and find current position
            let sortedTasks = project.tasks.sorted { $0.displayOrder < $1.displayOrder }
            
            // Find previous and next tasks based on display order, not array position
            let currentOrder = task.displayOrder
            let previousTask = sortedTasks.last(where: { $0.displayOrder < currentOrder && $0.id != task.id })
            let nextTask = sortedTasks.first(where: { $0.displayOrder > currentOrder && $0.id != task.id })
            
            // If display orders are the same, fallback to array position
            let fallbackIndex = sortedTasks.firstIndex(where: { $0.id == task.id })
            let fallbackPrevious = fallbackIndex.map { index in
                index > 0 ? sortedTasks[index - 1] : nil
            }?.flatMap { $0 }
            let fallbackNext = fallbackIndex.map { index in
                index < sortedTasks.count - 1 ? sortedTasks[index + 1] : nil
            }?.flatMap { $0 }
            
            HStack(spacing: 12) {
                // Previous task
                if let prevTask = previousTask ?? fallbackPrevious {
                    navigationCard(
                        title: "Previous",
                        task: prevTask,
                        icon: "chevron.left.circle.fill",
                        alignment: .leading
                    )
                }
                
                // Next task
                if let nextTaskToShow = nextTask ?? fallbackNext {
                    navigationCard(
                        title: "Next",
                        task: nextTaskToShow,
                        icon: "chevron.right.circle.fill",
                        alignment: .trailing
                    )
                }
            }
            .padding(.horizontal)
            
            // View Project button
            Button(action: {
                // Save any unsaved notes before navigating
                if taskNotes != originalTaskNotes {
                    saveTaskNotes()
                }
                showingProjectDetails = true
            }) {
                HStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 20))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VIEW PROJECT")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Text(project.title.uppercased())
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(.horizontal)
        }
    }
    
    private func navigationCard(title: String, task newTask: ProjectTask, icon: String, alignment: HorizontalAlignment) -> some View {
        Button(action: {
            // Save current notes if needed before navigating
            if taskNotes != originalTaskNotes {
                saveTaskNotes()
            }
            
            // Update to show the new task
            withAnimation(.easeInOut(duration: 0.3)) {
                self.task = newTask
                // Update notes state for the new task
                let notes = newTask.taskNotes ?? ""
                self.taskNotes = notes
                self.originalTaskNotes = notes
                // Reload team members for the new task
                loadTaskTeamMembers()
            }
        }) {
            VStack(alignment: alignment, spacing: 4) {
                HStack {
                    if alignment == .leading {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    
                    VStack(alignment: alignment, spacing: 2) {
                        Text("\(title) Task")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Text(newTask.taskType?.display ?? "Task")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    
                    if alignment == .trailing {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Schedule Update

    private func handleScheduleUpdate(startDate: Date, endDate: Date) {
        print("🔄 Task handleScheduleUpdate called - New dates: \(startDate) to \(endDate)")

        // Update or create the calendar event for the task
        if let calendarEvent = task.calendarEvent {
            // Update existing calendar event
            print("🔄 Updating existing calendar event")
            calendarEvent.startDate = startDate
            calendarEvent.endDate = endDate
            let daysDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            calendarEvent.duration = daysDiff + 1
            calendarEvent.active = true  // Mark as active when scheduled
            calendarEvent.needsSync = true
        } else {
            // Create new calendar event for the task
            print("🔄 Creating new calendar event for task")
            let newEvent = CalendarEvent.fromTask(task, startDate: startDate, endDate: endDate)
            task.calendarEvent = newEvent
            modelContext.insert(newEvent)
        }

        task.needsSync = true

        // Update parent project dates if necessary
        if let project = task.project {
            let allTaskEvents = project.tasks.compactMap { $0.calendarEvent }
            if !allTaskEvents.isEmpty {
                let earliestStart = allTaskEvents.compactMap { $0.startDate }.min() ?? startDate
                let latestEnd = allTaskEvents.compactMap { $0.endDate }.max() ?? endDate

                if project.startDate != earliestStart || project.endDate != latestEnd {
                    print("🔄 Updating project dates to match task range")
                    project.startDate = earliestStart
                    project.endDate = latestEnd
                    project.needsSync = true
                }
            }
        }

        // Save to database
        do {
            try modelContext.save()
            print("✅ Successfully saved task schedule update")

            // Force view refresh to show updated dates
            refreshTrigger.toggle()

            // Notify calendar views to refresh
            dataController.calendarEventsDidChange.toggle()

            // Immediately sync calendar event to server to prevent reversion
            if let calendarEvent = task.calendarEvent {
                Task {
                    await syncCalendarEventToServer(calendarEvent)
                }
            }
        } catch {
            print("❌ Failed to save task schedule update: \(error)")
        }

        // Don't show notification - haptic feedback is enough
    }

    private func handleClearDates() {
        print("🗑️ handleClearDates called - Clearing task dates")

        // Capture IDs and data before async work to avoid holding references
        guard let calendarEvent = task.calendarEvent else {
            print("ℹ️ No calendar event to clear for this task")
            return
        }

        let calendarEventId = calendarEvent.id
        let projectId = task.project?.id

        print("🗑️ Clearing calendar event dates: \(calendarEventId)")

        // Clear dates locally
        calendarEvent.startDate = nil
        calendarEvent.endDate = nil
        calendarEvent.duration = 0
        calendarEvent.active = false  // Mark as inactive when unscheduled
        calendarEvent.needsSync = true
        task.needsSync = true

        // Capture scheduled task data for recalculation
        let scheduledTaskDates: [(start: Date, end: Date)]? = task.project?.tasks.compactMap { projectTask in
            guard let event = projectTask.calendarEvent,
                  projectTask.id != task.id, // Exclude current task
                  let start = event.startDate,
                  let end = event.endDate else {
                return nil
            }
            return (start, end)
        }

        // Save to database
        do {
            try modelContext.save()
            print("✅ Successfully cleared calendar event dates")

            // Force view refresh to show cleared dates
            refreshTrigger.toggle()

            // Notify calendar views to refresh
            dataController.calendarEventsDidChange.toggle()

            // Sync to Bubble
            Task {
                do {
                    // STEP 1: Clear calendar event dates in Bubble
                    print("📡 Clearing calendar event dates in Bubble...")
                    let updates: [String: Any] = [
                        BubbleFields.CalendarEvent.startDate: NSNull(),
                        BubbleFields.CalendarEvent.endDate: NSNull(),
                        BubbleFields.CalendarEvent.duration: 0,
                        BubbleFields.CalendarEvent.active: false
                    ]

                    try await dataController.apiService.updateCalendarEvent(
                        id: calendarEventId,
                        updates: updates
                    )
                    print("✅ Calendar event dates cleared in Bubble")

                    // STEP 2: Recalculate parent project dates
                    if let projId = projectId {
                        print("🔄 Recalculating parent project dates...")

                        if let dates = scheduledTaskDates, !dates.isEmpty {
                            // Recalculate from remaining scheduled tasks
                            let earliestStart = dates.map { $0.start }.min()
                            let latestEnd = dates.map { $0.end }.max()

                            print("📅 New project dates: \(earliestStart?.description ?? "nil") to \(latestEnd?.description ?? "nil")")

                            // Update in Bubble
                            if let start = earliestStart, let end = latestEnd {
                                try await dataController.apiService.updateProjectDates(
                                    projectId: projId,
                                    startDate: start,
                                    endDate: end
                                )
                                print("✅ Project dates updated in Bubble")
                            }
                        } else {
                            // No tasks have dates - clear project dates
                            print("🗑️ No scheduled tasks - clearing project dates")

                            // Clear in Bubble
                            try await dataController.apiService.updateProjectDates(
                                projectId: projId,
                                startDate: nil,
                                endDate: nil,
                                clearDates: true
                            )
                            print("✅ Project dates cleared")
                        }
                    }
                } catch {
                    print("❌ Failed to clear dates in Bubble: \(error)")
                }
            }
        } catch {
            print("❌ Failed to save cleared task dates: \(error)")
        }
    }

    private func syncCalendarEventToServer(_ calendarEvent: CalendarEvent) async {
        print("🔄 Syncing task calendar event to server: \(calendarEvent.id)")

        do {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]

            // Check if this is a new event that needs to be created on the server
            let isNewEvent = calendarEvent.lastSyncedAt == nil

            if isNewEvent {
                print("📅 Creating new calendar event on server for task")

                // Get company's default project color
                let company = dataController.getCompany(id: task.companyId)
                let projectColor = company?.defaultProjectColor ?? "#9CA3AF"

                // Get task type display name for the title
                let taskTypeName = task.taskType?.display ?? "Task"
                let taskTitle = "\(taskTypeName) - \(project.title)"

                let eventDTO = CalendarEventDTO(
                    id: calendarEvent.id,
                    color: task.taskColor,
                    companyId: task.companyId,
                    projectId: task.projectId,
                    taskId: task.id,
                    duration: Double(calendarEvent.duration),
                    endDate: calendarEvent.endDate.map { formatter.string(from: $0) } ?? "",
                    startDate: calendarEvent.startDate.map { formatter.string(from: $0) } ?? "",
                    teamMembers: task.getTeamMemberIds(),
                    title: taskTitle,
                    type: "Task",
                    active: true,
                    createdDate: nil,
                    modifiedDate: nil,
                    deletedAt: nil
                )

                let createdEvent = try await dataController.apiService.createAndLinkCalendarEvent(eventDTO)
                print("✅ Task calendar event created on server with ID: \(createdEvent.id)")
            } else {
                print("📅 Updating existing calendar event on server")

                let startDateString = calendarEvent.startDate.map { formatter.string(from: $0) } ?? ""
                let endDateString = calendarEvent.endDate.map { formatter.string(from: $0) } ?? ""

                let updates: [String: Any] = [
                    BubbleFields.CalendarEvent.startDate: startDateString,
                    BubbleFields.CalendarEvent.endDate: endDateString,
                    BubbleFields.CalendarEvent.duration: calendarEvent.duration
                ]

                try await dataController.apiService.updateCalendarEvent(id: calendarEvent.id, updates: updates)
                print("✅ Task calendar event updated on server")
            }

            await MainActor.run {
                calendarEvent.needsSync = false
                calendarEvent.lastSyncedAt = Date()
                try? modelContext.save()
            }

            print("✅ Task calendar event synced successfully to server")
        } catch {
            print("⚠️ Failed to sync task calendar event to server: \(error)")
        }
    }

    // MARK: - Debug Logging

    private func logTaskTeamMemberData() {
        print("\n========== TASK DETAILS VIEW: Team Member Debug ==========")
        print("📱 SCREEN: TaskDetailsView loaded for task")
        print("📊 DATA: Task ID: \(task.id)")
        print("📊 DATA: Task Type: \(task.taskType?.display ?? "Unknown")")
        print("📊 DATA: Task Status: \(task.status.displayName)")
        print("📊 DATA: Project ID: \(task.projectId)")
        print("📊 DATA: Project Title: \(project.title)")
        
        // Log team member string storage
        print("📊 DATA: teamMemberIdsString: '\(task.teamMemberIdsString)'")
        let teamMemberIds = task.getTeamMemberIds()
        print("📊 DATA: Team member IDs from string: \(teamMemberIds)")
        print("📊 DATA: Team member ID count: \(teamMemberIds.count)")
        
        // Log team member relationship
        print("📊 DATA: task.teamMembers array count: \(task.teamMembers.count)")
        for (index, member) in task.teamMembers.enumerated() {
            print("📊 DATA: Team member \(index + 1): \(member.fullName) (ID: \(member.id))")
            print("📊 DATA:   - Role: \(member.role.displayName)")
            print("📊 DATA:   - Company: \(member.companyId ?? "No company")")
            print("📊 DATA:   - Email: \(member.email ?? "No email")")
            print("📊 DATA:   - Phone: \(member.phone ?? "No phone")")
        }
        
        // Check if team member objects match IDs
        let memberObjectIds = Set(task.teamMembers.map { $0.id })
        let storedIds = Set(teamMemberIds)
        let missingFromObjects = storedIds.subtracting(memberObjectIds)
        let extraInObjects = memberObjectIds.subtracting(storedIds)
        
        if !missingFromObjects.isEmpty {
            print("⚠️ DATA: Team member IDs in string but missing from objects: \(missingFromObjects)")
        }
        if !extraInObjects.isEmpty {
            print("⚠️ DATA: Team member objects present but not in ID string: \(extraInObjects)")
        }
        if missingFromObjects.isEmpty && extraInObjects.isEmpty && !teamMemberIds.isEmpty {
            print("✅ DATA: Team member IDs and objects are in sync")
        } else if teamMemberIds.isEmpty && task.teamMembers.isEmpty {
            print("💡 DATA: No team members assigned to this task")
        }
        
        // Log calendar event relationship
        if let calendarEvent = task.calendarEvent {
            print("📅 DATA: Task has calendar event: \(calendarEvent.id)")
            print("📅 DATA: Calendar event team member count: \(calendarEvent.teamMembers.count)")
            let calendarEventIds = calendarEvent.getTeamMemberIds()
            print("📅 DATA: Calendar event team member IDs: \(calendarEventIds)")
        } else {
            print("📅 DATA: Task has no calendar event")
        }
        
        print("=====================================================")
    }
    
    // MARK: - Helper Methods
    
    private var availableStatuses: [TaskStatus] {
        // Only office crew and admins can cancel tasks
        guard let currentUser = dataController.currentUser else {
            return [.booked, .inProgress, .completed]
        }
        
        if currentUser.role == .admin || currentUser.role == .officeCrew {
            return TaskStatus.allCases
        } else {
            return [.booked, .inProgress, .completed]
        }
    }
    
    private func infoRow(icon: String, title: String, value: String, valueColor: Color = .white, showChevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(value)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(valueColor)
            }
            
            Spacer()
            
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
    }
    
    private func checkForUnsavedChanges() {
        if taskNotes != originalTaskNotes {
            showingUnsavedChangesAlert = true
        } else {
            dismiss()
        }
    }
    
    private func saveTaskNotes() {
        // Haptic feedback on save
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        task.taskNotes = taskNotes.isEmpty ? nil : taskNotes
        task.needsSync = true
        try? dataController.modelContext?.save()

        originalTaskNotes = taskNotes
        showSaveNotification()

        // Sync to API
        Task {
            await syncTaskNotesToAPI()
        }
    }
    
    @MainActor
    private func syncTaskNotesToAPI() async {
        guard let syncManager = dataController.syncManager else { return }
        
        do {
            print("📤 Syncing task notes to API")
            try await syncManager.updateTaskNotes(taskId: task.id, notes: task.taskNotes ?? "")
            print("✅ Task notes synced successfully")
            task.needsSync = false
            try? dataController.modelContext?.save()
        } catch {
            print("❌ Failed to sync task notes: \(error)")
        }
    }
    
    private func updateTaskStatus(to newStatus: TaskStatus) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Handle project status updates before task status update
        if newStatus == .inProgress {
            if project.status == .completed {
                project.status = .inProgress
                project.needsSync = true
                Task {
                    try? await dataController.syncManager.updateProjectStatus(
                        projectId: project.id,
                        status: .inProgress,
                        forceSync: true
                    )
                }
            }
        }

        // Use centralized status update function - handles local update AND Bubble sync
        Task {
            do {
                try await dataController.updateTaskStatus(task: task, to: newStatus)

                // Check if all tasks are complete after successful update
                if newStatus == .completed {
                    await MainActor.run {
                        checkIfAllTasksComplete()
                    }
                }
            } catch {
                print("[TASK_DETAILS] ❌ Failed to update task status: \(error)")
            }
        }
    }
    
    private func statusColor(for status: TaskStatus) -> Color {
        return status.color
    }
    
    private func statusIcon(for status: TaskStatus) -> String {
        switch status {
        case .booked:
            return "calendar"
        case .inProgress:
            return "hammer.fill"
        case .completed:
            return "checkmark"
        case .cancelled:
            return "xmark"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private var canModify: Bool {
        guard let user = dataController.currentUser else { return false }
        return user.role == .admin || user.role == .officeCrew
    }

    private func formatDateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        } else {
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }
    }
    
    private func openInMaps() {
        guard let lat = project.latitude, let lon = project.longitude else { return }
        
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = project.address
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
    
    // MARK: - Helper Methods for Team Members
    
    private func loadTaskTeamMembers() {
        print("\n📱 TaskDetailsView: Loading team members for task")
        print("   Task ID: \(task.id)")
        print("   Task Type: \(task.taskType?.display ?? "Unknown")")
        
        // Get team member IDs
        let teamMemberIds = task.getTeamMemberIds()
        print("   Team Member IDs stored: \(teamMemberIds.joined(separator: ", "))")
        print("   Team Members array count: \(task.teamMembers.count)")
        
        // If we have IDs but no team member objects, try to load them
        if !teamMemberIds.isEmpty && task.teamMembers.isEmpty {
            print("   ⚠️ Team member IDs exist but objects are empty, attempting to load...")
            
            var loadedMembers: [User] = []
            for memberId in teamMemberIds {
                // Try to find the user in the Query results
                if let user = users.first(where: { $0.id == memberId }) {
                    loadedMembers.append(user)
                    print("   ✅ Loaded team member: \(user.fullName) (\(user.id))")
                } else {
                    print("   ❌ Could not find user with ID: \(memberId)")
                }
            }
            
            // Update the loaded team members
            if !loadedMembers.isEmpty {
                loadedTeamMembers = loadedMembers
                print("   ✅ Successfully loaded \(loadedMembers.count) team members")
            }
        } else if !task.teamMembers.isEmpty {
            // Team members are already loaded
            loadedTeamMembers = Array(task.teamMembers)
            print("   ✅ Task already has \(task.teamMembers.count) team members loaded")
        } else {
            print("   ℹ️ No team members assigned to this task")
        }
    }
    
    // MARK: - Project Completion Check
    
    private func checkIfAllTasksComplete() {
        // Check if all tasks in the project are complete
        let allTasks = project.tasks
        let incompleteTasks = allTasks.filter { $0.status != .completed && $0.status != .cancelled }
        
        // If all tasks are complete or cancelled, show the alert
        if incompleteTasks.isEmpty && !allTasks.isEmpty {
            // Add a small delay to let the UI update first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingProjectCompletionAlert = true
            }
        }
    }
    
    private func completeProject() {
        // Update project status to completed
        project.status = .completed
        project.needsSync = true
        
        // Save to model context
        if let modelContext = dataController.modelContext {
            try? modelContext.save()
        }
        
        // Sync to API
        Task {
            try? await dataController.syncManager?.updateProjectStatus(
                projectId: project.id,
                status: .completed,
                forceSync: true
            )
            
            // Exit project mode after completing
            await MainActor.run {
                appState.exitProjectMode()
                dismiss()
            }
        }
    }
    
    // MARK: - Save Notification
    
    private func showSaveNotification() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showingSaveNotification = true
        }
        
        notificationTimer?.invalidate()
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showingSaveNotification = false
            }
        }
    }
    
    private var saveNotificationOverlay: some View {
        VStack {
            if showingSaveNotification {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(OPSStyle.Colors.successStatus)
                    
                    Text("Notes saved")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(.white)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 50)
            }
            
            Spacer()
        }
    }
}

