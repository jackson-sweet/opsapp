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
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        while true {
            let batch = queue.dequeueBatch(size: 50)
            guard !batch.isEmpty else { break }

            do {
                try await SupabaseService.shared.client
                    .from("analytics_events")
                    .insert(batch)
                    .execute()

                print("[ANALYTICS] ✅ Flushed \(batch.count) events")
            } catch {
                // Put failed batch back in queue for retry
                queue.requeue(batch)
                print("[ANALYTICS] ⚠️ Flush failed, requeued \(batch.count) events: \(error.localizedDescription)")
                break  // Stop trying — will retry on next flush trigger
            }
        }
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
