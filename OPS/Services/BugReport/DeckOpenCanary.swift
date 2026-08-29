//
//  DeckOpenCanary.swift
//  OPS
//
//  Crash evidence for bug 2fa645a8 (DECK tap on the lead dossier killing the
//  app). The 2026-08-19 watchdog investigation fixed both proven causes, but
//  a watchdog kill leaves nothing behind in-app: breadcrumbs are in-memory
//  and the process dies mid-transaction. This canary is a persisted marker,
//  armed at the DECK tap and disarmed when the deck screen demonstrably
//  settles. A relaunch that finds it armed files ONE auto bug-report row
//  (AutoBugReporter — client + server dedupe built in) naming how far the
//  open got before the process died.
//
//  Honesty notes:
//    - Backgrounding disarms it: iOS killing a background app is jetsam,
//      not this bug.
//    - A marker older than 24h is stale (device rebooted, battery died) and
//      is discarded, never filed.
//    - A user force-quitting within the settle window is a possible false
//      positive; the summary says "did not settle", not "crashed", and
//      dedupe collapses repeats.
//

import Foundation

enum DeckOpenCanary {

    enum Phase: String, Codable {
        /// DECK row tapped; push requested.
        case tapped
        /// LeadDeckScreen reached its first .task (first body committed).
        case screenAppeared
        /// DeckTabView resolved a design (or resolved none) and rendered.
        case designResolved
    }

    struct Armed: Codable, Equatable {
        let leadId: String
        var phase: Phase
        let armedAt: Date
    }

    static let defaultsKey = "deck_open_canary_v1"
    /// Beyond this age an armed marker is stale, not evidence.
    static let maxEvidenceAge: TimeInterval = 24 * 3600
    /// The screen is considered settled this long after the design resolves.
    static let settleDelay: TimeInterval = 3

    // MARK: - Pure state machine (tested directly)

    static func armed(from data: Data?) -> Armed? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Armed.self, from: data)
    }

    static func isEvidence(_ armed: Armed, now: Date) -> Bool {
        now.timeIntervalSince(armed.armedAt) < maxEvidenceAge
    }

    // MARK: - Store (UserDefaults)

    private static var defaults: UserDefaults { .standard }

    static func arm(leadId: String, now: Date = Date()) {
        let marker = Armed(leadId: leadId, phase: .tapped, armedAt: now)
        defaults.set(try? JSONEncoder().encode(marker), forKey: defaultsKey)
    }

    static func advance(_ phase: Phase) {
        guard var marker = armed(from: defaults.data(forKey: defaultsKey)) else { return }
        marker.phase = phase
        defaults.set(try? JSONEncoder().encode(marker), forKey: defaultsKey)
    }

    static func disarm() {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Reads-and-clears. Returns a marker only when it is evidence.
    static func takeEvidenceAtLaunch(now: Date = Date()) -> Armed? {
        defer { disarm() }
        guard let marker = armed(from: defaults.data(forKey: defaultsKey)),
              isEvidence(marker, now: now) else { return nil }
        return marker
    }
}
