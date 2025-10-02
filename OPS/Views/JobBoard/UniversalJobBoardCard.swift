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

            Button("Add Task") {
                showingTaskForm = true
            }

            Button("Reschedule") {
                showingScheduler = true
            }

            Button("Change Status") {
                showingStatusPicker = true
            }

            Button("Change Team") {
                showingTeamPicker = true
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

            Button("Add Project") {
                showingProjectForm = true
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

            Button("Reschedule") {
                showingScheduler = true
            }

            Button("Change Status") {
                showingStatusPicker = true
            }

            Button("Change Team") {
                showingTeamPicker = true
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
            TeamMemberDetailView(client: client, project: nil)
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
                    project.startDate = startDate
                    project.endDate = endDate
                    project.needsSync = true
                    try? dataController.modelContext?.save()
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
                    if let calendarEvent = task.calendarEvent {
                        calendarEvent.startDate = startDate
                        calendarEvent.endDate = endDate
                        calendarEvent.needsSync = true
                    }
                    try? dataController.modelContext?.save()
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

            if let startDate = project.startDate {
                items.append((OPSStyle.Icons.calendar, DateHelper.fullDateString(from: startDate)))
            }

            if !project.teamMembers.isEmpty {
                items.append((OPSStyle.Icons.personTwo, "\(project.teamMembers.count)"))
            }

            if project.eventType == .task {
                items.append((OPSStyle.Icons.checklist, "\(project.tasks.count)"))
            } else {
                items.append((OPSStyle.Icons.folderFill, "Project"))
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
                project.status = status
                project.needsSync = true
                try? modelContext.save()
            }
        case .task(let task):
            if let status = newStatus as? TaskStatus {
                task.status = status
                task.needsSync = true
                try? modelContext.save()
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

            withAnimation(.easeInOut(duration: 0.2)) {
                swipeOffset = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                performStatusChange(to: targetStatus)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
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
