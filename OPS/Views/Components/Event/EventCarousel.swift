//
//  EventCarousel.swift
//  OPS
//
//  Carousel for displaying calendar events on the home screen
//

import SwiftUI

struct EventCarousel: View {
    let events: [CalendarEvent]
    @Binding var selectedIndex: Int
    @Binding var showStartConfirmation: Bool
    let isInProjectMode: Bool
    let activeProjectID: String?
    let onStart: (Project) -> Void
    let onStop: (Project) -> Void
    let onLongPress: (Project) -> Void
    
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        TabView(selection: $selectedIndex) {
            // Create card views for each event
            ForEach(events.indices, id: \.self) { index in
                makeEventCard(for: index)
                    .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never)) // Hide default dots
        .frame(height: 120)
        .onChange(of: selectedIndex) { oldIndex, newIndex in
            // Hide confirmation when swiping
            if showStartConfirmation {
                showStartConfirmation = false
            }
        }
    }
    
    private func makeEventCard(for index: Int) -> some View {
        let event = events[index]
        let project = dataController.getProject(id: event.projectId)
        
        return EventCardView(
            event: event,
            project: project,
            isSelected: selectedIndex == index,
            showConfirmation: showStartConfirmation && selectedIndex == index,
            isActiveProject: activeProjectID == event.projectId,
            currentIndex: selectedIndex,
            totalCount: events.count,
            onTap: {
                handleCardTap(forIndex: index)
            },
            onStart: {
                if let project = project {
                    onStart(project)
                }
            },
            onStop: {
                if let project = project {
                    onStop(project)
                }
            },
            onLongPress: {
                if let project = project {
                    onLongPress(project)
                }
            }
        )
    }
    
    private func handleCardTap(forIndex index: Int) {
        guard !isInProjectMode else {
            return
        }
        
        if selectedIndex == index {
            // Toggle confirmation for selected card
            DispatchQueue.main.async {
                self.showStartConfirmation.toggle()
            }
        } else {
            // Select this card
            selectedIndex = index
            // Always hide confirmation when selecting a new card
            showStartConfirmation = false
        }
    }
}

// Event card view for displaying individual calendar events
struct EventCardView: View {
    let event: CalendarEvent
    let project: Project?
    let isSelected: Bool
    let showConfirmation: Bool
    let isActiveProject: Bool
    let currentIndex: Int
    let totalCount: Int
    let onTap: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onLongPress: () -> Void
    
    @State private var isLongPressing = false
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var dataController: DataController
    
    private var displayTitle: String {
        // ALWAYS show project title
        return project?.title ?? event.title
    }

    private var taskTypeBadge: String? {
        // All events are task events now
        if let task = event.task {
            return task.taskType?.display
        }
        return nil
    }

    private var displayColor: Color {
        // All events are task events now - use task color
        if let task = event.task,
           let color = Color(hex: task.effectiveColor) {
            return color
        }

        // Fallback to event color or grey
        if let eventColor = Color(hex: event.color) {
            return eventColor
        }
        return Color.gray.opacity(0.6)
    }
    
    var body: some View {
        ZStack {
            // Card container
            ZStack {
                // Card background
                ZStack {
                    // Base background
                    Color("CardBackground")
                        .opacity(0.3)
                    
                    Rectangle()
                        .fill(Color.clear)
                        .background(Material.thinMaterial.opacity(0.7))
                    
                    // Subtle background for completed tasks
                    // All events are task events now
                    if let task = event.task, task.status == .completed {
                        OPSStyle.Colors.statusColor(for: .completed).opacity(0.1)
                    }
                    
                    // Highlight for long press
                    if isLongPressing {
                        OPSStyle.Colors.primaryAccent.opacity(0.3)
                    }
                }
                
                // Content
                HStack(spacing: 0) {
                    // Left color bar
                    Rectangle()
                        .fill(displayColor)
                        .frame(width: 4)
                    
                    ZStack(alignment: .topTrailing) {
                        // Main content
                        VStack(alignment: .leading, spacing: 2) {
                            // Event title
                            Text(displayTitle.uppercased())
                                .font(OPSStyle.Typography.cardTitle)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineLimit(1)
                            
                            // Client name
                            if let clientName = project?.effectiveClientName {
                                Text(clientName)
                                    .font(OPSStyle.Typography.cardBody)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .lineLimit(1)
                            }
                            
                            // Address with event type badge inline
                            HStack(spacing: 8) {
                                if let address = project?.address {
                                    Text(extractAddressComponents(address))
                                        .font(OPSStyle.Typography.cardBody)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .lineLimit(1)
                                }
                                
                                Spacer()

                                // Event type badge - show task type (all events are tasks now)
                                if let taskType = taskTypeBadge {
                                    Text(taskType.uppercased())
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(displayColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(displayColor.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .stroke(displayColor.opacity(0.3), lineWidth: 1)
                                                )
                                        )
                                } else {
                                    Text("TASK")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(displayColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(displayColor.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .stroke(displayColor.opacity(0.3), lineWidth: 1)
                                                )
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(width: 358, alignment: .leading)

                        // Page indicators - only show if there's more than one event
                        if totalCount > 1 {
                            HStack(spacing: 12) {
                                ForEach(0..<totalCount, id: \.self) { index in
                                    Circle()
                                        .fill(index == currentIndex ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder)
                                        .frame(width: 13, height: 13)
                                }
                            }
                            .padding(6)
                            .padding(.top, 6)
                            .padding(.trailing, 10)
                        }
                    }
                }
            }
            .frame(width: 362, height: 100)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(isActiveProject ? OPSStyle.Colors.primaryAccent : Color.clear, lineWidth: 2)
            )
            
            // Confirmation overlay
            if showConfirmation && !isActiveProject {
                confirmationOverlay
            }

            // Completed overlay - grey out and show badge
            // All events are task events now
            if event.task?.status == .completed {
                ZStack(alignment: .topTrailing) {
                    // Grey overlay
                    OPSStyle.Colors.modalOverlay
                        .frame(width: 362, height: 100)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)

                    // Completed badge
                    Text("COMPLETED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(OPSStyle.Colors.statusColor(for: .completed))
                        )
                        .padding(8)
                }
            }

            // Cancelled overlay - grey out and show badge
            if event.task?.status == .cancelled {
                ZStack(alignment: .topTrailing) {
                    // Grey overlay
                    OPSStyle.Colors.modalOverlay
                        .frame(width: 362, height: 100)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)

                    // Cancelled badge
                    Text("CANCELLED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(OPSStyle.Colors.inactiveStatus)
                        )
                        .padding(8)
                }
            }
        }
        .onTapGesture {
            // Always use the tap handler for confirmation
            onTap()
        }
        .onLongPressGesture(
            minimumDuration: 0.6,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isLongPressing = pressing
                }
                
                if pressing {
                    // Immediate light feedback on press start
                    HapticFeedback.impact(.light)
                }
            },
            perform: {
                // Success feedback and open details
                HapticFeedback.longPressSuccess()
                
                // Open task details view (all events are task events now)
                if let task = event.task, let project = project {
                    appState.viewTaskDetails(task: task, project: project)
                } else if let project = project {
                    // Fallback to project details if task is missing
                    appState.viewProjectDetails(project)
                }
            }
        )
    }
    
    private var confirmationOverlay: some View {
        VStack(spacing: 8) {
            Text("START TASK")  // All events are task events now
                .font(OPSStyle.Typography.button)
                .foregroundColor(.white)

            Image(systemName: "play.fill")
                .font(.system(size: 24))
                .foregroundColor(.white)
        }
        .frame(width: 362, height: 100)
        .background(OPSStyle.Colors.primaryAccent.opacity(0.95))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .onTapGesture {
            // Start task navigation (all events are task events now)
            if let task = event.task, let project = project {
                startTask(task, project: project)
            } else {
                // Fallback to generic start
                onStart()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeOut(duration: 0.15), value: showConfirmation)
    }
    
    private func startTask(_ task: ProjectTask, project: Project) {
        // Update task status to in progress using centralized function
        if task.status != .inProgress {
            Task {
                do {
                    try await dataController.updateTaskStatus(task: task, to: .inProgress)
                } catch {
                    print("[EVENT_CAROUSEL] ❌ Failed to update task status: \(error)")
                }
            }
        }

        // Post notification to start routing to task location
        NotificationCenter.default.post(
            name: Notification.Name("StartTaskNavigation"),
            object: nil,
            userInfo: [
                "taskId": task.id,
                "projectId": project.id
            ]
        )
        
        // Enter project mode for the task's project and set active task ID
        appState.activeTaskID = task.id
        appState.enterProjectMode(projectID: project.id)
    }
    
    private func navigateToTask(_ task: ProjectTask) {
        // Check if we have the project
        guard let project = project else { return }
        
        // Create task detail info with just IDs
        let taskDetail = TaskDetailInfo(taskId: task.id, projectId: project.id)
        
        // Post notification to show task details
        let userInfo: [String: Any] = [
            "taskID": task.id,
            "projectID": project.id
        ]
        
        NotificationCenter.default.post(
            name: Notification.Name("ShowCalendarTaskDetails"),
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func extractAddressComponents(_ address: String) -> String {
        let components = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if components.count >= 2 {
            return "\(components[0]), \(components[1])"
        }
        return address
    }
}

// Haptic feedback helper
extension EventCarousel {
    enum HapticFeedback {
        static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
        
        static func longPressSuccess() {
            // Heavy impact followed by success notification
            impact(.heavy)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.success)
            }
        }
    }
}