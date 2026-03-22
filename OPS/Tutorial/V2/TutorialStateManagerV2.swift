import SwiftUI

@MainActor
final class TutorialStateManagerV2: ObservableObject {

    @Published private(set) var currentPhase: TutorialPhaseV2 = .leadArrives
    @Published private(set) var isActive: Bool = false

    private var phaseStart: Date = .now
    private var tutorialStart: Date = .now
    private let sessionId = UUID().uuidString

    // MARK: - Lifecycle

    func start() {
        tutorialStart = .now
        phaseStart = .now
        currentPhase = .leadArrives
        isActive = true
        TutorialHaptics.prepare()
        recordAnalytics(action: "started_v2")
    }

    func advancePhase() {
        recordAnalytics(action: "step_completed", durationMs: phaseDurationMs)

        guard let next = currentPhase.next else {
            recordAnalytics(action: "completed_v2", totalElapsedMs: totalElapsedMs)
            isActive = false
            return
        }

        currentPhase = next
        phaseStart = .now
    }

    func skip() {
        recordAnalytics(action: "skipped_v2", totalElapsedMs: totalElapsedMs)
        isActive = false
    }

    func recordSwipe(cardIndex: Int, direction: String) {
        recordAnalytics(action: "review_swipe_\(direction)", durationMs: cardIndex)
    }

    func ctaTapped(action: String) {
        recordAnalytics(action: "cta_\(action)", totalElapsedMs: totalElapsedMs)
    }

    // MARK: - Private

    private var phaseDurationMs: Int {
        Int(Date.now.timeIntervalSince(phaseStart) * 1000)
    }

    private var totalElapsedMs: Int {
        Int(Date.now.timeIntervalSince(tutorialStart) * 1000)
    }

    private func recordAnalytics(action: String, durationMs: Int? = nil, totalElapsedMs: Int? = nil) {
        TutorialAnalytics.record(
            action: action,
            phase: currentPhase.name,
            phaseIndex: currentPhase.rawValue,
            durationMs: durationMs,
            totalElapsedMs: totalElapsedMs,
            sessionId: sessionId
        )
    }
}
