//
//  TaskDetailPopupSheet.swift
//  OPS
//
//  The task's dossier, opened from the project Details task list. One document
//  card in the same anatomy the project-info card and the lead dossier use
//  (`DetailsTabView.swift` / `LeadDetailsDocument.swift`): a mono label column
//  down the left, the field's own content to its right, `lineSoft` hairlines
//  between adjacent rows. Three surfaces that answer "what is this, when does
//  it run, who is on it" should not be three different objects.
//
//  The sheet reads top to bottom in one order, always: IDENTITY (what this task
//  is and what state it is in) → DETAILS (the document) → ACTIONS (what you can
//  do about it). Actions used to sandwich the content — a status button above
//  the card and two more below it — which put the sheet's least-used control
//  (a view-mode toggle) in its most prominent position and left the reader
//  hunting for the pair of buttons that actually change the task.
//
//  Three specific corrections, all of them observed in a real render:
//
//   • The name printed twice. `ProjectTask.displayTitle` FALLS BACK to
//     `taskType?.display`, so a task with no custom title rendered "RAILING" in
//     the type badge and "RAILING" again as the title. The badge now renders
//     only when a custom title exists — then badge and title carry different
//     facts (the type, and the operator's name for this instance of it). With
//     the badge suppressed the task's colour is still real signal used across
//     the app, so it rides beside the title as a dot rather than being lost.
//
//   • Three full-width CTAs competed, and the steel-blue accent — reserved for
//     the single primary action on a screen — sat on SELECT THIS TASK, a
//     view-mode toggle. There is now one prominent action, the status-
//     appropriate one (MARK COMPLETE / REOPEN TASK) in its semantic earth tone;
//     SELECT drops to the quiet bordered control idiom; CANCEL TASK stays rose
//     and becomes the quietest of the three.
//
//   • The description sat in a second card of its own. It is a field of this
//     task like its dates and its crew, so it is a NOTES row inside the one
//     document card (bug b6adebf43 — the `—` an empty field prints is part of
//     that reveal and is preserved verbatim).
//
//  The old COMPLETED info row is gone with the second card, and deliberately:
//  `ProjectTask.completionDate` IS `endDate` (computed, not stored), so that
//  row could only ever restate the end date already on the DATES line, under a
//  label that would not have cleared the document's 58pt column anyway. The
//  status badge says COMPLETED; the span says when.
//
//  The inline crew picker keeps its contract exactly (bugs 0aa825fe +
//  62481022): the draft is seeded from the committed selection every time the
//  picker opens, and ONLY the DONE button commits — collapsing the picker or
//  dragging the sheet away discards. It expands full width directly beneath the
//  card as its own panel rather than being squeezed into the document's content
//  region beside a label column.
//

import SwiftUI

struct TaskDetailDescriptionPresentation: Equatable {
    let text: String
    let isEmpty: Bool

    init(notes: String?) {
        let normalizedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isEmpty = normalizedNotes.isEmpty
        text = isEmpty ? "—" : normalizedNotes
    }
}

struct TaskDetailPopupSheet: View {
    let task: ProjectTask
    let onSelect: (ProjectTask) -> Void
    let onComplete: (ProjectTask) -> Void
    let onReschedule: (ProjectTask) -> Void
    let onCancel: (ProjectTask) -> Void
    let onScheduleTap: ((ProjectTask) -> Void)?
    @Binding var selectedTeamMemberIds: Set<String>
    let allTeamMembers: [TeamMember]
    var isProjectCompleted: Bool = false
    /// Bug 0aa825fe + 62481022 — fired only when the operator explicitly taps
    /// DONE on the inline team picker. Drag-to-dismiss does NOT call this, so
    /// the parent can keep the save off the sheet-dismiss critical path
    /// (which was tearing down ProjectDetails via the SwiftData notification
    /// cascade triggered mid-animation by updateTaskTeamMembers' multiple
    /// modelContext.save() calls).
    var onCommitTeam: ((Set<String>) -> Void)? = nil

    @State private var showReopenAlert = false
    @State private var showCancelAlert = false
    @State private var showTeamPicker = false
    /// Draft team selection that lives only inside this sheet — the operator
    /// can tap rows freely without each tap immediately mutating the parent
    /// state. Only committed back to `selectedTeamMemberIds` when DONE is
    /// tapped. Resets from the committed value every time the picker
    /// expands so a discarded picker leaves no trace.
    @State private var draftTeamMemberIds: Set<String> = []

    private var isInactive: Bool {
        task.status == .completed || task.status == .cancelled
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, OPSStyle.Layout.spacing3)

            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                    header

                    documentCard

                    // Full width, its own panel, directly beneath the document.
                    // The roster is a list of 32pt rows; folding it into the
                    // document's ~255pt content region beside a label column
                    // would squeeze the one thing the operator came here to read.
                    if showTeamPicker {
                        TaskTeamPickerPanel(
                            members: allTeamMembers,
                            committed: selectedTeamMemberIds,
                            draft: $draftTeamMemberIds,
                            onCancel: cancelTeamEdit,
                            onCommit: commitTeam
                        )
                    }

                    actionZone
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background)
        .environment(\.colorScheme, .dark)
        .opsSheet(detents: [.medium, .large])
        .alert("Reopen Task?", isPresented: $showReopenAlert) {
            Button("Reopen", role: .destructive) {
                onComplete(task)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to reopen this task? It will be set back to active status.")
        }
        .alert("Cancel Task?", isPresented: $showCancelAlert) {
            Button("Confirm", role: .destructive) {
                onCancel(task)
            }
            Button("Leave Open", role: .cancel) {}
        } message: {
            Text("This task will be marked as cancelled.")
        }
    }

    // MARK: - Identity

    private var taskColor: Color {
        Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent
    }

    /// The operator's own name for this task, or nil.
    ///
    /// This is `ProjectTask.displayTitle`'s predicate EXACTLY — not a trimmed
    /// or otherwise "improved" version of it. The badge is suppressed on the
    /// strength of this answer while the title is rendered from `displayTitle`,
    /// so the two must agree in every case; a stricter test here would suppress
    /// the badge for a whitespace-only custom title and leave the sheet with no
    /// legible name at all.
    private var customTitle: String? {
        guard let customTitle = task.customTitle, !customTitle.isEmpty else { return nil }
        return customTitle
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // Type badge ONLY when the title is the operator's own words.
                // Otherwise `displayTitle` IS the type name and the badge would
                // print it a second time.
                if customTitle != nil {
                    TaskBadge(
                        name: task.taskType?.display ?? "Task",
                        color: taskColor,
                        size: .medium,
                        faded: task.status == .completed
                    )
                }

                StatusBadgePill(
                    text: task.status.displayName.uppercased(),
                    color: task.status.color,
                    size: .medium
                )

                Spacer(minLength: 0)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                // The task's colour is load-bearing everywhere else in the app
                // (calendar, job board, task list). When the badge that usually
                // carries it is suppressed, it rides here instead of vanishing.
                if customTitle == nil {
                    Circle()
                        .fill(taskColor)
                        .frame(
                            width: OPSStyle.Layout.Indicator.dotMD,
                            height: OPSStyle.Layout.Indicator.dotMD
                        )
                        .accessibilityHidden(true)
                }

                Text(task.displayTitle)
                    .font(OPSStyle.Typography.pageTitle)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
            }
            .opacity(task.status == .completed ? 0.5 : 1.0)
        }
    }

    // MARK: - Document card

    /// The document's rows, in render order. The order is the reading order —
    /// when it runs, who is on it, what it says — and it is the same order on
    /// every task, for every viewer, always.
    private enum DocField: Int, CaseIterable {
        case dates, team, notes
    }

    /// Whether a row renders. One answer feeds both the row and the hairline
    /// above it, so the card can never open on a rule, close on one, or draw
    /// two where a row used to be.
    ///
    /// Every field here is unconditional: a reader who can open this sheet is
    /// entitled to all three. Emptiness never removes a row — an empty field
    /// prints its own blank (or its invitation) in place, so the card's shape
    /// never shifts under the reader between one task and the next.
    private func shows(_ field: DocField) -> Bool {
        switch field {
        case .dates, .team, .notes:
            return true
        }
    }

    @ViewBuilder
    private func hairline(above field: DocField) -> some View {
        if DocField.allCases.prefix(field.rawValue).contains(where: { shows($0) }) {
            Rectangle()
                .fill(OPSStyle.Colors.lineSoft)
                .frame(height: 1)
                .padding(.leading, 14)
        }
    }

    private var documentCard: some View {
        VStack(spacing: 0) {
            if shows(.dates) {
                hairline(above: .dates)
                datesRow
            }
            if shows(.team) {
                hairline(above: .team)
                teamRow
            }
            if shows(.notes) {
                hairline(above: .notes)
                notesRow
            }
        }
        .commandCard()
    }

    // MARK: - DATES

    private var hasDates: Bool {
        task.startDate != nil || task.endDate != nil
    }

    /// Whether this row can actually take the operator somewhere. Scheduling is
    /// gated on `calendar.edit`, scope-aware on this task's assignees — a crew
    /// member who cannot move the task reads the dates and is offered nothing
    /// that would not work.
    private var canSchedule: Bool {
        onScheduleTap != nil && task.canEditSchedule
    }

    private var dateSpan: String {
        "\(stamp(task.startDate)) → \(stamp(task.endDate))"
    }

    /// `Jul. 20`, or the document's blank when the date does not exist.
    private func stamp(_ date: Date?) -> String {
        guard let date else { return "—" }
        return DateHelper.simpleDateString(from: date)
    }

    private var datesRow: some View {
        DocRow(label: "DATES") {
            VStack(alignment: .leading, spacing: 6) {
                if hasDates {
                    if canSchedule {
                        Button(action: openScheduler) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Text(dateSpan)
                                    .font(TaskDoc.valueFont)
                                    .foregroundColor(OPSStyle.Colors.text)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                                Image(systemName: OPSStyle.Icons.chevronRight)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(OPSStyle.Colors.text3)
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: OPSStyle.Layout.touchTargetMin,
                                alignment: .leading
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("Dates \(dateSpan)")
                        .accessibilityHint("Opens the scheduler")
                    } else {
                        Text(dateSpan)
                            .font(TaskDoc.valueFont)
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else if canSchedule {
                    TaskDocChip(title: "SET DATES", action: openScheduler)
                        .accessibilityLabel("Set the dates for this task")
                } else {
                    TaskDoc.blank
                }
            }
        }
    }

    private func openScheduler() {
        // Defense in depth — the row only offers this when `canSchedule`, but
        // the gate lives with the action too so a stale render cannot fire it.
        guard task.canEditSchedule else { return }
        onScheduleTap?(task)
    }

    // MARK: - TEAM

    private var assignedMembers: [TeamMember] {
        allTeamMembers.filter { selectedTeamMemberIds.contains($0.id) }
    }

    /// There is nobody to assign from an empty roster, so an empty roster gets
    /// the blank rather than an invitation that opens onto nothing.
    private var canAssignTeam: Bool {
        !allTeamMembers.isEmpty
    }

    private var teamRow: some View {
        DocRow(label: "TEAM") {
            if selectedTeamMemberIds.isEmpty {
                if canAssignTeam {
                    TaskDocChip(title: "ASSIGN TEAM", action: toggleTeamPicker)
                        .accessibilityLabel("Assign team to this task")
                } else {
                    TaskDoc.blank
                }
            } else {
                Button(action: toggleTeamPicker) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if assignedMembers.isEmpty {
                            // Ids are on the task but the User rows have not
                            // hydrated yet. State the count rather than drawing
                            // an empty rail that reads as "nobody".
                            Text("\(selectedTeamMemberIds.count) ASSIGNED")
                                .font(TaskDoc.metaFont)
                                .tracking(0.9)
                                .monospacedDigit()
                                .foregroundColor(OPSStyle.Colors.text2)
                        } else {
                            avatarRail
                        }

                        Spacer(minLength: 0)

                        Image(systemName: showTeamPicker
                              ? OPSStyle.Icons.chevronDown
                              : OPSStyle.Icons.chevronRight)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(OPSStyle.Colors.text3)
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: OPSStyle.Layout.touchTargetMin,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Team, \(selectedTeamMemberIds.count) assigned")
                .accessibilityHint(showTeamPicker ? "Closes the crew picker" : "Opens the crew picker")
            }
        }
    }

    private var avatarRail: some View {
        HStack(spacing: -6) {
            ForEach(assignedMembers.prefix(5), id: \.id) { member in
                Circle()
                    .fill(OPSStyle.Colors.surfaceHover)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(member.initials)
                            .font(OPSStyle.Typography.miniLabel)
                            .foregroundColor(OPSStyle.Colors.text)
                    )
                    // Punched out of the card's own fill so overlapping avatars
                    // stay legible as separate people.
                    .overlay(
                        Circle()
                            .stroke(OPSStyle.Colors.surfaceRaised, lineWidth: OPSStyle.Layout.Border.thick)
                    )
            }
            if assignedMembers.count > 5 {
                Text("+\(assignedMembers.count - 5)")
                    .font(TaskDoc.metaFont)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.text3)
                    .padding(.leading, OPSStyle.Layout.spacing2)
            }
        }
    }

    private func toggleTeamPicker() {
        withAnimation(OPSStyle.Animation.panel) {
            if showTeamPicker {
                // Collapsing without DONE = discard. Draft is reset on
                // the next open via the `if !showTeamPicker` branch.
                showTeamPicker = false
            } else {
                // Opening — seed the draft from the committed selection
                // so the picker shows what's actually on the task, not
                // a stale draft from an earlier abandoned session.
                draftTeamMemberIds = selectedTeamMemberIds
                showTeamPicker = true
            }
        }
    }

    private func cancelTeamEdit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(OPSStyle.Animation.panel) {
            showTeamPicker = false
        }
    }

    /// The ONLY path that writes the crew back. Update the binding so
    /// subsequent reads see the new committed value, then collapse. The actual
    /// SwiftData write happens via `onCommitTeam` in the parent — the parent
    /// defers it off the dismiss critical path.
    private func commitTeam(_ committed: Set<String>) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        selectedTeamMemberIds = committed
        onCommitTeam?(committed)
        ToastCenter.shared.present(Feedback.Task.teamUpdated)
        withAnimation(OPSStyle.Animation.panel) {
            showTeamPicker = false
        }
    }

    // MARK: - NOTES

    /// Read-only here. The task's notes are authored in the task form; this
    /// sheet reports them (bug b6adebf43 — an empty field prints the document's
    /// `—` so the reader learns the field exists and is blank).
    private var notesRow: some View {
        let presentation = TaskDetailDescriptionPresentation(notes: task.taskNotes)

        return DocRow(label: "NOTES") {
            Text(presentation.text)
                .font(TaskDoc.valueFont)
                .foregroundColor(
                    presentation.isEmpty
                        ? OPSStyle.Colors.textMute
                        : OPSStyle.Colors.text
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Task description")
        .accessibilityValue(presentation.text)
        .accessibilityIdentifier("taskDetailDescriptionArea")
    }

    // MARK: - Actions

    /// One zone, one prominence ladder: the status-appropriate primary in its
    /// semantic earth tone at the bottom-CTA height, then the quiet bordered
    /// view-mode toggle, then the destructive action as the quietest thing on
    /// the sheet. The steel-blue accent appears nowhere — this sheet's primary
    /// action carries meaning (complete / reopen) and its tone says so.
    private var actionZone: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            if task.status == .active {
                primaryAction(
                    title: "MARK COMPLETE",
                    icon: "checkmark.circle.fill",
                    tint: OPSStyle.Colors.oliveTextM,
                    fill: OPSStyle.Colors.oliveFillM,
                    border: OPSStyle.Colors.oliveLineM,
                    action: { onComplete(task) }
                )
            } else {
                // Completed AND cancelled both come back the same way, through
                // the same confirmation. A separate REOPEN TO SELECT at the
                // bottom of the sheet was the same action wearing a second name.
                primaryAction(
                    title: "REOPEN TASK",
                    icon: "arrow.uturn.backward.circle.fill",
                    tint: OPSStyle.Colors.tanTextM,
                    fill: OPSStyle.Colors.tanFillM,
                    border: OPSStyle.Colors.tanLineM,
                    action: { showReopenAlert = true }
                )
            }

            // Selecting is how the operator focuses the project view on this
            // task — only meaningful while the task is live.
            if !isInactive {
                Button(action: { onSelect(task) }) {
                    Text("SELECT THIS TASK")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.text)
                        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .fill(OPSStyle.Colors.surfaceHover)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }

            if task.status == .active && !isProjectCompleted {
                Button(action: { showCancelAlert = true }) {
                    Text("CANCEL TASK")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.roseTextM)
                        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func primaryAction(
        title: String,
        icon: String,
        tint: Color,
        fill: Color,
        border: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                Text(title)
                    .font(OPSStyle.Typography.buttonLabel)
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.bottomCTAHeight)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Inline crew picker

/// The task's crew, edited in place. Expands full width beneath the document
/// card as its own panel.
///
/// The commit contract is the whole point of this component and is not
/// negotiable (bugs 0aa825fe + 62481022 + 53552d03):
///   • every tap edits a DRAFT the parent seeds on open — never the task;
///   • ONLY `onCommit` writes, and only the DONE button calls it. CANCEL, a
///     collapse, and a drag-dismiss of the whole sheet all discard;
///   • CANCEL / DONE sit at the TOP of the panel, so the operator never scrolls
///     past the roster to find the way out.
struct TaskTeamPickerPanel: View {
    let members: [TeamMember]
    /// What is currently on the task — the draft is measured against this to
    /// decide whether DONE has anything to commit.
    let committed: Set<String>
    @Binding var draft: Set<String>
    let onCancel: () -> Void
    let onCommit: (Set<String>) -> Void

    private var isDirty: Bool {
        draft != committed
    }

    var body: some View {
        VStack(spacing: 0) {
            commitRow

            ForEach(members, id: \.id) { member in
                hairline
                memberRow(member)
            }
        }
        .commandCard()
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var hairline: some View {
        Rectangle()
            .fill(OPSStyle.Colors.lineSoft)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    private var commitRow: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .fill(OPSStyle.Colors.surfaceInput)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("taskDetailTeamCancelButton")

            Button(action: { onCommit(draft) }) {
                Text("DONE")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(isDirty
                        ? OPSStyle.Colors.invertedText
                        : OPSStyle.Colors.text3)
                    .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .fill(isDirty
                                  ? OPSStyle.Colors.primaryAccent
                                  : OPSStyle.Colors.surfaceInput)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isDirty)
            .accessibilityIdentifier("taskDetailTeamDoneButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }

    private func memberRow(_ member: TeamMember) -> some View {
        let isSelected = draft.contains(member.id)

        return Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected {
                draft.remove(member.id)
            } else {
                draft.insert(member.id)
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))

                Circle()
                    .fill(OPSStyle.Colors.surfaceHover)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(member.initials)
                            .font(OPSStyle.Typography.microLabel)
                            .foregroundColor(OPSStyle.Colors.text)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(member.fullName)
                        .font(TaskDoc.valueFont)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(member.role)
                        .font(TaskDoc.metaFont)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(member.fullName)
        // `Button` already publishes `.isButton`; only the selection state is
        // ours to add.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Task document kit

/// This document's shared type and blanks, in one place so its three fields
/// cannot drift apart. The values are the lead dossier's and the project-info
/// card's own (`LeadDetailsDocument.swift` / `DetailsTabView.swift`) — this card
/// is deliberately the same document, and matching that reference exactly is
/// the point. `DocRow`'s default 58pt label column is kept: DATES, TEAM and
/// NOTES all clear it with room to spare.
private enum TaskDoc {
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
}

/// The document's chip — the one shape this card uses for an action that sits
/// inside an empty field (SET DATES, ASSIGN TEAM). Styled exactly as the lead
/// dossier's ADD TO CLIENT / MATCH PROJECT chips and the project-info card's
/// ASSIGN CLIENT / ADD ADDRESS chips, so an operator who has learned one
/// document's way in has learned all three.
private struct TaskDocChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 5) {
                Image(systemName: OPSStyle.Icons.plus)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(TaskDoc.metaFont)
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
