//
//  CascadePreviewSheet.swift
//  OPS
//
//  Shows a preview of tasks that will be affected by a push/cascade operation.
//  Presented as a bottom sheet with confirm/cancel and "don't show again" toggle.
//

import SwiftUI
import SwiftData

struct CascadePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataController: DataController

    let pushedTaskName: String
    let pushedTaskOldStart: Date?
    let pushedTaskNewStart: Date
    let pushedTaskNewEnd: Date
    let cascadeChanges: [SchedulingEngine.CascadeResult.TaskDateChange]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @AppStorage("showCascadePreview") private var showCascadePreview: Bool = true

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            // Header
            HStack {
                Text("SCHEDULE CHANGES")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text("\(cascadeChanges.count + 1) tasks")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Task changes list
            ScrollView {
                VStack(spacing: 8) {
                    // The pushed task itself
                    changeRow(
                        taskName: pushedTaskName,
                        oldStart: pushedTaskOldStart,
                        newStart: pushedTaskNewStart,
                        newEnd: pushedTaskNewEnd,
                        isPrimary: true
                    )

                    // Jobs moving because they share a crew member with the
                    // pushed job, then jobs moving because of a dependency.
                    cascadeGroup(title: "Same crew", changes: crewChanges)
                    cascadeGroup(title: "Dependent tasks", changes: dependencyChanges)
                }
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 300)

            Divider().background(OPSStyle.Colors.cardBorder)

            // Don't show again toggle
            Toggle(isOn: Binding(
                get: { !showCascadePreview },
                set: { showCascadePreview = !$0 }
            )) {
                Text("Don't show preview")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.text))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    onCancel()
                    dismiss()
                }) {
                    Text("CANCEL")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                }

                Button(action: {
                    onConfirm()
                    dismiss()
                }) {
                    Text("CONFIRM")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(OPSStyle.Colors.background)
    }

    private var crewChanges: [SchedulingEngine.CascadeResult.TaskDateChange] {
        cascadeChanges.filter { $0.reason == .crew }
    }

    private var dependencyChanges: [SchedulingEngine.CascadeResult.TaskDateChange] {
        cascadeChanges.filter { $0.reason == .dependency }
    }

    /// A labelled group of cascade rows (e.g. "Same crew"). Renders nothing when
    /// the group is empty so only the reasons that actually apply are shown.
    @ViewBuilder
    private func cascadeGroup(title: String, changes: [SchedulingEngine.CascadeResult.TaskDateChange]) -> some View {
        if !changes.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 12))
                Text(title)
                    .font(OPSStyle.Typography.smallCaption)
                Spacer()
            }
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            ForEach(changes) { change in
                changeRow(
                    taskName: taskName(for: change.id),
                    oldStart: change.oldStartDate,
                    newStart: change.newStartDate,
                    newEnd: change.newEndDate,
                    isPrimary: false
                )
            }
        }
    }

    @ViewBuilder
    private func changeRow(taskName: String, oldStart: Date?, newStart: Date, newEnd: Date, isPrimary: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(taskName)
                    .font(isPrimary ? OPSStyle.Typography.bodyBold : OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                HStack(spacing: 4) {
                    if let old = oldStart {
                        Text(dateFormatter.string(from: old))
                            .strikethrough()
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    Text("\(dateFormatter.string(from: newStart)) – \(dateFormatter.string(from: newEnd))")
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .font(OPSStyle.Typography.caption)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(isPrimary ? 1.0 : 0.5))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .padding(.horizontal, 16)
    }

    private func taskName(for taskId: String) -> String {
        guard let ctx = dataController.modelContext else { return "Task" }
        let predicate = #Predicate<ProjectTask> { $0.id == taskId }
        let descriptor = FetchDescriptor<ProjectTask>(predicate: predicate)
        if let task = try? ctx.fetch(descriptor).first {
            return task.displayTitle
        }
        return "Task"
    }
}
