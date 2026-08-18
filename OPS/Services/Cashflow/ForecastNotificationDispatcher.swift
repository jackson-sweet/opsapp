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
//  Recipients are derived server-side from `public.users_with_permission` —
//  never by role, and never by a client-side lookup. The client keeps only the
//  anti-spam cadence (the `forecast_alerts` ledger); the rail rows themselves
//  are created and resolved by the narrow RPCs.
//

import Foundation
import Supabase

/// Seam for the cashflow forecast rail rows. Conformed to by
/// `NotificationRepository` (the `sync_forecast_dip_notification` /
/// `sync_forecast_cleared_notification` RPCs); tests substitute a spy.
protocol ForecastRailNotifying {
    /// Persistent dip alert to every `finances.view` holder, the actor
    /// included — a cash dip is a company condition, not an actor echo.
    /// Returns the ids that received NEW rows.
    @discardableResult
    func syncForecastDip(lowestBalance: Double, weekStart: String) async throws -> [String]

    /// Resolves the company's standing dip rows — a persistent row must never
    /// outlive its condition — and posts the all-clear.
    @discardableResult
    func syncForecastCleared() async throws -> [String]
}

extension NotificationRepository: ForecastRailNotifying {}

/// Seam for the `forecast_alerts` anti-spam ledger. Conformed to by
/// `ForecastAlertRepository`; tests substitute a spy.
protocol ForecastAlertLedgering {
    func fetch() async throws -> ForecastAlertDTO?
    func upsert(_ dto: UpsertForecastAlertDTO) async throws -> ForecastAlertDTO
}

extension ForecastAlertRepository: ForecastAlertLedgering {}

actor ForecastNotificationDispatcher {
    private let companyId: String
    private let ledger: ForecastAlertLedgering
    private let railSyncer: ForecastRailNotifying

    /// Per-session flag — UI gates the .warning haptic to the first render of
    /// this session where state is .danger.
    static var sessionHasShownDipHaptic = false

    /// `ledger` defaults to the live `forecast_alerts` repository for this
    /// company. A Swift default argument cannot reference another parameter,
    /// so nil means "build the real one".
    init(
        companyId: String,
        railSyncer: ForecastRailNotifying = NotificationRepository.shared,
        ledger: ForecastAlertLedgering? = nil
    ) {
        self.companyId = companyId
        self.ledger = ledger ?? ForecastAlertRepository(companyId: companyId)
        self.railSyncer = railSyncer
    }

    func reactTo(result: ForecastResult) async {
        guard !companyId.isEmpty else { return }

        let prior = try? await ledger.fetch()

        switch result.state {
        case .danger:
            await handleDanger(result: result, prior: prior)
        case .lowWater, .healthy:
            // Only fire "cleared" if there was an active dip that hasn't yet
            // been marked cleared.
            if let p = prior,
               p.lastDipNotifiedAt != nil,
               p.lastClearedAt == nil {
                await fireClearedNotification(prior: p)
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

        // The server resolves every `finances.view` holder, renders the
        // currency and the week, and replaces a stale unread dip rather than
        // stacking one. Contained on purpose: the ledger below is the
        // anti-spam cadence, and a failed rail row must not strand it in its
        // pre-dip state — that re-fired the same alert on the next tick.
        _ = try? await railSyncer.syncForecastDip(
            lowestBalance: result.lowestBalance,
            weekStart: SupabaseDate.formatDate(lowestWeek.weekStart)
        )

        let payload = UpsertForecastAlertDTO(
            companyId: companyId,
            lastDipNotifiedAt: SupabaseDate.format(Date()),
            lastDipMinBalance: result.lowestBalance,
            lastDipMinWeekStart: SupabaseDate.formatDate(lowestWeek.weekStart),
            lastClearedAt: nil,
            dismissedUntilBalance: prior?.dismissedUntilBalance
        )
        _ = try? await ledger.upsert(payload)
    }

    private func fireClearedNotification(prior: ForecastAlertDTO) async {
        // One call resolves the company's standing dip rows and posts the
        // all-clear to the same holders. Contained for the same reason as the
        // dip lane.
        _ = try? await railSyncer.syncForecastCleared()

        // Mark cleared; reset dismissal so a *new* dip can re-notify.
        let payload = UpsertForecastAlertDTO(
            companyId: companyId,
            lastDipNotifiedAt: prior.lastDipNotifiedAt,
            lastDipMinBalance: prior.lastDipMinBalance,
            lastDipMinWeekStart: prior.lastDipMinWeekStart,
            lastClearedAt: SupabaseDate.format(Date()),
            dismissedUntilBalance: nil
        )
        _ = try? await ledger.upsert(payload)
    }
}
