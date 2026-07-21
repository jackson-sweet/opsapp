//
//  ReviewAccessPolicy.swift
//  OPS
//
//  Pure, testable permission and completion policy shared by review entry,
//  hints, gestures, accessibility actions, and mutation completion.
//

import Foundation

enum ReviewPermissionScope: String {
    case all
    case assigned
    case own

    init?(_ value: String?) {
        guard let value else { return nil }
        self.init(rawValue: value)
    }
}

struct PaymentReviewFinancialSummary: Equatable, Sendable {
    let invoiceCount: Int
    let unresolvedInvoiceCount: Int
    let outstandingInvoiceCount: Int
    let externallyManagedOutstandingInvoiceCount: Int
    let overdueInvoiceCount: Int
    let unresolvedBalance: Double
    let outstandingBalance: Double
    let currencyCode: String

    init(
        invoiceCount: Int,
        unresolvedInvoiceCount: Int,
        outstandingInvoiceCount: Int,
        externallyManagedOutstandingInvoiceCount: Int = 0,
        overdueInvoiceCount: Int,
        unresolvedBalance: Double,
        outstandingBalance: Double,
        currencyCode: String
    ) {
        self.invoiceCount = invoiceCount
        self.unresolvedInvoiceCount = unresolvedInvoiceCount
        self.outstandingInvoiceCount = outstandingInvoiceCount
        self.externallyManagedOutstandingInvoiceCount = externallyManagedOutstandingInvoiceCount
        self.overdueInvoiceCount = overdueInvoiceCount
        self.unresolvedBalance = unresolvedBalance
        self.outstandingBalance = outstandingBalance
        self.currencyCode = currencyCode
    }

    static func empty(currencyCode: String) -> PaymentReviewFinancialSummary {
        PaymentReviewFinancialSummary(
            invoiceCount: 0,
            unresolvedInvoiceCount: 0,
            outstandingInvoiceCount: 0,
            externallyManagedOutstandingInvoiceCount: 0,
            overdueInvoiceCount: 0,
            unresolvedBalance: 0,
            outstandingBalance: 0,
            currencyCode: currencyCode
        )
    }

    var hasOutstandingInvoices: Bool {
        outstandingInvoiceCount > 0 && outstandingBalance > 0
    }

    var hasExternallyManagedOutstandingInvoices: Bool {
        externallyManagedOutstandingInvoiceCount > 0
    }

    var hasUnresolvedInvoices: Bool {
        unresolvedInvoiceCount > 0 && unresolvedBalance > 0
    }

    var hasOverdueInvoices: Bool {
        overdueInvoiceCount > 0 && outstandingBalance > 0
    }
}

struct PaymentReviewAccessPolicy {
    let currentUserID: String?
    let projectEditScope: ReviewPermissionScope?
    let canViewInvoices: Bool
    let canSendInvoices: Bool
    let canEditInvoices: Bool

    func canClose(projectTeamMemberIDs: [String]) -> Bool {
        switch projectEditScope {
        case .all:
            return true
        case .assigned:
            return containsCurrentUser(projectTeamMemberIDs)
        case .own, .none:
            return false
        }
    }

    func allowedDirections(
        projectTeamMemberIDs: [String],
        financials: PaymentReviewFinancialSummary?
    ) -> Set<SwipeDirection> {
        var directions: Set<SwipeDirection> = [.left]
        guard canClose(projectTeamMemberIDs: projectTeamMemberIDs),
              let financials else {
            return directions
        }

        // Closing a project that still carries debt makes later partial
        // payments invalid. Outstanding balances must be resolved or written
        // off before the close action is available.
        if !financials.hasUnresolvedInvoices {
            directions.insert(.right)
        }
        if projectEditScope == .all,
           canViewInvoices,
           canSendInvoices,
           financials.hasOverdueInvoices {
            directions.insert(.up)
        }
        if canViewInvoices,
           canEditInvoices,
           financials.hasOutstandingInvoices,
           !financials.hasExternallyManagedOutstandingInvoices,
           financials.unresolvedInvoiceCount == financials.outstandingInvoiceCount {
            directions.insert(.down)
        }
        return directions
    }

    private func containsCurrentUser(_ ids: [String]) -> Bool {
        guard let currentUserID = currentUserID?.lowercased() else { return false }
        return ids.contains { $0.lowercased() == currentUserID }
    }
}

struct UnscheduledReviewTaskState {
    let taskTeamMemberIDs: [String]
    let projectTeamMemberIDs: [String]
    let isScheduled: Bool

    var isUnassigned: Bool { taskTeamMemberIDs.isEmpty }
}

struct UnscheduledReviewAccessPolicy {
    let currentUserID: String?
    let taskEditScope: ReviewPermissionScope?
    let canAssignTasks: Bool
    let taskStatusScope: ReviewPermissionScope?
    let calendarEditScope: ReviewPermissionScope?

    func allows(_ direction: SwipeDirection, task: UnscheduledReviewTaskState) -> Bool {
        if direction == .left { return true }

        let canEdit = canEditTask(task)
        guard canEdit else { return false }

        if task.isUnassigned {
            // Both right and up intentionally open crew assignment in this flow.
            if direction == .right || direction == .up {
                return canAssignTasks
            }
            return direction == .down && canChangeStatus(task)
        }

        switch direction {
        case .right:
            return !task.isScheduled && canSchedule(task)
        case .up, .down:
            return canChangeStatus(task)
        case .left:
            return true
        }
    }

    func canEditTask(_ task: UnscheduledReviewTaskState) -> Bool {
        switch taskEditScope {
        case .all:
            return true
        case .assigned:
            return containsCurrentUser(task.taskTeamMemberIDs)
                || containsCurrentUser(task.projectTeamMemberIDs)
        case .own, .none:
            return false
        }
    }

    func canSchedule(_ task: UnscheduledReviewTaskState) -> Bool {
        guard canEditTask(task) else { return false }
        switch calendarEditScope {
        case .all:
            return true
        case .assigned, .own:
            return containsCurrentUser(task.taskTeamMemberIDs)
        case .none:
            return false
        }
    }

    func canChangeStatus(_ task: UnscheduledReviewTaskState) -> Bool {
        guard canEditTask(task) else { return false }
        switch taskStatusScope {
        case .all:
            return true
        case .assigned:
            return containsCurrentUser(task.taskTeamMemberIDs)
                || containsCurrentUser(task.projectTeamMemberIDs)
        case .own, .none:
            return false
        }
    }

    func hasAvailableMutation(for task: UnscheduledReviewTaskState) -> Bool {
        [.right, .up, .down].contains { allows($0, task: task) }
    }

    private func containsCurrentUser(_ ids: [String]) -> Bool {
        guard let currentUserID = currentUserID?.lowercased() else { return false }
        return ids.contains { $0.lowercased() == currentUserID }
    }
}

enum UnscheduledReviewMutationOutcome {
    case skipped
    case succeeded
    case failed
    case denied
}

enum UnscheduledReviewCompletionPolicy {
    static func shouldFinish(_ outcome: UnscheduledReviewMutationOutcome) -> Bool {
        outcome == .skipped || outcome == .succeeded
    }
}

enum ReviewCrewAssignmentRebase {
    /// Reapply only the operator's picker delta to the latest assignment set.
    /// Crew added remotely while the sheet is open remain assigned, while a
    /// member the operator explicitly removed from the opening snapshot stays
    /// removed.
    static func rebase(
        baseline: Set<String>,
        selected: Set<String>,
        current: Set<String>
    ) -> Set<String> {
        let additions = selected.subtracting(baseline)
        let removals = baseline.subtracting(selected)
        return current.union(additions).subtracting(removals)
    }
}
