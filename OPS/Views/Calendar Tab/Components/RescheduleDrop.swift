//
//  RescheduleDrop.swift
//  OPS
//
//  The drop side of drag-and-drop reschedule: the day-cell drop target + live
//  highlight, the commit coordinator (resolve → plan → prompt-or-commit), the drag
//  preview chip, and the live target-date banner. Shared by the month grid
//  (MonthDayCell) and the week strip (WeekDayCell); hosted by ScheduleView.
//
//  Reuses the existing scheduling engine end-to-end — no scheduler is reinvented.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Commit coordinator

@MainActor
enum RescheduleCoordinator {

    /// Resolve a dropped payload to its live model, compute target dates (time-of-day
    /// + span preserved), re-check the permission gate, then either commit the move
    /// or stage the three-way crew/dependency prompt on the session.
    static func handleDrop(_ payload: RescheduleDragPayload, on day: Date,
                           dataController: DataController, session: ScheduleDragSession) {
        let cal = Calendar.current

        switch payload.kind {
        case .task:
            // Defense-in-depth: re-check calendar.edit (scope-aware) before any write.
            // Dates come from the live model, not the (possibly stale) drag payload.
            guard let task = dataController.getTask(id: payload.id), task.canEditSchedule,
                  let oStart = task.startDate, let oEnd = task.endDate else { return }
            let target = targetDates(originalStart: oStart, originalEnd: oEnd, droppedDay: day, calendar: cal)
            // No-op when dropped back on the same start day.
            if cal.isDate(oStart, inSameDayAs: target.start) { return }

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            let plan = dataController.planDropReschedule(for: task, targetStart: target.start, targetEnd: target.end)
            let changes = plan?.cascade.changes ?? []
            let showPreview = UserDefaults.standard.object(forKey: "showCascadePreview") as? Bool ?? true

            if !changes.isEmpty && showPreview {
                session.pendingPrompt = ReschedulePrompt(
                    taskId: task.id,
                    taskName: task.displayTitle,
                    oldStart: task.startDate,
                    newStart: target.start,
                    newEnd: target.end,
                    changes: changes,
                    explanationLines: explanationLines(for: changes,
                                                       pushedCrew: Set(task.getTeamMemberIds()),
                                                       dataController: dataController),
                    primaryLabel: "PUSH IT ALL")
            } else {
                let cascade = !changes.isEmpty   // pref off but changes exist → still cascade
                Task {
                    do {
                        _ = try await dataController.commitDropReschedule(
                            task, targetStart: target.start, targetEnd: target.end, cascade: cascade)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        ToastCenter.shared.present(Feedback.Task.scheduledFor(start: target.start, end: target.end))
                    } catch {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
            }

        case .userEvent:
            guard let event = dataController.getUserEvent(id: payload.id) else { return }
            // Recurring instances keep the explicit tap-to-edit scope picker.
            if event.isRecurringInstance { return }
            // Same gate UserEventSheet uses for edits.
            guard PermissionStore.shared.canEditSchedule(
                assigneeIds: [event.userId] + (event.teamMemberIds ?? [])) else { return }
            let target = targetDates(originalStart: event.startDate, originalEnd: event.endDate, droppedDay: day, calendar: cal)
            if cal.isDate(event.startDate, inSameDayAs: target.start) { return }

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dataController.commitUserEventReschedule(event, targetStart: target.start, targetEnd: target.end)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ToastCenter.shared.present(Feedback.Task.scheduledFor(start: target.start, end: target.end))
        }
    }

    /// Build plain-language "why" lines from the actual changes — names the crew on
    /// each shifting job, then the follow-on tasks — so the prompt explains exactly
    /// what "push it all" will do. Capped so the sheet stays glanceable.
    private static func explanationLines(for changes: [SchedulingEngine.CascadeResult.TaskDateChange],
                                         pushedCrew: Set<String>,
                                         dataController: DataController) -> [String] {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        var lines: [String] = []

        let crew = changes.filter { $0.reason == .crew }
        for change in crew.prefix(3) {
            let job = dataController.getTask(id: change.id)
            let title = job?.displayTitle ?? "Another job"
            let member = job.flatMap { Set($0.getTeamMemberIds()).intersection(pushedCrew).first }
            let name = member.flatMap { dataController.getUser(id: $0)?.firstName } ?? "Same crew"
            let to = df.string(from: change.newStartDate)
            if let from = change.oldStartDate.map({ df.string(from: $0) }) {
                lines.append("\(name)'s on \(title) (\(from) → \(to)).")
            } else {
                lines.append("\(name)'s on \(title) — shifts to \(to).")
            }
        }
        if crew.count > 3 { lines.append("+\(crew.count - 3) more crew jobs shift.") }

        let deps = changes.filter { $0.reason == .dependency }
        if let first = deps.first {
            let title = dataController.getTask(id: first.id)?.displayTitle ?? "A follow-on task"
            lines.append(deps.count == 1
                ? "\(title) follows this — shifts to \(df.string(from: first.newStartDate))."
                : "\(title) and \(deps.count - 1) more follow this — they shift too.")
        }
        return lines
    }

    /// Move an event onto `droppedDay`, preserving its day-span AND both time-of-days.
    /// Fully DST-safe: the day count uses calendar arithmetic and the time-of-day is
    /// re-applied with date components (a raw seconds offset would drift an hour
    /// across a daylight-saving boundary).
    private static func targetDates(originalStart: Date, originalEnd: Date,
                                    droppedDay: Date, calendar cal: Calendar) -> (start: Date, end: Date) {
        let dropDayStart = cal.startOfDay(for: droppedDay)
        let s = cal.dateComponents([.hour, .minute, .second], from: originalStart)
        let e = cal.dateComponents([.hour, .minute, .second], from: originalEnd)
        let daySpan = max(cal.dateComponents([.day],
                                             from: cal.startOfDay(for: originalStart),
                                             to: cal.startOfDay(for: originalEnd)).day ?? 0, 0)
        let start = cal.date(bySettingHour: s.hour ?? 0, minute: s.minute ?? 0, second: s.second ?? 0,
                             of: dropDayStart) ?? dropDayStart
        let endDayStart = cal.date(byAdding: .day, value: daySpan, to: dropDayStart) ?? dropDayStart
        let end = cal.date(bySettingHour: e.hour ?? 0, minute: e.minute ?? 0, second: e.second ?? 0,
                           of: endDayStart) ?? endDayStart
        return (start, end)
    }
}

// MARK: - Drop target + live highlight

/// Makes a day cell a reschedule drop target and lights it up when it falls inside
/// the dragged item's projected span. `weekClamp` limits the highlight to the visible
/// week (the strip shows one week; a longer span clamps to what's on screen).
struct RescheduleDropTarget: ViewModifier {
    let day: Date
    var weekClamp: ClosedRange<Date>? = nil

    @Environment(ScheduleDragSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var dataController: DataController

    func body(content: Content) -> some View {
        let highlighted = session.isInProjectedSpan(day, weekClamp: weekClamp)
        content
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(OPSStyle.Colors.opsAccent.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.opsAccent, lineWidth: 1.5)
                        )
                        .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? nil : OPSStyle.Animation.hover, value: highlighted)
            // A custom DropDelegate (not .dropDestination) so we can propose `.move`
            // instead of `.copy` — otherwise iOS shows the green "+" add badge, which
            // reads as "creating something" rather than moving a job.
            .onDrop(of: [.opsRescheduleItem],
                    delegate: RescheduleDropDelegate(day: day, session: session, dataController: dataController))
    }
}

/// Drives one day cell's drop behaviour. Proposes `.move` (no add badge), tracks the
/// live hover target for the multi-day highlight, and commits via the coordinator.
struct RescheduleDropDelegate: DropDelegate {
    let day: Date
    let session: ScheduleDragSession
    let dataController: DataController

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.opsRescheduleItem])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // The whole point of the custom delegate: a move, not a copy.
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        let cal = Calendar.current
        // Tick only when the projected start day actually changes (no haptic spam).
        let changed = session.hoveredDate.map { !cal.isDate($0, inSameDayAs: day) } ?? true
        if changed { UISelectionFeedbackGenerator().selectionChanged() }
        session.hoveredDate = day
    }

    func dropExited(info: DropInfo) {
        let cal = Calendar.current
        if let h = session.hoveredDate, cal.isDate(h, inSameDayAs: day) {
            session.hoveredDate = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.opsRescheduleItem]).first else { return false }
        _ = provider.loadTransferable(type: RescheduleDragPayload.self) { result in
            guard case .success(let payload) = result else { return }
            Task { @MainActor in
                RescheduleCoordinator.handleDrop(payload, on: day,
                                                 dataController: dataController, session: session)
                session.end()
            }
        }
        return true
    }
}

// MARK: - Draggable attach (lift)

extension View {
    /// Make a view a reschedule drop target (day cell).
    func reschedulableDropTarget(day: Date, weekClamp: ClosedRange<Date>? = nil) -> some View {
        modifier(RescheduleDropTarget(day: day, weekClamp: weekClamp))
    }

    /// Make an event view draggable for reschedule when `payload` is non-nil
    /// (i.e. the item is permitted to move). Coexists with an existing context menu:
    /// long-press shows the menu, long-press + move lifts into a drag (native iOS).
    /// The drag preview's `onAppear` is the reliable drag-start hook that arms the
    /// shared session so day cells can project the span during hover.
    @ViewBuilder
    func reschedulable(_ payload: RescheduleDragPayload?, session: ScheduleDragSession?) -> some View {
        if let payload, let session {
            self.draggable(payload) {
                // The drag preview is created at lift and torn down when the drag
                // ENDS — commit or cancel. onAppear arms the session; onDisappear is
                // the only reliable "drag ended" hook SwiftUI gives `.draggable`, so
                // it clears `active` even when the user releases off-grid (otherwise
                // the month-grid hit-test gate would stay disabled and lock out taps).
                RescheduleDragPreview(payload: payload)
                    .onAppear { session.begin(payload) }
                    .onDisappear { session.end() }
            }
        } else {
            self
        }
    }
}

// MARK: - Drag preview chip

/// The lift preview: a compact branded chip showing what's being moved. (The live
/// target date is shown by RescheduleTargetBanner — the system drag preview is
/// static and can't re-render as the finger moves.)
struct RescheduleDragPreview: View {
    let payload: RescheduleDragPayload

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
            Text(payload.title)
                .font(OPSStyle.Typography.captionBold)
                .lineLimit(1)
        }
        .foregroundColor(OPSStyle.Colors.primaryText)
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.opsAccent, lineWidth: 1.5)
        )
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    }
}

// MARK: - Live target banner

/// Floating banner shown at the top of the calendar while a reschedule drag is in
/// flight. Reads the shared session so it updates live as the projected start day
/// changes. Hidden when no drag is active or the finger is off-grid.
struct RescheduleTargetBanner: View {
    @Environment(ScheduleDragSession.self) private var session

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    var body: some View {
        Group {
            if let payload = session.active, let start = session.hoveredDate {
                let cal = Calendar.current
                let end = cal.date(byAdding: .day, value: max(payload.durationDays - 1, 0), to: start) ?? start
                let single = cal.isDate(start, inSameDayAs: end)
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.opsAccent)
                    Text(single
                         ? Self.dayFormatter.string(from: start).uppercased()
                         : "\(Self.dayFormatter.string(from: start).uppercased()) – \(Self.dayFormatter.string(from: end).uppercased())")
                        .font(OPSStyle.Typography.dataValue)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .glassDense()
                .clipShape(Capsule())
                .transition(.opacity)
            }
        }
    }
}
