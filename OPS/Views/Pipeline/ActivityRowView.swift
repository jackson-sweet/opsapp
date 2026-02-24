//
//  ActivityRowView.swift
//  OPS
//
//  Single activity row in the opportunity timeline.
//

import SwiftUI

struct ActivityRowView: View {
    let activity: Activity

    private var isSystemGenerated: Bool {
        activity.type.isSystemGenerated
    }

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(activity.createdAt)
        let minutes = Int(interval / 60)
        if minutes < 60 { return "[\(max(minutes, 1))m ago]" }
        let hours = minutes / 60
        if hours < 24 { return "[\(hours)hr ago]" }
        let days = hours / 24
        if days == 1 { return "[yesterday]" }
        return "[\(days) days ago]"
    }

    var body: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: activity.type.icon)
                .font(.system(size: 14))
                .foregroundColor(isSystemGenerated ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(activity.type.rawValue.uppercased().replacingOccurrences(of: "_", with: " "))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(isSystemGenerated ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text(timeAgo)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                if let body = activity.body, !body.isEmpty {
                    Text(body)
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(isSystemGenerated ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }
}
