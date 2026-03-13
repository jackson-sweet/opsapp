//
//  ProjectReviewCardStack.swift
//  OPS
//

import SwiftUI

/// Tinder-style card stack with 4-directional swipe.
struct ProjectReviewCardStack: View {
    let projects: [Project]
    let hasFinancialAccess: Bool
    let onSwipe: (Project, SwipeDirection) -> Void
    let onTapCard: (Project) -> Void

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
                        SwipeCardView(
                            project: projects[index],
                            daysSinceCompleted: OverdueProjectDetector.daysSinceCompleted(projects[index]),
                            showFinancialInfo: hasFinancialAccess,
                            onTap: { onTapCard(projects[index]) }
                        )

                        if index == currentIndex, let direction = dragDirection {
                            SwipeStampOverlay(
                                direction: direction,
                                progress: swipeProgress
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
                    .zIndex(Double(projects.count - index))
                    .allowsHitTesting(index == currentIndex)
                    .gesture(index == currentIndex ? dragGesture : nil)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentIndex)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Visible Cards

    private var visibleIndices: [Int] {
        let end = min(currentIndex + maxVisibleCards, projects.count)
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
                    // Block up/down without financial access
                    if (dir == .up || dir == .down) && !hasFinancialAccess {
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
            let project = projects[currentIndex]
            currentIndex += 1
            dragOffset = .zero
            dragDirection = nil
            onSwipe(project, direction)
        }
    }

    // MARK: - Direction Detection

    private func computeDirection(from translation: CGSize) -> SwipeDirection? {
        let absW = abs(translation.width)
        let absH = abs(translation.height)
        guard max(absW, absH) > 20 else { return nil } // Dead zone

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
}
