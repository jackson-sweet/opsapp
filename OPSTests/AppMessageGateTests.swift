//
//  AppMessageGateTests.swift
//  OPSTests
//
//  Pure-logic tests for the Update Gate version/range/date/role evaluator.
//  No network, no UI — AppMessageGate is a pure function of (message, install,
//  platform, now, role).
//

import XCTest
@testable import OPS

final class AppMessageGateTests: XCTestCase {

    // Fixed reference instant so date-window tests are deterministic.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func iso(_ offsetSeconds: TimeInterval) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: now.addingTimeInterval(offsetSeconds))
    }

    private func make(
        id: String = "m1",
        messageType: String? = "announcement",
        dismissable: Bool? = true,
        targetUserTypes: [String]? = nil,
        appStoreUrl: String? = nil,
        createdAt: String? = nil,
        minimumVersion: String? = nil,
        maximumVersion: String? = nil,
        platform: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil
    ) -> AppMessageDTO {
        AppMessageDTO(
            id: id,
            active: true,
            title: "T",
            body: "B",
            messageType: messageType,
            dismissable: dismissable,
            targetUserTypes: targetUserTypes,
            appStoreUrl: appStoreUrl,
            createdAt: createdAt,
            minimumVersion: minimumVersion,
            maximumVersion: maximumVersion,
            platform: platform,
            startDate: startDate,
            endDate: endDate
        )
    }

    // MARK: - Semantic version comparison

    func test_semver_doubleDigitMinorBeatsSingleDigit() {
        XCTAssertEqual(AppMessageGate.semVerCompare("3.10.0", "3.9.0"), .orderedDescending)
        XCTAssertEqual(AppMessageGate.semVerCompare("3.9.0", "3.10.0"), .orderedAscending)
    }

    func test_semver_patchOrdering() {
        XCTAssertEqual(AppMessageGate.semVerCompare("3.0.3", "3.1.0"), .orderedAscending)
        XCTAssertEqual(AppMessageGate.semVerCompare("3.1.0", "3.0.3"), .orderedDescending)
    }

    func test_semver_equalAndZeroPadded() {
        XCTAssertEqual(AppMessageGate.semVerCompare("3.1.0", "3.1.0"), .orderedSame)
        // 3.1 and 3.1.0 are semantically equal — missing components are zero.
        XCTAssertEqual(AppMessageGate.semVerCompare("3.1", "3.1.0"), .orderedSame)
    }

    // MARK: - Range applicability (the spine)

    func test_applies_noConstraints_appliesToAnyInstall() {
        XCTAssertTrue(AppMessageGate.applies(make(), installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil))
    }

    func test_applies_maxOnly_belowMax_isForceUpdateTarget() {
        // Force-update model: block everyone below the fixed build (max).
        let m = make(maximumVersion: "3.1.0")
        XCTAssertTrue(AppMessageGate.applies(m, installedVersion: "3.0.3", platform: "ios", now: now, userRole: nil))
    }

    func test_applies_maxOnly_atMax_excluded_selfResolves() {
        // The user who updates to the fixed build falls out of range — wall clears.
        let m = make(maximumVersion: "3.1.0")
        XCTAssertFalse(AppMessageGate.applies(m, installedVersion: "3.1.0", platform: "ios", now: now, userRole: nil))
        XCTAssertFalse(AppMessageGate.applies(m, installedVersion: "3.2.0", platform: "ios", now: now, userRole: nil))
    }

    func test_applies_minOnly_inclusiveLowerBound() {
        let m = make(minimumVersion: "3.2.0")
        XCTAssertTrue(AppMessageGate.applies(m, installedVersion: "3.2.0", platform: "ios", now: now, userRole: nil))
        XCTAssertTrue(AppMessageGate.applies(m, installedVersion: "3.3.0", platform: "ios", now: now, userRole: nil))
        XCTAssertFalse(AppMessageGate.applies(m, installedVersion: "3.1.9", platform: "ios", now: now, userRole: nil))
    }

    func test_applies_fullRange_halfOpenInterval() {
        let m = make(minimumVersion: "3.0.0", maximumVersion: "3.2.0")
        XCTAssertTrue(AppMessageGate.applies(m, installedVersion: "3.1.0", platform: "ios", now: now, userRole: nil))
        XCTAssertFalse(AppMessageGate.applies(m, installedVersion: "3.2.0", platform: "ios", now: now, userRole: nil)) // == max excluded
        XCTAssertFalse(AppMessageGate.applies(m, installedVersion: "2.9.0", platform: "ios", now: now, userRole: nil)) // < min excluded
    }

    func test_applies_semanticBoundary_doubleDigit() {
        let m = make(maximumVersion: "3.9.0")
        XCTAssertTrue(AppMessageGate.applies(m, installedVersion: "3.8.5", platform: "ios", now: now, userRole: nil))
        XCTAssertFalse(AppMessageGate.applies(m, installedVersion: "3.10.0", platform: "ios", now: now, userRole: nil)) // 3.10 >= 3.9
    }

    // MARK: - Platform scoping

    func test_applies_platformMismatch_excluded() {
        XCTAssertFalse(AppMessageGate.applies(make(platform: "android"), installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil))
    }

    func test_applies_platformMatchOrAll() {
        XCTAssertTrue(AppMessageGate.applies(make(platform: "ios"), installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil))
        XCTAssertTrue(AppMessageGate.applies(make(platform: nil), installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil))
    }

    // MARK: - Schedule window

    func test_applies_beforeStart_excluded() {
        XCTAssertFalse(AppMessageGate.applies(make(startDate: iso(3600)), installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil))
    }

    func test_applies_afterEnd_excluded() {
        XCTAssertFalse(AppMessageGate.applies(make(endDate: iso(-3600)), installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil))
    }

    func test_applies_withinWindow_included() {
        let m = make(startDate: iso(-3600), endDate: iso(3600))
        XCTAssertTrue(AppMessageGate.applies(m, installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil))
    }

    // MARK: - Role targeting

    func test_applies_roleTargeted_matchAndMiss() {
        let m = make(targetUserTypes: ["admin", "owner"])
        XCTAssertTrue(AppMessageGate.applies(m, installedVersion: "3.0.0", platform: "ios", now: now, userRole: .admin))
        XCTAssertFalse(AppMessageGate.applies(m, installedVersion: "3.0.0", platform: "ios", now: now, userRole: .crew))
    }

    func test_applies_roleTargeted_unknownRole_includedForKillSwitchSafety() {
        // Pre-auth (role unknown): a targeted message still applies so a blocking
        // wall is never let through for someone we can't classify yet.
        let m = make(targetUserTypes: ["admin"])
        XCTAssertTrue(AppMessageGate.applies(m, installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil))
    }

    func test_applies_emptyTargets_appliesToAllRoles() {
        XCTAssertTrue(AppMessageGate.applies(make(targetUserTypes: []), installedVersion: "3.0.0", platform: "ios", now: now, userRole: .crew))
    }

    // MARK: - Resolution (blocking vs dismissable vs synthetic nudge)

    func test_resolve_blockingTakesPrecedence() {
        let blocking = make(id: "force", messageType: "mandatory_update", dismissable: false, maximumVersion: "3.1.0")
        let nudge = make(id: "nudge", messageType: "optional_update", dismissable: true, maximumVersion: "3.1.0")
        let r = AppMessageGate.resolve(messages: [nudge, blocking], installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil, storeVersion: nil, appStoreURL: nil)
        XCTAssertEqual(r.blocking?.id, "force")
        XCTAssertNil(r.dismissable)
    }

    func test_resolve_dismissableWhenNoBlocking() {
        let nudge = make(id: "nudge", messageType: "optional_update", dismissable: true, maximumVersion: "3.1.0")
        let r = AppMessageGate.resolve(messages: [nudge], installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil, storeVersion: nil, appStoreURL: nil)
        XCTAssertNil(r.blocking)
        XCTAssertEqual(r.dismissable?.id, "nudge")
    }

    func test_resolve_excludesNonApplicable_forceUpdateSelfResolved() {
        // Already-updated install: the force message no longer applies → no wall.
        let blocking = make(id: "force", messageType: "mandatory_update", dismissable: false, maximumVersion: "3.1.0")
        let r = AppMessageGate.resolve(messages: [blocking], installedVersion: "3.1.0", platform: "ios", now: now, userRole: nil, storeVersion: nil, appStoreURL: nil)
        XCTAssertNil(r.blocking)
        XCTAssertNil(r.dismissable)
    }

    func test_resolve_syntheticNudgeWhenStoreHasNewerVersion() {
        let r = AppMessageGate.resolve(messages: [], installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil, storeVersion: "3.2.0", appStoreURL: "https://apps.apple.com/app/id1")
        XCTAssertNil(r.blocking)
        XCTAssertEqual(r.dismissable?.messageType, "optional_update")
        XCTAssertEqual(r.dismissable?.dismissable, true)
        XCTAssertEqual(r.dismissable?.appStoreUrl, "https://apps.apple.com/app/id1")
    }

    func test_resolve_noSyntheticNudgeWhenOnLatest() {
        let r = AppMessageGate.resolve(messages: [], installedVersion: "3.2.0", platform: "ios", now: now, userRole: nil, storeVersion: "3.2.0", appStoreURL: "https://apps.apple.com/app/id1")
        XCTAssertNil(r.blocking)
        XCTAssertNil(r.dismissable)
    }

    func test_resolve_publishedMessageWinsOverSyntheticNudge() {
        let published = make(id: "published", messageType: "optional_update", dismissable: true)
        let r = AppMessageGate.resolve(messages: [published], installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil, storeVersion: "3.2.0", appStoreURL: "https://apps.apple.com/app/id1")
        XCTAssertEqual(r.dismissable?.id, "published")
    }

    func test_resolve_higherPriorityBlockingChosen() {
        let maintenance = make(id: "maint", messageType: "maintenance", dismissable: false)
        let mandatory = make(id: "force", messageType: "mandatory_update", dismissable: false)
        let r = AppMessageGate.resolve(messages: [maintenance, mandatory], installedVersion: "3.0.0", platform: "ios", now: now, userRole: nil, storeVersion: nil, appStoreURL: nil)
        XCTAssertEqual(r.blocking?.id, "force")
    }
}
