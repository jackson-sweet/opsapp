import Foundation

/// A single serialized accounting boundary for cache writers and intake reservations.
/// Directory enumeration occurs only at initialization/reconciliation, never per photo.
final class PhotoCacheLedger: @unchecked Sendable {
    static let shared = PhotoCacheLedger(directories: {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return ["photos", "thumbnails", "ProjectImages"].map {
            documents.appendingPathComponent($0, isDirectory: true)
        }
    }())

    struct Entry {
        var bytes: Int64
        var modified: Date
    }
    private let directories: [URL]
    private let lock = NSRecursiveLock()
    private var entries: [URL: Entry] = [:]
    private var reservations: [UUID: Int64] = [:]
    private var usedBytes: Int64 = 0
    private var initialized = false
    private(set) var snapshotCount = 0

    init(directories: [URL]) { self.directories = directories }

    func reconcile() {
        locked {
            entries = [:]
            usedBytes = 0
            for directory in directories {
                guard let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for case let url as URL in enumerator {
                    if let entry = Self.entry(at: url) { entries[url.standardizedFileURL] = entry; usedBytes += entry.bytes }
                }
            }
            initialized = true
            snapshotCount += 1
        }
    }

    func snapshot() -> Int64 {
        locked { ensureSnapshot(); return usage }
    }

    func reserve(bytes: Int64, budget: Int64) -> UUID? {
        locked {
            ensureSnapshot()
            let bytes = max(0, bytes)
            guard bytes <= max(0, budget - usage - reserved) else { return nil }
            let id = UUID()
            reservations[id] = bytes
            return id
        }
    }

    func release(_ id: UUID) { _ = locked { reservations.removeValue(forKey: id) } }

    /// Atomic overwrite + actual allocated-byte settlement. Pending local originals
    /// bypass the cache budget and can never be selected for eviction.
    func write(
        data: Data, to url: URL, budget: Int64?, reservation: UUID? = nil,
        allowEviction: Bool = true, pinnedFilenames: Set<String> = []
    ) -> Bool {
        locked {
            ensureSnapshot()
            let url = url.standardizedFileURL
            let old = entries[url]?.bytes ?? 0
            let ownReservation = reservation.flatMap { reservations[$0] } ?? 0
            let otherReservations = max(0, reserved - ownReservation)
            // APFS files consume allocation blocks, not their compressed JPEG length.
            let incoming = ((Int64(data.count) + 4095) / 4096) * 4096
            if let budget {
                if allowEviction {
                    _ = evictLocked(bytesNeeded: max(0, incoming - old) + otherReservations,
                                    budget: budget, pinned: pinnedFilenames, excluding: url)
                }
                guard usage - old + incoming + otherReservations <= budget else { return false }
            }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                let entry = Self.entry(at: url) ?? Entry(bytes: incoming, modified: Date())
                entries[url] = entry
                usedBytes += entry.bytes - old
                if let reservation { reservations.removeValue(forKey: reservation) }
                return true
            } catch { return false }
        }
    }

    @discardableResult
    func remove(_ url: URL) -> Bool {
        locked {
            let url = url.standardizedFileURL
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                usedBytes -= entries.removeValue(forKey: url)?.bytes ?? 0
                return true
            } catch { return false }
        }
    }

    @discardableResult
    func evict(bytesNeeded: Int64, budget: Int64, pinned: Set<String>) -> Int64 {
        locked {
            ensureSnapshot()
            return evictLocked(bytesNeeded: bytesNeeded + reserved, budget: budget, pinned: pinned, excluding: nil)
        }
    }

    private func evictLocked(bytesNeeded: Int64, budget: Int64, pinned: Set<String>, excluding: URL?) -> Int64 {
        guard usage + bytesNeeded > budget else { return 0 }
        let candidates = entries.filter { url, _ in
            let name = url.lastPathComponent
            return url != excluding && url.deletingLastPathComponent().lastPathComponent == "ProjectImages"
                && (name.hasPrefix("remote_") || name.hasPrefix("composited_remote_"))
                && !pinned.contains(name)
        }.sorted { $0.value.modified < $1.value.modified }
        var freed: Int64 = 0
        for (url, entry) in candidates {
            guard usage + bytesNeeded > budget else { break }
            if remove(url) { freed += entry.bytes }
        }
        return freed
    }

    private var usage: Int64 { usedBytes }
    private var reserved: Int64 { reservations.values.reduce(0, +) }
    private func ensureSnapshot() { if !initialized { reconcile() } }
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
    private static func entry(at url: URL) -> Entry? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true else { return nil }
        return Entry(bytes: Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0),
                     modified: values.contentModificationDate ?? .distantPast)
    }
}

extension PhotoCacheLedger {
    nonisolated func backgroundSnapshot(reconcile: Bool = false) async -> Int64 {
        if reconcile { self.reconcile() }
        return snapshot()
    }
    nonisolated func reserveInBackground(bytes: Int64, budget: Int64) async -> UUID? {
        reserve(bytes: bytes, budget: budget)
    }
}
