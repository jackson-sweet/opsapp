//
//  LeadsToastSubscriber.swift
//  OPS
//
//  Bridges the 8 LEADS-sheet `*Success` notifications onto the global
//  `ToastCenter`. Mount once at the app root (MainTabView) so toasts
//  survive tab swaps — the operator who taps SAVE LEAD and immediately
//  switches to PROJECTS still gets the confirmation.
//
//  Maintained alongside the notification posters in:
//    OPS/Views/Leads/Sheets/AddLeadSheet.swift         (LeadCreatedSuccess)
//    OPS/Views/Leads/Sheets/EditLeadSheet.swift        (LeadUpdatedSuccess, ArchivedSuccess, DeletedSuccess)
//    OPS/Views/Leads/Sheets/LeadLogActivitySheet.swift (LeadActivityLoggedSuccess)
//    OPS/Views/Leads/Sheets/LostReasonSheet.swift      (LeadMarkedLostSuccess)
//    OPS/Views/Leads/Sheets/ConvertToProjectSheet.swift (LeadMarkedWonSuccess, LeadConvertedSuccess)
//

import SwiftUI

struct LeadsToastSubscriber: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("LeadCreatedSuccess"))
            ) { _ in
                ToastCenter.shared.present(
                    Toast(label: "// LEAD CREATED", tone: .success)
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("LeadUpdatedSuccess"))
            ) { _ in
                ToastCenter.shared.present(
                    Toast(label: "// LEAD UPDATED", tone: .success)
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("LeadActivityLoggedSuccess"))
            ) { _ in
                ToastCenter.shared.present(
                    Toast(label: "// ACTIVITY LOGGED", tone: .success)
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("LeadMarkedLostSuccess"))
            ) { _ in
                // Loss is acknowledged in tan (attention), not rose (error).
                // Per design-intent §11: "no drama, just acknowledgment."
                ToastCenter.shared.present(
                    Toast(label: "// LEAD LOST", tone: .warning)
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("LeadMarkedWonSuccess"))
            ) { _ in
                ToastCenter.shared.present(
                    Toast(label: "// LEAD WON · NO PROJECT", tone: .success)
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("LeadConvertedSuccess"))
            ) { _ in
                // userInfo carries `projectId` (UUID), but the Project model
                // has no short / job-number identifier suitable for the label.
                // The wider form is `// LEAD WON · PROJECT P-XXXX CREATED`;
                // we use the schema-truthful version until a job-number lands.
                ToastCenter.shared.present(
                    Toast(label: "// LEAD WON · PROJECT CREATED", tone: .success)
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("LeadArchivedSuccess"))
            ) { _ in
                ToastCenter.shared.present(
                    Toast(label: "// LEAD ARCHIVED", tone: .warning)
                )
            }
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("LeadDeletedSuccess"))
            ) { _ in
                ToastCenter.shared.present(
                    Toast(label: "// LEAD DELETED", tone: .error)
                )
            }
    }
}

extension View {
    /// Listens to LEADS sheet `*Success` notifications and presents toasts
    /// via `ToastCenter.shared`. Pair with `.toastHost()` on the same root.
    func leadsToastSubscriber() -> some View {
        modifier(LeadsToastSubscriber())
    }
}
