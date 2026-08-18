//
//  CalendarUserEventOutboundSync.swift
//  OPS
//
//  Time off and personal events, moved onto the durable outbound queue
//  (bug ef5a69e6).
//
//  What this replaces. Every write to `calendar_user_events` used to be
//  fire-and-forget from the surface that made it:
//
//      context.insert(event); event.needsSync = true
//      Task { if let saved = try? await repo.create(dto) { … } }   ← failure swallowed
//      await notifyAdmins(...)                                     ← fired regardless
//
//  When the create failed the sheet still reported success, the local row kept
//  `needsSync = true` forever with nothing queued to push it, and approvers got
//  a push for a request that existed on exactly one phone. The recurring-series
//  helpers were worse: `syncEditToSupabase` / `syncDeleteToSupabase` cleared
//  `needsSync` unconditionally after `try?` calls, so a failed edit reverted on
//  the next pull and a failed delete resurrected the event.
//
//  What happens now. The surfaces still write locally and dismiss immediately —
//  the operator should never wait on a network round trip — but the server write
//  is a durable `SyncOperation`. It retries with the rest of the queue, it
//  survives app kills, it appears in PENDING WORK when it needs a human, and
//  `needsSync` clears on ONE thing only: a confirmed per-row server success.
//
//  Notifications ride the same guarantee. The admin/approver notification for a
//  time-off request is not the sheet's job any more — the request has to exist
//  on the server before anyone is told about it, so the notification payload
//  travels inside the operation and dispatches from the completed write. It
//  stays best-effort: the row is already saved, and a push that fails must never
//  fail the write.
//
//  SERIES SCOPE. "This and future" / "all events" enqueue one operation per
//  LOCAL sibling rather than one server-side batch statement. Every row then
//  retries, coalesces, and reports independently, and the create barrier can
//  order each one. The trade is that a sibling this device has never pulled is
//  not rewritten — the inbound window is ±12 months — where the old batch
//  statement covered the whole series. That coverage was illusory: the old path
//  cleared `needsSync` whether or not the batch landed, so a failed series edit
//  reported success and reverted. Real per-row delivery beats theoretical
//  whole-series reach.
//

import Foundation
import SwiftData

enum CalendarUserEventOutboundSync {

    static let entityType = SyncEntityType.calendarUserEvent
    static let table = SyncEntityType.calendarUserEvent.supabaseTable

    /// Columns `calendar_user_events` actually has. Everything else in a payload
    /// is local routing and is stripped before the write — PostgREST rejects the
    /// whole statement over one unknown column.
    static let validColumns: Set<String> = [
        "id", "user_id", "company_id", "type", "title",
        "start_date", "end_date", "all_day", "notes", "status",
        "address", "team_member_ids", "reviewed_by", "reviewed_at",
        "series_id", "created_at", "updated_at", "deleted_at"
    ]

    /// Local-only payload key carrying the notification to fire once the server
    /// has the row. Double-underscored so it can never collide with a column.
    static let notificationKey = "__time_off_notification"

    // MARK: - The notification that waits for the server

    /// Everything the time-off dispatch needs, captured at the moment the
    /// operator submitted and carried in the durable payload so an app kill
    /// between submit and delivery loses nothing.
    struct TimeOffNotification: Codable, Equatable {
        enum Kind: String, Codable {
            /// Submitted for approval — approvers are asked to review.
            case requested
            /// Booked outright by someone who holds the approval permission.
            case booked
        }

        let kind: Kind
        let companyId: String
        let requesterId: String
        let requesterName: String
        let targetUserId: String
        let targetName: String
        let eventTitle: String
        let startDate: Date
        let endDate: Date
    }

    // MARK: - Enqueue

    /// Queues the create for an event the surface has already inserted locally.
    /// The row keeps `needsSync = true` until the push is confirmed, which is
    /// also what stops the inbound merge from overwriting it in the meantime.
    /// Callers writing a batch (a recurring series, a multi-person time-off
    /// request) pass `deferPush` on every row and call `pushQueued` once —
    /// otherwise each recorded operation spawns its own push and N rows become
    /// a request storm that drops the connection.
    @MainActor
    static func enqueueCreate(
        _ event: CalendarUserEvent,
        notification: TimeOffNotification? = nil,
        syncEngine: SyncEngine,
        deferPush: Bool = false
    ) {
        var payload = columns(of: event)
        if let notification, let encoded = encode(notification) {
            payload[notificationKey] = encoded
        }
        syncEngine.recordOperation(
            entityType: entityType,
            entityId: event.id,
            operationType: "create",
            changedFields: payload,
            deferPush: deferPush
        )
    }

    /// Queues a field update for one row. `fields` are Supabase column names —
    /// the caller has already applied the same change locally.
    @MainActor
    static func enqueueUpdate(
        eventId: String,
        fields: [String: Any],
        syncEngine: SyncEngine,
        deferPush: Bool = false
    ) {
        guard !fields.isEmpty else { return }
        syncEngine.recordOperation(
            entityType: entityType,
            entityId: eventId,
            operationType: "update",
            changedFields: fields,
            deferPush: deferPush
        )
    }

    /// Queues the soft delete for one row.
    @MainActor
    static func enqueueDelete(
        eventId: String,
        syncEngine: SyncEngine,
        deferPush: Bool = false
    ) {
        syncEngine.recordOperation(
            entityType: entityType,
            entityId: eventId,
            operationType: "delete",
            changedFields: ["id": eventId],
            deferPush: deferPush
        )
    }

    /// One push for a batch of deferred rows.
    @MainActor
    static func pushQueued(syncEngine: SyncEngine) {
        Task { await syncEngine.pushPending() }
    }

    // MARK: - Payload building

    /// The full row as Supabase columns. Dates are ISO8601 so the payload
    /// survives JSON round-tripping in the operation store.
    static func columns(of event: CalendarUserEvent) -> [String: Any] {
        var payload: [String: Any] = [
            "id": event.id.lowercased(),
            "user_id": event.userId,
            "company_id": event.companyId,
            "type": event.type,
            "title": event.title,
            "start_date": SupabaseDate.format(event.startDate),
            "end_date": SupabaseDate.format(event.endDate),
            "all_day": event.allDay,
            "status": event.status
        ]
        if let notes = event.notes { payload["notes"] = notes }
        if let address = event.address { payload["address"] = address }
        if let teamMemberIds = event.teamMemberIds {
            payload["team_member_ids"] = teamMemberIds
        }
        if let reviewedBy = event.reviewedBy { payload["reviewed_by"] = reviewedBy }
        if let reviewedAt = event.reviewedAt {
            payload["reviewed_at"] = SupabaseDate.format(reviewedAt)
        }
        if let seriesId = event.seriesId {
            payload["series_id"] = seriesId.lowercased()
        }
        payload["created_at"] = SupabaseDate.format(event.createdAt)
        return payload
    }

    /// The editable field set the recurring-event helpers write, as columns.
    /// `detachFromSeries` folds into the same statement — the old path spent a
    /// separate round trip on it, and a detach that landed while the edit did
    /// not left the row half-changed.
    static func editColumns(
        title: String,
        notes: String?,
        allDay: Bool,
        teamMemberIds: [String]?,
        startDate: Date,
        endDate: Date,
        detachFromSeries: Bool
    ) -> [String: Any] {
        var fields: [String: Any] = [
            "title": title,
            "all_day": allDay,
            "start_date": SupabaseDate.format(startDate),
            "end_date": SupabaseDate.format(endDate)
        ]
        // NSNull is how a JSON payload says "write NULL" — omitting the key
        // would silently leave the old value in place.
        fields["notes"] = notes ?? NSNull()
        fields["team_member_ids"] = teamMemberIds ?? NSNull()
        if detachFromSeries {
            fields["series_id"] = NSNull()
        }
        return fields
    }

    // MARK: - Execution

    /// Handles every `calendarUserEvent` operation. Returns false for anything
    /// this subsystem does not own so the caller can fall through.
    @discardableResult
    static func executeIfHandled(
        entityType operationEntityType: String,
        operationType: String,
        entityId: String,
        payload: [String: Any],
        companyId: String,
        repositoryFactory: (String) -> CalendarUserEventRemoteWriting = {
            CalendarUserEventRepository(companyId: $0)
        }
    ) async throws -> Bool {
        guard operationEntityType == entityType.rawValue else { return false }

        let repository = repositoryFactory(companyId)
        let columns = payload.filter { validColumns.contains($0.key) }

        switch operationType {
        case "create":
            try await repository.upsertEvent(columns)
            // Server-confirmed. Only now is there something to notify about.
            await dispatchNotificationIfPresent(in: payload, eventId: entityId)

        case "update":
            try await repository.updateFields(entityId, fields: columns)

        case "delete":
            try await repository.softDelete(entityId)

        default:
            throw SyncError.encodingFailed(
                detail: "Unsupported calendarUserEvent operation: \(operationType)"
            )
        }
        return true
    }

    // MARK: - Confirmed-success bookkeeping

    /// Clears `needsSync` on the row a just-completed operation delivered.
    ///
    /// Runs inside the caller's completion transaction so the flag and the
    /// operation's `completed` status commit together — the flag is what holds
    /// the inbound merge off a locally-edited row, and clearing it a moment
    /// early would let a pull overwrite an edit that had not landed.
    ///
    /// The entity-type guard runs FIRST so the fetch below only ever happens on
    /// a calendar completion. The fetch itself is predicate-free and filtered in
    /// Swift — a `#Predicate` fetch can trap inside SwiftData against a table
    /// that has never held a row, and this sits on the completion path of every
    /// outbound operation. A user's calendar is a small table; a missing row
    /// (deleted locally after the push was queued) is simply nothing to clear.
    static func clearNeedsSyncOnCompletion(
        for operation: SyncOperation,
        in context: ModelContext
    ) throws {
        guard operation.entityType == entityType.rawValue else { return }
        let eventId = operation.entityId.lowercased()
        let rows = try context.fetch(FetchDescriptor<CalendarUserEvent>())
            .filter { $0.id.lowercased() == eventId }
        let now = Date()
        for row in rows {
            row.needsSync = false
            row.lastSyncedAt = now
        }
    }

    // MARK: - Launch backfill

    /// Rows left dirty with nothing queued to push them — the exact state every
    /// swallowed `try?` produced before this subsystem existed. Queues a write
    /// for each so stranded work drains and, if it cannot, becomes visible in
    /// PENDING WORK instead of sitting invisibly dirty forever.
    ///
    /// A row is stranded only when NO live operation already covers it; an op in
    /// any non-completed state is the queue already doing its job.
    static func strandedEvents(
        _ events: [CalendarUserEvent],
        operations: [SyncOperation]
    ) -> [CalendarUserEvent] {
        let coveredIds = Set(
            operations
                .filter {
                    $0.entityType == entityType.rawValue && $0.status != "completed"
                }
                .map { $0.entityId.lowercased() }
        )
        return events.filter {
            $0.needsSync && !coveredIds.contains($0.id.lowercased())
        }
    }

    /// The operation a stranded row needs: a tombstoned row has a delete
    /// outstanding, anything else has its current state to push. Upsert
    /// semantics make the create safe whether or not the server already has it.
    static func recoveryOperationType(for event: CalendarUserEvent) -> String {
        event.deletedAt == nil ? "create" : "delete"
    }

    /// Fetches dirty calendar rows and queues the writes they are missing.
    ///
    /// Both fetches are predicate-free and filtered in Swift: a `#Predicate`
    /// fetch of `SyncOperation` traps against a table that has never held a row,
    /// and this runs at launch on every device.
    @MainActor
    @discardableResult
    static func backfillStrandedEvents(
        in context: ModelContext,
        syncEngine: SyncEngine
    ) -> [String] {
        let events = (try? context.fetch(FetchDescriptor<CalendarUserEvent>())) ?? []
        guard events.contains(where: { $0.needsSync }) else { return [] }
        let operations = (try? context.fetch(FetchDescriptor<SyncOperation>())) ?? []

        let stranded = strandedEvents(events, operations: operations)
        for event in stranded {
            switch recoveryOperationType(for: event) {
            case "delete":
                enqueueDelete(eventId: event.id, syncEngine: syncEngine)
            default:
                enqueueCreate(event, syncEngine: syncEngine)
            }
        }
        if !stranded.isEmpty {
            print(
                "[CalendarUserEventOutboundSync] Queued \(stranded.count) "
                    + "stranded calendar event(s) that had no pending write"
            )
        }
        return stranded.map { $0.id.lowercased() }.sorted()
    }

    // MARK: - Notifications

    private static func encode(_ notification: TimeOffNotification) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(notification),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else { return nil }
        return object
    }

    static func decodeNotification(
        from payload: [String: Any]
    ) -> TimeOffNotification? {
        guard let object = payload[notificationKey],
              let data = try? JSONSerialization.data(withJSONObject: object),
              let notification = try? JSONDecoder()
                .decode(TimeOffNotification.self, from: data) else { return nil }
        return notification
    }

    /// Best-effort by design: the event is already on the server, so a failed
    /// push or rail insert must never fail the operation and send the whole
    /// write back through the retry cycle.
    private static func dispatchNotificationIfPresent(
        in payload: [String: Any],
        eventId: String
    ) async {
        guard let notification = decodeNotification(from: payload) else { return }
        switch notification.kind {
        case .requested:
            await notifyApproversOfRequest(notification, eventId: eventId)
        case .booked:
            await notifyBooked(notification, eventId: eventId)
        }
    }

    /// The rail is the server's: `notify_time_off_requested` reads the event
    /// row this operation just delivered and writes the requester's receipt,
    /// the on-behalf target's row, and one row per `time_off.approve` holder —
    /// recipients are never computed on this phone. The push wording below is
    /// verbatim from the two sheets this moved out of, and it reaches exactly
    /// the approvers the server reports as having received NEW rows.
    private static func notifyApproversOfRequest(
        _ notification: TimeOffNotification,
        eventId: String
    ) async {
        let dateRange = dateRange(
            startDate: notification.startDate,
            endDate: notification.endDate
        )
        let isSelfRequest = notification.requesterId == notification.targetUserId
        let approvalBody = isSelfRequest
            ? "\(notification.requesterName) requested time off: \(dateRange)"
            : "\(notification.requesterName) requested time off for \(notification.targetName): \(dateRange)"

        let pushed = await TimeOffRequestNotificationDispatcher.dispatchRequested(
            eventId: eventId,
            push: .init(
                title: "Time Off Request",
                body: approvalBody,
                data: [
                    "type": "time_off_requested",
                    "eventId": eventId,
                    "screen": "schedule"
                ]
            )
        )

        print(
            "[CalendarUserEventOutboundSync] Time-off request notified "
                + "\(pushed.count) scheduler(s)"
        )
    }

    /// The rail is the server's: `notify_time_off_booked` reads the event row
    /// this operation just delivered, confirms the recorded 'approved' state,
    /// and writes the target's row. The push wording stays the sheets' own and
    /// fires only when the server actually created a new row for someone other
    /// than the booker.
    private static func notifyBooked(
        _ notification: TimeOffNotification,
        eventId: String
    ) async {
        let dateRange = dateRange(
            startDate: notification.startDate,
            endDate: notification.endDate
        )
        let isSelfBooking = notification.requesterId == notification.targetUserId
        let body = isSelfBooking
            ? "Your time off for \(dateRange) is on the schedule."
            : "\(notification.requesterName) booked you off for \(dateRange)."

        _ = await TimeOffRequestNotificationDispatcher.dispatchBooked(
            eventId: eventId,
            targetUserId: notification.targetUserId,
            targetIsSelf: isSelfBooking,
            push: .init(
                title: "Time Off Booked",
                body: body,
                data: [
                    "type": "time_off_booked",
                    "eventId": eventId,
                    "screen": "schedule"
                ]
            )
        )

        print("[CalendarUserEventOutboundSync] Time off booked for \(notification.targetName)")
    }

    /// "Aug 18" for a single day, "Aug 18 – Aug 20" across days. Matches the
    /// range the sheets used so the copy is unchanged.
    static func dateRange(startDate: Date, endDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return formatter.string(from: startDate)
        }
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }
}

// MARK: - Repository seam

/// The writes this subsystem performs. A protocol so the queue can be exercised
/// without a network, matching the site-visit outbound seam.
protocol CalendarUserEventRemoteWriting {
    /// Insert-or-replace by primary key. Idempotent, so a create that lands but
    /// loses its response can retry without a duplicate-key park.
    func upsertEvent(_ columns: [String: Any]) async throws
    func updateFields(_ eventId: String, fields: [String: Any]) async throws
    func softDelete(_ eventId: String) async throws
}
