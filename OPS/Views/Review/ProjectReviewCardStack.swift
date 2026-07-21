//
//  ProjectReviewCardStack.swift
//  OPS
//

import SwiftUI

/// Four-direction Payment Review stack. A committed gesture locks the outgoing
/// card, but the card only leaves after the authoritative action resolves.
struct ProjectReviewCardStack: View {
    let projects: [Project]
    let financialsByProjectID: [String: PaymentReviewFinancialSummary]
    let accessPolicy: PaymentReviewAccessPolicy
    let onSwipe: (Project, SwipeDirection, @escaping (Bool) -> Void) -> Void
    let onAdvance: (Project) -> Void
    let onTapCard: (Project) -> Void

    @State private var currentIndex = 0
    @State private var dragOffset: CGSize = .zero
    @State private var dragDirection: SwipeDirection?
    @State private var hasTriggeredThresholdHaptic = false
    @State private var isCommitting = false
    @State private var activeCommitID: UUID?
    @State private var commitOpacity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let swipeThreshold: CGFloat = 120
    private let maxVisibleCards = 3

    private var stackShiftAnimation: Animation { OPSStyle.Animation.panel }
    private var snapBackAnimation: Animation? {
        reduceMotion ? nil : OPSStyle.Animation.hover
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(visibleIndices.reversed().enumerated()), id: \.element) { _, index in
                    let project = projects[index]
                    let relativeIndex = index - currentIndex

                    ZStack {
                        SwipeCardView(
                            project: project,
                            daysSinceCompleted: OverdueProjectDetector.daysSinceCompleted(project),
                            financialSummary: financials(for: project),
                            onTap: { onTapCard(project) }
                        )

                        if index == currentIndex, let direction = dragDirection {
                            SwipeStampOverlay(
                                direction: direction,
                                progress: swipeProgress,
                                actionConfig: actionConfig(for: direction)
                            )
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale(for: relativeIndex))
                    .offset(y: yOffset(for: relativeIndex))
                    .offset(index == currentIndex ? dragOffset : .zero)
                    .rotationEffect(index == currentIndex ? dragRotation : .zero)
                    .opacity(index == currentIndex ? commitOpacity : 1)
                    .zIndex(Double(projects.count - index))
                    .allowsHitTesting(index == currentIndex && !isCommitting)
                    .gesture(index == currentIndex && !isCommitting ? dragGesture : nil)
                    .animation(reduceMotion ? nil : stackShiftAnimation, value: currentIndex)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: project))
                    .accessibilityValue(accessibilityValue(for: project))
                    .accessibilityHint("Open project details or choose a review action")
                    .accessibilityAddTraits(index == currentIndex ? .isButton : [])
                    .accessibilityHidden(index != currentIndex)
                    .accessibilityActions {
                        if index == currentIndex {
                            Button("PROJECT DETAILS") { onTapCard(project) }
                            ForEach(allowedDirections(for: project), id: \.self) { direction in
                                Button(actionConfig(for: direction).label) {
                                    beginAction(direction)
                                }
                            }
                        }
                    }
                    .modifier(WizardTargetModifier(
                        stepIds: index == currentIndex
                            ? ["payment_demo_swipe_right", "payment_demo_swipe_left", "payment_demo_swipe_up", "payment_demo_swipe_down"]
                            : [],
                        style: .button
                    ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var visibleIndices: [Int] {
        let end = min(currentIndex + maxVisibleCards, projects.count)
        guard currentIndex < end else { return [] }
        return Array(currentIndex..<end)
    }

    private func scale(for relativeIndex: Int) -> CGFloat {
        1 - CGFloat(relativeIndex) * 0.05
    }

    private func yOffset(for relativeIndex: Int) -> CGFloat {
        CGFloat(relativeIndex) * OPSStyle.Layout.spacing2
    }

    private var dragRotation: Angle {
        reduceMotion ? .zero : .degrees(Double(dragOffset.width) / 20)
    }

    private var swipeProgress: CGFloat {
        min(max(abs(dragOffset.width), abs(dragOffset.height)) / swipeThreshold, 1)
    }

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
                let direction = computeDirection(from: value.translation)
                let magnitude = max(abs(value.translation.width), abs(value.translation.height))
                guard magnitude > swipeThreshold, let direction else {
                    resetDrag()
                    return
                }
                guard let project = currentProject,
                      allowedDirections(for: project).contains(direction) else {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    resetDrag()
                    return
                }
                beginAction(direction)
            }
    }

    private var currentProject: Project? {
        guard projects.indices.contains(currentIndex) else { return nil }
        return projects[currentIndex]
    }

    private func beginAction(_ direction: SwipeDirection) {
        guard !isCommitting,
              let project = currentProject,
              allowedDirections(for: project).contains(direction) else { return }

        isCommitting = true
        let commitID = UUID()
        activeCommitID = commitID
        dragDirection = nil
        withAnimation(snapBackAnimation) {
            dragOffset = .zero
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        onSwipe(project, direction) { shouldAdvance in
            Task { @MainActor in
                resolveAction(
                    shouldAdvance,
                    project: project,
                    direction: direction,
                    commitID: commitID
                )
            }
        }
    }

    private func resolveAction(
        _ shouldAdvance: Bool,
        project: Project,
        direction: SwipeDirection,
        commitID: UUID
    ) {
        guard isCommitting, activeCommitID == commitID else { return }
        // A retry or a duplicated async callback must never advance twice.
        activeCommitID = nil
        guard shouldAdvance else {
            dragOffset = .zero
            dragDirection = nil
            commitOpacity = 1
            isCommitting = false
            return
        }

        withAnimation(OPSStyle.Animation.hover, completionCriteria: .logicallyComplete) {
            if reduceMotion {
                commitOpacity = 0
            } else {
                dragOffset = flyAwayOffset(for: direction)
            }
        } completion: {
            guard isCommitting else { return }
            currentIndex += 1
            dragOffset = .zero
            dragDirection = nil
            commitOpacity = 1
            isCommitting = false
            onAdvance(project)
        }
    }

    private func resetDrag() {
        withAnimation(snapBackAnimation) {
            dragOffset = .zero
            dragDirection = nil
        }
    }

    private func financials(for project: Project) -> PaymentReviewFinancialSummary? {
        financialsByProjectID[project.id]
    }

    private func projectAccessIDs(_ project: Project) -> [String] {
        project.getTeamMemberIds() + project.tasks.flatMap { $0.getTeamMemberIds() }
    }

    private func allowedDirections(for project: Project) -> [SwipeDirection] {
        let allowed = accessPolicy.allowedDirections(
            projectTeamMemberIDs: projectAccessIDs(project),
            financials: financials(for: project)
        )
        return SwipeDirection.allCases.filter(allowed.contains)
    }

    private func actionConfig(for direction: SwipeDirection) -> SwipeActionConfig {
        switch direction {
        case .right:
            return SwipeActionConfig(
                label: "CLOSE PROJECT",
                icon: direction.icon,
                color: direction.color
            )
        case .left:
            return SwipeActionConfig(
                label: "SKIP",
                icon: direction.icon,
                color: direction.color
            )
        case .up:
            return SwipeActionConfig(
                label: "QUEUE REMINDER",
                icon: direction.icon,
                color: direction.color
            )
        case .down:
            return SwipeActionConfig(
                label: "WRITE OFF & CLOSE",
                icon: direction.icon,
                color: direction.color
            )
        }
    }

    private func accessibilityLabel(for project: Project) -> String {
        "\(project.title), \(project.effectiveClientName)"
    }

    private func accessibilityValue(for project: Project) -> String {
        guard let summary = financials(for: project) else {
            return "Balance data unavailable"
        }
        if summary.hasUnresolvedInvoices && !summary.hasOutstandingInvoices {
            return "\(summary.unresolvedInvoiceCount) unresolved invoice, \(summary.unresolvedBalance.formatted(.currency(code: summary.currencyCode)))"
        }
        guard summary.hasOutstandingInvoices else {
            return "No outstanding invoice balance"
        }
        return "\(summary.outstandingInvoiceCount) outstanding, \(summary.outstandingBalance.formatted(.currency(code: summary.currencyCode)))"
    }

    private func computeDirection(from translation: CGSize) -> SwipeDirection? {
        let absW = abs(translation.width)
        let absH = abs(translation.height)
        guard max(absW, absH) > 20 else { return nil }
        if absW > absH {
            return translation.width > 0 ? .right : .left
        }
        return translation.height < 0 ? .up : .down
    }

    private func flyAwayOffset(for direction: SwipeDirection) -> CGSize {
        switch direction {
        case .right: return CGSize(width: 500, height: 0)
        case .left: return CGSize(width: -500, height: 0)
        case .up: return CGSize(width: 0, height: -700)
        case .down: return CGSize(width: 0, height: 700)
        }
    }
}
