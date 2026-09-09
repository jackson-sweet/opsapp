//
//  AppointmentReviewRow.swift
//  OPS
//
//  The `phase_c_appointment_review` rail row, rewritten so it names the
//  customer and hands the operator the one thing that fixes it (bug 74bbb5b7).
//
//  The scan line carries WHO and WHAT is missing, because that is what the
//  founder could not see. The reason lives in the expanded detail. The single
//  action opens this lead's booking sheet — and appears only when the row
//  actually carries a lead id, so it can never be a button that goes nowhere.
//

import SwiftUI

struct AppointmentReviewRow: View {
    let notification: NotificationDTO
    /// Resolved from the local store. Nil yields the name-free sentence rather
    /// than a placeholder or a network round trip.
    let leadName: String?
    let timestamp: String
    let isExpanded: Bool
    /// False when the row carries no opportunity id — no lead, no booking sheet.
    let canSetTime: Bool
    let onToggle: () -> Void
    let onSetTime: () -> Void

    private var copy: AppointmentReviewPresentation.Copy {
        AppointmentReviewPresentation.copy(
            serverBody: notification.body,
            leadName: leadName
        )
    }

    var body: some View {
        let copy = self.copy
        return NotificationRowChrome(
            title: notification.title,
            bodyText: Text(copy.headline)
                .font(OPSStyle.Typography.smallBody)
                .foregroundStyle(
                    notification.isRead
                        ? OPSStyle.Colors.tertiaryText
                        : OPSStyle.Colors.secondaryText
                ),
            bodyAccessibilityLabel: copy.headline,
            timestamp: timestamp,
            isRead: notification.isRead,
            isExpanded: isExpanded,
            onToggle: onToggle,
            icon: {
                // Attention, not failure: nothing is broken, a time is missing.
                NotificationIconBadge(
                    systemName: "calendar.badge.exclamationmark",
                    tint: OPSStyle.Colors.warningStatus
                )
            },
            detail: {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    NotificationDetailDivider()

                    Text(copy.detail)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.top, OPSStyle.Layout.spacing2)

                    if canSetTime {
                        NotificationActionButton(
                            label: copy.actionLabel,
                            systemImage: "calendar.badge.plus",
                            action: onSetTime
                        )
                    }

                    Spacer().frame(height: OPSStyle.Layout.spacing2)
                }
            }
        )
    }
}
