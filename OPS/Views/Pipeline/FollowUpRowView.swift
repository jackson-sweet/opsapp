//
//  FollowUpRowView.swift
//  OPS
//
//  Single follow-up reminder row on opportunity detail.
//

import SwiftUI

struct FollowUpRowView: View {
    let followUp: FollowUp

    private var dueLabel: String {
        if followUp.isOverdue {
            let days = Calendar.current.dateComponents([.day], from: followUp.dueAt, to: Date()).day ?? 0
            return "[overdue \(days)d]"
        }
        if followUp.isDueToday { return "[today]" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: followUp.dueAt).day ?? 0
        if days == 1 { return "[tomorrow]" }
        return "[in \(days)d]"
    }

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: followUp.type.icon)
                .font(.system(size: 14))
                .foregroundColor(followUp.isOverdue ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.secondaryText)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(followUp.type.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                    Text(dueLabel)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(followUp.isOverdue ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.tertiaryText)
                }

                if let notes = followUp.notes, !notes.isEmpty {
                    Text(notes)
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }
}
