//
//  CallLogStore.swift
//  OPS
//
//  Around-call lead capture (iOS feature 154cb8a3). When the operator taps CALL
//  on a lead, OPS records the outbound intent (who / what number / when) before
//  iOS hands off to the Phone app and backgrounds OPS. On the next foreground,
//  MainTabView reads the pending intent and offers a one-tap "log that call"
//  prompt pre-filled to that exact lead.
//
//  Persisted to UserDefaults so the intent survives the app→Phone→app switch
//  and even a cold relaunch. A single field-grade record — no history, no PII
//  beyond the number the operator just dialed themselves.
//

import Foundation
import Combine

/// One recorded outbound-call intent, awaiting a post-call log prompt.
struct PendingOutboundCall: Codable, Equatable {
    /// The lead the call was placed against, when known (the ContactCard path
    /// always knows it). `nil` for a raw-number dial with no lead context.
    let opportunityId: String?
    let contactName: String?
    /// The number as dialed (raw). Normalized via `PhoneNumber` at compare time.
    let phoneNumber: String
    let startedAt: Date
}

@MainActor
final class CallLogStore: ObservableObject {
    static let shared = CallLogStore()

    private let defaultsKey = "ops.callLog.pendingOutbound"

    /// An intent older than this is treated as abandoned — the operator never
    /// returned to OPS in a window where logging the call still makes sense, so
    /// we don't ambush them with a stale prompt. 30 minutes.
    nonisolated static let maxPromptAge: TimeInterval = 30 * 60

    @Published private(set) var pending: PendingOutboundCall?

    private init() {
        load()
    }

    /// Record an outbound call placed from inside OPS. Overwrites any prior
    /// pending intent — the freshest dial is the one worth prompting about.
    func recordOutbound(opportunityId: String?, contactName: String?, phone: String) {
        let intent = PendingOutboundCall(
            opportunityId: opportunityId,
            contactName: contactName,
            phoneNumber: phone,
            startedAt: Date()
        )
        pending = intent
        persist(intent)
    }

    /// Return the pending intent if it's recent enough to prompt about, then
    /// clear it (one prompt per call). Stale intents are silently discarded.
    func consumeRecent(now: Date = Date(), maxAge: TimeInterval = CallLogStore.maxPromptAge) -> PendingOutboundCall? {
        guard let intent = pending else { return nil }
        clear()
        guard now.timeIntervalSince(intent.startedAt) <= maxAge else { return nil }
        return intent
    }

    func clear() {
        pending = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Persistence

    private func persist(_ intent: PendingOutboundCall) {
        guard let data = try? JSONEncoder().encode(intent) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let intent = try? JSONDecoder().decode(PendingOutboundCall.self, from: data) else { return }
        pending = intent
    }
}
