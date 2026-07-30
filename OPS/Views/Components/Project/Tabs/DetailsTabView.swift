//
//  DetailsTabView.swift
//  OPS
//
//  Project metadata organized in card sections — the Details tab.
//  Sections are permission-scoped: each renders only for viewers who hold the
//  permission that governs its data (clients.view → CLIENT, team.view → TEAM,
//  catalog.orders.view → VINYL ordering, projects.edit → edit/delete
//  affordances). A field-crew member is left with a focused where/what/when
//  view — status, timeline, client contact, address, tasks, reminders,
//  description — and none of the owner/office management depth that read as
//  "way too much" on site. Gating is by permission, never by role name.
//

import SwiftUI
import SwiftData
import MapKit

struct DetailsTabView: View {
    @Bindable var project: Project
    @ObservedObject var viewModel: ProjectDetailsViewModel
    let onClientTap: () -> Void
    let onTeamMemberTap: (User) -> Void
    let onTaskTap: (ProjectTask) -> Void
    let onAddTask: () -> Void
    var onSelectTask: ((ProjectTask) -> Void)? = nil
    var onCompleteTask: ((ProjectTask) -> Void)? = nil
    var onReopenTask: ((ProjectTask) -> Void)? = nil
    var onCancelTask: ((ProjectTask) -> Void)? = nil
    var onDuplicateTask: ((ProjectTask) -> Void)? = nil
    var onDeleteTask: ((ProjectTask) -> Void)? = nil
    var onClientLongPress: (() -> Void)? = nil
    /// Opens the existing `ProjectStatusChangeSheet` (wired in
    /// ProjectDetailsView via `showingStatusPicker`). Bug f3a300f7 — the
    /// Details surface previously had no affordance to reach that sheet.
    var onChangeStatus: (() -> Void)? = nil

    /// All Users in the store. Used to resolve team member avatars from the
    /// authoritative `teamMemberIdsString` CSV on both Project and ProjectTask.
    /// We render from this lookup rather than the `teamMembers: [User]`
    /// SwiftData relationship because that relationship can be empty even
    /// when the id-string has values (hydration lag: user-objects may sync
    /// in a separate batch, or `linkAllRelationships` may not have run yet
    /// for a freshly-inserted local row).
    @Query private var allUsers: [User]
    @Query private var vinylOrderMarkers: [ProjectVinylOrderMarker]

    private var userById: [String: User] {
        Dictionary(allUsers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Resolve the project's team members from the canonical id string.
    /// Falls back to the relationship only if the id string is empty — that's
    /// the legitimate "no one assigned" case.
    private var resolvedProjectTeam: [User] {
        let ids = project.getTeamMemberIds()
        guard !ids.isEmpty else { return [] }
        return ids.compactMap { userById[$0] }
    }

    private var vinylOrderMarker: ProjectVinylOrderMarker? {
        vinylOrderMarkers.first { $0.projectId == project.id }
    }

    /// Permission-scoped section visibility for this viewer (never role-based).
    private var access: DetailsTabAccess {
        DetailsTabAccess(permissions: .shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            // STATUS — current project status + manual change control.
            // Bug f3a300f7 — opens the existing ProjectStatusChangeSheet
            // through the parent's `showingStatusPicker` hook.
            StatusSection(
                status: project.status,
                canEdit: viewModel.canEditProject,
                onChangeStatus: onChangeStatus
            )

            // PROJECT INFO — client, address, timeline, description, team in
            // ONE card of hairline-separated rows. Five separately-labelled
            // cards made the reader parse five objects to answer one question:
            // what is this job, and where. Each row names its own field, so the
            // card carries no header of its own.
            projectInfoCard

            // VINYL ORDER MARKER — order tracking is a purchasing/office concern,
            // not an on-site one; hidden from field crew. See DetailsTabAccess.
            if access.showsVinylOrder {
                VinylOrderMarkerSection(
                    marker: vinylOrderMarker,
                    canEdit: viewModel.canEditVinylOrderMarker,
                    isUpdating: viewModel.isUpdatingVinylOrderMarker,
                    onToggle: { ordered in viewModel.setVinylOrdered(ordered) }
                )
            }

            // TASKS
            TaskListSection(
                tasks: project.tasks.sorted { $0.displayOrder < $1.displayOrder },
                selectedTask: viewModel.selectedTask,
                project: project,
                canEdit: viewModel.canEditProject,
                canDuplicate: viewModel.canDuplicateTasks,
                userById: userById,
                onTaskTap: onTaskTap,
                onAddTask: onAddTask,
                onSelectTask: onSelectTask,
                onCompleteTask: onCompleteTask,
                onReopenTask: onReopenTask,
                onCancelTask: onCancelTask,
                onDuplicateTask: onDuplicateTask,
                onDeleteTask: onDeleteTask
            )

            // REMINDERS (bug 4f00c2d7) — only renders when there's at least
            // one open reminder across the project's open tasks
            ProjectReminderChecklist(project: project)

            // DELETE PROJECT (admin only)
            if viewModel.canEditProject {
                Button(action: {
                    viewModel.showingDeleteAlert = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: OPSStyle.Icons.delete)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        Text("DELETE PROJECT")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }

            Spacer()
                .frame(height: 200)
        }
        .padding(.top, OPSStyle.Layout.spacing3)
        .onAppear {
            NotificationCenter.default.post(name: Notification.Name("WizardDetailsTabViewed"), object: nil)
        }
        .sheet(item: $viewModel.pendingVinylOrderConfirm) { ctx in
            VinylOrderConfirmSheet(
                projectTitle: ctx.projectTitle,
                deckTitle: ctx.deckTitle,
                rollWidthInches: ctx.rollWidthInches,
                calculated: ctx.calculated,
                onConfirm: { confirmed in viewModel.confirmVinylOrder(ctx, confirmed) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Project Info Card

    /// The project's identity block — who it's for, where it is, when it runs,
    /// what it is, who's on it — as ONE card of hairline-separated rows.
    ///
    /// Rows leave the card two ways: by permission (CLIENT, TEAM) and by
    /// absence (no tasks means no span; a description nobody can read or write
    /// is not a field). Both the row and the hairline above it read the same
    /// `shows(_:)` answer, so a departed row can never leave a doubled line or
    /// one dangling at an edge.
    private var projectInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if shows(.client) {
                hairline(above: .client)
                ClientRow(
                    project: project,
                    canEdit: viewModel.canEditProject,
                    onContactTap: onClientTap,
                    onCall: { if let p = project.effectiveClientPhone { viewModel.callPhone(p) } },
                    onEmail: { if let e = project.effectiveClientEmail { viewModel.sendEmail(e) } },
                    onAssignClient: onClientLongPress
                )
            }

            if shows(.address) {
                hairline(above: .address)
                AddressRow(
                    address: project.address,
                    canEdit: viewModel.canEditProject,
                    onDirections: { viewModel.openDirections() },
                    onSaveAddress: { newAddress in
                        viewModel.editedAddress = newAddress
                        viewModel.saveAddress()
                    }
                )
            }

            if shows(.timeline) {
                hairline(above: .timeline)
                ProjectTimelineRow(project: project)
            }

            if shows(.description) {
                hairline(above: .description)
                DescriptionRow(
                    project: project,
                    canEdit: viewModel.canEditProject,
                    isEditing: $viewModel.isEditingProjectDetails,
                    editText: $viewModel.editingProjectDetailsText,
                    onSave: { viewModel.saveDescription() }
                )
            }

            if shows(.team) {
                hairline(above: .team)
                TeamRow(
                    teamMembers: resolvedProjectTeam,
                    onMemberTap: onTeamMemberTap
                )
            }
        }
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    /// The info card's rows, in render order. The order is the reading order:
    /// who it's for, where it is, when it runs, what it is, who's on it.
    private enum InfoRow: Int, CaseIterable {
        case client, address, timeline, description, team
    }

    /// Whether a row renders, for this viewer and this project. Single source
    /// of truth for the row and for the hairline above it.
    private func shows(_ row: InfoRow) -> Bool {
        switch row {
        case .client:
            return access.showsClient
        case .address:
            // Where the job is is never scoped away — anyone who can open the
            // project may need to drive to it.
            return true
        case .timeline:
            return project.hasTasks
        case .description:
            // Nothing written and no way to write it: omit the field rather
            // than print a dead line saying so.
            return !(project.projectDescription ?? "").isEmpty || viewModel.canEditProject
        case .team:
            return access.showsTeam
        }
    }

    /// A hairline sits above a row only when a row already precedes it inside
    /// the card, so the card never opens or closes on a rule and two lines
    /// never meet where a gated row used to be.
    @ViewBuilder
    private func hairline(above row: InfoRow) -> some View {
        if InfoRow.allCases.prefix(row.rawValue).contains(where: { shows($0) }) {
            Rectangle()
                .fill(OPSStyle.Colors.cardBorderSubtle)
                .frame(height: 1)
                .padding(.leading, OPSStyle.Layout.spacing3)
        }
    }
}

// MARK: - Permission-Scoped Section Visibility

/// Decides which Details-tab sections a viewer may see, purely from granular
/// permissions — never a role name. One place answers "what does this viewer
/// see", so the field-crew view (bug 71213e3b — "Jake doesn't even need to see
/// the details tab") and the owner/admin view derive from the same rules and stay
/// testable in isolation.
///
/// Every viewer who can open the project keeps the where/what/when essentials —
/// status, timeline, address + directions, their tasks, reminders, description
/// (governed by projects.view / tasks.view, which put them on the tab at all).
/// What's scoped away by permission:
///   • CLIENT contact → needs `clients.view` (assigned scope — they're on the
///     project). Crew keep it for site coordination; Unassigned lose it.
///   • VINYL ordering → needs `catalog.orders.view` (an office/purchasing
///     concern) on top of the deck feature. Crew can't order and don't need the
///     status, so it's hidden; operators/office keep it.
///   • TEAM roster    → needs `team.view` (management context). Crew lack it.
///   • edit / delete  → governed by `projects.edit` inside the sections.
struct DetailsTabAccess {
    let showsClient: Bool
    let showsVinylOrder: Bool
    let showsTeam: Bool

    init(permissions: PermissionStore) {
        showsClient = permissions.can("clients.view", requiredScope: "assigned")
        showsVinylOrder = permissions.isFeatureEnabled("deck_builder")
            && permissions.can("deck_builder.view", requiredScope: "assigned")
            && permissions.can("catalog.orders.view")
        showsTeam = permissions.can("team.view")
    }
}

// MARK: - Project Timeline Row

/// START——END: the project's span, with task progress drawn between the two
/// dates. The bar sits on the date line rather than beneath the whole block, so
/// its fill reads as ground covered from start to finish — one glance answers
/// "when does this run, and how far in are we".
///
/// The track mirrors the date columns' own type metrics — an unseen label line,
/// then an unseen date line it centres itself inside — instead of carrying a
/// hand-tuned offset, so it stays on the dates at any type size.
private struct ProjectTimelineRow: View {
    let project: Project

    private var activeTasks: [ProjectTask] {
        project.tasks.filter { $0.status != .cancelled }
    }

    private var completedCount: Int {
        activeTasks.filter { $0.status == .completed }.count
    }

    private var totalCount: Int {
        activeTasks.count
    }

    private var progress: Double {
        totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
                dateColumn("START", date: project.computedStartDate, alignment: .leading)

                VStack(spacing: OPSStyle.Layout.spacing1) {
                    rowLabel("START")
                        .hidden()

                    Text("—")
                        .font(OPSStyle.Typography.body)
                        .hidden()
                        .frame(maxWidth: .infinity)
                        .overlay { progressTrack }
                }

                dateColumn("END", date: project.computedEndDate, alignment: .trailing)
            }

            // Only a project with live tasks has a count to report; one whose
            // tasks are all cancelled keeps the empty track and says nothing.
            if totalCount > 0 {
                Text("\(completedCount) of \(totalCount) TASKS COMPLETE")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
    }

    private func dateColumn(_ label: String, date: Date?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: OPSStyle.Layout.spacing1) {
            rowLabel(label)

            if let date {
                Text(DateHelper.simpleDateString(from: date))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            } else {
                Text("—")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(OPSStyle.Colors.fillNeutralDim)

                Capsule()
                    .fill(progress >= 1.0
                          ? OPSStyle.Colors.successStatus
                          : OPSStyle.Colors.primaryAccent)
                    .frame(width: max(0, geo.size.width * CGFloat(progress)))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Status Section

/// Project status row — shows the current status as the app's standard
/// job-status badge and, for users with edit permission, opens the existing
/// `ProjectStatusChangeSheet` picker. Mirrors the Details-tab card pattern
/// (section label outside, `cardBackgroundDark` card with `cardBorder`).
///
/// Bug f3a300f7 — the status picker sheet and its `showingStatusPicker`
/// hook already existed in ProjectDetailsView but nothing on the Details
/// surface ever triggered it. This section is that trigger.
private struct StatusSection: View {
    let status: Status
    let canEdit: Bool
    var onChangeStatus: (() -> Void)? = nil

    // Compact, single-line status field — a labelled value row, not a
    // content-weight glass card. A single enum value doesn't warrant the same
    // card the content-rich sections use; the original full card read oversized
    // and bolted-on at the top of the tab (bug f3a300f7 follow-up).
    private var row: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Inline label — reuses the app's `[ LABEL ]` section-label convention.
            Text("[ STATUS ]")
                .font(OPSStyle.Typography.smallCaption)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Spacer(minLength: 12)

            // Current status — canonical badge at the standard (medium) size.
            StatusBadge.forJobStatus(status, size: .medium)

            // The whole row is tappable; a chevron signals it (no separate label).
            if canEdit {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .contentShape(Rectangle())
    }

    var body: some View {
        VStack(spacing: 0) {
            if canEdit, let onChangeStatus {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onChangeStatus()
                }) {
                    row
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                row
            }

            // Hairline anchors the backgroundless field above the content
            // sections below it.
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing2)
        }
    }
}

// MARK: - Client Row

/// WHO the job is for, and the two ways to reach them. Tap opens the contact;
/// a long press reassigns (with edit permission).
private struct ClientRow: View {
    let project: Project
    let canEdit: Bool
    let onContactTap: () -> Void
    let onCall: () -> Void
    let onEmail: () -> Void
    var onAssignClient: (() -> Void)? = nil

    private var hasClient: Bool { project.client != nil }

    var body: some View {
        if hasClient {
            // Client assigned — tap to view contact, long press to reassign
            assignedRow
        } else if canEdit {
            // No client, user can assign — tap to pick
            emptyRow
                .onTapGesture {
                    if let assign = onAssignClient {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        assign()
                    }
                }
        } else {
            // No client, no permission — static display
            emptyRow
        }
    }

    private var assignedRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Left side — tap to open contact details
            Button(action: onContactTap) {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    if let client = project.client {
                        UserAvatar(client: client, size: 36)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.effectiveClientName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Text("Client")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Contact action buttons — independent tap targets
            HStack(spacing: OPSStyle.Layout.spacing3) {
                let hasPhone = project.effectiveClientPhone != nil && !project.effectiveClientPhone!.isEmpty
                let hasEmail = project.effectiveClientEmail != nil && !project.effectiveClientEmail!.isEmpty

                Button(action: onCall) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(hasPhone ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText.opacity(0.3))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasPhone)
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

                Button(action: onEmail) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(hasEmail ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText.opacity(0.3))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!hasEmail)
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            }

            Button(action: onContactTap) {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(14)
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    if canEdit, let assign = onAssignClient {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        assign()
                    }
                }
        )
    }

    private var emptyRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Circle()
                .fill(OPSStyle.Colors.background)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "building.2")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                )

            Text("NO CLIENT ASSIGNED")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Spacer()

            if canEdit {
                Text("ASSIGN")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .contentShape(Rectangle())
        .padding(14)
    }
}

// MARK: - Vinyl Order Marker

private struct VinylOrderMarkerSection: View {
    let marker: ProjectVinylOrderMarker?
    let canEdit: Bool
    let isUpdating: Bool
    let onToggle: (Bool) -> Void

    private var status: ProjectVinylOrderStatus {
        marker?.status ?? .notOrdered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("VINYL")

            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("ORDER STATUS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(status.displayLabel)
                        .font(OPSStyle.Typography.dataValue)
                        .foregroundColor(status == .ordered ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryText)
                    if let orderedAt = marker?.orderedAt, status == .ordered {
                        Text("ORDERED \(DateHelper.simpleDateString(from: orderedAt).uppercased())")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    onToggle(status != .ordered)
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if isUpdating {
                            ProgressView()
                                .tint(OPSStyle.Colors.primaryText)
                        }
                        Text(status == .ordered ? "CLEAR ORDERED" : "MARK ORDERED")
                            .font(OPSStyle.Typography.buttonLabel)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.surfaceHover)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canEdit || isUpdating)
                .opacity(canEdit ? 1 : 0.45)
            }
            .padding(14)
            .glassSurface()
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }
}

// MARK: - Team Row

/// WHO is on the job. The card's deepest field — a 36pt avatar rail with first
/// names, breathing wider than the rows above it so the card lands on a base
/// instead of trailing off. Scoped away for viewers without `team.view`.
private struct TeamRow: View {
    let teamMembers: [User]
    let onMemberTap: (User) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            rowLabel("TEAM")
                .padding(.horizontal, 14)

            if teamMembers.isEmpty {
                Text("No team members assigned")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, 14)
            } else {
                // The rail scrolls the full width of the card; the 14pt inset
                // rides inside the scroll content, so avatars run to the card
                // edge rather than stopping short of it.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2_5) {
                        ForEach(teamMembers, id: \.id) { member in
                            Button(action: { onMemberTap(member) }) {
                                VStack(spacing: OPSStyle.Layout.spacing1) {
                                    UserAvatar(user: member, size: 36)
                                    Text(member.firstName ?? "")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, OPSStyle.Layout.spacing3_5)
    }
}

// MARK: - Task List Section

struct TaskListSection: View {
    let tasks: [ProjectTask]
    let selectedTask: ProjectTask?
    let project: Project
    let canEdit: Bool
    let canDuplicate: Bool
    /// User lookup keyed by id — used to resolve task team-member avatars from
    /// the authoritative `teamMemberIdsString` CSV. Passed down from
    /// DetailsTabView so the @Query only runs once per project view.
    let userById: [String: User]
    let onTaskTap: (ProjectTask) -> Void
    let onAddTask: () -> Void
    var onSelectTask: ((ProjectTask) -> Void)? = nil
    var onCompleteTask: ((ProjectTask) -> Void)? = nil
    var onReopenTask: ((ProjectTask) -> Void)? = nil
    var onCancelTask: ((ProjectTask) -> Void)? = nil
    var onDuplicateTask: ((ProjectTask) -> Void)? = nil
    var onDeleteTask: ((ProjectTask) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TASKS")

            VStack(spacing: 0) {
                ForEach(tasks, id: \.id) { task in
                    let isSelected = selectedTask?.id == task.id
                    let hasSelection = selectedTask != nil
                    let taskColor = Color(hex: task.taskColor) ?? OPSStyle.Colors.primaryAccent
                    let isInactive = task.status == .completed || task.status == .cancelled

                    Button(action: { onTaskTap(task) }) {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            // Left cluster: task type badge + status badge (always adjacent)
                            TaskBadge(
                                name: task.taskType?.display ?? "Task",
                                color: taskColor,
                                size: .medium,
                                faded: isInactive
                            )

                            if task.status == .completed {
                                StatusBadgePill(
                                    text: "COMPLETE",
                                    color: TaskStatus.completed.color,
                                    size: .medium
                                )
                            } else if task.status == .cancelled {
                                StatusBadgePill(
                                    text: "CANCELLED",
                                    color: TaskStatus.cancelled.color,
                                    size: .medium
                                )
                            } else if task.isReadyToStart {
                                // READY — predecessors all complete, this task can start.
                                TaskReadyBadge()
                            }

                            // Assigned team avatars — resolved from `teamMemberIdsString`
                            // (the authoritative source) via the parent's User lookup.
                            // Reading `task.teamMembers` directly would miss rows whose
                            // relationship hasn't been rewired yet (post-insert, pre-sync).
                            let assignedMembers: [User] = task.getTeamMemberIds().compactMap { userById[$0] }
                            if !assignedMembers.isEmpty {
                                HStack(spacing: -6) {
                                    ForEach(Array(assignedMembers.prefix(3)), id: \.id) { member in
                                        UserAvatar(user: member, size: 22)
                                            .overlay(
                                                Circle()
                                                    .stroke(OPSStyle.Colors.background, lineWidth: 1.5)
                                            )
                                    }
                                    if assignedMembers.count > 3 {
                                        Text("+\(assignedMembers.count - 3)")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            .padding(.leading, OPSStyle.Layout.spacing2)
                                    }
                                }
                                .padding(.leading, OPSStyle.Layout.spacing1)
                            }

                            Spacer()

                            // Schedule date
                            if let startDate = task.startDate {
                                Text(TaskListSection.formatTaskDate(startDate))
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(Calendar.current.isDateInToday(startDate) ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                            }

                            // Right side: SELECTED badge OR chevron — never both
                            if isSelected {
                                StatusBadgePill(
                                    text: "SELECTED",
                                    color: OPSStyle.Colors.tertiaryText,
                                    size: .small
                                )
                            } else {
                                Image(systemName: OPSStyle.Icons.chevronRight)
                                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                        .contentShape(Rectangle())
                        .background(isSelected ? OPSStyle.Colors.surfaceHover : Color.clear)
                        .opacity(isSelected || !hasSelection ? 1.0 : 0.45)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        // Select / Deselect
                        if isSelected {
                            Button(action: { onSelectTask?(task) }) {
                                Label("Deselect", systemImage: "xmark.circle")
                            }
                        } else {
                            Button(action: { onSelectTask?(task) }) {
                                Label("Select Task", systemImage: "checkmark.circle")
                            }
                        }

                        if canDuplicate && task.deletedAt == nil {
                            Button(action: { onDuplicateTask?(task) }) {
                                Label("Duplicate Task", systemImage: OPSStyle.Icons.copy)
                            }
                        }

                        Divider()

                        // Status actions based on current status
                        if task.status == .active {
                            Button(action: { onCompleteTask?(task) }) {
                                Label("Complete", systemImage: "checkmark")
                            }
                            Button(role: .destructive, action: { onCancelTask?(task) }) {
                                Label("Cancel Task", systemImage: "xmark")
                            }
                        } else if task.status == .completed || task.status == .cancelled {
                            Button(action: { onReopenTask?(task) }) {
                                Label("Reopen", systemImage: "arrow.uturn.backward")
                            }
                        }

                        Divider()

                        // Delete (always available for admin)
                        if canEdit {
                            Button(role: .destructive, action: { onDeleteTask?(task) }) {
                                Label("Delete Task", systemImage: "trash")
                            }
                        }
                    }

                    // Divider
                    if task.id != tasks.last?.id {
                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorderSubtle)
                            .frame(height: 1)
                            .padding(.leading, OPSStyle.Layout.spacing3)
                    }
                }

                // Quick Add suggestions rail (bug e3996ac3 — surface
                // company-frequent (taskType + crew) combos as one-tap chips).
                // Rail self-collapses when there are no qualifying
                // suggestions; gated on canEdit via the rail's internals.
                if canEdit {
                    QuickAddSuggestionsRail(project: project, canEdit: canEdit)
                }

                // Add task row (admin only)
                if canEdit {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)
                        .padding(.leading, OPSStyle.Layout.spacing3)

                    Button(action: onAddTask) {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: "plus")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            Text("ADD TASK")
                                .font(OPSStyle.Typography.captionBold)
                            Spacer()
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .glassSurface()
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Date Formatting

    static func formatTaskDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "TODAY"
        }
        if calendar.isDateInTomorrow(date) {
            return "TOMORROW"
        }
        let formatter = DateFormatter()
        // Same year → "Mar 9", different year → "Mar 9, 2025"
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date).uppercased()
    }
}

// MARK: - Description Row

/// WHAT the job is, in the operator's own words. Nothing written and no way to
/// write it means the row does not render at all — see
/// `DetailsTabView.shows(_:)`, which owns that decision for the whole card.
private struct DescriptionRow: View {
    @Bindable var project: Project
    let canEdit: Bool
    @Binding var isEditing: Bool
    @Binding var editText: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            rowLabel("DESCRIPTION")

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                if isEditing {
                    TextEditor(text: $editText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 80)
                        .padding(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )

                    HStack {
                        Button("Cancel") {
                            isEditing = false
                            editText = ""
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        Button("Save") {
                            onSave()
                        }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                } else if let description = project.projectDescription, !description.isEmpty {
                    HStack(alignment: .top) {
                        Text(description)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        if canEdit {
                            Button(action: {
                                editText = description
                                isEditing = true
                            }) {
                                Image(systemName: OPSStyle.Icons.pencil)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                } else if canEdit {
                    Button(action: {
                        editText = ""
                        isEditing = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            Text("ADD DESCRIPTION")
                                .font(OPSStyle.Typography.captionBold)
                            Spacer()
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Address Row

/// WHERE the job is. Tap the address for directions; the pencil opens an inline
/// field whose suggestions expand inside the row.
///
/// The row does not tint the card while editing. The card carries four other
/// fields now, so an accent edge around the whole surface would announce "this
/// card is being edited" when one row is. The focused field and its SAVE /
/// CANCEL pair are the edit signal, and they sit in the row that owns them.
private struct AddressRow: View {
    let address: String?
    let canEdit: Bool
    let onDirections: () -> Void
    var onSaveAddress: ((String) -> Void)? = nil

    @State private var isEditing = false
    @State private var draft = ""
    @StateObject private var completer = InlineAddressCompleter()
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                // Inline edit mode
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "mappin.circle")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                        TextField("Start typing an address...", text: $draft)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .focused($fieldFocused)
                            .onSubmit { saveAndClose() }
                            .onChange(of: draft) { _, newValue in
                                completer.search(newValue)
                            }

                        // Save / Cancel
                        Button(action: saveAndClose) {
                            Text("SAVE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: cancelEdit) {
                            Image(systemName: OPSStyle.Icons.xmark)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(14)

                    // Inline suggestions
                    if !completer.results.isEmpty {
                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorderSubtle)
                            .frame(height: 1)

                        ForEach(completer.results, id: \.self) { result in
                            Button(action: { selectResult(result) }) {
                                HStack(spacing: OPSStyle.Layout.spacing2) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.title)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .lineLimit(1)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, OPSStyle.Layout.spacing2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())

                            if result != completer.results.last {
                                Rectangle()
                                    .fill(OPSStyle.Colors.cardBorderSubtle)
                                    .frame(height: 1)
                                    .padding(.leading, 36)
                            }
                        }
                    }
                }
            } else {
                // Display mode
                HStack {
                    if let address = address, !address.isEmpty {
                        Button(action: onDirections) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Image(systemName: "mappin.circle")
                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                Text(address)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Text("No address set")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()

                    if canEdit {
                        Button(action: startEditing) {
                            Image(systemName: OPSStyle.Icons.pencil)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(14)
            }
        }
        // Scoped to this row: the expansion is the only thing that moves, and
        // the rows above and below it hold still.
        .animation(OPSStyle.Animation.panel, value: isEditing)
    }

    private func startEditing() {
        draft = address ?? ""
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            fieldFocused = true
        }
    }

    private func saveAndClose() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        onSaveAddress?(trimmed)
        completer.clear()
        withAnimation { isEditing = false }
    }

    private func cancelEdit() {
        completer.clear()
        withAnimation { isEditing = false }
    }

    private func selectResult(_ result: MKLocalSearchCompletion) {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: result))
        search.start { response, _ in
            if let placemark = response?.mapItems.first?.placemark {
                let parts = [
                    placemark.subThoroughfare,
                    placemark.thoroughfare,
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.postalCode
                ].compactMap { $0 }
                draft = parts.joined(separator: " ")
            } else {
                draft = [result.title, result.subtitle]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            }
            completer.clear()
        }
    }
}

// MARK: - Inline Address Completer

private class InlineAddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 3 {
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        results = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = Array(completer.results.prefix(4))
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

// MARK: - Photos Section

struct PhotosSection: View {
    @Bindable var project: Project
    let onPhotoTap: (Int) -> Void
    let onAddPhoto: () -> Void

    @EnvironmentObject private var dataController: DataController

    var body: some View {
        let photos = project.getProjectImages()

        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PHOTOS")

            VStack(spacing: 0) {
                if photos.isEmpty {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("No photos yet")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                    }
                    .padding(14)
                } else {
                    // Horizontal scroll of photo thumbnails with per-photo
                    // client-visibility toggle (eye icon). Tapping the eye
                    // adds/removes the URL from clientVisibleImagesString and
                    // syncs the change to project_photos.is_client_visible so
                    // the web client portal reflects the crew's choice.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                                ZStack(alignment: .topTrailing) {
                                    Button(action: { onPhotoTap(index) }) {
                                        PhotoThumbnail(url: url, project: project)
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .overlay(alignment: .topLeading) {
                                        // Bug 189ace29 — sync-fail badge mirrors
                                        // the visibility eye on the opposite
                                        // corner: same 22pt circle, same 4pt
                                        // outside-the-corner offset.
                                        if !project.isImageSynced(url) {
                                            PhotoSyncFailBadge()
                                                .offset(x: -4, y: -4)
                                                .allowsHitTesting(false)
                                        }
                                    }

                                    // Per-photo client-portal visibility toggle.
                                    // Filled eye = visible to client, slashed = hidden.
                                    ClientVisibilityButton(
                                        url: url,
                                        project: project,
                                        dataController: dataController
                                    )
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .padding(14)
                    }

                    // Photo count
                    Text("\(photos.count) PHOTO\(photos.count == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
            .glassSurface()
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }
}

// MARK: - Client Visibility Button

/// Eye icon toggle that marks a single project photo as visible (or
/// hidden) in the client portal. Writes the change to the local model
/// and syncs to project_photos.is_client_visible on Supabase.
///
/// Bug 8ff95cd4 — gated on `projects.edit` (the same permission that
/// guards every other project-level decision in the OPS hierarchy:
/// adding tasks, editing dates, assigning team, etc.). Crew members
/// without edit permission, mention-only viewers, and the customer
/// portal user never see the eye icon at all. The toggle path also
/// re-checks the permission as defense-in-depth so a stale UI cannot
/// fire a write the role isn't entitled to.
private struct ClientVisibilityButton: View {
    let url: String
    let project: Project
    let dataController: DataController

    @State private var isSyncing = false

    private var isVisible: Bool {
        project.isImageClientVisible(url)
    }

    private var canToggle: Bool {
        PermissionStore.shared.can("projects.edit")
    }

    var body: some View {
        if !canToggle {
            EmptyView()
        } else {
            toggleButton
        }
    }

    private var toggleButton: some View {
        Button(action: toggleVisibility) {
            ZStack {
                Circle()
                    .fill(isSyncing
                          ? OPSStyle.Colors.background.opacity(0.85)
                          : (isVisible
                             ? OPSStyle.Colors.primaryAccent.opacity(0.9)
                             : Color.black.opacity(0.55)))
                    .frame(width: 22, height: 22)

                if isSyncing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: isVisible ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
        .accessibilityLabel(isVisible ? "Hide from client portal" : "Show to client portal")
        .disabled(isSyncing)
    }

    private func toggleVisibility() {
        guard !isSyncing else { return }
        // Bug 8ff95cd4 — defense-in-depth permission re-check before
        // dispatching the write. The button is hidden when the role
        // lacks projects.edit, but a stale UI or an accessibility
        // shortcut shouldn't be able to bypass that.
        guard canToggle else { return }
        let newVisible = !isVisible

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Optimistic local write
        project.setImageClientVisible(url, visible: newVisible)
        try? dataController.modelContext?.save()

        // Sync to Supabase best-effort
        isSyncing = true
        Task {
            defer { Task { @MainActor in isSyncing = false } }
            do {
                try await dataController.imageSyncManager?.setPhotoClientVisibility(
                    url: url,
                    isVisible: newVisible,
                    projectId: project.id
                )
            } catch {
                // Revert local optimistic write on failure
                await MainActor.run {
                    project.setImageClientVisible(url, visible: !newVisible)
                    try? dataController.modelContext?.save()
                }
                print("[CLIENT_VISIBILITY] Failed to sync for \(url): \(error)")
            }
        }
    }
}

// MARK: - Section Label Helper

/// Reusable section label: `[ LABEL ]` — Kosugi 12pt caps, tertiaryText
/// Section headers appear OUTSIDE cards per design system
func sectionLabel(_ title: String) -> some View {
    Text("[ \(title) ]")
        .font(OPSStyle.Typography.smallCaption)
        .textCase(.uppercase)
        .tracking(1)
        .foregroundColor(OPSStyle.Colors.tertiaryText)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
}

/// Micro-label for a field inside the consolidated project-info card. That card
/// has no header, so its rows name themselves — this is the in-card label
/// treatment the VINYL card already uses for "ORDER STATUS", not the
/// `[ LABEL ]` header that sits outside a card.
private func rowLabel(_ title: String) -> some View {
    Text(title)
        .font(OPSStyle.Typography.smallCaption)
        .foregroundColor(OPSStyle.Colors.tertiaryText)
}
