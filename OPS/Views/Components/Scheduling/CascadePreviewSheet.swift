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

    /// Optional plain-language "why" lines shown under the header (drag-drop crew/
    /// dependency prompt). Empty for existing callers, which render unchanged.
    var explanationLines: [String] = []
    /// Label for the primary (confirm) action. Defaults "CONFIRM".
    var primaryLabel: String = "CONFIRM"
    /// Optional third action: move only the dropped job, leaving the rest in place
    /// (overlap allowed). Rendered as a full-width button above CANCEL / primary
    /// only when provided.
    var onMoveOnly: (() -> Void)? = nil

    @AppStorage("showCascadePreview") private var showCascadePreview: Bool = true

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, OPSStyle.Layout.spacing2)

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
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)

            // Plain-language "why" lines (drag-drop crew/dependency prompt)
            if !explanationLines.isEmpty {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    ForEach(explanationLines, id: \.self) { line in
                        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(line)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing2)
            }

            // Task changes list
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing2) {
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
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
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
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)

            // Action buttons
            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                // Optional third action — move only the dropped job (overlap allowed).
                if let onMoveOnly {
                    Button(action: {
                        onMoveOnly()
                        dismiss()
                    }) {
                        Text("MOVE ONLY THIS")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .nestedCard()
                    }
                }

                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Button(action: {
                        onCancel()
                        dismiss()
                    }) {
                        Text("CANCEL")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .nestedCard()
                    }

                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        Text(primaryLabel)
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing3)
        }
        .glassDense()
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
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 12))
                Text(title)
                    .font(OPSStyle.Typography.smallCaption)
                Spacer()
            }
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing1)

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
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(taskName)
                    .font(isPrimary ? OPSStyle.Typography.bodyBold : OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                HStack(spacing: OPSStyle.Layout.spacing1) {
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
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3)
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
