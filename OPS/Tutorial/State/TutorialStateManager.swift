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

    /// The current tooltip description (optional)
    @Published var tooltipDescription: String? = nil

    /// Whether to show the tooltip
    @Published var showTooltip: Bool = false

    /// Whether the tutorial is paused (e.g., waiting for auto-advance)
    @Published var isPaused: Bool = false

    /// Whether to show the Continue button (after auto-advance timer completes)
    @Published var showContinueButton: Bool = false

    /// Current phase index (0-based position in flow)
    @Published var phaseIndex: Int = 0

    // MARK: - Timing Properties

    /// When the tutorial started
    @Published var startTime: Date?

    /// Total time to complete the tutorial (calculated on completion)
    @Published var completionTime: TimeInterval?

    /// When the current phase started (for per-phase duration tracking)
    var phaseStartTime: Date?

    // MARK: - Flow Configuration

    /// The type of tutorial flow (company creator or employee)
    let flowType: TutorialFlowType

    /// UUID generated per tutorial session for analytics grouping
    let sessionId: String = UUID().uuidString

    // MARK: - Analytics

    /// Accumulated per-phase analytics actions
    var phaseActions: [(phase: TutorialPhase, action: String, durationMs: Int)] = []

    /// Analytics service for recording phase events
    private let analyticsService = TutorialAnalyticsService()

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
    /// Only shown if completed in under 2 minutes (120 seconds)
    var showTimeInCompletion: Bool {
        guard let time = completionTime else { return false }
        return time < 120
    }

    /// Current elapsed time since tutorial start
    var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Total number of phases in the current flow
    var totalPhases: Int {
        TutorialPhase.phaseOrder(for: flowType).count
    }

    /// Progress fraction for the progress bar (0.0 to 1.0)
    var progressFraction: CGFloat {
        guard totalPhases > 0 else { return 0 }
        return CGFloat(phaseIndex) / CGFloat(totalPhases)
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
        phaseStartTime = Date()
        phaseIndex = 0
        phaseActions = []
        currentPhase = TutorialPhase.firstPhase(for: flowType)
        highestPhaseReached = currentPhase
        updateForCurrentPhase()

        // Handle auto-advancing phases (truly auto-advance, no user action)
        if currentPhase.autoAdvances {
            scheduleAutoAdvance()
        }
        // Handle phases that show Continue button after a delay
        else if currentPhase.showsContinueButtonAfterDelay {
            scheduleContinueButton()
        }
    }

    /// Advances to the next phase
    func advancePhase() {
        // Record "completed" action for current phase before advancing
        recordPhaseAction("completed")

        // Cancel any pending auto-advance
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil

        // Hide continue button
        showContinueButton = false

        guard let nextPhase = currentPhase.next(for: flowType) else {
            complete()
            return
        }

        // If the next phase is .completed, call complete() to calculate completion time
        if nextPhase == .completed {
            complete()
            return
        }

        currentPhase = nextPhase
        updatePhaseIndex()
        updateForCurrentPhase()

        // Handle auto-advancing phases (truly auto-advance, no user action)
        if currentPhase.autoAdvances {
            scheduleAutoAdvance()
        }
        // Handle phases that show Continue button after a delay
        else if currentPhase.showsContinueButtonAfterDelay {
            scheduleContinueButton()
        }
        // Handle phases that show Continue button immediately (with brief delay for transition)
        else if currentPhase.showsContinueButtonImmediately {
            // Small delay to let the view transition complete before showing button
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
                self.showContinueButton = true
            }
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
        } else if currentPhase.showsContinueButtonAfterDelay {
            scheduleContinueButton()
        } else if currentPhase.showsContinueButtonImmediately {
            showContinueButton = true
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
        highestPhaseReached = .notStarted
        isActive = false
        showSwipeHint = false
        swipeDirection = .right
        currentCutout = .zero
        tooltipText = ""
        showTooltip = false
        isPaused = false
        showContinueButton = false
        startTime = nil
        completionTime = nil
        phaseIndex = 0
        phaseStartTime = nil
        phaseActions = []
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
        // Reset phase timing
        phaseStartTime = Date()

        // Update tooltip (use flow-specific copy where applicable)
        tooltipText = currentPhase.tooltipText(for: flowType)
        tooltipDescription = currentPhase.tooltipDescription(for: flowType)
        showTooltip = !tooltipText.isEmpty

        // Update swipe hint
        showSwipeHint = currentPhase.showsSwipeHint
        if let direction = currentPhase.swipeDirection {
            swipeDirection = direction
        }

        // Light haptic on phase change
        TutorialHaptics.lightTap()
    }

    /// Schedules auto-advancing to the next phase after a delay (no user action needed)
    private func scheduleAutoAdvance() {
        isPaused = true
        showContinueButton = false
        let delay = currentPhase.autoAdvanceDelay

        autoAdvanceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if !Task.isCancelled {
                isPaused = false
                // Actually advance to next phase
                advancePhase()
            }
        }
    }

    /// Schedules showing the Continue button after a delay
    private func scheduleContinueButton() {
        isPaused = true
        showContinueButton = false
        let delay = currentPhase.autoAdvanceDelay

        autoAdvanceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if !Task.isCancelled {
                isPaused = false
                showContinueButton = true
            }
        }
    }

    /// Called when user taps Continue button
    func continueFromAutoAdvance() {
        showContinueButton = false
        TutorialHaptics.lightTap()
        advancePhase()
    }

    /// Navigate to previous phase using phase order array
    func goBack() {
        let order = TutorialPhase.phaseOrder(for: flowType)
        guard phaseIndex > 0 else { return }

        // Record "skipped" for current phase (going back means abandoning it)
        recordPhaseAction("skipped")

        // Cancel any pending auto-advance
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        showContinueButton = false

        let previousIndex = phaseIndex - 1
        currentPhase = order[previousIndex]
        phaseIndex = previousIndex
        updateForCurrentPhase()

        // Handle auto-advancing/continue phases
        if currentPhase.autoAdvances {
            scheduleAutoAdvance()
        } else if currentPhase.showsContinueButtonAfterDelay {
            scheduleContinueButton()
        } else if currentPhase.showsContinueButtonImmediately {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.showContinueButton = true
            }
        }
    }

    /// Skip the current phase without completing the action
    func skipPhase() {
        recordPhaseAction("skipped")
        TutorialHaptics.lightTap()

        // Cancel any pending auto-advance
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        showContinueButton = false

        guard let nextPhase = currentPhase.next(for: flowType) else {
            complete()
            return
        }

        if nextPhase == .completed {
            complete()
            return
        }

        currentPhase = nextPhase
        updatePhaseIndex()
        updateForCurrentPhase()

        if currentPhase.autoAdvances {
            scheduleAutoAdvance()
        } else if currentPhase.showsContinueButtonAfterDelay {
            scheduleContinueButton()
        } else if currentPhase.showsContinueButtonImmediately {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.showContinueButton = true
            }
        }
    }

    /// Record drop-off when tutorial is abandoned without completion
    func recordDropOff() {
        guard isActive, currentPhase != .completed, currentPhase != .notStarted else { return }
        let durationMs = Int((phaseStartTime.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
        let totalElapsedMs = Int(elapsedTime * 1000)

        Task {
            await analyticsService.recordPhaseAction(
                phase: "\(currentPhase)",
                phaseIndex: phaseIndex,
                action: "dropped_off",
                durationMs: durationMs,
                totalElapsedMs: totalElapsedMs,
                flowType: flowType.rawValue,
                sessionId: sessionId,
                userId: nil
            )
        }
    }

    // MARK: - Private Analytics

    /// Record an action for the current phase and send to analytics
    private func recordPhaseAction(_ action: String) {
        let durationMs = Int((phaseStartTime.map { Date().timeIntervalSince($0) } ?? 0) * 1000)
        let totalElapsedMs = Int(elapsedTime * 1000)

        phaseActions.append((phase: currentPhase, action: action, durationMs: durationMs))

        Task {
            await analyticsService.recordPhaseAction(
                phase: "\(currentPhase)",
                phaseIndex: phaseIndex,
                action: action,
                durationMs: durationMs,
                totalElapsedMs: totalElapsedMs,
                flowType: flowType.rawValue,
                sessionId: sessionId,
                userId: nil
            )
        }
    }

    /// Update phaseIndex from phase order array
    private func updatePhaseIndex() {
        let order = TutorialPhase.phaseOrder(for: flowType)
        if let index = order.firstIndex(of: currentPhase) {
            phaseIndex = index
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
