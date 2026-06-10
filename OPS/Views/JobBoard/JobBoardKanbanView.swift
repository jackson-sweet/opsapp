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
    var activeOnly: Bool = false
    var assignedToMe: Bool = false
    var selectedStatuses: Set<Status> = []
    var selectedTeamMemberIds: Set<String> = []

    /// Active statuses only (no Closed, Archived)
    private let displayStatuses: [Status] = [
        .rfq, .estimated, .accepted, .inProgress, .completed
    ]

    /// Status bars to render. Honors the ACTIVE ONLY toggle (drops any
    /// non-active status) and the filter sheet's status selection, so the
    /// board's bars track the action-row filters instead of always showing
    /// the full set.
    private var visibleStatuses: [Status] {
        displayStatuses.filter { status in
            if activeOnly && !status.isActive { return false }
            if !selectedStatuses.isEmpty && !selectedStatuses.contains(status) { return false }
            return true
        }
    }

    /// Projects excluding Closed, Archived, and soft-deleted — run through the
    /// same active / assigned-to-me / status / team filters the action row and
    /// filter sheet expose, via the shared JobBoardProjectFiltering helper so
    /// the board matches the project list's filtering rules exactly.
    private var activeProjects: [Project] {
        JobBoardProjectFiltering.kanbanProjects(
            from: allProjects,
            activeOnly: activeOnly,
            assignedToMe: assignedToMe,
            currentUserId: dataController.currentUser?.id,
            selectedStatuses: selectedStatuses,
            selectedTeamMemberIds: selectedTeamMemberIds
        )
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
            // Bug 9a9c211a — spacing2 (8pt) between status bars read as
            // visually flush against the dark background in the screenshot.
            // Bump to spacing3 (16pt) so each status bar reads as its own
            // standalone card.
            VStack(spacing: OPSStyle.Layout.spacing3) {
                ForEach(visibleStatuses, id: \.self) { status in
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
            // Bug d335d3ae — bumped from 120pt → 160pt so the last status bar
            // (or the trailing project card inside an expanded bar) clears
            // the floating tab bar with visible breathing room. The standard
            // tabBarPadding helper uses 90pt; the additional 70pt gives the
            // kanban a generous bottom gutter matching the inter-bar rhythm.
            .padding(.bottom, 160)
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
        // Bug 9a9c211a — bumped inter-card spacing from spacing2 (8pt) to
        // spacing3 (16pt) so the project cards inside an expanded status bar
        // read as discrete cards instead of a flush stack.
        VStack(spacing: OPSStyle.Layout.spacing3) {
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
        .padding(.vertical, OPSStyle.Layout.spacing3)
        .padding(.horizontal, OPSStyle.Layout.spacing2)
    }
}
