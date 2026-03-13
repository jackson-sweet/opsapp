//
//  JobBoardKanbanView.swift
//  OPS
//
//  Status board overview: proportional fill bars showing project distribution by status.
//  Tap a bar to expand it and reveal compact project cards inline.
//

import SwiftUI
import SwiftData

struct JobBoardKanbanView: View {
    @EnvironmentObject private var dataController: DataController
    @Query private var allProjects: [Project]
    @State private var expandedStatus: Status? = nil

    /// Active statuses only (no Closed, Archived)
    private let displayStatuses: [Status] = [
        .rfq, .estimated, .accepted, .inProgress, .completed
    ]

    /// Projects excluding Closed and Archived
    private var activeProjects: [Project] {
        allProjects.filter { $0.status != .closed && $0.status != .archived }
    }

    private var totalCount: Int { max(activeProjects.count, 1) }

    private func projects(for status: Status) -> [Project] {
        activeProjects.filter { $0.status == status }
    }

    private func fillFraction(for status: Status) -> CGFloat {
        let count = projects(for: status).count
        return CGFloat(count) / CGFloat(totalCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(displayStatuses, id: \.self) { status in
                    KanbanStatusBar(
                        status: status,
                        count: projects(for: status).count,
                        fillFraction: fillFraction(for: status),
                        isExpanded: expandedStatus == status,
                        projects: projects(for: status),
                        onTap: {
                            withAnimation(.accessibleEaseInOut(duration: 0.25)) {
                                expandedStatus = expandedStatus == status ? nil : status
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
            .padding(.bottom, 120)
        }
        .trackScreen("JobBoard.Kanban")
    }
}

// MARK: - Kanban Status Bar

private struct KanbanStatusBar: View {
    let status: Status
    let count: Int
    let fillFraction: CGFloat
    let isExpanded: Bool
    let projects: [Project]
    let onTap: () -> Void

    @EnvironmentObject private var dataController: DataController

    private let barHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            // Bar row — styled like a large status badge
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Proportional fill — mild opacity vs no fill
                    Rectangle()
                        .fill(status.color.opacity(0.15))
                        .frame(width: geo.size.width * fillFraction)
                        .animation(.accessibleEaseInOut(), value: fillFraction)

                    // Label + count
                    HStack {
                        Text(status.displayName.uppercased())
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(status.color)
                            .padding(.leading, OPSStyle.Layout.spacing3)

                        Spacer()

                        Text("\(count)")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(status.color)
                            .padding(.trailing, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .frame(height: barHeight)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            // Expanded project cards — inside the same border
            if isExpanded {
                Divider()
                    .background(status.color.opacity(0.2))

                expandedContent
                    .transition(.opacity)
            }
        }
        .background(status.color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(status.color, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var expandedContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            if projects.isEmpty {
                Text("No projects")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                ForEach(projects) { project in
                    UniversalJobBoardCard(cardType: .project(project), compact: true)
                        .environmentObject(dataController)
                }
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing2)
    }
}
