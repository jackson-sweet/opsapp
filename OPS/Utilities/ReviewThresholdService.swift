//
//  ReviewThresholdService.swift
//  OPS
//
//  Reports the three review stacks (task review, payment review, unscheduled
//  review) to the server after each sync. The SERVER owns the rail semantics:
//  `sync_review_stack_notification` (SECURITY DEFINER, actor-derived) decides
//  whether a persistent rail notification is created, kept, or auto-cleared,
//  renders the fixed copy, and enforces at-most-one-unread-per-stack dedupe
//  under an advisory lock. The client's whole job is to hand over honest
//  counts — including zero, so a drained stack clears without user action.
//
//  Why an RPC and not an insert: the 2026-07-15 notification-creation
//  hardening revoked app-role INSERT on `notifications` (all creation crosses
//  a narrow actor-derived RPC or a trusted service boundary). The legacy
//  client-side insert died 42501 on every launch — silently, because push
//  and rail are separate rails (bug 88a0a1e3).
//
//  The 5+ threshold lives in the RPC now. It still deliberately has nothing
//  to do with the FAB review-queue UNLOCK gate (`ReviewUnlockThresholds`) —
//  "should I be told about this backlog?" is answered server-side, "have I
//  done enough work to open this feature?" stays a client design choice.
//  Retuning rail loudness is a server-side edit and must never move the
//  unlock gate, or vice versa.
//

import Foundation

/// Seam for reporting one review stack's count to the server. Conformed to by
/// `NotificationRepository` (the `sync_review_stack_notification` RPC); tests
/// substitute a spy.
protocol ReviewStackSyncing {
    /// Returns the server's verdict: `created`, `kept`, `cleared`, or `noop`.
    @discardableResult
    func syncReviewStack(stack: String, count: Int) async throws -> String
}

enum ReviewThresholdService {

    /// Notification `type` values in the `notifications` table — the RPC
    /// accepts exactly these three stack kinds. Distinct from the older
    /// `task_review_overdue` / `payment_review_overdue` periodic reminder
    /// types so the condensed threshold rail entries don't collide with them.
    private enum StackType: String, CaseIterable {
        case taskReview        = "task_review_stack"
        case paymentReview     = "payment_review_stack"
        case unscheduledReview = "unscheduled_review_stack"
    }

    // MARK: - Entry Point

    /// Report the shared actor-computed snapshot. Loading/failure is never
    /// reported as zero; a valid drained stack still reports all three zeros.
    @MainActor
    @discardableResult
    static func evaluate(
        dataController: DataController,
        syncer: ReviewStackSyncing = NotificationRepository.shared,
        snapshotStore: ReviewSnapshotStore? = nil
    ) -> Task<Void, Never>? {
        guard dataController.currentUser != nil else { return nil }
        let store = snapshotStore ?? .shared
        if snapshotStore == nil { store.bind(dataController: dataController) }
        return store.report(syncer: syncer)
    }

    /// Report every stack, every evaluation. One stack's transport failure
    /// must not starve the rest — each report is isolated.
    @MainActor
    static func syncAll(
        taskReviewCount: Int,
        paymentReviewCount: Int,
        unscheduledReviewCount: Int,
        syncer: ReviewStackSyncing,
        isCurrent: () -> Bool = { true }
    ) async {
        let reports: [(StackType, Int)] = [
            (.taskReview, taskReviewCount),
            (.paymentReview, paymentReviewCount),
            (.unscheduledReview, unscheduledReviewCount),
        ]
        for (stack, count) in reports {
            guard !Task.isCancelled, isCurrent() else { return }
            do {
                let action = try await syncer.syncReviewStack(
                    stack: stack.rawValue,
                    count: count
                )
                print("[REVIEW_STACK] \(stack.rawValue) — \(action) for count=\(count)")
            } catch {
                print("[REVIEW_STACK] \(stack.rawValue) — sync failed: \(error)")
            }
        }
    }

}
