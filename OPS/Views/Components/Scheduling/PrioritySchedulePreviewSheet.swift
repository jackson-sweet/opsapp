import SwiftUI
import SwiftData

struct PrioritySchedulePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let plan: SchedulePlan
    @State var anchorDate: Date
    let onConfirm: () -> Void

    private let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AUTO-SCHEDULE").font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text("\(plan.placements.count) tasks").font(OPSStyle.Typography.caption).foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, 16).padding(.top, 16)

            if plan.metadata.totalGapDays > 0 || plan.metadata.proximityGroupsFound > 0 {
                HStack(spacing: 12) {
                    if plan.metadata.totalGapDays > 0 {
                        Label("\(plan.metadata.totalGapDays) gap days", systemImage: "calendar.badge.clock")
                            .font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    if plan.metadata.proximityGroupsFound > 0 {
                        Label("\(plan.metadata.proximityGroupsFound) nearby", systemImage: "mappin.and.ellipse")
                            .font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(plan.placements.enumerated()), id: \.element.id) { idx, p in
                        row(p, idx: idx)
                    }
                }
                .padding(.vertical, 12)
            }

            Divider().background(OPSStyle.Colors.cardBorder)

            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("CANCEL").font(OPSStyle.Typography.button).foregroundColor(OPSStyle.Colors.primaryText).frame(maxWidth: .infinity)
                }
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.cardBackgroundDark).cornerRadius(OPSStyle.Layout.cardCornerRadius)
                Button { onConfirm(); dismiss() } label: {
                    Text("SCHEDULE ALL").font(OPSStyle.Typography.button).foregroundColor(.white).frame(maxWidth: .infinity)
                }
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.primaryAccent).cornerRadius(OPSStyle.Layout.cardCornerRadius)
            }
            .padding(16)
        }
        .background(OPSStyle.Colors.background)
    }

    @ViewBuilder
    private func row(_ p: TaskPlacement, idx: Int) -> some View {
        let conflict = plan.conflicts.first { $0.id == p.id }
        HStack(spacing: 12) {
            Text("\(idx + 1)").font(OPSStyle.Typography.captionBold).foregroundColor(OPSStyle.Colors.tertiaryText).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(taskName(p.id)).font(OPSStyle.Typography.body).foregroundColor(OPSStyle.Colors.primaryText)
                Text("\(df.string(from: p.startDate)) – \(df.string(from: p.endDate))")
                    .font(OPSStyle.Typography.caption).foregroundColor(OPSStyle.Colors.primaryAccent)
                if let conflict { Text(conflict.message).font(OPSStyle.Typography.smallCaption).foregroundColor(OPSStyle.Colors.warningStatus) }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(OPSStyle.Colors.cardBackgroundDark).cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .padding(.horizontal, 16)
    }

    private func taskName(_ id: String) -> String {
        guard let ctx = dataController.modelContext,
              let task = try? ctx.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate { $0.id == id })).first
        else { return "Task" }
        return task.displayTitle
    }
}
