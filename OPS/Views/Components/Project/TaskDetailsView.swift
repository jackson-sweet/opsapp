//
//  TaskDetailsView.swift
//  OPS
//
//  Detailed view for a specific task within a project
//

import SwiftUI
import SwiftData
import MapKit
import Supabase

struct TaskDetailsView: View {
    @State var task: ProjectTask
    let project: Project

    private enum MaterialHistoryLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @Query private var users: [User]
    
    @State private var showingSaveNotification = false
    @State private var notificationTimer: Timer?
    @State private var showingClientContact = false
    @State private var showingProjectDetails = false
    @State private var loadedTeamMembers: [User] = []
    @State private var selectedTeamMember: User? = nil
    @State private var showingTeamMemberDetails = false
    @State private var showingTeamMemberPicker = false
    @State private var selectedTeamMemberIds: Set<String> = []
    /// Team members as full User objects so UserAvatar can render real profile
    /// photos (profileImageData / profileImageURL / userColor). The previous
    /// TeamMember projection stripped profileImageData, forcing every row to
    /// fall back to the initials placeholder.
    @State private var allTeamMembers: [User] = []
    @State private var showTeamUpdateMessage = false
    @State private var showingProjectCompletionAlert = false
    @State private var showingScheduler = false
    @State private var refreshTrigger = false  // Toggle to force view refresh
    @State private var showingDeleteConfirmation = false
    @State private var materialHistory: TaskMaterialHistory = .empty
    @State private var materialHistoryLoadState: MaterialHistoryLoadState = .idle
    /// Company inventory operating mode. The Material History card only exists
    /// for tracked companies; off-mode companies must not see an empty em-dash
    /// card. Resolved from `company_inventory_settings`, never inferred from the
    /// absence of demand rows. Defaults to `.off` until the real value loads so
    /// the card stays hidden rather than flashing for off-mode companies.
    @State private var companyInventoryMode: InventoryMode = .off

    init(task: ProjectTask, project: Project) {
        self._task = State(initialValue: task)
        self.project = project
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            OPSStyle.Colors.background
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
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .fill(task.status.color.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(task.status.color, lineWidth: OPSStyle.Layout.Border.standard)
                            )

                        Spacer()

                        // Done button
                        Button("Done") {
                            dismiss()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(OPSStyle.Colors.primaryText)
                        .foregroundColor(OPSStyle.Colors.invertedText)
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
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text(task.taskType?.display ?? "Task")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .background(task.status == .completed ?
                           OPSStyle.Colors.cardBackgroundDark :
                           OPSStyle.Colors.background)
                
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

                        // Source attribution (visible to all roles)
                        if let _ = task.sourceEstimateId {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Image(systemName: OPSStyle.Icons.estimateDoc)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                Text("[AUTO-GENERATED FROM ESTIMATE]")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                Spacer()
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3)

                        }

                        // Location map - matching ProjectDetailsView style
                        locationSection
                        
                        // Task info sections - matching ProjectDetailsView card style
                        infoSection

                        // Material History is meaningless when the company
                        // doesn't track inventory — hide the whole card rather
                        // than render an empty em-dash for off-mode companies.
                        if companyInventoryMode.isTracked {
                            materialHistorySection
                        }

                        // Team members section - matching ProjectDetailsView
                        teamSection
                        
                        // Status update section
                        statusUpdateSection
                        
                        // Navigation cards
                        navigationSection

                        // Delete task section (permission-gated)
                        if permissionStore.can("tasks.delete") {
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
        .trackScreen("TaskDetails")
        .navigationBarHidden(true)
        .onAppear {
            // Track screen view for analytics
            AnalyticsManager.shared.trackScreenView(screenName: .taskDetails, screenClass: "TaskDetailsView")
            AnalyticsService.shared.trackScreenView(screenName: "task_details")

            loadTaskTeamMembers()
            logTaskTeamMemberData()
            loadMaterialHistory()
        }
        .onChange(of: task.id) { _, _ in
            loadMaterialHistory()
        }
        .sheet(isPresented: $showingTeamMemberDetails) {
            if let selectedMember = selectedTeamMember {
                ContactDetailView(user: selectedMember)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.medium, .large])
                    .environmentObject(dataController)
            }
        }
        .overlay(saveNotificationOverlay)
        .sheet(isPresented: $showingProjectDetails) {
            ProjectDetailsView(project: project)
                .environmentObject(dataController)
                .environmentObject(appState)
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
        .onDisappear {
            AnalyticsService.shared.endScreenView(screenName: "task_details")
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
            Text("This will permanently delete this task. This action cannot be undone.")
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

                // Map view — same Mapbox dark style + segmented-ring pin as main map
                MiniMapView(
                    coordinate: project.coordinate,
                    address: project.address ?? "",
                    onTap: { openInMaps() },
                    projectName: project.title,
                    status: project.status,
                    taskColorHexes: project.tasks
                        .filter { $0.deletedAt == nil && $0.status == .active }
                        .map { $0.effectiveColor },
                    onResolvedCoordinate: { coord in
                        // Bug bec71df9 — persist the resolved coord so the
                        // project's map pin renders immediately on the next
                        // load and the server row gets hydrated.
                        project.latitude = coord.latitude
                        project.longitude = coord.longitude
                        project.needsSync = true
                        try? modelContext.save()

                        dataController.syncEngine.recordOperation(
                            entityType: .project,
                            entityId: project.id,
                            operationType: "update",
                            changedFields: [
                                "latitude": coord.latitude,
                                "longitude": coord.longitude
                            ]
                        )
                    }
                )
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

            }
        }
        .padding(.horizontal)
    }

    private var materialHistorySection: some View {
        SectionCard(
            icon: OPSStyle.Icons.productTag,
            title: "Material History"
        ) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                switch materialHistoryLoadState {
                case .idle, .loading:
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryAccent)
                        Text("SYS :: LOADING")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                case .failed:
                    Text("SYS :: MATERIAL HISTORY FAILED")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                case .loaded:
                    if materialHistory.isEmpty {
                        Text("—")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    } else {
                        materialHistorySummary
                        materialHistoryLines
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var materialHistorySummary: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            materialMetric(
                label: "BOOKED",
                value: materialQuantityText(materialHistory.totalBookedQuantity),
                color: OPSStyle.Colors.primaryText
            )
            materialMetric(
                label: "CONSUMED",
                value: materialQuantityText(materialHistory.totalConsumedQuantity),
                color: OPSStyle.Colors.successStatus
            )
            materialMetric(
                label: materialHistory.hasOverrun ? "OVER" : "SHORT",
                value: materialQuantityText(materialHistory.totalOverrunQuantity),
                color: materialHistory.hasOverrun ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.tertiaryText
            )
        }
    }

    private var materialHistoryLines: some View {
        // Render EVERY evidence line. The card lives inside the screen's
        // ScrollView, so a long allocation history scrolls naturally — never
        // silently drop rows past the fourth, which would hide real stock the
        // crew consumed.
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(materialHistory.lines) { line in
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                        Text(materialLineTitle(line))
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        Spacer()

                        Text(materialLineUsageText(line))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(line.overrunQuantity > 0 ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.secondaryText)
                    }

                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text("BOOKED \(materialQuantityText(line.bookedQuantity))")
                        if line.overrunQuantity > 0 {
                            Text("OVER \(materialQuantityText(line.overrunQuantity))")
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                        }
                        Text("STOCK \(line.stockLabel)")
                    }
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)

                    if line.stockLocation != nil || line.stockStatus != nil || line.stockQuantity != nil {
                        Text(materialStockEvidence(line))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
        }
    }

    private func materialMetric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .opacity(project.effectiveClientPhone != nil ? 1.0 : 0.2)

                        Image(systemName: OPSStyle.Icons.envelopeFill)
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .opacity(project.effectiveClientEmail != nil ? 1.0 : 0.2)
                    }

                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
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
                // Scheduling is gated on calendar.edit (scope-aware), not tasks.edit:
                // a Crew member may edit task fields but never move it on the calendar.
                if task.canEditSchedule {
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

                            if let start = task.startDate, let end = task.endDate {
                                Text(formatDateRange(start, end))
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            } else if let date = task.scheduledDate {
                                Text(formatDate(date))
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            } else {
                                Text("Tap to Schedule")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        }

                        Spacer()

                        // Chevron indicator for users who can reschedule (calendar.edit)
                        if task.canEditSchedule {
                            Image(systemName: OPSStyle.Icons.chevronRight)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
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
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .id(refreshTrigger)
            .allowsHitTesting(task.canEditSchedule)
        }
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
                // Sync team members from Supabase, then query locally
                await dataController.triggerTeamMembersSync(companyId: companyId)

                await MainActor.run {
                    // Query local SwiftData for all users in the company
                    let descriptor = FetchDescriptor<User>(
                        predicate: #Predicate<User> { user in
                            user.companyId == companyId && user.isActive == true
                        }
                    )
                    if let users = try? dataController.modelContext?.fetch(descriptor) {
                        self.allTeamMembers = users
                    }
                }
            } catch {
                print("[TASK_TEAM] Error loading available members: \(error)")
            }
        }
    }

    private func loadMaterialHistory() {
        let companyId = dataController.currentUser?.companyId ?? task.companyId
        guard !companyId.isEmpty else {
            materialHistory = .empty
            materialHistoryLoadState = .loaded
            return
        }

        let taskId = task.id
        let projectId = task.projectId.isEmpty ? project.id : task.projectId
        materialHistoryLoadState = .loading

        Task {
            // Resolve the company operating mode first. Off-mode companies hide
            // the card entirely, so there's no reason to fetch the heavier
            // demand/allocation/snapshot history for them.
            let mode = await resolveInventoryMode(companyId: companyId)
            await MainActor.run {
                guard self.task.id == taskId else { return }
                self.companyInventoryMode = mode
            }

            guard mode.isTracked else {
                await MainActor.run {
                    guard self.task.id == taskId else { return }
                    self.materialHistory = .empty
                    self.materialHistoryLoadState = .loaded
                }
                return
            }

            do {
                let repository = TaskMaterialHistoryRepository(companyId: companyId)
                let history = try await repository.fetchTaskHistory(projectId: projectId, taskId: taskId)
                await MainActor.run {
                    guard self.task.id == taskId else { return }
                    self.materialHistory = history
                    self.materialHistoryLoadState = .loaded
                }
            } catch {
                print("[TASK_MATERIAL_HISTORY] Failed to load task material history: \(error)")
                await MainActor.run {
                    guard self.task.id == taskId else { return }
                    self.materialHistory = .empty
                    self.materialHistoryLoadState = .failed
                }
            }
        }
    }

    /// Reads the company inventory mode. On failure, falls back to `.off` so a
    /// transient read error never flashes an empty Material History card.
    private func resolveInventoryMode(companyId: String) async -> InventoryMode {
        do {
            return try await CompanyInventoryModeRepository(companyId: companyId).fetchInventoryMode()
        } catch {
            print("[TASK_MATERIAL_HISTORY] Failed to resolve company inventory mode: \(error)")
            return .off
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
        // - API sync for task
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
                        icon: OPSStyle.Icons.chevronLeft,
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
                        icon: OPSStyle.Icons.chevronRight,
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
                        .strokeBorder(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: OPSStyle.Layout.Border.standard)
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
            withAnimation(OPSStyle.Animation.standard) {
                self.task = newTask
                loadTaskTeamMembers()
                loadMaterialHistory()
            }
        }) {
            HStack(spacing: 8) {
                if iconPosition == .leading {
                    Image(systemName: icon)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
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
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
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
                    .strokeBorder(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private func emptyNavigationPill(caption: String, iconPosition: IconPosition) -> some View {
        HStack(spacing: 8) {
            if iconPosition == .leading {
                Image(systemName: OPSStyle.Icons.chevronLeft)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
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
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
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
                .strokeBorder(OPSStyle.Colors.inputFieldBorder.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Delete Task Section

    private var deleteTaskSection: some View {
        Button(action: {
            showingDeleteConfirmation = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: OPSStyle.Icons.delete)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
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
                    .strokeBorder(OPSStyle.Colors.errorStatus.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
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
                    dataController.scheduledTasksDidChange.toggle()
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
        guard task.canEditSchedule else { return }
        print("🔄 Task handleScheduleUpdate called - New dates: \(startDate) to \(endDate)")

        // Set dates directly on the task
        task.startDate = startDate
        task.endDate = endDate
        let daysDiff = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        task.duration = daysDiff + 1
        task.needsSync = true

        // Update parent project dates if necessary
        if let project = task.project {
            let allTasks = project.tasks
            let earliestStart = allTasks.compactMap { $0.startDate }.min() ?? startDate
            let latestEnd = allTasks.compactMap { $0.endDate }.max() ?? endDate

            if project.startDate != earliestStart || project.endDate != latestEnd {
                print("🔄 Updating project dates to match task range")
                project.startDate = earliestStart
                project.endDate = latestEnd
                project.needsSync = true
            }
        }

        // Save to database
        do {
            try modelContext.save()
            print("✅ Successfully saved task schedule update")

            // Force view refresh to show updated dates
            refreshTrigger.toggle()

            // Notify calendar views to refresh
            dataController.scheduledTasksDidChange.toggle()

            // Sync task dates to server
            Task {
                await syncTaskDatesToServer()
            }
        } catch {
            print("❌ Failed to save task schedule update: \(error)")
        }
    }

    private func handleClearDates() {
        guard task.canEditSchedule else { return }
        print("🗑️ handleClearDates called - Clearing task dates")

        let projectId = task.project?.id

        // Clear dates directly on task
        task.startDate = nil
        task.endDate = nil
        task.duration = 0
        task.needsSync = true

        // Capture scheduled task data for recalculation
        let scheduledTaskDates: [(start: Date, end: Date)]? = task.project?.tasks.compactMap { projectTask in
            guard projectTask.id != task.id,
                  let start = projectTask.startDate,
                  let end = projectTask.endDate else {
                return nil
            }
            return (start, end)
        }

        // Save to database
        do {
            try modelContext.save()
            print("✅ Successfully cleared task dates")

            // Force view refresh to show cleared dates
            refreshTrigger.toggle()

            // Notify calendar views to refresh
            dataController.scheduledTasksDidChange.toggle()

            // Sync to Supabase
            Task {
                do {
                    // STEP 1: Clear task dates in Supabase
                    print("📡 Clearing task dates in Supabase...")
                    try await dataController.updateTaskFields(
                        taskId: task.id,
                        fields: [
                            "start_date": .null,
                            "end_date": .null,
                            "duration": .integer(0)
                        ]
                    )
                    print("✅ Task dates cleared")

                    // STEP 2: Recalculate parent project dates
                    if let project = task.project {
                        print("🔄 Recalculating parent project dates...")

                        if let dates = scheduledTaskDates, !dates.isEmpty {
                            let earliestStart = dates.map { $0.start }.min()
                            let latestEnd = dates.map { $0.end }.max()

                            if let start = earliestStart, let end = latestEnd {
                                try await dataController.updateProjectDates(
                                    project: project,
                                    startDate: start,
                                    endDate: end
                                )
                                print("✅ Project dates updated")
                            }
                        } else {
                            print("🗑️ No scheduled tasks - clearing project dates")
                            try await dataController.updateProjectDates(
                                project: project,
                                startDate: nil,
                                endDate: nil
                            )
                            print("✅ Project dates cleared")
                        }
                    }
                } catch {
                    print("❌ Failed to clear dates in Supabase: \(error)")
                }
            }
        } catch {
            print("❌ Failed to save cleared task dates: \(error)")
        }
    }

    private func syncTaskDatesToServer() async {
        print("🔄 Syncing task dates to server: \(task.id)")

        do {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]

            let startDateString = task.startDate.map { formatter.string(from: $0) } ?? ""
            let endDateString = task.endDate.map { formatter.string(from: $0) } ?? ""

            try await dataController.updateTaskFields(
                taskId: task.id,
                fields: [
                    "start_date": .string(startDateString),
                    "end_date": .string(endDateString),
                    "duration": .integer(task.duration)
                ]
            )

            await MainActor.run {
                task.needsSync = false
                try? modelContext.save()
            }

            print("✅ Task dates synced successfully to server")
        } catch {
            print("⚠️ Failed to sync task dates to server: \(error)")
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
        
        // Log scheduling info
        if let startDate = task.startDate {
            print("📅 DATA: Task start date: \(startDate)")
            print("📅 DATA: Task end date: \(task.endDate?.description ?? "nil")")
            print("📅 DATA: Task duration: \(task.duration)")
        } else {
            print("📅 DATA: Task has no scheduled dates")
        }
        
        print("=====================================================")
    }
    
    // MARK: - Helper Methods
    
    private var availableStatuses: [TaskStatus] {
        // Only office crew and admins can cancel tasks
        guard let currentUser = dataController.currentUser else {
            return [.active, .completed]
        }

        if permissionStore.can("tasks.change_status") {
            return TaskStatus.allCases
        } else {
            return [.active, .completed]
        }
    }
    
    private func updateTaskStatus(to newStatus: TaskStatus) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Handle project status updates before task status update
        if newStatus == .active {
            if project.status == .completed {
                project.status = .inProgress
                project.needsSync = true
                Task {
                    try? await dataController.updateProjectStatus(
                        project: project,
                        to: .inProgress
                    )
                }
            }
        }

        // Use centralized status update function - handles local update and server sync
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
        case .active:
            return OPSStyle.Icons.calendar
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
        permissionStore.can("tasks.edit")
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

    private func materialQuantityText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 1
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func materialLineTitle(_ line: TaskMaterialHistory.Line) -> String {
        if let variantId = line.catalogVariantId, !variantId.isEmpty {
            return "VARIANT \(shortMaterialId(variantId))"
        }
        return shortMaterialDemandKey(line.demandKey)
    }

    private func materialLineUsageText(_ line: TaskMaterialHistory.Line) -> String {
        if line.consumedQuantity > 0 {
            return "USED \(materialQuantityText(line.consumedQuantity))"
        }
        if line.overrunQuantity > 0 {
            return "OVER \(materialQuantityText(line.overrunQuantity))"
        }
        if let stockQuantity = line.stockQuantity {
            return "QTY \(materialQuantityText(stockQuantity))"
        }
        return "USED 0"
    }

    private func materialStockEvidence(_ line: TaskMaterialHistory.Line) -> String {
        [
            line.stockLocation.map { "LOC \($0.uppercased())" },
            line.stockStatus.map { "STATUS \($0.uppercased())" },
            materialStockQuantityEvidence(line)
        ]
        .compactMap { $0 }
        .joined(separator: "  ")
    }

    private func materialStockQuantityEvidence(_ line: TaskMaterialHistory.Line) -> String? {
        guard let stockQuantity = line.stockQuantity else { return nil }
        let unit = line.stockQuantityUnit.map { " \($0.uppercased())" } ?? ""
        return "QTY \(materialQuantityText(stockQuantity))\(unit)"
    }

    private func shortMaterialDemandKey(_ demandKey: String) -> String {
        demandKey
            .split(separator: ":")
            .suffix(2)
            .joined(separator: " ")
            .uppercased()
    }

    private func shortMaterialId(_ value: String) -> String {
        String(value.prefix(8)).uppercased()
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
        project.completedAt = Date()
        project.needsSync = true
        
        // Save to model context
        if let modelContext = dataController.modelContext {
            try? modelContext.save()
        }
        
        // Sync to API
        Task {
            try? await dataController.updateProjectStatus(
                project: project,
                to: .completed
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
        withAnimation(OPSStyle.Animation.standard) {
            showingSaveNotification = true
        }
        
        notificationTimer?.invalidate()
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            withAnimation(OPSStyle.Animation.standard) {
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
                        .foregroundColor(OPSStyle.Colors.primaryText)
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
                .foregroundColor(isSelected ? OPSStyle.Colors.invertedText : status.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(isSelected ? status.color : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .strokeBorder(status.color, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
