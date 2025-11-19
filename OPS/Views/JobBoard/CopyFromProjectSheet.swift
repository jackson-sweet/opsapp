//
//  CopyFromProjectSheet.swift
//  OPS
//
//  Sheet for copying data from existing projects
//

import SwiftUI
import SwiftData

struct CopyFromProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Query private var allProjects: [Project]

    let onCopy: ([String: Any]) -> Void
    let populatedFields: Set<String>

    @State private var searchText = ""
    @State private var selectedProject: Project?
    @State private var selectedFields: Set<String> = []
    @State private var showingOverwriteWarning = false
    @State private var fieldsToOverwrite: [String] = []

    private var filteredProjects: [Project] {
        let baseProjects: [Project]
        if searchText.isEmpty {
            baseProjects = allProjects
        } else {
            baseProjects = allProjects.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.effectiveClientName.localizedCaseInsensitiveContains(searchText)
            }
        }
        // Sort by most recently synced (or title alphabetically if no sync date)
        return baseProjects.sorted { (project1: Project, project2: Project) -> Bool in
            let date1 = project1.lastSyncedAt ?? Date.distantPast
            let date2 = project2.lastSyncedAt ?? Date.distantPast
            if date1 == date2 {
                return project1.title.localizedCompare(project2.title) == .orderedAscending
            }
            return date1 > date2
        }
    }

    private var availableFields: [(id: String, label: String, hasData: Bool)] {
        guard let project = selectedProject else { return [] }

        // Return ALL fields, not just those with data
        return [
            (id: "name", label: "PROJECT NAME", hasData: !project.title.isEmpty),
            (id: "client", label: "CLIENT", hasData: project.client != nil),
            (id: "address", label: "SITE ADDRESS", hasData: !(project.address ?? "").isEmpty),
            (id: "description", label: "DESCRIPTION", hasData: !(project.projectDescription ?? "").isEmpty),
            (id: "notes", label: "NOTES", hasData: !(project.notes ?? "").isEmpty),
            (id: "tasks", label: "TASKS", hasData: !project.tasks.isEmpty)
            // (id: "images", label: "PROJECT IMAGES", hasData: false) // TODO: Add when image support is implemented
        ]
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                if selectedProject == nil {
                    projectSelectionView
                } else {
                    fieldSelectionView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(selectedProject == nil ? "SELECT PROJECT" : "SELECT FIELDS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(selectedProject == nil ? "Cancel" : "Back") {
                        if selectedProject != nil {
                            selectedProject = nil
                            selectedFields.removeAll()
                        } else {
                            dismiss()
                        }
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }

                if selectedProject != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Copy") {
                            handleCopy()
                        }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(selectedFields.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                        .disabled(selectedFields.isEmpty)
                    }
                }
            }
        }
        .alert("Overwrite Warning", isPresented: $showingOverwriteWarning) {
            Button("Cancel", role: .cancel) {
                fieldsToOverwrite.removeAll()
            }
            Button("Overwrite", role: .destructive) {
                performCopy()
            }
        } message: {
            Text("You are about to overwrite data in the following fields:\n\n\(fieldsToOverwrite.joined(separator: ", "))\n\nAre you sure you want to continue?")
        }
        .overlay(alignment: .bottom) {
            // Alert description at bottom of screen
            if showingOverwriteWarning {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                            .font(.system(size: 14))

                        Text("Some fields will be overwritten")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.warningStatus, lineWidth: 1)
                    )
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Project Selection View

    private var projectSelectionView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TextField("Search projects...", text: $searchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocorrectionDisabled(true)

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .padding()

            // Project list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredProjects) { project in
                        // Use simplified card layout matching UniversalJobBoardCard pattern
                        projectSelectionCard(for: project)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedProject = project
                            }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Project Selection Card

    private func projectSelectionCard(for project: Project) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title.uppercased())
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)

                        Text(project.effectiveClientName)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                // Metadata row
                HStack(spacing: 12) {
                    if let address = project.address, !address.isEmpty {
                        HStack(alignment: .bottom, spacing: 4) {
                            Image(systemName: OPSStyle.Icons.location)
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text(formatAddressStreetOnly(address))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }

                    if let startDate = project.startDate {
                        HStack(alignment: .bottom, spacing: 4) {
                            Image(systemName: OPSStyle.Icons.calendar)
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text(DateHelper.simpleDateString(from: startDate))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }

                    if !project.teamMembers.isEmpty {
                        HStack(alignment: .bottom, spacing: 4) {
                            Image(systemName: OPSStyle.Icons.personTwo)
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text("\(project.teamMembers.count)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
            }
            .padding(14)
        }
        .frame(height: 80)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .overlay(
            // Status badge
            VStack(alignment: .trailing, spacing: 0) {
                Text(project.status.displayName.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(project.status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(project.status.color.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(project.status.color, lineWidth: 1)
                    )

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(8)
        )
        .padding(.vertical, 8)
    }

    /// Format address to show only street number and street name (no city)
    private func formatAddressStreetOnly(_ address: String) -> String {
        let components = address.components(separatedBy: ",")
        if let streetAddress = components.first?.trimmingCharacters(in: .whitespaces), !streetAddress.isEmpty {
            return streetAddress
        }
        return address.formatAsSimpleAddress()
    }

    // MARK: - Field Selection View

    private var fieldSelectionView: some View {
        VStack(spacing: 16) {
            // Selected project info
            if let project = selectedProject {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COPYING FROM")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text(project.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(project.effectiveClientName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .padding(.horizontal)
            }

            // Field checklist
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(availableFields, id: \.id) { field in
                        fieldChecklistRow(field: field)
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .padding()
            }
        }
        .padding(.top)
    }

    private func fieldChecklistRow(field: (id: String, label: String, hasData: Bool)) -> some View {
        Button(action: {
            // Only allow selecting fields that have data
            guard field.hasData else { return }

            if selectedFields.contains(field.id) {
                selectedFields.remove(field.id)
            } else {
                selectedFields.insert(field.id)
            }
        }) {
            HStack {
                Image(systemName: selectedFields.contains(field.id) ? "checkmark.square.fill" : "square")
                    .foregroundColor(selectedFields.contains(field.id) ? OPSStyle.Colors.primaryAccent : (field.hasData ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.tertiaryText.opacity(0.3)))
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(field.hasData ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                    // Show [EMPTY] caption for empty fields
                    if !field.hasData {
                        Text("[EMPTY]")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                Spacer()

                // Show warning icon if field is already populated
                if populatedFields.contains(field.id) && field.hasData {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                        .font(.system(size: 14))
                }
            }
            .padding()
            .background(OPSStyle.Colors.background)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!field.hasData) // Disable button for empty fields
    }

    // MARK: - Copy Logic

    private func handleCopy() {
        // Check if any selected fields would overwrite existing data
        fieldsToOverwrite = selectedFields.filter { populatedFields.contains($0) }
            .compactMap { fieldId in
                availableFields.first(where: { $0.id == fieldId })?.label
            }

        if !fieldsToOverwrite.isEmpty {
            showingOverwriteWarning = true
        } else {
            performCopy()
        }
    }

    private func performCopy() {
        guard let project = selectedProject else { return }

        var copiedData: [String: Any] = [:]

        for fieldId in selectedFields {
            switch fieldId {
            case "name":
                copiedData["name"] = project.title
            case "client":
                if let client = project.client {
                    copiedData["clientId"] = client.id
                }
            case "address":
                if let address = project.address {
                    copiedData["address"] = address
                }
            case "description":
                if let description = project.projectDescription {
                    copiedData["description"] = description
                }
            case "notes":
                if let notes = project.notes {
                    copiedData["notes"] = notes
                }
            case "tasks":
                // Copy task data including team members and dates
                copiedData["tasks"] = project.tasks.map { task in
                    var taskDict: [String: Any] = [
                        "taskTypeId": task.taskTypeId,
                        "status": task.status.rawValue,
                        "teamMemberIds": task.getTeamMemberIds()
                    ]
                    // Include dates if the task has a calendar event
                    if let startDate = task.calendarEvent?.startDate {
                        taskDict["startDate"] = startDate
                    }
                    if let endDate = task.calendarEvent?.endDate {
                        taskDict["endDate"] = endDate
                    }
                    return taskDict
                }
            case "images":
                // TODO: Image copying not implemented yet
                break
            default:
                break
            }
        }

        onCopy(copiedData)

        #if !targetEnvironment(simulator)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        dismiss()
    }
}

