//
//  HomeBillableThisWeekNotificationDispatcher.swift
//  OPS
//

import Foundation

enum HomeBillableThisWeekNotificationDispatcher {
    /// The rail row's type is the server's to set; this constant survives
    /// because the local banner tags its `userInfo` with it so a tap routes to
    /// the same place (`NotificationManager.scheduleBillableThisWeekNotification`).
    static let notificationType = "billable_this_week"

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
                syncRemote: { projectCount, amount, weekKey in
                    try await repo.syncBillableWeek(
                        projectCount: projectCount,
                        amount: amount,
                        weekStart: weekKey
                    )
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
        syncRemote: (Int, Double, String) async throws -> String,
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

        // One call replaces the old read-then-insert pair. The server renders
        // the copy, owns the deep link, and decides whether this week is new:
        // `created` means the summary just landed, `kept` means the week was
        // already reported — read or unread — and must not be announced twice.
        do {
            let verdict = try await syncRemote(
                rollup.projectCount,
                rollup.totalKnownAmount,
                weekKey
            )

            switch verdict {
            case "created":
                scheduleLocalNotification(rollup.projectCount, rollup.totalKnownAmount)
                markWeekDispatched(weekKey)
                onNotificationCreated()
            case "kept":
                // The rail already carries this week. Record it locally so the
                // Monday gate stops asking, but no banner: a reinstall or a
                // second device must not re-announce delivered news.
                markWeekDispatched(weekKey)
            default:
                print("[BILLABLE_THIS_WEEK] Unexpected verdict '\(verdict)' — week left unrecorded")
            }
        } catch {
            print("[BILLABLE_THIS_WEEK] Notification dispatch failed: \(error)")
        }
    }

    static func weekStartKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func defaultsKey(userId: String, companyId: String) -> String {
        "homeBillableThisWeekNotification.\(companyId).\(userId)"
    }
}
