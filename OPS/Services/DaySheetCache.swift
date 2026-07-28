//
//  DaySheetCache.swift
//  OPS
//
//  Offline for the delegate day sheet (spec §6). Leads are repo-fetched, not
//  SwiftData-synced, so there is no local row to fall back on when the truck
//  drops signal — this file is the entire offline read path, plus the write
//  path back out.
//
//  Two halves, one storage directory (Application Support/DaySheet):
//
//   1. `DaySheetCache` — the last good fetch, verbatim. DTOs are persisted as
//      they came off the wire (every timestamp is already a Postgres string on
//      `OpportunityDTO`), so a cached sheet renders identically to a live one.
//      Keyed by company AND operator: one device can be handed to a different
//      runner, and nobody may read someone else's sheet.
//
//   2. `MilestoneWriteQueue` — milestone presses made with no signal. Follows
//      the LeadImageService doctrine in miniature: the record survives
//      relaunch, the queue drains on connectivity change, on a retry timer,
//      and the moment a committer is installed, and every retry is idempotent
//      because the row carries its own request id.
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §6
//

import Foundation

// MARK: - Storage

/// One directory and one date contract shared by both halves, so the snapshot
/// and the queue can never drift into different on-disk formats.
enum DaySheetStorage {

    /// Application Support/DaySheet — app-private, survives relaunch, and is
    /// not user-visible the way Documents is.
    static var defaultDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("DaySheet", isDirectory: true)
    }

    static func snapshotFileName(userId: String, companyId: String) -> String {
        "daysheet-\(sanitized(companyId))-\(sanitized(userId)).json"
    }

    static let queueFileName = "milestone-queue.json"

    /// Ids are uuids in practice; sanitizing keeps a malformed one from
    /// walking out of the directory through a path separator.
    static func sanitized(_ id: String) -> String {
        String(id.map { character in
            character.isASCII && (character.isLetter || character.isNumber)
                || character == "-" || character == "_"
                ? character
                : "_"
        })
    }

    @discardableResult
    static func ensureDirectory(_ url: URL, fileManager: FileManager = .default) -> Bool {
        if fileManager.fileExists(atPath: url.path) { return true }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            print("[DAY_SHEET_CACHE] could not create \(url.path): \(error)")
            return false
        }
    }

    /// `OpportunityDTO` keeps every server timestamp as the raw string, so the
    /// only Dates written here are ours (`savedAt`, `stampedAt`). They ride the
    /// same ISO-8601 fractional-second format the rest of the app speaks, which
    /// keeps the files readable and the round-trip exact to the millisecond —
    /// the resolution of a sync stamp, not of a measurement.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SupabaseDate.format(date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        SupabaseDate.makeISODecoder()
    }
}

// MARK: - Snapshot cache

/// Last-good-fetch snapshot so the day sheet renders offline.
final class DaySheetCache {

    static let shared = DaySheetCache()

    struct Snapshot: Codable {
        let dtos: [OpportunityDTO]
        let savedAt: Date
    }

    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL = DaySheetStorage.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Overwrite this operator's sheet with the fetch that just succeeded.
    /// Atomic: a crash mid-write leaves the previous sheet intact rather than
    /// half a file, and two writers of the same key produce one whole sheet.
    @discardableResult
    func save(
        _ dtos: [OpportunityDTO],
        userId: String,
        companyId: String,
        savedAt: Date = Date()
    ) -> Bool {
        guard DaySheetStorage.ensureDirectory(directory, fileManager: fileManager) else { return false }
        do {
            let data = try DaySheetStorage.makeEncoder()
                .encode(Snapshot(dtos: dtos, savedAt: savedAt))
            try data.write(to: url(userId: userId, companyId: companyId), options: .atomic)
            return true
        } catch {
            print("[DAY_SHEET_CACHE] save failed: \(error)")
            return false
        }
    }

    /// The cached sheet for this operator at this company, or nil when there
    /// has never been a successful fetch (first launch, or a fresh operator on
    /// a shared device) — the caller shows the error state, never a stale one.
    func load(userId: String, companyId: String) -> Snapshot? {
        guard let data = try? Data(contentsOf: url(userId: userId, companyId: companyId)) else {
            return nil
        }
        do {
            return try DaySheetStorage.makeDecoder().decode(Snapshot.self, from: data)
        } catch {
            print("[DAY_SHEET_CACHE] unreadable snapshot: \(error)")
            return nil
        }
    }

    /// `SYS :: OFFLINE — LAST SYNC 07:12` (spec §8). Local 24-hour clock,
    /// zero-padded, POSIX-locked so a device set to 12-hour time still reads
    /// the operator's own wall clock in the app's number style.
    static func lastSyncLabel(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func url(userId: String, companyId: String) -> URL {
        directory.appendingPathComponent(
            DaySheetStorage.snapshotFileName(userId: userId, companyId: companyId)
        )
    }
}

// MARK: - Milestone write queue

/// One milestone press, durable. `id` is the request id the committer replays
/// on retry, so a press that landed server-side but lost its answer commits
/// once, not twice.
struct QueuedMilestoneCommit: Codable, Equatable, Identifiable {
    let id: String                 // requestId, uuid lowercased
    let leadId: String
    let companyId: String
    let userId: String
    let milestoneVerb: String      // LeadMilestone.label verbatim (activity subject)
    let priorStageRaw: String      // PipelineStage.rawValue at press time
    let targetStageRaw: String     // stage the press wrote
    let stampedAt: Date
}

/// Milestone presses waiting on signal.
///
/// The network lives entirely behind `executor`: this type never calls
/// Supabase, which keeps it testable with fakes and keeps the retry policy in
/// one place. The day sheet's committer installs the real executor at first
/// use — installing it is itself a drain trigger, so nothing here needs a
/// launch-time bootstrap in `OPSApp`.
@MainActor
final class MilestoneWriteQueue: ObservableObject {

    static let shared = MilestoneWriteQueue()

    /// What the committer did with one queued press.
    /// - `committed`: the stamp landed (or was already there under this
    ///   request id). Row is done.
    /// - `conflictSkipped`: the lead's CURRENT stage is no longer
    ///   `priorStageRaw` — somebody moved it while we were dark. Honest
    ///   last-writer behaviour is to drop our stale press, not to drag the
    ///   lead backwards. Row is done, and the skip is logged.
    /// - `retryLater`: still no signal, or a transient server failure. Row
    ///   survives for the next drain.
    enum DrainOutcome {
        case committed
        case conflictSkipped
        case retryLater
    }

    /// Presses not yet committed. Published so a row can show its pending
    /// affordance while the queue is still holding the stamp.
    @Published private(set) var pending: [QueuedMilestoneCommit] = []

    /// Installed by the day sheet's milestone committer. Nil until then, and a
    /// drain with no executor is a no-op that keeps every row — an uninstalled
    /// committer must never look like a successful commit.
    var executor: ((QueuedMilestoneCommit) async -> DrainOutcome)? {
        didSet {
            guard backgroundWorkEnabled, executor != nil, !pending.isEmpty else { return }
            Task { await drain() }
        }
    }

    private let directory: URL
    private let fileManager: FileManager
    private let backgroundWorkEnabled: Bool
    private var isDraining = false
    private var drainRequested = false
    private var retryTimer: Timer?

    init(
        directory: URL = DaySheetStorage.defaultDirectory,
        fileManager: FileManager = .default,
        backgroundWorkEnabled: Bool = true
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.backgroundWorkEnabled = backgroundWorkEnabled
        loadPending()
        if backgroundWorkEnabled {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(connectivityChanged),
                name: ConnectivityManager.connectivityChangedNotification,
                object: nil
            )
            startRetryTimerIfNeeded()
        }
    }

    // MARK: Queue

    /// Idempotent by request id: the same press enqueued twice (a retry of the
    /// local write, a double-tap the UI already coalesced) stays one row.
    func enqueue(_ commit: QueuedMilestoneCommit) {
        if let index = pending.firstIndex(where: { $0.id == commit.id }) {
            pending[index] = commit
        } else {
            pending.append(commit)
        }
        savePending()
        guard backgroundWorkEnabled else { return }
        startRetryTimerIfNeeded()
        if executor != nil {
            Task { await drain() }
        }
    }

    func remove(id: String) {
        guard pending.contains(where: { $0.id == id }) else { return }
        pending.removeAll { $0.id == id }
        savePending()
        if pending.isEmpty { stopRetryTimer() }
    }

    func pending(forLead leadId: String) -> [QueuedMilestoneCommit] {
        pending.filter { $0.leadId == leadId }
    }

    // MARK: Drain

    /// Hand every queued press to the committer, oldest first. Runs on
    /// connectivity restore, on the retry timer, on enqueue, and when the
    /// executor is installed. Serialized: a second call while one is in flight
    /// requests a follow-up pass instead of double-committing.
    func drain() async {
        guard !pending.isEmpty else { return }
        guard let executor else { return }
        guard !isDraining else {
            drainRequested = true
            return
        }
        isDraining = true
        let snapshot = pending
        var stillPending: [QueuedMilestoneCommit] = []

        for commit in snapshot {
            switch await executor(commit) {
            case .committed:
                break
            case .conflictSkipped:
                print("[MILESTONE_QUEUE] skipped \(commit.milestoneVerb) on lead \(commit.leadId): "
                      + "stage left \(commit.priorStageRaw) before the stamp landed")
            case .retryLater:
                stillPending.append(commit)
            }
        }

        // Presses made while the drain was out on the network keep their place
        // at the back of the queue.
        let drainedIDs = Set(snapshot.map(\.id))
        pending = stillPending + pending.filter { !drainedIDs.contains($0.id) }
        savePending()

        isDraining = false
        let shouldDrainAgain = drainRequested
        drainRequested = false
        if pending.isEmpty {
            stopRetryTimer()
        } else if shouldDrainAgain, backgroundWorkEnabled {
            Task { await drain() }
        }
    }

    // MARK: Triggers

    @objc private func connectivityChanged() {
        Task { await drain() }
    }

    private func startRetryTimerIfNeeded() {
        guard backgroundWorkEnabled, retryTimer == nil, !pending.isEmpty else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.drain()
            }
        }
    }

    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    // MARK: Persistence

    private var storeURL: URL {
        directory.appendingPathComponent(DaySheetStorage.queueFileName)
    }

    private func loadPending() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        do {
            pending = try DaySheetStorage.makeDecoder().decode([QueuedMilestoneCommit].self, from: data)
        } catch {
            // Keep the file: an unreadable queue is a bug to inspect, not a
            // reason to silently start empty.
            print("[MILESTONE_QUEUE] unreadable queue left on disk: \(error)")
        }
    }

    private func savePending() {
        guard DaySheetStorage.ensureDirectory(directory, fileManager: fileManager) else { return }
        do {
            let data = try DaySheetStorage.makeEncoder().encode(pending)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("[MILESTONE_QUEUE] save failed: \(error)")
        }
    }
}
