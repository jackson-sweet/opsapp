//
//  PendingWorkRetryTracker.swift
//  OPS
//
//  Truthful retry feedback for the PENDING WORK recovery surface. Re-arming
//  local work is not success: an attempt must first appear in the sending
//  inventory, then leave the recovery inventory, before the UI may confirm it.
//

import Foundation

enum PendingWorkRetryFeedback: Equatable {
    case retrying
    case succeeded
    case failed
}

struct PendingWorkRetryReconciliation: Equatable {
    let succeededIDs: [String]
    let failedIDs: [String]
    let expiredSuccessIDs: [String]
}

struct PendingWorkRetryTracker {
    static let successReceiptDuration: TimeInterval = 2

    private enum AttemptState {
        case armed
        case retrying
        case succeeded(at: Date)
        case failed
    }

    private struct Attempt {
        let item: RecoveryItem
        var state: AttemptState
    }

    private var attemptsByID: [String: Attempt] = [:]

    var feedbackByID: [String: PendingWorkRetryFeedback] {
        attemptsByID.reduce(into: [:]) { result, entry in
            switch entry.value.state {
            case .armed, .retrying:
                result[entry.key] = .retrying
            case .succeeded:
                result[entry.key] = .succeeded
            case .failed:
                result[entry.key] = .failed
            }
        }
    }

    var successReceipts: [RecoveryItem] {
        attemptsByID.values
            .compactMap { attempt in
                if case .succeeded = attempt.state { return attempt.item }
                return nil
            }
            .sorted { $0.sortDate < $1.sortDate }
    }

    mutating func begin(items: [RecoveryItem]) {
        for item in items where item.isRetryableFromAttention {
            attemptsByID[item.id] = Attempt(item: item, state: .armed)
        }
    }

    mutating func reconcile(
        inventory: RecoveryInventory,
        now: Date
    ) -> PendingWorkRetryReconciliation {
        let attentionIDs = Set(inventory.attention.map(\.id))
        let sendingIDs = Set(inventory.sending.map(\.id))
        var succeededIDs: [String] = []
        var failedIDs: [String] = []
        var expiredSuccessIDs: [String] = []

        for id in attemptsByID.keys.sorted() {
            guard var attempt = attemptsByID[id] else { continue }

            switch attempt.state {
            case .armed:
                if sendingIDs.contains(id) {
                    attempt.state = .retrying
                } else {
                    // Absence is not success until in-flight evidence has existed.
                    attempt.state = .failed
                    failedIDs.append(id)
                }
            case .retrying:
                if attentionIDs.contains(id) {
                    attempt.state = .failed
                    failedIDs.append(id)
                } else if !sendingIDs.contains(id) {
                    attempt.state = .succeeded(at: now)
                    succeededIDs.append(id)
                }
            case .succeeded(let completedAt):
                if now.timeIntervalSince(completedAt) >= Self.successReceiptDuration {
                    attemptsByID[id] = nil
                    expiredSuccessIDs.append(id)
                    continue
                }
            case .failed:
                break
            }

            attemptsByID[id] = attempt
        }

        return PendingWorkRetryReconciliation(
            succeededIDs: succeededIDs,
            failedIDs: failedIDs,
            expiredSuccessIDs: expiredSuccessIDs
        )
    }
}

extension RecoveryItem {
    var isRetryableFromAttention: Bool {
        switch self {
        case .op, .autocreate, .photos, .bundle:
            return tone >= .attention
        case .draft, .orphanDesign, .quarantinedVisit:
            return false
        }
    }
}
