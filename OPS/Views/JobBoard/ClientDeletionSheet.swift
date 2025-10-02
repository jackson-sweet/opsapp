//
//  ClientDeletionSheet.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-09-26.
//

import SwiftUI
import SwiftData

struct ClientDeletionSheet: View {
    let client: Client
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allClients: [Client]
    @State private var reassignments: [String: String] = [:] // projectId: newClientId
    @State private var selectedBulkClient: String?
    @State private var isDeleting = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private var clientProjects: [Project] {
        client.projects.sorted { $0.title < $1.title }
    }

    private var availableClients: [Client] {
        allClients.filter { $0.id != client.id }
    }

    private var allProjectsReassigned: Bool {
        clientProjects.allSatisfy { project in
            reassignments[project.id] != nil
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    if !clientProjects.isEmpty {
                        // Warning Card
                        WarningCard(
                            clientName: client.name,
                            projectCount: clientProjects.count
                        )

                        // Bulk Reassignment Option
                        if clientProjects.count > 1 {
                            BulkReassignmentCard(
                                selectedClient: $selectedBulkClient,
                                availableClients: availableClients,
                                onApply: applyBulkReassignment
                            )
                        }

                        // Individual Project Reassignments
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(clientProjects) { project in
                                    ProjectReassignmentRow(
                                        project: project,
                                        selectedClientId: binding(for: project.id),
                                        availableClients: availableClients
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    } else {
                        // No projects to reassign
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(OPSStyle.Colors.successStatus)

                            Text("No projects to reassign")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Text("This client has no associated projects and can be safely deleted.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxHeight: .infinity)
                    }

                    Spacer()

                    // Delete Button
                    Button(action: performDeletion) {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "trash.fill")
                                Text("DELETE CLIENT")
                                    .font(OPSStyle.Typography.bodyBold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            !clientProjects.isEmpty && !allProjectsReassigned
                                ? Color.gray.opacity(0.3)
                                : OPSStyle.Colors.errorStatus
                        )
                        .foregroundColor(.white)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .disabled(!clientProjects.isEmpty && !allProjectsReassigned || isDeleting)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("DELETE CLIENT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
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

    // MARK: - Helper Methods

    private func binding(for projectId: String) -> Binding<String?> {
        Binding(
            get: { reassignments[projectId] },
            set: { reassignments[projectId] = $0 }
        )
    }

    private func applyBulkReassignment() {
        guard let selectedBulkClient = selectedBulkClient else { return }

        for project in clientProjects {
            reassignments[project.id] = selectedBulkClient
        }
    }

    private func performDeletion() {
        isDeleting = true

        Task {
            do {
                // First reassign all projects if needed
                for project in clientProjects {
                    if let newClientId = reassignments[project.id],
                       let newClient = availableClients.first(where: { $0.id == newClientId }) {
                        project.client = newClient
                    }
                }

                // Save changes
                try modelContext.save()

                // Delete the client
                modelContext.delete(client)
                try modelContext.save()

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

struct WarningCard: View {
    let clientName: String
    let projectCount: Int

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(OPSStyle.Colors.warningStatus)

            VStack(alignment: .leading, spacing: 4) {
                Text("PROJECT REASSIGNMENT REQUIRED")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Deleting \(clientName) requires reassigning \(projectCount) project\(projectCount == 1 ? "" : "s")")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.warningStatus.opacity(0.1))
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

struct BulkReassignmentCard: View {
    @Binding var selectedClient: String?
    let availableClients: [Client]
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BULK REASSIGNMENT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack {
                Menu {
                    ForEach(availableClients) { client in
                        Button(action: { selectedClient = client.id }) {
                            HStack {
                                Text(client.name)
                                if selectedClient == client.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedClientName(for: selectedClient, from: availableClients))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(
                                selectedClient != nil
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.tertiaryText
                            )

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }

                Button(action: onApply) {
                    Text("APPLY TO ALL")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(selectedClient == nil)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private func selectedClientName(for id: String?, from clients: [Client]) -> String {
        guard let id = id,
              let client = clients.first(where: { $0.id == id }) else {
            return "Select Client"
        }
        return client.name
    }
}

struct ProjectReassignmentRow: View {
    let project: Project
    @Binding var selectedClientId: String?
    let availableClients: [Client]
    @State private var showingCreateClient = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(project.status.color)
                    .frame(width: 8, height: 8)

                Text(project.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            Menu {
                Button("Create New Client") {
                    showingCreateClient = true
                }

                Divider()

                ForEach(availableClients) { client in
                    Button(action: { selectedClientId = client.id }) {
                        HStack {
                            Text(client.name)
                            if selectedClientId == client.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(selectedClientName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(
                            selectedClientId != nil
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                        )

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(12)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .sheet(isPresented: $showingCreateClient) {
            ClientFormSheet(mode: .create) { newClient in
                selectedClientId = newClient.id
            }
        }
    }

    private var selectedClientName: String {
        guard let id = selectedClientId,
              let client = availableClients.first(where: { $0.id == id }) else {
            return "Select Client"
        }
        return client.name
    }
}