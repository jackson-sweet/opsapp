//
//  DayEventsSheet.swift
//  OPS
//
//  Sheet for displaying calendar events for a selected day
//

import SwiftUI

struct DayEventsSheet: View {
    let date: Date
    let scheduledTasks: [ProjectTask]
    let onTaskSelected: (ProjectTask) -> Void
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    // Bug 077edeff — `task.startDate ?? Date()` was reading the current
    // instant on every render. A task with no startDate flipped between
    // the "new" and "ongoing" buckets each redraw, and within each bucket
    // the rows had no explicit sort so SwiftUI swapped them around as the
    // upstream array order shifted. Sort once by (startDate, displayOrder,
    // id) and treat undated tasks as "new" — they have no past start so
    // they cannot be ongoing.
    private var sortedTasks: [ProjectTask] {
        scheduledTasks.sorted { lhs, rhs in
            let lhsStart = lhs.startDate ?? .distantFuture
            let rhsStart = rhs.startDate ?? .distantFuture
            if lhsStart != rhsStart { return lhsStart < rhsStart }
            if lhs.displayOrder != rhs.displayOrder { return lhs.displayOrder < rhs.displayOrder }
            return lhs.id < rhs.id
        }
    }

    private var newTasks: [ProjectTask] {
        sortedTasks.filter { task in
            guard let startDate = task.startDate else { return true }
            return Calendar.current.isDate(startDate, inSameDayAs: date)
        }
    }

    private var ongoingTasks: [ProjectTask] {
        sortedTasks.filter { task in
            guard let startDate = task.startDate else { return false }
            return !Calendar.current.isDate(startDate, inSameDayAs: date)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: OPSStyle.Layout.spacing3) {
            // Header with day info and dismiss button
            HStack {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(dayOfWeek)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text(monthDayText)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                // Card with project count - showing total count (new + ongoing)
                ZStack {
                    // Project count card with softer edges
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(width: 60, height: 60)

                    // Total event count number (new + ongoing)
                    Text("\(scheduledTasks.count)")
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .frame(width: 60, height: 60)
                .segmentedEventBorder(
                    events: scheduledTasks,
                    isSelected: false,
                    cornerRadius: OPSStyle.Layout.panelRadius
                )
                
                Button(action: { dismiss() }) {
                    Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.leading, OPSStyle.Layout.spacing3)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing2)
            
            // Task list
            if scheduledTasks.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // New tasks section
                        ForEach(Array(newTasks.enumerated()), id: \.element.id) { index, task in
                            CalendarEventCard(
                                task: task,
                                isFirst: index == 0,
                                isOngoing: false,
                                onTap: {
                                    onTaskSelected(task)
                                }
                            )
                            .environmentObject(dataController)
                        }

                        // Ongoing section divider and tasks
                        if !ongoingTasks.isEmpty {
                            // Divider with count
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Text("ONGOING")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                // Horizontal line
                                Rectangle()
                                    .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                                    .frame(height: 1)

                                // Count
                                Text("[\(ongoingTasks.count)]")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.vertical, OPSStyle.Layout.spacing2)

                            // Ongoing tasks
                            ForEach(Array(ongoingTasks.enumerated()), id: \.element.id) { index, task in
                                CalendarEventCard(
                                    task: task,
                                    isFirst: false,
                                    isOngoing: true,
                                    onTap: {
                                        onTaskSelected(task)
                                    }
                                )
                                .environmentObject(dataController)
                            }
                        }
                    }
                    .padding(.bottom, OPSStyle.Layout.spacing3_5)
                }
                }
            }
            .background(OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all))
            .navigationBarHidden(true) // Hide the default navigation bar
        }
    }
    
    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).uppercased()
    }
    
    private var monthDayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3_5) {
            Text("[ No events scheduled ]".uppercased())
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
