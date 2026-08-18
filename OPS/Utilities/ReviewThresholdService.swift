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

    /// Compute all three review-stack counts from local state and report them
    /// to the server, which surfaces / keeps / clears the matching rail
    /// notifications. Safe to call after every sync.
    ///
    /// The SwiftData reads are synchronous on the caller's thread; the RPC
    /// calls run on a background `Task` (returned for tests to await —
    /// production call sites discard it).
    ///
    /// - Returns: the reporting task, or `nil` when no operator is resolved.
    @discardableResult
    static func evaluate(
        dataController: DataController,
        syncer: ReviewStackSyncing = NotificationRepository.shared
    ) -> Task<Void, Never>? {
        guard dataController.currentUser != nil else {
            print("[REVIEW_STACK] Skipped — no current user")
            return nil
        }

        let taskReviewCount        = computeTaskReviewCount(dataController: dataController)
        let paymentReviewCount     = computePaymentReviewCount(dataController: dataController)
        let unscheduledReviewCount = computeUnscheduledReviewCount(dataController: dataController)

        print("[REVIEW_STACK] counts — task=\(taskReviewCount) payment=\(paymentReviewCount) unscheduled=\(unscheduledReviewCount)")

        return Task {
            await syncAll(
                taskReviewCount: taskReviewCount,
                paymentReviewCount: paymentReviewCount,
                unscheduledReviewCount: unscheduledReviewCount,
                syncer: syncer
            )
        }
    }

    /// Report every stack, every evaluation. One stack's transport failure
    /// must not starve the rest — each report is isolated.
    static func syncAll(
        taskReviewCount: Int,
        paymentReviewCount: Int,
        unscheduledReviewCount: Int,
        syncer: ReviewStackSyncing
    ) async {
        let reports: [(StackType, Int)] = [
            (.taskReview, taskReviewCount),
            (.paymentReview, paymentReviewCount),
            (.unscheduledReview, unscheduledReviewCount),
        ]
        for (stack, count) in reports {
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

    // MARK: - Count Sources
    // Task counts delegate to TaskReviewQuery — the single source of truth the
    // FAB badge, JobBoard entries, and periodic push all share — so every rail
    // count agrees with the in-app review stack the user actually opens.

    private static func computeTaskReviewCount(dataController: DataController) -> Int {
        TaskReviewQuery.overdueReviewTasks(dataController: dataController).count
    }

    private static func computePaymentReviewCount(dataController: DataController) -> Int {
        ProjectReviewQuery.snapshot(dataController: dataController).count
    }

    private static func computeUnscheduledReviewCount(dataController: DataController) -> Int {
        TaskReviewQuery.unscheduledReviewTasks(dataController: dataController).count
    }
}
