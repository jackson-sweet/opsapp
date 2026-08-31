//
//  AnalyticsService.swift
//  OPS
//
//  Durable first-party product analytics. Firebase conversion tracking is
//  intentionally isolated in AnalyticsManager.
//

import Foundation
import UIKit

enum AnalyticsEventType: String {
    case screenView = "screen_view"
    case action
    case featureUse = "feature_use"
    case lifecycle
    case error
}

@MainActor
final class AnalyticsService {

    static let shared = AnalyticsService()

    private let queue = AnalyticsEventQueue.shared
    private let session = AnalyticsSession.shared
    private var flushTimer: Timer?
    private var isFlushing = false
    private var hasStarted = false

    private init() {}

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        startFlushTimer()
        observeAppLifecycle()
        observeConnectivity()
        track(eventType: .lifecycle, eventName: "app_open", properties: ["launch_type": "cold"])
        Task { await flush() }
        debugLog("service_started")
    }

    @discardableResult
    func track(
        eventType: AnalyticsEventType,
        eventName: String,
        properties: [String: Any] = [:],
        durationMs: Int? = nil
    ) -> Bool {
        guard AnalyticsEventContract.isValidEventName(eventName) else {
            debugLog("event_rejected_invalid_name")
            return false
        }
        if let durationMs, !(0...(24 * 60 * 60 * 1_000)).contains(durationMs) {
            debugLog("event_rejected_invalid_duration")
            return false
        }
        let subject = SupabaseService.shared.currentUserId

        let event = QueuedAnalyticsEvent(
            expected_subject: subject,
            is_preauth: subject == nil,
            id: UUID().uuidString,
            event_type: eventType.rawValue,
            event_name: eventName,
            app_version: boundedContext(session.appVersion),
            device_type: boundedContext(session.deviceType),
            os_version: boundedContext(session.osVersion),
            session_id: session.sessionId.uuidString,
            properties: AnalyticsEventContract.sanitizeProperties(properties),
            duration_ms: durationMs,
            schema_version: AnalyticsEventContract.schemaVersion,
            environment: AnalyticsEventContract.environment,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        queue.enqueue(event)
        debugLog("event_queued")
        return true
    }

    func trackScreenView(screenName: String, properties: [String: Any] = [:]) {
        session.screenDidAppear(screenName)
        track(eventType: .screenView, eventName: screenName, properties: properties)
    }

    func endScreenView(screenName: String) {
        guard let durationMs = session.screenDidDisappear(screenName) else { return }
        track(
            eventType: .screenView,
            eventName: "\(screenName)_duration",
            durationMs: durationMs
        )
    }

    // MARK: - Durable delivery

    /// The server RPC provides the only identity boundary: it resolves the
    /// signed Firebase subject to the canonical user/company/role/plan, stamps
    /// platform=iOS, validates the contract, and inserts UUIDs idempotently.
    /// Permanent poison events are dropped; transient failures return to the
    /// front of the queue without changing their IDs or order.
    func flush() async {
        guard !isFlushing else { return }
        guard let subject = SupabaseService.shared.currentUserId else { return }
        isFlushing = true
        defer { isFlushing = false }

        while true {
            let dequeued = queue.dequeueBatch(size: 50)
            guard !dequeued.isEmpty else { break }

            let batch = dequeued.compactMap { event -> QueuedAnalyticsEvent? in
                if event.expected_subject == subject {
                    return event
                }
                if event.is_preauth {
                    return event.claimed(by: subject)
                }
                return nil
            }
            let discardedCount = dequeued.count - batch.count
            if discardedCount > 0 {
                // Never attribute an old or legacy queue to a different login.
                debugLog("discarded_stale_identity_events", count: discardedCount)
            }
            guard !batch.isEmpty else { continue }

            do {
                try await insert(batch, expectedSubject: subject)
                debugLog("batch_flushed", count: batch.count)
            } catch {
                switch AnalyticsFlushPolicy.outcome(for: error) {
                case .splitBatch:
                    let unresolved = await insertIndividually(
                        batch,
                        expectedSubject: subject
                    )
                    guard unresolved.isEmpty else {
                        queue.requeue(unresolved)
                        debugLog("batch_partially_requeued", count: unresolved.count)
                        return
                    }
                case .retry:
                    queue.requeue(batch)
                    debugLog("batch_requeued", count: batch.count)
                    return
                case .drop:
                    debugLog("batch_dropped", count: batch.count)
                }
            }
        }
    }

    private func insert(
        _ batch: [QueuedAnalyticsEvent],
        expectedSubject: String
    ) async throws {
        try await SupabaseService.shared.client
            .rpc(
                "append_analytics_events",
                params: AnalyticsAppendRPCParams(
                    p_events: batch,
                    p_expected_subject: expectedSubject,
                    p_schema_version: AnalyticsEventContract.schemaVersion,
                    p_environment: AnalyticsEventContract.environment
                )
            )
            .execute()
    }

    private func insertIndividually(
        _ batch: [QueuedAnalyticsEvent],
        expectedSubject: String
    ) async -> [QueuedAnalyticsEvent] {
        var unresolved: [QueuedAnalyticsEvent] = []
        for event in batch {
            do {
                try await insert([event], expectedSubject: expectedSubject)
            } catch {
                switch AnalyticsFlushPolicy.outcome(for: error) {
                case .splitBatch, .drop:
                    continue
                case .retry:
                    unresolved.append(event)
                }
            }
        }
        return unresolved
    }

    // MARK: - Flush triggers

    private func startFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.flush() }
        }
    }

    private func observeAppLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.track(
                    eventType: .lifecycle,
                    eventName: "app_close",
                    properties: ["session_duration_ms": self.session.sessionDurationMs]
                )
                await self.flush()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.flush() }
        }
    }

    private func observeConnectivity() {
        NotificationCenter.default.addObserver(
            forName: ConnectivityManager.connectivityChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let state = notification.userInfo?["state"] as? ConnectionState,
                  state.status != .offline else { return }
            Task { @MainActor in await self.flush() }
        }
    }

    private func boundedContext(_ value: String?) -> String? {
        guard let value else { return nil }
        return String(value.prefix(128))
    }

    private func debugLog(_ message: String, count: Int? = nil) {
        #if DEBUG
        let suffix = count.map { " count=\($0)" } ?? ""
        print("[ANALYTICS] \(message)\(suffix)")
        #endif
    }
}
