//
//  ClientDeletionSheet.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-09-26.
//

import SwiftUI
import SwiftData

enum ReassignmentMode: String, CaseIterable {
    case bulk = "Bulk Reassign"
    case individual = "Individual"
}

struct ClientDeletionSheet: View {
    let client: Client
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @Query private var allClients: [Client]

    @State private var reassignmentMode: ReassignmentMode = .bulk
    @State private var reassignments: [String: String] = [:] // projectId: newClientId
    @State private var projectsToDelete: Set<String> = [] // projectIds to delete instead of reassign
    @State private var bulkSelectedClient: String?
    @State private var bulkDeleteAll = false // For bulk delete all option
    @State private var isDeleting = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private var clientProjects: [Project] {
        client.projects.sorted { $0.title < $1.title }
    }

    private var availableClients: [Client] {
        allClients.filter {
            $0.id != client.id &&
            !$0.id.contains("-") // Filter out UUIDs - only show Bubble-synced clients
        }
    }

    private var canDeleteClient: Bool {
        if clientProjects.isEmpty {
            return true
        }

        switch reassignmentMode {
        case .bulk:
            return bulkSelectedClient != nil || bulkDeleteAll
        case .individual:
            return clientProjects.allSatisfy { project in
                reassignments[project.id] != nil || projectsToDelete.contains(project.id)
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    // Header section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DELETE CLIENT")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Text(client.name)
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("\(clientProjects.count) project\(clientProjects.count == 1 ? "" : "s")")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                    if !clientProjects.isEmpty {
                        // Segmented control for mode selection
                        SegmentedControl(
                            selection: $reassignmentMode,
                            options: [
                                (.bulk, "Bulk Reassign"),
                                (.individual, "Individual")
                            ]
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        // Content based on mode
                        ScrollView {
                            VStack(spacing: 16) {
                                if reassignmentMode == .bulk {
                                    bulkReassignmentView
                                } else {
                                    individualReassignmentView
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 100)
                        }
                    } else {
                        Spacer()
                    }
                }

                // Delete Button - Floating at bottom
                Button(action: performDeletion) {
                    HStack {
                        if isDeleting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.errorStatus))
                                .scaleEffect(0.8)
                        } else {
                            Text("Delete Client")
                                .font(OPSStyle.Typography.body)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.ultraThinMaterial)
                    .foregroundColor(
                        canDeleteClient
                            ? OPSStyle.Colors.errorStatus
                            : OPSStyle.Colors.tertiaryText
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(
                                canDeleteClient
                                    ? OPSStyle.Colors.errorStatus
                                    : OPSStyle.Colors.tertiaryText,
                                lineWidth: 1.5
                            )
                    )
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(!canDeleteClient || isDeleting)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .disabled(isDeleting)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Bulk Reassignment View

    private var bulkReassignmentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !bulkDeleteAll {
                Text("Reassign all \(clientProjects.count) project\(clientProjects.count == 1 ? "" : "s") to:")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                ClientSearchField(
                    selectedClientId: $bulkSelectedClient,
                    availableClients: availableClients,
                    placeholder: "Search for client"
                )
            } else {
                Text("All \(clientProjects.count) project\(clientProjects.count == 1 ? "" : "s") will be deleted")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .italic()
            }

            // Delete All Projects button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    bulkDeleteAll.toggle()
                    if bulkDeleteAll {
                        bulkSelectedClient = nil
                    }
                }
            }) {
                HStack {
                    Image(systemName: bulkDeleteAll ? "xmark" : "trash")
                        .font(OPSStyle.Typography.body)
                    Text(bulkDeleteAll ? "Don't Delete All Projects" : "Delete All Projects")
                        .font(OPSStyle.Typography.bodyBold)
                }
                .foregroundColor(bulkDeleteAll ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.errorStatus)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(bulkDeleteAll ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.errorStatus, lineWidth: 1.5)
                )
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    // MARK: - Individual Reassignment View

    private var individualReassignmentView: some View {
        VStack(spacing: 12) {
            ForEach(clientProjects) { project in
                ProjectReassignmentRow(
                    project: project,
                    selectedClientId: binding(for: project.id),
                    markedForDeletion: projectsToDelete.contains(project.id),
                    availableClients: availableClients,
                    onToggleDelete: { toggleProjectDeletion(project.id) }
                )
            }
        }
    }

    // MARK: - Helper Methods

    private func binding(for projectId: String) -> Binding<String?> {
        Binding(
            get: { reassignments[projectId] },
            set: { reassignments[projectId] = $0 }
        )
    }

    private func toggleProjectDeletion(_ projectId: String) {
        if projectsToDelete.contains(projectId) {
            projectsToDelete.remove(projectId)
        } else {
            projectsToDelete.insert(projectId)
            reassignments.removeValue(forKey: projectId)
        }
    }

    private func performDeletion() {
        isDeleting = true

        Task {
            do {
                // Step 1: Handle projects (reassign or delete via API)
                if reassignmentMode == .bulk {
                    if bulkDeleteAll {
                        // Delete all projects using centralized method
                        for project in clientProjects {
                            try await dataController.deleteProject(project)
                        }
                    } else if let newClientId = bulkSelectedClient,
                       let newClient = availableClients.first(where: { $0.id == newClientId }) {
                        // Reassign all projects via API
                        print("🔄 Bulk reassigning \(clientProjects.count) projects to client: \(newClient.name) (\(newClientId))")

                        var projectIds: [String] = []
                        for project in clientProjects {
                            print("  📋 Updating project: \(project.title) (\(project.id))")
                            // Update via Bubble API directly
                            let updates = ["Client": newClientId]
                            let bodyData = try JSONSerialization.data(withJSONObject: updates)
                            let _: EmptyResponse = try await dataController.apiService.executeRequest(
                                endpoint: "api/1.1/obj/Project/\(project.id)",
                                method: "PATCH",
                                body: bodyData,
                                requiresAuth: false
                            )
                            print("  ✅ Project \(project.title) updated successfully")
                            projectIds.append(project.id)
                            project.client = newClient
                            project.clientId = newClient.id
                            project.needsSync = false
                            project.lastSyncedAt = Date()
                        }

                        // Fetch current client state from Bubble to get accurate Projects List
                        print("🔄 Fetching current state of client \(newClient.name) from Bubble")
                        let clientDTO: ClientDTO = try await dataController.apiService.executeRequest(
                            endpoint: "api/1.1/obj/Client/\(newClientId)",
                            method: "GET",
                            body: nil,
                            requiresAuth: false
                        )
                        let currentProjectsList = clientDTO.projectsList ?? []
                        print("  Current projects in Bubble: \(currentProjectsList.count)")

                        // Add new projects to the list (avoiding duplicates)
                        var updatedProjectsList = currentProjectsList
                        for projectId in projectIds where !updatedProjectsList.contains(projectId) {
                            updatedProjectsList.append(projectId)
                        }
                        print("  Updated projects list count: \(updatedProjectsList.count)")

                        // Update the client's projects list
                        print("🔄 Updating client \(newClient.name) Projects List")
                        let clientUpdates = ["Projects List": updatedProjectsList]
                        let clientBodyData = try JSONSerialization.data(withJSONObject: clientUpdates)
                        let _: EmptyResponse = try await dataController.apiService.executeRequest(
                            endpoint: "api/1.1/obj/Client/\(newClientId)",
                            method: "PATCH",
                            body: clientBodyData,
                            requiresAuth: false
                        )
                        print("✅ Client \(newClient.name) updated with new projects list")
                        print("✅ All \(clientProjects.count) projects reassigned")
                    }
                } else {
                    // Individual mode
                    var clientProjectMap: [String: [String]] = [:]

                    for project in clientProjects {
                        if projectsToDelete.contains(project.id) {
                            // Delete using centralized method
                            try await dataController.deleteProject(project)
                        } else if let newClientId = reassignments[project.id],
                           let newClient = availableClients.first(where: { $0.id == newClientId }) {
                            print("  📋 Individual: Updating project \(project.title) to client \(newClient.name)")
                            // Update via Bubble API directly
                            let updates = ["Client": newClientId]
                            let bodyData = try JSONSerialization.data(withJSONObject: updates)
                            let _: EmptyResponse = try await dataController.apiService.executeRequest(
                                endpoint: "api/1.1/obj/Project/\(project.id)",
                                method: "PATCH",
                                body: bodyData,
                                requiresAuth: false
                            )
                            print("  ✅ Project \(project.title) updated successfully")
                            project.client = newClient
                            project.clientId = newClient.id
                            project.needsSync = false
                            project.lastSyncedAt = Date()

                            // Track which projects go to which client
                            if clientProjectMap[newClientId] == nil {
                                clientProjectMap[newClientId] = []
                            }
                            clientProjectMap[newClientId]?.append(project.id)
                        }
                    }

                    // Update each affected client's projects list
                    for (clientId, projectIds) in clientProjectMap {
                        if let client = availableClients.first(where: { $0.id == clientId }) {
                            print("🔄 Fetching current state of client \(client.name) from Bubble")
                            let clientDTO: ClientDTO = try await dataController.apiService.executeRequest(
                                endpoint: "api/1.1/obj/Client/\(clientId)",
                                method: "GET",
                                body: nil,
                                requiresAuth: false
                            )
                            let currentProjectsList = clientDTO.projectsList ?? []
                            print("  Current projects in Bubble: \(currentProjectsList.count)")

                            // Add new projects to the list (avoiding duplicates)
                            var updatedProjectsList = currentProjectsList
                            for projectId in projectIds where !updatedProjectsList.contains(projectId) {
                                updatedProjectsList.append(projectId)
                            }
                            print("  Updated projects list count: \(updatedProjectsList.count)")

                            // Update the client's projects list
                            print("🔄 Updating client \(client.name) Projects List")
                            let clientUpdates = ["Projects List": updatedProjectsList]
                            let clientBodyData = try JSONSerialization.data(withJSONObject: clientUpdates)
                            let _: EmptyResponse = try await dataController.apiService.executeRequest(
                                endpoint: "api/1.1/obj/Client/\(clientId)",
                                method: "PATCH",
                                body: clientBodyData,
                                requiresAuth: false
                            )
                            print("✅ Client \(client.name) updated with new projects list")
                        }
                    }
                }

                // Step 2: Save project changes locally
                try modelContext.save()

                // Step 3: Delete the client using centralized method
                try await dataController.deleteClient(client)

                // Step 4: Trigger a sync to refresh data from Bubble
                print("🔄 Triggering sync to refresh client/project relationships from Bubble")
                await dataController.syncManager.forceSyncProjects()
                print("✅ Sync completed")

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = "Failed to delete client: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ProjectReassignmentRow: View {
    let project: Project
    @Binding var selectedClientId: String?
    let markedForDeletion: Bool
    let availableClients: [Client]
    let onToggleDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(project.status.color)
                    .frame(width: 8, height: 8)

                Text(project.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(markedForDeletion ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)

                if markedForDeletion {
                    Spacer()
                    Text("Will be deleted")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .italic()
                }
            }

            if markedForDeletion {
                Button(action: onToggleDelete) {
                    HStack {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.errorStatus)

                        Text("Don't Delete Project")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.errorStatus)

                        Spacer()
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }
            } else {
                HStack(spacing: 8) {
                    ClientSearchField(
                        selectedClientId: $selectedClientId,
                        availableClients: availableClients,
                        placeholder: "Search for client"
                    )

                    Button(action: onToggleDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .frame(width: 44, height: 44)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
            }
        }
    }
}
