//
//  CalendarSiteVisitLeadResolver.swift
//  OPS
//
//  Calendar-owned lead metadata for booked site visits. Opportunities are
//  intentionally REST-backed rather than part of the SwiftData sync graph, so
//  Schedule resolves the visible visit ids in one request and keeps the last
//  successful result available when the phone loses signal.
//

import Foundation

struct CalendarSiteVisitLeadDetails: Codable, Equatable, Sendable {
    let opportunityId: String
    let companyId: String
    let contactName: String?
    let title: String?
    let address: String?
    let agentSummary: String?
    let leadDescription: String?

    init(
        opportunityId: String,
        companyId: String,
        contactName: String?,
        title: String?,
        address: String?,
        agentSummary: String?,
        leadDescription: String?
    ) {
        self.opportunityId = CalendarSiteVisitLeadIdentity.canonical(opportunityId)
        self.companyId = CalendarSiteVisitLeadIdentity.canonical(companyId)
        self.contactName = contactName
        self.title = title
        self.address = address
        self.agentSummary = agentSummary
        self.leadDescription = leadDescription
    }

    init(dto: OpportunityDTO) {
        self.init(
            opportunityId: dto.id,
            companyId: dto.companyId,
            contactName: dto.contactName,
            title: dto.title,
            address: dto.address,
            agentSummary: dto.aiSummary,
            leadDescription: dto.description
        )
    }

    /// Matches Opportunity.displayContactName without requiring a SwiftData
    /// Opportunity row to exist on Schedule.
    var displayName: String {
        CalendarSiteVisitLeadIdentity.nonempty(contactName)
            ?? CalendarSiteVisitLeadIdentity.nonempty(title)
            ?? "Site visit"
    }

    /// The primary site-visit form owns this priority rule. Calendar delegates
    /// to it so agent-written context wins, with the lead's inquiry as fallback.
    var primarySummaryPresentation: SiteVisitLeadSummaryPresentation? {
        SiteVisitPrimaryFormSemantics.leadSummary(
            boundLeadSummary: agentSummary,
            leadDescription: leadDescription
        )
    }

    var primarySummary: String? {
        primarySummaryPresentation?.text
    }

    fileprivate func canonicalized() -> CalendarSiteVisitLeadDetails {
        CalendarSiteVisitLeadDetails(
            opportunityId: opportunityId,
            companyId: companyId,
            contactName: contactName,
            title: title,
            address: address,
            agentSummary: agentSummary,
            leadDescription: leadDescription
        )
    }
}

/// One presentation contract shared by OPS Schedule and personal-calendar
/// mirroring. Phase-C appointment metadata is authoritative when present;
/// ordinary booked visits fall back to their resolved pipeline lead.
struct CalendarSiteVisitPresentation: Equatable, Sendable {
    let title: String
    let address: String?
    let detail: String?

    init(visit: SiteVisit, leadDetails: CalendarSiteVisitLeadDetails?) {
        title = CalendarSiteVisitLeadIdentity.nonempty(visit.appointmentTitle)
            ?? leadDetails?.displayName
            ?? "Site visit"
        address = CalendarSiteVisitLeadIdentity.nonempty(visit.appointmentLocation)
            ?? CalendarSiteVisitLeadIdentity.nonempty(leadDetails?.address)
            ?? CalendarSiteVisitLeadIdentity.nonempty(visit.address)
        detail = leadDetails?.primarySummary
    }
}

/// The day header and empty-state gate must count booked appointments as a
/// first-class calendar source beside tasks and operator events.
enum CalendarDayContent {
    static func eventCount(
        taskCount: Int,
        userEventCount: Int,
        bookedVisitCount: Int
    ) -> Int {
        taskCount + userEventCount + bookedVisitCount
    }

    static func hasEvents(
        taskCount: Int,
        userEventCount: Int,
        bookedVisitCount: Int
    ) -> Bool {
        eventCount(
            taskCount: taskCount,
            userEventCount: userEventCount,
            bookedVisitCount: bookedVisitCount
        ) > 0
    }
}

/// App-private, operator-and-company-scoped last-good lead metadata.
///
/// Each scope owns one whole JSON snapshot under Application Support. Writes
/// use Foundation's atomic replacement so interruption cannot leave a partial
/// file, while the in-process lock keeps refreshes from interleaving a
/// read/merge/write cycle.
final class CalendarSiteVisitLeadCache: @unchecked Sendable {
    static let shared = CalendarSiteVisitLeadCache()

    private static let fileNameCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "-_")
    )

    private struct Snapshot: Codable {
        let schemaVersion: Int
        let userId: String
        let companyId: String
        let details: [CalendarSiteVisitLeadDetails]
    }

    static var defaultDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CalendarSiteVisitLeads", isDirectory: true)
    }

    private let directory: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(
        directory: URL = CalendarSiteVisitLeadCache.defaultDirectory,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Replaces the complete snapshot for one operator at one company.
    @discardableResult
    func save(
        _ details: [CalendarSiteVisitLeadDetails],
        userId: String,
        companyId: String
    ) -> Bool {
        guard let scope = scope(userId: userId, companyId: companyId),
              let normalized = normalized(details, companyId: scope.companyId) else {
            return false
        }

        lock.lock()
        defer { lock.unlock() }
        return writeUnlocked(normalized, scope: scope)
    }

    func load(userId: String, companyId: String) -> [CalendarSiteVisitLeadDetails] {
        guard let scope = scope(userId: userId, companyId: companyId) else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked(scope: scope)
    }

    /// Replaces only the ids covered by a successful authoritative request,
    /// preserving cached details for visits outside the current calendar
    /// window. A successful response that omits an id removes that stale row;
    /// only a failed request is allowed to fall back to it.
    fileprivate func mergeAuthoritative(
        _ remoteDetails: [CalendarSiteVisitLeadDetails],
        replacing opportunityIds: [String],
        userId: String,
        companyId: String
    ) -> [CalendarSiteVisitLeadDetails] {
        guard let scope = scope(userId: userId, companyId: companyId),
              let normalizedRemote = normalized(remoteDetails, companyId: scope.companyId) else {
            return []
        }
        let replacedIds = Set(opportunityIds.map(CalendarSiteVisitLeadIdentity.canonical))

        lock.lock()
        defer { lock.unlock() }

        var byId = Dictionary(
            uniqueKeysWithValues: loadUnlocked(scope: scope).map { ($0.opportunityId, $0) }
        )
        for id in replacedIds where !id.isEmpty {
            byId.removeValue(forKey: id)
        }
        for detail in normalizedRemote {
            byId[detail.opportunityId] = detail
        }

        let merged = byId.values.sorted { $0.opportunityId < $1.opportunityId }
        _ = writeUnlocked(merged, scope: scope)
        return merged
    }

    private typealias Scope = (userId: String, companyId: String)

    private func scope(userId: String, companyId: String) -> Scope? {
        let userId = CalendarSiteVisitLeadIdentity.canonical(userId)
        let companyId = CalendarSiteVisitLeadIdentity.canonical(companyId)
        guard !userId.isEmpty, !companyId.isEmpty else { return nil }
        return (userId, companyId)
    }

    private func normalized(
        _ details: [CalendarSiteVisitLeadDetails],
        companyId: String
    ) -> [CalendarSiteVisitLeadDetails]? {
        var byId: [String: CalendarSiteVisitLeadDetails] = [:]
        for raw in details {
            let detail = raw.canonicalized()
            guard detail.companyId == companyId else { return nil }
            guard !detail.opportunityId.isEmpty else { continue }
            byId[detail.opportunityId] = detail
        }
        return byId.values.sorted { $0.opportunityId < $1.opportunityId }
    }

    private func loadUnlocked(scope: Scope) -> [CalendarSiteVisitLeadDetails] {
        let fileURL = url(scope: scope)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard snapshot.schemaVersion == 1,
                  CalendarSiteVisitLeadIdentity.canonical(snapshot.userId) == scope.userId,
                  CalendarSiteVisitLeadIdentity.canonical(snapshot.companyId) == scope.companyId,
                  let normalized = normalized(snapshot.details, companyId: scope.companyId) else {
                return []
            }
            return normalized
        } catch {
            print("[CALENDAR_SITE_VISIT_LEADS] cache read failed: \(error)")
            return []
        }
    }

    private func writeUnlocked(
        _ details: [CalendarSiteVisitLeadDetails],
        scope: Scope
    ) -> Bool {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let snapshot = Snapshot(
                schemaVersion: 1,
                userId: scope.userId,
                companyId: scope.companyId,
                details: details
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url(scope: scope), options: .atomic)
            return true
        } catch {
            print("[CALENDAR_SITE_VISIT_LEADS] cache write failed: \(error)")
            return false
        }
    }

    private func url(scope: Scope) -> URL {
        directory.appendingPathComponent(
            "site-visits-\(sanitized(scope.companyId))-\(sanitized(scope.userId)).json",
            isDirectory: false
        )
    }

    private func sanitized(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: Self.fileNameCharacters)
            ?? "invalid-scope"
    }
}

/// One booked visit Calendar wants a brief for, with the lead it is linked to
/// on this phone (the id the authoritative merge replaces).
struct CalendarSiteVisitBriefRequest: Equatable, Sendable {
    let siteVisitId: String
    let opportunityId: String?
}

/// The outcome of one `read_site_visit_briefs` refresh.
struct CalendarSiteVisitBriefResolution: Equatable {
    /// Lead details keyed by canonical opportunity id — same shape and cache
    /// semantics as `refreshDetails`.
    let detailsByOpportunityId: [String: CalendarSiteVisitLeadDetails]
    /// The requested visit ids the server says this user can still read.
    /// Nil when the answer was not authoritative (offline, error) — the caller
    /// keeps whatever it last knew.
    let readableSiteVisitIds: Set<String>?
}

/// Which booked visits Schedule may show, from the server's readable-set
/// answers (CREW SITE VISITS P1). The phone never prunes rows it can no longer
/// read, so a visit reassigned away (or whose lead moved out of reach) would
/// otherwise stay on Schedule forever.
///
/// Per-id verdicts from the last SUCCESSFUL answer that covered the id: a
/// requested id absent from that answer is hidden; an id never asked about
/// shows (before any successful answer, everything shows); a failed refresh
/// changes nothing.
struct CalendarSiteVisitReadability: Equatable {
    private(set) var verdicts: [String: Bool] = [:]

    mutating func record(
        readableSiteVisitIds: Set<String>?,
        requestedSiteVisitIds: [String]
    ) {
        guard let readableSiteVisitIds else { return }
        let readable = Set(readableSiteVisitIds.map(CalendarSiteVisitLeadIdentity.canonical))
        for id in requestedSiteVisitIds.map(CalendarSiteVisitLeadIdentity.canonical) where !id.isEmpty {
            verdicts[id] = readable.contains(id)
        }
    }

    func isVisible(siteVisitId: String) -> Bool {
        verdicts[CalendarSiteVisitLeadIdentity.canonical(siteVisitId)] ?? true
    }

    func visible<Item>(_ items: [Item], siteVisitId: (Item) -> String) -> [Item] {
        items.filter { isVisible(siteVisitId: siteVisitId($0)) }
    }

    mutating func reset() {
        verdicts = [:]
    }
}

final class CalendarSiteVisitLeadResolver {
    typealias RemoteLoader = (
        _ companyId: String,
        _ opportunityIds: [String]
    ) async throws -> [CalendarSiteVisitLeadDetails]

    /// Reads `read_site_visit_briefs` for at most
    /// `SiteVisitBriefRepository.maxIdsPerRequest` visit ids.
    typealias BriefLoader = (
        _ siteVisitIds: [String]
    ) async throws -> [SiteVisitBriefDTO]

    private let cache: CalendarSiteVisitLeadCache
    private let remoteLoader: RemoteLoader
    private let briefLoader: BriefLoader

    private static let liveRemoteLoader: RemoteLoader = { companyId, opportunityIds in
        try await OpportunityRepository(companyId: companyId)
            .fetchByIds(opportunityIds)
            .map { CalendarSiteVisitLeadDetails(dto: $0) }
    }

    private static let liveBriefLoader: BriefLoader = { siteVisitIds in
        try await SiteVisitBriefRepository.fetchBriefs(siteVisitIds: siteVisitIds)
    }

    /// Production initializer. `refreshDetails` performs one authoritative
    /// company-scoped opportunities fetch; `refreshBriefs` reads the narrow
    /// visit-keyed projection an assignee may see.
    init(cache: CalendarSiteVisitLeadCache = .shared) {
        self.cache = cache
        self.remoteLoader = Self.liveRemoteLoader
        self.briefLoader = Self.liveBriefLoader
    }

    /// Test seam and alternate transport seam. The cache behavior remains real.
    init(
        cache: CalendarSiteVisitLeadCache,
        remoteLoader: @escaping RemoteLoader
    ) {
        self.cache = cache
        self.remoteLoader = remoteLoader
        self.briefLoader = Self.liveBriefLoader
    }

    /// Brief transport seam. The cache behavior remains real.
    init(
        cache: CalendarSiteVisitLeadCache,
        briefLoader: @escaping BriefLoader
    ) {
        self.cache = cache
        self.remoteLoader = Self.liveRemoteLoader
        self.briefLoader = briefLoader
    }

    /// Resolves lead details through `read_site_visit_briefs`, keyed by the
    /// booked visits Calendar is showing.
    ///
    /// Lead details keep `refreshDetails`' contract: one successful response
    /// is authoritative for every lead id involved (the visits' local links
    /// plus any the server returned) — an omitted lead drops its cached row —
    /// and a transport failure returns the last successful scoped snapshot.
    /// A successful response also yields the set of still-readable visit ids.
    func refreshBriefs(
        visits: [CalendarSiteVisitBriefRequest],
        userId: String,
        companyId: String
    ) async -> CalendarSiteVisitBriefResolution {
        let userId = CalendarSiteVisitLeadIdentity.canonical(userId)
        let companyId = CalendarSiteVisitLeadIdentity.canonical(companyId)
        let requestedVisitIds = SiteVisitBriefRepository.canonicalIds(visits.map(\.siteVisitId))
        let localOpportunityIds = Set(
            visits
                .compactMap { $0.opportunityId.map(CalendarSiteVisitLeadIdentity.canonical) }
                .filter { !$0.isEmpty }
        )

        guard !userId.isEmpty, !companyId.isEmpty, !requestedVisitIds.isEmpty else {
            return CalendarSiteVisitBriefResolution(
                detailsByOpportunityId: [:],
                readableSiteVisitIds: nil
            )
        }

        let cached = cache.load(userId: userId, companyId: companyId)
        do {
            var rows: [SiteVisitBriefDTO] = []
            var start = 0
            while start < requestedVisitIds.count {
                let end = min(start + SiteVisitBriefRepository.maxIdsPerRequest, requestedVisitIds.count)
                rows.append(contentsOf: try await briefLoader(Array(requestedVisitIds[start..<end])))
                start = end
            }

            let requested = Set(requestedVisitIds)
            let authoritativeRows = rows.filter {
                requested.contains(CalendarSiteVisitLeadIdentity.canonical($0.siteVisitId))
            }
            let readable = Set(authoritativeRows.map {
                CalendarSiteVisitLeadIdentity.canonical($0.siteVisitId)
            })
            let details = authoritativeRows.compactMap { row -> CalendarSiteVisitLeadDetails? in
                guard let opportunityId = row.opportunityId.map(CalendarSiteVisitLeadIdentity.canonical),
                      !opportunityId.isEmpty else { return nil }
                return CalendarSiteVisitLeadDetails(
                    opportunityId: opportunityId,
                    companyId: companyId,
                    contactName: row.contactName,
                    title: row.title,
                    address: row.address,
                    agentSummary: row.aiSummary,
                    leadDescription: row.description
                )
            }
            let involvedOpportunityIds = localOpportunityIds.union(details.map(\.opportunityId))
            let merged = cache.mergeAuthoritative(
                details,
                replacing: Array(involvedOpportunityIds),
                userId: userId,
                companyId: companyId
            )
            return CalendarSiteVisitBriefResolution(
                detailsByOpportunityId: Self.index(merged, requestedIds: involvedOpportunityIds),
                readableSiteVisitIds: readable
            )
        } catch {
            return CalendarSiteVisitBriefResolution(
                detailsByOpportunityId: Self.index(cached, requestedIds: localOpportunityIds),
                readableSiteVisitIds: nil
            )
        }
    }

    /// Returns details keyed by canonical opportunity id. One successful
    /// response is authoritative for every requested id; a transport failure
    /// returns the last successful scoped snapshot instead.
    func refreshDetails(
        opportunityIds: [String],
        userId: String,
        companyId: String
    ) async -> [String: CalendarSiteVisitLeadDetails] {
        let userId = CalendarSiteVisitLeadIdentity.canonical(userId)
        let companyId = CalendarSiteVisitLeadIdentity.canonical(companyId)
        let requestedIds = Array(Set(
            opportunityIds
                .map(CalendarSiteVisitLeadIdentity.canonical)
                .filter { !$0.isEmpty }
        )).sorted()

        guard !userId.isEmpty, !companyId.isEmpty, !requestedIds.isEmpty else {
            return [:]
        }

        let cached = cache.load(userId: userId, companyId: companyId)
        do {
            let fetched = try await remoteLoader(companyId, requestedIds)
            let requested = Set(requestedIds)
            let authoritative = fetched
                .map { $0.canonicalized() }
                .filter {
                    $0.companyId == companyId && requested.contains($0.opportunityId)
                }
            let merged = cache.mergeAuthoritative(
                authoritative,
                replacing: requestedIds,
                userId: userId,
                companyId: companyId
            )
            return Self.index(merged, requestedIds: requested)
        } catch {
            return Self.index(cached, requestedIds: Set(requestedIds))
        }
    }

    private static func index(
        _ details: [CalendarSiteVisitLeadDetails],
        requestedIds: Set<String>
    ) -> [String: CalendarSiteVisitLeadDetails] {
        Dictionary(
            uniqueKeysWithValues: details
                .filter { requestedIds.contains($0.opportunityId) }
                .map { ($0.opportunityId, $0) }
        )
    }
}

private enum CalendarSiteVisitLeadIdentity {
    static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
