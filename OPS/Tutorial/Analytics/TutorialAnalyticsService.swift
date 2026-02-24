//
//  TutorialAnalyticsService.swift
//  OPS
//
//  Fire-and-forget analytics service for tutorial phase tracking.
//  Inserts rows to the tutorial_analytics table in Supabase.
//

import Foundation
import Supabase

/// Codable payload matching the tutorial_analytics table schema
private struct TutorialAnalyticsRow: Encodable {
    let user_id: String?
    let platform: String
    let flow_type: String
    let phase: String
    let phase_index: Int
    let action: String
    let duration_ms: Int?
    let total_elapsed_ms: Int?
    let session_id: String
}

class TutorialAnalyticsService {
    private var client: SupabaseClient {
        SupabaseService.shared.client
    }

    /// Record a phase action (completed, skipped, auto_advanced, dropped_off)
    func recordPhaseAction(
        phase: String,
        phaseIndex: Int,
        action: String,
        durationMs: Int,
        totalElapsedMs: Int,
        flowType: String,
        sessionId: String,
        userId: String?
    ) async {
        let row = TutorialAnalyticsRow(
            user_id: userId,
            platform: "ios",
            flow_type: flowType,
            phase: phase,
            phase_index: phaseIndex,
            action: action,
            duration_ms: durationMs,
            total_elapsed_ms: totalElapsedMs,
            session_id: sessionId
        )

        do {
            try await client
                .from("tutorial_analytics")
                .insert(row)
                .execute()
        } catch {
            print("[TutorialAnalytics] Insert failed: \(error.localizedDescription)")
        }
    }
}
