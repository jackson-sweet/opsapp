//
//  ClientDeletionSheet.swift
//  OPS
//
//  Canonical client deletion transaction used by client details, Job Board,
//  and Universal Search.
//

import SwiftUI
import SwiftData

private enum ClientDeletionError: LocalizedError {
    case incompleteProjectSelection
    case reassignmentTargetUnavailable

    var errorDescription: String? {
        switch self {
        case .incompleteProjectSelection:
            return "Choose where every project should go."
        case .reassignmentTargetUnavailable:
            return "That client is no longer available. Choose another."
        }
    }
}

struct ClientDeletionSheet: View {
    let client: Client
    private let onRequestOwningDetailDismissal: () -> Void
    private let waitForOwningDetailDismissal: () async -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allClients: [Client]
    @StateObject private var dismissalGate = ClientDeletionPresentationGate()

    init(
        client: Client,
        onRequestOwningDetailDismissal: @escaping () -> Void = {},
        waitForOwningDetailDismissal: @escaping () async -> Void = {}
    ) {
        self.client = client
        self.onRequestOwningDetailDismissal = onRequestOwningDetailDismissal
        self.waitForOwningDetailDismissal = waitForOwningDetailDismissal
    }

    private var activeProjects: [Project] {
        client.activeProjects.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private var reassignmentCandidates: [Client] {
        ClientDeletionTargetPolicy.candidates(from: allClients, deleting: client)
    }

    var body: some View {
        DeletionSheet(
            item: client,
            itemType: "Client",
            childItems: activeProjects,
            childType: "Project",
            availableReassignments: reassignmentCandidates,
            getItemDisplay: { client in
                AnyView(
                    Text(client.name)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                )
            },
            filterAvailableItems: { $0 },
            getChildId: { $0.id },
            getReassignmentId: { $0.id },
            renderReassignmentRow: { project, selectedId, markedForDeletion, available, onToggleDelete in
                AnyView(
                    ProjectReassignmentRow(
                        project: project,
                        selectedClientId: selectedId,
                        markedForDeletion: markedForDeletion,
                        availableClients: available,
                        onToggleDelete: onToggleDelete
                    )
                )
            },
            renderSearchField: { selectedId, available in
                AnyView(
                    SearchField(
                        selectedId: selectedId,
                        items: available,
                        placeholder: "Search for client",
                        leadingIcon: OPSStyle.Icons.client,
                        getId: { $0.id },
                        getDisplayText: { $0.name },
                        getSubtitle: { candidate in
                            candidate.activeProjects.isEmpty
                                ? nil
                                : "\(candidate.activeProjects.count) project\(candidate.activeProjects.count == 1 ? "" : "s")"
                        }
                    )
                )
            },
            onDelete: performDeletion
        )
        .environmentObject(dataController)
        .onDisappear {
            dismissalGate.signalDismissed()
        }
    }

    @MainActor
    private func performDeletion(
        _ client: Client,
        reassignments: [String: String],
        deletions: Set<String>
    ) async throws {
        let projects = activeProjects
        let candidatesById = reassignmentCandidates.reduce(into: [String: Client]()) {
            candidates, candidate in
            // Candidate policy already deduplicates logical IDs. Keep this map
            // collision-safe as a final defence against corrupt local history.
            if candidates[candidate.id] == nil {
                candidates[candidate.id] = candidate
            }
        }

        // Validate the entire disposition before changing the first project.
        // This prevents a stale or incomplete picker selection from leaving a
        // client only partially reassigned when the sheet reports an error.
        for project in projects where !deletions.contains(project.id) {
            guard let targetId = reassignments[project.id] else {
                throw ClientDeletionError.incompleteProjectSelection
            }
            guard candidatesById[targetId] != nil else {
                throw ClientDeletionError.reassignmentTargetUnavailable
            }
        }

        for project in projects {
            if deletions.contains(project.id) {
                try await dataController.deleteProject(project)
                continue
            }

            guard let targetId = reassignments[project.id] else {
                throw ClientDeletionError.incompleteProjectSelection
            }
            guard let target = candidatesById[targetId] else {
                throw ClientDeletionError.reassignmentTargetUnavailable
            }

            try await dataController.updateProjectFields(
                projectId: project.id,
                fields: ["client_id": .string(target.id)]
            )
            project.client = target
            project.clientId = target.id
        }

        try modelContext.save()

        var presentationsDismissed = false
        do {
            try await ClientDeletionPresentationCoordinator.performInvalidatingMutation(
                dismissPresentations: {
                    presentationsDismissed = true
                    dismiss()
                    onRequestOwningDetailDismissal()
                },
                waitForDismissal: {
                    await dismissalGate.waitUntilDismissed()
                    await waitForOwningDetailDismissal()
                },
                mutation: {
                    try await dataController.deleteClient(client)
                }
            )

            // Drain the queued project/client mutations explicitly before any
            // pull. triggerSync may already be serving another caller, so its
            // own concurrency guard is not a sufficient delivery barrier.
            await dataController.syncEngine.pushPending()
            await dataController.syncEngine.triggerSync()
            ToastCenter.shared.present(Feedback.deleted("Client"))
        } catch {
            if presentationsDismissed {
                ToastCenter.shared.present(
                    Toast(label: Feedback.Err.deleteFailed, tone: .error)
                )
            }
            throw error
        }
    }
}
