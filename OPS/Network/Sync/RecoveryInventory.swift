//
//  RecoveryInventory.swift
//  OPS
//
//  SYNC RECOVERY · T5 — the pure, synchronous model behind the PENDING WORK
//  recovery screen (spec §4).
//
//  This file answers one question with value types: "what locally-created work
//  is not yet safely on the server, and how worried should the operator be about
//  each piece?" It never touches the wall clock on its own (callers pass `now`),
//  never imports the outbound engine, and — crucially — takes plain snapshot
//  arrays so the whole join can be unit-tested without a SwiftData container. The
//  live `load(from:queue:now:)` convenience maps the real models into snapshots
//  and calls the same pure `build(...)`.
//
//  The unit of thought is the piece of WORK ("Charles — site visit"), not a raw
//  sync op. A site-visit identity draft is the spine of a bundle: it gathers its
//  client-create op, its durable lead-autocreate request, the deck ops for the
//  designs captured on that visit, and (see the photo-linkage note below) its
//  photos. Everything that doesn't join a bundle renders as a loose row; chronic
//  server-orphaned deck designs get their own section.
//
//  PHOTO LINKAGE — verified finding (do not "fix" without re-checking):
//  Site-visit photos are NOT `LocalPhoto` rows. Capture stores them as
//  `SiteVisitCaptureArtifact` (kind == .photo) with an on-disk `localAssetURL`
//  via `ImageFileManager` (see SiteVisitCaptureViewModel.addPhotos). `LocalPhoto`
//  is a separate, polymorphic upload record keyed by (`entityType`, `entityId`) —
//  and in the current tree its only construction site, `PhotoProcessor.savePhoto`,
//  has no live callers, so no `LocalPhoto` links to a site visit at all. There is
//  therefore no honest `LocalPhoto → siteVisit` join key. A `LocalPhoto` only ever
//  points at whatever entity it is attached to (its `entityId`). So a bundle
//  absorbs photos ONLY when its draft is already bound to an opportunity and a
//  `LocalPhoto.entityId` matches that opportunity id — i.e. we join on
//  `draft.opportunityId` when present, never on an invented site-visit key. Every
//  other `LocalPhoto` renders as a loose `.photos` row grouped by `entityId`.
//

import Foundation
import SwiftData

// MARK: - Snapshot inputs
//
// Small value types the builder consumes. Each carries a mapping init from its
// live model so `load(...)` can bridge SwiftData → pure builder, while tests
// construct the snapshots directly.

/// A queued outbound sync operation, flattened to the fields the recovery screen
/// reasons about.
struct SyncOpSnapshot: Identifiable, Equatable {
    let id: UUID
    let entityType: String
    let entityId: String
    let operationType: String
    let status: String
    let retryCount: Int
    let lastAttemptedAt: Date?
    let lastError: String?
    let createdAt: Date
    /// Durable packet routing decoded from the operation envelope. Nil for all
    /// legacy/non-site-visit work.
    let siteVisitId: String?

    init(
        id: UUID,
        entityType: String,
        entityId: String,
        operationType: String,
        status: String,
        retryCount: Int,
        lastAttemptedAt: Date?,
        lastError: String?,
        createdAt: Date,
        siteVisitId: String? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.operationType = operationType
        self.status = status
        self.retryCount = retryCount
        self.lastAttemptedAt = lastAttemptedAt
        self.lastError = lastError
        self.createdAt = createdAt
        self.siteVisitId = siteVisitId?.lowercased()
    }

    init(from operation: SyncOperation) {
        self.init(
            id: operation.id,
            entityType: operation.entityType,
            entityId: operation.entityId,
            operationType: operation.operationType,
            status: operation.status,
            retryCount: operation.retryCount,
            lastAttemptedAt: operation.lastAttemptedAt,
            lastError: operation.lastError,
            createdAt: operation.createdAt,
            siteVisitId: Self.siteVisitId(from: operation)
        )
    }

    private static func siteVisitId(from operation: SyncOperation) -> String? {
        let siteVisitEntityTypes = Set([
            SyncEntityType.siteVisit.rawValue,
            SyncEntityType.siteVisitArtifact.rawValue,
            SyncEntityType.siteVisitChecklistAnswer.rawValue,
            SyncEntityType.siteVisitIdentityDraft.rawValue,
        ])
        guard siteVisitEntityTypes.contains(operation.entityType),
              let payload = try? JSONDecoder().decode(
                SiteVisitSyncOperation.Payload.self,
                from: operation.payload
              ) else { return nil }
        return payload.siteVisitId.lowercased()
    }
}

/// A durable client→lead autocreate request awaiting delivery. `attempts` is the
/// request's effective attempt count; `isParked` marks a permanent rejection.
struct AutocreateSnapshot: Identifiable, Equatable {
    let clientId: String
    let name: String
    let createdAt: Date
    let attempts: Int
    let lastAttemptAt: Date?
    let lastError: String?
    let isParked: Bool

    var id: String { clientId.lowercased() }

    init(
        clientId: String,
        name: String,
        createdAt: Date,
        attempts: Int,
        lastAttemptAt: Date?,
        lastError: String?,
        isParked: Bool
    ) {
        self.clientId = clientId
        self.name = name
        self.createdAt = createdAt
        self.attempts = attempts
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
        self.isParked = isParked
    }

    init(from request: PendingClientLeadAutocreate) {
        self.init(
            clientId: request.clientId,
            name: request.name,
            createdAt: request.createdAt,
            attempts: request.effectiveAttempts,
            lastAttemptAt: request.lastAttemptAt,
            lastError: request.lastError,
            isParked: request.isParked
        )
    }
}

/// A locally-stored photo awaiting upload. `entityType`/`entityId` are the
/// polymorphic link back to whatever the photo is attached to. `status` follows
/// PhotoProcessor's vocabulary — "local" (queued) and "failed" are the two the
/// recovery screen surfaces; "failed" is the only one that reads as attention.
struct PhotoSnapshot: Identifiable, Equatable {
    let id: String
    let entityType: String
    let entityId: String
    let status: String
    let createdAt: Date

    init(id: String, entityType: String, entityId: String, status: String, createdAt: Date) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.status = status
        self.createdAt = createdAt
    }

    init(from photo: LocalPhoto) {
        self.init(
            id: photo.id,
            entityType: photo.entityType,
            entityId: photo.entityId,
            status: photo.status,
            createdAt: photo.createdAt
        )
    }
}

/// A site-visit identity draft — the spine of a recovery bundle.
struct DraftSnapshot: Identifiable, Equatable {
    let id: String
    let siteVisitId: String
    let clientId: String?
    let opportunityId: String?
    let displayName: String
    let createdAt: Date
    let lastCommittedAt: Date?

    init(
        id: String,
        siteVisitId: String,
        clientId: String?,
        opportunityId: String?,
        displayName: String,
        createdAt: Date,
        lastCommittedAt: Date?
    ) {
        self.id = id
        self.siteVisitId = siteVisitId
        self.clientId = clientId
        self.opportunityId = opportunityId
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastCommittedAt = lastCommittedAt
    }

    init(from draft: SiteVisitIdentityDraft) {
        self.init(
            id: draft.id,
            siteVisitId: draft.siteVisitId,
            clientId: draft.clientId,
            opportunityId: draft.opportunityId,
            displayName: draft.displayName,
            createdAt: draft.createdAt,
            lastCommittedAt: draft.lastCommittedAt
        )
    }
}

/// A site-visit capture artifact — used only to resolve which deck designs were
/// drawn on a visit, so a draft's deck ops can join its bundle.
struct ArtifactSnapshot: Identifiable, Equatable {
    let id: String
    let siteVisitId: String
    let deckDesignId: String?
    let kind: String

    init(id: String, siteVisitId: String, deckDesignId: String?, kind: String) {
        self.id = id
        self.siteVisitId = siteVisitId
        self.deckDesignId = deckDesignId
        self.kind = kind
    }

    init(from artifact: SiteVisitCaptureArtifact) {
        self.init(
            id: artifact.id,
            siteVisitId: artifact.siteVisitId,
            deckDesignId: artifact.deckDesignId,
            kind: artifact.kind.rawValue
        )
    }
}

/// A locally captured checklist answer. Recovery only needs its packet key and
/// identity so the row can report an honest captured-item count.
struct ChecklistAnswerSnapshot: Identifiable, Equatable {
    let id: String
    let siteVisitId: String

    init(id: String, siteVisitId: String) {
        self.id = id
        self.siteVisitId = siteVisitId
    }

    init(from answer: SiteVisitChecklistAnswer) {
        self.init(id: answer.id, siteVisitId: answer.siteVisitId)
    }
}

/// A deck design that is orphaned locally — attached to neither a project nor a
/// lead, and not deleted. These are the chronic server-side orphans the screen's
/// NOT LINKED section lets the operator re-home.
struct OrphanDesignSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let createdAt: Date
    let hasThumbnail: Bool

    init(id: String, title: String, createdAt: Date, hasThumbnail: Bool) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.hasThumbnail = hasThumbnail
    }

    init(from design: DeckDesign) {
        self.init(
            id: design.id,
            title: design.title,
            createdAt: design.createdAt,
            hasThumbnail: design.thumbnailURL != nil || design.localThumbnailPath != nil
        )
    }
}

// MARK: - Output model

/// How worried the operator should be about a piece of work. Ordered so the
/// worst state sorts highest: a bundle inherits its worst member's tone via
/// `max()`, and a section places an item by whether its tone reaches `.attention`.
enum RecoveryTone: Int, Comparable {
    case waiting = 0     // queued / in flight / backing off — informational
    case attention = 1   // failed transiently (recoverable) — needs a look
    case parked = 2      // permanently rejected — out of auto-retries, worst

    static func < (lhs: RecoveryTone, rhs: RecoveryTone) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The role a member plays inside a site-visit bundle — drives the member strip
/// glyph label (CLIENT / LEAD / DECK / PHOTOS).
enum RecoveryMemberRole: Equatable {
    case client
    case lead
    case deck
    case photos
    case other(String)
}

/// Everything the status line needs, resolved once here so the view is a dumb
/// renderer. `statusRaw` is the op's own status vocabulary (or a synthesized
/// equivalent for autocreates/photos); `nextEligibleAt` is the future instant the
/// item next becomes eligible to send — nil when it is due now or never
/// auto-retries.
struct RecoveryStatusPayload: Equatable {
    let statusRaw: String
    let retryCount: Int
    let lastError: String?
    let nextEligibleAt: Date?
}

/// One row in a bundle's member strip. Exactly one underlying reference is
/// populated: a sync op (`syncOpId`), an autocreate request (`autocreateClientId`),
/// or a group of photos (`photoIds`).
struct RecoveryMember: Identifiable, Equatable {
    let id: String
    let role: RecoveryMemberRole
    let syncOpId: UUID?
    let autocreateClientId: String?
    let photoIds: [String]
    let tone: RecoveryTone
    let status: RecoveryStatusPayload
}

/// The dependency stage currently governing a site-visit packet. Ordered by
/// the actual outbound chain so ties resolve to the first stage that must clear.
enum SiteVisitBlockedStage: Int, Comparable, Equatable {
    case visit = 0
    case media = 1
    case completion = 2

    static func < (lhs: SiteVisitBlockedStage, rhs: SiteVisitBlockedStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A work-unit bundle: a site-visit draft plus every unsynced item that belongs
/// to it. `tone` is the worst member's tone.
struct SiteVisitBundle: Identifiable, Equatable {
    let id: String            // "bundle:<draftId>"
    let title: String         // draft.displayName
    let createdAt: Date       // draft.createdAt
    let members: [RecoveryMember]
    let tone: RecoveryTone
    let draft: DraftSnapshot
    let siteVisitId: String
    let capturedItemCount: Int
    let blockedStage: SiteVisitBlockedStage
    /// Every queue record in the work unit. Retry and discard operate on this
    /// complete set so grouped packet stages never strand hidden siblings.
    let syncOperationIds: [UUID]
    /// Distinguishes the durable cloud packet from older draft-only bundles.
    let siteVisitOperationIds: [UUID]
}

/// A single renderable entry in a section. Stable `id`s let SwiftUI diff rows
/// across rebuilds without reordering flicker.
enum RecoveryItem: Identifiable, Equatable {
    case bundle(SiteVisitBundle)
    case op(SyncOpSnapshot, tone: RecoveryTone, nextEligibleAt: Date?)
    case autocreate(AutocreateSnapshot, tone: RecoveryTone, nextEligibleAt: Date?)
    case photos(grouped: [PhotoSnapshot], tone: RecoveryTone)
    case draft(DraftSnapshot)
    case orphanDesign(OrphanDesignSnapshot)

    var id: String {
        switch self {
        case .bundle(let bundle):
            return bundle.id
        case .op(let snapshot, _, _):
            return snapshot.id.uuidString
        case .autocreate(let snapshot, _, _):
            return "autocreate:\(snapshot.clientId)"
        case .photos(let grouped, _):
            return "photos:\(grouped.first?.entityId ?? "none")"
        case .draft(let draft):
            return draft.id
        case .orphanDesign(let design):
            return design.id
        }
    }

    /// The tone that governs which section this item lands in.
    var tone: RecoveryTone {
        switch self {
        case .bundle(let bundle):            return bundle.tone
        case .op(_, let tone, _):            return tone
        case .autocreate(_, let tone, _):    return tone
        case .photos(_, let tone):           return tone
        case .draft:                         return .waiting
        case .orphanDesign:                  return .waiting
        }
    }

    /// The instant used to order a section — oldest-waiting first (photos use the
    /// earliest capture in their group).
    var sortDate: Date {
        switch self {
        case .bundle(let bundle):            return bundle.createdAt
        case .op(let snapshot, _, _):        return snapshot.createdAt
        case .autocreate(let snapshot, _, _): return snapshot.createdAt
        case .photos(let grouped, _):        return grouped.first?.createdAt ?? .distantPast
        case .draft(let draft):              return draft.createdAt
        case .orphanDesign(let design):      return design.createdAt
        }
    }
}

/// The four sections the PENDING WORK screen renders, plus the counts the pill
/// badge and empty-state read. Sections render only when non-empty; order is
/// fixed by the caller (attention → sending → drafts → unlinked).
struct RecoveryInventory: Equatable {
    let attention: [RecoveryItem]
    let sending: [RecoveryItem]
    let drafts: [RecoveryItem]
    let unlinked: [RecoveryItem]

    /// Rows demanding a look — drives the "N NEED A LOOK" pill badge.
    var attentionCount: Int { attention.count }

    /// Every live sync item (attention + sending). Drafts and chronic orphans are
    /// excluded — they are not work in flight.
    var totalActive: Int { attention.count + sending.count }

    /// True when there is nothing to recover, draft, or re-home — the zero-state.
    var isEmpty: Bool {
        attention.isEmpty && sending.isEmpty && drafts.isEmpty && unlinked.isEmpty
    }
}

// MARK: - Builder

extension RecoveryInventory {

    /// Pure, deterministic assembly of the recovery inventory from plain
    /// snapshots. `now` is the only clock input; the function makes no `Date()`
    /// call of its own so a fixed `now` yields a byte-stable result.
    static func build(
        ops: [SyncOpSnapshot],
        autocreates: [AutocreateSnapshot],
        photos: [PhotoSnapshot],
        drafts: [DraftSnapshot],
        artifacts: [ArtifactSnapshot],
        answers: [ChecklistAnswerSnapshot] = [],
        orphans: [OrphanDesignSnapshot],
        now: Date
    ) -> RecoveryInventory {
        // 1 · Only these statuses are live work. `completed` (and anything else) is
        //     ignored entirely.
        let consideredOps = ops.filter { isConsidered(status: $0.status) }

        // Consumption ledgers: a bundle absorbs its members so they never also
        // appear as loose rows.
        var consumedOpIds = Set<UUID>()
        var consumedAutocreateIds = Set<String>()   // lowercased clientId
        var consumedPhotoIds = Set<String>()

        var attention: [RecoveryItem] = []
        var sending: [RecoveryItem] = []
        var draftItems: [RecoveryItem] = []

        let siteVisitOpsById = Dictionary(grouping: consideredOps.compactMap { op in
            op.siteVisitId.map { ($0, op) }
        }, by: { $0.0 }).mapValues { $0.map(\.1) }

        // 2–4 · Bundle join, one draft at a time.
        for draft in drafts {
            var members: [RecoveryMember] = []
            let normalizedSiteVisitId = draft.siteVisitId.lowercased()
            let packetOps = (siteVisitOpsById[normalizedSiteVisitId] ?? [])
                .filter { !consumedOpIds.contains($0.id) }

            let normalizedClientId = draft.clientId?.lowercased()

            // Client-create/update ops for this draft's client (role .client).
            if let clientId = normalizedClientId, !clientId.isEmpty {
                for op in consideredOps where op.entityType == "client"
                    && op.entityId.lowercased() == clientId
                    && !consumedOpIds.contains(op.id) {
                    members.append(makeOpMember(op, role: .client, now: now))
                    consumedOpIds.insert(op.id)
                }
            }

            // Durable lead-autocreate request for this client (role .lead).
            if let clientId = normalizedClientId, !clientId.isEmpty {
                if let request = autocreates.first(where: {
                    $0.clientId.lowercased() == clientId
                        && !consumedAutocreateIds.contains($0.clientId.lowercased())
                }) {
                    members.append(makeAutocreateMember(request, now: now))
                    consumedAutocreateIds.insert(request.clientId.lowercased())
                }
            }

            // Deck ops for every design captured on this visit — create, update,
            // AND linkOpportunity all count (role .deck).
            let deckDesignIds = Set(
                artifacts
                    .filter { $0.siteVisitId == draft.siteVisitId }
                    .compactMap { $0.deckDesignId?.lowercased() }
            )
            if !deckDesignIds.isEmpty {
                for op in consideredOps where op.entityType == "deckDesign"
                    && deckDesignIds.contains(op.entityId.lowercased())
                    && !consumedOpIds.contains(op.id) {
                    members.append(makeOpMember(op, role: .deck, now: now))
                    consumedOpIds.insert(op.id)
                }
            }

            // Photos join a bundle only through the opportunity link (see the
            // PHOTO LINKAGE note at the top of the file). One grouped .photos
            // member per bundle.
            if let opportunityId = draft.opportunityId?.lowercased(), !opportunityId.isEmpty {
                let bundlePhotos = photos.filter {
                    $0.entityId.lowercased() == opportunityId && !consumedPhotoIds.contains($0.id)
                }
                if !bundlePhotos.isEmpty {
                    members.append(makePhotosMember(bundlePhotos))
                    for photo in bundlePhotos { consumedPhotoIds.insert(photo.id) }
                }
            }

            members.append(contentsOf: makeSiteVisitMembers(
                packetOps,
                siteVisitId: normalizedSiteVisitId,
                now: now
            ))
            for op in packetOps { consumedOpIds.insert(op.id) }

            if !members.isEmpty {
                // 3 · At least one live member → a bundle. Tone is the worst member.
                let tone = members.map(\.tone).max() ?? .waiting
                let bundle = SiteVisitBundle(
                    id: "bundle:\(draft.id)",
                    title: draft.displayName,
                    createdAt: draft.createdAt,
                    members: members,
                    tone: tone,
                    draft: draft,
                    siteVisitId: normalizedSiteVisitId,
                    capturedItemCount: capturedItemCount(
                        siteVisitId: normalizedSiteVisitId,
                        packetOps: packetOps,
                        artifacts: artifacts,
                        answers: answers
                    ),
                    blockedStage: blockedStage(for: packetOps),
                    syncOperationIds: sortedUniqueOperationIds(
                        members.compactMap(\.syncOpId) + packetOps.map(\.id)
                    ),
                    siteVisitOperationIds: sortedUniqueOperationIds(packetOps.map(\.id))
                )
                let item = RecoveryItem.bundle(bundle)
                if tone >= .attention { attention.append(item) } else { sending.append(item) }
            } else if draft.opportunityId == nil && draft.lastCommittedAt == nil {
                // 4 · No live members, never bound, never committed → an abandoned
                //     capture the operator can resume.
                draftItems.append(.draft(draft))
            }
            // else: a bound / committed draft with nothing outstanding is healthy —
            // omit it entirely.
        }

        // A committed packet can outlive its identity draft while media or the
        // completion receipt is still queued. Those operations still render as
        // one visit row, backed by a synthetic display-only draft so existing
        // export/recovery surfaces retain a stable contract.
        for siteVisitId in siteVisitOpsById.keys.sorted() {
            let packetOps = (siteVisitOpsById[siteVisitId] ?? [])
                .filter { !consumedOpIds.contains($0.id) }
            guard !packetOps.isEmpty else { continue }

            let createdAt = packetOps.map(\.createdAt).min() ?? now
            let syntheticDraft = DraftSnapshot(
                id: "visit:\(siteVisitId)",
                siteVisitId: siteVisitId,
                clientId: nil,
                opportunityId: nil,
                displayName: "",
                createdAt: createdAt,
                lastCommittedAt: createdAt
            )
            let members = makeSiteVisitMembers(packetOps, siteVisitId: siteVisitId, now: now)
            let tone = members.map(\.tone).max() ?? .waiting
            let bundle = SiteVisitBundle(
                id: "visit:\(siteVisitId)",
                title: "",
                createdAt: createdAt,
                members: members,
                tone: tone,
                draft: syntheticDraft,
                siteVisitId: siteVisitId,
                capturedItemCount: capturedItemCount(
                    siteVisitId: siteVisitId,
                    packetOps: packetOps,
                    artifacts: artifacts,
                    answers: answers
                ),
                blockedStage: blockedStage(for: packetOps),
                syncOperationIds: sortedUniqueOperationIds(packetOps.map(\.id)),
                siteVisitOperationIds: sortedUniqueOperationIds(packetOps.map(\.id))
            )
            packetOps.forEach { consumedOpIds.insert($0.id) }
            let item = RecoveryItem.bundle(bundle)
            if tone >= .attention { attention.append(item) } else { sending.append(item) }
        }

        // 5 · Loose items — everything a bundle did not consume.

        // Loose ops.
        for op in consideredOps where !consumedOpIds.contains(op.id) {
            let tone = opTone(op.status)
            let item = RecoveryItem.op(op, tone: tone, nextEligibleAt: opNextEligibleAt(op, now: now))
            if tone >= .attention { attention.append(item) } else { sending.append(item) }
        }

        // Loose autocreates.
        for request in autocreates where !consumedAutocreateIds.contains(request.clientId.lowercased()) {
            let tone = autocreateTone(request)
            let item = RecoveryItem.autocreate(
                request,
                tone: tone,
                nextEligibleAt: autocreateNextEligibleAt(request, now: now)
            )
            if tone >= .attention { attention.append(item) } else { sending.append(item) }
        }

        // Loose photos, grouped by entityId into one row per entity.
        let loosePhotos = photos.filter { !consumedPhotoIds.contains($0.id) }
        let photoGroups = Dictionary(grouping: loosePhotos, by: { $0.entityId })
        for (_, group) in photoGroups {
            let sortedGroup = group.sorted { $0.createdAt < $1.createdAt }
            let tone: RecoveryTone = sortedGroup.contains { $0.status == "failed" } ? .attention : .waiting
            let item = RecoveryItem.photos(grouped: sortedGroup, tone: tone)
            if tone >= .attention { attention.append(item) } else { sending.append(item) }
        }

        // 6 · Sort. Attention / sending / drafts are oldest-first (longest-waiting
        //     on top); orphans are newest-first. A stable id tiebreaker guarantees
        //     a deterministic order regardless of the (unordered) grouping above.
        attention.sort(by: Self.oldestFirst)
        sending.sort(by: Self.oldestFirst)
        draftItems.sort(by: Self.oldestFirst)

        let unlinked = orphans
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id > rhs.id
            }
            .map { RecoveryItem.orphanDesign($0) }

        return RecoveryInventory(
            attention: attention,
            sending: sending,
            drafts: draftItems,
            unlinked: unlinked
        )
    }

    // MARK: - Ordering

    private static func oldestFirst(_ lhs: RecoveryItem, _ rhs: RecoveryItem) -> Bool {
        if lhs.sortDate != rhs.sortDate { return lhs.sortDate < rhs.sortDate }
        return lhs.id < rhs.id
    }

    // MARK: - Status → tone

    private static func isConsidered(status: String) -> Bool {
        status == "pending" || status == "inProgress" || status == "failed" || status == "parked"
    }

    private static func opTone(_ status: String) -> RecoveryTone {
        switch status {
        case "parked": return .parked
        case "failed": return .attention
        default:       return .waiting   // pending / inProgress
        }
    }

    private static func autocreateTone(_ request: AutocreateSnapshot) -> RecoveryTone {
        if request.isParked { return .parked }
        if request.attempts > 0 { return .attention }
        return .waiting
    }

    // MARK: - Backoff → next-eligible instant
    //
    // Both formulas mirror their live source of truth exactly:
    //   * sync ops   — `SyncOperation.backoffDelay` = min(2^retryCount, 60)s
    //   * autocreate — `ClientLeadAutocreateQueue.backoffInterval(attempts:)`
    // The result is surfaced only when it is still in the FUTURE relative to
    // `now` (an elapsed window means "due now", so there is no countdown to show),
    // and only for states that actually auto-retry on a timer (pending/inProgress
    // ops, non-parked autocreates). A `failed` op revives on the next launch /
    // reconnect sweep, not on a timer, and a `parked` item never retries — both
    // report nil.

    private static func opNextEligibleAt(_ op: SyncOpSnapshot, now: Date) -> Date? {
        guard op.status == "pending" || op.status == "inProgress",
              let lastAttemptedAt = op.lastAttemptedAt else { return nil }
        let window = min(pow(2.0, Double(op.retryCount)), 60.0)
        let eligible = lastAttemptedAt.addingTimeInterval(window)
        return eligible > now ? eligible : nil
    }

    private static func autocreateNextEligibleAt(_ request: AutocreateSnapshot, now: Date) -> Date? {
        guard !request.isParked, let lastAttemptAt = request.lastAttemptAt else { return nil }
        let window = ClientLeadAutocreateQueue.backoffInterval(attempts: request.attempts)
        let eligible = lastAttemptAt.addingTimeInterval(window)
        return eligible > now ? eligible : nil
    }

    // MARK: - Member factories

    private static func makeOpMember(
        _ op: SyncOpSnapshot,
        role: RecoveryMemberRole,
        now: Date
    ) -> RecoveryMember {
        RecoveryMember(
            id: op.id.uuidString,
            role: role,
            syncOpId: op.id,
            autocreateClientId: nil,
            photoIds: [],
            tone: opTone(op.status),
            status: RecoveryStatusPayload(
                statusRaw: op.status,
                retryCount: op.retryCount,
                lastError: op.lastError,
                nextEligibleAt: opNextEligibleAt(op, now: now)
            )
        )
    }

    private static func makeAutocreateMember(
        _ request: AutocreateSnapshot,
        now: Date
    ) -> RecoveryMember {
        let tone = autocreateTone(request)
        // Synthesize a status token from the tone so the copy layer speaks one
        // vocabulary across ops and autocreates.
        let statusRaw: String
        switch tone {
        case .parked:    statusRaw = "parked"
        case .attention: statusRaw = "failed"
        case .waiting:   statusRaw = "pending"
        }
        return RecoveryMember(
            id: "lead:\(request.clientId)",
            role: .lead,
            syncOpId: nil,
            autocreateClientId: request.clientId,
            photoIds: [],
            tone: tone,
            status: RecoveryStatusPayload(
                statusRaw: statusRaw,
                retryCount: request.attempts,
                lastError: request.lastError,
                nextEligibleAt: autocreateNextEligibleAt(request, now: now)
            )
        )
    }

    private static func makePhotosMember(_ group: [PhotoSnapshot]) -> RecoveryMember {
        let sortedGroup = group.sorted { $0.createdAt < $1.createdAt }
        let tone: RecoveryTone = sortedGroup.contains { $0.status == "failed" } ? .attention : .waiting
        let entityId = sortedGroup.first?.entityId ?? ""
        return RecoveryMember(
            id: "photos:\(entityId)",
            role: .photos,
            syncOpId: nil,
            autocreateClientId: nil,
            photoIds: sortedGroup.map(\.id),
            tone: tone,
            status: RecoveryStatusPayload(
                statusRaw: tone == .attention ? "failed" : "local",
                retryCount: 0,
                lastError: nil,
                nextEligibleAt: nil
            )
        )
    }

    private static func makeSiteVisitMembers(
        _ operations: [SyncOpSnapshot],
        siteVisitId: String,
        now: Date
    ) -> [RecoveryMember] {
        let grouped = Dictionary(grouping: operations, by: operationStage)
        return [SiteVisitBlockedStage.visit, .media, .completion].compactMap { stage in
            guard let stageOps = grouped[stage], !stageOps.isEmpty else { return nil }
            let representative = stageOps.sorted(by: preferredRepresentative).first!
            return RecoveryMember(
                id: "site-visit:\(siteVisitId):\(stage.rawValue)",
                role: .other(stageLabel(stage)),
                syncOpId: representative.id,
                autocreateClientId: nil,
                photoIds: [],
                tone: stageOps.map { opTone($0.status) }.max() ?? .waiting,
                status: RecoveryStatusPayload(
                    statusRaw: representative.status,
                    retryCount: representative.retryCount,
                    lastError: representative.lastError,
                    nextEligibleAt: opNextEligibleAt(representative, now: now)
                )
            )
        }
    }

    private static func blockedStage(for operations: [SyncOpSnapshot]) -> SiteVisitBlockedStage {
        guard let worstTone = operations.map({ opTone($0.status) }).max() else { return .visit }
        return operations
            .filter { opTone($0.status) == worstTone }
            .map(operationStage)
            .min() ?? .visit
    }

    private static func operationStage(_ operation: SyncOpSnapshot) -> SiteVisitBlockedStage {
        if operation.operationType == SiteVisitSyncOperation.completionOperationType { return .completion }
        if operation.operationType == SiteVisitSyncOperation.mediaOperationType { return .media }
        return .visit
    }

    private static func stageLabel(_ stage: SiteVisitBlockedStage) -> String {
        switch stage {
        case .visit: return "visit"
        case .media: return "media"
        case .completion: return "completion"
        }
    }

    private static func preferredRepresentative(_ lhs: SyncOpSnapshot, _ rhs: SyncOpSnapshot) -> Bool {
        let lhsTone = opTone(lhs.status)
        let rhsTone = opTone(rhs.status)
        if lhsTone != rhsTone { return lhsTone > rhsTone }
        let statusRank = ["pending": 0, "inProgress": 1, "failed": 2, "parked": 3]
        let lhsRank = statusRank[lhs.status, default: 0]
        let rhsRank = statusRank[rhs.status, default: 0]
        if lhsRank != rhsRank { return lhsRank > rhsRank }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func sortedUniqueOperationIds(_ ids: [UUID]) -> [UUID] {
        Array(Set(ids)).sorted { $0.uuidString < $1.uuidString }
    }

    private static func capturedItemCount(
        siteVisitId: String,
        packetOps: [SyncOpSnapshot],
        artifacts: [ArtifactSnapshot],
        answers: [ChecklistAnswerSnapshot]
    ) -> Int {
        var ids = Set<String>()
        for artifact in artifacts where artifact.siteVisitId.lowercased() == siteVisitId {
            ids.insert("artifact:\(artifact.id.lowercased())")
        }
        for answer in answers where answer.siteVisitId.lowercased() == siteVisitId {
            ids.insert("answer:\(answer.id.lowercased())")
        }
        // Queue-derived fallback keeps the count useful if a local child was
        // removed after a tombstone was queued or an older store cannot load it.
        for op in packetOps {
            switch op.entityType {
            case SyncEntityType.siteVisitArtifact.rawValue:
                ids.insert("artifact:\(op.entityId.lowercased())")
            case SyncEntityType.siteVisitChecklistAnswer.rawValue:
                ids.insert("answer:\(op.entityId.lowercased())")
            default:
                break
            }
        }
        return ids.count
    }
}

// MARK: - Live load

extension RecoveryInventory {

    /// Fetches the live models the recovery screen cares about and maps them into
    /// the pure builder. Fetches are kept narrow via predicates; the one in-memory
    /// filter (deck artifacts → the drafts' visit ids) is documented inline.
    @MainActor
    static func load(
        from modelContext: ModelContext,
        queue: ClientLeadAutocreateQueue,
        now: Date = Date()
    ) -> RecoveryInventory {
        // Ops: the four live statuses (completed excluded).
        let opDescriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.status == "pending"
                    || $0.status == "inProgress"
                    || $0.status == "failed"
                    || $0.status == "parked"
            }
        )
        let ops = ((try? modelContext.fetch(opDescriptor)) ?? []).map(SyncOpSnapshot.init(from:))

        // Autocreates: both parked and still-draining requests.
        let autocreates = (queue.parkedRequests + queue.activeRequests).map(AutocreateSnapshot.init(from:))

        // Drafts: unbound (no opportunity) OR uncommitted (never delivered a lead).
        // A fully bound + committed draft is healthy and never surfaces.
        let draftDescriptor = FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate<SiteVisitIdentityDraft> {
                $0.opportunityId == nil || $0.lastCommittedAt == nil
            }
        )
        let draftModels = (try? modelContext.fetch(draftDescriptor)) ?? []
        let drafts = draftModels.map(DraftSnapshot.init(from:))

        // Captures: load every active artifact/answer for the visit ids represented
        // by a draft or durable packet operation. They drive the row's captured
        // count; deck artifacts additionally resolve legacy deck-operation joins.
        let visitIds = Set(draftModels.map { $0.siteVisitId.lowercased() })
            .union(ops.compactMap(\.siteVisitId))
        let artifactDescriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate<SiteVisitCaptureArtifact> {
                $0.deletedAt == nil
            }
        )
        let artifacts = ((try? modelContext.fetch(artifactDescriptor)) ?? [])
            .filter { visitIds.contains($0.siteVisitId.lowercased()) }
            .map(ArtifactSnapshot.init(from:))

        let answerDescriptor = FetchDescriptor<SiteVisitChecklistAnswer>(
            predicate: #Predicate<SiteVisitChecklistAnswer> { $0.deletedAt == nil }
        )
        let answers = ((try? modelContext.fetch(answerDescriptor)) ?? [])
            .filter { visitIds.contains($0.siteVisitId.lowercased()) }
            .map(ChecklistAnswerSnapshot.init(from:))

        // Photos: queued ("local") or failed uploads.
        let photoDescriptor = FetchDescriptor<LocalPhoto>(
            predicate: #Predicate<LocalPhoto> {
                $0.status == "failed" || $0.status == "local"
            }
        )
        let photos = ((try? modelContext.fetch(photoDescriptor)) ?? []).map(PhotoSnapshot.init(from:))

        // Orphan deck designs: linked to neither a project nor a lead, not deleted.
        // The predicate carries the two defining nullity checks (unlinked); the
        // `deletedAt == nil` guard is applied in memory. Three `== nil` conjuncts in
        // one #Predicate blow the type-checker's budget ("unable to type-check in
        // reasonable time"), and the unlinked set is already tiny — so the third
        // check rides as a cheap in-memory filter.
        let orphanDescriptor = FetchDescriptor<DeckDesign>(
            predicate: #Predicate<DeckDesign> {
                $0.projectId == nil && $0.opportunityId == nil
            }
        )
        let orphans = ((try? modelContext.fetch(orphanDescriptor)) ?? [])
            .filter { $0.deletedAt == nil }
            .map(OrphanDesignSnapshot.init(from:))

        return build(
            ops: ops,
            autocreates: autocreates,
            photos: photos,
            drafts: drafts,
            artifacts: artifacts,
            answers: answers,
            orphans: orphans,
            now: now
        )
    }
}
