//
//  ProjectFormSheet.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//  Overhauled on 2025-09-29.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ProjectFormSheet: View {
    enum Mode {
        case create
        case edit(Project)

        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }

        var project: Project? {
            if case .edit(let project) = self { return project }
            return nil
        }
    }

    enum CreationMode {
        case quick
        case extended
    }

    let mode: Mode
    let onSave: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Query private var allClients: [Client]
    @Query private var allTeamMembers: [TeamMember]

    private var uniqueTeamMembers: [TeamMember] {
        var seen = Set<String>()
        return allTeamMembers.filter { member in
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
    }

    @State private var creationMode: CreationMode = .quick
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var notes: String = ""
    @State private var address: String = ""
    @State private var selectedClientId: String?
    @State private var selectedStatus: Status = .rfq
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var projectImages: [UIImage] = []

    @AppStorage("defaultProjectStatus") private var defaultProjectStatusRaw: String = Status.rfq.rawValue

    private var defaultProjectStatus: Status {
        Status(rawValue: defaultProjectStatusRaw) ?? .rfq
    }

    @State private var showingCreateClient = false
    @State private var clientSearchText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingImagePicker = false
    @State private var showingScheduler = false

    @State private var expandedSections: Set<String> = []

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var isValid: Bool {
        !title.isEmpty && !address.isEmpty && selectedClientId != nil
    }

    private var matchingClients: [Client] {
        guard !clientSearchText.isEmpty else { return [] }
        return allClients.filter {
            $0.name.localizedCaseInsensitiveContains(clientSearchText)
        }
    }

    private var selectedClient: Client? {
        guard let selectedClientId = selectedClientId else { return nil }
        return allClients.first { $0.id == selectedClientId }
    }

    init(mode: Mode, preselectedClient: Client? = nil, onSave: @escaping (Project) -> Void) {
        self.mode = mode
        self.onSave = onSave

        if case .edit(let project) = mode {
            _creationMode = State(initialValue: .extended)
            _title = State(initialValue: project.title)
            _description = State(initialValue: project.projectDescription ?? "")
            _notes = State(initialValue: project.notes ?? "")
            _address = State(initialValue: project.address ?? "")
            _selectedClientId = State(initialValue: project.client?.id)
            _startDate = State(initialValue: project.startDate)
            _endDate = State(initialValue: project.endDate)
            _selectedTeamMemberIds = State(initialValue: Set(project.teamMembers.map { $0.id }))
        } else if let preselectedClient = preselectedClient {
            // Pre-populate with client info when creating from client view
            _selectedClientId = State(initialValue: preselectedClient.id)
            _address = State(initialValue: preselectedClient.address ?? "")
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if mode.isCreate {
                            modeToggle
                        }

                        quickFieldsSection

                        if creationMode == .extended {
                            expandedFieldsSection
                        }
    }
                    .padding()
                    .padding(.bottom, 100)
                }

                if isSaving {
                    savingOverlay
                }
            }
            .navigationTitle(mode.isCreate ? "NEW PROJECT" : "EDIT PROJECT")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                }.foregroundColor(OPSStyle.Colors.primaryAccent),
                trailing: Button("Save") {
                    saveProject()
                }
                .foregroundColor(isValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                .disabled(!isValid || isSaving)
            )
        }
        .sheet(isPresented: $showingCreateClient) {
            ClientFormSheet(mode: .create, prefilledName: clientSearchText) { newClient in
                selectedClientId = newClient.id
                clientSearchText = newClient.name
            }
        }
        .sheet(isPresented: $showingScheduler) {
            if let start = startDate, let end = endDate {
                CalendarSchedulerSheet(
                    isPresented: $showingScheduler,
                    itemType: .project(Project(id: UUID().uuidString, title: "Temp", status: .rfq)),
                    currentStartDate: start,
                    currentEndDate: end,
                    onScheduleUpdate: { newStart, newEnd in
                        self.startDate = newStart
                        self.endDate = newEnd
                    }
                )
                .environmentObject(dataController)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .onAppear {
            if mode.isCreate {
                selectedStatus = defaultProjectStatus
            }
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            Button(action: { withAnimation { creationMode = .quick } }) {
                Text("QUICK")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(creationMode == .quick ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(creationMode == .quick ? OPSStyle.Colors.primaryText : Color.clear)
            }

            Button(action: { withAnimation { creationMode = .extended } }) {
                Text("EXTENDED")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(creationMode == .extended ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(creationMode == .extended ? OPSStyle.Colors.primaryText : Color.clear)
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Quick Fields (Always Visible)

    private var quickFieldsSection: some View {
        VStack(spacing: 16) {
            clientField
            titleField
            addressField
            statusField
        }
    }

    private var clientField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIENT *")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if let selectedClient = selectedClient {
                selectedClientCard
            } else {
                clientSearchField
            }
        }
    }

    private var selectedClientCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedClient!.name)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if let email = selectedClient!.email {
                    Text(email)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Spacer()

            Button(action: {
                selectedClientId = nil
                clientSearchText = ""
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var clientSearchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TextField("Search or create client...", text: $clientSearchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if !clientSearchText.isEmpty {
                    Button(action: {
                        clientSearchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)

            if !clientSearchText.isEmpty {
                VStack(spacing: 0) {
                    if matchingClients.isEmpty {
                        Button(action: { showingCreateClient = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                Text("Create \"\(clientSearchText)\"")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                Spacer()
                            }
                            .padding()
                        }
                    } else {
                        ForEach(matchingClients.prefix(5)) { client in
                            Button(action: {
                                selectedClientId = client.id
                                clientSearchText = client.name
                            }) {
                                HStack {
                                    Text(client.name)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Spacer()
                                }
                                .padding()
                            }
                            .buttonStyle(PlainButtonStyle())

                            if client.id != matchingClients.prefix(5).last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                            }
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROJECT NAME *")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField("Enter project name", text: $title)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ADDRESS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                if let client = selectedClient, let billingAddress = client.address, !billingAddress.isEmpty {
                    Button(action: {
                        address = billingAddress
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }) {
                        Text("USE BILLING ADDRESS")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }

            AddressSearchField(
                address: $address,
                placeholder: "Enter project address"
            )
        }
    }

    private var statusField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JOB STATUS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Menu {
                ForEach(Status.allCases, id: \.self) { status in
                    Button(action: {
                        selectedStatus = status
                        defaultProjectStatusRaw = status.rawValue
                    }) {
                        HStack {
                            Text(status.displayName)
                            if selectedStatus == status {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedStatus.displayName.uppercased())
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Extended Fields

    private var expandedFieldsSection: some View {
        VStack(spacing: 16) {
            descriptionSection
            notesSection
            datesSection
            teamMembersSection
            photosSection
        }
    }

    private var descriptionSection: some View {
        ExpandableSection(
            title: "PROJECT DESCRIPTION",
            isExpanded: Binding(
                get: { expandedSections.contains("description") || creationMode == .extended },
                set: { if $0 { expandedSections.insert("description") } else { expandedSections.remove("description") } }
            )
        ) {
            TextEditor(text: $description)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(minHeight: 100)
                .padding(12)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .scrollContentBackground(.hidden)
        }
    }

    private var notesSection: some View {
        ExpandableSection(
            title: "PROJECT NOTES",
            isExpanded: Binding(
                get: { expandedSections.contains("notes") || creationMode == .extended },
                set: { if $0 { expandedSections.insert("notes") } else { expandedSections.remove("notes") } }
            )
        ) {
            TextEditor(text: $notes)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(minHeight: 80)
                .padding(12)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .scrollContentBackground(.hidden)
        }
    }

    private var datesSection: some View {
        ExpandableSection(
            title: "DATES",
            isExpanded: Binding(
                get: { expandedSections.contains("dates") || creationMode == .extended },
                set: { if $0 { expandedSections.insert("dates") } else { expandedSections.remove("dates") } }
            )
        ) {
            Button(action: {
                if startDate == nil {
                    startDate = Date()
                    endDate = Date().addingTimeInterval(86400 * 7)
                }
                showingScheduler = true
            }) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if let startDate = startDate, let endDate = endDate {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDate(startDate))
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text("to \(formatDate(endDate))")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    } else {
                        Text("Tap to Schedule")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    private var teamMembersSection: some View {
        ExpandableSection(
            title: "TEAM MEMBERS",
            isExpanded: Binding(
                get: { expandedSections.contains("team") || creationMode == .extended },
                set: { if $0 { expandedSections.insert("team") } else { expandedSections.remove("team") } }
            )
        ) {
            VStack(spacing: 1) {
                ForEach(uniqueTeamMembers) { member in
                    Button(action: {
                        if selectedTeamMemberIds.contains(member.id) {
                            selectedTeamMemberIds.remove(member.id)
                        } else {
                            selectedTeamMemberIds.insert(member.id)
                        }
                    }) {
                        HStack {
                            Image(systemName: selectedTeamMemberIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedTeamMemberIds.contains(member.id) ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)

                            Text(member.fullName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            Spacer()

                            Text(member.role)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .padding()
                        .background(OPSStyle.Colors.background)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)

            if !selectedTeamMemberIds.isEmpty {
                Text("\(selectedTeamMemberIds.count) member\(selectedTeamMemberIds.count == 1 ? "" : "s") selected")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private var photosSection: some View {
        ExpandableSection(
            title: "PROJECT PHOTOS",
            isExpanded: Binding(
                get: { expandedSections.contains("photos") || creationMode == .extended },
                set: { if $0 { expandedSections.insert("photos") } else { expandedSections.remove("photos") } }
            )
        ) {
            if !projectImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(projectImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipped()
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)

                                Button(action: { removeImage(at: index) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.7)))
                                }
                                .offset(x: 5, y: -5)
                            }
                        }

                        Button(action: { showingImagePicker = true }) {
                            VStack {
                                Image(systemName: "plus")
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .frame(width: 100, height: 100)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.5))
                            )
                        }
                    }
                }
            } else {
                Button(action: { showingImagePicker = true }) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20))
                        Text("Add Photos")
                            .font(OPSStyle.Typography.body)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                            .foregroundColor(OPSStyle.Colors.primaryAccent.opacity(0.3))
                    )
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(images: $projectImages, selectionLimit: 10)
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text("Saving Project...")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Helper Methods

    private func removeImage(at index: Int) {
        guard index < projectImages.count else { return }
        projectImages.remove(at: index)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func saveProject() {
        isSaving = true

        Task {
            do {
                let project: Project

                if case .create = mode {
                    project = try await createNewProject()
                } else if case .edit(let existingProject) = mode {
                    try await updateExistingProject(existingProject)
                    project = existingProject
                } else {
                    return
                }

                await MainActor.run {
                    onSave(project)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
            }
        }
    }

    private func createNewProject() async throws -> Project {
        guard let companyId = dataController.currentUser?.companyId,
              let client = selectedClient else {
            throw ProjectError.missingRequiredFields
        }

        let project = Project(
            id: UUID().uuidString,
            title: title,
            status: selectedStatus
        )

        project.companyId = companyId
        project.eventType = .project
        project.client = client
        project.projectDescription = description.isEmpty ? nil : description
        project.notes = notes.isEmpty ? "" : notes
        project.address = address.isEmpty ? "" : address
        project.startDate = startDate
        project.endDate = endDate
        project.allDay = true

        let members = allTeamMembers.filter { selectedTeamMemberIds.contains($0.id) }
        project.teamMembers = Array(members.map { member in
            let user = User(
                id: member.id,
                firstName: member.firstName,
                lastName: member.lastName,
                role: UserRole(rawValue: member.role.lowercased()) ?? .fieldCrew,
                companyId: project.companyId
            )
            user.email = member.email
            return user
        })

        await MainActor.run {
            modelContext.insert(project)

            client.projects.append(project)

            try? modelContext.save()
        }

        dataController.syncManager?.triggerBackgroundSync()

        return project
    }

    private func updateExistingProject(_ project: Project) async throws {
        guard let client = selectedClient else {
            throw ProjectError.missingRequiredFields
        }

        await MainActor.run {
            project.title = title
            project.client = client
            project.projectDescription = description.isEmpty ? nil : description
            project.notes = notes.isEmpty ? "" : notes
            project.address = address.isEmpty ? "" : address
            project.startDate = startDate
            project.endDate = endDate
            project.needsSync = true

            let members = allTeamMembers.filter { selectedTeamMemberIds.contains($0.id) }
            project.teamMembers = Array(members.map { member in
                let user = User(
                    id: member.id,
                    firstName: member.firstName,
                    lastName: member.lastName,
                    role: UserRole(rawValue: member.role.lowercased()) ?? .fieldCrew,
                    companyId: project.companyId
                )
                user.email = member.email
                return user
            })

            try? modelContext.save()
        }

        dataController.syncManager?.triggerBackgroundSync()
    }
}

// MARK: - Expandable Section Component

struct ExpandableSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(title)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            if isExpanded {
                content()
            }
        }
    }
}

// MARK: - Supporting Types

enum ProjectError: LocalizedError {
    case missingRequiredFields
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .missingRequiredFields:
            return "Please fill in all required fields"
        case .saveFailed:
            return "Failed to save project"
        }
    }
}