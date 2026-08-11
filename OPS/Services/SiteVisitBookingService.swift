//
//  SiteVisitBookingService.swift
//  OPS
//
//  The app's ONLY write path for visit appointments — thin wrappers over the
//  three server RPCs (book / reschedule / cancel). Side effects (activity row,
//  stage nudge, calendar sync enqueue, prompt re-arm) are server-owned, which
//  is exactly why these calls are RPC-only and never queued locally: replaying
//  a stale booking hours later would fire stale side effects. Offline = a
//  clear, terse error and nothing written.
//

import Foundation
import Supabase

// MARK: - Errors (user-presentable)

/// Mapped from the RPC error contract:
///   42501 → permission / actor    55000 → one-open-booking conflict
///   22023 → validation            P0002 → row not found
/// URLError connectivity failures → offline. Everything else → server.
enum SiteVisitBookingError: Error, Equatable, LocalizedError {
    case offline
    case permissionDenied
    case bookingConflict
    case validation(detail: String)
    case notFound
    case server(detail: String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "No connection. Try again when you have signal."
        case .permissionDenied:
            return "You don't have permission to manage site visits."
        case .bookingConflict:
            return "This lead already has a visit booked."
        case .validation:
            return "That didn't go through. Check the time and try again."
        case .notFound:
            return "Visit not found. It may have been cancelled on another device."
        case .server:
            return "Server error. Try again."
        }
    }
}

// MARK: - Reminder override

/// How a reschedule treats the per-booking heads-up override. The -1 clear
/// sentinel is a wire detail — Swift callers never see it.
enum SiteVisitReminderOverride: Equatable {
    /// Leave the stored override untouched (param omitted → server keeps).
    case keep
    /// Set the override to this many minutes before the visit.
    case set(Int)
    /// Drop the override so the assignee's default lead applies again.
    case clear

    fileprivate var wireValue: Int? {
        switch self {
        case .keep:           return nil
        case .set(let lead):  return lead
        case .clear:          return -1
        }
    }
}

// MARK: - Wire params

/// Property names ARE the wire names (matching CompleteSiteVisitRPCParams);
/// optionals encode by omission so server-side defaults and NULL-keeps apply.
struct BookSiteVisitRPCParams: Codable, Equatable {
    let p_opportunity_id: String
    let p_scheduled_at: String
    let p_duration_minutes: Int
    let p_assignee_ids: [String]?
    let p_reminder_lead_minutes: Int?
}

struct RescheduleSiteVisitRPCParams: Codable, Equatable {
    let p_site_visit_id: String
    let p_scheduled_at: String?
    let p_duration_minutes: Int?
    let p_assignee_ids: [String]?
    let p_reminder_lead_minutes: Int?
}

struct CancelSiteVisitBookingRPCParams: Codable, Equatable {
    let p_site_visit_id: String
}

enum SiteVisitBookingRequest: Equatable {
    case book(BookSiteVisitRPCParams)
    case reschedule(RescheduleSiteVisitRPCParams)
    case cancel(CancelSiteVisitBookingRPCParams)

    var functionName: String {
        switch self {
        case .book:       return "book_site_visit"
        case .reschedule: return "reschedule_site_visit"
        case .cancel:     return "cancel_site_visit_booking"
        }
    }
}

/// Narrow transport seam so booking behavior is provable without a live
/// network — same shape as SiteVisitRemoteTransport.
protocol SiteVisitBookingTransport: AnyObject {
    func send(_ request: SiteVisitBookingRequest) async throws -> Data
}

// MARK: - Service

final class SiteVisitBookingService: @unchecked Sendable {
    private let transport: SiteVisitBookingTransport
    private let decoder = JSONDecoder()

    init(transport: SiteVisitBookingTransport) {
        self.transport = transport
    }

    @MainActor
    convenience init() {
        self.init(
            transport: SupabaseSiteVisitBookingTransport(
                client: SupabaseService.shared.client
            )
        )
    }

    /// Books a visit on the lead and returns the new visit id. Assignees
    /// default server-side to the booker; the reminder default resolves per
    /// assignee at prompt time, so nil here means "no per-booking override."
    @discardableResult
    func book(
        opportunityId: String,
        scheduledAt: Date,
        durationMinutes: Int = 60,
        assigneeIds: [String]? = nil,
        reminderLeadMinutes: Int? = nil
    ) async throws -> String {
        try await send(
            .book(
                BookSiteVisitRPCParams(
                    p_opportunity_id: opportunityId.lowercased(),
                    p_scheduled_at: SupabaseDate.format(scheduledAt),
                    p_duration_minutes: durationMinutes,
                    p_assignee_ids: assigneeIds.map { $0.map { $0.lowercased() } },
                    p_reminder_lead_minutes: reminderLeadMinutes
                )
            )
        )
    }

    /// Reschedules a booked, not-yet-started visit. Nil parameters keep the
    /// server's current values; the changed time re-arms every prompt by
    /// construction (dedupe keys carry the epoch).
    @discardableResult
    func reschedule(
        siteVisitId: String,
        scheduledAt: Date? = nil,
        durationMinutes: Int? = nil,
        assigneeIds: [String]? = nil,
        reminderOverride: SiteVisitReminderOverride = .keep
    ) async throws -> String {
        try await send(
            .reschedule(
                RescheduleSiteVisitRPCParams(
                    p_site_visit_id: siteVisitId.lowercased(),
                    p_scheduled_at: scheduledAt.map(SupabaseDate.format),
                    p_duration_minutes: durationMinutes,
                    p_assignee_ids: assigneeIds.map { $0.map { $0.lowercased() } },
                    p_reminder_lead_minutes: reminderOverride.wireValue
                )
            )
        )
    }

    /// Cancels a booking. Idempotent server-side — cancelling an already
    /// cancelled visit resolves as success.
    @discardableResult
    func cancel(siteVisitId: String) async throws -> String {
        try await send(
            .cancel(
                CancelSiteVisitBookingRPCParams(
                    p_site_visit_id: siteVisitId.lowercased()
                )
            )
        )
    }

    // MARK: - Internals

    private func send(_ request: SiteVisitBookingRequest) async throws -> String {
        let data: Data
        do {
            data = try await transport.send(request)
        } catch {
            throw Self.mapTransportError(error)
        }
        do {
            return try decoder.decode(String.self, from: data).lowercased()
        } catch {
            throw SiteVisitBookingError.server(
                detail: "Malformed RPC response: \(String(describing: error))"
            )
        }
    }

    private static func mapTransportError(_ error: Error) -> SiteVisitBookingError {
        if let typed = error as? SiteVisitBookingError {
            return typed
        }
        if let postgrest = error as? PostgrestError {
            switch postgrest.code ?? "" {
            case "42501":
                return .permissionDenied
            case "55000":
                return .bookingConflict
            case "22023":
                return .validation(detail: postgrest.message)
            case "P0002":
                return .notFound
            default:
                return .server(detail: "[\(postgrest.code ?? "?")] \(postgrest.message)")
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .internationalRoamingOff, .dataNotAllowed:
                return .offline
            default:
                return .server(detail: urlError.localizedDescription)
            }
        }
        if let http = error as? HTTPError {
            let status = http.response.statusCode
            if status == 401 || status == 403 {
                return .permissionDenied
            }
            return .server(detail: "HTTP \(status)")
        }
        return .server(detail: error.localizedDescription)
    }
}

// MARK: - Live Supabase adapter

private final class SupabaseSiteVisitBookingTransport: SiteVisitBookingTransport {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func send(_ request: SiteVisitBookingRequest) async throws -> Data {
        switch request {
        case .book(let params):
            return try await client
                .rpc(request.functionName, params: params)
                .execute()
                .data
        case .reschedule(let params):
            return try await client
                .rpc(request.functionName, params: params)
                .execute()
                .data
        case .cancel(let params):
            return try await client
                .rpc(request.functionName, params: params)
                .execute()
                .data
        }
    }
}
