//
//  TaskReviewCardStack.swift
//  OPS
//
//  Tinder-style card stack with 4-directional swipe for task completion review.
//  Mirrors ProjectReviewCardStack but uses ProjectTask and task-specific config.
//

import SwiftUI

struct TaskReviewCardStack: View {
    let tasks: [ProjectTask]
    let hasCalendarAccess: Bool
    let onSwipe: (ProjectTask, SwipeDirection) -> Void
    let onTapCard: (ProjectTask) -> Void
    var actionConfigProvider: (SwipeDirection) -> SwipeActionConfig = SwipeActionConfig.taskConfig
    /// Per-task config override — takes precedence over actionConfigProvider when set
    var taskActionConfigProvider: ((ProjectTask, SwipeDirection) -> SwipeActionConfig)? = nil
    var blockedDirections: Set<SwipeDirection> = []
    var badgeProvider: ((ProjectTask) -> (text: String, color: Color)?)? = nil

    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var dragDirection: SwipeDirection? = nil
    @State private var hasTriggeredThresholdHaptic: Bool = false

    private let swipeThreshold: CGFloat = 120
    private let maxVisibleCards: Int = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(visibleIndices.reversed().enumerated()), id: \.element) { _, index in
                    let relativeIndex = index - currentIndex

                    ZStack {
                        TaskSwipeCardView(
                            task: tasks[index],
                            scheduledDaysAgo: daysSinceScheduled(tasks[index]),
                            onTap: { onTapCard(tasks[index]) },
                            badgeOverride: badgeProvider?(tasks[index])
                        )

                        if index == currentIndex, let direction = dragDirection {
                            let config = taskActionConfigProvider?(tasks[index], direction) ?? actionConfigProvider(direction)
                            SwipeStampOverlay(
                                direction: direction,
                                progress: swipeProgress,
                                actionConfig: config
                            )
                        }
                    }
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .scaleEffect(scale(for: relativeIndex))
                    .offset(y: yOffset(for: relativeIndex))
                    .offset(index == currentIndex ? dragOffset : .zero)
                    .rotationEffect(index == currentIndex ? dragRotation : .zero)
                    .zIndex(Double(tasks.count - index))
                    .allowsHitTesting(index == currentIndex)
                    .gesture(index == currentIndex ? dragGesture : nil)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentIndex)
                    .modifier(WizardTargetModifier(
                        stepIds: index == currentIndex
                            ? ["task_demo_swipe_right", "task_demo_swipe_left", "task_demo_swipe_up"]
                            : [],
                        style: .button
                    ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Visible Cards

    private var visibleIndices: [Int] {
        let end = min(currentIndex + maxVisibleCards, tasks.count)
        guard currentIndex < end else { return [] }
        return Array(currentIndex..<end)
    }

    // MARK: - Card Positioning

    private func scale(for relativeIndex: Int) -> CGFloat {
        1.0 - CGFloat(relativeIndex) * 0.05
    }

    private func yOffset(for relativeIndex: Int) -> CGFloat {
        CGFloat(relativeIndex) * 12
    }

    private var dragRotation: Angle {
        .degrees(Double(dragOffset.width) / 20)
    }

    private var swipeProgress: CGFloat {
        let maxDrag = max(abs(dragOffset.width), abs(dragOffset.height))
        return min(maxDrag / swipeThreshold, 1.0)
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
                dragDirection = computeDirection(from: value.translation)
                let magnitude = max(abs(value.translation.width), abs(value.translation.height))
                if magnitude >= swipeThreshold && !hasTriggeredThresholdHaptic {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    hasTriggeredThresholdHaptic = true
                } else if magnitude < swipeThreshold {
                    hasTriggeredThresholdHaptic = false
                }
            }
            .onEnded { value in
                hasTriggeredThresholdHaptic = false
                let translation = value.translation
                let direction = computeDirection(from: translation)
                let magnitude = max(abs(translation.width), abs(translation.height))

                if magnitude > swipeThreshold, let dir = direction {
                    // Block UP swipe without calendar access (legacy behavior)
                    let effectiveBlocked = blockedDirections.union(hasCalendarAccess ? [] : [.up])
                    if effectiveBlocked.contains(dir) {
                        withAnimation(.spring()) {
                            dragOffset = .zero
                            dragDirection = nil
                        }
                        return
                    }

                    commitSwipe(dir)
                } else {
                    withAnimation(.spring()) {
                        dragOffset = .zero
                        dragDirection = nil
                    }
                }
            }
    }

    private func commitSwipe(_ direction: SwipeDirection) {
        let flyAway = flyAwayOffset(for: direction)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.easeIn(duration: 0.25)) {
            dragOffset = flyAway
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let task = tasks[currentIndex]
            currentIndex += 1
            dragOffset = .zero
            dragDirection = nil
            onSwipe(task, direction)
        }
    }

    // MARK: - Direction Detection

    private func computeDirection(from translation: CGSize) -> SwipeDirection? {
        let absW = abs(translation.width)
        let absH = abs(translation.height)
        guard max(absW, absH) > 20 else { return nil }

        if absW > absH {
            return translation.width > 0 ? .right : .left
        } else {
            return translation.height < 0 ? .up : .down
        }
    }

    private func flyAwayOffset(for direction: SwipeDirection) -> CGSize {
        switch direction {
        case .right: return CGSize(width: 500, height: 0)
        case .left:  return CGSize(width: -500, height: 0)
        case .up:    return CGSize(width: 0, height: -700)
        case .down:  return CGSize(width: 0, height: 700)
        }
    }

    // MARK: - Helpers

    private func daysSinceScheduled(_ task: ProjectTask) -> Int {
        guard let endDate = task.endDate else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: endDate, to: Date()).day ?? 0)
    }
}
