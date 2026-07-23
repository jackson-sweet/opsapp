//
//  ShareCaptureOutcome.swift
//  Shared between the OPS app and OPSShareExtension.
//
//  A share is only accepted when every selected photo is durably represented by
//  the App Group recovery ledger. Partial capture is a failure: telling an
//  operator that two of three photos landed would invite a retry that duplicates
//  the first two.
//

import Foundation

enum ShareCaptureOutcome: Equatable {
    case queued(count: Int)
    case failed
    /// The manifest write was attempted but its acknowledgement was ambiguous.
    /// Photo bytes stay on disk and retry is withheld to avoid duplicate jobs.
    case retainedForRecovery

    /// Only a definite pre-commit failure is safe to roll back. Ambiguous writes
    /// retain the staged bytes until OPS has had a chance to inspect the queue.
    var shouldDiscardStagedFiles: Bool {
        self == .failed
    }

    init(
        selectedCount: Int,
        persistedCount: Int,
        recoveryResult: ShareUploadRecoveryStore.SaveResult
    ) {
        guard selectedCount > 0, persistedCount == selectedCount else {
            self = .failed
            return
        }
        switch recoveryResult {
        case .committed:
            self = .queued(count: persistedCount)
        case .rejected:
            self = .failed
        case .uncertain:
            self = .retainedForRecovery
        }
    }
}
