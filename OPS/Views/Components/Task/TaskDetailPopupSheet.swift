//
//  TaskDetailPopupSheet.swift
//  OPS
//
//  Task detail sheet shown from project details task list.
//  Dates row tappable to open scheduler. Team row expands inline.
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
    /// Bug 10b66fce — a confirmed task-type change. Same contract as
    /// `onCommitTeam`: fired only on an explicit pick, never on dismiss, and
    /// the parent performs the write off the sheet's critical path.
    var onCommitTaskType: ((TaskType) -> Void)? = nil
    /// Bug 10b66fce — a confirmed description edit. Fired only when the
    /// operator taps SAVE; abandoning the editor or dragging the sheet away
    /// discards the draft and writes nothing.
    var onCommitDescription: ((String) -> Void)? = nil

    @EnvironmentObject private var dataController: DataController

    @State private var showReopenAlert = false
    @State private var showCancelAlert = false
    @State private var showTeamPicker = false
    @State private var showTypePicker = false
    /// Draft description, live only while the editor is open. Seeded from the
    /// task every time the editor opens so an abandoned edit leaves no trace.
    @State private var isEditingDescription = false
    @State private var draftDescription = ""
    /// Draft team selection that lives only inside this sheet — the operator
    /// can tap rows freely without each tap immediately mutating the parent
    /// state. Only committed back to `selectedTeamMemberIds` when DONE is
    /// tapped. Resets from the committed value every time the picker
    /// expands so a discarded picker leaves no trace.
    @State private var draftTeamMemberIds: Set<String> = []

    private var isInactive: Bool {
        task.status == .completed || task.status == .cancelled
    }

    private var teamDraftIsDirty: Bool {
        draftTeamMemberIds != selectedTeamMemberIds
    }

    private var descriptionDraftIsDirty: Bool {
        draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            != (task.taskNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Permission Gates (bug 10b66fce)
    //
    // Before this, only DATES was gated. TEAM reassignment and every status
    // button were wide open, and the task type and description could not be
    // touched at all. Each control now reads the grant that actually governs
    // it, scope-aware on this task's crew.

    /// `tasks.edit` — task type and description.
    private var canEditFields: Bool { task.canEditFields }

    /// `tasks.assign` — which crew is on the job.
    private var canAssignCrew: Bool { task.canAssignCrew }

    /// `tasks.change_status` — complete, reopen, cancel.
    private var canChangeStatus: Bool { task.canChangeStatus }

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
                    // Bug 10b66fce — status changes are gated on
                    // tasks.change_status. Crew without the grant see the job,
                    // not a button that will refuse them.
                    if canChangeStatus {
                        if task.status == .active {
                            completeButton
                        } else if task.status == .completed {
                            reopenButton
                        }
                    }
                    infoCard
                    descriptionCard
                    actionButtons
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
        // Bug 10b66fce — task type is now editable behind tasks.edit. Picking a
        // type fires the parent's commit closure; dismissing the picker without
        // a pick writes nothing.
        .sheet(isPresented: $showTypePicker) {
            TaskTypePickerSheet(
                selectedTaskTypeId: task.taskTypeId.isEmpty ? nil : task.taskTypeId,
                onSelect: { picked in
                    guard picked.id != task.taskTypeId else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCommitTaskType?(picked)
                    ToastCenter.shared.present(Feedback.Task.typeUpdated)
                }
            )
            .environmentObject(dataController)
        }
    }

    // MARK: - Header

    /// Bug 10b66fce — the old header sat two 9pt mono pills alone on a
    /// full-width row above a 22pt title: tiny, floating, and disproportionate.
    ///
    /// The two badges carried different kinds of information and should never
    /// have been peers. Task type is what the job IS — an attribute of the
    /// title — so it became a colored eyebrow directly above it, carrying the
    /// same identity color the calendar draws the job in. Status is a state —
    /// one glanceable token, right-aligned on the title line where the eye
    /// lands after reading the name.
    ///
    /// The eyebrow doubles as the type control (see `typeEyebrow`) rather than
    /// repeating the type as a separate row in the card below: one datum, one
    /// place on screen.
    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            typeEyebrow

            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2_5) {
                Text(task.displayTitle)
                    .font(OPSStyle.Typography.pageTitle)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                    .opacity(task.status == .completed ? 0.5 : 1.0)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: OPSStyle.Layout.spacing2)

                // Never truncates — the job's state is the one thing that must
                // stay readable no matter how long the title runs.
                StatusBadgePill(
                    text: task.status.displayName.uppercased(),
                    color: task.status.color,
                    size: .medium
                )
                .fixedSize()
            }
        }
    }

    /// The task type, rendered as a colored eyebrow. Tappable — with a chevron
    /// and a full 44pt target — only when the operator holds `tasks.edit` for
    /// this task; otherwise it is plain text with no affordance, so the sheet
    /// shows the operator's actual reality rather than a control that refuses.
    private var typeEyebrow: some View {
        let taskColor = Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent
        let tint = taskColor.opacity(task.status == .completed ? 0.5 : 1.0)

        return Group {
            if canEditFields {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showTypePicker = true
                }) {
                    typeEyebrowContent(tint: tint, showsChevron: true)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Task type")
                .accessibilityValue(typeLabel)
                .accessibilityHint("Change the task type")
                .accessibilityIdentifier("taskDetailTypeButton")
            } else {
                typeEyebrowContent(tint: tint, showsChevron: false)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Task type")
                    .accessibilityValue(typeLabel)
                    .accessibilityIdentifier("taskDetailTypeLabel")
            }
        }
    }

    private func typeEyebrowContent(tint: Color, showsChevron: Bool) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            // A 2pt tick, not a boxed pill — the mark reads as the job's
            // identity colour without competing with the title above it.
            RoundedRectangle(cornerRadius: OPSStyle.Layout.Border.standard)
                .fill(tint)
                .frame(
                    width: OPSStyle.Layout.Border.thick,
                    height: OPSStyle.Layout.IconSize.xs
                )

            Text(typeLabel)
                .font(OPSStyle.Typography.smallCaption)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundColor(tint)
                .lineLimit(1)

            if showsChevron {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer(minLength: 0)
        }
    }

    private var typeLabel: String {
        if let display = task.taskType?.display, !display.isEmpty { return display }
        return canEditFields ? "Set type" : "—"
    }

    // MARK: - Complete Button

    private var completeButton: some View {
        Button(action: {
            onComplete(task)
        }) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                Text("MARK COMPLETE")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
            }
            .foregroundColor(OPSStyle.Colors.successStatus)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.successStatus.opacity(0.1))
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.successStatus.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Reopen Button

    private var reopenButton: some View {
        Button(action: {
            showReopenAlert = true
        }) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                Text("REOPEN TASK")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
            }
            .foregroundColor(OPSStyle.Colors.warningStatus)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.warningStatus.opacity(0.1))
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(spacing: 0) {
            datesRow

            divider

            if task.status == .completed, let completionDate = task.completionDate {
                infoRow(
                    icon: "checkmark.circle",
                    label: "COMPLETED",
                    value: DateHelper.simpleDateString(from: completionDate)
                )
                divider
            }

            teamHeader

            if showTeamPicker {
                teamMemberList
            }
        }
        .glassSurface()
    }

    // MARK: - Description Card

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("DESCRIPTION")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            if isEditingDescription {
                descriptionEditor
            } else {
                descriptionReadout
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    /// Read state. Tappable only when the operator holds `tasks.edit` on this
    /// task — otherwise it stays a plain readout with no false affordance.
    private var descriptionReadout: some View {
        let presentation = TaskDetailDescriptionPresentation(notes: task.taskNotes)
        // An editable empty description says what to do; a read-only one shows
        // the design system's empty mark.
        let text = presentation.isEmpty && canEditFields ? "Tap to add notes" : presentation.text

        return Group {
            if canEditFields {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    // Seed from the task on every open so an abandoned edit
                    // can never resurface later.
                    draftDescription = task.taskNotes ?? ""
                    withAnimation(OPSStyle.Animation.panel) { isEditingDescription = true }
                }) {
                    descriptionText(text, isPlaceholder: presentation.isEmpty)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Task description")
                .accessibilityValue(presentation.text)
                .accessibilityHint("Edit the description")
                .accessibilityIdentifier("taskDetailDescriptionArea")
            } else {
                descriptionText(text, isPlaceholder: presentation.isEmpty)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Task description")
                    .accessibilityValue(presentation.text)
                    .accessibilityIdentifier("taskDetailDescriptionArea")
            }
        }
    }

    private func descriptionText(_ text: String, isPlaceholder: Bool) -> some View {
        Text(text)
            .font(OPSStyle.Typography.body)
            .foregroundColor(
                isPlaceholder
                    ? OPSStyle.Colors.tertiaryText
                    : OPSStyle.Colors.primaryText
            )
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    /// Edit state. Explicit commit only — SAVE writes, CANCEL and sheet
    /// dismissal both discard. Nothing is ever written on the dismiss path
    /// (bugs 0aa825fe / 62481022).
    private var descriptionEditor: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            TextEditor(text: $draftDescription)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                // Two input rows tall — enough to see a couple of lines of
                // notes without the editor swallowing the sheet.
                .frame(minHeight: OPSStyle.Layout.inputHeight * 2)
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .accessibilityIdentifier("taskDetailDescriptionEditor")

            commitRow(
                saveTitle: "SAVE",
                isDirty: descriptionDraftIsDirty,
                cancelIdentifier: "taskDetailDescriptionCancelButton",
                saveIdentifier: "taskDetailDescriptionSaveButton",
                onCancel: {
                    withAnimation(OPSStyle.Animation.panel) { isEditingDescription = false }
                },
                onSave: {
                    let committed = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    onCommitDescription?(committed)
                    ToastCenter.shared.present(Feedback.Task.notesUpdated)
                    withAnimation(OPSStyle.Animation.panel) { isEditingDescription = false }
                }
            )
        }
        .transition(.opacity)
    }

    // MARK: - Dates Row (tappable — opens scheduler)

    private var datesRow: some View {
        Button(action: {
            // Scheduling is gated on calendar.edit, scope-aware on this task.
            guard task.canEditSchedule else { return }
            onScheduleTap?(task)
        }) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "calendar")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DATES")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(dateRangeText)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                Spacer()

                // No chevron when the operator cannot reschedule — a row that
                // advertises an action it will refuse is worse than a plain row.
                if task.canEditSchedule {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var dateRangeText: String {
        if let start = task.startDate, let end = task.endDate {
            return "\(DateHelper.simpleDateString(from: start)) → \(DateHelper.simpleDateString(from: end))"
        }
        return "Not scheduled"
    }

    // MARK: - Team Header (tap to expand inline picker)

    private var teamHeader: some View {
        Button(action: {
            // Bug 10b66fce — reassigning crew is gated on tasks.assign, which
            // this row previously ignored entirely.
            guard canAssignCrew else { return }
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
        }) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "person.2")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TEAM")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    if selectedTeamMemberIds.isEmpty {
                        Text("Tap to assign team")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    } else {
                        let selectedMembers = allTeamMembers.filter { selectedTeamMemberIds.contains($0.id) }
                        if selectedMembers.isEmpty {
                            // IDs exist but members not loaded yet — show count
                            Text("\(selectedTeamMemberIds.count) assigned")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        } else {
                            HStack(spacing: -6) {
                                ForEach(selectedMembers.prefix(5), id: \.id) { member in
                                    Circle()
                                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Text(member.initials)
                                                .font(OPSStyle.Typography.miniLabel)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(OPSStyle.Colors.background, lineWidth: 2)
                                        )
                                }
                                if selectedMembers.count > 5 {
                                    Text("+\(selectedMembers.count - 5)")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        .padding(.leading, OPSStyle.Layout.spacing2)
                                }
                            }
                        }
                    }
                }

                Spacer()

                if canAssignCrew {
                    Image(systemName: showTeamPicker ? "chevron.down" : OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Inline Team Member List

    private var teamMemberList: some View {
        VStack(spacing: 0) {
            // Bug 53552d03 — keep the explicit commit controls immediately
            // below the TEAM header. The operator must not have to scroll
            // through the crew roster before DONE is visible.
            teamCommitRow

            ForEach(allTeamMembers, id: \.id) { member in
                let isSelected = draftTeamMemberIds.contains(member.id)

                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if isSelected {
                        draftTeamMemberIds.remove(member.id)
                    } else {
                        draftTeamMemberIds.insert(member.id)
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.tertiaryText)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))

                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(member.initials)
                                    .font(OPSStyle.Typography.microLabel)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.fullName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text(member.role)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.bottom, OPSStyle.Layout.spacing1)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var teamCommitRow: some View {
        commitRow(
            saveTitle: "DONE",
            isDirty: teamDraftIsDirty,
            cancelIdentifier: "taskDetailTeamCancelButton",
            saveIdentifier: "taskDetailTeamDoneButton",
            onCancel: {
                withAnimation(OPSStyle.Animation.panel) { showTeamPicker = false }
            },
            onSave: {
                let committed = draftTeamMemberIds
                // Update the binding so subsequent reads see the new
                // committed value, then collapse the picker. The actual
                // SwiftData write happens via onCommitTeam in the parent —
                // the parent defers it off the dismiss critical path.
                selectedTeamMemberIds = committed
                onCommitTeam?(committed)
                ToastCenter.shared.present(Feedback.Task.teamUpdated)
                withAnimation(OPSStyle.Animation.panel) { showTeamPicker = false }
            }
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing1)
    }

    // MARK: - Shared Commit Row

    /// The explicit-commit control shared by the crew picker and the
    /// description editor. Both inline editors in this sheet commit the same
    /// way and must look identical, so they are literally the same view.
    ///
    /// The contract that matters: SAVE is the ONLY path that writes. CANCEL
    /// and sheet dismissal both discard — no write ever rides the dismiss
    /// animation, which is what tore down ProjectDetails in bugs 0aa825fe /
    /// 62481022.
    private func commitRow(
        saveTitle: String,
        isDirty: Bool,
        cancelIdentifier: String,
        saveIdentifier: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onCancel()
            }) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.chipMinHeight)
                    .background(OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier(cancelIdentifier)

            Button(action: {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSave()
            }) {
                Text(saveTitle)
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(0.5)
                    .foregroundColor(isDirty
                        ? OPSStyle.Colors.invertedText
                        : OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.chipMinHeight)
                    .background(isDirty
                        ? OPSStyle.Colors.primaryAccent
                        : OPSStyle.Colors.surfaceInput)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isDirty)
            .accessibilityIdentifier(saveIdentifier)
        }
    }

    // MARK: - Static Info Row

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(value)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }

    private var divider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.cardBorder)
            .frame(height: 1)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            // Reopening is a status change (tasks.change_status). Without the
            // grant an inactive task simply has no action — SELECT is not an
            // option either, since selecting requires reopening first.
            if isInactive {
                if canChangeStatus {
                    Button(action: {
                        showReopenAlert = true
                    }) {
                        Text("REOPEN TO SELECT")
                            .font(OPSStyle.Typography.captionBold)
                            .tracking(0.5)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(OPSStyle.Colors.warningStatus.opacity(0.1))
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                Button(action: {
                    onSelect(task)
                }) {
                    Text("SELECT THIS TASK")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(0.5)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if task.status == .active && !isProjectCompleted && canChangeStatus {
                Button(action: {
                    showCancelAlert = true
                }) {
                    Text("CANCEL TASK")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OPSStyle.Colors.errorStatus.opacity(0.1))
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.errorStatus.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}
