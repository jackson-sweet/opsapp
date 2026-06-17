//
//  QuickAddSuggestionsRail.swift
//  OPS
//
//  Horizontal chip rail inside the TASKS section on Project Details. Surfaces
//  up to 3 of the company's most-repeated (taskType + crew) combinations as
//  one-tap "create task" chips. Long-press opens the full TaskFormSheet with
//  the suggestion preselected. Long-press → Dismiss suppresses the suggestion
//  for this project only.
//
//  Spec: docs/superpowers/specs/2026-05-10-quick-add-task-chips-design.md
//  Bug:  e3996ac3-4180-4bdf-9423-f1d3b0c7b6de
//

import SwiftUI
import SwiftData

struct QuickAddSuggestionsRail: View {
    let project: Project
    let canEdit: Bool

    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tutorialMode) private var tutorialMode
    @Query private var allTaskTypes: [TaskType]
    @Query private var allUsers: [User]

    /// Bump this to force a recompute after a dismissal — SwiftData task
    /// changes already trigger re-render via the parent's @Query on tasks,
    /// but dismissals don't touch SwiftData.
    @State private var dismissBump: Int = 0

    /// Drives the long-press → prefilled TaskFormSheet path.
    @State private var prefilledSuggestion: TaskSuggestion?

    private var taskTypeById: [String: TaskType] {
        Dictionary(uniqueKeysWithValues: allTaskTypes.map { ($0.id, $0) })
    }

    private var userById: [String: User] {
        Dictionary(uniqueKeysWithValues: allUsers.map { ($0.id, $0) })
    }

    /// Lowercased ids of the company's current, non-removed, active members —
    /// the canonical "team members" set (mirrors DataController.getTeamMembers:
    /// companyId match, deletedAt == nil, isActive != false). Lowercased to
    /// match the ids stored in ProjectTask.teamMemberIdsString.
    private var activeMemberIds: Set<String> {
        Set(
            allUsers
                .filter {
                    $0.companyId == project.companyId &&
                    $0.deletedAt == nil &&
                    $0.isActive != false
                }
                .map { $0.id.lowercased() }
        )
    }

    /// True when this user is a current, non-removed, active member of the
    /// project's company — the gate for whether their avatar/id may be shown
    /// or committed. Catches members deactivated AFTER the engine ran.
    private func isActiveMember(_ user: User) -> Bool {
        user.companyId == project.companyId &&
        user.deletedAt == nil &&
        user.isActive != false
    }

    private var suggestions: [TaskSuggestion] {
        guard canEdit, !tutorialMode else { return [] }
        _ = dismissBump  // tie state to recompute on dismissal

        let computed = TaskSuggestionEngine.suggestions(
            context: modelContext,
            companyId: project.companyId,
            activeMemberIds: activeMemberIds,
            for: project
        )

        // Drop any whose task type the user no longer has access to — the
        // chip needs the display name and color from the TaskType row.
        return computed.filter { taskTypeById[$0.taskTypeId] != nil }
    }

    /// Resolve a suggestion's crew to displayable Users, dropping any id whose
    /// User is missing OR no longer an active member of the company. The engine
    /// already emits only active ids, but a member can be deactivated between
    /// the engine running and this render — this is the last guard.
    private func activeMembers(for suggestion: TaskSuggestion) -> [User] {
        suggestion.teamMemberIds.compactMap { id in
            guard let user = userById[id], isActiveMember(user) else { return nil }
            return user
        }
    }

    var body: some View {
        let items = suggestions
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("QUICK ADD")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing2_5)
                    .padding(.bottom, OPSStyle.Layout.spacing2)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(items) { suggestion in
                            chip(for: suggestion)
                                .transition(
                                    .scale(scale: 0.85).combined(with: .opacity)
                                )
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing2_5)
                }
            }
            .sheet(item: $prefilledSuggestion) { suggestion in
                TaskFormSheet(
                    mode: .create,
                    preselectedProjectId: project.id,
                    prefilledTaskTypeId: suggestion.taskTypeId,
                    prefilledTeamMemberIds: activeMembers(for: suggestion).map { $0.id.lowercased() },
                    onSave: { _ in }
                )
                .environmentObject(dataController)
            }
        }
    }

    // MARK: - Chip

    @ViewBuilder
    private func chip(for suggestion: TaskSuggestion) -> some View {
        let taskType = taskTypeById[suggestion.taskTypeId]
        let displayName = taskType?.display ?? "Task"
        let chipColor = Color(hex: taskType?.color ?? "") ?? OPSStyle.Colors.primaryAccent
        let members: [User] = activeMembers(for: suggestion)

        Button(action: { commit(suggestion) }) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(chipColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    metaRow(members: members)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, OPSStyle.Layout.spacing2)
            }
            .frame(width: 168, height: 56, alignment: .leading)
            .nestedCard()
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                prefilledSuggestion = suggestion
            } label: {
                Label("Edit Before Adding", systemImage: "pencil")
            }
            Button(role: .destructive) {
                dismiss(suggestion)
            } label: {
                Label("Dismiss Suggestion", systemImage: "xmark.circle")
            }
        }
    }

    @ViewBuilder
    private func metaRow(members: [User]) -> some View {
        if members.isEmpty {
            Text("UNASSIGNED")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        } else {
            HStack(spacing: 6) {
                HStack(spacing: -4) {
                    ForEach(Array(members.prefix(2)), id: \.id) { member in
                        UserAvatar(user: member, size: 16)
                            .overlay(
                                Circle()
                                    .stroke(OPSStyle.Colors.background, lineWidth: 1.5)
                            )
                    }
                }
                Text(memberLabel(members))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func memberLabel(_ members: [User]) -> String {
        guard let first = members.first else { return "" }
        let firstName = first.firstName.uppercased()
        if members.count == 1 { return firstName }
        return "\(firstName) +\(members.count - 1)"
    }

    // MARK: - Actions

    private func commit(_ suggestion: TaskSuggestion) {
        guard canEdit else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Final guard: commit only members still active in the company. The
        // engine emits active ids, but one could have been deactivated since
        // it ran — never assign a removed member to a new task. Preserves the
        // engine's lowercased, sorted ordering.
        let activeCrew = activeMembers(for: suggestion)
        let committedMemberIds = activeCrew.map { $0.id.lowercased() }

        let taskType = taskTypeById[suggestion.taskTypeId]
        let taskTypeColor = taskType?.color ?? "#59779F"

        let newTask = ProjectTask(
            id: UUID().uuidString.lowercased(),
            projectId: project.id,
            taskTypeId: suggestion.taskTypeId,
            companyId: project.companyId,
            status: .active,
            taskColor: taskTypeColor
        )
        newTask.setTeamMemberIds(committedMemberIds)
        newTask.displayOrder = (project.tasks.map { $0.displayOrder }.max() ?? -1) + 1

        modelContext.insert(newTask)
        newTask.project = project
        if let taskType { newTask.taskType = taskType }

        // Hydrate teamMembers relationship so the new row renders avatars
        // immediately, matching TaskFormSheet.saveTask's behaviour
        // (TaskFormSheet.swift ~1467-1473). Use the already-resolved active
        // crew rather than re-fetching, so a just-deactivated member can't
        // slip back in.
        newTask.teamMembers = activeCrew

        newTask.needsSync = true
        try? modelContext.save()

        let dto = SupabaseProjectTaskDTO(
            id: newTask.id,
            bubbleId: nil,
            companyId: newTask.companyId,
            projectId: newTask.projectId,
            taskTypeId: newTask.taskTypeId,
            customTitle: nil,
            taskNotes: nil,
            status: newTask.status.rawValue,
            taskColor: newTask.taskColor,
            displayOrder: newTask.displayOrder,
            teamMemberIds: committedMemberIds,
            sourceLineItemId: nil,
            sourceEstimateId: nil,
            startDate: nil,
            endDate: nil,
            duration: 0,
            dependencyOverrides: nil,
            startTime: nil,
            endTime: nil,
            pairedFromTaskId: nil,
            scheduleLocked: nil,
            deletedAt: nil,
            createdAt: nil
        )

        Task { @MainActor in
            do {
                _ = try await dataController.createTask(dto: dto)
            } catch {
                print("[QUICK_ADD] ❌ createTask sync enqueue failed: \(error)")
            }
        }
    }

    private func dismiss(_ suggestion: TaskSuggestion) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        TaskSuggestionEngine.dismiss(suggestion, forProjectId: project.id)
        withAnimation(OPSStyle.Animation.fast) {
            dismissBump &+= 1
        }
    }
}
