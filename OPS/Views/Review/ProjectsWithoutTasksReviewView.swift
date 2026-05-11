//
//  ProjectsWithoutTasksReviewView.swift
//  OPS
//
//  Simple list view for the "projects in accepted/in-progress with zero tasks"
//  rail notification deep link. Tapping a row opens the project details so the
//  admin can add the missing tasks. Mirrors the OPS list-view pattern used by
//  ExpensesListView (header + scrollable card list + empty state).
//

import SwiftUI
import SwiftData

struct ProjectsWithoutTasksReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState

    @State private var projects: [Project] = []

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .trackScreen("ProjectsNeedingTasks")
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .onAppear {
            recomputeProjects()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: OPSStyle.Icons.chevronLeft)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)

            Spacer()

            Text("PROJECTS NEEDING TASKS")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            Spacer().frame(width: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2_5)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if projects.isEmpty {
            emptyState
        } else {
            countLabel
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing2)

            ScrollView {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(projects, id: \.id) { project in
                        Button(action: { openProject(project) }) {
                            row(project)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing4)
            }
        }
    }

    private var countLabel: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("\(projects.count) PROJECT\(projects.count == 1 ? "" : "S")")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("// no tasks attached")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Spacer()
        }
    }

    // MARK: - Row

    private func row(_ project: Project) -> some View {
        return HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Circle()
                .fill(project.status.color.opacity(0.25))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(project.status.color, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .overlay(
                    Image(systemName: "folder")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        .foregroundColor(project.status.color)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(project.title.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(project.status.displayName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(project.status.color)

                    Text("·")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Text(daysSinceLabel(project))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Spacer()

            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .contentShape(Rectangle())
    }

    // MARK: - Row helpers

    private func daysSinceLabel(_ project: Project) -> String {
        let recency = project.lastSyncedAt ?? project.startDate
        guard let recency = recency else { return "no date" }
        let days = max(0, Calendar.current.dateComponents([.day], from: recency, to: Date()).day ?? 0)
        if days < 1 { return "today" }
        if days == 1 { return "1 day ago" }
        if days < 30 { return "\(days) days ago" }
        let months = days / 30
        return "\(months)mo ago"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.successStatus.opacity(0.7))

            Text("ALL CAUGHT UP")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("Every active project has at least one task.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func recomputeProjects() {
        let all = dataController.getProjects()
        projects = ProjectsWithoutTasksDetector.projectsWithoutTasks(from: all)
    }

    private func openProject(_ project: Project) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            appState.viewProjectDetailsById(project.id)
        }
    }
}
