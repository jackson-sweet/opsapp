import SwiftUI

struct PriorityQueueRow: View {
    let project: Project
    let rankNumber: Int?     // 1-based rank; nil = unranked

    private var subtitle: String {
        let client = project.effectiveClientName
        let addr = project.address ?? ""
        if addr.isEmpty { return client }
        if client.isEmpty { return addr }
        return "\(client) · \(addr)"
    }

    /// Completed / total active tasks (cancelled + deleted excluded).
    private var taskFraction: String {
        let active = project.tasks.filter { $0.deletedAt == nil && $0.status != .cancelled }
        let done = active.filter { $0.status == .completed }.count
        return "\(done)/\(active.count)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(rankNumber.map(String.init) ?? "—")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(rankNumber == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer()

            // OPSStyle.Typography.dataValue = JetBrains Mono 13pt — correct token for numeric data
            Text(taskFraction)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    }
}
