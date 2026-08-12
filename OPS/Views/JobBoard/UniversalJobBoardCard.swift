//
//  UniversalJobBoardCard.swift
//  OPS
//
//  Created by Assistant on 2025-09-29.
//

import SwiftUI
import SwiftData
import Supabase

enum JobBoardCardType {
    case project(Project)
    case client(Client)
    case task(ProjectTask)
}

struct UniversalJobBoardCard: View {
    let cardType: JobBoardCardType
    var disableSwipe: Bool = false  // When true, disables swipe gestures (useful in sheets where scrolling is needed)
    var compact: Bool = false       // When true, renders a compact card layout (used in kanban board)
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.wizardStateManager) private var wizardStateManager
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @State private var tutorialShimmerOffset: CGFloat = -200
    @State private var showingMoreActions = false
    /// The one modal this card can have open. Was ten independent
    /// `.sheet(isPresented:)` / `.sheet(item:)` modifiers stacked on every card
    /// — each one a presentation the framework installs and tracks for every
    /// visible row, all of them rebuilt on every render of a list that keeps 8+
    /// rows alive. A card can only ever show one, so it holds one route.
    @State private var activeSheet: CardSheetRoute?
    @State private var selectedTaskForScheduling: ProjectTask? = nil
    @State private var isLongPressing = false
    @State private var hasTriggeredLongPressHaptic = false
    @State private var swipeOffset: CGFloat = 0
    @State private var isChangingStatus = false
    @State private var hasTriggeredHaptic = false
    @State private var confirmingStatus: Any? = nil
    @State private var confirmingDirection: CardSwipeDirection? = nil
    @State private var showingDeleteConfirmation = false
    @State private var showingWrongSwipeHint = false
    // Item 435cf11f — Share action on the project card's long-press menu.
    // The route carries the built item source (not a bool) so the activity
    // sheet can never snapshot an empty items array on first tap.
    @State private var isPreparingShare = false
    private let menuLongPressDuration: Double = 0.55
    private let menuLongPressMaximumDistance: CGFloat = 12

    private var isFieldCrew: Bool {
        !permissionStore.hasFullAccess("projects.view")
    }

    private var canModify: Bool {
        permissionStore.can("projects.edit")
    }

    private var canCreateProjects: Bool {
        permissionStore.can("projects.create")
    }

    private var canDeleteClients: Bool {
        permissionStore.can("clients.delete")
    }

    var body: some View {
        cardBody
            // One dialog, one sheet, one delete confirmation for all three card
            // kinds — the card renders exactly one of them, so the presentation
            // modifiers belong here rather than duplicated per kind.
            .confirmationDialog("Actions", isPresented: $showingMoreActions, titleVisibility: .hidden) {
                moreActionsContent
            }
            .sheet(item: $activeSheet) { route in
                sheetContent(for: route)
            }
            .deleteConfirmation(
                isPresented: $showingDeleteConfirmation,
                itemName: deleteItemName,
                onConfirm: deleteItem
            )
    }

    @ViewBuilder
    private var cardBody: some View {
        if case .client = cardType {
            clientCard
        } else if case .project = cardType {
            projectCard
                .padding(.vertical, compact ? 0 : 8)
        } else {
            taskCard
                .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Modal routing

    /// Every modal a job-board card can raise, as one route.
    private enum CardSheetRoute: Identifiable {
        case details              // project / client / task detail
        case parentProjectDetails // task card → its project
        case taskForm
        case projectForm
        case scheduler
        case taskPicker           // project reschedule with >1 schedulable task
        case statusPicker
        case teamPicker
        case clientDeletion
        case share(ProjectShareItemSource)

        var id: String {
            switch self {
            case .details:              return "details"
            case .parentProjectDetails: return "parentProjectDetails"
            case .taskForm:             return "taskForm"
            case .projectForm:          return "projectForm"
            case .scheduler:            return "scheduler"
            case .taskPicker:           return "taskPicker"
            case .statusPicker:         return "statusPicker"
            case .teamPicker:           return "teamPicker"
            case .clientDeletion:       return "clientDeletion"
            case .share:                return "share"
            }
        }
    }

    /// `Binding<Bool>` onto a single route, for sheets that dismiss themselves
    /// through an `isPresented` binding (CalendarSchedulerSheet).
    private func presented(_ route: CardSheetRoute) -> Binding<Bool> {
        Binding(
            get: { activeSheet?.id == route.id },
            set: { isPresented in
                if isPresented {
                    activeSheet = route
                } else if activeSheet?.id == route.id {
                    activeSheet = nil
                }
            }
        )
    }

    @ViewBuilder
    private func sheetContent(for route: CardSheetRoute) -> some View {
        switch route {
        case .details:
            detailsSheet
                .interactiveDismissDisabled(true)

        case .parentProjectDetails:
            if case .task(let task) = cardType,
               let project = JobBoardCardText.liveProject(of: task) {
                NavigationView {
                    ProjectDetailsView(project: project)
                }
                .interactiveDismissDisabled(true)
                .wizardBannerIfAvailable(stateManager: wizardStateManager)
                .wizardOverlayIfAvailable(stateManager: wizardStateManager)
            }

        case .taskForm:
            switch cardType {
            case .project(let project):
                TaskFormSheet(mode: .create, preselectedProjectId: project.id) { _ in }
            case .task(let task):
                if let project = JobBoardCardText.liveProject(of: task) {
                    TaskFormSheet(mode: .create, preselectedProjectId: project.id) { _ in }
                } else {
                    TaskFormSheet(mode: .create) { _ in }
                }
            case .client:
                TaskFormSheet(mode: .create) { _ in }
            }

        case .projectForm:
            if case .client(let client) = cardType {
                ProjectFormSheet(mode: .create, preselectedClient: client) { _ in }
                    .environmentObject(dataController)
            } else {
                ProjectFormSheet(mode: .create) { _ in }
                    .environmentObject(dataController)
            }

        case .scheduler:
            schedulerSheet

        case .taskPicker:
            taskPickerSheet

        case .statusPicker:
            switch cardType {
            case .project(let project):
                ProjectStatusChangeSheet(project: project)
                    .environmentObject(dataController)
            case .task(let task):
                TaskStatusChangeSheet(task: task)
                    .environmentObject(dataController)
            case .client:
                EmptyView()
            }

        case .teamPicker:
            switch cardType {
            case .project(let project):
                ProjectTeamChangeSheet(project: project)
                    .environmentObject(dataController)
            case .task(let task):
                TaskTeamChangeSheet(task: task)
                    .environmentObject(dataController)
            case .client:
                EmptyView()
            }

        case .clientDeletion:
            if case .client(let client) = cardType {
                ClientDeletionSheet(client: client)
                    .environmentObject(dataController)
            }

        case .share(let source):
            ActivityView(items: [source])
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
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .contentShape(Rectangle())
        .scaleEffect(isLongPressing ? 0.95 : 1.0)
        .animation(.accessibleEaseInOut(duration: 0.2), value: isLongPressing)
        .onTapGesture {
            // Block tap to open details during projectListSwipe tutorial phase
            if tutorialMode && tutorialPhase == .projectListSwipe {
                NotificationCenter.default.post(name: Notification.Name("TutorialSwipeGestureBlocked"), object: nil)
                return
            }
            activeSheet = .details
        }
        .onLongPressGesture(minimumDuration: menuLongPressDuration, maximumDistance: menuLongPressMaximumDistance) {
            // Block long press during projectListSwipe tutorial phase
            if tutorialMode && tutorialPhase == .projectListSwipe {
                NotificationCenter.default.post(name: Notification.Name("TutorialSwipeGestureBlocked"), object: nil)
                return
            }
            showingMoreActions = true
        } onPressingChanged: { pressing in
            if pressing {
                isLongPressing = true
                hasTriggeredLongPressHaptic = false
                DispatchQueue.main.asyncAfter(deadline: .now() + menuLongPressDuration) {
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
                    .directionalDrag(
                        isEnabled: canSwipeInAnyDirection,
                        onChanged: { translation in
                            handleSwipeChangedWidth(translation, cardWidth: geometry.size.width)
                        },
                        onEnded: { translation in
                            handleSwipeEndedWidth(translation, cardWidth: geometry.size.width)
                        }
                    )

                if isChangingStatus, let confirmingStatus = confirmingStatus, let direction = confirmingDirection {
                    RevealedStatusCard(status: confirmingStatus, direction: direction)
                        .opacity(isChangingStatus ? 1 : 0)
                }

                // Tutorial mode: Wrong swipe direction hint
                if showingWrongSwipeHint {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .bold))
                        Text("SWIPE RIGHT")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .fill(OPSStyle.Colors.overlayHeavy)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.thick)
                            )
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .frame(height: compact ? 72 : 80)
        .onTapGesture {
            // Block tap to open details during projectListSwipe tutorial phase
            if tutorialMode && tutorialPhase == .projectListSwipe {
                NotificationCenter.default.post(name: Notification.Name("TutorialSwipeGestureBlocked"), object: nil)
                return
            }
            activeSheet = .details
        }
        .onLongPressGesture(minimumDuration: menuLongPressDuration, maximumDistance: menuLongPressMaximumDistance) {
            // Block long press during projectListSwipe tutorial phase
            if tutorialMode && tutorialPhase == .projectListSwipe {
                NotificationCenter.default.post(name: Notification.Name("TutorialSwipeGestureBlocked"), object: nil)
                return
            }
            showingMoreActions = true
        } onPressingChanged: { pressing in
            if pressing {
                isLongPressing = true
                hasTriggeredLongPressHaptic = false
                DispatchQueue.main.asyncAfter(deadline: .now() + menuLongPressDuration) {
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
    }

    /// Builds the project's deep link + a thumbnail and presents the system
    /// share sheet. Reuses the same ProjectShareSheet infrastructure
    /// ProjectDetailsView uses, so a card share and a detail share produce an
    /// identical rich preview card. Thumbnail loads off the main thread; the
    /// share still works without one.
    private func shareProjectFromCard() {
        guard case .project(let project) = cardType else { return }
        guard !isPreparingShare, activeSheet == nil else { return }
        guard let url = ProjectShareLinkBuilder.url(for: project) else { return }

        let title = project.title
        let subtitle = project.effectiveClientName.isEmpty ? nil : project.effectiveClientName

        isPreparingShare = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task { @MainActor in
            let thumbnail = await ProjectShareImageLoader.loadFirstImage(for: project)
            activeSheet = .share(
                ProjectShareItemSource(
                    url: url,
                    title: title,
                    subtitle: subtitle,
                    image: thumbnail
                )
            )
            isPreparingShare = false

            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "project_shared",
                properties: [
                    "project_id": project.id,
                    "source": "job_board_card"
                ]
            )
        }
    }

    /// Whether to show tutorial shimmer for swipe hint
    private var shouldShowTutorialSwipeShimmer: Bool {
        tutorialMode && tutorialPhase == .projectListSwipe
    }

    @ViewBuilder
    private var projectCardContent: some View {
        Group {
            if compact {
                compactProjectCardContent
            } else {
                standardProjectCardContent
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isLongPressing ? 0.95 : 1.0)
        .animation(.accessibleEaseInOut(duration: 0.2), value: isLongPressing)
    }

    // MARK: - Compact project card content (kanban board)

    @ViewBuilder
    private var compactProjectCardContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            // Row 1: Project name
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            // Row 2: Client name - Address
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(subtitle)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)

                if case .project(let project) = cardType,
                   let address = project.address, !address.isEmpty {
                    Text("-")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(JobBoardCardText.streetOnly(address))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            // Row 3: Dates + task progress
            HStack(spacing: OPSStyle.Layout.spacing3) {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: OPSStyle.Icons.calendar)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(compactDateRange)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                if case .project(let project) = cardType {
                    compactTaskProgress(project: project)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .glassSurface(.listRow)
    }

    private var compactDateRange: String {
        guard case .project(let project) = cardType else { return "-" }
        let start = project.computedStartDate ?? project.startDate
        let end = project.computedEndDate ?? project.endDate
        switch (start, end) {
        case (let s?, let e?):
            return "\(DateHelper.simpleDateString(from: s)) - \(DateHelper.simpleDateString(from: e))"
        case (let s?, nil):
            return DateHelper.simpleDateString(from: s)
        case (nil, let e?):
            return "- \(DateHelper.simpleDateString(from: e))"
        case (nil, nil):
            return "-"
        }
    }

    @ViewBuilder
    private func compactTaskProgress(project: Project) -> some View {
        // One pass over project.tasks — was two filters allocating two arrays.
        let progress = JobBoardCompactProgress.make(project: project)
        let completed = progress.completed
        let total = progress.total

        if total > 0 {
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(0..<total, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < completed
                                  ? OPSStyle.Colors.successStatus
                                  : OPSStyle.Colors.cardBorder)
                            .frame(height: 3)
                    }
                }
                .frame(width: 48)

                Text("\(completed)/\(total)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        } else {
            Text("No tasks")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Standard project card content (full layout)

    @ViewBuilder
    private var standardProjectCardContent: some View {
        if case .project(let project) = cardType {
            // Every value the row needs from the project, derived ONCE per
            // render — crew count, address, dates, assignment, progress bars,
            // and the UNSCHEDULED rule, in a single pass over project.tasks.
            standardProjectCard(
                project: project,
                model: JobBoardProjectCardModel.make(
                    project: project,
                    currentUserId: dataController.currentUser?.id,
                    hasFullProjectView: permissionStore.hasFullAccess("projects.view")
                )
            )
        }
    }

    private func standardProjectCard(project: Project, model: JobBoardProjectCardModel) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    titleText(project.title.uppercased(), terminalStatus: project.status)
                    subtitleText(project.effectiveClientName)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Title flows full-width; the opaque overlay badges (top-right)
                // cover it where they sit, so no trailing reservation/truncation.

                metadataRow([
                    (OPSStyle.Icons.location, model.addressText),
                    (OPSStyle.Icons.calendar, model.dateText),
                    (OPSStyle.Icons.personTwo, "\(model.teamCount)")
                ])
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(OPSStyle.Layout.spacing3)
        }
        .glassSurface(.listRow)
        .overlay(
            // Tutorial shimmer effect over the card surface (blue/primaryAccent)
            Group {
                if shouldShowTutorialSwipeShimmer {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                Color.clear,
                                OPSStyle.Colors.primaryAccent.opacity(0.15),
                                OPSStyle.Colors.primaryAccent.opacity(0.25),
                                OPSStyle.Colors.primaryAccent.opacity(0.15),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 80)
                        .offset(x: tutorialShimmerOffset)
                        .onAppear {
                            startTutorialShimmer(cardWidth: geo.size.width)
                        }
                        .onChange(of: tutorialPhase) { _, newPhase in
                            if newPhase == .projectListSwipe {
                                startTutorialShimmer(cardWidth: geo.size.width)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
                    .allowsHitTesting(false)
                }
            }
        )
        .overlay(
            // Tutorial highlight border — emphasis state only, augments the glass edge
            Group {
                if shouldShowTutorialSwipeShimmer {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                        .strokeBorder(TutorialHighlightStyle.color, lineWidth: 2)
                }
            }
        )
        .overlay(
            Group {
                // Status badge + assigned-to-me badge — top right
                HStack(spacing: 6) {
                    if model.isAssignedToMe {
                        Text("ASSIGNED TO ME")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .fill(OPSStyle.Colors.surfaceRaised)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }

                    Text(project.status.displayName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(project.status.color)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .listRowBadgeFill(project.status.color, cornerRadius: OPSStyle.Layout.cardCornerRadius)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(OPSStyle.Layout.spacing2)

                // Task progress bars — always vertically centered, right side
                if project.status == .inProgress {
                    VStack {
                        taskProgressBars(model.progress)
                            .frame(width: 60)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                }

                // Unscheduled badge — bottom right
                if model.showsUnscheduledBadge {
                    VStack {
                        Text("UNSCHEDULED")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .listRowBadgeFill(OPSStyle.Colors.warningStatus, cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(OPSStyle.Layout.spacing2)
                }
            }
        )
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
                    .directionalDrag(
                        isEnabled: canSwipeInAnyDirection,
                        onChanged: { translation in
                            handleSwipeChangedWidth(translation, cardWidth: geometry.size.width)
                        },
                        onEnded: { translation in
                            handleSwipeEndedWidth(translation, cardWidth: geometry.size.width)
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
        if case .task(let task) = cardType {
            // One derivation per render replaces two whole-table Project
            // fetches, three whole-table TaskType fetches, and two assignee
            // CSV splits that the title, subtitle, stripe, metadata row, and
            // badges each used to pay for on their own.
            taskCard(
                task: task,
                model: JobBoardTaskCardModel.make(
                    task: task,
                    currentUserId: dataController.currentUser?.id,
                    hasFullTaskView: permissionStore.hasFullAccess("tasks.view")
                )
            )
        }
    }

    private func taskCard(task: ProjectTask, model: JobBoardTaskCardModel) -> some View {
        var metadata: [(icon: String, text: String)] = []
        if let addressText = model.addressText {
            metadata.append((OPSStyle.Icons.location, addressText))
        }
        metadata.append((OPSStyle.Icons.calendar, model.dateText))
        metadata.append((OPSStyle.Icons.personTwo, "\(model.teamCount)"))

        let stripeColor = model.typeColorHex.flatMap { Color(hex: $0) } ?? OPSStyle.Colors.tertiaryText

        return HStack(spacing: 0) {
            Rectangle()
                .fill(stripeColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    titleText(model.title, terminalStatus: nil)
                    subtitleText(model.subtitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                metadataRow(metadata)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(OPSStyle.Layout.spacing3)
        }
        .glassSurface(.listRow)
        .overlay(
            ZStack {
                // Status badge + assigned-to-me badge — top right
                HStack(spacing: 6) {
                    // READY — predecessors all complete, this task can start.
                    if model.isReadyToStart {
                        TaskReadyBadge(surface: .listRow)
                    }

                    if model.isAssignedToMe {
                        Text("ASSIGNED TO ME")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .fill(OPSStyle.Colors.surfaceRaised)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }

                    Text(task.status.displayName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(task.status.color)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .listRowBadgeFill(task.status.color, cornerRadius: OPSStyle.Layout.cardCornerRadius)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(OPSStyle.Layout.spacing2)

                if model.isUnscheduled {
                    Text("UNSCHEDULED")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .listRowBadgeFill(OPSStyle.Colors.warningStatus, cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(OPSStyle.Layout.spacing2)
                }
            }
        )
        .contentShape(Rectangle())
        .scaleEffect(isLongPressing ? 0.95 : 1.0)
        .animation(.accessibleEaseInOut(duration: 0.2), value: isLongPressing)
        .onTapGesture {
            // Block tap to open details during projectListSwipe tutorial phase
            if tutorialMode && tutorialPhase == .projectListSwipe {
                NotificationCenter.default.post(name: Notification.Name("TutorialSwipeGestureBlocked"), object: nil)
                return
            }
            activeSheet = .details
        }
        .onLongPressGesture(minimumDuration: menuLongPressDuration, maximumDistance: menuLongPressMaximumDistance) {
            // Block long press during projectListSwipe tutorial phase
            if tutorialMode && tutorialPhase == .projectListSwipe {
                NotificationCenter.default.post(name: Notification.Name("TutorialSwipeGestureBlocked"), object: nil)
                return
            }
            showingMoreActions = true
        } onPressingChanged: { pressing in
            if pressing {
                isLongPressing = true
                hasTriggeredLongPressHaptic = false
                DispatchQueue.main.asyncAfter(deadline: .now() + menuLongPressDuration) {
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
    }

    /// Progress segments, already ordered and single-passed by
    /// `JobBoardProjectCardModel` — the bar only paints them.
    @ViewBuilder
    private func taskProgressBars(_ segments: [JobBoardTaskProgressState]) -> some View {
        if !segments.isEmpty {
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            segment == .completed ? OPSStyle.Colors.successStatus :
                            segment == .cancelled ? OPSStyle.Colors.errorStatus.opacity(0.5) :
                            OPSStyle.Colors.cardBorder
                        )
                        .frame(height: 3)
                }
            }
        }
    }

    /// - Parameter terminalStatus: the project's status, or nil for a task row.
    ///   For projects in a terminal state (completed / closed / archived) we
    ///   surface an inline title-adjacent badge so the finished status is
    ///   impossible to miss. The corner status chip still renders for every
    ///   project — this badge augments it, it does not replace it.
    @ViewBuilder
    private func titleText(_ text: String, terminalStatus: Status?) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .baselineOffset(0)
                .layoutPriority(1)

            if let terminalStatus, let terminalBadge = terminalStatusBadge(for: terminalStatus) {
                terminalBadge
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            }
        }
    }

    /// Returns an inline "DONE", "CLOSED", or "ARCHIVED" pill for terminal
    /// project statuses so a completed job reads as finished at a glance —
    /// even before the user looks at the corner status chip. Non-terminal
    /// statuses return `nil` so no badge renders.
    ///
    /// Not a `@ViewBuilder` — we need an optional return, and @ViewBuilder
    /// can't construct `Optional<View>` from explicit `return nil`.
    private func terminalStatusBadge(for status: Status) -> AnyView? {
        switch status {
        case .completed:
            // Bug 206ffff1 — the corner status chip already reads "COMPLETED",
            // so an inline "DONE" pill is redundant noise. CLOSED and ARCHIVED
            // are distinct enough from the chip to keep their badges (they
            // signal post-completion state the chip alone doesn't convey).
            return nil
        case .closed:
            return AnyView(
                inlineBadge(
                    text: "CLOSED",
                    color: OPSStyle.Colors.inactiveStatus
                )
            )
        case .archived:
            return AnyView(
                inlineBadge(
                    text: "ARCHIVED",
                    color: OPSStyle.Colors.tertiaryText
                )
            )
        default:
            return nil
        }
    }

    @ViewBuilder
    private func inlineBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(color)
            .tracking(1.0)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                    .stroke(color.opacity(0.6), lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    @ViewBuilder
    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .baselineOffset(0)
    }


    @ViewBuilder
    private func metadataRow(_ items: [(icon: String, text: String)]) -> some View {
        GeometryReader { geometry in
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: item.icon)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        if index == 0 {
                            // Address field - truncates at 35% max width
                            Text(item.text)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: geometry.size.width * 0.35, alignment: .leading)
                        } else {
                            // Other fields - natural width
                            Text(item.text)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()
            }
        }
        .frame(height: 16)
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
                activeSheet = .details
            }

            Button("Share") {
                shareProjectFromCard()
            }

            if canModify {
                Button("Add Task") {
                    activeSheet = .taskForm
                }
            }

            // Reschedule is gated on calendar.edit (scope-aware on the project),
            // not projects.edit — scheduling authority is separate from editing.
            if case .project(let project) = cardType,
               project.canEditSchedule,
               UniversalSearchScheduleTargeting.target(forProject: project) != .unavailable {
                Button("Reschedule") {
                    handleRescheduleForProject()
                }
            }

            Button("Change Status") {
                activeSheet = .statusPicker
            }

            if canModify {
                Button("Change Team") {
                    activeSheet = .teamPicker
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
                activeSheet = .details
            }

            if canCreateProjects {
                Button("Add Project") {
                    activeSheet = .projectForm
                }
            }

            if canDeleteClients {
                Button("Delete", role: .destructive) {
                    activeSheet = .clientDeletion
                }
            }

            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var taskActions: some View {
        Group {
            Button("View Task") {
                activeSheet = .details
            }

            Button("View Project") {
                activeSheet = .parentProjectDetails
            }

            // Reschedule is gated on calendar.edit (scope-aware on the task),
            // not projects.edit — a user may edit the task but not move it.
            if case .task(let task) = cardType, task.canEditSchedule {
                Button("Reschedule") {
                    activeSheet = .scheduler
                }
            }

            Button("Change Status") {
                activeSheet = .statusPicker
            }

            if canModify {
                Button("Change Team") {
                    activeSheet = .teamPicker
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
            if let project = JobBoardCardText.liveProject(of: task) {
                NavigationView {
                    ProjectDetailsView(project: project, initialSelectedTask: task)
                        .environmentObject(dataController)
                }
            }
        }
    }

    @ViewBuilder
    private var schedulerSheet: some View {
        switch cardType {
        case .project:
            // If a specific task was selected, schedule it instead of the project
            if let selectedTask = selectedTaskForScheduling {
                CalendarSchedulerSheet(
                    isPresented: presented(.scheduler),
                    itemType: .task(selectedTask),
                    currentStartDate: selectedTask.startDate,
                    currentEndDate: selectedTask.endDate,
                    onScheduleUpdate: { startDate, endDate in
                        Task {
                            do {
                                // Update dates directly on the task
                                guard selectedTask.canEditSchedule else { return }
                                try await dataController.updateTaskSchedule(task: selectedTask, startDate: startDate, endDate: endDate)

                                // Update parent project dates if necessary
                                if let project = selectedTask.project {
                                    let tasksWithDates = project.tasks.filter { $0.startDate != nil }
                                    if !tasksWithDates.isEmpty {
                                        let earliestStart = tasksWithDates.compactMap { $0.startDate }.min() ?? startDate
                                        let latestEnd = tasksWithDates.compactMap { $0.endDate }.max() ?? endDate

                                        if project.startDate != earliestStart || project.endDate != latestEnd {
                                            try await dataController.updateProjectDates(project: project, startDate: earliestStart, endDate: latestEnd)
                                        }
                                    }
                                }
                            } catch {
                                print("❌ Failed to sync task schedule: \(error)")
                            }
                        }
                    },
                    onClearDates: {
                        // Clear task dates
                        Task {
                            do {
                                guard selectedTask.canEditSchedule else { return }
                                // Clear dates directly on the task
                                await MainActor.run {
                                    selectedTask.startDate = nil
                                    selectedTask.endDate = nil
                                    selectedTask.duration = 0
                                    selectedTask.needsSync = true
                                    try? dataController.modelContext?.save()
                                }

                                // Persist the cleared dates to Supabase. Previously this
                                // only saved locally and synced the project, so the task
                                // stayed scheduled on web after being cleared on device.
                                try await dataController.updateTaskFields(taskId: selectedTask.id, fields: [
                                    "start_date": .null,
                                    "end_date": .null,
                                    "duration": .integer(0)
                                ])
                                await MainActor.run {
                                    selectedTask.needsSync = false
                                    selectedTask.lastSyncedAt = Date()
                                    try? dataController.modelContext?.save()
                                }

                                // Update parent project dates if necessary
                                if let project = selectedTask.project {
                                    let tasksWithDates = project.tasks.filter { $0.startDate != nil && $0.endDate != nil }

                                    if tasksWithDates.isEmpty {
                                        try await dataController.updateProjectDates(project: project, startDate: nil, endDate: nil, clearDates: true)
                                    } else {
                                        let earliestStart = tasksWithDates.compactMap { $0.startDate }.min()
                                        let latestEnd = tasksWithDates.compactMap { $0.endDate }.max()

                                        if let start = earliestStart, let end = latestEnd {
                                            try await dataController.updateProjectDates(project: project, startDate: start, endDate: end)
                                        }
                                    }
                                }
                            } catch {
                                print("❌ Failed to clear task dates: \(error)")
                            }
                        }
                    }
                )
                .environmentObject(dataController)
                .onDisappear {
                    // Clear the selected task when sheet is dismissed
                    selectedTaskForScheduling = nil
                }
            } else {
                Color.clear
                    .onAppear { activeSheet = nil }
            }
        case .task(let task):
            CalendarSchedulerSheet(
                isPresented: presented(.scheduler),
                itemType: .task(task),
                currentStartDate: task.startDate,
                currentEndDate: task.endDate,
                onScheduleUpdate: { startDate, endDate in
                    Task {
                        do {
                            // Update dates directly on the task
                            guard task.canEditSchedule else { return }
                            try await dataController.updateTaskSchedule(task: task, startDate: startDate, endDate: endDate)

                            // Update parent project dates if necessary
                            if let project = task.project {
                                let tasksWithDates = project.tasks.filter { $0.startDate != nil }
                                if !tasksWithDates.isEmpty {
                                    let earliestStart = tasksWithDates.compactMap { $0.startDate }.min() ?? startDate
                                    let latestEnd = tasksWithDates.compactMap { $0.endDate }.max() ?? endDate

                                    if project.startDate != earliestStart || project.endDate != latestEnd {
                                        try await dataController.updateProjectDates(project: project, startDate: earliestStart, endDate: latestEnd)
                                    }
                                }
                            }
                        } catch {
                            print("❌ Failed to sync task schedule: \(error)")
                        }
                    }
                },
                onClearDates: {
                    // Clear task dates
                    Task {
                        do {
                            guard task.canEditSchedule else { return }
                            print("🗑️ [JOB_BOARD] Clearing task dates")

                            // Update locally
                            await MainActor.run {
                                task.startDate = nil
                                task.endDate = nil
                                task.duration = 0
                                task.needsSync = true
                                try? dataController.modelContext?.save()
                            }

                            // Sync to Supabase
                            let fields: [String: AnyJSON] = [
                                "start_date": .null,
                                "end_date": .null,
                                "duration": .integer(0)
                            ]
                            try await dataController.updateTaskFields(taskId: task.id, fields: fields)
                            await MainActor.run {
                                task.needsSync = false
                                task.lastSyncedAt = Date()
                                try? dataController.modelContext?.save()
                            }

                            // Update parent project dates if necessary
                            if let project = task.project {
                                let tasksWithDates = project.tasks.filter { $0.startDate != nil && $0.endDate != nil }

                                if tasksWithDates.isEmpty {
                                    try await dataController.updateProjectDates(project: project, startDate: nil, endDate: nil, clearDates: true)
                                } else {
                                    let earliestStart = tasksWithDates.compactMap { $0.startDate }.min()
                                    let latestEnd = tasksWithDates.compactMap { $0.endDate }.max()

                                    if let start = earliestStart, let end = latestEnd {
                                        try await dataController.updateProjectDates(project: project, startDate: start, endDate: end)
                                    }
                                }
                            }

                            print("✅ [JOB_BOARD] Task dates cleared")
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

    // MARK: - Helper Functions

    /// Handle reschedule action for projects
    /// Checks if project has tasks and shows appropriate UI
    private func handleRescheduleForProject() {
        guard case .project(let project) = cardType else { return }
        guard project.canEditSchedule else { return }

        let activeTasks = UniversalSearchScheduleTargeting.schedulableTasks(forProject: project)

        if activeTasks.isEmpty {
            // No tasks - present toast with action to create one
            ToastCenter.shared.present(Feedback.JobBoard.noTasksToReschedule(createTask: { activeSheet = .taskForm }))
        } else if activeTasks.count == 1 {
            // Exactly one task - reschedule it automatically
            selectedTaskForScheduling = activeTasks.first
            activeSheet = .scheduler
        } else {
            // Multiple tasks - show task picker
            activeSheet = .taskPicker
        }
    }

    /// Task picker sheet for selecting which task to reschedule
    private var taskPickerSheet: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .edgesIgnoringSafeArea(.all)

                if case .project(let project) = cardType {
                    let activeTasks = UniversalSearchScheduleTargeting.schedulableTasks(forProject: project)

                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing2_5) {
                            ForEach(activeTasks, id: \.id) { task in
                                Button(action: {
                                    selectedTaskForScheduling = task
                                    activeSheet = .scheduler
                                }) {
                                    HStack {
                                        Circle()
                                            .fill(Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent)
                                            .frame(width: 12, height: 12)

                                        if let taskType = task.taskType {
                                            if let icon = taskType.icon {
                                                Image(systemName: icon)
                                                    .foregroundColor(Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent)
                                            }
                                        }

                                        Text(task.displayTitle.uppercased())
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(OPSStyle.Colors.primaryText)

                                        Spacer()

                                        // Show dates if scheduled
                                        if let startDate = task.startDate,
                                           let endDate = task.endDate {
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(startDate, style: .date)
                                                    .font(OPSStyle.Typography.smallCaption)
                                                Text(endDate, style: .date)
                                                    .font(OPSStyle.Typography.smallCaption)
                                            }
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                        } else {
                                            Text("NOT SCHEDULED")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        }

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    }
                                    .padding()
                                    .glassSurface()
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("SELECT TASK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("CANCEL") {
                        activeSheet = nil
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
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
            // Relationship read — SwiftData already holds the row the old
            // whole-table `getAllTaskTypes(for:).first(where:)` was matching by
            // id (wired in `InboundProcessor.linkAllRelationships`).
            return task.taskType?.display.uppercased() ?? "TASK"
        }
    }

    private var subtitle: String {
        switch cardType {
        case .project(let project):
            return project.effectiveClientName
        case .client(let client):
            let projectCount = client.activeProjects.count
            return "\(projectCount) \(projectCount == 1 ? "project" : "projects")"
        case .task(let task):
            // Relationship read, tombstone-gated — see `JobBoardCardText.liveProject`.
            if let project = JobBoardCardText.liveProject(of: task) {
                let clientName = project.effectiveClientName
                return "\(project.title) - \(clientName)"
            }
            return "No project"
        }
    }

    private func getTargetStatus(direction: CardSwipeDirection) -> Any? {
        switch cardType {
        case .project(let project):
            return direction == .right ? project.status.nextStatus() : project.status.previousStatus()
        case .task(let task):
            return direction == .right ? task.status.nextStatus() : task.status.previousStatus()
        case .client:
            return nil
        }
    }

    private func canSwipe(direction: CardSwipeDirection) -> Bool {
        switch cardType {
        case .project(let project):
            // Permission gate: require projects.edit to change project status via swipe
            guard PermissionStore.shared.can("projects.edit") else { return false }
            return direction == .right ? project.status.canSwipeForward : project.status.canSwipeBackward
        case .task(let task):
            // Permission gate: require tasks.change_status to change task status via swipe
            guard PermissionStore.shared.can("tasks.change_status") else { return false }
            return direction == .right ? task.status.canSwipeForward : task.status.canSwipeBackward
        case .client:
            return false
        }
    }

    /// Returns true if the card can swipe in at least one direction (and swipe is not disabled)
    private var canSwipeInAnyDirection: Bool {
        !disableSwipe && (canSwipe(direction: .left) || canSwipe(direction: .right))
    }

    private func performStatusChange(to newStatus: Any) {
        switch cardType {
        case .project(let project):
            if let status = newStatus as? Status {
                // CENTRALIZED COMPLETION CHECK: If completing project, check for incomplete tasks first
                if status == .completed {
                    if !appState.requestProjectCompletion(project) {
                        // Has incomplete tasks - checklist sheet will be shown globally
                        return
                    }
                }

                Task {
                    do {
                        try await dataController.updateProjectStatus(project: project, to: status)

                        // Post notification for tutorial system to detect swipe status changes
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: Notification.Name("ProjectStatusChanged"),
                                object: nil,
                                userInfo: ["projectId": project.id, "newStatus": status]
                            )
                            // Wizard system: notify project status changed
                            NotificationCenter.default.post(
                                name: Notification.Name("WizardProjectStatusChanged"),
                                object: nil
                            )
                        }
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

    // MARK: - CGFloat-based handlers used by DirectionalDragModifier

    /// Called by directionalDrag modifier; axis discrimination is handled upstream.
    private func handleSwipeChangedWidth(_ translationWidth: CGFloat, cardWidth: CGFloat) {
        guard !isChangingStatus else { return }

        let direction: CardSwipeDirection = translationWidth > 0 ? .right : .left

        // Tutorial mode: During projectListSwipe, ONLY allow right swipe (to complete project)
        if tutorialMode && tutorialPhase == .projectListSwipe {
            if direction == .left {
                if !showingWrongSwipeHint {
                    showingWrongSwipeHint = true
                    TutorialHaptics.error()
                    NotificationCenter.default.post(name: Notification.Name("TutorialWrongAction"), object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            self.showingWrongSwipeHint = false
                        }
                    }
                }
                return
            }
        }

        guard canSwipe(direction: direction) else { return }

        swipeOffset = translationWidth

        let swipePercentage = abs(swipeOffset) / cardWidth
        if swipePercentage >= 0.4 && !hasTriggeredHaptic {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            hasTriggeredHaptic = true
        }
    }

    /// Called by directionalDrag modifier; axis discrimination is handled upstream.
    private func handleSwipeEndedWidth(_ translationWidth: CGFloat, cardWidth: CGFloat) {
        guard !isChangingStatus else { return }

        let swipePercentage = abs(translationWidth) / cardWidth
        let direction: CardSwipeDirection = translationWidth > 0 ? .right : .left

        // Tutorial mode: Block left swipe during projectListSwipe
        if tutorialMode && tutorialPhase == .projectListSwipe && direction == .left {
            withAnimation(OPSStyle.Animation.standard) {
                swipeOffset = 0
            }
            hasTriggeredHaptic = false
            return
        }

        if swipePercentage >= 0.4, canSwipe(direction: direction), let targetStatus = getTargetStatus(direction: direction) {
            confirmingStatus = targetStatus
            confirmingDirection = direction
            isChangingStatus = true

            if tutorialMode {
                if case .project(let project) = cardType {
                    NotificationCenter.default.post(
                        name: Notification.Name("ProjectStatusChanged"),
                        object: nil,
                        userInfo: ["projectId": project.id, "newStatus": targetStatus]
                    )
                }
            }

            withAnimation(OPSStyle.Animation.standard) {
                swipeOffset = 0
            }

            let flashDelay: Double = tutorialMode ? 0.05 : 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + flashDelay) {
                performStatusChange(to: targetStatus)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(OPSStyle.Animation.standard) {
                        isChangingStatus = false
                        confirmingStatus = nil
                        confirmingDirection = nil
                    }
                    hasTriggeredHaptic = false
                }
            }
        } else {
            withAnimation(OPSStyle.Animation.standard) {
                swipeOffset = 0
            }
            hasTriggeredHaptic = false
        }
    }

    // MARK: - Legacy DragGesture.Value handlers (retained, no longer attached to gesture)

    private func handleSwipeChanged(value: DragGesture.Value, cardWidth: CGFloat) {
        guard !isChangingStatus else { return }

        let horizontalDrag = abs(value.translation.width)
        let verticalDrag = abs(value.translation.height)

        // Only activate swipe if horizontal movement is clearly dominant
        guard horizontalDrag > verticalDrag else { return }

        let direction: CardSwipeDirection = value.translation.width > 0 ? .right : .left

        // Tutorial mode: During projectListSwipe, ONLY allow right swipe (to complete project)
        if tutorialMode && tutorialPhase == .projectListSwipe {
            if direction == .left {
                // Block left swipe entirely during tutorial - show hint
                if !showingWrongSwipeHint {
                    showingWrongSwipeHint = true
                    TutorialHaptics.error()
                    // Notify tooltip to enter error state
                    NotificationCenter.default.post(name: Notification.Name("TutorialWrongAction"), object: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            self.showingWrongSwipeHint = false
                        }
                    }
                }
                return
            }
            // Right swipe allowed during tutorial - continue
        }

        guard canSwipe(direction: direction) else { return }

        withAnimation(.accessibleEaseInOut()) {
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
        let direction: CardSwipeDirection = value.translation.width > 0 ? .right : .left

        // Tutorial mode: Block left swipe during projectListSwipe
        if tutorialMode && tutorialPhase == .projectListSwipe && direction == .left {
            withAnimation(.accessibleEaseInOut()) {
                swipeOffset = 0
            }
            hasTriggeredHaptic = false
            return
        }

        if swipePercentage >= 0.4, canSwipe(direction: direction), let targetStatus = getTargetStatus(direction: direction) {
            confirmingStatus = targetStatus
            confirmingDirection = direction
            isChangingStatus = true

            // Tutorial mode: Post notification immediately for fast tutorial advance
            if tutorialMode {
                if case .project(let project) = cardType {
                    NotificationCenter.default.post(
                        name: Notification.Name("ProjectStatusChanged"),
                        object: nil,
                        userInfo: ["projectId": project.id, "newStatus": targetStatus]
                    )
                }
            }

            // Snap card back to center with smooth animation
            withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                swipeOffset = 0
            }

            // Brief flash of status confirmation, then perform change
            // In tutorial mode, use shorter delay for smoother flow
            let flashDelay: Double = tutorialMode ? 0.05 : 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + flashDelay) {
                performStatusChange(to: targetStatus)

                // Immediately hide confirmation after status change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.accessibleEaseInOut(duration: 0.2)) {
                        isChangingStatus = false
                        confirmingStatus = nil
                        confirmingDirection = nil
                    }
                    hasTriggeredHaptic = false
                }
            }
        } else {
            withAnimation(.accessibleEaseInOut()) {
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
                    // Only active (non-deleted) projects count here — soft-deleted rows are
                    // tombstones and shouldn't block a client delete.
                    let activeProjects = client.activeProjects
                    guard activeProjects.isEmpty else {
                        await MainActor.run {
                            ToastCenter.shared.present(Toast(label: "// CLIENT HAS ACTIVE PROJECTS", tone: .error))
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

                // Show success feedback via canonical toast
                await MainActor.run {
                    ToastCenter.shared.present(Feedback.JobBoard.deleted)
                }
            } catch {
                print("[DELETE] ❌ Error deleting item: \(error)")
            }
        }
    }

    // REMOVED: scheduleDeletionNotification - now using in-app popup only

    // MARK: - Tutorial Shimmer Animation

    /// Starts the tutorial shimmer animation for swipe hint
    private func startTutorialShimmer(cardWidth: CGFloat) {
        // Reset to start position
        tutorialShimmerOffset = -100

        // Animate across the card width
        withAnimation(
            .linear(duration: 1.5)
            .repeatForever(autoreverses: false)
        ) {
            tutorialShimmerOffset = cardWidth + 100
        }
    }
}

enum CardSwipeDirection {
    case left
    case right
}

struct RevealedStatusCard: View {
    let status: Any
    let direction: CardSwipeDirection

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
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

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
                .stroke(statusColor, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

struct ClientProjectBadges: View {
    let client: Client

    private var statusCounts: [Status: Int] {
        var counts: [Status: Int] = [:]
        for project in client.activeProjects where project.status != .closed && project.status != .archived {
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
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .fill(status.color.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(status.color, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
            }
        }
    }
}
