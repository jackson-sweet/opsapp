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
    /// Optional authoritative action gate. When present, the card stays put and
    /// remains locked until the action reports success. A failure restores the
    /// card so the operator can retry.
    var swipeResolutionProvider: ((ProjectTask, SwipeDirection, @escaping (Bool) -> Void) -> Void)? = nil
    /// Per-row permission and state gate. When absent the legacy Task Review
    /// calendar rule remains in force.
    var directionAllowedProvider: ((ProjectTask, SwipeDirection) -> Bool)? = nil
    var onBlockedSwipe: ((ProjectTask, SwipeDirection) -> Void)? = nil
    var onAdvance: ((ProjectTask, SwipeDirection) -> Void)? = nil

    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var dragDirection: SwipeDirection? = nil
    @State private var hasTriggeredThresholdHaptic: Bool = false
    @State private var commitOpacity: Double = 1
    /// True from the moment a swipe commits until the fly-away animation
    /// completes — locks the outgoing card so a second drag cannot fire against
    /// the same index.
    @State private var isCommitting: Bool = false
    @State private var activeCommitID: UUID? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let swipeThreshold: CGFloat = 120
    private let maxVisibleCards: Int = 3

    /// Stack shift uses the canonical 200ms OPS panel transition.
    private var stackShiftAnimation: Animation {
        OPSStyle.Animation.panel
    }

    /// Snap-back uses the canonical interaction transition; Reduce Motion
    /// removes the transform animation entirely.
    private var snapBackAnimation: Animation? {
        reduceMotion ? nil : OPSStyle.Animation.hover
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(visibleIndices.reversed().enumerated()), id: \.element) { _, index in
                    let relativeIndex = index - currentIndex

                    ZStack {
                        TaskSwipeCardView(
                            task: tasks[index],
                            scheduleStatus: scheduleStatus(for: tasks[index]),
                            onTap: { onTapCard(tasks[index]) },
                            badgeOverride: badgeProvider?(tasks[index])
                        )

                        if index == currentIndex,
                           let direction = dragDirection,
                           isDirectionAllowed(direction, for: tasks[index]) {
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
                    .opacity(index == currentIndex ? commitOpacity : 1)
                    .zIndex(Double(tasks.count - index))
                    .allowsHitTesting(index == currentIndex && !isCommitting)
                    .gesture(index == currentIndex && !isCommitting ? dragGesture : nil)
                    .accessibilityHidden(index != currentIndex)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(tasks[index].displayTitle)
                    .accessibilityValue(accessibilityValue(for: tasks[index], index: index))
                    .accessibilityHint("Open the Actions rotor for available review actions")
                    .accessibilityActions {
                        ForEach(accessibilityDirections(for: tasks[index], index: index), id: \.self) { direction in
                            let config = taskActionConfigProvider?(tasks[index], direction)
                                ?? actionConfigProvider(direction)
                            Button(config.label) {
                                requestSwipe(direction, for: tasks[index])
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : stackShiftAnimation, value: currentIndex)
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
        guard !reduceMotion else { return .zero }
        return .degrees(Double(dragOffset.width) / 20)
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
                let direction = computeDirection(from: value.translation)
                dragDirection = direction
                let magnitude = max(abs(value.translation.width), abs(value.translation.height))
                let directionIsAllowed = direction.map {
                    guard tasks.indices.contains(currentIndex) else { return false }
                    return isDirectionAllowed($0, for: tasks[currentIndex])
                } ?? false

                if directionIsAllowed,
                   magnitude >= swipeThreshold,
                   !hasTriggeredThresholdHaptic {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    hasTriggeredThresholdHaptic = true
                } else if !directionIsAllowed || magnitude < swipeThreshold {
                    hasTriggeredThresholdHaptic = false
                }
            }
            .onEnded { value in
                hasTriggeredThresholdHaptic = false
                let translation = value.translation
                let direction = computeDirection(from: translation)
                let magnitude = max(abs(translation.width), abs(translation.height))

                if magnitude > swipeThreshold, let dir = direction {
                    guard tasks.indices.contains(currentIndex) else { return }
                    let task = tasks[currentIndex]
                    if !isDirectionAllowed(dir, for: task) {
                        withAnimation(snapBackAnimation) {
                            dragOffset = .zero
                            dragDirection = nil
                        }
                        onBlockedSwipe?(task, dir)
                        return
                    }

                    commitSwipe(dir)
                } else {
                    withAnimation(snapBackAnimation) {
                        dragOffset = .zero
                        dragDirection = nil
                    }
                }
            }
    }

    private func commitSwipe(_ direction: SwipeDirection) {
        guard !isCommitting, tasks.indices.contains(currentIndex) else { return }

        // Capture the outgoing task before animation. Parent data updates may
        // remove it from live Job Board queries as soon as onSwipe runs.
        let task = tasks[currentIndex]
        guard isDirectionAllowed(direction, for: task) else {
            onBlockedSwipe?(task, direction)
            return
        }
        isCommitting = true
        let commitID = UUID()
        activeCommitID = commitID
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if let swipeResolutionProvider {
            swipeResolutionProvider(task, direction) { didSucceed in
                Task { @MainActor in
                    resolveSwipe(
                        didSucceed,
                        task: task,
                        direction: direction,
                        commitID: commitID,
                        invokesLegacyHandler: false
                    )
                }
            }
        } else {
            resolveSwipe(
                true,
                task: task,
                direction: direction,
                commitID: commitID,
                invokesLegacyHandler: true
            )
        }
    }

    private func requestSwipe(_ direction: SwipeDirection, for task: ProjectTask) {
        guard tasks.indices.contains(currentIndex), tasks[currentIndex].id == task.id else { return }
        guard isDirectionAllowed(direction, for: task) else {
            onBlockedSwipe?(task, direction)
            return
        }
        commitSwipe(direction)
    }

    private func resolveSwipe(
        _ didSucceed: Bool,
        task: ProjectTask,
        direction: SwipeDirection,
        commitID: UUID,
        invokesLegacyHandler: Bool
    ) {
        guard isCommitting, activeCommitID == commitID else { return }
        // Consume this resolver immediately. Network callbacks and sheet
        // dismissal callbacks can race; only the first result may move or
        // restore the frozen outgoing card.
        activeCommitID = nil

        guard didSucceed else {
            withAnimation(snapBackAnimation) {
                dragOffset = .zero
                dragDirection = nil
                commitOpacity = 1
            }
            isCommitting = false
            return
        }

        let flyAway = flyAwayOffset(for: direction)
        withAnimation(OPSStyle.Animation.hover, completionCriteria: .logicallyComplete) {
            if reduceMotion {
                commitOpacity = 0
            } else {
                dragOffset = flyAway
            }
        } completion: {
            guard isCommitting else { return }
            currentIndex += 1
            dragOffset = .zero
            dragDirection = nil
            commitOpacity = 1
            isCommitting = false
            if invokesLegacyHandler {
                onSwipe(task, direction)
            }
            onAdvance?(task, direction)
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

    private func isDirectionAllowed(_ direction: SwipeDirection, for task: ProjectTask) -> Bool {
        if let directionAllowedProvider {
            return directionAllowedProvider(task, direction)
        }
        let effectiveBlocked = blockedDirections.union(hasCalendarAccess ? [] : [.up])
        return !effectiveBlocked.contains(direction)
    }

    private func accessibilityDirections(for task: ProjectTask, index: Int) -> [SwipeDirection] {
        guard index == currentIndex, !isCommitting else { return [] }
        let allowedDirections = SwipeDirection.allCases.filter {
            isDirectionAllowed($0, for: task)
        }
        return SwipeAccessibilityActionPolicy.uniqueDirections(
            allowedDirections,
            labelForDirection: { direction in
                (
                    taskActionConfigProvider?(task, direction)
                        ?? actionConfigProvider(direction)
                ).label
            }
        )
    }

    private func accessibilityValue(for task: ProjectTask, index: Int) -> String {
        let status: String
        if let badge = badgeProvider?(task)?.text {
            status = badge
        } else {
            switch scheduleStatus(for: task) {
            case .unscheduled:
                status = "Unscheduled"
            case .unassigned:
                status = "Unassigned"
            case .scheduledDaysAgo(let days):
                status = "Scheduled \(days) days ago"
            }
        }
        return "Card \(index + 1) of \(tasks.count). \(status)"
    }

    // MARK: - Helpers

    /// Compute the review-card badge state for a task.
    /// Unscheduled (no start/end dates) and unassigned (no crew) tasks are
    /// called out explicitly instead of being squashed into a meaningless
    /// "0 DAYS AGO" label when the underlying day count is zero.
    private func scheduleStatus(for task: ProjectTask) -> TaskScheduleStatus {
        // Prefer scheduled completion (endDate), fall back to startDate if unavailable
        guard let scheduledDate = task.endDate ?? task.startDate else {
            return .unscheduled
        }
        if task.getTeamMemberIds().isEmpty {
            return .unassigned
        }
        let days = max(0, Calendar.current.dateComponents([.day], from: scheduledDate, to: Date()).day ?? 0)
        return .scheduledDaysAgo(days)
    }
}
