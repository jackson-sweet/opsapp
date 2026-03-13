//
//  WizardAnalyticsService.swift
//  OPS
//
//  Fire-and-forget analytics for wizard events.
//  Inserts rows to the wizard_analytics table in Supabase.
//

import Foundation
import Supabase

/// Codable payload matching the wizard_analytics table schema
private struct WizardAnalyticsRow: Codable {
    let user_id: String?
    let user_role: String?
    let platform: String
    let wizard_id: String
    let event: String
    let step_index: Int?
    let step_id: String?
    let total_steps: Int?
    let duration_ms: Int?
    let steps_skipped: Int?
    let trigger_type: String?
    let trigger_context: String?
    let is_restart: Bool?
    let session_id: String
}

class WizardAnalyticsService {
    static let shared = WizardAnalyticsService()

    private var client: SupabaseClient {
        SupabaseService.shared.client
    }

    /// UserDefaults key for offline event queue
    private let queueKey = "wizard_analytics_queue"

    /// Record any wizard event. Events are sent to Supabase immediately when
    /// online. If the insert fails (offline or network error), the event is
    /// queued locally in UserDefaults and sent on the next successful call.
    func recordEvent(
        event: String,
        wizardId: String,
        sessionId: String,
        userId: String? = nil,
        userRole: String? = nil,
        stepIndex: Int? = nil,
        stepId: String? = nil,
        totalSteps: Int? = nil,
        durationMs: Int? = nil,
        stepsSkipped: Int? = nil,
        triggerType: String? = nil,
        triggerContext: String? = nil,
        isRestart: Bool? = nil
    ) {
        let row = WizardAnalyticsRow(
            user_id: userId,
            user_role: userRole,
            platform: "ios",
            wizard_id: wizardId,
            event: event,
            step_index: stepIndex,
            step_id: stepId,
            total_steps: totalSteps,
            duration_ms: durationMs,
            steps_skipped: stepsSkipped,
            trigger_type: triggerType,
            trigger_context: triggerContext,
            is_restart: isRestart,
            session_id: sessionId
        )

        Task {
            // Attempt to flush any previously queued events first
            await flushQueue()

            do {
                try await client
                    .from("wizard_analytics")
                    .insert(row)
                    .execute()
            } catch {
                print("[WizardAnalytics] Insert failed, queuing locally: \(error.localizedDescription)")
                enqueueLocally(row)
            }
        }
    }

    /// Flush any locally queued events to Supabase
    func flushQueue() async {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let queued = try? JSONDecoder().decode([WizardAnalyticsRow].self, from: data),
              !queued.isEmpty else { return }

        var remaining: [WizardAnalyticsRow] = []
        for row in queued {
            do {
                try await client
                    .from("wizard_analytics")
                    .insert(row)
                    .execute()
            } catch {
                remaining.append(row)
            }
        }

        if remaining.isEmpty {
            UserDefaults.standard.removeObject(forKey: queueKey)
        } else if let encoded = try? JSONEncoder().encode(remaining) {
            UserDefaults.standard.set(encoded, forKey: queueKey)
        }
    }

    private func enqueueLocally(_ row: WizardAnalyticsRow) {
        var queued: [WizardAnalyticsRow] = []
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let existing = try? JSONDecoder().decode([WizardAnalyticsRow].self, from: data) {
            queued = existing
        }
        queued.append(row)
        // Cap at 500 events to prevent unbounded growth
        if queued.count > 500 { queued = Array(queued.suffix(500)) }
        if let encoded = try? JSONEncoder().encode(queued) {
            UserDefaults.standard.set(encoded, forKey: queueKey)
        }
    }
}
