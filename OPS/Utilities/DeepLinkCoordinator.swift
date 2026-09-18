//
//  DeepLinkCoordinator.swift
//  OPS
//
//  In-memory coordinator for incoming deep-link navigation intent.
//
//  ## Problem
//
//  Deep links arrive via `AppDelegate.application(_:open:options:)` (ops://)
//  or `OPSApp.onOpenURL` / `onContinueUserActivity` (https://app.opsapp.co).
//  Both entry points fire IMMEDIATELY on URL arrival — potentially BEFORE
//  `MainTabView` has mounted, and while the app may be in a state where it
//  is unsafe to present the destination (PIN gate, subscription lockout,
//  blocking app message, fresh cold launch during `SplashLoadingView`).
//
//  A fire-and-forget `NotificationCenter.post` in those states is lost —
//  nothing listens, the link is dropped, the user sees the home tab.
//
//  ## Approach
//
//  Singleton `@MainActor` observable holding the current pending link in
//  memory as a `@Published` property. URL handlers call `receive(...)`,
//  which:
//    1. Stashes the link in `pendingLink` (surviving any state transition
//       that doesn't kill the process).
//    2. Posts the matching NotificationCenter event so any already-attached
//       handler fires immediately (hot path).
//
//  Readiness triggers (MainTabView.onAppear, PIN unlock) call `drain(...)`
//  which re-posts the notification if a link is still pending. Handlers
//  call `clear()` after a successful resolution or explicit denial.
//
//  Handlers that cannot safely present (PIN-gated) return without clearing
//  so the link persists until readiness is restored.
//
//  ## Why not UserDefaults?
//
//  An earlier draft persisted to UserDefaults. That added disk I/O, an
//  expiry mechanism, cross-user wipe responsibility, jailbreak visibility,
//  a stale-peek race, and a schema versioning burden — all to buy recovery
//  from the narrow case of "process killed between URL arrival and
//  MainTabView mount." iOS already re-delivers Universal Links on next
//  launch via scene activities, and the user can re-tap anyway. In-memory
//  is the right primitive.
//
//  ## Analytics
//
//  Emits the full deep-link funnel:
//    - `deep_link_received`   — URL arrived
//    - `deep_link_restored`   — drain fired (cold launch / PIN unlock / etc.)
//    - `deep_link_malformed`  — URL couldn't be parsed into a known entity
//    - `deep_link_resolved`   — handler successfully navigated (emitted by
//                                the entity handler, not here)
//    - `deep_link_denied`     — handler denied access (emitted by the
//                                entity handler, not here)
//
//  A UUID `deepLinkId` is threaded through `userInfo` so the full funnel
//  is correlatable end-to-end even when the same `(entity, id)` is tapped
//  repeatedly.
//

import Foundation
import SwiftUI
import UIKit

/// Pure payload routing for push notifications that should open the existing
/// notification rail. Keeping this decision separate from OneSignal and UIKit
/// makes the provider contract directly testable.
enum NotificationRailPushRoute {
    static let coordinatorEntity = "notifications"
    static let coordinatorId = "rail"

    private static let notificationScreen = "notifications"
    private static let quotaNotificationType = "ai_provider_quota"

    static func shouldOpen(screen: String?, type: String?) -> Bool {
        normalized(screen) == notificationScreen
            || normalized(type) == quotaNotificationType
    }

    /// APNs/OneSignal delivery callbacks describe arrival, not user intent.
    /// Notification-rail pushes navigate only from the explicit tap callback.
    static func shouldNavigateFromDelivery(screen: String?, type: String?) -> Bool {
        !shouldOpen(screen: screen, type: type)
    }

    /// Sheets render above the PIN overlay, so presentation must wait for both
    /// the signed-in session and the local PIN gate. The coordinator retains
    /// the pending intent and replays it after unlock.
    static func canPresent(
        sessionAuthenticated: Bool,
        requiresPIN: Bool,
        pinAuthenticated: Bool
    ) -> Bool {
        sessionAuthenticated && (!requiresPIN || pinAuthenticated)
    }

    private static func normalized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

/// Routing for the booked site-visit prompts (`type = site_visit_reminder`;
/// the moment is `deep_link_type` `site_visit_start` / `site_visit_heads_up`).
/// Pure so the push, rail and cold-launch paths share one tested decision.
///
/// CREW SITE VISITS P1: the push now carries `siteVisitId` beside `leadId`, so
/// an assignee without the Leads tab can land on the exact visit. The visit id
/// is the primary key when present; the lead id rides along.
enum SiteVisitPushRoute {
    enum Kind: Equatable {
        /// START — straight into capture.
        case start
        /// Heads-up / reminder — the lead, or Schedule on the visit's day for
        /// a user without the Leads tab.
        case headsUp
    }

    struct CoordinatorLink: Equatable {
        let entity: String
        let id: String
        let extraUserInfo: [String: String]
    }

    static let startRelayName = Notification.Name("StartSiteVisit")
    static let reminderRelayName = Notification.Name("OpenSiteVisitReminder")
    static let leadIdKey = "leadId"
    static let siteVisitIdKey = "siteVisitId"

    /// `deep_link_type` is authoritative; a bare `site_visit_reminder` type
    /// (no deep-link type) is treated as the heads-up — the non-committal
    /// landing.
    static func kind(deepLinkType: String?, type: String?) -> Kind? {
        switch normalized(deepLinkType) {
        case "site_visit_start": return .start
        case "site_visit_heads_up": return .headsUp
        default: break
        }
        switch normalized(type) {
        case "site_visit_start": return .start
        case "site_visit_heads_up", "site_visit_reminder": return .headsUp
        default: return nil
        }
    }

    /// The coordinator entity/id for a prompt tap. Nil when the payload names
    /// neither a visit nor a lead.
    static func coordinatorLink(kind: Kind, leadId: String?, siteVisitId: String?) -> CoordinatorLink? {
        let lead = nonEmpty(leadId)
        if let visit = nonEmpty(siteVisitId) {
            return CoordinatorLink(
                entity: kind == .start ? "site-visit-start-visit" : "site-visit-heads-up-visit",
                id: visit,
                extraUserInfo: lead.map { [leadIdKey: $0] } ?? [:]
            )
        }
        guard let lead else { return nil }
        return CoordinatorLink(
            entity: kind == .start ? "site-visit-start" : "site-visit-heads-up",
            id: lead,
            extraUserInfo: [:]
        )
    }

    /// The relay userInfo for a direct (non-coordinator) post.
    static func userInfo(leadId: String?, siteVisitId: String?) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [:]
        if let lead = nonEmpty(leadId) { info[leadIdKey] = lead }
        if let visit = nonEmpty(siteVisitId) { info[siteVisitIdKey] = visit }
        return info
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

@MainActor
final class DeepLinkCoordinator: ObservableObject {

    // MARK: - Singleton

    static let shared = DeepLinkCoordinator()

    private let notificationCenter: NotificationCenter

    private convenience init() {
        self.init(notificationCenter: .default)
    }

    init(notificationCenter: NotificationCenter) {
        self.notificationCenter = notificationCenter
    }

    // MARK: - Model

    struct PendingLink: Equatable {
        /// Entity namespace — projects, clients, tasks, invoices, estimates,
        /// leads, or the notification rail.
        let entity: String

        /// Entity-specific ID (Bubble unique identifier).
        let id: String

        /// Correlation UUID threaded through every analytics event so the
        /// received → restored → resolved/denied funnel is joinable.
        let deepLinkId: UUID

        /// Wallclock of URL arrival (for `age_seconds` telemetry on drain).
        let receivedAt: Date

        /// URL scheme observed at the handler — `https` for Universal Links,
        /// `ops` for the custom scheme. Useful for measuring which channel
        /// drives traffic.
        let scheme: String

        /// Whether the app was already running in foreground when the URL
        /// arrived. Discriminates hot-path (was_running=true, observers
        /// attached) from cold-launch (was_running=false, observers likely
        /// not attached yet).
        let wasRunning: Bool

        /// An optional address for an originating creation parent. Its endpoint
        /// is weak; retaining navigation intent never retains an unfinished form.
        let projectCreationPresentationTarget: ProjectCreationPresentationTarget?

        /// Secondary ids posted alongside the primary one (e.g. a site-visit
        /// prompt's `leadId` beside its `siteVisitId`). Never overrides the
        /// primary key or the correlation id.
        let extraUserInfo: [String: String]
    }

    // MARK: - Published State

    @Published private(set) var pendingLink: PendingLink?

    // MARK: - Notification Keys

    /// Threaded through `userInfo` on every posted notification so handlers
    /// can attach the correlation ID to their resolved/denied events.
    static let deepLinkIdUserInfoKey = "deepLinkId"

    // MARK: - Public API

    /// Called by the URL handlers when a deep link arrives. Stashes the
    /// link and immediately posts the NotificationCenter event for any
    /// observer that's already attached (hot path).
    ///
    /// Malformed URLs (unknown entity, empty ID) emit `deep_link_malformed`
    /// and are NOT stashed — they would never resolve.
    func receive(
        entity: String,
        id: String,
        scheme: String,
        projectCreationPresentationTarget: ProjectCreationPresentationTarget? = nil,
        extraUserInfo: [String: String] = [:]
    ) {
        // Validate
        guard isKnownEntity(entity) else {
            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "deep_link_malformed",
                properties: [
                    "entity": entity,
                    "id": id,
                    "scheme": scheme,
                    "reason": "unknown_entity"
                ]
            )
            print("[DEEP_LINK_COORDINATOR] Malformed — unknown entity '\(entity)'")
            return
        }
        guard !id.isEmpty else {
            AnalyticsService.shared.track(
                eventType: .action,
                eventName: "deep_link_malformed",
                properties: [
                    "entity": entity,
                    "scheme": scheme,
                    "reason": "empty_id"
                ]
            )
            print("[DEEP_LINK_COORDINATOR] Malformed — empty id for \(entity)")
            return
        }

        let link = PendingLink(
            entity: entity,
            id: id,
            deepLinkId: UUID(),
            receivedAt: Date(),
            scheme: scheme,
            wasRunning: UIApplication.shared.applicationState != .inactive,
            projectCreationPresentationTarget: entity == "projects" ? projectCreationPresentationTarget : nil,
            extraUserInfo: extraUserInfo
        )

        pendingLink = link

        AnalyticsService.shared.track(
            eventType: .action,
            eventName: "deep_link_received",
            properties: [
                "entity": link.entity,
                "id": link.id,
                "scheme": link.scheme,
                "was_running": link.wasRunning,
                Self.deepLinkIdUserInfoKey: link.deepLinkId.uuidString
            ]
        )

        print("[DEEP_LINK_COORDINATOR] Received \(entity)/\(id) (scheme=\(scheme), running=\(link.wasRunning))")

        postNotification(for: link)
    }

    /// Called by readiness triggers (MainTabView.onAppear, PIN unlock,
    /// subscription lockout clear). Re-posts the pending link so the
    /// just-attached or just-unblocked handler can pick it up.
    ///
    /// `context` is recorded as `resume_context` on the `deep_link_restored`
    /// event so we can measure which readiness gate drove the most drops.
    func drain(context: String) {
        guard let link = pendingLink else { return }

        let age = Int(Date().timeIntervalSince(link.receivedAt))

        AnalyticsService.shared.track(
            eventType: .action,
            eventName: "deep_link_restored",
            properties: [
                "entity": link.entity,
                "id": link.id,
                "scheme": link.scheme,
                "age_seconds": age,
                "resume_context": context,
                Self.deepLinkIdUserInfoKey: link.deepLinkId.uuidString
            ]
        )

        print("[DEEP_LINK_COORDINATOR] Draining \(link.entity)/\(link.id) (age=\(age)s, context=\(context))")

        postNotification(for: link)
    }

    /// Called by entity handlers after a successful resolution (navigation
    /// happened) OR after an explicit denial (AccessDeniedSheet was shown).
    /// Either way, the link has been "handled" from the user's perspective.
    ///
    /// Handlers that defer resolution (e.g., PIN-gated) MUST NOT call this —
    /// the link stays pending until readiness is restored.
    func clear() {
        if pendingLink != nil {
            print("[DEEP_LINK_COORDINATOR] Cleared pending link")
        }
        pendingLink = nil
    }

    // MARK: - Routing

    /// Post the NotificationCenter event for a link. The `deepLinkId`
    /// correlation UUID is always included in userInfo so downstream
    /// handlers can attach it to their resolved/denied events.
    private func postNotification(for link: PendingLink) {
        let (name, entityIdKey) = notificationMapping(for: link.entity)
        guard let name = name, let entityIdKey = entityIdKey else {
            // Should be unreachable — validated in receive().
            return
        }
        var info: [AnyHashable: Any] = [:]
        for (key, value) in link.extraUserInfo {
            info[key] = value
        }
        info[entityIdKey] = link.id
        info[Self.deepLinkIdUserInfoKey] = link.deepLinkId.uuidString
        if let target = link.projectCreationPresentationTarget {
            info[ProjectCreationPresentationTarget.userInfoKey] = target
        }
        notificationCenter.post(name: name, object: nil, userInfo: info)
    }

    /// Mapping from entity name to the notification name and the key under
    /// which the entity ID appears in userInfo. Must stay in sync with the
    /// observer declarations in `MainTabView.swift:59-80`.
    private func notificationMapping(for entity: String) -> (Notification.Name?, String?) {
        switch entity {
        case "projects":
            return (Notification.Name("OpenProjectDetails"), "projectId")
        case "clients":
            return (Notification.Name("OpenClientDetails"), "clientId")
        case "invoices":
            return (Notification.Name("OpenInvoiceDetails"), "invoiceId")
        case "estimates":
            return (Notification.Name("OpenEstimateDetails"), "estimateId")
        case "leads", "opportunities":
            // Both entity spellings resolve to the same LEADS-tab detail; the
            // OpenLeadDetails observer in MainTabView reads `leadId`.
            return (Notification.Name("OpenLeadDetails"), "leadId")
        case "site-visit-start":
            // START-visit push tapped on a cold launch: the StartSiteVisit relay
            // has no listener until MainTabView mounts, so the intent rides the
            // same stash/drain as leads (MainTabView clears it on receipt).
            return (SiteVisitPushRoute.startRelayName, SiteVisitPushRoute.leadIdKey)
        case "site-visit-start-visit":
            // Same START intent keyed by the exact visit (the push carries
            // siteVisitId); the lead id rides in extraUserInfo.
            return (SiteVisitPushRoute.startRelayName, SiteVisitPushRoute.siteVisitIdKey)
        case "site-visit-heads-up":
            // Heads-up / reminder: the lead with the Leads tab, else Schedule
            // on the visit's day (MainTabView decides).
            return (SiteVisitPushRoute.reminderRelayName, SiteVisitPushRoute.leadIdKey)
        case "site-visit-heads-up-visit":
            return (SiteVisitPushRoute.reminderRelayName, SiteVisitPushRoute.siteVisitIdKey)
        case "tasks":
            return (Notification.Name("OpenTaskDetails"), "taskId")
        case "notifications":
            return (Notification.Name("OpenNotifications"), "notificationRail")
        default:
            return (nil, nil)
        }
    }

    private func isKnownEntity(_ entity: String) -> Bool {
        notificationMapping(for: entity).0 != nil
    }
}
