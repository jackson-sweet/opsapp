//
//  TutorialStateManager.swift
//  OPS
//
//  Central state manager for the interactive tutorial.
//  Tracks current phase, timing, cutout positions, and tooltip display.
//

import SwiftUI
import Combine

@MainActor
class TutorialStateManager: ObservableObject {

    // MARK: - Published Properties

    /// Current phase of the tutorial
    @Published var currentPhase: TutorialPhase = .notStarted

    /// Whether the tutorial is actively running
    @Published var isActive: Bool = false

    /// Whether to show the swipe hint indicator
    @Published var showSwipeHint: Bool = false

    /// Direction for swipe hint animation
    @Published var swipeDirection: TutorialSwipeDirection = .right

    /// The current cutout frame for the overlay
    @Published var currentCutout: CGRect = .zero

    /// The current tooltip text
    @Published var tooltipText: String = ""

    /// Whether to show the tooltip
    @Published var showTooltip: Bool = false

    /// Whether the tutorial is paused (e.g., waiting for auto-advance)
    @Published var isPaused: Bool = false

    // MARK: - Timing Properties

    /// When the tutorial started
    @Published var startTime: Date?

    /// Total time to complete the tutorial (calculated on completion)
    @Published var completionTime: TimeInterval?

    // MARK: - Flow Configuration

    /// The type of tutorial flow (company creator or employee)
    let flowType: TutorialFlowType

    // MARK: - Private Properties

    private var autoAdvanceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// Formatted completion time string (MM:SS)
    var formattedTime: String {
        guard let time = completionTime else { return "" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Whether to show completion time on the completion screen
    /// Only shown if completed in under 3 minutes (180 seconds)
    var showTimeInCompletion: Bool {
        guard let time = completionTime else { return false }
        return time < 180
    }

    /// Current elapsed time since tutorial start
    var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Initialization

    init(flowType: TutorialFlowType) {
        self.flowType = flowType
    }

    // MARK: - Lifecycle Methods

    /// Starts the tutorial
    func start() {
        isActive = true
        startTime = Date()
        currentPhase = TutorialPhase.firstPhase(for: flowType)
        updateForCurrentPhase()
    }

    /// Advances to the next phase
    func advancePhase() {
        // Cancel any pending auto-advance
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil

        guard let nextPhase = currentPhase.next(for: flowType) else {
            complete()
            return
        }

        currentPhase = nextPhase
        updateForCurrentPhase()

        // Handle auto-advancing phases
        if currentPhase.autoAdvances {
            scheduleAutoAdvance()
        }
    }

    /// Skips to a specific phase (for debugging/testing)
    func skipTo(phase: TutorialPhase) {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil

        currentPhase = phase
        updateForCurrentPhase()

        if currentPhase.autoAdvances {
            scheduleAutoAdvance()
        }
    }

    /// Completes the tutorial
    func complete() {
        guard let start = startTime else { return }

        completionTime = Date().timeIntervalSince(start)
        currentPhase = .completed
        isActive = false
        showSwipeHint = false
        showTooltip = false

        // Haptic feedback for completion
        TutorialHaptics.success()
    }

    /// Resets the tutorial state
    func reset() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil

        currentPhase = .notStarted
        isActive = false
        showSwipeHint = false
        swipeDirection = .right
        currentCutout = .zero
        tooltipText = ""
        showTooltip = false
        isPaused = false
        startTime = nil
        completionTime = nil
    }

    // MARK: - Cutout Management

    /// Sets the cutout frame with animation
    func setCutout(for frame: CGRect, padding: CGFloat = 8) {
        let paddedFrame = frame.insetBy(dx: -padding, dy: -padding)
        withAnimation(.easeInOut(duration: 0.3)) {
            currentCutout = paddedFrame
        }
    }

    /// Clears the cutout (full overlay)
    func clearCutout() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentCutout = .zero
        }
    }

    // MARK: - Private Methods

    /// Updates state for the current phase
    private func updateForCurrentPhase() {
        // Update tooltip
        tooltipText = currentPhase.tooltipText
        showTooltip = !tooltipText.isEmpty

        // Update swipe hint
        showSwipeHint = currentPhase.showsSwipeHint
        if let direction = currentPhase.swipeDirection {
            swipeDirection = direction
        }

        // Light haptic on phase change
        TutorialHaptics.lightTap()
    }

    /// Schedules auto-advance for phases that don't require user action
    private func scheduleAutoAdvance() {
        isPaused = true
        let delay = currentPhase.autoAdvanceDelay

        autoAdvanceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if !Task.isCancelled {
                isPaused = false
                advancePhase()
            }
        }
    }
}

// MARK: - Haptic Feedback

/// Centralized haptic feedback for tutorial interactions
struct TutorialHaptics {
    /// Light tap for general interactions
    static func lightTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium impact for significant actions (long press, drag drop)
    static func mediumImpact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Success notification for completions
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Error notification for invalid actions
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Warning notification
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
