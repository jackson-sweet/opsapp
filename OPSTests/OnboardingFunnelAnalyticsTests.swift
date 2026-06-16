//
//  OnboardingFunnelAnalyticsTests.swift
//  OPSTests
//
//  Onboarding rebuild P6 — the funnel instrumentation (spec §8).
//
//  The funnel is instrumented at the GATEWAY (gateway-observe), with every
//  non-trivial decision pushed into pure value types so they are unit-testable
//  without a render:
//    • `OnboardingFlowStep.analyticsId` — the stable funnel step id (parameterised
//      cases collapse to their base id).
//    • `OnboardingFunnelPath.from(role:)` — owner / crew / unknown derivation.
//    • `OnboardingFunnelTracker` — the once-per-entry `step_viewed` guard, the
//      viewed-step count, and the completed/abandoned event payloads.
//
//  This file exercises ALL of that directly. The gateway's firing surface (the
//  `.onAppear` + `.onChange` + terminal calls) is the thin translation of these
//  pure outputs into `AnalyticsService.shared.track`, and is not separately unit-
//  tested — there is no logic there beyond calling the tracker and unwrapping the
//  returned event.
//

import XCTest
@testable import OPS

final class OnboardingFunnelAnalyticsTests: XCTestCase {

    // MARK: - step.analyticsId (stable, parameter-free)

    func testAnalyticsIdForEverySimpleStep() {
        XCTAssertEqual(OnboardingFlowStep.welcome.analyticsId, "welcome")
        XCTAssertEqual(OnboardingFlowStep.login.analyticsId, "login")
        XCTAssertEqual(OnboardingFlowStep.rolePick.analyticsId, "rolePick")
        XCTAssertEqual(OnboardingFlowStep.createAccount.analyticsId, "createAccount")
        XCTAssertEqual(OnboardingFlowStep.companyName.analyticsId, "companyName")
        XCTAssertEqual(OnboardingFlowStep.crewCode.analyticsId, "crewCode")
        XCTAssertEqual(OnboardingFlowStep.inviteCheck.analyticsId, "inviteCheck")
        XCTAssertEqual(OnboardingFlowStep.invitePicker.analyticsId, "invitePicker")
        XCTAssertEqual(OnboardingFlowStep.profile.analyticsId, "profile")
        XCTAssertEqual(OnboardingFlowStep.emergencyContact.analyticsId, "emergencyContact")
        XCTAssertEqual(OnboardingFlowStep.completionGate.analyticsId, "completionGate")
    }

    func testAnalyticsIdCollapsesCodeEntryProvenance() {
        // The funnel tracks WHICH screen — not the provenance that routed there.
        XCTAssertEqual(OnboardingFlowStep.codeEntry(provenance: .zeroInvites).analyticsId, "codeEntry")
        XCTAssertEqual(OnboardingFlowStep.codeEntry(provenance: .fromPicker).analyticsId, "codeEntry")
    }

    func testAnalyticsIdCollapsesConfirmCompanySource() {
        XCTAssertEqual(OnboardingFlowStep.confirmCompany(source: .picker).analyticsId, "confirmCompany")
        XCTAssertEqual(
            OnboardingFlowStep.confirmCompany(source: .codeEntry(.fromPicker)).analyticsId,
            "confirmCompany"
        )
    }

    /// The funnel id mirrors the persisted wire identifier for every simple case —
    /// the two surfaces read consistently. (Pinned so a drift between the analytics
    /// id and the wire format is caught.)
    func testAnalyticsIdMirrorsPersistedIdentifierForSimpleSteps() {
        let steps: [OnboardingFlowStep] = [
            .welcome, .login, .rolePick, .createAccount, .companyName, .crewCode,
            .inviteCheck, .invitePicker, .profile, .emergencyContact, .completionGate
        ]
        for step in steps {
            // Round-trip the step through Codable and read the persisted `step` key.
            let data = try! JSONEncoder().encode(step)
            let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(step.analyticsId, json["step"] as? String, "drift for \(step)")
        }
    }

    // MARK: - Path derivation

    func testPathFromRole() {
        XCTAssertEqual(OnboardingFunnelPath.from(role: .owner), .owner)
        XCTAssertEqual(OnboardingFunnelPath.from(role: .crew), .crew)
        XCTAssertEqual(OnboardingFunnelPath.from(role: nil), .unknown)
    }

    func testPathRawValues() {
        XCTAssertEqual(OnboardingFunnelPath.owner.rawValue, "owner")
        XCTAssertEqual(OnboardingFunnelPath.crew.rawValue, "crew")
        XCTAssertEqual(OnboardingFunnelPath.unknown.rawValue, "unknown")
    }

    // MARK: - step_viewed: fires once per entry, with the right payload

    func testStepEntryEmitsStepViewedWithStepAndPath() {
        var tracker = OnboardingFunnelTracker()
        let event = tracker.recordStepEntry(step: .welcome, path: .unknown)

        XCTAssertEqual(event?.type, .lifecycle)
        XCTAssertEqual(event?.name, "onboarding_step_viewed")
        XCTAssertEqual(event?.properties["step"], .string("welcome"))
        XCTAssertEqual(event?.properties["path"], .string("unknown"))
        XCTAssertNil(event?.durationMs)
    }

    func testStepViewedCarriesTheDerivedPath() {
        var tracker = OnboardingFunnelTracker()
        let event = tracker.recordStepEntry(step: .companyName, path: .owner)
        XCTAssertEqual(event?.properties["step"], .string("companyName"))
        XCTAssertEqual(event?.properties["path"], .string("owner"))
    }

    func testStepEntryIsDedupedForTheSameStep() {
        // The initial-appear + first-onChange double-fire (and any re-render) must
        // collapse to a single `step_viewed` for the same step.
        var tracker = OnboardingFunnelTracker()
        XCTAssertNotNil(tracker.recordStepEntry(step: .welcome, path: .unknown))
        XCTAssertNil(tracker.recordStepEntry(step: .welcome, path: .unknown))
        XCTAssertNil(tracker.recordStepEntry(step: .welcome, path: .unknown))
    }

    func testGenuineTransitionReArmsAndFires() {
        var tracker = OnboardingFunnelTracker()
        XCTAssertNotNil(tracker.recordStepEntry(step: .welcome, path: .unknown))
        XCTAssertNotNil(tracker.recordStepEntry(step: .rolePick, path: .unknown))
        XCTAssertNotNil(tracker.recordStepEntry(step: .createAccount, path: .owner))
    }

    func testReturningToAStepAfterLeavingItFiresAgain() {
        // Back-navigation re-enters a step → that's a genuine new entry, fires.
        var tracker = OnboardingFunnelTracker()
        XCTAssertNotNil(tracker.recordStepEntry(step: .rolePick, path: .unknown))
        XCTAssertNotNil(tracker.recordStepEntry(step: .createAccount, path: .owner))
        XCTAssertNotNil(tracker.recordStepEntry(step: .rolePick, path: .owner)) // back
    }

    func testParameterOnlyChangeOnCodeEntryDoesNotRefire() {
        // `.codeEntry(.zeroInvites)` and `.codeEntry(.fromPicker)` are the SAME
        // screen — a provenance-only difference is not a new screen view.
        var tracker = OnboardingFunnelTracker()
        XCTAssertNotNil(tracker.recordStepEntry(step: .codeEntry(provenance: .zeroInvites), path: .crew))
        XCTAssertNil(tracker.recordStepEntry(step: .codeEntry(provenance: .fromPicker), path: .crew))
    }

    // MARK: - viewedStepCount

    func testViewedStepCountTracksDistinctEntries() {
        var tracker = OnboardingFunnelTracker()
        XCTAssertEqual(tracker.viewedStepCount, 0)
        _ = tracker.recordStepEntry(step: .welcome, path: .unknown)
        _ = tracker.recordStepEntry(step: .welcome, path: .unknown) // deduped
        XCTAssertEqual(tracker.viewedStepCount, 1)
        _ = tracker.recordStepEntry(step: .rolePick, path: .unknown)
        XCTAssertEqual(tracker.viewedStepCount, 2)
    }

    // MARK: - onboarding_completed

    func testCompletedEventCarriesPathStepCountAndDuration() {
        // Pin the clock so the duration is deterministic.
        var t: TimeInterval = 100.0
        var tracker = OnboardingFunnelTracker(now: { t })

        _ = tracker.recordStepEntry(step: .welcome, path: .owner)      // startedAt = 100
        _ = tracker.recordStepEntry(step: .rolePick, path: .owner)
        _ = tracker.recordStepEntry(step: .createAccount, path: .owner)
        t = 142.5                                                       // +42.5s

        let event = tracker.completedEvent(path: .owner)
        XCTAssertEqual(event.type, .lifecycle)
        XCTAssertEqual(event.name, "onboarding_completed")
        XCTAssertEqual(event.properties["path"], .string("owner"))
        XCTAssertEqual(event.properties["step_count"], .int(3))
        XCTAssertEqual(event.durationMs, 42_500)
    }

    func testCompletedEventDurationIsNilWhenNoStepEverViewed() {
        // Defensive: an admit with no recorded step (no flow measured) → nil duration.
        let tracker = OnboardingFunnelTracker(now: { 0 })
        let event = tracker.completedEvent(path: .crew)
        XCTAssertNil(event.durationMs)
        XCTAssertEqual(event.properties["step_count"], .int(0))
        XCTAssertEqual(event.properties["path"], .string("crew"))
    }

    // MARK: - onboarding_abandoned

    func testAbandonedEventCarriesLastStepAndPath() {
        let tracker = OnboardingFunnelTracker()
        let event = tracker.abandonedEvent(lastStep: .createAccount, path: .owner)
        XCTAssertEqual(event.type, .lifecycle)
        XCTAssertEqual(event.name, "onboarding_abandoned")
        XCTAssertEqual(event.properties["last_step"], .string("createAccount"))
        XCTAssertEqual(event.properties["path"], .string("owner"))
        XCTAssertNil(event.durationMs)
    }

    func testAbandonedLastStepCollapsesParameterisedStep() {
        let tracker = OnboardingFunnelTracker()
        let event = tracker.abandonedEvent(
            lastStep: .confirmCompany(source: .codeEntry(.fromPicker)),
            path: .crew
        )
        XCTAssertEqual(event.properties["last_step"], .string("confirmCompany"))
    }

    // MARK: - Property value → analytics value

    func testPropertyValueUnwrapsToAnalyticsValue() {
        XCTAssertEqual(OnboardingFunnelPropertyValue.string("x").analyticsValue as? String, "x")
        XCTAssertEqual(OnboardingFunnelPropertyValue.int(7).analyticsValue as? Int, 7)
    }
}
