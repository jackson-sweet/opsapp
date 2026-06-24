//
//  ReviewThresholdService.swift
//  OPS
//
//  Evaluates the three review stacks (task review, payment review, unscheduled
//  review) after each sync and surfaces a persistent rail notification whenever
//  a stack crosses the threshold. When a stack drops back below the threshold,
//  the matching unread notifications are marked as read so the rail clears
//  automatically without user action.
//
//  The threshold mirrors the FAB review-queue lock: 5 items. Below 5, the
//  review is manageable; at 5+, it's worth calling out.
//

import Foundation

enum ReviewThresholdService {

    /// Stacks below this count are considered manageable and do not surface
    /// a rail notification. Matches the FAB lock threshold in
    /// FloatingActionMenu.refreshReviewCounts().
    static let threshold: Int = 5

    /// Notification types written into the `notifications` table. These are
    /// distinct from the existing `task_review_overdue` / `payment_review_overdue`
    /// types so the condensed threshold rail entries don't collide with the
    /// older periodic reminder notifications.
    private enum StackType: String {
        case taskReview       = "task_review_stack"
        case paymentReview    = "payment_review_stack"
        case unscheduledReview = "unscheduled_review_stack"

        var deepLink: String {
            switch self {
            case .taskReview:        return "taskReview"
            case .paymentReview:     return "paymentReview"
            case .unscheduledReview: return "unscheduledReview"
            }
        }

        var actionLabel: String { "REVIEW" }
    }

    // MARK: - Entry Point

    /// Evaluate all three review stacks for the current user and upsert / clear
    /// the matching rail notifications. Safe to call after every sync.
    ///
    /// - Parameter dataController: the app's `DataController`, used to read
    ///   local SwiftData state for the current user. The data reads are
    ///   synchronous and happen on the caller's thread; network upsert/clear
    ///   runs on a background `Task`.
    static func evaluate(dataController: DataController) {
        guard let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId
        else {
            print("[REVIEW_STACK] Skipped — no current user / company")
            return
        }

        let taskReviewCount        = computeTaskReviewCount(dataController: dataController)
        let paymentReviewCount     = computePaymentReviewCount(dataController: dataController)
        let unscheduledReviewCount = computeUnscheduledReviewCount(dataController: dataController)

        print("[REVIEW_STACK] counts — task=\(taskReviewCount) payment=\(paymentReviewCount) unscheduled=\(unscheduledReviewCount)")

        let repo = NotificationRepository()

        Task {
            await syncStack(
                stack: .taskReview,
                count: taskReviewCount,
                title: "TASKS PILING UP",
                body: "\(taskReviewCount) past due. Close them out.",
                userId: userId,
                companyId: companyId,
                repo: repo
            )
            await syncStack(
                stack: .paymentReview,
                count: paymentReviewCount,
                title: "PAYMENTS SITTING",
                body: "\(paymentReviewCount) closed. Collect.",
                userId: userId,
                companyId: companyId,
                repo: repo
            )
            await syncStack(
                stack: .unscheduledReview,
                count: unscheduledReviewCount,
                title: "LOOSE ENDS",
                body: "\(unscheduledReviewCount) tasks with no date or crew.",
                userId: userId,
                companyId: companyId,
                repo: repo
            )
        }
    }

    // MARK: - Upsert / Clear

    /// Insert a persistent rail notification when `count ≥ threshold` and no
    /// unread one of the same type already exists; otherwise mark any existing
    /// unread notifications of this type as read so the rail clears.
    private static func syncStack(
        stack: StackType,
        count: Int,
        title: String,
        body: String,
        userId: String,
        companyId: String,
        repo: NotificationRepository
    ) async {
        if count >= threshold {
            // Dedup: only create a new row if the user doesn't already have
            // one outstanding for this stack.
            do {
                let alreadyShown = try await repo.hasUnreadOfType(type: stack.rawValue, userId: userId)
                guard !alreadyShown else {
                    print("[REVIEW_STACK] \(stack.rawValue) — existing unread, skipping insert")
                    return
                }
            } catch {
                print("[REVIEW_STACK] \(stack.rawValue) — dedup check failed: \(error). Proceeding.")
            }

            let dto = NotificationRepository.CreateNotificationDTO(
                userId: userId,
                companyId: companyId,
                type: stack.rawValue,
                title: title,
                body: body,
                projectId: nil,
                noteId: nil,
                expenseId: nil,
                batchId: nil,
                deepLinkType: stack.deepLink,
                persistent: true,
                actionUrl: "ops://\(stack.deepLink)",
                actionLabel: stack.actionLabel
            )

            do {
                try await repo.createNotification(dto)
                print("[REVIEW_STACK] \(stack.rawValue) — created for count=\(count)")
            } catch {
                print("[REVIEW_STACK] \(stack.rawValue) — create failed: \(error)")
            }
        } else {
            // Count dropped back below threshold — auto-clear any unread
            // notifications of this stack type so the rail goes quiet.
            do {
                try await repo.markAllAsReadByType(type: stack.rawValue, userId: userId)
            } catch {
                print("[REVIEW_STACK] \(stack.rawValue) — auto-clear failed: \(error)")
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
        let allProjects = dataController.getProjects()

        let threshold: Int
        if let companyId = dataController.currentUser?.companyId,
           let company = dataController.getCompany(id: companyId) {
            threshold = company.overdueReviewThresholdDays
        } else {
            threshold = 14
        }

        let overdueCount = OverdueProjectDetector.overdueProjects(
            from: allProjects,
            thresholdDays: threshold
        ).count

        let completedCount = allProjects.filter {
            $0.status == .completed && $0.deletedAt == nil
        }.count

        return overdueCount + completedCount
    }

    private static func computeUnscheduledReviewCount(dataController: DataController) -> Int {
        TaskReviewQuery.unscheduledReviewTasks(dataController: dataController).count
    }
}
