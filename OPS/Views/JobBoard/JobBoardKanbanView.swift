//
//  JobBoardKanbanView.swift
//  OPS
//
//  Kanban overview: proportional fill bars showing project distribution by status.
//  Tap a bar to expand it and reveal project cards inline.
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
            VStack(spacing: 1) {
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
            .padding(.bottom, 120)
        }
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

    private let collapsedHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            // Bar row
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBackgroundDark)

                    // Proportional fill — full width at low opacity when expanded
                    Rectangle()
                        .fill(status.color.opacity(isExpanded ? 0.15 : 1.0))
                        .frame(width: isExpanded
                               ? geo.size.width
                               : geo.size.width * fillFraction)
                        .animation(.accessibleEaseInOut(), value: isExpanded)
                        .animation(.accessibleEaseInOut(), value: fillFraction)

                    // Label + count overlay
                    HStack {
                        Text(status.displayName.uppercased())
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(labelColor)
                            .padding(.leading, 16)

                        Spacer()

                        Text("\(count)")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(labelColor)
                            .padding(.trailing, 16)
                    }
                }
            }
            .frame(height: collapsedHeight)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            // Divider
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1)

            // Expanded project cards
            if isExpanded {
                expandedContent
                    .transition(.opacity)
            }
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 8) {
            if projects.isEmpty {
                Text("No projects")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            } else {
                ForEach(projects) { project in
                    UniversalJobBoardCard(cardType: .project(project))
                        .environmentObject(dataController)
                        .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 12)
        .background(status.color.opacity(0.08))
    }

    /// Label color that reads against fill
    private var labelColor: Color {
        // When expanded, fill is very low opacity — use primaryText
        // When collapsed with wide fill, use dark text for contrast
        if isExpanded { return OPSStyle.Colors.primaryText }
        return fillFraction > 0.6 ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.primaryText
    }
}
