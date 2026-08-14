//
//  SiteVisitAuthorHeal.swift
//  OPS
//
//  Author resolution for site-visit rows the V19→V20 lightweight migration left
//  holding a nil `createdBy`. Those rows can never satisfy the wire contract on
//  their own, so the outbound boundary resolves an author before building a
//  payload — otherwise the write fails on device, forever, on every launch.
//

import Foundation
import SwiftData

/// A site-visit row whose Supabase contract requires an author the V19→V20
/// lightweight migration could not supply. Class-bound so the heal writes through
/// to the stored `@Model` row.
protocol SiteVisitAuthoredRow: AnyObject {
    var createdBy: String? { get set }
}

extension SiteVisit: SiteVisitAuthoredRow {}
extension SiteVisitIdentityDraft: SiteVisitAuthoredRow {}
extension SiteVisitCaptureArtifact: SiteVisitAuthoredRow {}
extension SiteVisitChecklistAnswer: SiteVisitAuthoredRow {}

enum SiteVisitAuthorHeal {

    /// True when a row cannot satisfy the wire contract's `created_by` on its own.
    static func needsAuthor(_ value: String?) -> Bool {
        canonical(value) == nil
    }

    /// Returns a canonical (trimmed, lowercased) author id, or nil when nothing
    /// usable exists. Precedence: the row's own value, then the parent visit's
    /// author, then the active session user.
    ///
    /// UUID shape is deliberately NOT validated here — `SiteVisitWire.payloadUUID`
    /// owns that, so a malformed author still surfaces as a payload error instead
    /// of being silently discarded into an unresolvable row.
    static func resolvedAuthor(
        current: String?,
        parentVisitAuthor: String?,
        sessionUserId: String?
    ) -> String? {
        for candidate in [current, parentVisitAuthor, sessionUserId] {
            if let canonical = canonical(candidate) { return canonical }
        }
        return nil
    }

    /// The session user id as persisted by auth (UserDefaults "currentUserId").
    /// Canonicalized the same way; nil when absent/blank.
    static func sessionUserId(defaults: UserDefaults = .standard) -> String? {
        canonical(defaults.string(forKey: "currentUserId"))
    }

    /// A candidate counts only when it survives trimming. Ids elsewhere in the
    /// app are lowercase (model inits lowercase them, Postgres lowercases every
    /// uuid), so canonicalizing keeps a healed row byte-identical to a native one.
    private static func canonical(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }
}

// MARK: - Launch backfill

extension SiteVisitAuthorHeal {

    struct BackfillResult: Equatable {
        /// Rows this pass gave an author, sorted by id.
        let healedIds: [String]
        /// Rows still authorless — nothing resolved, so the caller must run again
        /// rather than retire the sweep.
        let unresolvedIds: [String]

        var isClean: Bool { unresolvedIds.isEmpty }
    }

    /// Clears the whole authorless backlog up front, so a wedged row never gets the
    /// chance to dam its visit's queue. The outbound boundary heals a row when its
    /// turn comes; this makes sure that turn is not spent failing first.
    ///
    /// Fetches are predicate-free and filtered in Swift on purpose: a `#Predicate`
    /// fetch against a table that has never held a row can trap inside SwiftData,
    /// and this runs at launch on every device, including ones with no site visits.
    ///
    /// Soft-deleted rows are skipped — they sync as a delete, which carries no
    /// author, so healing them is busywork and counting them unresolved would pin
    /// the sweep open forever.
    ///
    /// Writes ONLY `createdBy`, for the same reason the outbound heal does:
    /// flipping `needsSync` would enqueue a write for every legacy row at once.
    static func backfillAuthors(
        in context: ModelContext,
        sessionUserId: String?
    ) throws -> BackfillResult {
        let visits = try context.fetch(FetchDescriptor<SiteVisit>())
        let authorByVisitId = Dictionary(
            visits.map { ($0.id.lowercased(), $0.createdBy) },
            uniquingKeysWith: { first, second in first ?? second }
        )

        var candidates: [(row: SiteVisitAuthoredRow, id: String, visitId: String?)] = []
        candidates += try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>())
            .filter { $0.deletedAt == nil }
            .map { ($0, $0.id, $0.siteVisitId) }
        candidates += try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
            .filter { $0.deletedAt == nil }
            .map { ($0, $0.id, $0.siteVisitId) }
        candidates += try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
            .filter { $0.deletedAt == nil }
            .map { ($0, $0.id, $0.siteVisitId) }
        candidates += visits
            .filter { $0.deletedAt == nil }
            .map { ($0, $0.id, nil) }

        var healed: [String] = []
        var unresolved: [String] = []
        var pending: [(row: SiteVisitAuthoredRow, author: String)] = []

        for candidate in candidates where needsAuthor(candidate.row.createdBy) {
            let parentAuthor = candidate.visitId
                .flatMap { authorByVisitId[$0.lowercased()] } ?? nil
            guard let resolved = resolvedAuthor(
                current: candidate.row.createdBy,
                parentVisitAuthor: parentAuthor,
                sessionUserId: sessionUserId
            ) else {
                unresolved.append(candidate.id)
                continue
            }
            pending.append((candidate.row, resolved))
            healed.append(candidate.id)
        }

        if !pending.isEmpty {
            try context.transaction {
                for entry in pending { entry.row.createdBy = entry.author }
            }
        }

        return BackfillResult(
            healedIds: healed.sorted(),
            unresolvedIds: unresolved.sorted()
        )
    }
}
