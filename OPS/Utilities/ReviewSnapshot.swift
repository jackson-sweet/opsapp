import Foundation

/// Effective permissions only: unrelated permission changes do not recount.
struct ReviewSnapshotAccess: Equatable, Sendable {
    let canViewAllTasks: Bool
    let taskEditScope: String?
    let canAssignTasks: Bool
    let taskStatusScope: String?
    let calendarEditScope: String?
    let projectEditScope: String?

    init(permissionStore: PermissionStore) {
        canViewAllTasks = permissionStore.hasFullAccess("tasks.view")
        taskEditScope = permissionStore.scope(for: "tasks.edit")
        canAssignTasks = permissionStore.hasFullAccess("tasks.assign")
        taskStatusScope = permissionStore.scope(for: "tasks.change_status")
        calendarEditScope = permissionStore.scope(for: "calendar.edit")
        projectEditScope = permissionStore.scope(for: "projects.edit")
    }

    init(canViewAllTasks: Bool, taskEditScope: String?, canAssignTasks: Bool,
         taskStatusScope: String?, calendarEditScope: String?, projectEditScope: String?) {
        self.canViewAllTasks = canViewAllTasks
        self.taskEditScope = taskEditScope
        self.canAssignTasks = canAssignTasks
        self.taskStatusScope = taskStatusScope
        self.calendarEditScope = calendarEditScope
        self.projectEditScope = projectEditScope
    }

    func unscheduledPolicy(userID: String?) -> UnscheduledReviewAccessPolicy {
        UnscheduledReviewAccessPolicy(
            currentUserID: userID, taskEditScope: ReviewPermissionScope(taskEditScope),
            canAssignTasks: canAssignTasks, taskStatusScope: ReviewPermissionScope(taskStatusScope),
            calendarEditScope: ReviewPermissionScope(calendarEditScope)
        )
    }

    func paymentPolicy(userID: String?) -> PaymentReviewAccessPolicy {
        PaymentReviewAccessPolicy(
            currentUserID: userID, projectEditScope: ReviewPermissionScope(projectEditScope),
            canViewInvoices: false, canSendInvoices: false, canEditInvoices: false
        )
    }
}

struct ReviewSnapshotScope: Equatable, Sendable {
    let containerID: ObjectIdentifier
    let companyID: String
    let userID: String
    let access: ReviewSnapshotAccess
    let calendar: Calendar
    let day: Date
    let overdueThresholdDays: Int
    let staleEstimateThresholdDays: Int
    let reminderFrequencyDays: Int
    let taskUnlockThreshold: Int
    let paymentUnlockThreshold: Int
    var usesDataActor: Bool = true
    var actorID: ObjectIdentifier? = nil
}

struct ReviewSnapshotRequest: Sendable {
    let scope: ReviewSnapshotScope
    let now: Date

    var endOfToday: Date {
        scope.calendar.startOfDay(for: scope.calendar.date(byAdding: .day, value: 1, to: now) ?? now)
    }

    @MainActor
    static func capture(dataController: DataController, permissionStore: PermissionStore,
                        now: Date = Date(), calendar: Calendar = .current) -> Self? {
        guard let context = dataController.modelContext,
              let user = dataController.currentUser, let companyID = user.companyId,
              !companyID.isEmpty else { return nil }
        let company = dataController.getCompany(id: companyID)
        return Self(scope: ReviewSnapshotScope(
            containerID: ObjectIdentifier(context.container), companyID: companyID, userID: user.id,
            access: ReviewSnapshotAccess(permissionStore: permissionStore), calendar: calendar,
            day: calendar.startOfDay(for: now),
            overdueThresholdDays: company?.overdueReviewThresholdDays ?? 14,
            staleEstimateThresholdDays: company?.staleEstimateThresholdDays ?? 30,
            reminderFrequencyDays: company?.overdueReminderFrequencyDays ?? 7,
            taskUnlockThreshold: ReviewUnlockThresholds.taskReview,
            paymentUnlockThreshold: ReviewUnlockThresholds.paymentReview,
            usesDataActor: FeatureFlags.useDataActor,
            actorID: FeatureFlags.useDataActor ? dataController.dataActor.map { ObjectIdentifier($0) } : nil
        ), now: now)
    }
}

struct ReviewSnapshotCounts: Equatable, Sendable {
    var completedTaskCount = 0
    var completedProjectCount = 0
    var taskReviewCount = 0
    var unscheduledReviewCount = 0
    var paymentReviewCount = 0
    var overduePaymentCount = 0
    var staleEstimateCount = 0
    var projectsWithoutTasksCount = 0
    var projectCount = 0
}

/// No SwiftData model may leave the actor through this value.
struct ReviewSnapshot: Equatable, Sendable {
    let scope: ReviewSnapshotScope
    let counts: ReviewSnapshotCounts
    let computedAt: Date
    var nextEligibilityChangeAt: Date = .distantFuture

    var isTaskReviewLocked: Bool { counts.completedTaskCount < scope.taskUnlockThreshold }
    var isPaymentReviewLocked: Bool { counts.completedProjectCount < scope.paymentUnlockThreshold }
    var taskBadgeCount: Int { isTaskReviewLocked ? 0 : counts.taskReviewCount }
    var paymentBadgeCount: Int { isPaymentReviewLocked ? 0 : counts.paymentReviewCount }
    var totalBadgeCount: Int { taskBadgeCount + paymentBadgeCount + counts.unscheduledReviewCount }
}

/// Membership predicates shared by explicit sheet row queries and scalar reads.
/// Date arithmetic intentionally uses elapsed calendar days, as the existing
/// reminder detectors do; overdue task membership includes all of today.
enum ReviewEligibility {
    static func overdueTask(isActive: Bool, isDeleted: Bool, scheduledDate: Date?, endOfToday: Date) -> Bool {
        guard isActive, !isDeleted, let scheduledDate else { return false }
        return scheduledDate < endOfToday
    }

    static func unscheduledTask(isActive: Bool, isDeleted: Bool, projectIsActive: Bool,
                                state: UnscheduledReviewTaskState, policy: UnscheduledReviewAccessPolicy) -> Bool {
        isActive && !isDeleted && projectIsActive
            && (!state.isScheduled || state.isUnassigned) && policy.hasAvailableMutation(for: state)
    }

    static func paymentProject(isCompleted: Bool, isDeleted: Bool, teamIDs: [String],
                               policy: PaymentReviewAccessPolicy) -> Bool {
        isCompleted && !isDeleted && policy.canClose(projectTeamMemberIDs: teamIDs)
    }

    static func overduePayment(completedAt: Date?, thresholdDays: Int, now: Date, calendar: Calendar) -> Bool {
        guard let completedAt else { return false }
        return (calendar.dateComponents([.day], from: completedAt, to: now).day ?? 0) >= thresholdDays
    }

    static func staleEstimate(recency: Date, thresholdDays: Int, now: Date, calendar: Calendar) -> Bool {
        (calendar.dateComponents([.day], from: recency, to: now).day ?? Int.max) >= thresholdDays
    }
}

/// Runs wherever the owning models live. Production calls this only inside
/// DataActor; array injection lets parity tests compare against the sheet rows.
enum ReviewSnapshotCalculator {
    static func compute(tasks: [ProjectTask], projects: [Project], request: ReviewSnapshotRequest) -> ReviewSnapshot {
        let scope = request.scope
        let taskPolicy = scope.access.unscheduledPolicy(userID: scope.userID)
        let paymentPolicy = scope.access.paymentPolicy(userID: scope.userID)
        let endOfToday = request.endOfToday
        var nextChange = endOfToday
        var counts = ReviewSnapshotCounts()
        var paymentIDs = Set<String>()
        for task in tasks where task.deletedAt == nil && task.companyId == scope.companyID {
            if task.status == .completed { counts.completedTaskCount += 1 }
            guard task.status == .active else { continue }
            let team = task.getTeamMemberIds()
            // Preserve tasks.view's existing case-sensitive assignment check.
            if (scope.access.canViewAllTasks || team.contains(scope.userID)),
               ReviewEligibility.overdueTask(isActive: true, isDeleted: false,
                    scheduledDate: task.endDate ?? task.startDate, endOfToday: endOfToday) {
                counts.taskReviewCount += 1
            }
            if ReviewEligibility.unscheduledTask(isActive: true, isDeleted: false,
                projectIsActive: task.project?.status.isActive ?? false,
                state: UnscheduledReviewTaskState(taskTeamMemberIDs: team,
                    projectTeamMemberIDs: task.project?.getTeamMemberIds() ?? [], isScheduled: task.startDate != nil),
                policy: taskPolicy) {
                counts.unscheduledReviewCount += 1
            }
        }
        for project in projects where project.deletedAt == nil && project.companyId == scope.companyID {
            counts.projectCount += 1
            if project.status == .completed || project.status == .closed { counts.completedProjectCount += 1 }
            if project.status == .completed,
               ReviewEligibility.paymentProject(isCompleted: true, isDeleted: false,
                teamIDs: project.getTeamMemberIds() + project.tasks.flatMap { $0.getTeamMemberIds() }, policy: paymentPolicy) {
                paymentIDs.insert(project.id)
                if let completedAt = project.completedAt,
                   let change = scope.calendar.date(byAdding: .day, value: scope.overdueThresholdDays, to: completedAt),
                   change > request.now { nextChange = min(nextChange, change) }
                if ReviewEligibility.overduePayment(completedAt: project.completedAt,
                    thresholdDays: scope.overdueThresholdDays, now: request.now, calendar: scope.calendar) {
                    counts.overduePaymentCount += 1
                }
            }
            if project.status == .estimated,
               let change = scope.calendar.date(byAdding: .day, value: scope.staleEstimateThresholdDays,
                    to: project.lastSyncedAt ?? project.startDate ?? .distantPast),
               change > request.now { nextChange = min(nextChange, change) }
            if project.status == .estimated,
               ReviewEligibility.staleEstimate(recency: project.lastSyncedAt ?? project.startDate ?? .distantPast,
                    thresholdDays: scope.staleEstimateThresholdDays, now: request.now, calendar: scope.calendar) {
                counts.staleEstimateCount += 1
            }
            if ProjectsWithoutTasksDetector.actionableStatuses.contains(project.status),
               !project.tasks.contains(where: { $0.deletedAt == nil }) {
                counts.projectsWithoutTasksCount += 1
            }
        }
        counts.paymentReviewCount = paymentIDs.count
        return ReviewSnapshot(scope: scope, counts: counts, computedAt: request.now, nextEligibilityChangeAt: nextChange)
    }
}
