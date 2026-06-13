//
//  OnboardingFunnelAnalytics.swift
//  OPS
//
//  Onboarding rebuild P6 — the funnel instrumentation for the rebuilt flow.
//
//  The rebuilt flow's coordinator (`OnboardingFlowCoordinator`) is deliberately
//  dependency-free and fully unit-tested — it must NOT reach an analytics
//  singleton. So the funnel is instrumented at the GATEWAY (which already owns the
//  lifecycle and reaches `AnalyticsService`), and ALL of the non-trivial decisions
//  — the stable step id, the owner/crew/unknown path, and the once-per-entry guard
//  that stops `step_viewed` double-firing — live HERE as pure value types so they
//  are testable WITHOUT a render.
//
//  Events (spec §8):
//    • onboarding_step_viewed       — once per ENTRY to a step (initial appear +
//                                     each genuine `currentStep` change), props:
//                                     { step, path }.
//    • onboarding_completed         — the admit/handleComplete success, props:
//                                     { path, step_count, duration_ms }.
//    • onboarding_abandoned         — handleSignOut (bailed mid-flow), props:
//                                     { last_step, path }.
//  (`onboarding_completion_queued` fires from `CompletionGateView` on the `.queued`
//   outcome, and `onboarding_invite_check_failed` from `InviteCheckStepView` — both
//   are screen-local diagnostics, not gateway-observed, and are left where they are.)
//
//  The gateway holds ONE `OnboardingFunnelTracker` for the flow's lifetime and
//  calls `recordStepEntry` from the initial appear + the `currentStep` onChange,
//  and `completedPayload` / `abandonedPayload` at the terminal side effects. The
//  tracker mutates and returns the events to fire; the gateway does the actual
//  `AnalyticsService.shared.track` (it is the @MainActor firing surface).
//

import Foundation

// MARK: - Path

/// The funnel path the user is on, derived from the role they picked on S2.
/// `unknown` covers the pre-role-pick screens (welcome / login) — the role isn't
/// committed until a company exists (owner) or a join completes (crew), but for
/// the FUNNEL the picked role is the right segmentation: it's what splits the
/// owner vs crew conversion curves from S2 onward.
enum OnboardingFunnelPath: String, Equatable {
    case owner = "owner"
    case crew = "crew"
    case unknown = "unknown"

    /// Map the flow-local role choice into a funnel path. `nil` (not yet picked)
    /// → `.unknown`.
    static func from(role: OnboardingFlowRole?) -> OnboardingFunnelPath {
        switch role {
        case .owner: return .owner
        case .crew:  return .crew
        case .none:  return .unknown
        }
    }
}

// MARK: - Funnel events (the pure, testable output)

/// One funnel event the gateway should fire. The tracker emits these; the gateway
/// translates them into `AnalyticsService.shared.track` calls. Modelling the
/// events as values (rather than firing inside the tracker) keeps the tracker free
/// of the singleton and makes every decision — name, type, properties, and WHEN it
/// is emitted vs suppressed — assertable in a unit test.
struct OnboardingFunnelEvent: Equatable {
    let type: AnalyticsEventType
    let name: String
    let properties: [String: OnboardingFunnelPropertyValue]
    /// Only set on `onboarding_completed`.
    let durationMs: Int?

    init(
        type: AnalyticsEventType,
        name: String,
        properties: [String: OnboardingFunnelPropertyValue],
        durationMs: Int? = nil
    ) {
        self.type = type
        self.name = name
        self.properties = properties
        self.durationMs = durationMs
    }
}

/// A minimal property value union so the emitted events are `Equatable` for tests.
/// The gateway unwraps these into the `Any`-typed `AnalyticsService.track`
/// properties (which only ever stores String/Int/Double/Bool).
enum OnboardingFunnelPropertyValue: Equatable {
    case string(String)
    case int(Int)

    /// The raw value handed to `AnalyticsService.track(properties:)`.
    var analyticsValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let i):    return i
        }
    }
}

// MARK: - Tracker

/// The funnel state machine for ONE onboarding flow. Owns the once-per-entry
/// `step_viewed` guard, the viewed-step count, and the flow's start instant so
/// `onboarding_completed` can carry a duration + step count. A struct held in the
/// gateway's `@State` — value semantics keep it trivially testable (drive the
/// methods, assert the returned events) and the mutation-in-place is fine because
/// the gateway is the single caller on the main actor.
struct OnboardingFunnelTracker {

    /// The last step we fired `step_viewed` for. Guards the double-fire: the
    /// initial appear and the first `currentStep` `onChange` can both land on the
    /// SAME step, and a SwiftUI re-render can re-invoke the observer for an
    /// unchanged step — both must fire the event exactly ONCE. A genuine
    /// transition (different `analyticsId`) re-arms it.
    private var lastViewedStepId: String?

    /// How many DISTINCT step entries we've recorded — i.e. how many times
    /// `step_viewed` actually fired. Reported as `step_count` on completion.
    private(set) var viewedStepCount: Int = 0

    /// Monotonic clock reference for the flow's duration. Injected so tests can
    /// pin it; defaults to the process uptime (immune to wall-clock changes).
    private let now: () -> TimeInterval
    private var startedAt: TimeInterval?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    // MARK: Step entry

    /// Record an ENTRY to `step` on `path`. Returns the `onboarding_step_viewed`
    /// event to fire, or `nil` when this is a duplicate of the step already
    /// recorded (the once-per-entry guard) — the gateway fires only on a non-nil
    /// return.
    ///
    /// The guard keys off the step's `analyticsId`, so the parameterised cases
    /// (`.codeEntry`, `.confirmCompany`) re-fire only when the BASE step changes,
    /// not when only their provenance/source differs — the funnel tracks screens,
    /// and a same-screen provenance change is not a new screen view.
    mutating func recordStepEntry(
        step: OnboardingFlowStep,
        path: OnboardingFunnelPath
    ) -> OnboardingFunnelEvent? {
        let id = step.analyticsId
        guard id != lastViewedStepId else { return nil }
        lastViewedStepId = id
        viewedStepCount += 1
        if startedAt == nil { startedAt = now() }

        return OnboardingFunnelEvent(
            type: .lifecycle,
            name: "onboarding_step_viewed",
            properties: [
                "step": .string(id),
                "path": .string(path.rawValue)
            ]
        )
    }

    // MARK: Terminal events

    /// The `onboarding_completed` event for an admit on `path`. Carries the step
    /// count and — when the flow's start instant was captured (it always is, since
    /// the first `step_viewed` sets it before any admit) — the elapsed duration in
    /// milliseconds.
    func completedEvent(path: OnboardingFunnelPath) -> OnboardingFunnelEvent {
        OnboardingFunnelEvent(
            type: .lifecycle,
            name: "onboarding_completed",
            properties: [
                "path": .string(path.rawValue),
                "step_count": .int(viewedStepCount)
            ],
            durationMs: elapsedMs()
        )
    }

    /// The `onboarding_abandoned` event for a sign-out from `lastStep` on `path`.
    /// `lastStep` is the step the user was on when they bailed.
    func abandonedEvent(lastStep: OnboardingFlowStep, path: OnboardingFunnelPath) -> OnboardingFunnelEvent {
        OnboardingFunnelEvent(
            type: .lifecycle,
            name: "onboarding_abandoned",
            properties: [
                "last_step": .string(lastStep.analyticsId),
                "path": .string(path.rawValue)
            ]
        )
    }

    // MARK: Internals

    /// Elapsed time since the first recorded step entry, in whole milliseconds, or
    /// `nil` when no step has been recorded yet (no flow to measure).
    private func elapsedMs() -> Int? {
        guard let startedAt else { return nil }
        let seconds = max(0, now() - startedAt)
        return Int((seconds * 1000).rounded())
    }
}
