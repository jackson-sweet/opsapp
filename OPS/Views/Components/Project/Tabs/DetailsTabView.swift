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

/// Stable reading order for the project's one DETAILS document. Status is the
/// first fact about the job, not a separate oversized section above it.
enum ProjectInfoRow: Int, CaseIterable {
    case status, client, lead, address, timeline, description, team

    var label: String {
        switch self {
        case .status: return "STATUS"
        case .client: return "CLIENT"
        case .lead: return "LEAD"
        case .address: return "ADDRESS"
        case .timeline: return "TIMELINE"
        case .description: return "NOTES"
        case .team: return "TEAM"
        }
    }
}

enum ProjectStatusRowPolicy {
    static func canChangeStatus(canEdit: Bool, hasAction: Bool) -> Bool {
        canEdit && hasAction
    }
}

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
    /// PROJECT-side lead provenance (bug a3c4e216). Opens the linked lead, or
    /// the picker when this project has matchable won leads at its address.
    var leadRowPresentation: ProjectLeadRow.Presentation = .hidden
    var onOpenLead: (() -> Void)? = nil
    var onMatchLead: (() -> Void)? = nil

    /// All Users in the store. Used to resolve team member avatars from the
    /// authoritative `teamMemberIdsString` CSV on both Project and ProjectTask.
    /// We render from this lookup rather than the `teamMembers: [User]`
    /// SwiftData relationship because that relationship can be empty even
    /// when the id-string has values (hydration lag: user-objects may sync
    /// in a separate batch, or `linkAllRelationships` may not have run yet
    /// for a freshly-inserted local row).
    @Query private var allUsers: [User]
    @Query private var vinylOrderMarkers: [ProjectVinylOrderMarker]
    /// Deck designs for THIS project only. The vinyl card shows what was
    /// actually ordered, and the frozen record lives in the design's drawing
    /// JSON — a project-scoped query keeps this perf-sensitive tab off a
    /// whole-table fetch while staying live as the order is marked or edited.
    @Query private var deckDesigns: [DeckDesign]

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

    /// The frozen ordered record for this project's display-candidate design,
    /// or nil when the job has no deck drawing (marker-only order).
    private var vinylOrderSnapshot: DeckMaterialsSnapshot? {
        DeckDesign.displayCandidate(in: deckDesigns, forProjectId: project.id)?
            .drawingData.orderedMaterials
    }

    /// Permission-scoped section visibility for this viewer (never role-based).
    private var access: DetailsTabAccess {
        DetailsTabAccess(permissions: .shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            // PROJECT INFO — status, client, lead, address, timeline,
            // description, team in ONE document card of hairline-separated
            // rows. One header, one mono label column, one row per field.
            projectInfoCard

            // VINYL ORDER MARKER — order tracking is a purchasing/office concern,
            // not an on-site one; hidden from field crew. See DetailsTabAccess.
            if access.showsVinylOrder {
                VinylOrderMarkerSection(
                    marker: vinylOrderMarker,
                    snapshot: vinylOrderSnapshot,
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
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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

    /// The project's identity block — its status, who it's for, where it came
    /// from, where it is, when it runs, what it is, who's on it — as ONE
    /// document card, in the same anatomy the lead dossier uses
    /// (LeadDetailsDocument.swift): a `DETAILS` header above a solid raised
    /// card, a mono label column down the left, the field's own content to its
    /// right, hairlines between rows.
    ///
    /// The row ORDER NEVER CHANGES and blanks render in place. ADDRESS,
    /// TIMELINE and DESCRIPTION always render: a field that vanishes when it is
    /// empty teaches the reader nothing about where to look for it, and every
    /// vanish reshuffles the rows below it. CLIENT and TEAM still leave the card
    /// entirely when the viewer lacks the permission that governs their data —
    /// the fixed-order rule governs state, not entitlement.
    ///
    /// Every empty row answers the same way and in the same place: an action
    /// chip at the START of the content region when the viewer can fill the
    /// field, `—` at that same x when they cannot. One column, one answer — so
    /// the way in is always where the reader last found it.
    ///
    /// LEAD is the one field that leaves on emptiness, and deliberately (bug
    /// a3c4e216). The other five describe every project that exists; provenance
    /// describes a minority of them, and the server only accepts a link whose
    /// target shares the lead's address, so most projects have no lead and no
    /// candidate to offer. Holding a permanent `LEAD —` line on the app's
    /// most-visited card to advertise a once-ever action nobody can take is a
    /// worse lie than absence. See `ProjectLeadRow.Presentation`.
    private var projectInfoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionHeader(label: "DETAILS")
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                if shows(.status) {
                    hairline(above: .status)
                    ProjectStatusRow(
                        status: project.status,
                        canEdit: viewModel.canEditProject,
                        onChangeStatus: onChangeStatus
                    )
                }

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

                if shows(.lead) {
                    hairline(above: .lead)
                    ProjectLeadSection(
                        presentation: leadRowPresentation,
                        onOpenLead: { onOpenLead?() },
                        onMatchLead: { onMatchLead?() }
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
            .commandCard()
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    /// Whether a row renders, for this viewer. Single source of truth for the
    /// row and for the hairline above it.
    ///
    /// Entitlement removes a row. Emptiness does not — an empty field renders
    /// its own blank (or its invitation) in place, so the card's shape is a
    /// property of the viewer, not of how much has been filled in yet. LEAD is
    /// the documented exception; see `projectInfoCard`.
    private func shows(_ row: ProjectInfoRow) -> Bool {
        switch row {
        case .status:
            return true
        case .client:
            return access.showsClient
        case .lead:
            // No lead and nothing matchable: the row is absent entirely rather
            // than an em dash or a dead affordance (bug a3c4e216).
            return leadRowPresentation != .hidden
        case .address, .timeline, .description:
            // Where the job is, when it runs, and what it is are never scoped
            // away — anyone who can open the project needs all three.
            return true
        case .team:
            return access.showsTeam
        }
    }

    /// A hairline sits above a row only when a row already precedes it inside
    /// the card, so the card never opens or closes on a rule and two lines
    /// never meet where a gated row used to be.
    @ViewBuilder
    private func hairline(above row: ProjectInfoRow) -> some View {
        if ProjectInfoRow.allCases.prefix(row.rawValue).contains(where: { shows($0) }) {
            Rectangle()
                .fill(OPSStyle.Colors.lineSoft)
                .frame(height: 1)
                .padding(.leading, 14)
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

/// WHEN the job runs — a document row like every other: the span on the value
/// line, progress on the meta line beneath it.
///
/// The capsule spans the whole content region rather than sitting between the
/// two dates, because in this anatomy the content region IS the field: the
/// track's fill reads as ground covered across the job, and the count under it
/// says exactly how much. A project with no dates prints the same `—` every
/// other empty field prints, in the same place.
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

    private var hasSpan: Bool {
        project.computedStartDate != nil || project.computedEndDate != nil
    }

    var body: some View {
        DocRow(label: "TIMELINE", labelWidth: ProjectInfoDoc.labelColumnWidth) {
            VStack(alignment: .leading, spacing: 6) {
                if hasSpan {
                    Text("\(stamp(project.computedStartDate)) → \(stamp(project.computedEndDate))")
                        .font(ProjectInfoDoc.valueFont)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    ProjectInfoDoc.blank
                }

                // Only a project with live tasks has progress to report; one
                // whose tasks are all cancelled says nothing rather than
                // drawing an empty track that means nothing.
                if totalCount > 0 {
                    progressTrack

                    Text("\(completedCount) of \(totalCount) tasks complete")
                        .font(ProjectInfoDoc.metaFont)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.text3)
                }
            }
        }
    }

    /// `Jul. 20`, or the document's blank when the date does not exist.
    private func stamp(_ date: Date?) -> String {
        guard let date else { return "—" }
        return DateHelper.simpleDateString(from: date)
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

// MARK: - Status Row

/// The first row in DETAILS. It keeps the canonical status badge and existing
/// picker action while taking no more space than the other document facts.
private struct ProjectStatusRow: View {
    let status: Status
    let canEdit: Bool
    var onChangeStatus: (() -> Void)? = nil

    private var canChangeStatus: Bool {
        ProjectStatusRowPolicy.canChangeStatus(
            canEdit: canEdit,
            hasAction: onChangeStatus != nil
        )
    }

    private var value: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            StatusBadge.forJobStatus(status, size: .small)
            Spacer(minLength: .zero)

            if canChangeStatus {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var row: some View {
        DocRow(label: ProjectInfoRow.status.label, labelWidth: ProjectInfoDoc.labelColumnWidth) {
            value
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    var body: some View {
        if canChangeStatus, let onChangeStatus {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onChangeStatus()
            }) {
                row
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Status")
            .accessibilityValue(status.displayName)
            .accessibilityHint("Change status")
        } else {
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Status")
                .accessibilityValue(status.displayName)
        }
    }
}

// MARK: - Client Row

/// WHO the job is for, and the two ways to reach them. The name is the value
/// line — tap it (or its chevron) to open the contact, long press to hand the
/// job to a different client. CALL and EMAIL sit on the meta line beneath as
/// chips, and only the ones that exist are drawn: this row's content region is
/// narrower than the old full-width row, and two trailing icon buttons crowded
/// the name they were meant to serve. A channel the client does not have is not
/// a dimmed button — it is simply absent.
private struct ClientRow: View {
    let project: Project
    let canEdit: Bool
    let onContactTap: () -> Void
    let onCall: () -> Void
    let onEmail: () -> Void
    var onAssignClient: (() -> Void)? = nil

    private var hasClient: Bool { project.client != nil }
    private var hasPhone: Bool { !(project.effectiveClientPhone ?? "").isEmpty }
    private var hasEmail: Bool { !(project.effectiveClientEmail ?? "").isEmpty }

    var body: some View {
        DocRow(label: "CLIENT", labelWidth: ProjectInfoDoc.labelColumnWidth) {
            if hasClient {
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: onContactTap) {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Text(project.effectiveClientName)
                                .font(ProjectInfoDoc.valueFont)
                                .foregroundColor(OPSStyle.Colors.text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            Image(systemName: OPSStyle.Icons.chevronRight)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(OPSStyle.Colors.text3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("Open client \(project.effectiveClientName)")

                    if hasPhone || hasEmail {
                        HStack(spacing: 6) {
                            if hasPhone {
                                InfoActionChip(
                                    icon: OPSStyle.Icons.phoneFill,
                                    title: "CALL",
                                    action: onCall
                                )
                                .accessibilityLabel("Call client")
                            }
                            if hasEmail {
                                InfoActionChip(
                                    icon: OPSStyle.Icons.envelopeFill,
                                    title: "EMAIL",
                                    action: onEmail
                                )
                                .accessibilityLabel("Email client")
                            }
                        }
                    }
                }
            } else {
                ProjectInfoDoc.empty(
                    canAct: canEdit && onAssignClient != nil,
                    chip: "ASSIGN CLIENT",
                    accessibilityLabel: "Assign a client to this project"
                ) {
                    if let assign = onAssignClient {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        assign()
                    }
                }
            }
        }
        .rowEditAction(
            isEnabled: InfoRowEdit.offersLongPressEdit(canEdit: canEdit, hasValue: hasClient),
            title: "Change client"
        ) {
            if let assign = onAssignClient {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                assign()
            }
        }
    }
}

// MARK: - Vinyl Order Marker

/// The project's vinyl procurement state, in the two shapes it actually takes.
///
/// UNHANDLED, the card is an ENTRY POINT: one status line and one action. There
/// is nothing to read yet, so nothing pretends there is.
///
/// HANDLED, the card is a RECORD: what was obtained, where it came from, when,
/// and against which PO — because that is the question an operator opens this
/// project to answer ("did we get the vinyl, and how much?"), not "how do I undo
/// this?". The destructive verb that used to sit in prime scan space moves
/// behind an overflow control: rows are for scanning, actions live behind them.
///
/// The record is read from the FROZEN SNAPSHOT on the deck design, which is
/// where MARK ORDERED writes the operator's confirmed quantities. A job with no
/// deck drawing has no snapshot and honestly shows only the disposition and the
/// date — it never invents a quantity it does not have.
private struct VinylOrderMarkerSection: View {
    let marker: ProjectVinylOrderMarker?
    let snapshot: DeckMaterialsSnapshot?
    let canEdit: Bool
    let isUpdating: Bool
    let onToggle: (Bool) -> Void

    private var status: ProjectVinylOrderStatus {
        marker?.status ?? .notOrdered
    }

    private var isHandled: Bool { status == .ordered }

    /// Where the material came from. The frozen snapshot is authoritative; a
    /// marker-only job predates the distinction and was, in fact, an order.
    private var disposition: VinylOrderDisposition {
        snapshot?.disposition ?? .supplier
    }

    private var orderedAt: Date? { marker?.orderedAt ?? snapshot?.orderedAt }

    private var color: String? {
        let raw = (snapshot?.vinylColor ?? marker?.vinylColor ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw.uppercased()
    }

    private var po: String? {
        let raw = (snapshot?.po ?? marker?.vinylPO ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw.uppercased()
    }

    private var vinylLines: [String] { snapshot?.orderedVinylLines ?? [] }
    private var consumables: [VinylSharedConsumable] { snapshot?.orderedConsumables ?? [] }
    private var hasRecord: Bool { !vinylLines.isEmpty || !consumables.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionHeader(label: "VINYL")
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                statusRow
                if isHandled && hasRecord {
                    hairline
                    recordBody
                }
            }
            .padding(14)
            .commandCard()
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    // MARK: Status row

    private var statusRow: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("ORDER STATUS")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(isHandled ? disposition.statusLabel : status.displayLabel)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(isHandled ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryText)
                if isHandled, let meta = metaLine {
                    Text(meta)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)

            if isHandled {
                overflowMenu
            } else {
                markOrderedButton
            }
        }
    }

    /// `ORDERED 14 JUL · PO 6836 MARK LN` — the two facts that date and identify
    /// the record, on one line so the quantities below own the vertical space.
    private var metaLine: String? {
        var parts: [String] = []
        if let orderedAt {
            parts.append("\(disposition.datePrefix) \(DateHelper.simpleDateString(from: orderedAt).uppercased())")
        }
        if let po { parts.append("PO \(po)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The one action on an unhandled job.
    private var markOrderedButton: some View {
        Button {
            onToggle(true)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if isUpdating {
                    ProgressView()
                        .tint(OPSStyle.Colors.primaryText)
                }
                Text("MARK ORDERED")
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

    /// Undoing a completed order is rare and destructive. It stays reachable and
    /// stops competing with the record for attention. Quantities are corrected
    /// on the Deck tab's MATERIALS card, next to the materials context an edit
    /// needs — a second edit entry point here would be two doors to one room.
    private var overflowMenu: some View {
        Menu {
            Button(role: .destructive) {
                onToggle(false)
            } label: {
                Label("CLEAR ORDERED", systemImage: OPSStyle.Icons.delete)
            }
        } label: {
            Group {
                if isUpdating {
                    ProgressView().tint(OPSStyle.Colors.primaryText)
                } else {
                    Image(systemName: OPSStyle.Icons.ellipsis)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            .contentShape(Rectangle())
        }
        .disabled(!canEdit || isUpdating)
        .opacity(canEdit ? 1 : 0.45)
        .accessibilityLabel("Vinyl order actions")
    }

    // MARK: Record

    private var hairline: some View {
        Rectangle()
            .fill(OPSStyle.Colors.line)
            .frame(height: OPSStyle.Layout.Border.standard)
    }

    private var recordBody: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if let color {
                Text(color)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            if !vinylLines.isEmpty {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    ForEach(Array(vinylLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .monospacedDigit()
                    }
                }
            }

            if !consumables.isEmpty {
                VStack(spacing: 0) {
                    ForEach(consumables) { consumable in
                        consumableRow(consumable)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One purchased consumable. The shared count is the count as bought — never
    /// a per-job fraction — so the sharing partners ride on their own support
    /// line and the value column stays a clean, scannable number.
    private func consumableRow(_ consumable: VinylSharedConsumable) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(consumable.kind.displayLabel)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer(minLength: 0)
                Text(consumable.recordValue)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
            }
            if let shared = consumable.sharedSupportLine {
                Text(shared)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Team Row

/// WHO is on the job — a 36pt avatar rail with first names, riding in the
/// document's content region like every other field's value. The rail makes the
/// row naturally the tallest in the card; it needs no extra breathing room of
/// its own, and taking it would break the uniform row rhythm that makes the
/// label column scannable. Scoped away for viewers without `team.view`.
private struct TeamRow: View {
    let teamMembers: [User]
    let onMemberTap: (User) -> Void

    var body: some View {
        DocRow(label: "TEAM", labelWidth: ProjectInfoDoc.labelColumnWidth) {
            if teamMembers.isEmpty {
                // No add-crew action lives on this surface, so an empty roster
                // states the fact and offers nothing it cannot deliver.
                ProjectInfoDoc.blank
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2_5) {
                        ForEach(teamMembers, id: \.id) { member in
                            Button(action: { onMemberTap(member) }) {
                                VStack(spacing: OPSStyle.Layout.spacing1) {
                                    UserAvatar(user: member, size: 36)
                                    Text(member.firstName ?? "")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.text2)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionHeader(label: "TASKS")
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, 10)

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
                            .fill(OPSStyle.Colors.lineSoft)
                            .frame(height: 1)
                            .padding(.leading, 14)
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
                        .fill(OPSStyle.Colors.lineSoft)
                        .frame(height: 1)
                        .padding(.leading, 14)

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
            .commandCard()
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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

/// WHAT the job is, in the operator's own words. Written text is edited by long
/// press; an empty field carries the document's ADD DESCRIPTION chip, because a
/// long press on nothing is undiscoverable. The row always renders — a viewer
/// who cannot write one still learns that the field exists and is blank, and
/// the rows below it never move because someone typed a sentence.
private struct DescriptionRow: View {
    @Bindable var project: Project
    let canEdit: Bool
    @Binding var isEditing: Bool
    @Binding var editText: String
    let onSave: () -> Void

    private var writtenDescription: String {
        project.projectDescription ?? ""
    }

    var body: some View {
        DocRow(label: "NOTES", labelWidth: ProjectInfoDoc.labelColumnWidth) {
            if isEditing {
                editor
            } else if !writtenDescription.isEmpty {
                Text(writtenDescription)
                    .font(ProjectInfoDoc.valueFont)
                    .foregroundColor(OPSStyle.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProjectInfoDoc.empty(
                    canAct: canEdit,
                    chip: "ADD NOTES",
                    accessibilityLabel: "Add notes"
                ) {
                    editText = ""
                    isEditing = true
                }
            }
        }
        .rowEditAction(
            isEnabled: InfoRowEdit.offersLongPressEdit(
                canEdit: canEdit,
                hasValue: !writtenDescription.isEmpty,
                isEditing: isEditing
            ),
            title: "Edit description"
        ) {
            editText = writtenDescription
            isEditing = true
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            TextEditor(text: $editText)
                .font(ProjectInfoDoc.valueFont)
                .foregroundColor(OPSStyle.Colors.text)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 80)
                .padding(10)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
                )

            HStack {
                Button("Cancel") {
                    isEditing = false
                    editText = ""
                }
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.text2)

                Spacer()

                Button("Save") {
                    onSave()
                }
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
    }
}

// MARK: - Address Row

/// WHERE the job is. Tap the address for directions; long press to open an
/// inline field whose suggestions expand inside the row. Label, value and
/// suggestions all live in the document's own two columns, so the row does not
/// reshape under the reader when it starts being edited — only its content
/// region grows.
///
/// The row does not tint the card while editing. The card carries four other
/// fields, so an accent edge around the whole surface would announce "this card
/// is being edited" when one row is. The focused field and its SAVE / CANCEL
/// pair are the edit signal, and they sit in the row that owns them.
private struct AddressRow: View {
    let address: String?
    let canEdit: Bool
    let onDirections: () -> Void
    var onSaveAddress: ((String) -> Void)? = nil

    @State private var isEditing = false
    @State private var draft = ""
    @StateObject private var completer = InlineAddressCompleter()
    @FocusState private var fieldFocused: Bool

    private var writtenAddress: String {
        address ?? ""
    }

    var body: some View {
        DocRow(label: "ADDRESS", labelWidth: ProjectInfoDoc.labelColumnWidth) {
            if isEditing {
                editor
            } else if !writtenAddress.isEmpty {
                Button(action: onDirections) {
                    Text(writtenAddress)
                        .font(ProjectInfoDoc.valueFont)
                        .foregroundColor(OPSStyle.Colors.text)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(writtenAddress)
                .accessibilityHint("Opens directions")
            } else {
                ProjectInfoDoc.empty(
                    canAct: canEdit,
                    chip: "ADD ADDRESS",
                    accessibilityLabel: "Set the job address"
                ) {
                    startEditing()
                }
            }
        }
        .rowEditAction(
            isEnabled: InfoRowEdit.offersLongPressEdit(
                canEdit: canEdit,
                hasValue: !writtenAddress.isEmpty,
                isEditing: isEditing
            ),
            title: "Edit address"
        ) {
            startEditing()
        }
        // Scoped to this row: the expansion is the only thing that moves, and
        // the rows above and below it hold still.
        .animation(OPSStyle.Animation.panel, value: isEditing)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                TextField("Start typing an address...", text: $draft)
                    .font(ProjectInfoDoc.valueFont)
                    .foregroundColor(OPSStyle.Colors.text)
                    .focused($fieldFocused)
                    .onSubmit { saveAndClose() }
                    .onChange(of: draft) { _, newValue in
                        completer.search(newValue)
                    }

                Button(action: saveAndClose) {
                    Text("SAVE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: cancelEdit) {
                    Image(systemName: OPSStyle.Icons.xmark)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.text3)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Cancel")
            }

            // Suggestions expand inside the content region, under the field
            // that produced them — not across the card, which would break the
            // label column the rest of the document is read by.
            if !completer.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(completer.results, id: \.self) { result in
                        if result != completer.results.first {
                            Rectangle()
                                .fill(OPSStyle.Colors.lineSoft)
                                .frame(height: 1)
                        }

                        Button(action: { selectResult(result) }) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.title)
                                        .font(ProjectInfoDoc.valueFont)
                                        .foregroundColor(OPSStyle.Colors.text)
                                        .lineLimit(1)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.text3)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
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

// MARK: - Project Info Document Kit

/// The project-info document's shared geometry and type, in one place so its
/// fields cannot drift apart. The values are the lead dossier's own
/// (LeadDetailsDocument.swift) — this card is deliberately the same document,
/// and matching that reference exactly is the point.
enum ProjectInfoDoc {
    /// Width of the mono label column — the lead dossier's own 58pt.
    ///
    /// An earlier pass kept the label DESCRIPTION and widened the column to fit
    /// it. UIKit measured that string at 66pt and the widened column passed its
    /// own assertion, but SwiftUI still wrapped the label mid-word in the real
    /// render (DESCRIPTIO / N) — laying out `Text` in a fixed frame does not
    /// reproduce `NSAttributedString.size(withAttributes:)` closely enough to
    /// justify a hairline fit. The field is labelled NOTES instead: it clears
    /// the column with room to spare, and the card now shares the reference
    /// document's column exactly rather than running 10pt wider than it.
    static let labelColumnWidth: CGFloat = 58

    /// Every project-info label, for the width assertion. The card renders
    /// exactly these, in exactly this order. LEAD only renders when the project
    /// has provenance to state, but it shares the column and must fit it.
    static let labels = ProjectInfoRow.allCases.map(\.label)

    /// The document's value line — every row's primary text.
    static let valueFont = Font.custom("Mohave-Medium", size: 14)

    /// The document's meta line — the smaller mono line beneath a value.
    static let metaFont = Font.custom("JetBrainsMono-Medium", size: 9)

    /// Every blank field reads the same way, in the same place: `—` at the
    /// start of the content region.
    static var blank: some View {
        Text("—")
            .font(valueFont)
            .foregroundColor(OPSStyle.Colors.textMute)
    }

    /// An empty field, rendered identically on every row — the invitation when
    /// this viewer can fill it, the blank when they cannot. Both start at the
    /// same x, directly right of the label, because a reader who has learned
    /// where one row's way-in lives has learned where all of them live.
    @ViewBuilder
    static func empty(
        canAct: Bool,
        chip: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        if canAct {
            InfoActionChip(icon: OPSStyle.Icons.plus, title: chip, action: action)
                .accessibilityLabel(accessibilityLabel)
        } else {
            blank
        }
    }
}

/// The document's chip — the one shape this card uses for an action that sits
/// inside a field: ASSIGN CLIENT, ADD ADDRESS, ADD DESCRIPTION, CALL, EMAIL.
/// Styled exactly as the lead dossier's ADD TO CLIENT / MATCH PROJECT chips.
struct InfoActionChip: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(ProjectInfoDoc.metaFont)
                    .tracking(0.9)
                    .textCase(.uppercase)
            }
            .foregroundColor(OPSStyle.Colors.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Long-Press Editing

/// When a project-info row offers long-press editing.
///
/// Two conditions, and both are load-bearing. The viewer must hold
/// `projects.edit` — a read-only viewer gets no menu at all, so the gesture
/// can never surface an action they aren't entitled to take. And the field
/// must already hold a value: an empty field shows an explicit ADD/ASSIGN
/// affordance instead, because a long press on nothing is undiscoverable.
/// A field already in its inline edit mode offers nothing further.
///
/// One place answers this for CLIENT, ADDRESS and DESCRIPTION, so the three
/// rows cannot drift apart and the rule stays assertable on its own.
enum InfoRowEdit {
    static func offersLongPressEdit(canEdit: Bool, hasValue: Bool, isEditing: Bool = false) -> Bool {
        canEdit && hasValue && !isEditing
    }
}

/// Attaches a named long-press edit action to a filled info row.
///
/// `.contextMenu` rather than a bare `LongPressGesture`: it is the iOS-standard
/// long-press affordance, it *names* the action instead of firing a hidden one,
/// and it brings its own preview and haptics. The matching
/// `.accessibilityAction` keeps the same edit path reachable for anyone who
/// cannot perform a long press.
private struct RowEditAction: ViewModifier {
    let isEnabled: Bool
    let title: String
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contextMenu {
                    Button(action: action) {
                        Label(title, systemImage: OPSStyle.Icons.pencil)
                    }
                }
                .accessibilityAction(named: Text(title), action)
        } else {
            content
        }
    }
}

private extension View {
    func rowEditAction(
        isEnabled: Bool,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        modifier(RowEditAction(isEnabled: isEnabled, title: title, action: action))
    }
}
