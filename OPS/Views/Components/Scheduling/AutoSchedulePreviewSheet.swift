//
//  AutoSchedulePreviewSheet.swift
//  OPS
//
//  Preview sheet showing proposed auto-schedule placements before confirmation.
//

import SwiftUI
import SwiftData

struct AutoSchedulePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataController: DataController

    let project: Project
    let placements: [SchedulingEngine.AutoScheduleResult.TaskPlacement]
    @State private var anchorDate: Date
    let skipWeekends: Bool
    let onConfirm: (Date) -> Void

    init(project: Project, placements: [SchedulingEngine.AutoScheduleResult.TaskPlacement], anchorDate: Date, skipWeekends: Bool, onConfirm: @escaping (Date) -> Void) {
        self.project = project
        self.placements = placements
        self._anchorDate = State(initialValue: anchorDate)
        self.skipWeekends = skipWeekends
        self.onConfirm = onConfirm
    }

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
                .padding(.top, 8)

            // Header
            HStack {
                Text("AUTO-SCHEDULE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text("\(placements.count) tasks")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Anchor date picker
            HStack {
                Text("Starting from:")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                DatePicker("", selection: $anchorDate, displayedComponents: .date)
                    .labelsHidden()
                    .colorScheme(.dark)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Placements list
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(placements.enumerated()), id: \.element.id) { index, placement in
                        placementRow(placement: placement, index: index)
                    }
                }
                .padding(.vertical, 12)
            }

            Divider().background(OPSStyle.Colors.cardBorder)

            // Action buttons
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
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
                    onConfirm(anchorDate)
                    dismiss()
                }) {
                    Text("SCHEDULE ALL")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                }
            }
            .padding(16)
        }
        .background(OPSStyle.Colors.background)
    }

    @ViewBuilder
    private func placementRow(placement: SchedulingEngine.AutoScheduleResult.TaskPlacement, index: Int) -> some View {
        HStack(spacing: 12) {
            // Order indicator
            Text("\(index + 1)")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(taskName(for: placement.id))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("\(dateFormatter.string(from: placement.startDate)) – \(dateFormatter.string(from: placement.endDate))")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OPSStyle.Colors.cardBackgroundDark)
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
