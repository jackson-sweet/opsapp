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
    @State private var showingTeamMemberPicker = false
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var allTeamMembers: [TeamMember] = []
    @State private var showTeamUpdateMessage = false
    @State private var showingProjectCompletionAlert = false
    @State private var showingScheduler = false
    @State private var refreshTrigger = false  // Toggle to force view refresh
    @State private var isNotesExpanded = false
    @State private var showingDeleteConfirmation = false

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

                        Image(systemName: OPSStyle.Icons.chevronRight)
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
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
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

                        // Task type header
                        Text("TASK: \(task.taskType?.display.uppercased() ?? "TASK")")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)

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

                        // Delete task section (admin/office only)
                        if dataController.currentUser?.role == .admin || dataController.currentUser?.role == .officeCrew {
                            deleteTaskSection
                        }

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
            // Track screen view for analytics
            AnalyticsManager.shared.trackScreenView(screenName: .taskDetails, screenClass: "TaskDetailsView")

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
        .alert("Delete Task?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteTask()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete this task and any associated calendar events. This action cannot be undone.")
        }
    }
    
    // MARK: - Location Section

    private var locationSection: some View {
        SectionCard(
            icon: OPSStyle.Icons.jobSite,
            title: "Location",
            actionIcon: "arrow.triangle.turn.up.right.circle.fill",
            actionLabel: "Navigate",
            onAction: { openInMaps() }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Address
                Text(project.address ?? "No address")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                // Map view
                MiniMapView(
                    coordinate: project.coordinate,
                    address: project.address ?? ""
                ) {
                    openInMaps()
                }
                .frame(height: 180)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Info Section

    private var infoSection: some View {
        SectionCard(
            icon: "doc.text",
            title: "Task Details"
        ) {
            VStack(spacing: 16) {
                // Client field
                clientField

                // Dates field
                datesField

                // Notes field
                notesField
            }
        }
        .padding(.horizontal)
    }

    private var clientField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIENT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button(action: { showingClientContact = true }) {
                HStack(spacing: 12) {
                    Image(systemName: OPSStyle.Icons.client)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 24)

                    Text(project.effectiveClientName.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    // Contact indicators
                    HStack(spacing: 8) {
                        Image(systemName: OPSStyle.Icons.phoneFill)
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .opacity(project.effectiveClientPhone != nil ? 1.0 : 0.2)

                        Image(systemName: OPSStyle.Icons.envelopeFill)
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .opacity(project.effectiveClientEmail != nil ? 1.0 : 0.2)
                    }

                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var datesField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCHEDULE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button(action: {
                if dataController.currentUser?.role == .admin || dataController.currentUser?.role == .officeCrew {
                    showingScheduler = true
                }
            }) {
                VStack(spacing: 12) {
                    // Scheduled date
                    HStack(spacing: 12) {
                        Image(systemName: OPSStyle.Icons.calendar)
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

                        Spacer()

                        // Chevron indicator for admin/office crew
                        if dataController.currentUser?.role == .admin || dataController.currentUser?.role == .officeCrew {
                            Image(systemName: OPSStyle.Icons.chevronRight)
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }

                    // Completion date if completed
                    if task.status == .completed, let completionDate = task.completionDate {
                        Divider()
                            .background(OPSStyle.Colors.inputFieldBorder)

                        HStack(spacing: 12) {
                            Image(systemName: OPSStyle.Icons.calendarBadgeCheckmark)
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

                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .id(refreshTrigger)
            .allowsHitTesting(dataController.currentUser?.role == .admin || dataController.currentUser?.role == .officeCrew)
        }
    }

    private var notesField: some View {
        NotesDisplayField(
            title: "Task Notes",
            notes: task.taskNotes ?? "",
            isExpanded: $isNotesExpanded,
            editedNotes: $taskNotes,
            canEdit: canModify,
            onSave: saveTaskNotes
        )
    }
    
    // MARK: - Team Section

    private var teamSection: some View {
        SectionCard(
            icon: OPSStyle.Icons.personTwo,
            title: "Team Members",
            actionIcon: canModify ? "pencil.circle" : nil,
            actionLabel: canModify ? "Edit" : nil,
            onAction: canModify ? {
                // Load current team member IDs
                selectedTeamMemberIds = Set(task.getTeamMemberIds())
                // Load available team members
                loadAvailableTeamMembers()
                showingTeamMemberPicker = true
            } : nil
        ) {
            TaskTeamView(task: task)
                .environmentObject(dataController)
        }
        .padding(.horizontal)
        .sheet(isPresented: $showingTeamMemberPicker, onDismiss: {
            // Save team changes when sheet is dismissed
            saveTeamChanges()
        }) {
            TeamMemberPickerSheet(
                selectedTeamMemberIds: $selectedTeamMemberIds,
                allTeamMembers: allTeamMembers
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func loadAvailableTeamMembers() {
        guard let companyId = dataController.currentUser?.companyId else { return }

        Task {
            do {
                let userDTOs = try await dataController.apiService.fetchCompanyUsers(companyId: companyId)
                let teamMembers = userDTOs.map { TeamMember.fromUserDTO($0) }
                await MainActor.run {
                    self.allTeamMembers = teamMembers
                }
            } catch {
                print("[TASK_TEAM] Error loading available members: \(error)")
            }
        }
    }

    private func saveTeamChanges() {
        let currentIds = Set(task.getTeamMemberIds())
        guard selectedTeamMemberIds != currentIds else {
            // No changes
            return
        }

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        let newMemberIds = Array(selectedTeamMemberIds)

        // Show confirmation message
        showTeamUpdateMessage = true

        // Use centralized method which handles:
        // - Task teamMemberIdsString + teamMembers relationship
        // - Calendar event teamMemberIdsString + teamMembers relationship
        // - API sync for both task and calendar event
        // - Project team member updates
        // - Push notifications for new assignments
        Task {
            do {
                print("[TASK_DETAILS] Updating task team via centralized method...")
                try await dataController.updateTaskTeamMembers(task: task, memberIds: newMemberIds)
                print("[TASK_DETAILS] ✅ Task team update complete")
            } catch {
                print("[TASK_DETAILS] ⚠️ Team update failed: \(error)")
            }
        }
    }

    // MARK: - Status Update Section

    private var statusUpdateSection: some View {
        SectionCard(
            icon: "flag.fill",
            title: "Update Status",
            contentPadding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        ) {
            // Horizontal scrolling status chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableStatuses, id: \.self) { status in
                        StatusChip(
                            status: status,
                            isSelected: task.status == status,
                            onTap: {
                                if task.status != status {
                                    updateTaskStatus(to: status)
                                }
                            }
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Navigation Section

    private var navigationSection: some View {
        VStack(spacing: 16) {
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

            // Task navigation row - Previous / Next pills
            HStack(spacing: 12) {
                // Previous task pill
                if let prevTask = previousTask ?? fallbackPrevious {
                    navigationPill(
                        caption: "PREVIOUS",
                        label: prevTask.taskType?.display ?? "Task",
                        icon: "chevron.left",
                        iconPosition: .leading,
                        task: prevTask
                    )
                } else {
                    // Empty state for no previous task
                    emptyNavigationPill(caption: "PREVIOUS", iconPosition: .leading)
                }

                // Next task pill
                if let nextTaskToShow = nextTask ?? fallbackNext {
                    navigationPill(
                        caption: "NEXT",
                        label: nextTaskToShow.taskType?.display ?? "Task",
                        icon: "chevron.right",
                        iconPosition: .trailing,
                        task: nextTaskToShow
                    )
                } else {
                    // Empty state for no next task
                    emptyNavigationPill(caption: "NEXT", iconPosition: .trailing)
                }
            }
            .padding(.horizontal)

            // View Project pill - centered
            Button(action: {
                if taskNotes != originalTaskNotes {
                    saveTaskNotes()
                }
                showingProjectDetails = true
            }) {
                VStack(spacing: 4) {
                    Text("VIEW PROJECT")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(project.title.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .strokeBorder(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: 1)
                )
            }
            .padding(.horizontal)
        }
    }

    private enum IconPosition {
        case leading, trailing
    }

    private func navigationPill(caption: String, label: String, icon: String, iconPosition: IconPosition, task newTask: ProjectTask) -> some View {
        Button(action: {
            if taskNotes != originalTaskNotes {
                saveTaskNotes()
            }

            withAnimation(.easeInOut(duration: 0.3)) {
                self.task = newTask
                let notes = newTask.taskNotes ?? ""
                self.taskNotes = notes
                self.originalTaskNotes = notes
                loadTaskTeamMembers()
            }
        }) {
            HStack(spacing: 8) {
                if iconPosition == .leading {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                VStack(alignment: iconPosition == .leading ? .leading : .trailing, spacing: 2) {
                    Text(caption)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(label.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                }

                if iconPosition == .trailing {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .strokeBorder(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
            )
        }
    }

    private func emptyNavigationPill(caption: String, iconPosition: IconPosition) -> some View {
        HStack(spacing: 8) {
            if iconPosition == .leading {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.5))
            }

            VStack(alignment: iconPosition == .leading ? .leading : .trailing, spacing: 2) {
                Text(caption)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text("NO TASK")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.5))
            }

            if iconPosition == .trailing {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.inputFieldBorder.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Delete Task Section

    private var deleteTaskSection: some View {
        Button(action: {
            showingDeleteConfirmation = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                Text("DELETE TASK")
                    .font(OPSStyle.Typography.captionBold)
            }
            .foregroundColor(OPSStyle.Colors.errorStatus.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .strokeBorder(OPSStyle.Colors.errorStatus.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.top, 8)
    }

    private func deleteTask() {
        // Haptic feedback for destructive action
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        // Capture task ID before deletion
        let taskId = task.id

        Task {
            do {
                // Delete from server first
                try await dataController.deleteTask(task)
                print("[TASK_DELETE] ✅ Task deleted successfully: \(taskId)")

                // Dismiss the view after successful deletion
                await MainActor.run {
                    // Notify calendar views to refresh
                    dataController.calendarEventsDidChange.toggle()
                    dismiss()
                }
            } catch {
                print("[TASK_DELETE] ❌ Failed to delete task: \(error)")
                // Show error - could add an error alert here
            }
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
            // Task-only scheduling migration: 'active' property removed
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
        // Task-only scheduling migration: 'active' property removed
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
                        BubbleFields.CalendarEvent.duration: 0
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
            return OPSStyle.Icons.calendar
        case .inProgress:
            // NOTE: Missing icon in OPSStyle - "hammer.fill" (In-progress status icon)
            return "hammer.fill"
        case .completed:
            return OPSStyle.Icons.checkmark
        case .cancelled:
            return OPSStyle.Icons.xmark
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
        ZStack(alignment: .top) {
            // Notes saved notification
            if showingSaveNotification {
                HStack(spacing: 8) {
                    Image(systemName: OPSStyle.Icons.complete)
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

            // Team update push-in message (uses its own positioning)
            PushInMessage(
                isPresented: $showTeamUpdateMessage,
                title: "TEAM UPDATED",
                subtitle: "\(selectedTeamMemberIds.count) member\(selectedTeamMemberIds.count == 1 ? "" : "s") assigned",
                type: .success,
                autoDismissAfter: 3.0
            )
        }
    }
}

// MARK: - Status Chip Component

/// Compact horizontal status chip for task status selection
private struct StatusChip: View {
    let status: TaskStatus
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(status.displayName.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(isSelected ? .white : status.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(isSelected ? status.color : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .strokeBorder(status.color, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

