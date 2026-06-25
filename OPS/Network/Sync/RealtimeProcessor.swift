//
//  RealtimeProcessor.swift
//  OPS
//
//  Handles Supabase Realtime subscriptions with field-level merge
//  protection and reconnect catch-up. Features:
//   1. Pending-operation-aware field merge (skip fields with pending SyncOperations)
//   2. Disconnect / reconnect tracking with catch-up notification
//   3. Clean start / stop lifecycle
//

import Foundation
import SwiftData
import Supabase

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when realtime reconnects after a disconnect.
    /// userInfo contains "disconnectedAt" (Date) so SyncEngine can delta-pull.
    static let realtimeNeedsCatchUp = Notification.Name("realtimeNeedsCatchUp")

    /// Posted when a permission-related table changes via Realtime.
    /// SyncEngine observes this to re-fetch permissions and compare scopes.
    static let permissionsChanged = Notification.Name("permissionsChanged")

    /// Posted when a permission scope contracts (e.g., "all" -> "assigned").
    /// The app presents a blocking overlay requiring the user to refresh.
    static let permissionScopeContracted = Notification.Name("permissionScopeContracted")
}

// MARK: - RealtimeProcessor

@MainActor
final class RealtimeProcessor: ObservableObject {

    // MARK: - Published State

    @Published var isConnected: Bool = false
    var lastEventTimestamp: Date?

    // MARK: - Private State

    private var channel: RealtimeChannelV2?
    private var modelContext: ModelContext?
    private var companyId: String?
    private var userId: String?
    private var disconnectedAt: Date?

    /// True between an explicit `startListening`/`ensureListening` and an explicit
    /// `stopListening`. Distinguishes the internal teardown performed before a
    /// resubscribe (intent stays true) from a real stop (logout / backgrounding —
    /// intent clears). Drives whether a socket-status drop should auto-resubscribe.
    private var intendsToListen = false

    /// True while a subscribe is in flight. The lifecycle fires `ensureListening`
    /// from several triggers (cold launch, login, foreground, connectivity, socket
    /// recovery); without this guard two could interleave at the subscribe `await`
    /// and tear down each other's in-flight channel.
    private var isSubscribing = false

    /// Socket-level status observation. A websocket can die silently — server
    /// idle-close, NAT/proxy timeout, expired token — with NO ConnectivityManager
    /// network change, leaving the channel subscribed-but-dead and `isConnected`
    /// stuck true so postgres_changes silently stop arriving. Observing the
    /// realtime client's connection status lets us detect that drop, mark it for
    /// catch-up, and rebuild the subscription when the socket comes back.
    private var socketStatusObservation: RealtimeSubscription?

    /// Background data actor used when FeatureFlags.useDataActor is on.
    /// Supabase's channel subscription must stay on @MainActor (this class),
    /// but the SwiftData write inside each event handler dispatches to this actor.
    private weak var dataActor: DataActor?

    private let supabase: SupabaseClient
    private let decoder = JSONDecoder()

    /// Decoder for DTOs that decode `Date` directly (CalendarUserEventDTO).
    /// The plain `decoder` above works for DTOs that keep dates as String;
    /// realtime payload dates are ISO strings, so Date-typed DTOs need the
    /// Supabase-tolerant strategy.
    private static let userEventDecoder = SupabaseDate.makeISODecoder()

    /// Tables that filter on `company_id=eq.<companyId>`.
    ///
    /// ⚠️ EVERY table here MUST be a member of the `supabase_realtime` publication.
    /// Subscribing to a NON-published table makes the server's CDC
    /// `create_subscription` fail (Postgrex EncodeError) — and because all
    /// postgres_changes bindings share one channel join, a single bad table
    /// fails the ENTIRE channel ("Maximum retry attempts reached"), so NO realtime
    /// events arrive for ANY table (including the schedule). That is exactly what
    /// happened: `deck_designs`, the `catalog_*` tables, `company_default_products`,
    /// and the permission tables were subscribed here but were NOT in the
    /// publication, so live updates never worked. Those tables still sync via
    /// delta/full pull; only their (dead) realtime bindings were removed. Before
    /// adding a table here, confirm it is in the publication:
    ///   SELECT 1 FROM pg_publication_tables
    ///   WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='<t>';
    private let companyFilteredTables = [
        "projects",
        "project_tasks",
        "users",
        "clients",
        "sub_clients",
        "task_types",
        "project_notes",
        "project_photos",
        "project_photo_annotations"
    ]

    // MARK: - Init

    init(supabase: SupabaseClient = SupabaseService.shared.client) {
        self.supabase = supabase
    }

    /// Injects the background data actor. Called from SyncEngine.configure when
    /// FeatureFlags.useDataActor is enabled. Absent this, handleUpsert/handleDelete
    /// fall back to the legacy @MainActor path.
    func setDataActor(_ actor: DataActor) {
        self.dataActor = actor
    }

    // MARK: - Start Listening

    /// Subscribe to Realtime only if not already live for this company. Safe to
    /// call from every "the app is foregrounded / authenticated" trigger (cold
    /// launch, login, foreground, connectivity-restore) — a redundant call while
    /// already subscribed is a no-op, so the channel is never needlessly churned.
    /// The previous code only ever started Realtime on background→foreground, so
    /// a freshly launched app that stayed foregrounded never subscribed at all
    /// and teammate edits only arrived on the next periodic sync.
    func ensureListening(companyId: String, userId: String? = nil, context: ModelContext) async {
        if isConnected, self.companyId == companyId, channel != nil {
            return
        }
        await startListening(companyId: companyId, userId: userId, context: context)
    }

    /// Subscribe to Supabase Realtime for all core entity tables scoped to a company.
    func startListening(companyId: String, userId: String? = nil, context: ModelContext) async {
        self.companyId = companyId
        self.userId = userId
        self.modelContext = context
        intendsToListen = true

        // Serialize subscribes — a concurrent caller must not tear down the
        // channel this one is mid-way through establishing.
        guard !isSubscribing else { return }
        isSubscribing = true
        defer { isSubscribing = false }

        // Tear down any previous channel (without clearing listen intent).
        await teardownChannel()

        // Observe socket-level status so a silent websocket drop self-heals.
        observeSocketStatus()

        let channel = supabase.channel("company-\(companyId)")

        // Core entity tables filtered by company_id
        for table in companyFilteredTables {
            subscribeToTable(channel: channel, table: table, filter: "company_id=eq.\(companyId)")
        }

        // Companies table filters on `id`, not `company_id`
        subscribeToTable(channel: channel, table: "companies", filter: "id=eq.\(companyId)")

        // Expenses, expense envelopes (batches), and calendar events filtered by company_id.
        // expense_batches drives live envelope-status flips (filling → with the office,
        // auto-approved) and total recalcs in the review hub + crew list.
        subscribeToTable(channel: channel, table: "expenses", filter: "company_id=eq.\(companyId)")
        subscribeToTable(channel: channel, table: "expense_batches", filter: "company_id=eq.\(companyId)")
        subscribeToTable(channel: channel, table: "calendar_user_events", filter: "company_id=eq.\(companyId)")

        // Notifications filtered by user_id (user-specific)
        if let userId = userId {
            subscribeToTable(channel: channel, table: "notifications", filter: "user_id=eq.\(userId)")

            // NOTE: the permission tables (user_roles, user_permission_overrides,
            // role_permissions) are intentionally NOT subscribed here — they are
            // NOT in the supabase_realtime publication, so their bindings failed
            // the whole channel join (role_permissions crashed the server's
            // create_subscription outright). Permission changes are rare and
            // admin-driven; they are picked up on the next foreground / periodic
            // sync. Re-add a live subscription ONLY after adding the table to the
            // publication and verifying the channel still subscribes.
        }

        do {
            try await channel.subscribeWithError()
            self.channel = channel
            self.isConnected = true
            print("[RT_TRACE] ✅ SUBSCRIBED for company \(companyId) — \(companyFilteredTables.count + 4) tables")

            // If we had a previous disconnect, trigger catch-up
            if let disconnected = disconnectedAt {
                handleReconnect(disconnectedSince: disconnected)
                disconnectedAt = nil
            }
        } catch {
            print("[RT_TRACE] ❌ SUBSCRIBE FAILED for company \(companyId): \(error)")
            self.isConnected = false
        }
    }

    // MARK: - Stop Listening

    /// Permanently stop Realtime (logout / backgrounding). Clears listen intent
    /// and the socket-status observer so a later socket event can't resurrect a
    /// subscription we deliberately tore down.
    func stopListening() async {
        intendsToListen = false
        socketStatusObservation?.cancel()
        socketStatusObservation = nil
        await teardownChannel()
        print("[RealtimeProcessor] Unsubscribed")
    }

    /// Remove the current channel without touching listen intent or the socket
    /// observer. Used both by the real stop above and by `startListening` before
    /// it resubscribes — a resubscribe must keep `intendsToListen` true.
    private func teardownChannel() async {
        guard let channel = channel else { return }
        await channel.unsubscribe()
        await supabase.removeChannel(channel)
        self.channel = nil
        isConnected = false
    }

    // MARK: - Socket-Status Recovery

    /// Install a one-time observer on the realtime client's connection status.
    /// Idempotent — repeated `startListening` calls won't stack observers.
    private func observeSocketStatus() {
        guard socketStatusObservation == nil else { return }
        socketStatusObservation = supabase.realtimeV2.onStatusChange { [weak self] status in
            Task { @MainActor [weak self] in
                self?.handleSocketStatus(status)
            }
        }
    }

    private func handleSocketStatus(_ status: RealtimeClientStatus) {
        print("[RT_TRACE] 🔌 socket status: \(status)")
        guard intendsToListen else { return }
        switch status {
        case .disconnected:
            // Record the drop so reconnect triggers a catch-up delta. Does not
            // tear down the channel — the SDK owns reconnection of the socket.
            handleDisconnect()
        case .connected:
            // Socket is back. If our channel went down with it, rebuild a clean
            // subscription; startListening's reconnect path delta-syncs the gap.
            if !isConnected {
                Task { [weak self] in await self?.resubscribeAfterDrop() }
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    /// Rebuild the subscription after a silent socket drop, re-using the last
    /// company/user/context. No-op if intent was cleared (logout) in the interim.
    private func resubscribeAfterDrop() async {
        guard intendsToListen,
              let companyId = companyId,
              let modelContext = modelContext else { return }
        print("[RealtimeProcessor] Socket recovered — rebuilding subscription")
        await startListening(companyId: companyId, userId: userId, context: modelContext)
    }

    // MARK: - Disconnect / Reconnect

    /// Call when the WebSocket or network drops.
    func handleDisconnect() {
        guard isConnected else { return }
        disconnectedAt = Date()
        isConnected = false
        print("[RealtimeProcessor] Disconnected at \(disconnectedAt!)")
    }

    /// Post a notification so SyncEngine can delta-pull from the disconnect timestamp.
    private func handleReconnect(disconnectedSince: Date) {
        print("[RealtimeProcessor] Reconnected — requesting catch-up from \(disconnectedSince)")
        NotificationCenter.default.post(
            name: .realtimeNeedsCatchUp,
            object: nil,
            userInfo: ["disconnectedAt": disconnectedSince]
        )
    }

    // MARK: - Table Subscription Helper

    private func subscribeToTable(channel: RealtimeChannelV2, table: String, filter: String) {
        let _ = channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: table,
            filter: filter
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleChange(table: table, action: action)
            }
        }
    }

    // MARK: - Change Routing

    private func handleChange(table: String, action: AnyAction) {
        lastEventTimestamp = Date()

        switch action {
        case .insert(let insertAction):
            print("[RT_TRACE] ⚡️ EVENT received: INSERT \(table)")
            handleUpsert(table: table, record: insertAction)

        case .update(let updateAction):
            print("[RT_TRACE] ⚡️ EVENT received: UPDATE \(table)")
            handleUpsert(table: table, record: updateAction)

        case .delete(let deleteAction):
            print("[RT_TRACE] ⚡️ EVENT received: DELETE \(table)")
            handleDelete(table: table, action: deleteAction)
        }
    }

    // MARK: - Upsert with Field-Level Merge

    /// Decodes the Realtime record into the appropriate DTO, converts to a SwiftData
    /// model, and performs a field-by-field update — skipping any field that has a
    /// pending SyncOperation (to preserve the local value until it syncs).
    private func handleUpsert(table: String, record: some HasRecord) {
        // Actor path: decode on main, scope-guard on main, dispatch merge to DataActor.
        // Legacy path follows below when the feature flag is off.
        if FeatureFlags.useDataActor, let actor = dataActor {
            dispatchUpsertToActor(table: table, record: record, actor: actor)
            return
        }

        guard let context = modelContext else { return }

        do {
            switch table {
            case "projects":
                let dto = try record.decodeRecord(as: SupabaseProjectDTO.self, decoder: decoder)

                // Bug G9 — client-side scope guards removed. Supabase RLS
                // (migration 074, private.current_user_can_view_project) enforces
                // both team-based and mention-based grant. Any row delivered here
                // has already passed RLS and is valid to persist.

                let model = dto.toModel()
                let pendingFields = protectedFieldsForEntity(entityType: .project, entityId: dto.id, context: context)
                try upsertProject(context: context, id: dto.id, dto: dto, model: model, pendingFields: pendingFields)
                // Legacy path saves on mainContext, which never fires the
                // actor's didSave rebroadcast — post the inbound signal
                // directly so snapshot caches (calendar) invalidate.
                InboundChangeSignal.post(entityNames: ["Project"])

            case "project_tasks":
                let dto = try record.decodeRecord(as: SupabaseProjectTaskDTO.self, decoder: decoder)

                // Bug G9 — client-side scope guards removed. See "projects" case above.

                // Canonicalize uuid to lowercase to match local storage.
                let id = dto.id.lowercased()
                let model = dto.toModel()
                model.id = id
                let pendingFields = protectedFieldsForEntity(entityType: .projectTask, entityId: id, context: context)
                try upsertProjectTask(context: context, id: id, model: model, pendingFields: pendingFields)
                InboundChangeSignal.post(entityNames: ["ProjectTask"])
                Task { @MainActor in
                    await CalendarMirrorService.shared.mirrorEvent(opsId: id, source: .projectTask)
                }

            case "users":
                let dto = try record.decodeRecord(as: SupabaseUserDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = protectedFieldsForEntity(entityType: .user, entityId: dto.id, context: context)
                try upsertUser(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "clients":
                let dto = try record.decodeRecord(as: SupabaseClientDTO.self, decoder: decoder)

                // Permission scope guard for clients
                // Clients don't have team_member_ids or createdBy in the DTO,
                // so client-side filtering is not possible. Supabase RLS handles
                // scope enforcement for "assigned" and "own" at the server level.

                let model = dto.toModel()
                let pendingFields = protectedFieldsForEntity(entityType: .client, entityId: dto.id, context: context)
                try upsertClient(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "companies":
                let dto = try record.decodeRecord(as: SupabaseCompanyDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = protectedFieldsForEntity(entityType: .company, entityId: dto.id, context: context)
                try upsertCompany(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "task_types":
                let dto = try record.decodeRecord(as: SupabaseTaskTypeDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = protectedFieldsForEntity(entityType: .taskType, entityId: dto.id, context: context)
                try upsertTaskType(context: context, id: dto.id, model: model, pendingFields: pendingFields)
                InboundChangeSignal.post(entityNames: ["TaskType"])

            case "sub_clients":
                let dto = try record.decodeRecord(as: SupabaseSubClientDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = protectedFieldsForEntity(entityType: .subClient, entityId: dto.id, context: context)
                // Link parent client relationship
                let parentId = dto.parentClientId
                let clientDescriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == parentId })
                if let parentClient = try? context.fetch(clientDescriptor).first {
                    model.client = parentClient
                }
                try upsertSubClient(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "project_notes":
                let dto = try record.decodeRecord(as: ProjectNoteDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = protectedFieldsForEntity(entityType: .projectNote, entityId: dto.id, context: context)
                try upsertProjectNote(context: context, id: dto.id, model: model, pendingFields: pendingFields)
                // Notify views listening for new project notes
                NotificationCenter.default.post(
                    name: .projectNoteReceived,
                    object: nil,
                    userInfo: ["projectId": dto.projectId]
                )
                // Bug G9 — rebuild mention-access index so new / revoked mentions
                // resolve immediately; if the mention targets the current user
                // and the project isn't cached locally, fetch it.
                handleMentionAccessRealtimeUpdate(noteDTO: dto, context: context)

            case "project_photos":
                let dto = try record.decodeRecord(as: ProjectPhotoDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = protectedFieldsForEntity(entityType: .projectPhoto, entityId: dto.id, context: context)
                try upsertProjectPhoto(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "project_photo_annotations":
                let dto = try record.decodeRecord(as: PhotoAnnotationDTO.self, decoder: decoder)
                let model = dto.toModel()
                let pendingFields = protectedFieldsForEntity(entityType: .photoAnnotation, entityId: dto.id, context: context)
                try upsertPhotoAnnotation(context: context, id: dto.id, model: model, pendingFields: pendingFields)

            case "deck_designs":
                let dto = try record.decodeRecord(as: SupabaseDeckDesignDTO.self, decoder: decoder)
                let pendingFields = protectedFieldsForEntity(entityType: .deckDesign, entityId: dto.id, context: context)
                try upsertDeckDesign(context: context, id: dto.id, dto: dto, pendingFields: pendingFields)

            case "expenses", "expense_batches":
                NotificationCenter.default.post(name: .expenseUpdated, object: nil)
                NotificationCenter.default.post(name: .opsExpensesDidChange, object: nil)

            case "calendar_user_events":
                NotificationCenter.default.post(name: .calendarEventUpdated, object: nil)
                Task { @MainActor in
                    await CalendarMirrorService.shared.reconcileAll()
                }

            case "notifications":
                NotificationCenter.default.post(name: .notificationReceived, object: nil)

            case "user_roles", "role_permissions", "user_permission_overrides":
                print("[RealtimeProcessor] Permission change detected on \(table)")
                NotificationCenter.default.post(name: .permissionsChanged, object: nil)

            default:
                print("[RealtimeProcessor] Received change on \(table) (no handler)")
            }
        } catch {
            print("[RealtimeProcessor] Error upserting on \(table): \(error)")
        }
    }

    // MARK: - Soft Delete

    private func handleDelete(table: String, action: DeleteAction) {
        if FeatureFlags.useDataActor, let actor = dataActor {
            dispatchDeleteToActor(table: table, action: action, actor: actor)
            return
        }

        guard let context = modelContext else { return }

        struct IdPayload: Decodable { let id: String }

        do {
            let payload = try action.decodeOldRecord(as: IdPayload.self, decoder: decoder)
            let id = payload.id

            switch table {
            case "projects":
                let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }
                InboundChangeSignal.post(entityNames: ["Project"])

            case "project_tasks":
                let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }
                InboundChangeSignal.post(entityNames: ["ProjectTask"])
                Task { @MainActor in
                    await CalendarMirrorService.shared.unmirrorEvent(opsId: id)
                }

            case "users":
                let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "clients":
                let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "companies":
                let descriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "task_types":
                let descriptor = FetchDescriptor<TaskType>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }
                InboundChangeSignal.post(entityNames: ["TaskType"])

            case "sub_clients":
                let descriptor = FetchDescriptor<SubClient>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "project_notes":
                let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }
                // Bug G9 — soft-delete of a note may revoke mention access.
                if let userId = self.userId {
                    MentionAccessIndex.shared.rebuild(context: context, userId: userId)
                }

            case "project_photos":
                let descriptor = FetchDescriptor<ProjectPhoto>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "project_photo_annotations":
                let descriptor = FetchDescriptor<PhotoAnnotation>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "deck_designs":
                let descriptor = FetchDescriptor<DeckDesign>(predicate: #Predicate { $0.id == id })
                if let existing = try context.fetch(descriptor).first {
                    existing.deletedAt = Date()
                    try context.save()
                }

            case "expenses", "expense_batches":
                NotificationCenter.default.post(name: .expenseUpdated, object: nil)
                NotificationCenter.default.post(name: .opsExpensesDidChange, object: nil)

            case "calendar_user_events":
                NotificationCenter.default.post(name: .calendarEventUpdated, object: nil)
                Task { @MainActor in
                    await CalendarMirrorService.shared.unmirrorEvent(opsId: id)
                }

            case "notifications":
                NotificationCenter.default.post(name: .notificationReceived, object: nil)

            case "user_roles", "role_permissions", "user_permission_overrides":
                print("[RealtimeProcessor] Permission deletion detected on \(table)")
                NotificationCenter.default.post(name: .permissionsChanged, object: nil)

            default:
                print("[RealtimeProcessor] Delete on \(table) (no handler)")
            }
        } catch {
            print("[RealtimeProcessor] Error handling delete on \(table): \(error)")
        }
    }

    // MARK: - DataActor Dispatch (flag-gated)

    /// Decodes the realtime payload on MainActor, applies scope guards (PermissionStore
    /// reads are main-safe here), then hands a Sendable RealtimeUpdate case to the
    /// background actor for transaction-wrapped merge.
    ///
    /// Filtering DTOs BEFORE the actor boundary avoids sending discarded records across
    /// actors. Non-merge tables (expenses, calendar_user_events, notifications, permissions)
    /// bypass the actor entirely — they just post NotificationCenter events on main.
    private func dispatchUpsertToActor<R: HasRecord>(table: String, record: R, actor: DataActor) {
        do {
            switch table {
            case "projects":
                // Bug G9 — client-side scope guards removed. RLS (migration 074)
                // enforces team-based and mention-based grant server-side.
                let dto = try record.decodeRecord(as: SupabaseProjectDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.project(dto)) }

            case "project_tasks":
                // Bug G9 — client-side scope guards removed. See "projects" case.
                let dto = try record.decodeRecord(as: SupabaseProjectTaskDTO.self, decoder: decoder)
                print("[DUPE_TRACE] RT.dispatch id=\(dto.id) → DataActor.handleRealtimeUpdate(.task)")
                Task {
                    await actor.handleRealtimeUpdate(.task(dto))
                    // Legacy-path parity (see handleUpsert): refresh the
                    // iPhone-Calendar mirror AFTER the merge lands so a
                    // teammate's reschedule moves the mirrored event too.
                    await CalendarMirrorService.shared.mirrorEvent(opsId: dto.id.lowercased(), source: .projectTask)
                }

            case "users":
                let dto = try record.decodeRecord(as: SupabaseUserDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.user(dto)) }

            case "clients":
                // Scope enforcement for clients is server-side (RLS) — no client-side filter.
                let dto = try record.decodeRecord(as: SupabaseClientDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.client(dto)) }

            case "companies":
                let dto = try record.decodeRecord(as: SupabaseCompanyDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.company(dto)) }

            case "task_types":
                let dto = try record.decodeRecord(as: SupabaseTaskTypeDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.taskType(dto)) }

            case "sub_clients":
                let dto = try record.decodeRecord(as: SupabaseSubClientDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.subClient(dto)) }

            case "project_notes":
                let dto = try record.decodeRecord(as: ProjectNoteDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.projectNote(dto)) }
                // Preserve legacy side-effect: notify views listening for new notes.
                NotificationCenter.default.post(
                    name: .projectNoteReceived,
                    object: nil,
                    userInfo: ["projectId": dto.projectId]
                )
                // Bug G9 — same as legacy path: refresh mention-access.
                if let context = modelContext {
                    handleMentionAccessRealtimeUpdate(noteDTO: dto, context: context)
                }

            case "project_photos":
                let dto = try record.decodeRecord(as: ProjectPhotoDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.projectPhoto(dto)) }

            case "project_photo_annotations":
                let dto = try record.decodeRecord(as: PhotoAnnotationDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.photoAnnotation(dto)) }

            case "deck_designs":
                let dto = try record.decodeRecord(as: SupabaseDeckDesignDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.deckDesign(dto)) }

            // Catalog parents — Option A: only parent tables fire realtime;
            // their children (option values, joins, snapshot items, order
            // items, product extension rows) refetch on the next pullDelta.
            case "catalog_categories":
                let dto = try record.decodeRecord(as: CatalogCategoryDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.catalogCategory(dto)) }

            case "catalog_units":
                let dto = try record.decodeRecord(as: CatalogUnitDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.catalogUnit(dto)) }

            case "catalog_tags":
                let dto = try record.decodeRecord(as: CatalogTagDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.catalogTag(dto)) }

            case "catalog_items":
                let dto = try record.decodeRecord(as: CatalogItemDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.catalogItem(dto)) }

            case "catalog_variants":
                let dto = try record.decodeRecord(as: CatalogVariantDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.catalogVariant(dto)) }

            case "catalog_snapshots":
                let dto = try record.decodeRecord(as: CatalogSnapshotDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.catalogSnapshot(dto)) }

            case "catalog_orders":
                let dto = try record.decodeRecord(as: CatalogOrderDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.catalogOrder(dto)) }

            case "company_default_products":
                let dto = try record.decodeRecord(as: CompanyDefaultProductDTO.self, decoder: decoder)
                Task { await actor.handleRealtimeUpdate(.companyDefaultProduct(dto)) }

            // Non-merge tables: no actor involvement, just post events on main.
            case "expenses", "expense_batches":
                NotificationCenter.default.post(name: .expenseUpdated, object: nil)
                NotificationCenter.default.post(name: .opsExpensesDidChange, object: nil)
            case "calendar_user_events":
                // Merge the row so a time-off / personal-event change is live
                // (the legacy path deferred to the next pullDelta). The local
                // store and CalendarViewModel.loadUserEvents only ever hold
                // the CURRENT user's events (fetchForUser scope) — the
                // company-wide realtime filter also delivers teammates' rows,
                // so those are skipped to preserve visibility semantics.
                let dto = try record.decodeRecord(as: CalendarUserEventDTO.self, decoder: Self.userEventDecoder)
                if let userId = self.userId, dto.userId == userId {
                    Task {
                        await actor.handleRealtimeUpdate(.calendarUserEvent(dto))
                        // Legacy-path parity: refresh the iPhone-Calendar mirror.
                        await CalendarMirrorService.shared.reconcileAll()
                    }
                }
                NotificationCenter.default.post(name: .calendarEventUpdated, object: nil)
            case "notifications":
                NotificationCenter.default.post(name: .notificationReceived, object: nil)
            case "user_roles", "role_permissions", "user_permission_overrides":
                print("[RealtimeProcessor] Permission change detected on \(table)")
                NotificationCenter.default.post(name: .permissionsChanged, object: nil)

            default:
                print("[RealtimeProcessor] Received change on \(table) (no handler)")
            }
        } catch {
            print("[RealtimeProcessor] Error decoding for actor on \(table): \(error)")
        }
    }

    private func dispatchDeleteToActor(table: String, action: DeleteAction, actor: DataActor) {
        struct IdPayload: Decodable { let id: String }
        do {
            switch table {
            case "projects", "users", "clients", "companies",
                 "task_types", "sub_clients", "project_notes", "project_photos",
                 "project_photo_annotations",
                 "deck_designs",
                 // Catalog parents with surrogate-id identity. catalog_snapshots
                 // is append-only (no DELETE expected) and company_default_products
                 // uses a composite key (no surrogate id), so neither is dispatched.
                 "catalog_categories", "catalog_units", "catalog_tags",
                 "catalog_items", "catalog_variants", "catalog_orders":
                let payload = try action.decodeOldRecord(as: IdPayload.self, decoder: decoder)
                Task { await actor.softDeleteFromRealtime(table: table, id: payload.id) }

            case "project_tasks":
                let payload = try action.decodeOldRecord(as: IdPayload.self, decoder: decoder)
                Task {
                    await actor.softDeleteFromRealtime(table: table, id: payload.id)
                    // Legacy-path parity (see handleDelete): drop the mirrored
                    // iPhone-Calendar event for the deleted task.
                    await CalendarMirrorService.shared.unmirrorEvent(opsId: payload.id)
                }

            case "expenses", "expense_batches":
                NotificationCenter.default.post(name: .expenseUpdated, object: nil)
                NotificationCenter.default.post(name: .opsExpensesDidChange, object: nil)
            case "calendar_user_events":
                // Soft-delete the local row (only the current user's events
                // ever exist locally — see upsert case) and drop the mirrored
                // iPhone-Calendar event. Legacy parity plus live local removal.
                let payload = try action.decodeOldRecord(as: IdPayload.self, decoder: decoder)
                Task {
                    await actor.softDeleteFromRealtime(table: table, id: payload.id)
                    await CalendarMirrorService.shared.unmirrorEvent(opsId: payload.id)
                }
                NotificationCenter.default.post(name: .calendarEventUpdated, object: nil)
            case "notifications":
                NotificationCenter.default.post(name: .notificationReceived, object: nil)
            case "user_roles", "role_permissions", "user_permission_overrides":
                print("[RealtimeProcessor] Permission deletion detected on \(table)")
                NotificationCenter.default.post(name: .permissionsChanged, object: nil)

            default:
                print("[RealtimeProcessor] Delete on \(table) (no handler)")
            }
        } catch {
            print("[RealtimeProcessor] Error decoding delete for actor on \(table): \(error)")
        }
    }

    // MARK: - Pending Fields Check

    /// Returns the set of field names that have pending SyncOperations for a given entity.
    /// These fields should NOT be overwritten by incoming server values.
    /// Bug G9 — on an incoming ProjectNote realtime event, keep the mention
    /// access index in sync. If the note mentions the current user AND the
    /// referenced project isn't in the local cache yet, fetch it so the user
    /// can reach it via Search / Spotlight / deep link without waiting for
    /// the next full sync.
    private func handleMentionAccessRealtimeUpdate(noteDTO: ProjectNoteDTO, context: ModelContext) {
        guard let uid = self.userId else { return }

        MentionAccessIndex.shared.rebuild(context: context, userId: uid)

        // If the note mentions this user and the project isn't local, fetch it.
        let mentionsMe = noteDTO.mentionedUserIds?.contains(uid) == true
        guard mentionsMe else { return }

        let projectId = noteDTO.projectId
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
        let alreadyCached = (try? context.fetch(descriptor).first) != nil
        if alreadyCached { return }

        guard let companyId = self.companyId else { return }
        Task { @MainActor in
            do {
                let dto = try await ProjectRepository(companyId: companyId).fetchOne(projectId)
                let model = dto.toModel()
                let pendingFields = self.protectedFieldsForEntity(
                    entityType: .project, entityId: dto.id, context: context
                )
                try self.upsertProject(context: context, id: dto.id, dto: dto, model: model, pendingFields: pendingFields)
                try context.save()
                print("[RealtimeProcessor] G9 — fetched mention-granted project \(projectId)")
            } catch {
                print("[RealtimeProcessor] G9 — failed to fetch mention-granted project \(projectId): \(error)")
            }
        }
    }

    /// Fields with a strictly-`pending` SyncOperation. Used ONLY to decide
    /// whether `needsSync` may be cleared after a merge — that must stay keyed to
    /// un-pushed work, not to the recent-write window, so a completed push still
    /// clears the dirty flag promptly.
    private func pendingFieldsForEntity(
        entityType: SyncEntityType,
        entityId: String,
        context: ModelContext
    ) -> Set<String> {
        let entityTypeRaw = entityType.rawValue
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.entityType == entityTypeRaw
                && $0.entityId == entityId
                && $0.status == "pending"
            }
        )

        guard let ops = try? context.fetch(descriptor) else { return [] }

        var fields = Set<String>()
        for op in ops {
            for field in op.getChangedFields() {
                fields.insert(field)
            }
        }
        return fields
    }

    /// Fields an incoming realtime row must NOT overwrite: those with a pending
    /// OR recently in-flight / completed local write (see SyncFieldGuard). This
    /// is the field-level analogue of the insert-branch `hasRecentLocalWrite`
    /// guard, and closes the race where a websocket echo lands mid-push (op
    /// already flipped past "pending") and reverts the just-saved edit.
    private func protectedFieldsForEntity(
        entityType: SyncEntityType,
        entityId: String,
        context: ModelContext
    ) -> Set<String> {
        let entityTypeRaw = entityType.rawValue
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.entityType == entityTypeRaw
                && $0.entityId == entityId
            }
        )

        guard let ops = try? context.fetch(descriptor) else { return [] }

        return SyncFieldGuard.protectedFields(from: ops, now: Date())
    }

    /// Returns true if a SyncOperation for this entity had ANY lifecycle event
    /// (created / attempted / completed) within the given window, regardless
    /// of current status. Considers all three timestamps so the window covers
    /// freshly-recorded, push-in-flight, recently-completed, and
    /// offline-delayed-push cases.
    private func hasRecentLocalWrite(
        entityType: SyncEntityType,
        entityId: String,
        withinSeconds seconds: TimeInterval,
        context: ModelContext
    ) -> Bool {
        let typeStr = entityType.rawValue
        let idLower = entityId.lowercased()
        let idUpper = entityId.uppercased()
        let predicate = #Predicate<SyncOperation> { op in
            op.entityType == typeStr &&
            (op.entityId == idLower || op.entityId == idUpper || op.entityId == entityId)
        }
        let descriptor = FetchDescriptor<SyncOperation>(predicate: predicate)
        guard let ops = try? context.fetch(descriptor), !ops.isEmpty else {
            return false
        }

        let cutoff = Date().addingTimeInterval(-seconds)
        for op in ops {
            if op.createdAt >= cutoff { return true }
            if let last = op.lastAttemptedAt, last >= cutoff { return true }
            if let completed = op.completedAt, completed >= cutoff { return true }
        }
        return false
    }

    // MARK: - Per-Type Upsert Helpers (field-level merge with pending check)

    private func upsertProject(
        context: ModelContext,
        id: String,
        dto: SupabaseProjectDTO,
        model: Project,
        pendingFields: Set<String>
    ) throws {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        print("[DUPE_TRACE] RT.upsertProject id=\(id) existing_count=\(existingCount) ctx=\(ObjectIdentifier(context))")

        if let existing = try context.fetch(descriptor).first {
            // Bug 209281ba — pendingFields is built from SyncOperation.changedFields
            // which uses server-side wire names ("project_images",
            // "team_member_ids", "company_id", etc.). Compare against those, not
            // Swift property names, otherwise the protection silently fails and
            // realtime overwrites local optimistic writes (e.g., comment-photo
            // URLs appended to projectImagesString disappear).
            if !pendingFields.contains("title")             { existing.title = model.title }
            if !pendingFields.contains("status")            { existing.status = model.status }
            if !pendingFields.contains("company_id")        { existing.companyId = model.companyId }
            if !pendingFields.contains("client_id")         { existing.clientId = model.clientId }
            if !pendingFields.contains("opportunity_id")    { existing.opportunityId = model.opportunityId }
            if !pendingFields.contains("address")           { existing.address = model.address }
            if !pendingFields.contains("latitude")          { existing.latitude = model.latitude }
            if !pendingFields.contains("longitude")         { existing.longitude = model.longitude }
            if !pendingFields.contains("start_date")        { existing.startDate = model.startDate }
            if !pendingFields.contains("end_date")          { existing.endDate = model.endDate }
            if !pendingFields.contains("duration")          { existing.duration = model.duration }
            if !pendingFields.contains("notes")             { existing.notes = model.notes }
            if !pendingFields.contains("description")       { existing.projectDescription = model.projectDescription }
            if !pendingFields.contains("all_day")           { existing.allDay = model.allDay }
            if !pendingFields.contains("team_member_ids")   { existing.teamMemberIdsString = model.teamMemberIdsString }
            if !pendingFields.contains("project_images")    { existing.projectImagesString = model.projectImagesString }
            if !pendingFields.contains("deleted_at")        { existing.deletedAt = model.deletedAt }
            try upsertProjectVinylOrderMarker(context: context, dto: dto, pendingFields: pendingFields)
            existing.lastSyncedAt = Date()
            let pendingFieldsForSync = pendingFieldsForEntity(entityType: .project, entityId: existing.id, context: context)
            if pendingFieldsForSync.isEmpty {
                existing.needsSync = false
            }
        } else {
            // Origin suppression: if we wrote this entityId locally within the
            // last 60s — regardless of SyncOperation status (pending, inProgress,
            // completed) — the realtime payload is our own write echoing back.
            // Inserting here would produce a duplicate because Project.id
            // lacks @Attribute(.unique). Mirrors the ProjectTask suppression
            // below (bug f86cf554 / 858fa5e).
            if hasRecentLocalWrite(entityType: .project, entityId: id, withinSeconds: 60, context: context) {
                print("[DUPE_TRACE] RT.upsertProject SUPPRESSED id=\(id) — recent local write within 60s")
                try context.save()
                return
            }

            print("[DUPE_TRACE] RT.upsertProject INSERT id=\(id) — no recent local write, treating as remote create")
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
            let marker = dto.toVinylOrderMarkerModel()
            marker.lastSyncedAt = Date()
            context.insert(marker)
        }
        try context.save()
    }

    private func upsertProjectVinylOrderMarker(
        context: ModelContext,
        dto: SupabaseProjectDTO,
        pendingFields: Set<String>
    ) throws {
        let projectId = dto.id
        let descriptor = FetchDescriptor<ProjectVinylOrderMarker>(
            predicate: #Predicate { $0.id == projectId }
        )
        let marker: ProjectVinylOrderMarker
        if let existing = try context.fetch(descriptor).first {
            marker = existing
        } else {
            marker = ProjectVinylOrderMarker(projectId: projectId)
            context.insert(marker)
        }

        if !pendingFields.contains(ProjectVinylOrderFields.status) {
            marker.status = dto.resolvedVinylOrderStatus
        }
        if !pendingFields.contains(ProjectVinylOrderFields.orderedAt) {
            marker.orderedAt = dto.vinylOrderedAt.flatMap { SupabaseDate.parse($0) }
        }
        if !pendingFields.contains(ProjectVinylOrderFields.orderedBy) {
            marker.orderedBy = dto.vinylOrderedBy
        }
        marker.sourceProjectUpdatedAt = dto.updatedAt.flatMap { SupabaseDate.parse($0) }
        marker.lastSyncedAt = Date()
    }

    private func upsertProjectTask(context: ModelContext, id: String, model: ProjectTask, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == id })
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        print("[DUPE_TRACE] RT.upsertProjectTask id=\(id) existing_count=\(existingCount) ctx=\(ObjectIdentifier(context))")

        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("status")                { existing.status = model.status }
            if !pendingFields.contains("task_notes")             { existing.taskNotes = model.taskNotes }
            if !pendingFields.contains("custom_title")           { existing.customTitle = model.customTitle }
            if !pendingFields.contains("task_color")             { existing.taskColor = model.taskColor }
            if !pendingFields.contains("task_type_id") {
                existing.taskTypeId = model.taskTypeId
                // Rewire TaskType `@Relationship` to match the new id so UI
                // (badge color, display name) updates immediately. Realtime
                // updates do not trigger the end-of-sync linkAllRelationships
                // pass, so without this the relationship stays stale.
                if !existing.taskTypeId.isEmpty {
                    let ttId = existing.taskTypeId
                    if let newType = try? context.fetch(
                        FetchDescriptor<TaskType>(predicate: #Predicate<TaskType> { $0.id == ttId })
                    ).first {
                        if existing.taskType?.id != newType.id { existing.taskType = newType }
                    }
                } else if existing.taskType != nil {
                    existing.taskType = nil
                }
            }
            if !pendingFields.contains("start_date")             { existing.startDate = model.startDate }
            if !pendingFields.contains("end_date")               { existing.endDate = model.endDate }
            // Time-of-day gates were absent here, so a realtime echo could clobber
            // a pending TimelineView drag-to-retime edit. The realtime model carries
            // startTime/endTime from the DTO (toModel), so gate them on the wire names.
            if !pendingFields.contains("start_time")             { existing.startTime = model.startTime }
            if !pendingFields.contains("end_time")               { existing.endTime = model.endTime }
            if !pendingFields.contains("duration")              { existing.duration = model.duration }
            if !pendingFields.contains("display_order")          { existing.displayOrder = model.displayOrder }
            if !pendingFields.contains("team_member_ids") {
                existing.teamMemberIdsString = model.teamMemberIdsString
                // Rewire `teamMembers: [User]` to match the new id string. See
                // equivalent block in DataActor.mergeTask for rationale — this
                // is what fixes the avatars-flicker-between-openings bug.
                let ids = existing.getTeamMemberIds()
                if ids.isEmpty {
                    if !existing.teamMembers.isEmpty { existing.teamMembers = [] }
                } else {
                    let users = (try? context.fetch(
                        FetchDescriptor<User>(predicate: #Predicate<User> { ids.contains($0.id) })
                    )) ?? []
                    if Set(existing.teamMembers.map(\.id)) != Set(users.map(\.id)) {
                        existing.teamMembers = users
                    }
                }
            }
            if !pendingFields.contains("source_line_item_id")      { existing.sourceLineItemId = model.sourceLineItemId }
            if !pendingFields.contains("source_estimate_id")      { existing.sourceEstimateId = model.sourceEstimateId }
            if !pendingFields.contains("deleted_at")             { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            let pendingFieldsForSync = pendingFieldsForEntity(entityType: .projectTask, entityId: existing.id, context: context)
            if pendingFieldsForSync.isEmpty {
                existing.needsSync = false
            }
        } else {
            // Origin suppression: if we wrote this entityId locally within the
            // last 60s — regardless of SyncOperation status (pending, inProgress,
            // completed) — the realtime payload is our own write echoing back.
            // Inserting here would produce a duplicate because ProjectTask.id
            // lacks @Attribute(.unique).
            //
            // Previous implementation relied on `pendingFields` being non-empty,
            // which is derived from SyncOperations with status == "pending".
            // Under the DataActor path, outbound push had already flipped the
            // op to "completed" before the echo arrived, so `pendingFields` was
            // empty and suppression silently failed. A timestamp window catches
            // the echo regardless of where the op is in its lifecycle.
            if hasRecentLocalWrite(entityType: .projectTask, entityId: id, withinSeconds: 60, context: context) {
                print("[DUPE_TRACE] RT.upsertProjectTask SUPPRESSED id=\(id) — recent local write within 60s")
                try context.save()
                return
            }

            print("[DUPE_TRACE] RT.upsertProjectTask INSERT id=\(id) — no recent local write, treating as remote create")
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)

            // Wire relationships on the fresh row so the UI sees a complete
            // task immediately instead of waiting for the next sync's
            // linkAllRelationships pass.
            let projId = model.projectId
            if let project = try? context.fetch(
                FetchDescriptor<Project>(predicate: #Predicate<Project> { $0.id == projId })
            ).first {
                model.project = project
            }
            if !model.taskTypeId.isEmpty {
                let ttId = model.taskTypeId
                if let taskType = try? context.fetch(
                    FetchDescriptor<TaskType>(predicate: #Predicate<TaskType> { $0.id == ttId })
                ).first {
                    model.taskType = taskType
                }
            }
            let memberIds = model.getTeamMemberIds()
            if !memberIds.isEmpty {
                let users = (try? context.fetch(
                    FetchDescriptor<User>(predicate: #Predicate<User> { memberIds.contains($0.id) })
                )) ?? []
                if !users.isEmpty { model.teamMembers = users }
            }
        }
        try context.save()
    }

    private func upsertUser(context: ModelContext, id: String, model: User, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("firstName")                 { existing.firstName = model.firstName }
            if !pendingFields.contains("lastName")                  { existing.lastName = model.lastName }
            if !pendingFields.contains("email"), let email = model.email { existing.email = email }
            if !pendingFields.contains("phone")                     { existing.phone = model.phone }
            if !pendingFields.contains("homeAddress")               { existing.homeAddress = model.homeAddress }
            if !pendingFields.contains("profileImageURL")           { existing.profileImageURL = model.profileImageURL }
            if !pendingFields.contains("userColor")                 { existing.userColor = model.userColor }
            if !pendingFields.contains("role")                      { existing.role = model.role }
            if !pendingFields.contains("userType")                  { existing.userType = model.userType }
            if !pendingFields.contains("hasCompletedAppOnboarding") { existing.hasCompletedAppOnboarding = model.hasCompletedAppOnboarding }
            if !pendingFields.contains("hasCompletedAppTutorial")   { existing.hasCompletedAppTutorial = model.hasCompletedAppTutorial }
            if !pendingFields.contains("devPermission")             { existing.devPermission = model.devPermission }
            if !pendingFields.contains("latitude")                  { existing.latitude = model.latitude }
            if !pendingFields.contains("longitude")                 { existing.longitude = model.longitude }
            if !pendingFields.contains("locationName")              { existing.locationName = model.locationName }
            if !pendingFields.contains("isActive")                  { existing.isActive = model.isActive }
            if !pendingFields.contains("deletedAt")                 { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertClient(context: ModelContext, id: String, model: Client, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        print("[DUPE_TRACE] RT.upsertClient id=\(id) existing_count=\(existingCount) ctx=\(ObjectIdentifier(context))")

        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("name")              { existing.name = model.name }
            if !pendingFields.contains("email")             { existing.email = model.email }
            if !pendingFields.contains("phoneNumber")       { existing.phoneNumber = model.phoneNumber }
            if !pendingFields.contains("address")           { existing.address = model.address }
            if !pendingFields.contains("latitude")          { existing.latitude = model.latitude }
            if !pendingFields.contains("longitude")         { existing.longitude = model.longitude }
            if !pendingFields.contains("profileImageURL")   { existing.profileImageURL = model.profileImageURL }
            if !pendingFields.contains("notes")             { existing.notes = model.notes }
            if !pendingFields.contains("companyId")         { existing.companyId = model.companyId }
            if !pendingFields.contains("deletedAt")         { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            // Origin suppression: if we wrote this entityId locally within the
            // last 60s — regardless of SyncOperation status (pending, inProgress,
            // completed) — the realtime payload is our own write echoing back.
            // Inserting here would produce a duplicate because Client.id
            // lacks @Attribute(.unique). Mirrors upsertProject suppression
            // (bug f86cf554) and fixes bug b873deb7 (duplicate client created
            // when the form sheet creates the row with an uppercase UUID and
            // the realtime echo arrives with a lowercase id).
            if hasRecentLocalWrite(entityType: .client, entityId: id, withinSeconds: 60, context: context) {
                print("[DUPE_TRACE] RT.upsertClient SUPPRESSED id=\(id) — recent local write within 60s")
                try context.save()
                return
            }

            print("[DUPE_TRACE] RT.upsertClient INSERT id=\(id) — no recent local write, treating as remote create")
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertCompany(context: ModelContext, id: String, model: Company, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<Company>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("name")                  { existing.name = model.name }
            if !pendingFields.contains("logoURL")               { existing.logoURL = model.logoURL }
            if !pendingFields.contains("companyDescription")    { existing.companyDescription = model.companyDescription }
            if !pendingFields.contains("website")               { existing.website = model.website }
            if !pendingFields.contains("phone")                 { existing.phone = model.phone }
            if !pendingFields.contains("email")                 { existing.email = model.email }
            if !pendingFields.contains("address")               { existing.address = model.address }
            if !pendingFields.contains("latitude")              { existing.latitude = model.latitude }
            if !pendingFields.contains("longitude")             { existing.longitude = model.longitude }
            if !pendingFields.contains("defaultProjectColor")   { existing.defaultProjectColor = model.defaultProjectColor }
            if !pendingFields.contains("adminIdsString")        { existing.adminIdsString = model.adminIdsString }
            if !pendingFields.contains("seatedEmployeeIds")     { existing.seatedEmployeeIds = model.seatedEmployeeIds }
            if !pendingFields.contains("maxSeats")              { existing.maxSeats = model.maxSeats }
            if !pendingFields.contains("subscriptionStatus")    { existing.subscriptionStatus = model.subscriptionStatus }
            if !pendingFields.contains("subscriptionPlan")      { existing.subscriptionPlan = model.subscriptionPlan }
            if !pendingFields.contains("subscriptionEnd")       { existing.subscriptionEnd = model.subscriptionEnd }
            if !pendingFields.contains("subscriptionPeriod")    { existing.subscriptionPeriod = model.subscriptionPeriod }
            if !pendingFields.contains("trialStartDate")        { existing.trialStartDate = model.trialStartDate }
            if !pendingFields.contains("trialEndDate")          { existing.trialEndDate = model.trialEndDate }
            if !pendingFields.contains("hasPrioritySupport")    { existing.hasPrioritySupport = model.hasPrioritySupport }
            if !pendingFields.contains("stripeCustomerId")      { existing.stripeCustomerId = model.stripeCustomerId }
            if !pendingFields.contains("externalId")            { existing.externalId = model.externalId }
            if !pendingFields.contains("accountHolderId")       { existing.accountHolderId = model.accountHolderId }
            if !pendingFields.contains("deletedAt")             { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertTaskType(context: ModelContext, id: String, model: TaskType, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<TaskType>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("display")                    { existing.display = model.display }
            if !pendingFields.contains("color")                      { existing.color = model.color }
            if !pendingFields.contains("icon")                       { existing.icon = model.icon }
            if !pendingFields.contains("isDefault")                  { existing.isDefault = model.isDefault }
            if !pendingFields.contains("displayOrder")               { existing.displayOrder = model.displayOrder }
            if !pendingFields.contains("defaultTeamMemberIdsString") { existing.defaultTeamMemberIdsString = model.defaultTeamMemberIdsString }
            if !pendingFields.contains("deletedAt")                  { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            // Origin suppression: pendingFields non-empty means the main context
            // just wrote this row locally. Inserting here would leave two rows
            // with the same id (TaskType.id lacks @Attribute(.unique)), and the
            // UI's relationship resolution can pick the stale duplicate — the
            // "Rail task type crash" repro traces to this path.
            if !pendingFields.isEmpty {
                print("[RealtimeProcessor] Skipping upsert insert for task type \(id) — pending local op exists (origin suppression)")
                try context.save()
                return
            }

            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertSubClient(context: ModelContext, id: String, model: SubClient, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<SubClient>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("name")          { existing.name = model.name }
            if !pendingFields.contains("title")         { existing.title = model.title }
            if !pendingFields.contains("email")         { existing.email = model.email }
            if !pendingFields.contains("phoneNumber")   { existing.phoneNumber = model.phoneNumber }
            if !pendingFields.contains("address")       { existing.address = model.address }
            if !pendingFields.contains("deletedAt")     { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertProjectNote(context: ModelContext, id: String, model: ProjectNote, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("content")                   { existing.content = model.content }
            if !pendingFields.contains("attachmentsJSON")           { existing.attachmentsJSON = model.attachmentsJSON }
            if !pendingFields.contains("mentionedUserIdsString")    { existing.mentionedUserIdsString = model.mentionedUserIdsString }
            if !pendingFields.contains("updatedAt")                 { existing.updatedAt = model.updatedAt }
            if !pendingFields.contains("deletedAt")                 { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertProjectPhoto(context: ModelContext, id: String, model: ProjectPhoto, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<ProjectPhoto>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("url")             { existing.url = model.url }
            if !pendingFields.contains("thumbnailURL")    { existing.thumbnailURL = model.thumbnailURL }
            if !pendingFields.contains("renderedURL")     { existing.renderedURL = model.renderedURL }
            if !pendingFields.contains("source")          { existing.source = model.source }
            if !pendingFields.contains("caption")         { existing.caption = model.caption }
            if !pendingFields.contains("isClientVisible") { existing.isClientVisible = model.isClientVisible }
            if !pendingFields.contains("takenAt")         { existing.takenAt = model.takenAt }
            if !pendingFields.contains("updatedAt")       { existing.updatedAt = model.updatedAt }
            if !pendingFields.contains("deletedAt")       { existing.deletedAt = model.deletedAt }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertPhotoAnnotation(context: ModelContext, id: String, model: PhotoAnnotation, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<PhotoAnnotation>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            if !pendingFields.contains("annotationURL")     { existing.annotationURL = model.annotationURL }
            if !pendingFields.contains("renderedPhotoURL")  { existing.renderedPhotoURL = model.renderedPhotoURL }
            if !pendingFields.contains("note")              { existing.note = model.note }
            if !pendingFields.contains("updatedAt")         { existing.updatedAt = model.updatedAt }
            if !pendingFields.contains("deletedAt")         { existing.deletedAt = model.deletedAt }
            if !pendingFields.contains("dimensions"), let dimensionsData = model.dimensionsData {
                existing.dimensionsData = dimensionsData
            }
            existing.lastSyncedAt = Date()
            existing.needsSync = false
        } else {
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }

    private func upsertDeckDesign(context: ModelContext, id: String, dto: SupabaseDeckDesignDTO, pendingFields: Set<String>) throws {
        let descriptor = FetchDescriptor<DeckDesign>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            let acceptedFields = Set(DeckDesign.serverMergeFields).subtracting(pendingFields)
            existing.applyServerSnapshot(dto, accepting: acceptedFields)
            existing.lastSyncedAt = Date()
            existing.needsSync = !pendingFields.isEmpty
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            context.insert(model)
        }
        try context.save()
    }
}
