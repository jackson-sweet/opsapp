//
//  SpotlightTapRouter.swift
//  OPS
//
//  Handles CSSearchableItemActivityIdentifier continuation from Spotlight taps.
//  Decodes the item ID, re-checks permissions, and posts the matching deep-link
//  notification (or an access-denied notification).
//

import Foundation
import CoreSpotlight

@MainActor
enum SpotlightTapRouter {

    /// Handle an NSUserActivity continuation. Returns true if handled.
    static func handle(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == CSSearchableItemActionType,
              let itemId = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let decoded = SpotlightItemId.decode(itemId) else {
            return false
        }

        let perms = PermissionStore.shared

        switch decoded.domain {
        case SpotlightDomain.project:
            guard perms.can("projects.view") else {
                showAccessDenied("You don't have permission to view projects.")
                return true
            }
            NotificationCenter.default.post(
                name: Notification.Name("OpenProjectDetails"),
                object: nil,
                userInfo: ["projectId": decoded.id]
            )
            return true

        case SpotlightDomain.client:
            guard perms.can("clients.view") else {
                showAccessDenied("You don't have permission to view clients.")
                return true
            }
            NotificationCenter.default.post(
                name: Notification.Name("OpenClientDetails"),
                object: nil,
                userInfo: ["clientId": decoded.id]
            )
            return true

        case SpotlightDomain.subClient:
            // Bug G4 — sub-clients live inside a parent client's detail screen;
            // a tapped sub-client resolves to the parent client so the user
            // lands on the contact profile containing the tapped contact row.
            // Same permission gate as client (clients.view); routing itself
            // is handled by MainTabView's OpenSubClientDetails observer.
            guard perms.can("clients.view") else {
                showAccessDenied("You don't have permission to view clients.")
                return true
            }
            NotificationCenter.default.post(
                name: Notification.Name("OpenSubClientDetails"),
                object: nil,
                userInfo: ["subClientId": decoded.id]
            )
            return true

        case SpotlightDomain.task:
            guard perms.can("projects.view") else {
                showAccessDenied("You don't have permission to view tasks.")
                return true
            }
            NotificationCenter.default.post(
                name: Notification.Name("OpenTaskDetails"),
                object: nil,
                userInfo: ["taskId": decoded.id]
            )
            return true

        case SpotlightDomain.invoice:
            guard perms.can("pipeline.view") else {
                showAccessDenied("You don't have permission to view invoices.")
                return true
            }
            NotificationCenter.default.post(
                name: Notification.Name("OpenInvoiceDetails"),
                object: nil,
                userInfo: ["invoiceId": decoded.id]
            )
            return true

        case SpotlightDomain.estimate:
            guard perms.can("pipeline.view") || perms.can("estimates.view") else {
                showAccessDenied("You don't have permission to view estimates.")
                return true
            }
            NotificationCenter.default.post(
                name: Notification.Name("OpenEstimateDetails"),
                object: nil,
                userInfo: ["estimateId": decoded.id]
            )
            return true

        default:
            return false
        }
    }

    private static func showAccessDenied(_ message: String) {
        NotificationCenter.default.post(
            name: Notification.Name("ShowAccessDenied"),
            object: nil,
            userInfo: ["message": message]
        )
    }
}
