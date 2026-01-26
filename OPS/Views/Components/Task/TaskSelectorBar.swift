//
//  TaskSelectorBar.swift
//  OPS
//
//  Minimal horizontal task switcher with swipe navigation and dropdown picker
//

import SwiftUI

/// Minimal task selector bar with swipe and tap-to-select functionality
///
/// Features:
/// - Compact pill showing current task color + type name
/// - Swipe left/right to advance between tasks
/// - Tap to show dropdown picker with all tasks
/// - "No task selected" state when none active
/// - Unsaved changes prompt before switching
struct TaskSelectorBar: View {
    @Binding var selectedTask: ProjectTask?
    let tasks: [ProjectTask]
    let hasUnsavedChanges: Bool
    let onSaveChanges: () -> Void

    // MARK: - State
    @State private var swipeOffset: CGFloat = 0
    @State private var showingTaskPicker: Bool = false
    @State private var showingUnsavedChangesAlert: Bool = false
    @State private var pendingTask: ProjectTask? = nil
    @State private var hasTriggeredHaptic: Bool = false

    // MARK: - Computed Properties
    private var sortedTasks: [ProjectTask] {
        tasks.sorted { $0.displayOrder < $1.displayOrder }
    }

    private var currentIndex: Int? {
        guard let selected = selectedTask else { return nil }
        return sortedTasks.firstIndex(where: { $0.id == selected.id })
    }

    private var canSwipeLeft: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }

    private var canSwipeRight: Bool {
        guard let index = currentIndex else { return !sortedTasks.isEmpty }
        return index < sortedTasks.count - 1
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background hint indicators
                HStack {
                    // Left indicator (previous task)
                    if canSwipeLeft {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .opacity(swipeOffset > 20 ? min(swipeOffset / 60, 1.0) : 0)
                    }

                    Spacer()

                    // Right indicator (next task)
                    if canSwipeRight {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .opacity(swipeOffset < -20 ? min(abs(swipeOffset) / 60, 1.0) : 0)
                    }
                }
                .padding(.horizontal, 8)

                // Main pill
                taskPill
                    .offset(x: swipeOffset)
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                handleSwipeChanged(value: value, cardWidth: geometry.size.width)
                            }
                            .onEnded { value in
                                handleSwipeEnded(value: value, cardWidth: geometry.size.width)
                            }
                    )
            }
        }
        .frame(height: 44)
        .sheet(isPresented: $showingTaskPicker) {
            taskPickerSheet
        }
        .alert("Unsaved Changes", isPresented: $showingUnsavedChangesAlert) {
            Button("Save & Switch") {
                onSaveChanges()
                switchToTask(pendingTask)
            }
            Button("Discard & Switch", role: .destructive) {
                switchToTask(pendingTask)
            }
            Button("Cancel", role: .cancel) {
                pendingTask = nil
            }
        } message: {
            Text("You have unsaved changes. What would you like to do?")
        }
    }

    // MARK: - Task Pill
    private var taskPill: some View {
        Button(action: {
            showingTaskPicker = true
        }) {
            HStack(spacing: 10) {
                if let task = selectedTask {
                    // Task color indicator
                    Circle()
                        .fill(Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent)
                        .frame(width: 10, height: 10)

                    // Task name
                    Text(task.displayTitle.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    Spacer()

                    // Task position indicator
                    if let index = currentIndex {
                        Text("\(index + 1)/\(sortedTasks.count)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    // Dropdown chevron
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                } else {
                    // No task selected state
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Text("SELECT A TASK")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Spacer()

                    if !sortedTasks.isEmpty {
                        Text("\(sortedTasks.count) \(sortedTasks.count == 1 ? "TASK" : "TASKS")")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        selectedTask != nil ? Color(hex: selectedTask!.effectiveColor)?.opacity(0.3) ?? OPSStyle.Colors.cardBorder : OPSStyle.Colors.cardBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Task Picker Sheet
    private var taskPickerSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 8) {
                    // Deselect option
                    Button(action: {
                        attemptTaskSwitch(to: nil)
                        showingTaskPicker = false
                    }) {
                        HStack(spacing: 12) {
                            Circle()
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                                .frame(width: 10, height: 10)

                            Text("NO TASK SELECTED")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Spacer()

                            if selectedTask == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(selectedTask == nil ? OPSStyle.Colors.primaryAccent.opacity(0.1) : Color.clear)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider()
                        .background(OPSStyle.Colors.cardBorder)
                        .padding(.vertical, 4)

                    // Task options
                    ForEach(sortedTasks, id: \.id) { task in
                        Button(action: {
                            attemptTaskSwitch(to: task)
                            showingTaskPicker = false
                        }) {
                            HStack(spacing: 12) {
                                // Color indicator
                                Circle()
                                    .fill(Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent)
                                    .frame(width: 10, height: 10)

                                // Task info
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.displayTitle.uppercased())
                                        .font(OPSStyle.Typography.captionBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    Text(task.status.displayName.uppercased())
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(task.status.color)
                                }

                                Spacer()

                                // Selection indicator
                                if selectedTask?.id == task.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(selectedTask?.id == task.id ? OPSStyle.Colors.primaryAccent.opacity(0.1) : Color.clear)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("Select Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingTaskPicker = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Swipe Handling
    private func handleSwipeChanged(value: DragGesture.Value, cardWidth: CGFloat) {
        let horizontalDrag = abs(value.translation.width)
        let verticalDrag = abs(value.translation.height)

        // Only activate swipe if horizontal movement is dominant
        guard horizontalDrag > verticalDrag else { return }

        // Check if swipe direction is valid
        let isSwipingLeft = value.translation.width < 0
        let isSwipingRight = value.translation.width > 0

        if (isSwipingLeft && !canSwipeRight) || (isSwipingRight && !canSwipeLeft) {
            // Resistance when swiping in invalid direction
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                swipeOffset = value.translation.width * 0.2
            }
            return
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            swipeOffset = value.translation.width
        }

        // Haptic feedback at threshold
        let swipePercentage = abs(swipeOffset) / cardWidth
        if swipePercentage >= 0.3 && !hasTriggeredHaptic {
            #if !targetEnvironment(simulator)
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            #endif
            hasTriggeredHaptic = true
        }
    }

    private func handleSwipeEnded(value: DragGesture.Value, cardWidth: CGFloat) {
        let swipePercentage = abs(value.translation.width) / cardWidth

        // Reset haptic flag
        hasTriggeredHaptic = false

        if swipePercentage >= 0.3 {
            let isSwipingRight = value.translation.width > 0

            if isSwipingRight && canSwipeLeft {
                // Swipe right = previous task
                if let index = currentIndex, index > 0 {
                    attemptTaskSwitch(to: sortedTasks[index - 1])
                }
            } else if !isSwipingRight && canSwipeRight {
                // Swipe left = next task
                if let index = currentIndex, index < sortedTasks.count - 1 {
                    attemptTaskSwitch(to: sortedTasks[index + 1])
                } else if currentIndex == nil && !sortedTasks.isEmpty {
                    // No task selected, select first
                    attemptTaskSwitch(to: sortedTasks[0])
                }
            }
        }

        // Snap back to center
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            swipeOffset = 0
        }
    }

    // MARK: - Task Switching
    private func attemptTaskSwitch(to task: ProjectTask?) {
        if hasUnsavedChanges {
            pendingTask = task
            showingUnsavedChangesAlert = true
        } else {
            switchToTask(task)
        }
    }

    private func switchToTask(_ task: ProjectTask?) {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedTask = task
        }
        pendingTask = nil
    }
}
