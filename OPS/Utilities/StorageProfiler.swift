//
//  StorageProfiler.swift
//  OPS
//
//  Manages the photo storage budget for OPS on the device.
//
//  At first login, reads device free space and sets an initial budget
//  (20% of free space, clamped to [200 MB, 5 GB]). Stores budget + the
//  device's free-bytes-at-calibration + configured date in UserDefaults.
//
//  Exposes queries for current usage, headroom, and "would-exceed" predicates
//  used by PhotoPrefetchService (intake) and PhotoDownloadManager (eviction).
//
//  Usage is measured by walking the OPS photo directories:
//   - Documents/photos           (full-resolution originals awaiting upload)
//   - Documents/thumbnails       (200×200 thumbnails)
//   - Documents/ProjectImages    (remote-cached photos hashed by URL)
//

import Foundation

@MainActor
final class StorageProfiler {
    static let shared = StorageProfiler()

    // MARK: - UserDefaults Keys

    private enum Key {
        static let budgetBytes = "photoStorage.budgetBytes"
        static let initialFreeBytes = "photoStorage.initialDeviceFreeBytes"
        static let configuredAt = "photoStorage.configuredAt"
        static let userAdjustedBudget = "photoStorage.userAdjustedBudget"
    }

    // MARK: - Constants

    /// Hard floor — below this, OPS photo caching is effectively disabled.
    /// Chosen so a single site-visit batch (≈10 photos at 2 MB each) fits.
    static let minBudget: Int64 = 200 * 1024 * 1024             // 200 MB

    /// Hard ceiling — we never set a budget above this regardless of device size.
    /// Chosen as a reasonable limit for a work app; larger budgets are opt-in
    /// by the user via setBudget().
    static let initialMaxBudget: Int64 = 5 * 1024 * 1024 * 1024 // 5 GB

    /// Fraction of device free space used for the initial calibration.
    private static let budgetPercentageOfFreeSpace: Double = 0.20

    /// Fallback when free-space can't be read. Large enough that small devices
    /// still get a reasonable budget; small enough not to overwhelm storage.
    private static let fallbackFreeBytes: Int64 = 10 * 1024 * 1024 * 1024 // 10 GB

    /// Fallback budget when not yet calibrated.
    private static let fallbackBudget: Int64 = 2 * 1024 * 1024 * 1024    // 2 GB

    private init() {}

    // MARK: - Calibration

    /// Returns true if a budget has been recorded in UserDefaults.
    /// Used by the login flow to decide whether to run first-time calibration.
    var isCalibrated: Bool {
        UserDefaults.standard.object(forKey: Key.budgetBytes) != nil
    }

    /// Called once after first successful login. No-op if already calibrated.
    /// Reads device free space and computes a default budget as 20% of free,
    /// clamped to [minBudget, initialMaxBudget].
    func calibrateIfNeeded() {
        guard !isCalibrated else { return }

        let freeBytes = currentDeviceFreeBytes() ?? Self.fallbackFreeBytes
        let target = Int64(Double(freeBytes) * Self.budgetPercentageOfFreeSpace)
        let clamped = max(Self.minBudget, min(Self.initialMaxBudget, target))

        let defaults = UserDefaults.standard
        defaults.set(clamped, forKey: Key.budgetBytes)
        defaults.set(freeBytes, forKey: Key.initialFreeBytes)
        defaults.set(Date(), forKey: Key.configuredAt)
        defaults.set(false, forKey: Key.userAdjustedBudget)

        print("[StorageProfiler] Calibrated — device free: \(Self.formatBytes(freeBytes)), budget: \(Self.formatBytes(clamped))")
    }

    // MARK: - Queries

    /// Current budget in bytes. Returns a 2 GB fallback if not yet calibrated.
    nonisolated var budgetBytes: Int64 {
        let stored = Int64(UserDefaults.standard.integer(forKey: Key.budgetBytes))
        return stored > 0 ? stored : Self.fallbackBudget
    }

    /// Current on-disk photo storage usage in bytes.
    ///
    /// Walks the three OPS photo directories and sums allocated file sizes.
    /// Marked `nonisolated` so callers can run it off the main actor — this
    /// is essential for the Settings UI, which otherwise stalls main for
    /// seconds walking hundreds of megabytes of photos.
    nonisolated func currentUsageBytes() -> Int64 {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dirs = [
            docs.appendingPathComponent("photos", isDirectory: true),
            docs.appendingPathComponent("thumbnails", isDirectory: true),
            docs.appendingPathComponent("ProjectImages", isDirectory: true)
        ]

        var total: Int64 = 0
        for dir in dirs {
            total += Self.directorySize(at: dir)
        }
        return total
    }

    /// Remaining budget headroom in bytes. Negative value means over budget.
    nonisolated func headroomBytes() -> Int64 {
        budgetBytes - currentUsageBytes()
    }

    /// Would writing `bytes` of new content exceed the current budget?
    nonisolated func wouldExceedBudget(adding bytes: Int64) -> Bool {
        currentUsageBytes() + bytes > budgetBytes
    }

    /// Current device free space. Nil if the system query fails.
    nonisolated func currentDeviceFreeBytes() -> Int64? {
        let fm = FileManager.default
        let path = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        do {
            let attrs = try fm.attributesOfFileSystem(forPath: path)
            return attrs[.systemFreeSize] as? Int64
        } catch {
            print("[StorageProfiler] Failed to read free space: \(error)")
            return nil
        }
    }

    /// Device free space recorded at calibration time (for comparison/analytics).
    var initialFreeBytes: Int64? {
        guard UserDefaults.standard.object(forKey: Key.initialFreeBytes) != nil else {
            return nil
        }
        return Int64(UserDefaults.standard.integer(forKey: Key.initialFreeBytes))
    }

    /// Timestamp of the last calibration.
    var configuredAt: Date? {
        UserDefaults.standard.object(forKey: Key.configuredAt) as? Date
    }

    /// True once the user has explicitly changed the budget from its default.
    var userAdjustedBudget: Bool {
        UserDefaults.standard.bool(forKey: Key.userAdjustedBudget)
    }

    // MARK: - Mutation

    /// Update the budget — e.g., user raised the cap via the Settings slider.
    /// Clamped to [minBudget, maxAllowedBudget()]. Marks userAdjustedBudget=true
    /// so we don't quietly re-calibrate on future launches.
    func setBudget(_ newValue: Int64) {
        let upperBound = maxAllowedBudget()
        let clamped = max(Self.minBudget, min(upperBound, newValue))
        UserDefaults.standard.set(clamped, forKey: Key.budgetBytes)
        UserDefaults.standard.set(true, forKey: Key.userAdjustedBudget)
        print("[StorageProfiler] Budget updated → \(Self.formatBytes(clamped))")
    }

    /// Maximum budget the user can set right now:
    ///  - no lower than current on-disk usage (can't promise to store less than
    ///    what's already there without eviction)
    ///  - no higher than 50% of current device free space (leave room for iOS
    ///    and other apps)
    /// Both bounded by the hard floor.
    nonisolated func maxAllowedBudget() -> Int64 {
        let free = currentDeviceFreeBytes() ?? Self.fallbackFreeBytes
        let halfOfFree = max(Self.minBudget, free / 2)
        let currentUsage = currentUsageBytes()
        return max(halfOfFree, currentUsage)
    }

    // MARK: - Helpers

    /// Computes the total allocated size of a directory by walking its contents.
    /// Returns 0 if the directory doesn't exist or isn't enumerable.
    nonisolated private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
              ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
                  let size = values.totalFileAllocatedSize else { continue }
            total += Int64(size)
        }
        return total
    }

    /// Human-readable byte formatter for log messages and UI labels.
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }
}
