//
//  ForecastNotificationDispatcher.swift
//  OPS
//
//  Inspects a ForecastResult and the persisted ForecastAlert ledger, decides
//  whether to fire / re-fire / clear the dip notification.
//
//  Anti-spam rules (spec §7.3):
//   - First dip: no prior `last_dip_notified_at` OR a `last_cleared_at` newer
//     than the last notification.
//   - 10%-worse: ≥24h since last notify AND new lowest < prior lowest × 0.9.
//   - Cleared: state transitions out of .danger → fire one-shot non-persistent
//     "DIP CLEARED" notification, mark `last_cleared_at`, reset
//     `dismissed_until_balance`.
//
//  Recipients are looked up via `public.users_with_permission` — never by role.
//

import Foundation
import Supabase

actor ForecastNotificationDispatcher {
    private let companyId: String
    private let alertRepo: ForecastAlertRepository
    private let notificationRepo: NotificationRepository

    /// Per-session flag — UI gates the .warning haptic to the first render of
    /// this session where state is .danger.
    static var sessionHasShownDipHaptic = false

    init(companyId: String) {
        self.companyId = companyId
        self.alertRepo = ForecastAlertRepository(companyId: companyId)
        self.notificationRepo = NotificationRepository()
    }

    func reactTo(result: ForecastResult) async {
        guard !companyId.isEmpty else { return }

        let prior = try? await alertRepo.fetch()

        switch result.state {
        case .danger:
            await handleDanger(result: result, prior: prior)
        case .lowWater, .healthy:
            // Only fire "cleared" if there was an active dip that hasn't yet
            // been marked cleared.
            if let p = prior,
               p.lastDipNotifiedAt != nil,
               p.lastClearedAt == nil {
                await fireClearedNotification(result: result, prior: p)
            }
        }
    }

    // MARK: - Danger path

    private func handleDanger(result: ForecastResult, prior: ForecastAlertDTO?) async {
        // No prior row — first ever dip for this company.
        guard let prior else {
            await fireDipNotification(result: result, prior: nil)
            return
        }

        // Dismissed-until check: user clicked "don't show again". Suppress
        // unless the dip has materially worsened (10% deeper).
        if let dismissedAt = prior.dismissedUntilBalance,
           result.lowestBalance >= dismissedAt * 0.9 {
            return
        }

        // First dip after a clear.
        if let clearedStr = prior.lastClearedAt,
           let cleared = SupabaseDate.parse(clearedStr),
           let notifiedStr = prior.lastDipNotifiedAt,
           let lastNotified = SupabaseDate.parse(notifiedStr),
           cleared > lastNotified {
            await fireDipNotification(result: result, prior: prior)
            return
        }

        // 10%-worse rule.
        if let priorMin = prior.lastDipMinBalance,
           let notifiedStr = prior.lastDipNotifiedAt,
           let lastNotified = SupabaseDate.parse(notifiedStr) {
            let hoursSince = Date().timeIntervalSince(lastNotified) / 3600
            if hoursSince > 24 && result.lowestBalance < priorMin * 0.9 {
                await fireDipNotification(result: result, prior: prior)
            }
            return
        }

        // No prior notification yet for this row → first dip.
        if prior.lastDipNotifiedAt == nil {
            await fireDipNotification(result: result, prior: prior)
        }
    }

    // MARK: - Side effects

    private func fireDipNotification(result: ForecastResult, prior: ForecastAlertDTO?) async {
        let lowestWeek = result.weeks[result.lowestWeekIndex]
        let body = "Balance drops to \(formatCurrency(result.lowestBalance)) the week of \(formatWeek(lowestWeek.weekStart))."

        let recipients: [String]
        do {
            recipients = try await RecipientLookupService.usersWithPermission(
                companyId: companyId,
                permission: "finances.view",
                requiredScope: "own"
            )
        } catch {
            return
        }

        for userId in recipients {
            let dto = NotificationRepository.CreateNotificationDTO(
                userId: userId,
                companyId: companyId,
                type: "forecast_dip",
                title: "// CASH DIP PROJECTED",
                body: body,
                deepLinkType: "cashflow",
                persistent: true,
                actionUrl: "/books/cashflow",
                actionLabel: "REVIEW FORECAST"
            )
            try? await notificationRepo.createNotification(dto)
        }

        let payload = UpsertForecastAlertDTO(
            companyId: companyId,
            lastDipNotifiedAt: SupabaseDate.format(Date()),
            lastDipMinBalance: result.lowestBalance,
            lastDipMinWeekStart: SupabaseDate.formatDate(lowestWeek.weekStart),
            lastClearedAt: nil,
            dismissedUntilBalance: prior?.dismissedUntilBalance
        )
        _ = try? await alertRepo.upsert(payload)
    }

    private func fireClearedNotification(result: ForecastResult, prior: ForecastAlertDTO) async {
        let recipients: [String]
        do {
            recipients = try await RecipientLookupService.usersWithPermission(
                companyId: companyId,
                permission: "finances.view",
                requiredScope: "own"
            )
        } catch {
            return
        }

        for userId in recipients {
            let dto = NotificationRepository.CreateNotificationDTO(
                userId: userId,
                companyId: companyId,
                type: "forecast_cleared",
                title: "// CASH DIP CLEARED",
                body: "Projected balance now stays positive across the forecast horizon.",
                deepLinkType: "cashflow",
                persistent: false,
                actionUrl: "/books/cashflow",
                actionLabel: "VIEW FORECAST"
            )
            try? await notificationRepo.createNotification(dto)
        }

        // Mark cleared; reset dismissal so a *new* dip can re-notify.
        let payload = UpsertForecastAlertDTO(
            companyId: companyId,
            lastDipNotifiedAt: prior.lastDipNotifiedAt,
            lastDipMinBalance: prior.lastDipMinBalance,
            lastDipMinWeekStart: prior.lastDipMinWeekStart,
            lastClearedAt: SupabaseDate.format(Date()),
            dismissedUntilBalance: nil
        )
        _ = try? await alertRepo.upsert(payload)
    }

    private func formatCurrency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }

    private func formatWeek(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
