//
//  TaskRescheduleSheet.swift
//  OPS
//
//  Sheet presented on up-swipe during task review.
//  Allows quick push (+1D, +2D, +3D, +1W) or full calendar reschedule.
//

import SwiftUI

struct TaskRescheduleSheet: View {
    let task: ProjectTask
    let onRescheduled: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var dataController: DataController

    @AppStorage("showCascadePreview") private var cascadePreviewEnabled: Bool = true

    @State private var showCalendarScheduler: Bool = false
    @State private var showCascadePreview: Bool = false
    @State private var pendingCascadeResult: SchedulingEngine.CascadeResult?
    @State private var pendingNewStart: Date?
    @State private var pendingNewEnd: Date?

    // MARK: - Zoom-to-day state
    //
    // Pinching out on the current-start card (or tapping the inspect
    // affordance) zooms into a day-detail surface listing that day's events.
    // The pinch is a Transition beat — a camera move into the day — so the
    // header surface scales/fades up under the live pinch and the detail
    // takes over past the commit threshold. Reduced motion swaps the zoom
    // for a crossfade (same beat, no spatial scaling).
    @State private var showDayDetail: Bool = false
    /// Live magnification while the pinch is in progress (1.0 = at rest).
    @State private var pinchMagnitude: CGFloat = 1.0
    /// True once the commit threshold is crossed in a given pinch, so the
    /// commit haptic fires exactly once per gesture.
    @State private var pinchDidCommit: Bool = false

    /// The day the operator zooms into — the task's current start, or today
    /// when the task has no start date yet.
    private var dayDetailTarget: Date {
        Calendar.current.startOfDay(for: task.startDate ?? Date())
    }

    /// Pinch-out magnitude that commits the zoom into the day detail. 1.4×
    /// is enough deliberate intent to avoid accidental triggers from a
    /// two-finger scroll, while still feeling light.
    private let pinchCommitThreshold: CGFloat = 1.4
    /// Haptic generator for the zoom commit — pre-warmed on first pinch
    /// movement to eliminate Taptic Engine spin-up latency.
    private let zoomHaptic = UIImpactFeedbackGenerator(style: .medium)

    /// Whether the current user may reschedule this task — calendar.edit,
    /// scope-aware (own-scope → only their own tasks). The sheet is normally only
    /// reached for editable tasks; this guards the mutation paths as defense in
    /// depth, and cascade application filters to tasks the user may move.
    private var canModify: Bool { task.canEditSchedule }

    var body: some View {
        ZStack {
            // Base reschedule surface — quick-push chips + open-calendar.
            // Scales/fades back slightly as the pinch grows so the zoom reads
            // as moving INTO the day, not a flat swap. Held static under
            // reduced motion.
            rescheduleSurface
                .scaleEffect(reduceMotion ? 1.0 : baseSurfaceScale)
                .opacity(reduceMotion ? 1.0 : baseSurfaceOpacity)
                .allowsHitTesting(!showDayDetail)

            // Day detail — the zoom destination. Enters scaling up from the
            // pinch origin (or crossfades under reduced motion).
            if showDayDetail {
                RescheduleDayDetailView(
                    task: task,
                    day: dayDetailTarget,
                    onConfirm: { newStart, newEnd in
                        handleRescheduleToDay(newStart: newStart, newEnd: newEnd)
                    },
                    onClose: { closeDayDetail() }
                )
                .environmentObject(dataController)
                .transition(dayDetailTransition)
                .zIndex(1)
            }
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .sheet(isPresented: $showCalendarScheduler) {
            CalendarSchedulerSheet(
                isPresented: $showCalendarScheduler,
                itemType: .task(task),
                currentStartDate: task.startDate,
                currentEndDate: task.endDate,
                onScheduleUpdate: { newStart, newEnd in
                    applyReschedule(newStart: newStart, newEnd: newEnd)
                },
                onClearDates: nil,
                preselectedTeamMemberIds: Set(task.getTeamMemberIds())
            )
        }
        .sheet(isPresented: $showCascadePreview) {
            if let cascadeResult = pendingCascadeResult,
               let newStart = pendingNewStart,
               let newEnd = pendingNewEnd {
                CascadePreviewSheet(
                    pushedTaskName: task.displayTitle,
                    pushedTaskOldStart: task.startDate,
                    pushedTaskNewStart: newStart,
                    pushedTaskNewEnd: newEnd,
                    cascadeChanges: cascadeResult.changes,
                    onConfirm: {
                        applyReschedule(newStart: newStart, newEnd: newEnd)
                        applyCascade(cascadeResult)
                    },
                    onCancel: {
                        // User cancelled cascade preview — dismiss without changes
                    }
                )
                .environmentObject(dataController)
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Reschedule Surface
    //
    // The base layer: header card (now the pinch target), quick-push chips,
    // and the pinned action footer. Extracted so the zoom transition can
    // scale/fade the whole surface as one unit behind the day detail.

    private var rescheduleSurface: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: OPSStyle.Layout.spacing4) {
                    headerCard
                    quickPushSection
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing3)
            }

            actionFooter
        }
    }

    // MARK: - Zoom Transition Math
    //
    // While pinching, the base surface eases back from 1.0 toward 0.94 and
    // fades slightly so depth reads without the content distorting. Progress
    // is normalized 0→1 across the rest-to-commit magnitude range.

    private var pinchProgress: CGFloat {
        guard pinchCommitThreshold > 1 else { return 0 }
        let raw = (pinchMagnitude - 1.0) / (pinchCommitThreshold - 1.0)
        return min(max(raw, 0), 1)
    }

    private var baseSurfaceScale: CGFloat {
        // Recede at most 6% — enough to suggest the day surface coming
        // forward, not so much it looks broken.
        1.0 - (pinchProgress * 0.06)
    }

    private var baseSurfaceOpacity: Double {
        1.0 - Double(pinchProgress) * 0.25
    }

    /// The day-detail enter/exit transition. Scale-up from 92% + fade for the
    /// camera-move feel; pure crossfade under reduced motion (same beat).
    private var dayDetailTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .scale(scale: 0.92).combined(with: .opacity)
    }

    // MARK: - Pinch Gesture
    //
    // Applied to the current-start card. Tracks live magnitude, pre-warms the
    // commit haptic on first movement, and commits into the day detail once
    // the pinch-out crosses the threshold. Reduced motion still commits via
    // pinch — only the visual treatment changes (crossfade vs zoom).
    private var dayZoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.05)
            .onChanged { value in
                guard !showDayDetail else { return }
                if pinchMagnitude == 1.0 {
                    // First movement of this pinch — warm the Taptic Engine.
                    zoomHaptic.prepare()
                }
                pinchMagnitude = max(value.magnification, 0.5)

                // Commit once when the pinch-out crosses the threshold.
                if !pinchDidCommit && pinchMagnitude >= pinchCommitThreshold {
                    pinchDidCommit = true
                    commitDayDetail()
                }
            }
            .onEnded { _ in
                // Reset the live magnitude regardless of commit. If the user
                // released before the threshold, the surface eases back to
                // rest; if they committed, the detail is already presented.
                withAnimation(OPSStyle.Animation.panel) {
                    pinchMagnitude = 1.0
                }
                pinchDidCommit = false
            }
    }

    // MARK: - Day Detail Open / Close

    /// Commit the zoom — fired by the pinch crossing threshold. Haptic is the
    /// Transition beat fired at the peak visual change (the moment the detail
    /// takes over).
    private func commitDayDetail() {
        zoomHaptic.impactOccurred()
        withAnimation(reduceMotion ? OPSStyle.Animation.faster : OPSStyle.Animation.page) {
            showDayDetail = true
        }
    }

    /// Open the day detail from the tap affordance — same destination as the
    /// pinch, reachable without gestures and under reduced motion. Light
    /// arrival haptic (a tap, not a commit).
    private func openDayDetail() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? OPSStyle.Animation.faster : OPSStyle.Animation.page) {
            showDayDetail = true
        }
    }

    private func closeDayDetail() {
        withAnimation(reduceMotion ? OPSStyle.Animation.faster : OPSStyle.Animation.page) {
            showDayDetail = false
            pinchMagnitude = 1.0
        }
        pinchDidCommit = false
    }

    /// Reschedule confirmed from the day detail. Routes through the same
    /// canonical push path the quick-push chips use — building the cascade
    /// preview when relevant — so a day-move and a chip-push behave
    /// identically (save, sync, notify, cascade).
    private func handleRescheduleToDay(newStart: Date, newEnd: Date) {
        let projectTasks = getProjectTasks()
        let cascadeResult = SchedulingEngine.calculateCascade(
            pushedTaskId: task.id,
            newStartDate: newStart,
            newEndDate: newEnd,
            allProjectTasks: projectTasks
        )

        if !cascadeResult.changes.isEmpty && cascadePreviewEnabled {
            pendingCascadeResult = cascadeResult
            pendingNewStart = newStart
            pendingNewEnd = newEnd
            showDayDetail = false
            showCascadePreview = true
        } else if !cascadeResult.changes.isEmpty {
            applyReschedule(newStart: newStart, newEnd: newEnd)
            applyCascade(cascadeResult)
        } else {
            applyReschedule(newStart: newStart, newEnd: newEnd)
        }
    }

    // MARK: - Header Card
    //
    // Glass-on-canvas card stating WHAT is being rescheduled and FROM WHEN.
    // The current-start line is the load-bearing context for the entire sheet
    // — every push is relative to it — so it gets equal weight with the task
    // name via the internal hairline divider.

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            sectionEyebrow("RESCHEDULE")

            Text(task.displayTitle.uppercased())
                .font(OPSStyle.Typography.bodyBold)
                .tracking(0.6)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: OPSStyle.Layout.Border.standard)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1 + 2) {
                sectionEyebrow("CURRENT START")

                if let startDate = task.startDate {
                    Text(currentStartLabel(for: startDate))
                        .font(OPSStyle.Typography.dataValue)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.primaryText)
                } else {
                    Text("— NOT SCHEDULED")
                        .font(OPSStyle.Typography.dataValue)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            // Inspect affordance — the non-gesture path into the day detail.
            // Pinch is undiscoverable and excluded for reduced-motion users,
            // so this tappable hint guarantees the surface is reachable for
            // everyone. The whole card also accepts the pinch (below).
            inspectAffordance
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .contentShape(Rectangle())
        // Pinch-out anywhere on the card zooms into the day detail
        // (Transition beat). The tap path lives on the inspect affordance
        // button above so it stays an explicit, discoverable target and
        // doesn't fight the magnify gesture's hit-testing.
        .gesture(dayZoomGesture)
    }

    // MARK: - Inspect Affordance
    //
    // One terse line — what, not how. Sized as its own tap target so the hint
    // reads as actionable, with a magnifier glyph the operator already
    // associates with "look closer."

    private var inspectAffordance: some View {
        Button(action: { openDayDetail() }) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "arrow.up.left.and.arrow.down.right.magnifyingglass")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text("PINCH OR TAP TO INSPECT THIS DAY")
                    .font(OPSStyle.Typography.metadata)
                    .tracking(0.8)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.top, OPSStyle.Layout.spacing1)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Inspect this day")
        .accessibilityHint("Opens the day's schedule so you can move the task here")
    }

    // MARK: - Quick Push Section
    //
    // Four monochrome outlined chips. Filled steel-blue is reserved for the
    // primary CTA below per the OPS visual system; secondary "shortcut"
    // actions sit as hairline-bordered chips so the screen has one clear
    // dominant signal.

    private var quickPushSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionEyebrow("QUICK PUSH")

            HStack(spacing: OPSStyle.Layout.spacing2) {
                pushChip(label: "+1D", days: 1, hint: "Push start date by one day")
                pushChip(label: "+2D", days: 2, hint: "Push start date by two days")
                pushChip(label: "+3D", days: 3, hint: "Push start date by three days")
                pushChip(label: "+1W", days: 7, hint: "Push start date by one week", preserveCalendarWeek: true)
            }
        }
    }

    private func pushChip(label: String, days: Int, hint: String, preserveCalendarWeek: Bool = false) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            handlePush(days: days, preserveCalendarWeek: preserveCalendarWeek)
        } label: {
            Text(label)
                .font(OPSStyle.Typography.dataValue)
                .monospacedDigit()
                .tracking(0.6)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.surfaceInput)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Push \(label)")
        .accessibilityHint(hint)
    }

    // MARK: - Action Footer
    //
    // Pinned to the bottom edge so the primary CTA is one-thumb reachable
    // and unaffected by content scroll. Steel-blue fill on the primary CTA
    // is the only accent fill on the sheet — the single dominant signal.

    private var actionFooter: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showCalendarScheduler = true
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "calendar")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    Text("OPEN CALENDAR")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(1.0)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        .opacity(0.7)
                }
                .foregroundColor(.white)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Open full calendar to pick new dates")

            Button {
                onDismiss()
                dismiss()
            } label: {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(1.0)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2_5)
        .padding(.bottom, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OPSStyle.Colors.cardBorderSubtle)
                .frame(height: OPSStyle.Layout.Border.standard)
        }
    }

    // MARK: - Section Eyebrow

    private func sectionEyebrow(_ label: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("//")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.inactiveText)
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .tracking(1.2)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Formatting

    private func currentStartLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE · MMM d"
        return formatter.string(from: date).uppercased()
    }

    // MARK: - Push Logic

    private func handlePush(days: Int, preserveCalendarWeek: Bool = false) {
        // A week push preserves the weekday (exactly +7, no weekend-normalize);
        // day nudges honor the company weekend-skip.
        let skip = dataController.currentCompanySkipsWeekends
        let newDates = preserveCalendarWeek
            ? SchedulingEngine.pushByCalendarWeeks(task: task, weeks: days / 7)
            : SchedulingEngine.pushByDays(task: task, days: days, skipWeekends: skip)

        // Get project tasks for cascade calculation
        let projectTasks = getProjectTasks()

        let cascadeResult = SchedulingEngine.calculateCascade(
            pushedTaskId: task.id,
            newStartDate: newDates.newStart,
            newEndDate: newDates.newEnd,
            allProjectTasks: projectTasks,
            skipWeekends: skip
        )

        if !cascadeResult.changes.isEmpty && cascadePreviewEnabled {
            // Show cascade preview
            pendingCascadeResult = cascadeResult
            pendingNewStart = newDates.newStart
            pendingNewEnd = newDates.newEnd
            showCascadePreview = true
        } else if !cascadeResult.changes.isEmpty {
            // Cascade changes exist but preview disabled — apply immediately
            applyReschedule(newStart: newDates.newStart, newEnd: newDates.newEnd)
            applyCascade(cascadeResult)
        } else {
            // No cascade — apply directly
            applyReschedule(newStart: newDates.newStart, newEnd: newDates.newEnd)
        }
    }

    // MARK: - Apply

    private func applyReschedule(newStart: Date, newEnd: Date) {
        guard canModify else { return }
        // Canonical path — saves context, records SyncOperation, and sends
        // schedule-change notifications to assigned team members. Direct
        // mutation was losing every reschedule because neither the save nor
        // the outbound push was running.
        Task {
            do {
                try await dataController.updateTaskSchedule(
                    task: task,
                    startDate: newStart,
                    endDate: newEnd
                )
            } catch {
                print("[TASK_RESCHEDULE] Failed to apply reschedule: \(error)")
            }
            await MainActor.run {
                onRescheduled()
                dismiss()
            }
        }
    }

    private func applyCascade(_ cascadeResult: SchedulingEngine.CascadeResult) {
        let projectTasks = getProjectTasks()
        // Resolve each affected task on the main actor, then dispatch one
        // canonical update per change. Sequential to preserve ordering and
        // avoid race conditions on the shared sync queue.
        Task {
            for change in cascadeResult.changes {
                // Own-scope users only shift tasks they may move; "all" passes all.
                guard let affectedTask = projectTasks.first(where: { $0.id == change.id }),
                      affectedTask.canEditSchedule else { continue }
                do {
                    try await dataController.updateTaskSchedule(
                        task: affectedTask,
                        startDate: change.newStartDate,
                        endDate: change.newEndDate
                    )
                } catch {
                    print("[TASK_RESCHEDULE] Cascade update failed for \(change.id): \(error)")
                }
            }
        }
    }

    private func getProjectTasks() -> [ProjectTask] {
        guard let project = task.project else { return [] }
        return (project.tasks ?? []).filter { $0.deletedAt == nil }
    }
}
