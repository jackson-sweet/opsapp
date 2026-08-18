//
//  AnalyticsService.swift
//  OPS
//
//  Unified analytics service. Tracks events to Supabase analytics_events table
//  with offline queue support. Separate from AnalyticsManager (Firebase/Google Ads).
//

import Foundation
import UIKit

enum AnalyticsEventType: String {
    case screenView = "screen_view"
    case action = "action"
    case featureUse = "feature_use"
    case lifecycle = "lifecycle"
    case error = "error"
}

@MainActor
final class AnalyticsService {

    static let shared = AnalyticsService()

    private let queue = AnalyticsEventQueue.shared
    private let session = AnalyticsSession.shared
    private var flushTimer: Timer?
    private var isFlushing = false

    private init() {}

    // MARK: - Setup

    /// Call once from OPSApp.init to start the flush timer and lifecycle observers.
    func start() {
        startFlushTimer()
        observeAppLifecycle()
        observeConnectivity()

        // Track app open
        track(eventType: .lifecycle, eventName: "app_open", properties: ["launch_type": "cold"])

        // Flush any events queued from previous session (offline)
        Task { await flush() }

        print("[ANALYTICS] ✅ AnalyticsService started — session \(session.sessionId.uuidString.prefix(8))")
    }

    // MARK: - Public API

    /// Track an event. Property values must be String, Int, Double, or Bool.
    func track(
        eventType: AnalyticsEventType,
        eventName: String,
        properties: [String: Any] = [:],
        durationMs: Int? = nil
    ) {
        let event = QueuedAnalyticsEvent(
            id: UUID().uuidString,
            user_id: UserDefaults.standard.string(forKey: "user_id"),
            company_id: UserDefaults.standard.string(forKey: "company_id"),
            role: UserDefaults.standard.string(forKey: "user_role"),
            plan: UserDefaults.standard.string(forKey: "subscription_plan"),
            event_type: eventType.rawValue,
            event_name: eventName,
            platform: "ios",
            app_version: session.appVersion,
            device_type: session.deviceType,
            os_version: session.osVersion,
            session_id: session.sessionId.uuidString,
            properties: properties.mapValues { encodeValue($0) },
            duration_ms: durationMs,
            created_at: ISO8601DateFormatter().string(from: Date())
        )

        queue.enqueue(event)

        print("[ANALYTICS] 📊 Tracked \(eventType.rawValue)/\(eventName)" +
              (durationMs.map { " (\($0)ms)" } ?? ""))
    }

    /// Track a screen view. Call from .onAppear.
    func trackScreenView(screenName: String, properties: [String: Any] = [:]) {
        session.screenDidAppear(screenName)
        track(eventType: .screenView, eventName: screenName, properties: properties)
    }

    /// End a screen view. Call from .onDisappear. Records duration_ms.
    func endScreenView(screenName: String) {
        guard let durationMs = session.screenDidDisappear(screenName) else { return }
        track(
            eventType: .screenView,
            eventName: "\(screenName)_duration",
            durationMs: durationMs
        )
    }

    // MARK: - Flush

    /// Flush queued events to Supabase in batches.
    ///
    /// Two rules make the dam impossible by construction (bug 088d82dc):
    ///
    ///  1. **Plain insert, minimal return.** The old call was
    ///     `.upsert(onConflict: "id", ignoreDuplicates: true)`, and upsert
    ///     defaults to returning a representation. `ON CONFLICT` needs SELECT on
    ///     the conflict column and a representation needs SELECT on the row —
    ///     but `analytics_events` grants the app INSERT and nothing else, on
    ///     purpose. Every batch therefore 403'd, retried every 30 seconds
    ///     forever, and dammed the queue behind it until the 1,000-event cap
    ///     started dropping the oldest events. The idempotency the upsert was
    ///     reaching for (bug 08d1f969) is preserved without any new grant:
    ///     a duplicate key means the batch already landed, and
    ///     `AnalyticsFlushPolicy` reads that as success.
    ///  2. **A poison batch is dropped, never re-queued.** A permanently
    ///     rejected batch cannot become deliverable by waiting, so requeueing it
    ///     blocks every later event behind data that will never send. Analytics
    ///     are the one payload in this app that is cheaper to lose than to dam.
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while true {
            let batch = queue.dequeueBatch(size: 50)
            guard !batch.isEmpty else { break }

            do {
                try await insert(batch)
                print("[ANALYTICS] ✅ Flushed \(batch.count) events")
            } catch {
                switch AnalyticsFlushPolicy.outcome(for: error) {
                case .splitBatch:
                    // A duplicate key means at least one event in this batch is
                    // already on the server — and a Postgres INSERT is
                    // all-or-nothing, so the ones that are NOT would be lost if
                    // this were simply called delivered. A re-queued batch
                    // re-forms with newer events behind it, so a mixed batch is
                    // ordinary, not exotic. Retry event by event.
                    let unresolved = await insertIndividually(batch)
                    guard unresolved.isEmpty else {
                        queue.requeue(unresolved)
                        print("[ANALYTICS] ⚠️ \(unresolved.count) of \(batch.count) events requeued after a per-event retry")
                        return
                    }

                case .retry:
                    queue.requeue(batch)
                    print("[ANALYTICS] ⚠️ Flush failed, requeued \(batch.count) events: \(error.localizedDescription)")
                    return  // Transient — the next trigger tries again

                case .drop:
                    // Quarantine by dropping. Keeping it would wedge the queue.
                    print("[ANALYTICS] ⛔️ Dropped \(batch.count) events the server permanently rejected: \(error.localizedDescription)")
                }
            }
        }
    }

    /// One batch, one INSERT, nothing returned.
    private func insert(_ batch: [QueuedAnalyticsEvent]) async throws {
        try await SupabaseService.shared.client
            .from("analytics_events")
            .insert(batch, returning: .minimal)
            .execute()
    }

    /// Sends a duplicate-poisoned batch one event at a time and returns only the
    /// events that are genuinely still undelivered.
    ///
    /// A per-event duplicate is a success: the event is on the server, which is
    /// exactly what at-least-once delivery asks for. A permanently rejected
    /// event is dropped — one malformed row must not hold back the rest of the
    /// batch, let alone the queue behind it.
    private func insertIndividually(
        _ batch: [QueuedAnalyticsEvent]
    ) async -> [QueuedAnalyticsEvent] {
        var unresolved: [QueuedAnalyticsEvent] = []
        for event in batch {
            do {
                try await insert([event])
            } catch {
                switch AnalyticsFlushPolicy.outcome(for: error) {
                case .splitBatch:
                    continue    // already on the server
                case .drop:
                    print("[ANALYTICS] ⛔️ Dropped 1 permanently rejected event: \(error.localizedDescription)")
                case .retry:
                    unresolved.append(event)
                }
            }
        }
        return unresolved
    }

    // MARK: - Flush Triggers

    private func startFlushTimer() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.flush()
            }
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
                // Track app close with session duration
                self.track(
                    eventType: .lifecycle,
                    eventName: "app_close",
                    properties: ["session_duration_ms": self.session.sessionDurationMs]
                )
                // Best-effort flush before backgrounding
                await self.flush()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Flush queued events on return to foreground
            Task { @MainActor in
                await self.flush()
            }
        }
    }

    private func observeConnectivity() {
        NotificationCenter.default.addObserver(
            forName: ConnectivityManager.connectivityChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // Flush when connectivity is restored
            if let state = notification.userInfo?["state"] as? ConnectionState,
               state.status != .offline {
                Task { @MainActor in
                    await self.flush()
                }
            }
        }
    }

    // MARK: - Helpers

    private func encodeValue(_ value: Any) -> AnyCodableValue {
        switch value {
        case let val as Bool: return .bool(val)
        case let val as Int: return .int(val)
        case let val as Double: return .double(val)
        case let val as String: return .string(val)
        default: return .string(String(describing: value))
        }
    }
}
