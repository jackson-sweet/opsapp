//
//  SuggestedCalendarEventRepository.swift
//  OPS
//
//  Read/resolve path for Phase-C detected events (item 63144953), via two
//  SECURITY DEFINER RPCs. Fully dormant by contract: every call that fails for
//  any reason — no rows, offline, RPC error, decode error — yields an empty
//  result, so the surface shows nothing and the app never depends on the
//  (headless, Canpro-only) Phase C engine.
//

import Foundation
import Supabase

final class SuggestedCalendarEventRepository {
    private let client: SupabaseClient

    init() {
        self.client = SupabaseService.shared.client
    }

    /// Unresolved, upcoming, time-bearing detected commitments for the caller's
    /// company. Returns `[]` on any failure — never throws into the UI.
    func fetchSuggestedEvents() async -> [SuggestedCalendarEventDTO] {
        do {
            return try await client
                .rpc("get_suggested_calendar_events")
                .execute()
                .value
        } catch {
            // Dormant contract: an empty list is the healthy default. Swallow.
            return []
        }
    }

    /// Mark a commitment resolved so it isn't re-offered (after the user adds or
    /// dismisses it). Best-effort: returns false on any failure rather than
    /// surfacing an error — the client-side title+day dedup is the backstop.
    @discardableResult
    func resolve(_ memoryId: String) async -> Bool {
        do {
            let result: ResolveResult = try await client
                .rpc(
                    "resolve_suggested_calendar_event",
                    params: ResolveSuggestedCalendarEventParams(p_memory_id: memoryId)
                )
                .execute()
                .value
            return result.resolved
        } catch {
            return false
        }
    }

    private struct ResolveResult: Decodable {
        let resolved: Bool
    }
}
