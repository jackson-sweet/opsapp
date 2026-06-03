import SwiftUI

struct PriorityQueueRow: View {
    let task: ProjectTask
    let rankNumber: Int?     // 1-based position in the ranked zone; nil = unranked

    private var dateText: String {
        guard let start = task.startDate else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        if let end = task.endDate, end != start { return "\(f.string(from: start)) – \(f.string(from: end))" }
        return f.string(from: start)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(rankNumber.map(String.init) ?? "—")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(rankNumber == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayTitle)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Text(task.project?.title ?? "—")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer()

            if task.getTeamMemberIds().isEmpty {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }

            if task.startDate != nil {
                Text(dateText)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

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
