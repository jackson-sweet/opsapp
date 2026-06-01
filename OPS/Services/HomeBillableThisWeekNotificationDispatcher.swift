//
//  HomeBillableThisWeekNotificationDispatcher.swift
//  OPS
//

import Foundation

enum HomeBillableThisWeekNotificationDispatcher {
    static let notificationType = "billable_this_week"
    static let deepLinkType = "billableThisWeek"
    static let actionLabel = "OPEN HOME"

    static func shouldDispatch(
        rollup: HomeBillableThisWeekRollup,
        now: Date,
        lastDispatchedWeekStart: String?,
        permissionCanViewFinances: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        guard permissionCanViewFinances, rollup.hasItems else { return false }
        guard calendar.component(.weekday, from: now) == 2 else { return false }
        return lastDispatchedWeekStart != weekStartKey(for: rollup.weekStart, calendar: calendar)
    }

    @MainActor
    static func dispatchIfNeeded(
        rollup: HomeBillableThisWeekRollup,
        userId: String?,
        companyId: String?,
        now: Date = Date(),
        permissionCanViewFinances: Bool,
        onNotificationCreated: @escaping () -> Void = {}
    ) {
        guard let userId, !userId.isEmpty,
              let companyId, !companyId.isEmpty else { return }

        let key = defaultsKey(userId: userId, companyId: companyId)
        Task { @MainActor in
            let repo = NotificationRepository()
            await dispatchIfNeeded(
                rollup: rollup,
                userId: userId,
                companyId: companyId,
                now: now,
                permissionCanViewFinances: permissionCanViewFinances,
                lastDispatchedWeekStart: {
                    UserDefaults.standard.string(forKey: key)
                },
                markWeekDispatched: { weekKey in
                    UserDefaults.standard.set(weekKey, forKey: key)
                },
                scheduleLocalNotification: { projectCount, totalKnownAmount in
                    NotificationManager.shared.scheduleBillableThisWeekNotification(
                        projectCount: projectCount,
                        totalKnownAmount: totalKnownAmount
                    )
                },
                hasRemoteNotification: { type, userId, actionUrl in
                    try await repo.hasNotification(
                        type: type,
                        userId: userId,
                        actionUrl: actionUrl
                    )
                },
                createRemoteNotification: { dto in
                    try await repo.createNotification(dto)
                },
                onNotificationCreated: onNotificationCreated
            )
        }
    }

    @MainActor
    static func dispatchIfNeeded(
        rollup: HomeBillableThisWeekRollup,
        userId: String?,
        companyId: String?,
        now: Date = Date(),
        permissionCanViewFinances: Bool,
        calendar: Calendar = .current,
        lastDispatchedWeekStart: () -> String?,
        markWeekDispatched: (String) -> Void,
        scheduleLocalNotification: (Int, Double) -> Void,
        hasRemoteNotification: (String, String, String) async throws -> Bool,
        createRemoteNotification: (NotificationRepository.CreateNotificationDTO) async throws -> Void,
        onNotificationCreated: () -> Void = {}
    ) async {
        guard let userId, !userId.isEmpty,
              let companyId, !companyId.isEmpty else { return }

        let weekKey = weekStartKey(for: rollup.weekStart, calendar: calendar)
        guard shouldDispatch(
            rollup: rollup,
            now: now,
            lastDispatchedWeekStart: lastDispatchedWeekStart(),
            permissionCanViewFinances: permissionCanViewFinances,
            calendar: calendar
        ) else { return }

        let actionUrl = actionUrl(forWeekStart: weekKey)

        do {
            let alreadyExists = try await hasRemoteNotification(
                notificationType,
                userId,
                actionUrl
            )
            if alreadyExists {
                markWeekDispatched(weekKey)
                return
            }

            let dto = NotificationRepository.CreateNotificationDTO(
                userId: userId,
                companyId: companyId,
                type: notificationType,
                title: "BILLABLE THIS WEEK",
                body: notificationBody(for: rollup),
                projectId: nil,
                noteId: nil,
                expenseId: nil,
                batchId: nil,
                deepLinkType: deepLinkType,
                persistent: false,
                actionUrl: actionUrl,
                actionLabel: actionLabel
            )
            try await createRemoteNotification(dto)
            scheduleLocalNotification(rollup.projectCount, rollup.totalKnownAmount)
            markWeekDispatched(weekKey)
            onNotificationCreated()
        } catch {
            print("[BILLABLE_THIS_WEEK] Notification dispatch failed: \(error)")
        }
    }

    static func notificationBody(for rollup: HomeBillableThisWeekRollup) -> String {
        let jobLabel = "\(rollup.projectCount) \(rollup.projectCount == 1 ? "job" : "jobs")"
        guard rollup.totalKnownAmount > 0 else {
            return "\(jobLabel) ready for billing"
        }
        return "\(jobLabel) / \(currency(rollup.totalKnownAmount)) billable"
    }

    static func weekStartKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func actionUrl(forWeekStart weekStart: String) -> String {
        "ops://home/billable-this-week?weekStart=\(weekStart)"
    }

    private static func defaultsKey(userId: String, companyId: String) -> String {
        "homeBillableThisWeekNotification.\(companyId).\(userId)"
    }

    private static func currency(_ amount: Double) -> String {
        "$\(wholeDollarFormatter.string(from: NSNumber(value: amount.rounded())) ?? "0")"
    }

    private static let wholeDollarFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
