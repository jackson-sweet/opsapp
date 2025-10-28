//
//  UniversalJobBoardCard.swift
//  OPS
//
//  Created by Assistant on 2025-09-29.
//

import SwiftUI
import SwiftData

enum JobBoardCardType {
    case project(Project)
    case client(Client)
    case task(ProjectTask)
}

struct UniversalJobBoardCard: View {
    let cardType: JobBoardCardType
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @State private var showingMoreActions = false
    @State private var showingDetails = false
    @State private var showingTaskForm = false
    @State private var showingProjectForm = false
    @State private var showingScheduler = false
    @State private var showingStatusPicker = false
    @State private var showingTeamPicker = false
    @State private var isLongPressing = false
    @State private var hasTriggeredLongPressHaptic = false
    @State private var showingProjectDetails = false
    @State private var swipeOffset: CGFloat = 0
    @State private var isChangingStatus = false
    @State private var hasTriggeredHaptic = false
    @State private var confirmingStatus: Any? = nil
    @State private var confirmingDirection: SwipeDirection? = nil
    @State private var showingDeleteConfirmation = false
    @State private var showingClientDeletionSheet = false
    @State private var customAlert: CustomAlertConfig?

    private var isFieldCrew: Bool {
        dataController.currentUser?.role == .fieldCrew
    }

    private var canModify: Bool {
        guard let user = dataController.currentUser else { return false }
        return user.role == .admin || user.role == .officeCrew
    }

    var body: some View {
        if case .client = cardType {
            clientCard
        } else if case .project = cardType {
            projectCard
                .padding(.vertical, 8)
        } else {
            taskCard
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var clientCard: some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            if case .client(let client) = cardType {
                ClientProjectBadges(client: client)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .scaleEffect(isLongPressing ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isLongPressing)
        .onTapGesture {
            showingDetails = true
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            showingMoreActions = true
        } onPressingChanged: { pressing in
            if pressing {
                isLongPressing = true
                hasTriggeredLongPressHaptic = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isLongPressing && !hasTriggeredLongPressHaptic {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        hasTriggeredLongPressHaptic = true
                    }
                }
            } else {
                isLongPressing = false
                hasTriggeredLongPressHaptic = false
            }
        }
        .confirmationDialog("Actions", isPresented: $showingMoreActions, titleVisibility: .hidden) {
            moreActionsContent
        }
        .sheet(isPresented: $showingDetails) {
            detailsSheet
        }
        .sheet(isPresented: $showingProjectForm) {
            if case .client(let client) = cardType {
                ProjectFormSheet(mode: .create, preselectedClient: client) { _ in }
                    .environmentObject(dataController)
            } else {
                ProjectFormSheet(mode: .create) { _ in }
                    .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingClientDeletionSheet) {
            if case .client(let client) = cardType {
                ClientDeletionSheet(client: client)
            }
        }
    }

    @ViewBuilder
    private var projectCard: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if swipeOffset > 0, let targetStatus = getTargetStatus(direction: .right) {
                    RevealedStatusCard(status: targetStatus, direction: .right)
                        .opacity(min(abs(swipeOffset) / (geometry.size.width * 0.4), 1.0))
                } else if swipeOffset < 0, let targetStatus = getTargetStatus(direction: .left) {
                    RevealedStatusCard(status: targetStatus, direction: .left)
                        .opacity(min(abs(swipeOffset) / (geometry.size.width * 0.4), 1.0))
                }

                projectCardContent
                    .offset(x: swipeOffset)
                    .opacity(isChangingStatus ? 0 : 1)
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                handleSwipeChanged(value: value, cardWidth: geometry.size.width)
                            }
                            .onEnded { value in
                                handleSwipeEnded(value: value, cardWidth: geometry.size.width)
                            }
                    )

                if isChangingStatus, let confirmingStatus = confirmingStatus, let direction = confirmingDirection {
                    RevealedStatusCard(status: confirmingStatus, direction: direction)
                        .opacity(isChangingStatus ? 1 : 0)
                }
            }
        }
        .frame(height: 80)
    }

    @ViewBuilder
    private var projectCardContent: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        titleText
                        subtitleText
                    }

                    Spacer()
                }

                metadataRow
            }
            .padding(14)
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .overlay(
            Group {
                if case .project(let project) = cardType {
                    ZStack {
                        Text(project.status.displayName.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(project.status.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(project.status.color.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(project.status.color, lineWidth: 1)
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(8)

                        if shouldShowUnscheduledBadge(for: project) {
                            Text("UNSCHEDULED")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(OPSStyle.Colors.warningStatus.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(OPSStyle.Colors.warningStatus, lineWidth: 1)
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(8)
                        }
                    }
                }
            }
        )
        .contentShape(Rectangle())
        .scaleEffect(isLongPressing ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isLongPressing)
        .onTapGesture {
            showingDetails = true
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            showingMoreActions = true
        } onPressingChanged: { pressing in
            if pressing {
                isLongPressing = true
                hasTriggeredLongPressHaptic = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isLongPressing && !hasTriggeredLongPressHaptic {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        hasTriggeredLongPressHaptic = true
                    }
                }
            } else {
                isLongPressing = false
                hasTriggeredLongPressHaptic = false
            }
        }
        .confirmationDialog("Actions", isPresented: $showingMoreActions, titleVisibility: .hidden) {
            moreActionsContent
        }
        .sheet(isPresented: $showingDetails) {
            detailsSheet
        }
        .sheet(isPresented: $showingTaskForm) {
            if case .project(let project) = cardType {
                TaskFormSheet(mode: .create, preselectedProjectId: project.id) { _ in }
            } else {
                TaskFormSheet(mode: .create) { _ in }
            }
        }
        .sheet(isPresented: $showingProjectForm) {
            if case .client(let client) = cardType {
                ProjectFormSheet(mode: .create, preselectedClient: client) { _ in }
                    .environmentObject(dataController)
            } else {
                ProjectFormSheet(mode: .create) { _ in }
                    .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingScheduler) {
            schedulerSheet
        }
        .sheet(isPresented: $showingStatusPicker) {
            if case .project(let project) = cardType {
                ProjectStatusChangeSheet(project: project)
                    .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingTeamPicker) {
            if case .project(let project) = cardType {
                ProjectTeamChangeSheet(project: project)
                    .environmentObject(dataController)
            }
        }
        .alert("Delete \(deleteItemName)?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("This will permanently delete this \(deleteItemName.lowercased()). This action cannot be undone.")
        }
        .customAlert($customAlert)
    }

    private var deleteItemName: String {
        switch cardType {
        case .project:
            return "Project"
        case .client:
            return "Client"
        case .task:
            return "Task"
        }
    }

    @ViewBuilder
    private var taskCard: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if swipeOffset > 0, let targetStatus = getTargetStatus(direction: .right) {
                    RevealedStatusCard(status: targetStatus, direction: .right)
                        .opacity(min(abs(swipeOffset) / (geometry.size.width * 0.4), 1.0))
                } else if swipeOffset < 0, let targetStatus = getTargetStatus(direction: .left) {
                    RevealedStatusCard(status: targetStatus, direction: .left)
                        .opacity(min(abs(swipeOffset) / (geometry.size.width * 0.4), 1.0))
                }

                taskCardContent
                    .offset(x: swipeOffset)
                    .opacity(isChangingStatus ? 0 : 1)
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                handleSwipeChanged(value: value, cardWidth: geometry.size.width)
                            }
                            .onEnded { value in
                                handleSwipeEnded(value: value, cardWidth: geometry.size.width)
                            }
                    )

                if isChangingStatus, let confirmingStatus = confirmingStatus, let direction = confirmingDirection {
                    RevealedStatusCard(status: confirmingStatus, direction: direction)
                        .opacity(isChangingStatus ? 1 : 0)
                }
            }
        }
        .frame(height: 80)
    }

    @ViewBuilder
    private var taskCardContent: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(taskTypeColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        titleText
                        subtitleText
                    }

                    Spacer()
                }

                metadataRow
            }
            .padding(14)
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .overlay(
            Group {
                if case .task(let task) = cardType {
                    ZStack {
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
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(8)

                        if task.calendarEvent?.startDate == nil {
                            Text("UNSCHEDULED")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(OPSStyle.Colors.warningStatus.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(OPSStyle.Colors.warningStatus, lineWidth: 1)
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(8)
                        }
                    }
                }
            }
        )
        .contentShape(Rectangle())
        .scaleEffect(isLongPressing ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isLongPressing)
        .onTapGesture {
            showingDetails = true
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            showingMoreActions = true
        } onPressingChanged: { pressing in
            if pressing {
                isLongPressing = true
                hasTriggeredLongPressHaptic = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if isLongPressing && !hasTriggeredLongPressHaptic {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        hasTriggeredLongPressHaptic = true
                    }
                }
            } else {
                isLongPressing = false
                hasTriggeredLongPressHaptic = false
            }
        }
        .confirmationDialog("Actions", isPresented: $showingMoreActions, titleVisibility: .hidden) {
            moreActionsContent
        }
        .sheet(isPresented: $showingDetails) {
            detailsSheet
        }
        .sheet(isPresented: $showingTaskForm) {
            if case .task(let task) = cardType {
                if let project = dataController.getAllProjects().first(where: { $0.id == task.projectId }) {
                    TaskFormSheet(mode: .create, preselectedProjectId: project.id) { _ in }
                } else {
                    TaskFormSheet(mode: .create) { _ in }
                }
            } else {
                TaskFormSheet(mode: .create) { _ in }
            }
        }
        .sheet(isPresented: $showingProjectForm) {
            if case .client(let client) = cardType {
                ProjectFormSheet(mode: .create, preselectedClient: client) { _ in }
                    .environmentObject(dataController)
            } else {
                ProjectFormSheet(mode: .create) { _ in }
                    .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingScheduler) {
            schedulerSheet
        }
        .sheet(isPresented: $showingStatusPicker) {
            if case .task(let task) = cardType {
                TaskStatusChangeSheet(task: task)
                    .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingTeamPicker) {
            if case .task(let task) = cardType {
                TaskTeamChangeSheet(task: task)
                    .environmentObject(dataController)
            }
        }
        .sheet(isPresented: $showingProjectDetails) {
            if case .task(let task) = cardType {
                if let project = dataController.getAllProjects().first(where: { $0.id == task.projectId }) {
                    NavigationView {
                        ProjectDetailsView(project: project)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var titleText: some View {
        Text(title)
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .lineLimit(1)
    }

    @ViewBuilder
    private var subtitleText: some View {
        Text(subtitle)
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .lineLimit(1)
    }


    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 12) {
            ForEach(metadataItems, id: \.icon) { item in
                HStack(spacing: 4) {
                    Image(systemName: item.icon)
                        .font(.system(size: 11))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Text(item.text)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var moreActionsContent: some View {
        switch cardType {
        case .project:
            projectActions
        case .client:
            clientActions
        case .task:
            taskActions
        }
    }

    @ViewBuilder
    private var projectActions: some View {
        Group {
            Button("View Project") {
                showingDetails = true
            }

            if canModify {
                Button("Add Task") {
                    showingTaskForm = true
                }

                Button("Reschedule") {
                    showingScheduler = true
                }
            }

            Button("Change Status") {
                showingStatusPicker = true
            }

            if canModify {
                Button("Change Team") {
                    showingTeamPicker = true
                }

                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }

            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var clientActions: some View {
        Group {
            Button("View Client") {
                showingDetails = true
            }

            if canModify {
                Button("Add Project") {
                    showingProjectForm = true
                }

                Button("Delete", role: .destructive) {
                    showingClientDeletionSheet = true
                }
            }

            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var taskActions: some View {
        Group {
            Button("View Task") {
                showingDetails = true
            }

            Button("View Project") {
                showingProjectDetails = true
            }

            if canModify {
                Button("Reschedule") {
                    showingScheduler = true
                }
            }

            Button("Change Status") {
                showingStatusPicker = true
            }

            if canModify {
                Button("Change Team") {
                    showingTeamPicker = true
                }

                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }

            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var detailsSheet: some View {
        switch cardType {
        case .project(let project):
            NavigationView {
                ProjectDetailsView(project: project)
            }
        case .client(let client):
            ContactDetailView(client: client, project: nil)
                .environmentObject(dataController)
        case .task(let task):
            if let project = dataController.getAllProjects().first(where: { $0.id == task.projectId }) {
                NavigationView {
                    TaskDetailsView(task: task, project: project)
                        .environmentObject(dataController)
                }
            }
        }
    }

    @ViewBuilder
    private var schedulerSheet: some View {
        switch cardType {
        case .project(let project):
            CalendarSchedulerSheet(
                isPresented: $showingScheduler,
                itemType: .project(project),
                currentStartDate: project.startDate,
                currentEndDate: project.endDate,
                onScheduleUpdate: { startDate, endDate in
                    // Update or create calendar event
                    if let projectEvent = project.primaryCalendarEvent {
                        // Update existing calendar event and project dates using centralized functions
                        Task {
                            do {
                                try await dataController.updateProjectDates(project: project, startDate: startDate, endDate: endDate)
                                try await dataController.updateCalendarEvent(event: projectEvent, startDate: startDate, endDate: endDate)
                            } catch {
                                print("❌ Failed to sync project schedule to Bubble: \(error)")
                            }
                        }
                    } else {
                        // Create new calendar event
                        try? dataController.modelContext?.save()

                        Task {
                            do {
                                print("[JOB_BOARD_SCHEDULE] Creating calendar event for project")

                                let dateFormatter = ISO8601DateFormatter()
                                dateFormatter.formatOptions = [.withInternetDateTime]

                                let duration = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1

                                // Get company's default project color
                                let company = dataController.getCompany(id: project.companyId)
                                let projectColor = company?.defaultProjectColor ?? "#9CA3AF"  // Light grey fallback
                                print("[JOB_BOARD_SCHEDULE] Using project color: \(projectColor)")

                                let eventDTO = CalendarEventDTO(
                                    id: UUID().uuidString,
                                    color: projectColor,
                                    companyId: project.companyId,
                                    projectId: project.id,
                                    taskId: nil,
                                    duration: Double(duration),
                                    endDate: dateFormatter.string(from: endDate),
                                    startDate: dateFormatter.string(from: startDate),
                                    teamMembers: project.teamMembers.map { $0.id },
                                    title: project.effectiveClientName.capitalizedWords(),
                                    type: "Project",
                                    active: true,
                                    createdDate: nil,
                                    modifiedDate: nil
                                )

                                // Create event and link to project
                                let createdEvent = try await dataController.apiService.createAndLinkCalendarEvent(eventDTO)
                                print("[JOB_BOARD_SCHEDULE] ✅ Calendar event created with ID: \(createdEvent.id)")

                                await MainActor.run {
                                    if let calendarEvent = createdEvent.toModel() {
                                        calendarEvent.needsSync = false
                                        calendarEvent.lastSyncedAt = Date()
                                        dataController.modelContext?.insert(calendarEvent)

                                        project.primaryCalendarEvent = calendarEvent

                                        try? dataController.modelContext?.save()
                                        print("[JOB_BOARD_SCHEDULE] ✅ Calendar event linked to project")
                                    }
                                }

                                // Update project dates in Bubble
                                try await dataController.apiService.updateProjectDates(
                                    projectId: project.id,
                                    startDate: startDate,
                                    endDate: endDate
                                )
                            } catch {
                                print("❌ Failed to create calendar event: \(error)")
                            }
                        }
                    }
                },
                onClearDates: {
                    // Clear project and calendar event dates
                    Task {
                        do {
                            print("🗑️ [JOB_BOARD] Clearing project dates")

                            // Clear project dates using centralized function
                            try await dataController.updateProjectDates(project: project, startDate: nil, endDate: nil, clearDates: true)

                            // Clear calendar event dates if exists
                            if let projectEvent = project.primaryCalendarEvent {
                                try await dataController.performSyncedOperation(
                                    item: projectEvent,
                                    operationName: "CLEAR_CALENDAR_EVENT_DATES",
                                    itemDescription: "Clearing calendar event \(projectEvent.id) dates",
                                    localUpdate: {
                                        projectEvent.startDate = nil
                                        projectEvent.endDate = nil
                                        projectEvent.duration = 0
                                        projectEvent.needsSync = true
                                    },
                                    syncToAPI: {
                                        let updates: [String: Any] = [
                                            BubbleFields.CalendarEvent.startDate: NSNull(),
                                            BubbleFields.CalendarEvent.endDate: NSNull(),
                                            BubbleFields.CalendarEvent.duration: 0
                                        ]
                                        try await dataController.apiService.updateCalendarEvent(id: projectEvent.id, updates: updates)
                                        projectEvent.needsSync = false
                                        projectEvent.lastSyncedAt = Date()
                                    }
                                )
                            }

                            print("✅ [JOB_BOARD] Project dates cleared and synced")
                        } catch {
                            print("❌ [JOB_BOARD] Failed to clear project dates: \(error)")
                        }
                    }
                }
            )
            .environmentObject(dataController)
        case .task(let task):
            CalendarSchedulerSheet(
                isPresented: $showingScheduler,
                itemType: .task(task),
                currentStartDate: task.calendarEvent?.startDate,
                currentEndDate: task.calendarEvent?.endDate,
                onScheduleUpdate: { startDate, endDate in
                    Task {
                        do {
                            // Update or create calendar event
                            if let calendarEvent = task.calendarEvent {
                                try await dataController.updateCalendarEvent(event: calendarEvent, startDate: startDate, endDate: endDate)
                            } else {
                                // Create new calendar event for the task
                                let newEvent = CalendarEvent.fromTask(task, startDate: startDate, endDate: endDate)
                                task.calendarEvent = newEvent
                                dataController.modelContext?.insert(newEvent)
                                try? dataController.modelContext?.save()
                            }

                            // Update parent project dates if necessary
                            if let project = task.project {
                                let allTaskEvents = project.tasks.compactMap { $0.calendarEvent }
                                if !allTaskEvents.isEmpty {
                                    let earliestStart = allTaskEvents.compactMap { $0.startDate }.min() ?? startDate
                                    let latestEnd = allTaskEvents.compactMap { $0.endDate }.max() ?? endDate

                                    if project.startDate != earliestStart || project.endDate != latestEnd {
                                        try await dataController.updateProjectDates(project: project, startDate: earliestStart, endDate: latestEnd)
                                    }
                                }
                            }
                        } catch {
                            print("❌ Failed to sync task schedule to Bubble: \(error)")
                        }
                    }
                },
                onClearDates: {
                    // Clear task calendar event dates
                    Task {
                        do {
                            print("🗑️ [JOB_BOARD] Clearing task calendar event dates")

                            if let calendarEvent = task.calendarEvent {
                                try await dataController.performSyncedOperation(
                                    item: calendarEvent,
                                    operationName: "CLEAR_TASK_CALENDAR_EVENT",
                                    itemDescription: "Clearing task calendar event \(calendarEvent.id) dates",
                                    localUpdate: {
                                        calendarEvent.startDate = nil
                                        calendarEvent.endDate = nil
                                        calendarEvent.duration = 0
                                        calendarEvent.needsSync = true
                                    },
                                    syncToAPI: {
                                        let updates: [String: Any] = [
                                            BubbleFields.CalendarEvent.startDate: NSNull(),
                                            BubbleFields.CalendarEvent.endDate: NSNull(),
                                            BubbleFields.CalendarEvent.duration: 0
                                        ]
                                        try await dataController.apiService.updateCalendarEvent(id: calendarEvent.id, updates: updates)
                                        calendarEvent.needsSync = false
                                        calendarEvent.lastSyncedAt = Date()
                                    }
                                )

                                // Update parent project dates if necessary
                                if let project = task.project {
                                    let allTaskEvents = project.tasks.compactMap { $0.calendarEvent }
                                    let taskEventsWithDates = allTaskEvents.filter { $0.startDate != nil && $0.endDate != nil }

                                    if taskEventsWithDates.isEmpty {
                                        // No tasks have dates, clear project dates
                                        try await dataController.updateProjectDates(project: project, startDate: nil, endDate: nil, clearDates: true)
                                    } else {
                                        // Recalculate project dates from remaining task dates
                                        let earliestStart = taskEventsWithDates.compactMap { $0.startDate }.min()
                                        let latestEnd = taskEventsWithDates.compactMap { $0.endDate }.max()

                                        if let start = earliestStart, let end = latestEnd {
                                            try await dataController.updateProjectDates(project: project, startDate: start, endDate: end)
                                        }
                                    }
                                }
                            }

                            print("✅ [JOB_BOARD] Task calendar event dates cleared")
                        } catch {
                            print("❌ [JOB_BOARD] Failed to clear task dates: \(error)")
                        }
                    }
                }
            )
            .environmentObject(dataController)
        default:
            EmptyView()
        }
    }

    // MARK: - Computed Properties

    private var title: String {
        switch cardType {
        case .project(let project):
            return project.title.uppercased()
        case .client(let client):
            return client.name.uppercased()
        case .task(let task):
            if let taskType = dataController.getAllTaskTypes(for: task.companyId).first(where: { $0.id == task.taskTypeId }) {
                return taskType.display.uppercased()
            }
            return "TASK"
        }
    }

    private var subtitle: String {
        switch cardType {
        case .project(let project):
            return project.effectiveClientName
        case .client(let client):
            let projectCount = client.projects.count
            return "\(projectCount) \(projectCount == 1 ? "project" : "projects")"
        case .task(let task):
            if let project = dataController.getAllProjects().first(where: { $0.id == task.projectId }) {
                let clientName = project.effectiveClientName
                return "\(project.title) - \(clientName)"
            }
            return "No project"
        }
    }

    private var iconName: String {
        switch cardType {
        case .project:
            return OPSStyle.Icons.folderFill
        case .client:
            return OPSStyle.Icons.personTwoFill
        case .task(let task):
            if let taskType = dataController.getAllTaskTypes(for: task.companyId).first(where: { $0.id == task.taskTypeId }) {
                return taskType.icon ?? OPSStyle.Icons.checkmarkSquareFill
            }
            return OPSStyle.Icons.checkmarkSquareFill
        }
    }

    private var statusColor: Color {
        switch cardType {
        case .project(let project):
            return project.status.color
        case .client:
            return OPSStyle.Colors.primaryAccent
        case .task(let task):
            switch task.status {
            case .scheduled:
                return OPSStyle.Colors.primaryAccent
            case .inProgress:
                return Color.blue
            case .completed:
                return Color.green
            case .cancelled:
                return Color.gray
            }
        }
    }

    private var taskTypeColor: Color {
        if case .task(let task) = cardType {
            if let taskType = dataController.getAllTaskTypes(for: task.companyId).first(where: { $0.id == task.taskTypeId }) {
                if let color = Color(hex: taskType.color) {
                    return color
                }
            }
        }
        return OPSStyle.Colors.tertiaryText
    }

    private var statusText: String {
        switch cardType {
        case .project(let project):
            return project.status.displayName
        case .client(let client):
            return client.email != nil ? "Contact" : "No Contact"
        case .task(let task):
            return task.status.displayName
        }
    }

    private var metadataItems: [(icon: String, text: String)] {
        switch cardType {
        case .project(let project):
            var items: [(icon: String, text: String)] = []

            if let address = project.address, !address.isEmpty {
                items.append((OPSStyle.Icons.location, address.formatAsSimpleAddress()))
            } else {
                items.append((OPSStyle.Icons.location, "NO ADDRESS"))
            }

            if let startDate = project.startDate {
                items.append((OPSStyle.Icons.calendar, DateHelper.fullDateString(from: startDate)))
            }

            if !project.teamMembers.isEmpty {
                items.append((OPSStyle.Icons.personTwo, "\(project.teamMembers.count)"))
            }

            if project.eventType == .task {
                let taskText = project.tasks.count == 1 ? "TASK" : "TASKS"
                items.append((OPSStyle.Icons.checklist, "\(project.tasks.count) \(taskText)"))
            } else {
                items.append((OPSStyle.Icons.folderFill, "PROJECT"))
            }

            return items

        case .client(let client):
            var items: [(icon: String, text: String)] = []

            if client.phoneNumber != nil {
                items.append((OPSStyle.Icons.phone, "Phone"))
            }

            if client.email != nil {
                items.append((OPSStyle.Icons.envelope, "Email"))
            }

            return items

        case .task(let task):
            var items: [(icon: String, text: String)] = []

            if let project = dataController.getAllProjects().first(where: { $0.id == task.projectId }) {
                if let address = project.address, !address.isEmpty {
                    items.append((OPSStyle.Icons.location, address.formatAsSimpleAddress()))
                } else {
                    items.append((OPSStyle.Icons.location, "NO ADDRESS"))
                }
            }

            if let startDate = task.calendarEvent?.startDate {
                items.append((OPSStyle.Icons.calendar, DateHelper.fullDateString(from: startDate)))
            }

            let teamMemberCount = task.getTeamMemberIds().count
            if teamMemberCount > 0 {
                items.append((OPSStyle.Icons.personTwo, "\(teamMemberCount)"))
            }

            return items
        }
    }

    private func getTargetStatus(direction: SwipeDirection) -> Any? {
        switch cardType {
        case .project(let project):
            return direction == .right ? project.status.nextStatus() : project.status.previousStatus()
        case .task(let task):
            return direction == .right ? task.status.nextStatus() : task.status.previousStatus()
        case .client:
            return nil
        }
    }

    private func canSwipe(direction: SwipeDirection) -> Bool {
        switch cardType {
        case .project(let project):
            return direction == .right ? project.status.canSwipeForward : project.status.canSwipeBackward
        case .task(let task):
            return direction == .right ? task.status.canSwipeForward : task.status.canSwipeBackward
        case .client:
            return false
        }
    }

    private func performStatusChange(to newStatus: Any) {
        switch cardType {
        case .project(let project):
            if let status = newStatus as? Status {
                Task {
                    do {
                        try await dataController.updateProjectStatus(project: project, to: status)
                    } catch {
                        print("[UNIVERSAL_CARD] ❌ Failed to update project status: \(error)")
                    }
                }
            }
        case .task(let task):
            if let status = newStatus as? TaskStatus {
                Task {
                    do {
                        try await dataController.updateTaskStatus(task: task, to: status)
                    } catch {
                        print("[UNIVERSAL_CARD] ❌ Failed to update task status: \(error)")
                    }
                }
            }
        case .client:
            break
        }
    }

    private func handleSwipeChanged(value: DragGesture.Value, cardWidth: CGFloat) {
        guard !isChangingStatus else { return }

        let horizontalDrag = abs(value.translation.width)
        let verticalDrag = abs(value.translation.height)

        guard horizontalDrag > verticalDrag else { return }

        let direction: SwipeDirection = value.translation.width > 0 ? .right : .left

        guard canSwipe(direction: direction) else { return }

        withAnimation(.interactiveSpring()) {
            swipeOffset = value.translation.width
        }

        let swipePercentage = abs(swipeOffset) / cardWidth
        if swipePercentage >= 0.4 && !hasTriggeredHaptic {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            hasTriggeredHaptic = true
        }
    }

    private func handleSwipeEnded(value: DragGesture.Value, cardWidth: CGFloat) {
        guard !isChangingStatus else { return }

        let swipePercentage = abs(value.translation.width) / cardWidth
        let direction: SwipeDirection = value.translation.width > 0 ? .right : .left

        if swipePercentage >= 0.4, canSwipe(direction: direction), let targetStatus = getTargetStatus(direction: direction) {
            confirmingStatus = targetStatus
            confirmingDirection = direction
            isChangingStatus = true

            // Snap card back to center
            withAnimation(.easeInOut(duration: 0.15)) {
                swipeOffset = 0
            }

            // Brief flash of status confirmation (0.15s), then perform change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                performStatusChange(to: targetStatus)

                // Immediately hide confirmation after status change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isChangingStatus = false
                        confirmingStatus = nil
                        confirmingDirection = nil
                    }
                    hasTriggeredHaptic = false
                }
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                swipeOffset = 0
            }
            hasTriggeredHaptic = false
        }
    }

    private func deleteItem() {
        let itemName = title
        let itemType: String

        switch cardType {
        case .project:
            itemType = "PROJECT"
        case .client:
            itemType = "CLIENT"
        case .task:
            itemType = "TASK"
        }

        Task {
            do {
                switch cardType {
                case .project(let project):
                    try await dataController.deleteProject(project)
                case .client(let client):
                    // Safety check: Clients with projects should NEVER be deleted directly
                    // They must go through ClientDeletionSheet to handle project reassignment/deletion
                    guard client.projects.isEmpty else {
                        await MainActor.run {
                            customAlert = CustomAlertConfig(
                                title: "CANNOT DELETE CLIENT",
                                message: "This client has \(client.projects.count) project(s). Use the Delete option from the menu to properly handle projects.",
                                color: OPSStyle.Colors.errorStatus
                            )
                        }
                        return
                    }

                    // Only allow direct deletion if client has no projects
                    try await dataController.deleteClient(client)
                case .task(let task):
                    print("[DELETE_TASK_CARD] 🗑️ Deleting task: \(itemName)")
                    try await dataController.deleteTask(task)
                    print("[DELETE_TASK_CARD] ✅ Task deleted successfully")
                }

                // Show success feedback
                await MainActor.run {
                    customAlert = CustomAlertConfig(
                        title: "DELETION SUCCESS",
                        message: "\(itemName) has been deleted",
                        color: OPSStyle.Colors.successStatus
                    )
                    scheduleDeletionNotification(itemType: itemType, itemName: itemName)
                }
            } catch {
                print("[DELETE] ❌ Error deleting item: \(error)")
            }
        }
    }

    private func scheduleDeletionNotification(itemType: String, itemName: String) {
        let content = UNMutableNotificationContent()
        content.title = "OPS DATABASE"
        content.body = "Deletion of \(itemName) successful"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NOTIFICATION] Error scheduling notification: \(error)")
            }
        }
    }

    // Helper function to determine if UNSCHEDULED badge should be shown
    private func shouldShowUnscheduledBadge(for project: Project) -> Bool {
        // Check the project's scheduling mode
        if project.eventType == .project {
            // Project-based scheduling: Check if project's calendar event has a start date
            return project.primaryCalendarEvent?.startDate == nil
        } else {
            // Task-based scheduling: Check if any tasks are unscheduled
            let unscheduledTasks = project.tasks.filter { task in
                task.calendarEvent?.startDate == nil
            }
            return !unscheduledTasks.isEmpty
        }
    }
}

enum SwipeDirection {
    case left
    case right
}

struct RevealedStatusCard: View {
    let status: Any
    let direction: SwipeDirection

    private var statusText: String {
        if let projectStatus = status as? Status {
            return projectStatus.displayName.uppercased()
        } else if let taskStatus = status as? TaskStatus {
            return taskStatus.displayName.uppercased()
        }
        return ""
    }

    private var statusColor: Color {
        if let projectStatus = status as? Status {
            return projectStatus.color
        } else if let taskStatus = status as? TaskStatus {
            return taskStatus.color
        }
        return OPSStyle.Colors.primaryAccent
    }

    var body: some View {
        HStack {
            if direction == .left {
                Spacer()
            }

            Text(statusText)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(statusColor)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)

            if direction == .right {
                Spacer()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(statusColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(statusColor, lineWidth: 1)
        )
    }
}

struct ClientProjectBadges: View {
    let client: Client

    private var statusCounts: [Status: Int] {
        var counts: [Status: Int] = [:]
        for project in client.projects where project.status != .closed && project.status != .archived {
            counts[project.status, default: 0] += 1
        }
        return counts
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach([Status.rfq, .estimated, .accepted, .inProgress, .completed], id: \.self) { status in
                if let count = statusCounts[status], count > 0 {
                    Text("\(count)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(status.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(status.color.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(status.color, lineWidth: 1)
                        )
                }
            }
        }
    }
}
