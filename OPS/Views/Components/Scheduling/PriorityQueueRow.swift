import SwiftUI

struct PriorityQueueRow: View {
    /// Non-reflowing waterline preview state. While the handle is dragged the rows
    /// stay in committed order; instead of moving, a row that will flip sides gets
    /// an accent (→ ranked) or dim (→ unranked) treatment so the waterline reads as
    /// moving between rows without any layout change.
    enum Pending { case none, willRank, willUnrank }

    let project: Project
    let rankNumber: Int?     // 1-based rank; nil = unranked
    var pending: Pending = .none
    var isWaterline: Bool = false   // boundary row → accent waterline on its top edge

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
        ZStack(alignment: .top) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .overlay {
                if pending == .willRank {
                    Rectangle().fill(OPSStyle.Colors.primaryAccent.opacity(0.12))
                }
            }
            .overlay(alignment: .leading) {
                if pending == .willRank {
                    Rectangle().fill(OPSStyle.Colors.primaryAccent).frame(width: 3)
                }
            }
            .opacity(pending == .willUnrank ? 0.45 : 1)

            // The waterline rides ABOVE the dim so it stays crisp on the boundary row.
            if isWaterline {
                Rectangle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(height: 2)
            }
        }
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    }
}
