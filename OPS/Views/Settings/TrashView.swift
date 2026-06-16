//
//  TrashView.swift
//  OPS
//
//  Admin-facing trash bin: lists soft-deleted projects, clients, and tasks
//  and offers a one-tap restore. SwiftData relationships don't auto-filter
//  tombstoned rows, so the underlying data is already retained locally —
//  this view just makes it discoverable again.
//

import SwiftUI
import SwiftData

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @Query private var allProjects: [Project]
    @Query private var allClients: [Client]
    @Query private var allTasks: [ProjectTask]

    @State private var segment: TrashSegment = .projects
    @State private var errorMessage: String?
    @State private var restoringId: String? = nil

    enum TrashSegment: String, CaseIterable, Hashable {
        case projects = "PROJECTS"
        case clients = "CLIENTS"
        case tasks = "TASKS"
    }

    private var deletedProjects: [Project] {
        allProjects
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private var deletedClients: [Client] {
        allClients
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private var deletedTasks: [ProjectTask] {
        allTasks
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private var totalCount: Int {
        deletedProjects.count + deletedClients.count + deletedTasks.count
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Trash",
                    onBackTapped: { dismiss() }
                )

                segmentedPicker
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing2_5)

                if totalCount == 0 {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing2_5) {
                            currentContent
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing5)
                    }
                }
            }
        }
        .trackScreen("Settings.Trash")
        .errorToast($errorMessage, label: Feedback.Err.restoreFailed)
    }

    // MARK: - Segmented Picker

    private var segmentedPicker: some View {
        HStack(spacing: 0) {
            ForEach(TrashSegment.allCases, id: \.self) { option in
                Button {
                    withAnimation(OPSStyle.Animation.fast) {
                        segment = option
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Text(option.rawValue)
                            .font(OPSStyle.Typography.captionBold)
                            .tracking(0.8)
                        let count = countFor(option)
                        if count > 0 {
                            Text("\(count)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(segment == option ? OPSStyle.Colors.background : OPSStyle.Colors.primaryAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(segment == option ? OPSStyle.Colors.background : OPSStyle.Colors.primaryAccent.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(segment == option ? OPSStyle.Colors.background : OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(segment == option ? OPSStyle.Colors.primaryAccent : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(OPSStyle.Layout.spacing1)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius + 4)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius + 4)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func countFor(_ segment: TrashSegment) -> Int {
        switch segment {
        case .projects: return deletedProjects.count
        case .clients: return deletedClients.count
        case .tasks: return deletedTasks.count
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var currentContent: some View {
        switch segment {
        case .projects:
            if deletedProjects.isEmpty {
                emptySegmentState(label: "No deleted projects")
            } else {
                ForEach(deletedProjects, id: \.id) { project in
                    trashRow(
                        id: project.id,
                        title: project.title,
                        subtitle: project.effectiveClientName,
                        deletedAt: project.deletedAt,
                        icon: OPSStyle.Icons.project,
                        restore: { await restoreProject(project) }
                    )
                }
            }
        case .clients:
            if deletedClients.isEmpty {
                emptySegmentState(label: "No deleted clients")
            } else {
                ForEach(deletedClients, id: \.id) { client in
                    trashRow(
                        id: client.id,
                        title: client.name,
                        subtitle: client.phoneNumber ?? client.email,
                        deletedAt: client.deletedAt,
                        icon: OPSStyle.Icons.client,
                        restore: { await restoreClient(client) }
                    )
                }
            }
        case .tasks:
            if deletedTasks.isEmpty {
                emptySegmentState(label: "No deleted tasks")
            } else {
                ForEach(deletedTasks, id: \.id) { task in
                    trashRow(
                        id: task.id,
                        title: task.displayTitle,
                        subtitle: task.project?.title,
                        deletedAt: task.deletedAt,
                        icon: OPSStyle.Icons.checkmarkSquareFill,
                        restore: { await restoreTask(task) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func trashRow(
        id: String,
        title: String,
        subtitle: String?,
        deletedAt: Date?,
        icon: String,
        restore: @escaping () async -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(title.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }
                if let deletedAt = deletedAt {
                    Text("DELETED \(Self.relativeFormatter.localizedString(for: deletedAt, relativeTo: Date()).uppercased())")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .tracking(0.5)
                }
            }

            Spacer()

            Button {
                Task { await restore() }
            } label: {
                HStack(spacing: 6) {
                    if restoringId == id {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    }
                    Text("RESTORE")
                        .font(OPSStyle.Typography.smallCaption)
                        .tracking(0.8)
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(restoringId != nil)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, 14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "trash")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("TRASH IS EMPTY")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text("Deleted projects, clients, and tasks appear here for recovery.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptySegmentState(label: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Restore Actions

    private func restoreProject(_ project: Project) async {
        await MainActor.run { restoringId = project.id }
        defer { Task { @MainActor in restoringId = nil } }
        do {
            try await dataController.restoreProject(project)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            await MainActor.run {
                errorMessage = "Could not restore project: \(error.localizedDescription)"
            }
        }
    }

    private func restoreClient(_ client: Client) async {
        await MainActor.run { restoringId = client.id }
        defer { Task { @MainActor in restoringId = nil } }
        do {
            try await dataController.restoreClient(client)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            await MainActor.run {
                errorMessage = "Could not restore client: \(error.localizedDescription)"
            }
        }
    }

    private func restoreTask(_ task: ProjectTask) async {
        await MainActor.run { restoringId = task.id }
        defer { Task { @MainActor in restoringId = nil } }
        do {
            try await dataController.restoreTask(task)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            await MainActor.run {
                errorMessage = "Could not restore task: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Formatters

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
