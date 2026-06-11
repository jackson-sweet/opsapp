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

enum DeepLinkRouteRegistry {
    static func notificationMapping(for entity: String) -> (name: Notification.Name, entityIdKey: String)? {
        switch entity {
        case "projects":
            return (Notification.Name("OpenProjectDetails"), "projectId")
        case "clients":
            return (Notification.Name("OpenClientDetails"), "clientId")
        case "invoices":
            return (Notification.Name("OpenInvoiceDetails"), "invoiceId")
        case "estimates":
            return (Notification.Name("OpenEstimateDetails"), "estimateId")
        case "tasks":
            return (Notification.Name("OpenTaskDetails"), "taskId")
        case "leads", "opportunities":
            return (Notification.Name("OpenLeadDetails"), "leadId")
        default:
            return nil
        }
    }

    static func isKnownEntity(_ entity: String) -> Bool {
        notificationMapping(for: entity) != nil
    }
}

@MainActor
final class DeepLinkCoordinator: ObservableObject {

    // MARK: - Singleton

    static let shared = DeepLinkCoordinator()

    private init() {}

    // MARK: - Model

    struct PendingLink: Equatable {
        /// Entity namespace — "projects", "clients", "tasks", "invoices", "estimates", "leads".
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
    func receive(entity: String, id: String, scheme: String) {
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
            wasRunning: UIApplication.shared.applicationState != .inactive
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
        guard let route = DeepLinkRouteRegistry.notificationMapping(for: link.entity) else {
            // Should be unreachable — validated in receive().
            return
        }
        NotificationCenter.default.post(
            name: route.name,
            object: nil,
            userInfo: [
                route.entityIdKey: link.id,
                Self.deepLinkIdUserInfoKey: link.deepLinkId.uuidString
            ]
        )
    }

    private func isKnownEntity(_ entity: String) -> Bool {
        DeepLinkRouteRegistry.isKnownEntity(entity)
    }
}
