//
//  ClientServerVisibility.swift
//  OPS
//
//  Bug 13c66762 — clients are created LOCAL-FIRST (SwiftData insert plus a
//  queued sync operation), so a child row that references one can reach the
//  server before its parent does. `create_opportunity_guarded` rejects exactly
//  that case:
//
//      if v_client_id is not null and not exists (
//        select 1 from public.clients c where c.id = v_client_id …)
//      then raise exception 'client_not_found_in_company' using errcode '22023';
//
//  …and the whole transaction rolls back, so NOTHING is created. The operator
//  sees a failure for work that was actually fine.
//
//  This is the one place that waits, bounded, for a just-created client to
//  become readable by this authenticated session before its child row is
//  written. The durable lead queue has always had this guard
//  (`ClientLeadAutocreateQueue.performLiveAttempt`); every direct create path
//  now shares it instead of re-deriving it.
//

import Foundation

enum ClientServerVisibility {

    enum Outcome: Equatable {
        /// The server can see the client — safe to write its child row.
        case visible
        /// No signal. Probing again here is pointless; whoever owns durable
        /// delivery takes the work from here.
        case offline
        /// Still invisible when the probe budget ran out.
        case notVisible
    }

    /// Probes before giving up. Six probes with the default backoff is ~3.75s of
    /// waiting — long enough to cover a normal outbound sync of the client,
    /// short enough to sit under the button's existing spinner.
    static let defaultAttempts = 6

    /// 0.25s, 0.5s, 0.75s, 1.0s, 1.25s between probes (capped at 1.5s).
    static func defaultBackoff(afterAttempt attempt: Int) -> TimeInterval {
        min(Double(attempt) * 0.25, 1.5)
    }

    /// Polls until the client is readable, the network is clearly down, or the
    /// budget is spent. `probe`, `backoff`, and `isOffline` are injectable so
    /// the policy is testable without a network and without sleeping.
    static func wait(
        clientId: String,
        companyId: String,
        attempts: Int = defaultAttempts,
        probe: (String, String) async throws -> Void = ClientServerVisibility.liveProbe,
        backoff: (Int) async -> Void = ClientServerVisibility.liveBackoff,
        isOffline: (Error) -> Bool = ClientServerVisibility.isLikelyOfflineError
    ) async -> Outcome {
        let budget = max(1, attempts)
        for attempt in 1...budget {
            do {
                try await probe(clientId, companyId)
                return .visible
            } catch {
                if isOffline(error) { return .offline }
                guard attempt < budget else { break }
                await backoff(attempt)
            }
        }
        return .notVisible
    }

    static func liveProbe(clientId: String, companyId: String) async throws {
        _ = try await ClientRepository(companyId: companyId).fetchOne(clientId)
    }

    static func liveBackoff(afterAttempt attempt: Int) async {
        let seconds = defaultBackoff(afterAttempt: attempt)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Best-effort "the device has no usable connection" classification. Used to
    /// stop burning the probe budget when the answer cannot change.
    static func isLikelyOfflineError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotConnectToHost,
                 .dataNotAllowed:
                return true
            default:
                break
            }
        }
        let text = String(describing: error).lowercased()
        return text.contains("offline")
            || text.contains("network")
            || text.contains("connection")
            || text.contains("timed out")
    }
}
