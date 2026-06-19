//
//  ResilientRow.swift
//  OPS
//
//  Row-resilient decoding for Supabase list fetches.
//
//  A single corrupt row must never black out an entire entity's inbound sync.
//  That is exactly what stranded the crew on the deck-design tab: one
//  undecodable `drawing_data` made the whole-batch `.value` decode throw, the
//  sync swallowed it, advanced the cursor, and every deck vanished. The same
//  whole-batch `.value` decode is used by every repository's sync fetch, so the
//  same blackout was latent across the entire sync layer.
//
//  `ResilientRow<T>` decodes a list element-by-element: a row that fails to
//  decode yields `nil` and is dropped, while every valid row survives. Crucially
//  it rides on the SAME decoder the Supabase SDK uses for `.value` (it is just
//  another `Decodable` response shape), so every DTO's key strategy and date
//  strategy are honored exactly — no fidelity risk for `Date`-typed DTOs like
//  CalendarUserEvent. A genuine API error (non-array payload, network/auth
//  failure) still throws and is handled as an entity-level sync failure; only
//  per-row decode failures are tolerated.
//

import Foundation
import Supabase

/// A decode wrapper whose value is `nil` when the underlying row fails to decode
/// into `T`, instead of throwing and aborting the whole array. Decoding
/// `[ResilientRow<T>]` therefore never fails on a single bad row.
struct ResilientRow<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        // Each array element is handed a fresh sub-decoder over its own parsed
        // JSON value, so a throw here cannot corrupt decoding of later elements.
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}

extension PostgrestBuilder {
    /// Execute a list query and decode it row-by-row, dropping any single
    /// undecodable row instead of failing the whole batch. Use for inbound-sync
    /// fetches where one corrupt row must not black out the entire entity.
    ///
    /// Rides on the SDK's own decoder via `ResilientRow`, so DTO key/date
    /// strategies are preserved. Bind the call to an explicit `[DTO]` so `T` is
    /// inferred:
    /// ```
    /// let response: [SupabaseUserDTO] = try await query.executeResilient(label: "users")
    /// ```
    /// - Parameter label: optional table/entity name used only to log how many
    ///   rows were skipped, for visibility into otherwise-silent drops.
    func executeResilient<T: Decodable>(label: String? = nil) async throws -> [T] {
        let rows: [ResilientRow<T>] = try await execute().value
        let decoded = rows.compactMap(\.value)
        let dropped = rows.count - decoded.count
        if dropped > 0 {
            print("[SYNC_DECODE] \(label ?? String(describing: T.self)): skipped \(dropped)/\(rows.count) undecodable row(s)")
        }
        return decoded
    }
}
