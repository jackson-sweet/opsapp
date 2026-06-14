//
//  CrewTooltipCard.swift
//  OPS
//
//  Frosted tooltip card shown when a crew dot is tapped on the map.
//  Displays crew member name, current task/project, staleness, and action buttons.
//

import SwiftUI

struct CrewTooltipCard: View {

    let update: CrewLocationUpdate
    let onProjectTap: (String) -> Void   // projectId
    let onCall: () -> Void
    let onMessage: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Crew name ──
            Text(fullName.uppercased())
                .font(OPSStyle.Typography.caption)
                .tracking(0.5)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            // ── Current task / project ──
            if let projectId = update.currentProjectId,
               let taskName = update.currentTaskName, !taskName.isEmpty {
                // Tappable project row
                Button {
                    onProjectTap(projectId)
                } label: {
                    HStack(spacing: 0) {
                        Text(taskName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44) // Touch target
                .padding(.top, 2)

                // Project address sub-line
                if let address = update.currentProjectAddress, !address.isEmpty {
                    Text("at \(address)")
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }
            } else {
                // No assignment
                Text("No tasks assigned")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }

            // ── Staleness ──
            Text(timeAgo(from: update.timestamp))
                .font(OPSStyle.Typography.smallBody)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, OPSStyle.Layout.spacing1)

            // ── Divider ──
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)

            // ── Action buttons ──
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                // CALL button
                Button(action: onCall) {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13))
                        Text("CALL")
                            .font(OPSStyle.Typography.caption)
                            .tracking(0.5)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // MESSAGE button
                Button(action: onMessage) {
                    HStack(spacing: 6) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 13))
                        Text("MESSAGE")
                            .font(OPSStyle.Typography.caption)
                            .tracking(0.5)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, 14)
        .frame(maxWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private var fullName: String {
        let first = update.firstName
        let last = update.lastName ?? ""
        if last.isEmpty {
            return first
        }
        return "\(first) \(last)"
    }

    /// Returns a human-readable staleness string, e.g. "Updated 2 min ago".
    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))

        if seconds < 60 {
            return "Updated just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "Updated \(minutes) min ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "Updated \(hours) hr ago"
        } else {
            let days = seconds / 86400
            return "Updated \(days)d ago"
        }
    }
}
