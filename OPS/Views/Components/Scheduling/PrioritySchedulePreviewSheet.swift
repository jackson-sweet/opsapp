import SwiftUI
import SwiftData

struct PrioritySchedulePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let plan: SchedulePlan
    @State var anchorDate: Date
    let onConfirm: () -> Void

    /// Task/project names resolved ONCE when the sheet appears — not re-fetched
    /// from SwiftData on every row, every render (the old `taskName(_:)` did).
    @State private var rows: [PreviewRow] = []

    private let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()

    private struct PreviewRow: Identifiable {
        let id: String
        let taskName: String
        let projectName: String
        let startDate: Date
        let endDate: Date
        let conflict: String?
    }

    private var crewConflictCount: Int {
        plan.conflicts.filter { $0.type == .noCrewAssigned }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if plan.placements.isEmpty {
                emptyState
            } else {
                summary

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing1 + 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                            row(r, idx: idx)
                        }
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                }
            }

            Divider().background(OPSStyle.Colors.cardBorder)
            footer
        }
        .background(OPSStyle.Colors.background)
        .onAppear(perform: buildRows)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("AUTO-SCHEDULE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            if !plan.placements.isEmpty {
                Text("\(plan.placements.count) tasks")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    // MARK: - Summary chips (gap days · nearby · crew warnings)

    @ViewBuilder private var summary: some View {
        if plan.metadata.totalGapDays > 0 || plan.metadata.proximityGroupsFound > 0 || crewConflictCount > 0 {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                if crewConflictCount > 0 {
                    Label("\(crewConflictCount) need crew", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
                if plan.metadata.totalGapDays > 0 {
                    Label("\(plan.metadata.totalGapDays) gap days", systemImage: "calendar.badge.clock")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                if plan.metadata.proximityGroupsFound > 0 {
                    Label("\(plan.metadata.proximityGroupsFound) nearby", systemImage: "mappin.and.ellipse")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ r: PreviewRow, idx: Int) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text("\(idx + 1)")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.taskName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                if !r.projectName.isEmpty {
                    Text(r.projectName)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }
                Text("\(df.string(from: r.startDate)) – \(df.string(from: r.endDate))")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                if let conflict = r.conflict {
                    Text(conflict)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
            }
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Empty state (defensive — buildPlan won't present an empty plan)

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Nothing to schedule")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Every ranked task already has dates.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Button { dismiss() } label: {
                Text(plan.placements.isEmpty ? "CLOSE" : "CANCEL")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)

            if !plan.placements.isEmpty {
                Button { onConfirm(); dismiss() } label: {
                    Text("SCHEDULE ALL")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
    }

    // MARK: - Data

    private func buildRows() {
        let conflictById = Dictionary(plan.conflicts.map { ($0.id, $0.message) }, uniquingKeysWith: { first, _ in first })
        guard let ctx = dataController.modelContext else {
            rows = plan.placements.map {
                PreviewRow(id: $0.id, taskName: "Task", projectName: "",
                           startDate: $0.startDate, endDate: $0.endDate, conflict: conflictById[$0.id])
            }
            return
        }
        let ids = plan.placements.map(\.id)
        let tasks = (try? ctx.fetch(FetchDescriptor<ProjectTask>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rows = plan.placements.map { p in
            let task = byId[p.id]
            return PreviewRow(
                id: p.id,
                taskName: task?.displayTitle ?? "Task",
                projectName: task?.project?.title ?? "",
                startDate: p.startDate,
                endDate: p.endDate,
                conflict: conflictById[p.id]
            )
        }
    }
}
