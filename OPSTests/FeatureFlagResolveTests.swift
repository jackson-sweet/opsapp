import XCTest
@testable import OPS

/// Bug d5c899e6 — "If I don't have reception, the deck tab is not showing up as
/// if it's trying to live-sync my permissions." Under flaky reception the
/// feature-flag fetch (two extra round-trips) drops out while the RBAC fetch
/// still succeeds. The flag layer used to fail closed on that drop and overwrite
/// good in-memory state, hiding DECK / pipeline / estimates / accounting for
/// entitled users until the next clean fetch. The fix: a failed flag fetch is
/// "unknown", so the last-known-good flags are preserved (cache-first). Absence
/// of a fresh permission fetch is not absence of permission.
///
/// This is the airplane-mode proof in unit form — it pins the exact mechanism
/// that hid the deck tab offline.
final class FeatureFlagResolveTests: XCTestCase {

    private func flags(disabled: Set<String>, blocked: Set<String> = []) -> FeatureFlagResult {
        FeatureFlagResult(blockedPermissions: blocked, disabledFlags: disabled)
    }

    // MARK: - resolve(): a failed fetch keeps last-known-good

    func testFailedFlagFetchPreservesLastKnownGood() {
        // Offline: no fresh flags. Last-known-good has deck_builder ENABLED
        // (it is NOT in the disabled set); pipeline happens to be off.
        let lastKnown = flags(disabled: ["pipeline"])
        let resolved = FeatureFlagService.resolve(fresh: nil, lastKnown: lastKnown)

        XCTAssertFalse(resolved.disabledFlags.contains("deck_builder"),
                       "a failed flag fetch must NOT disable deck_builder — the deck tab stays")
        XCTAssertEqual(resolved.disabledFlags, lastKnown.disabledFlags,
                       "last-known-good flag state is preserved verbatim when offline")
    }

    func testFreshFlagResultWinsWhenPresent() {
        // Online: a real result that turns deck_builder OFF must win — a flag that
        // genuinely went off has to hide.
        let lastKnown = flags(disabled: [])              // everything on
        let fresh = flags(disabled: ["deck_builder"])    // deck really off now
        let resolved = FeatureFlagService.resolve(fresh: fresh, lastKnown: lastKnown)

        XCTAssertTrue(resolved.disabledFlags.contains("deck_builder"),
                      "a present fresh result wins over last-known-good")
    }

    // MARK: - fail-closed is the danger the fix avoids

    func testFailClosedDisablesDeckBuilder() {
        // The fail-closed default (correct only on a truly empty cache) disables
        // deck_builder. Overwriting good state with this on every reception blip
        // was the reported bug — resolve() no longer does that.
        let failClosed = FeatureFlagService.failClosedResult()
        XCTAssertTrue(failClosed.disabledFlags.contains("deck_builder"))
    }

    // MARK: - end-to-end: deck tab visibility survives an offline blip

    func testDeckTabVisibilitySurvivesOfflineRefresh() {
        // A store whose last successful sync enabled deck_builder and granted the
        // crew-scoped deck_builder.view — exactly the state before reception drops.
        let store = PermissionStore()
        store.permissions = ["deck_builder.view": "assigned"]
        store.disabledFlags = []          // deck_builder enabled from cache
        store.blockedByFlags = []

        // Simulate an offline refresh: RBAC ok, flag fetch dropped → resolve keeps
        // the cached flag state instead of failing closed.
        let lastKnown = FeatureFlagResult(blockedPermissions: store.blockedByFlags,
                                          disabledFlags: store.disabledFlags)
        let resolved = FeatureFlagService.resolve(fresh: nil, lastKnown: lastKnown)
        store.disabledFlags = resolved.disabledFlags
        store.blockedByFlags = resolved.blockedPermissions

        // The exact gate ProjectDetailsView.visibleTabs uses for the deck tab.
        let deckTabVisible = store.isFeatureEnabled("deck_builder")
            && store.can("deck_builder.view", requiredScope: "assigned")
        XCTAssertTrue(deckTabVisible,
                      "deck tab stays visible offline when the cached flags enabled it")
    }
}
