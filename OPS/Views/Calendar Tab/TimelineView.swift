//
//  TimelineView.swift
//  OPS
//
//  Vertical timeline view (8am-5pm) for precise scheduling mode.
//  Shows tasks as resizable, draggable blocks on a time axis.
//

import SwiftUI
import SwiftData
import Supabase

struct TimelineView: View {
    @EnvironmentObject var dataController: DataController
    @ObservedObject var viewModel: CalendarViewModel

    let date: Date

    private let hourHeight: CGFloat = 60
    private let startHour: Int = 8
    private let endHour: Int = 17
    private let snapMinutes: Int = 15

    @State private var draggedTaskId: String?
    @State private var dragOffset: CGFloat = 0

    var totalHeight: CGFloat {
        CGFloat(endHour - startHour) * hourHeight
    }

    var body: some View {
        ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                // Hour lines
                ForEach(startHour..<endHour, id: \.self) { hour in
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(hourLabel(hour))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: 40, alignment: .trailing)

                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorder)
                            .frame(height: 0.5)
                    }
                    .offset(y: CGFloat(hour - startHour) * hourHeight)
                }

                // Task blocks
                let tasks = viewModel.scheduledTasks(for: date)
                ForEach(tasks, id: \.id) { task in
                    timelineBlock(for: task)
                }
            }
            .frame(height: totalHeight)
            .padding(.leading, OPSStyle.Layout.spacing1)
        }
    }

    @ViewBuilder
    private func timelineBlock(for task: ProjectTask) -> some View {
        let yOffset = yPosition(for: task.startTime)
        let height = blockHeight(start: task.startTime, end: task.endTime)
        let color = Color(hex: task.effectiveColor) ?? Color.blue

        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
            .fill(color.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(color, lineWidth: 2)
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.displayTitle)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white)
                    Text(timeRange(task))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(6)
            }
            .frame(height: max(height, 30))
            .padding(.leading, 52)
            .padding(.trailing, OPSStyle.Layout.spacing2)
            .offset(y: yOffset + (draggedTaskId == task.id ? dragOffset : 0))
            .gesture(task.canEditSchedule ? timeDragGesture(for: task, yOffset: yOffset) : nil)
    }

    private func timeDragGesture(for task: ProjectTask, yOffset: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                draggedTaskId = task.id
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let newY = yOffset + value.translation.height
                let snappedTime = timeFromY(newY)
                updateTaskTime(task, newStartTime: snappedTime)
                draggedTaskId = nil
                dragOffset = 0
            }
    }

    private func yPosition(for time: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        return CGFloat(hour - startHour) * hourHeight + CGFloat(minute) / 60.0 * hourHeight
    }

    private func blockHeight(start: Date, end: Date) -> CGFloat {
        let interval = end.timeIntervalSince(start)
        return CGFloat(interval / 3600.0) * hourHeight
    }

    private func timeFromY(_ y: CGFloat) -> Date {
        let totalMinutes = Int(y / hourHeight * 60) + startHour * 60
        let snapped = (totalMinutes / snapMinutes) * snapMinutes
        let hour = snapped / 60
        let minute = snapped % 60
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = max(startHour, min(hour, endHour - 1))
        components.minute = minute
        return Calendar.current.date(from: components) ?? date
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 12 { return "12P" }
        if hour > 12 { return "\(hour - 12)P" }
        return "\(hour)A"
    }

    private func timeRange(_ task: ProjectTask) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return "\(formatter.string(from: task.startTime)) – \(formatter.string(from: task.endTime))"
    }

    private func updateTaskTime(_ task: ProjectTask, newStartTime: Date) {
        guard task.canEditSchedule else { return }

        let duration = task.endTime.timeIntervalSince(task.startTime)
        let newEndTime = newStartTime.addingTimeInterval(duration)

        // Apply locally for instant feedback
        task.startTime = newStartTime
        task.endTime = newEndTime
        task.needsSync = true
        try? dataController.modelContext?.save()

        // Persist to Supabase. triggerBackgroundSync() only drains the sync-op
        // queue — a local-only time edit is never queued, so without an explicit
        // updateTaskFields the new time would stay on-device (one time on the
        // phone, a different time on web). Format for the `time` columns.
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm:ss"
        let startString = timeFormatter.string(from: newStartTime)
        let endString = timeFormatter.string(from: newEndTime)
        let taskId = task.id
        Task {
            try? await dataController.updateTaskFields(taskId: taskId, fields: [
                "start_time": .string(startString),
                "end_time": .string(endString)
            ])
        }
    }
}
