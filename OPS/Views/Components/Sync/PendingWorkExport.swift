//
//  PendingWorkExport.swift
//  OPS
//
//  SYNC RECOVERY · T6 — the export escape hatch (spec §4). Turns a piece of
//  pending work into a share-sheet payload so nothing is ever unrecoverable: a
//  plain-text summary ALWAYS, plus a rendered deck PNG for any exportable design
//  and any failed photo files that still live on disk. Render uses the deck
//  builder's own `DeckRenderer` (pure Core Graphics with explicit colours — the
//  spec's "never bare ImageRenderer" rule; ImageRenderer mis-resolves asset
//  colours), not a hosted view.
//

import UIKit
import SwiftData

/// A ready-to-share payload. `Identifiable` so the wrapper can drive a
/// `.sheet(item:)` share presentation.
struct PendingWorkExportPayload: Identifiable {
    let id = UUID()
    let title: String
    let activityItems: [Any]
}

enum PendingWorkExport {

    /// Assemble the share payload for a piece of work. Summary text is always
    /// present; images/files are added when they can be produced/resolved.
    @MainActor
    static func build(
        item: RecoveryItem,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> PendingWorkExportPayload {
        let name = PendingWorkVisuals.title(for: item)
        let summary = summaryText(item: item, name: name, modelContext: modelContext, now: now)

        var activityItems: [Any] = [summary]

        for image in deckImages(item: item, modelContext: modelContext) {
            activityItems.append(image)
        }
        for url in photoFileURLs(item: item, modelContext: modelContext) {
            activityItems.append(url)
        }
        for url in siteVisitMediaFileURLs(item: item, modelContext: modelContext) {
            activityItems.append(url)
        }

        return PendingWorkExportPayload(
            title: SyncStatusCopy.PendingWork.exportTitle(name: name),
            activityItems: activityItems
        )
    }

    // MARK: - Summary

    private static func summaryText(
        item: RecoveryItem,
        name: String,
        modelContext: ModelContext,
        now: Date
    ) -> String {
        var lines: [String] = [SyncStatusCopy.PendingWork.exportTitle(name: name), ""]

        // Client contact block — recovered from the Client model when the work
        // has a client id (bundle or loose autocreate).
        if let clientId = clientId(for: item),
           let client = fetchClient(clientId: clientId, modelContext: modelContext) {
            lines.append("CLIENT")
            lines.append("  Name: \(client.name)")
            if let email = client.email, !email.isEmpty { lines.append("  Email: \(email)") }
            if let phone = client.phoneNumber, !phone.isEmpty { lines.append("  Phone: \(phone)") }
            if let address = client.address, !address.isEmpty { lines.append("  Address: \(address)") }
            if let notes = client.notes, !notes.isEmpty { lines.append("  Notes: \(notes)") }
            lines.append("")
        }

        // Visit notes — for a quarantined packet the server may never accept
        // this work again (deleted-parent custody), so the words the operator
        // wrote on site travel with the export instead of dying on the phone.
        if let notes = visitNotes(for: item, modelContext: modelContext) {
            lines.append("VISIT NOTES")
            lines.append("  \(notes)")
            lines.append("")
        }

        // Per-item / per-member status.
        lines.append("STATUS")
        for status in statusEntries(for: item, now: now) {
            lines.append("  · \(status.label): \(status.text)")
        }
        lines.append("")

        // Raw server errors — the honest text, preserved for support.
        let errors = rawErrors(for: item)
        if !errors.isEmpty {
            lines.append("SERVER RESPONSE")
            for error in errors { lines.append("  \(error)") }
            lines.append("")
        }

        lines.append("Captured \(Self.timestampFormatter.string(from: sortDate(for: item)))")
        return lines.joined(separator: "\n")
    }

    // MARK: - Deck images

    private static func deckImages(item: RecoveryItem, modelContext: ModelContext) -> [UIImage] {
        deckDesignIds(for: item, modelContext: modelContext).compactMap { designId in
            guard let design = fetchDesign(designId: designId, modelContext: modelContext) else { return nil }
            // Full vector render first (the builder's own path); fall back to the
            // persisted local thumbnail image if the drawing renders empty.
            if let rendered = DeckRenderer.renderToPNG(drawingData: design.drawingData) {
                return rendered
            }
            if let path = design.localThumbnailPath,
               FileManager.default.fileExists(atPath: path),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
            return nil
        }
    }

    // MARK: - Photo files

    private static func photoFileURLs(item: RecoveryItem, modelContext: ModelContext) -> [URL] {
        photoIds(for: item).compactMap { photoId in
            guard let photo = fetchPhoto(photoId: photoId, modelContext: modelContext),
                  FileManager.default.fileExists(atPath: photo.localPath) else { return nil }
            return URL(fileURLWithPath: photo.localPath)
        }
    }

    // MARK: - Site-visit media (quarantined packets)

    /// Local, still-on-disk capture media for a quarantined site-visit packet.
    /// The vault holds encrypted copies for custody; EXPORT hands the operator
    /// the actual files — for a deleted-parent packet these bytes may exist
    /// nowhere else (e.g. a rendered markup whose upload never landed). Remote
    /// URLs are skipped (already durable in OPS), as are pointers whose file is
    /// gone (a dead share item helps no one).
    private static func siteVisitMediaFileURLs(
        item: RecoveryItem,
        modelContext: ModelContext
    ) -> [URL] {
        guard case .quarantinedVisit(let visit) = item else { return [] }
        let visitId = visit.siteVisitId.lowercased()
        let companyId = visit.companyId.lowercased()
        // Whole-table fetch + in-memory match: stored id casing varies (see the
        // capture-scan note in RecoveryInventory), and this runs once per
        // explicit operator tap, never in a drain loop.
        let artifacts = (
            try? modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>())
        ) ?? []
        var urls: [URL] = []
        var seen = Set<String>()
        for artifact in artifacts where
            artifact.deletedAt == nil
                && artifact.siteVisitId.lowercased() == visitId
                && artifact.companyId.lowercased() == companyId
        {
            let sources = [
                artifact.localAssetURL,
                artifact.renderedAssetURL,
                artifact.thumbnailURL,
            ]
            for source in sources {
                guard let source,
                      !SiteVisitMediaSyncManager.isRemoteURL(source),
                      seen.insert(source).inserted,
                      let url = localMediaURL(source),
                      FileManager.default.fileExists(atPath: url.path) else {
                    continue
                }
                urls.append(url)
            }
        }
        return urls
    }

    /// Same phone-local id resolution the recovery vault uses.
    private static func localMediaURL(_ source: String) -> URL? {
        if source.hasPrefix("local://project_images/") {
            return ImageFileManager.shared.getFileURL(for: source)
        }
        if source.hasPrefix("file://") { return URL(string: source) }
        if source.hasPrefix("/") { return URL(fileURLWithPath: source) }
        return nil
    }

    /// The visit's own notes for a quarantined packet's summary block.
    private static func visitNotes(
        for item: RecoveryItem,
        modelContext: ModelContext
    ) -> String? {
        guard case .quarantinedVisit(let visit) = item else { return nil }
        let visitId = visit.siteVisitId.lowercased()
        let companyId = visit.companyId.lowercased()
        let visits = (try? modelContext.fetch(FetchDescriptor<SiteVisit>())) ?? []
        guard let match = visits.first(where: {
            $0.id.lowercased() == visitId && $0.companyId.lowercased() == companyId
        }) else { return nil }
        let notes = [match.notes, match.internalNotes]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return notes.isEmpty ? nil : notes.joined(separator: "\n  ")
    }

    // MARK: - Item introspection

    private struct StatusEntry { let label: String; let text: String }

    private static func statusEntries(for item: RecoveryItem, now: Date) -> [StatusEntry] {
        switch item {
        case .bundle(let bundle):
            return bundle.members.map { member in
                let status = SyncStatusCopy.PendingWork.statusLine(
                    statusRaw: member.status.statusRaw,
                    lastError: member.status.lastError,
                    secondsUntilRetry: PendingWorkVisuals.secondsUntilRetry(member.status.nextEligibleAt, now: now)
                )
                return StatusEntry(label: SyncStatusCopy.PendingWork.memberLabel(member.role), text: status.text)
            }
        default:
            let status = PendingWorkVisuals.statusLine(for: item, now: now)
            return [StatusEntry(label: PendingWorkVisuals.title(for: item), text: status.text)]
        }
    }

    private static func rawErrors(for item: RecoveryItem) -> [String] {
        let collected: [String?]
        switch item {
        case .bundle(let bundle):
            collected = bundle.members.map { $0.status.lastError }
        default:
            collected = [PendingWorkVisuals.displayStatus(for: item).lastError]
        }
        var seen = Set<String>()
        return collected.compactMap { raw in
            guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !seen.contains(raw) else { return nil }
            seen.insert(raw)
            return raw
        }
    }

    private static func clientId(for item: RecoveryItem) -> String? {
        switch item {
        case .bundle(let bundle):    return bundle.draft.clientId
        case .autocreate(let s, _, _): return s.clientId
        default:                     return nil
        }
    }

    private static func deckDesignIds(for item: RecoveryItem, modelContext: ModelContext) -> [String] {
        switch item {
        case .op(let snapshot, _, _) where snapshot.entityType == "deckDesign":
            return [snapshot.entityId]
        case .bundle(let bundle):
            // A deck member carries its sync-op id; the op's `entityId` is the
            // deck design id. Resolve each so a bundle export renders its decks.
            return bundle.members.compactMap { member in
                guard case .deck = member.role, let opId = member.syncOpId,
                      let op = fetchOperation(id: opId, modelContext: modelContext) else { return nil }
                return op.entityId
            }
        default:
            return []
        }
    }

    private static func fetchOperation(id: UUID, modelContext: ModelContext) -> SyncOperation? {
        let target = id
        let descriptor = FetchDescriptor<SyncOperation>(predicate: #Predicate<SyncOperation> { $0.id == target })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private static func photoIds(for item: RecoveryItem) -> [String] {
        switch item {
        case .photos(let grouped, _):
            return grouped.map(\.id)
        case .bundle(let bundle):
            return bundle.members.first { !$0.photoIds.isEmpty }?.photoIds ?? []
        default:
            return []
        }
    }

    private static func sortDate(for item: RecoveryItem) -> Date { item.sortDate }

    // MARK: - Fetches

    private static func fetchClient(clientId: String, modelContext: ModelContext) -> Client? {
        let target = clientId
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate<Client> { $0.id == target })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private static func fetchDesign(designId: String, modelContext: ModelContext) -> DeckDesign? {
        let target = designId
        let descriptor = FetchDescriptor<DeckDesign>(predicate: #Predicate<DeckDesign> { $0.id == target })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private static func fetchPhoto(photoId: String, modelContext: ModelContext) -> LocalPhoto? {
        let target = photoId
        let descriptor = FetchDescriptor<LocalPhoto>(predicate: #Predicate<LocalPhoto> { $0.id == target })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
