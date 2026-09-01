//
//  DataControllerAuthSuppression.swift
//  OPSTests
//
//  `DataController.init` fires a one-shot `checkExistingAuth()` on a detached
//  Task. With no stored credentials that call falls through to Firebase session
//  restoration and then `clearAuthentication()`, which nils `currentUser`.
//
//  On a COLD process Firebase's first `restoreSession()` takes seconds, so the
//  teardown lands in the middle of whichever test happened to construct the
//  controller. Every production read guarded on `currentUser` — the calendar
//  load among them — then correctly refuses to serve a signed-out operator and
//  returns nothing, so the test fails with an unexplained empty result far from
//  the actual cause.
//
//  Fixtures used to race that teardown: seed `currentUser`, spin a RunLoop until
//  it went nil, re-seed. That loop gave up after 5 seconds and proceeded anyway,
//  which is precisely the failure — on the first test of a cold process the
//  clear had not landed yet (measured: the bound expired at 5.01s), so the
//  fixture re-seeded into a state the pending teardown promptly demolished
//  mid-test. Racing an unbounded async teardown is unwinnable.
//
//  So suppress it instead, deterministically. `checkExistingAuth()` returns
//  immediately when `is_authenticated` is set and onboarding is incomplete: no
//  Firebase, no keychain teardown, and none of the sync-manager / OneSignal /
//  permission-fetch side effects the fully-authenticated branch starts. Clearing
//  the stored ids additionally keeps the legacy-id migration branch — which
//  calls `clearAuthentication()` directly — from firing on whatever a previously
//  run test left behind in UserDefaults.
//
//  Install BEFORE constructing the `DataController`; call `restore()` when the
//  fixture dies so nothing leaks into sibling suites.
//

import Foundation

struct DataControllerAuthSuppression {

    /// Every key `checkExistingAuth()` consults before it decides to tear auth
    /// down, plus the one its early-return branch writes.
    private static let keys = [
        "user_id",
        "company_id",
        "is_authenticated",
        "onboarding_completed",
        "resume_onboarding"
    ]

    private let previous: [String: Any]

    /// Must be called BEFORE `DataController()`: its init spawns the auth Task
    /// straight away, and only the values present when that Task runs decide
    /// whether the teardown happens at all.
    init() {
        let defaults = UserDefaults.standard
        var captured: [String: Any] = [:]
        for key in Self.keys {
            if let value = defaults.object(forKey: key) { captured[key] = value }
        }
        previous = captured

        // No stored ids → the legacy-id migration branch cannot fire.
        defaults.removeObject(forKey: "user_id")
        defaults.removeObject(forKey: "company_id")
        // Authenticated + onboarding incomplete → `checkExistingAuth()` sets the
        // resume flag and returns before it can reach Firebase or the teardown.
        defaults.set(true, forKey: "is_authenticated")
        defaults.set(false, forKey: "onboarding_completed")
    }

    /// Puts every touched key back exactly as it was — including removing the
    /// ones that did not exist, so a full-suite run sees no residue.
    func restore() {
        let defaults = UserDefaults.standard
        for key in Self.keys {
            if let value = previous[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
