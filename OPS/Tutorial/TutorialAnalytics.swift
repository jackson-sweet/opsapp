import Foundation

/// Fire-and-forget analytics for the tutorial.
enum TutorialAnalytics {

    private struct Row: Encodable {
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

    static func record(
        action: String,
        phase: String,
        phaseIndex: Int,
        durationMs: Int? = nil,
        totalElapsedMs: Int? = nil,
        sessionId: String,
        userId: String? = nil
    ) {
        let row = Row(
            user_id: userId,
            platform: "ios",
            flow_type: "leadToRevenue",
            phase: phase,
            phase_index: phaseIndex,
            action: action,
            duration_ms: durationMs,
            total_elapsed_ms: totalElapsedMs,
            session_id: sessionId
        )

        Task.detached(priority: .utility) {
            do {
                try await SupabaseService.shared.client
                    .from("tutorial_analytics")
                    .insert(row)
                    .execute()
            } catch {
                // Silent. Analytics never blocks the tutorial.
            }
        }
    }
}
