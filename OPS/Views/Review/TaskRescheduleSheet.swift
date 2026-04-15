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
            // Drag indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            // Header
            VStack(spacing: 6) {
                Text("RESCHEDULE TASK")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text(task.displayTitle.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if let startDate = task.startDate {
                    Text(startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 20)

            // Quick push buttons
            VStack(spacing: 8) {
                Text("QUICK PUSH")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                HStack(spacing: 12) {
                    pushButton(label: "+1D", days: 1)
                    pushButton(label: "+2D", days: 2)
                    pushButton(label: "+3D", days: 3)
                    pushButton(label: "+1W", days: 7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)

            // Calendar reschedule button
            Button(action: {
                showCalendarScheduler = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16))
                    Text("RESCHEDULE")
                        .font(OPSStyle.Typography.captionBold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Cancel button
            Button(action: {
                onDismiss()
                dismiss()
            }) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(OPSStyle.Colors.background)
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

    // MARK: - Push Button

    private func pushButton(label: String, days: Int) -> some View {
        Button(action: {
            handlePush(days: days)
        }) {
            Text(label)
                .font(OPSStyle.Typography.button)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        }
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
