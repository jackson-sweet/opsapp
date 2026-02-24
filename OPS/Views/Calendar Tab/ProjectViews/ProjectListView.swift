//
//  ProjectListView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// ProjectListView.swift
import SwiftUI

struct ProjectListView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var dataController: DataController
    @Environment(\.tutorialMode) private var tutorialMode
    @State private var isAnimating = false
    @State private var hasNotifiedTutorialScroll = false
    @State private var allowScrollDetection = false  // Delay scroll detection to avoid false triggers on layout

    // Separate new and ongoing tasks
    private var newTasks: [ProjectTask] {
        viewModel.scheduledTasksForSelectedDate.filter { task in
            Calendar.current.isDate(task.startDate ?? Date(), inSameDayAs: viewModel.selectedDate)
        }
    }

    private var ongoingTasks: [ProjectTask] {
        viewModel.scheduledTasksForSelectedDate.filter { task in
            let startDate = task.startDate ?? Date()
            return !Calendar.current.isDate(startDate, inSameDayAs: viewModel.selectedDate)
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            
            // Only the content area should be in the ScrollView, not the header
            if viewModel.scheduledTasksForSelectedDate.isEmpty {
                emptyStateView
                    .opacity(isAnimating ? 1 : 0)
                    .offset(y: isAnimating ? 0 : 20)
            } else {
                // Project list content in ScrollView
                ScrollView {
                    projectListView
                        .opacity(isAnimating ? 1 : 0)
                        .offset(y: isAnimating ? 0 : 20)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.frame(in: .global).minY) { oldY, newY in
                                        // Detect if user has scrolled (significant movement)
                                        // Only detect after delay to avoid false triggers from initial layout
                                        if tutorialMode && allowScrollDetection && !hasNotifiedTutorialScroll && abs(oldY - newY) > 10 {
                                            hasNotifiedTutorialScroll = true
                                            NotificationCenter.default.post(
                                                name: Notification.Name("CalendarWeekViewScrolled"),
                                                object: nil
                                            )
                                        }
                                    }
                            }
                        )
                        .onAppear {
                            // Delay scroll detection to allow initial layout to settle
                            if tutorialMode {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    allowScrollDetection = true
                                }
                            }
                        }
                }
            }
            
            // Selected date header based on reference design
            // IMPORTANT: Header should NOT be in ScrollView
            HStack(alignment: .top) {
                // Day of week and month/day in vertical layout
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayOfWeek)
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text(monthDayText)
                        .font(OPSStyle.Typography.cardSubtitle)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                // Card with project count - showing total count (new + ongoing)
                ZStack {
                    // Project count card with softer edges
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(width: 40, height: 40)
                    
                    // Total event count number (new + ongoing)
                    Text("\(viewModel.scheduledTasksForSelectedDate.count)")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(.white)
                }
                .frame(width: 40, height: 40)
                .segmentedEventBorder(
                    events: viewModel.scheduledTasksForSelectedDate,  // Show border for all events
                    isSelected: false,
                    cornerRadius: 10
                )
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial)
            
            
        }
        .overlay(
            // White border for first/selected project card
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        // Watch for calendar event changes and force refresh
        .onChange(of: dataController.scheduledTasksDidChange) { _, _ in
            // Use objectWillChange instead of forcing full view recreation
            viewModel.objectWillChange.send()
        }
        // Trigger animation when view appears
        .onAppear {
            withAnimation(OPSStyle.Animation.standard) {
                isAnimating = true
            }
        }
        // Reset animation state when date changes
        .onChange(of: viewModel.selectedDate) { _, _ in
            isAnimating = false
            withAnimation(OPSStyle.Animation.standard) {
                isAnimating = true
            }
        }
    }
    
    // Split the date into components for better styling
    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: viewModel.selectedDate).uppercased()
    }
    
    private var monthDayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: viewModel.selectedDate)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("[ No projects scheduled ]".uppercased())
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var projectListView: some View {
        VStack(spacing: 16) {

            Spacer(minLength: 90)
                .frame(maxWidth: .infinity, maxHeight: 90)

            // New tasks section
            ForEach(Array(newTasks.enumerated()), id: \.element.id) { index, task in
                CalendarEventCard(
                    task: task,
                    isFirst: index == 0,
                    isOngoing: false,
                    onTap: {
                        handleTaskTap(task)
                    }
                )
            }

            // Ongoing section divider and tasks
            if !ongoingTasks.isEmpty {
                // Divider with count
                HStack(spacing: 8) {
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
                .padding(.vertical, 8)
                .padding(.horizontal, 8)

                // Ongoing tasks
                ForEach(Array(ongoingTasks.enumerated()), id: \.element.id) { index, task in
                    CalendarEventCard(
                        task: task,
                        isFirst: false,
                        isOngoing: true,
                        onTap: {
                            handleTaskTap(task)
                        }
                    )
                }
            }
        }
        .padding(.bottom, 16)
    }
    
    private func handleTaskTap(_ task: ProjectTask) {
        let userInfo: [String: String] = [
            "taskID": task.id,
            "projectID": task.projectId
        ]

        NotificationCenter.default.post(
            name: Notification.Name("ShowCalendarTaskDetails"),
            object: nil,
            userInfo: userInfo
        )
    }
}
