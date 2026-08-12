//
//  ReviewUnlockThresholds.swift
//  OPS
//
//  The completed-work counts that unlock the review queues.
//
//  Review is a learned habit, not a day-one feature: an operator with two
//  finished jobs has nothing to review, and a review stack shown empty teaches
//  them the entry point is dead. So both queues stay locked — visible, with the
//  remaining count — until enough work has actually closed out.
//
//  The same gate is rendered in two places: the JobBoard header entries and the
//  FAB review menu (which caches the locked/unlocked verdict rather than
//  recomputing it per render). Both read the value from here so the number the
//  operator is promised on one surface cannot drift from the other, or from the
//  "Complete N …" copy that explains the lock.
//
//  Not to be confused with `ReviewThresholdService.threshold`, which decides
//  when a review BACKLOG is loud enough to earn a rail notification. The two
//  numbers coincide today by design, but they answer different questions
//  (may I open this? / should I be told about this?) and are deliberately
//  separate knobs — moving one must not silently move the other.
//

import Foundation

enum ReviewUnlockThresholds {

    /// Completed tasks required before Task Review unlocks. Counted over the
    /// operator's whole task history, not a window.
    static let taskReview: Int = 5

    /// Completed-or-closed projects required before Payment Review unlocks.
    static let paymentReview: Int = 5
}
