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
    @EnvironmentObject var dataController: DataController

    @AppStorage("showCascadePreview") private var cascadePreviewEnabled: Bool = true

    @State private var showCalendarScheduler: Bool = false
    @State private var showCascadePreview: Bool = false
    @State private var pendingCascadeResult: SchedulingEngine.CascadeResult?
    @State private var pendingNewStart: Date?
    @State private var pendingNewEnd: Date?

    var body: some View {
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
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
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
                pushChip(label: "+1W", days: 7, hint: "Push start date by one week")
            }
        }
    }

    private func pushChip(label: String, days: Int, hint: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            handlePush(days: days)
        } label: {
            Text(label)
                .font(OPSStyle.Typography.dataValue)
                .monospacedDigit()
                .tracking(0.6)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.cardBackgroundDark)
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

    private func handlePush(days: Int) {
        let newDates = SchedulingEngine.pushByDays(task: task, days: days)

        // Get project tasks for cascade calculation
        let projectTasks = getProjectTasks()

        let cascadeResult = SchedulingEngine.calculateCascade(
            pushedTaskId: task.id,
            newStartDate: newDates.newStart,
            newEndDate: newDates.newEnd,
            allProjectTasks: projectTasks
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
                guard let affectedTask = projectTasks.first(where: { $0.id == change.id }) else { continue }
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
