//
//  ProjectFormSheet.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//  Overhauled on November 16, 2025 - Progressive Disclosure Design
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

    let mode: Mode
    let onSave: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Query private var allClients: [Client]
    @Query private var allTeamMembers: [TeamMember]
    @Query private var allTaskTypes: [TaskType]

    private var uniqueTeamMembers: [TeamMember] {
        var seen = Set<String>()
        return allTeamMembers.filter { member in
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
    }

    // MARK: - Form Fields
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var notes: String = ""
    @State private var address: String = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var selectedClientId: String?
    @State private var selectedStatus: Status = .rfq
    @State private var startDate: Date? = nil
    @State private var endDate: Date? = nil
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var projectImages: [UIImage] = []

    // Local tasks for multiple task creation
    @State private var localTasks: [LocalTask] = []

    @AppStorage("defaultProjectStatus") private var defaultProjectStatusRaw: String = Status.rfq.rawValue

    private var defaultProjectStatus: Status {
        Status(rawValue: defaultProjectStatusRaw) ?? .rfq
    }

    // MARK: - UI State
    @State private var showingCreateClient = false
    @State private var clientSearchText = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingImagePicker = false
    @State private var showingScheduler = false
    @State private var showingCopyFromProject = false
    @State private var showingTaskForm = false
    @State private var editingTaskIndex: Int?

    // Expanded sections tracking
    @State private var isBasicInfoExpanded = true // New: for client and project name
    @State private var isAddressExpanded = false
    @State private var isDescriptionExpanded = false
    @State private var isNotesExpanded = false
    @State private var isTasksExpanded = false
    @State private var isDatesExpanded = false
    @State private var isPhotosExpanded = false

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false

    // Focus states for input fields
    @FocusState private var focusedField: FormField?

    // Temporary state for notes and description editing
    @State private var tempNotes: String = ""
    @State private var tempDescription: String = ""
    @State private var isEditingNotes = false
    @State private var isEditingDescription = false

    enum FormField: Hashable {
        case client
        case title
        case address
        case notes
        case description
        case status
    }

    private var isValid: Bool {
        !title.isEmpty && selectedClientId != nil
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

    // Track which fields are populated for copy warnings
    private var populatedFields: Set<String> {
        var fields = Set<String>()
        if !title.isEmpty { fields.insert("name") }
        if selectedClientId != nil { fields.insert("client") }
        if !address.isEmpty { fields.insert("address") }
        if !description.isEmpty { fields.insert("description") }
        if !notes.isEmpty { fields.insert("notes") }
        if !localTasks.isEmpty { fields.insert("tasks") }
        return fields
    }

    init(mode: Mode, preselectedClient: Client? = nil, onSave: @escaping (Project) -> Void) {
        self.mode = mode
        self.onSave = onSave

        if case .edit(let project) = mode {
            _title = State(initialValue: project.title)
            _description = State(initialValue: project.projectDescription ?? "")
            _notes = State(initialValue: project.notes ?? "")
            _address = State(initialValue: project.address ?? "")
            _selectedClientId = State(initialValue: project.client?.id)
            _startDate = State(initialValue: project.startDate)
            _endDate = State(initialValue: project.endDate)
            _selectedTeamMemberIds = State(initialValue: Set(project.teamMembers.map { $0.id }))

            // Auto-expand sections with data
            _isAddressExpanded = State(initialValue: !(project.address ?? "").isEmpty)
            _isDescriptionExpanded = State(initialValue: !(project.projectDescription ?? "").isEmpty)
            _isNotesExpanded = State(initialValue: !(project.notes ?? "").isEmpty)
            _isDatesExpanded = State(initialValue: project.startDate != nil)

            // Convert project tasks to local tasks
            _localTasks = State(initialValue: project.tasks.map { task in
                LocalTask(
                    id: UUID(),
                    taskTypeId: task.taskTypeId,
                    customTitle: nil,
                    status: task.status
                )
            })
            _isTasksExpanded = State(initialValue: !project.tasks.isEmpty)
        } else if let preselectedClient = preselectedClient {
            // Pre-populate with client info when creating from client view
            _selectedClientId = State(initialValue: preselectedClient.id)
            if let billingAddress = preselectedClient.address, !billingAddress.isEmpty {
                _address = State(initialValue: billingAddress)
                _isAddressExpanded = State(initialValue: true)
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // PREVIEW CARD
                        previewCard

                        // COPY FROM BUTTON
                        if mode.isCreate {
                            HStack {
                                Spacer()
                                Button(action: { showingCopyFromProject = true }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption)
                                        Text("Copy from project")
                                            .font(OPSStyle.Typography.caption)
                                    }
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.bottom, 12)
                        }

                        // MANDATORY FIELDS (always visible)
                        mandatoryFieldsSection

                        // OPTIONAL SECTIONS
                        optionalSectionsArea
                    }
                    .padding()
                    .padding(.bottom, 24)
                }

                if isSaving {
                    savingOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .principal) {
                    Text(mode.isCreate ? "CREATE PROJECT" : "EDIT PROJECT")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveProject) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                .scaleEffect(0.8)
                        } else {
                            Text(mode.isCreate ? "CREATE" : "SAVE")
                                .font(OPSStyle.Typography.bodyBold)
                        }
                    }
                    .foregroundColor(isValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .disabled(!isValid || isSaving)
                }
            }
            .interactiveDismissDisabled()
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
        .sheet(isPresented: $showingCopyFromProject) {
            CopyFromProjectSheet(
                onCopy: handleCopyFromProject,
                populatedFields: populatedFields
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingTaskForm) {
            SimpleTaskFormSheet(
                allTaskTypes: allTaskTypes.filter { $0.deletedAt == nil }.sorted { $0.displayOrder < $1.displayOrder },
                allTeamMembers: uniqueTeamMembers,
                editingTask: editingTaskIndex != nil ? localTasks[editingTaskIndex!] : nil,
                onSave: { task in
                    if let editingIndex = editingTaskIndex {
                        localTasks[editingIndex] = task
                        editingTaskIndex = nil
                    } else {
                        localTasks.append(task)
                    }
                }
            )
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

    // MARK: - Mandatory Fields Section

    private var mandatoryFieldsSection: some View {
        VStack(spacing: 16) {
            // Expandable section for client and project name
            if isBasicInfoExpanded {
                ExpandableSection(
                    title: "PROJECT DETAILS",
                    icon: "doc.text",
                    isExpanded: $isBasicInfoExpanded,
                    onDelete: nil // Can't delete mandatory section
                ) {
                    VStack(spacing: 16) {
                        clientField
                        titleField
                        statusField
                    }
                }
            }
        }
    }

    private var clientField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIENT")
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
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.clear)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
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
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .client)

                if !clientSearchText.isEmpty {
                    Button(action: {
                        clientSearchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        focusedField == .client ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.2),
                        lineWidth: 1
                    )
            )

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
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
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
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if client.id != matchingClients.prefix(5).last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                            }
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROJECT NAME")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField("Enter project name", text: $title)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .title)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            focusedField == .title ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
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
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            focusedField == .status ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.2),
                            lineWidth: 1
                        )
                )
            }
            .onTapGesture {
                focusedField = .status
            }
        }
    }

    // MARK: - Optional Sections Area

    private var optionalSectionsArea: some View {
        VStack(spacing: 16) {
            // Collapsed pills for unexpanded sections
            OptionalSectionPillGroup(pills: [
                (title: "SITE ADDRESS", icon: "mappin.circle", isExpanded: isAddressExpanded, action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isAddressExpanded = true
                    }
                }),
                (title: "DESCRIPTION", icon: "text.alignleft", isExpanded: isDescriptionExpanded, action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isDescriptionExpanded = true
                    }
                }),
                (title: "NOTES", icon: "note.text", isExpanded: isNotesExpanded, action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isNotesExpanded = true
                    }
                }),
                (title: "ADD TASKS", icon: "checklist", isExpanded: isTasksExpanded, action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isTasksExpanded = true
                    }
                }),
                (title: "PHOTOS", icon: "photo", isExpanded: isPhotosExpanded, action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPhotosExpanded = true
                    }
                })
            ])

            // Expanded sections
            if isAddressExpanded {
                addressSection
            }

            if isDescriptionExpanded {
                descriptionSection
            }

            if isNotesExpanded {
                notesSection
            }

            if isTasksExpanded {
                tasksSection
            }

            if isPhotosExpanded {
                photosSection
            }
        }
    }

    // MARK: - Optional Section Views

    private var addressSection: some View {
        ExpandableSection(
            title: "SITE ADDRESS",
            icon: "mappin.circle",
            isExpanded: $isAddressExpanded,
            onDelete: {
                address = ""
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isAddressExpanded = false
                }
                #if !targetEnvironment(simulator)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let client = selectedClient, let billingAddress = client.address, !billingAddress.isEmpty {
                    Button(action: {
                        address = billingAddress
                        #if !targetEnvironment(simulator)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        #endif
                    }) {
                        Text("USE BILLING ADDRESS")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                AddressAutocompleteField(
                    address: $address,
                    placeholder: "Enter project address",
                    onAddressSelected: { fullAddress, coordinates in
                        address = fullAddress
                        if let coords = coordinates {
                            latitude = coords.latitude
                            longitude = coords.longitude
                        }
                    }
                )
            }
        }
    }

    private var descriptionSection: some View {
        ExpandableSection(
            title: "DESCRIPTION",
            icon: "text.alignleft",
            isExpanded: $isDescriptionExpanded,
            onDelete: {
                description = ""
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isDescriptionExpanded = false
                }
                #if !targetEnvironment(simulator)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            }
        ) {
            VStack(spacing: 12) {
                TextEditor(text: isEditingDescription ? $tempDescription : $description)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .description)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(
                                focusedField == .description ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.2),
                                lineWidth: 1
                            )
                    )
                    .onTapGesture {
                        if !isEditingDescription {
                            tempDescription = description
                            isEditingDescription = true
                        }
                    }

                if isEditingDescription {
                    HStack(spacing: 16) {
                        Spacer()

                        Button("CANCEL") {
                            tempDescription = ""
                            isEditingDescription = false
                            focusedField = nil
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                        Button("SAVE") {
                            description = tempDescription
                            isEditingDescription = false
                            focusedField = nil
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        ExpandableSection(
            title: "NOTES",
            icon: "note.text",
            isExpanded: $isNotesExpanded,
            onDelete: {
                notes = ""
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isNotesExpanded = false
                }
                #if !targetEnvironment(simulator)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            }
        ) {
            VStack(spacing: 12) {
                TextEditor(text: isEditingNotes ? $tempNotes : $notes)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(minHeight: 80)
                    .padding(12)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: .notes)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(
                                focusedField == .notes ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.2),
                                lineWidth: 1
                            )
                    )
                    .onTapGesture {
                        if !isEditingNotes {
                            tempNotes = notes
                            isEditingNotes = true
                        }
                    }

                if isEditingNotes {
                    HStack(spacing: 16) {
                        Spacer()

                        Button("CANCEL") {
                            tempNotes = ""
                            isEditingNotes = false
                            focusedField = nil
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                        Button("SAVE") {
                            notes = tempNotes
                            isEditingNotes = false
                            focusedField = nil
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
        }
    }

    private var tasksSection: some View {
        ExpandableSection(
            title: "ADD TASKS",
            icon: "checklist",
            isExpanded: $isTasksExpanded,
            onDelete: {
                localTasks.removeAll()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isTasksExpanded = false
                }
                #if !targetEnvironment(simulator)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            }
        ) {
            VStack(spacing: 12) {
                if !localTasks.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(Array(localTasks.enumerated()), id: \.element.id) { index, task in
                            taskRow(task: task, index: index)
                        }
                    }
                }

                Button(action: {
                    editingTaskIndex = nil
                    showingTaskForm = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                        Text(localTasks.isEmpty ? "Add Task" : "Add Another Task")
                            .font(OPSStyle.Typography.body)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
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
    }

    private func taskRow(task: LocalTask, index: Int) -> some View {
        let taskType = allTaskTypes.first { $0.id == task.taskTypeId }
        let taskColor = (taskType.flatMap { Color(hex: $0.color) }) ?? OPSStyle.Colors.primaryText
        let taskTeamMembers = uniqueTeamMembers.filter { task.teamMemberIds.contains($0.id) }

        return HStack(spacing: 0) {
            // Colored left border
            Rectangle()
                .fill(taskColor)
                .frame(width: 4)

            // Main tappable content area
            HStack {
                // All text inline with bullet separators
                HStack(spacing: 6) {
                    // Task type name
                    Text(taskType?.display.uppercased() ?? "UNKNOWN TASK")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Bullet separator
                    Text("•")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    // Status
                    Text(task.status.displayName.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    // Date (if exists)
                    if let startDate = startDate {
                        Text("•")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text(DateHelper.simpleDateString(from: startDate).uppercased())
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    // Team count (if exists)
                    if !taskTeamMembers.isEmpty {
                        Text("•")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text("\(taskTeamMembers.count) \(taskTeamMembers.count == 1 ? "MEMBER" : "MEMBERS")")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)

                Spacer()

                // Team member avatars on the right using UserAvatar
                if !taskTeamMembers.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(taskTeamMembers.prefix(3), id: \.id) { member in
                            UserAvatar(teamMember: member, size: 20)
                        }
                        if taskTeamMembers.count > 3 {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.tertiaryText)
                                    .frame(width: 20, height: 20)
                                Text("+\(taskTeamMembers.count - 3)")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .overlay(
                                Circle()
                                    .stroke(OPSStyle.Colors.background, lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                editingTaskIndex = index
                showingTaskForm = true
            }

            // Delete button (separate, on the right)
            Button(action: {
                localTasks.remove(at: index)
                #if !targetEnvironment(simulator)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            }) {
                Image(systemName: "trash")
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .font(.system(size: 16))
                    .padding(.trailing, 16)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private var photosSection: some View {
        ExpandableSection(
            title: "PROJECT PHOTOS",
            icon: "photo",
            isExpanded: $isPhotosExpanded,
            onDelete: {
                projectImages.removeAll()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isPhotosExpanded = false
                }
                #if !targetEnvironment(simulator)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                #endif
            }
        ) {
            if !projectImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(projectImages.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipped()
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(alignment: .topTrailing) {
                                    Button(action: { removeImage(at: index) }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 24, height: 24)
                                            .background(
                                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                    .fill(Color.black.opacity(0.7))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                    .padding(6)
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

    // MARK: - Preview Card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            // Title
                            Text(title.isEmpty ? "PROJECT NAME" : title.uppercased())
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(title.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                                .lineLimit(1)

                            // Client name
                            Text(selectedClient?.name ?? "NO CLIENT SELECTED")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(selectedClient == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer()
                    }

                    // Metadata row
                    HStack(spacing: 12) {
                        // Address
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle")
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(address.isEmpty ? "NO ADDRESS" : address.components(separatedBy: ",").first ?? address)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .lineLimit(1)
                        }

                        // Date
                        if let startDate = startDate {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 11))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                Text(DateHelper.simpleDateString(from: startDate))
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }

                        Spacer()
                    }
                }
                .padding(14)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .overlay(
                // Badge stack - right side
                VStack(alignment: .trailing, spacing: 0) {
                    // Status badge - top
                    Text(selectedStatus.displayName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(selectedStatus.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedStatus.color.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(selectedStatus.color, lineWidth: 1)
                        )

                    Spacer()

                    // Task count badge
                    if !localTasks.isEmpty {
                        Text("\(localTasks.count) \(localTasks.count == 1 ? "TASK" : "TASKS")")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(OPSStyle.Colors.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(OPSStyle.Colors.secondaryText.opacity(0.3), lineWidth: 1)
                            )

                        Spacer()
                    }

                    // Unscheduled badge
                    if !localTasks.isEmpty && startDate == nil {
                        Text("UNSCHEDULED")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(OPSStyle.Colors.warningStatus.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(OPSStyle.Colors.warningStatus, lineWidth: 1)
                            )
                    } else if !localTasks.isEmpty {
                        Color.clear.frame(height: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(8)
            )
        }
        .opacity(0.7) // Slightly faded to indicate it's a preview
    }

    // MARK: - Helper Methods

    private func handleCopyFromProject(_ copiedData: [String: Any]) {
        // Apply copied data with animation
        if let name = copiedData["name"] as? String {
            title = name
        }

        if let clientId = copiedData["clientId"] as? String {
            selectedClientId = clientId
            if let client = allClients.first(where: { $0.id == clientId }) {
                clientSearchText = client.name
            }
        }

        if let addressValue = copiedData["address"] as? String {
            address = addressValue
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isAddressExpanded = true
            }
        }

        if let descriptionValue = copiedData["description"] as? String {
            description = descriptionValue
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isDescriptionExpanded = true
            }
        }

        if let notesValue = copiedData["notes"] as? String {
            notes = notesValue
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isNotesExpanded = true
            }
        }

        if let taskData = copiedData["tasks"] as? [[String: Any]] {
            let newTasks = taskData.compactMap { taskDict -> LocalTask? in
                guard let taskTypeId = taskDict["taskTypeId"] as? String,
                      let statusRaw = taskDict["status"] as? String,
                      let status = TaskStatus(rawValue: statusRaw) else {
                    return nil
                }
                return LocalTask(id: UUID(), taskTypeId: taskTypeId, customTitle: nil, status: status)
            }
            localTasks.append(contentsOf: newTasks)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isTasksExpanded = true
            }
        }

        #if !targetEnvironment(simulator)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

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
                    #if !targetEnvironment(simulator)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif

                    onSave(project)

                    // Brief delay for graceful dismissal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    #if !targetEnvironment(simulator)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    #endif

                    errorMessage = error.localizedDescription
                    showingError = true
                    isSaving = false
                }
            }
        }
    }

    private func createNewProject() async throws -> Project {
        print("[PROJECT_CREATE] Starting project creation")

        guard let companyId = dataController.currentUser?.companyId,
              let client = selectedClient else {
            print("[PROJECT_CREATE] ❌ Missing required fields")
            throw ProjectError.missingRequiredFields
        }

        let projectId = UUID().uuidString
        print("[PROJECT_CREATE] Creating project locally with ID: \(projectId)")

        let project = Project(
            id: projectId,
            title: title,
            status: selectedStatus
        )

        project.companyId = companyId
        project.client = client
        project.clientId = client.id
        project.projectDescription = description.isEmpty ? nil : description
        project.notes = notes.isEmpty ? "" : notes
        project.address = address.isEmpty ? "" : address
        project.startDate = startDate
        project.endDate = endDate
        project.allDay = true
        project.needsSync = true

        // Gather all unique team member IDs from all tasks
        let taskTeamMemberIds = Set(localTasks.flatMap { task in
            task.teamMemberIds
        })

        // Combine with project-level selected team members
        let allTeamMemberIds = selectedTeamMemberIds.union(taskTeamMemberIds)

        let members = allTeamMembers.filter { allTeamMemberIds.contains($0.id) }
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
            print("[PROJECT_CREATE] ✅ Project saved locally")
        }

        var savedOffline = false

        do {
            print("[PROJECT_CREATE] Creating project in Bubble...")
            let bubbleProjectId = try await Task.timeout(seconds: 5) {
                try await dataController.apiService.createProject(project)
            }
            print("[PROJECT_CREATE] ✅ Project created in Bubble with ID: \(bubbleProjectId)")

            // Update project ID BEFORE creating tasks
            project.id = bubbleProjectId
            project.needsSync = false
            project.lastSyncedAt = Date()

            await MainActor.run {
                try? modelContext.save()
            }

            // Create tasks AFTER project is synced and has Bubble ID
            if !localTasks.isEmpty {
                print("[PROJECT_CREATE] Creating \(localTasks.count) task(s) with project ID: \(bubbleProjectId)")
                for localTask in localTasks {
                    await createTask(for: project, localTask: localTask)
                }
            }

            // Continue with linking and other operations in background
            let capturedDataController = dataController
            let capturedModelContext = modelContext
            let capturedClientId = client.id
            let capturedCompanyId = companyId
            let capturedImages = projectImages

            Task.detached {
                do {
                    print("[PROJECT_CREATE] Linking project to client...")
                    try await capturedDataController.apiService.linkProjectToClient(clientId: capturedClientId, projectId: bubbleProjectId)
                    print("[PROJECT_CREATE] ✅ Project linked to client")

                    print("[PROJECT_CREATE] Linking project to company...")
                    try await capturedDataController.apiService.linkProjectToCompany(companyId: capturedCompanyId, projectId: bubbleProjectId)
                    print("[PROJECT_CREATE] ✅ Project linked to company")

                    if !capturedImages.isEmpty {
                        print("[PROJECT_CREATE] Uploading \(capturedImages.count) project images...")
                        let imageUrls = await capturedDataController.imageSyncManager.saveImages(capturedImages, for: project)
                        print("[PROJECT_CREATE] ✅ Uploaded \(imageUrls.count) images")
                    }
                } catch {
                    print("[PROJECT_CREATE] ⚠️ Background operation failed: \(error)")
                    await MainActor.run {
                        project.needsSync = true
                        try? capturedModelContext.save()
                    }
                }
            }
        } catch is CancellationError {
            savedOffline = true
            print("[PROJECT_CREATE] ⏱️ Network timeout - project saved offline")

            // Create tasks offline with local project ID
            if !localTasks.isEmpty {
                print("[PROJECT_CREATE] Creating \(localTasks.count) task(s) offline with local project ID")
                for localTask in localTasks {
                    await createTask(for: project, localTask: localTask)
                }
            }
        } catch let error as URLError {
            savedOffline = true
            print("[PROJECT_CREATE] ❌ Network error - project saved offline: \(error)")

            // Create tasks offline with local project ID
            if !localTasks.isEmpty {
                print("[PROJECT_CREATE] Creating \(localTasks.count) task(s) offline with local project ID")
                for localTask in localTasks {
                    await createTask(for: project, localTask: localTask)
                }
            }
        } catch let error as APIError {
            print("[PROJECT_CREATE] ❌ API error during project creation: \(error)")
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
                isSaving = false
            }
            return project
        } catch {
            print("[PROJECT_CREATE] ❌ Unexpected error during project creation: \(error)")
            await MainActor.run {
                errorMessage = "Failed to create project: \(error.localizedDescription)"
                showingError = true
                isSaving = false
            }
            return project
        }

        await MainActor.run {
            if savedOffline {
                #if !targetEnvironment(simulator)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                #endif

                errorMessage = "WEAK/NO CONNECTION, QUEUING FOR LATER SYNC. SAVED LOCALLY"
                showingError = true
                isSaving = false
            } else {
                isSaving = false
            }
        }

        print("[PROJECT_CREATE] ✅ Project creation complete")
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

            // Gather all unique team member IDs from all tasks
            let taskTeamMemberIds = Set(localTasks.flatMap { task in
                task.teamMemberIds
            })

            // Combine with project-level selected team members
            let allTeamMemberIds = selectedTeamMemberIds.union(taskTeamMemberIds)

            let members = allTeamMembers.filter { allTeamMemberIds.contains($0.id) }
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

    private func createTask(for project: Project, localTask: LocalTask) async {
        guard let companyId = dataController.currentUser?.companyId else {
            print("[TASK_CREATE] ❌ No company ID available")
            return
        }

        guard let taskType = allTaskTypes.first(where: { $0.id == localTask.taskTypeId }) else {
            print("[TASK_CREATE] ❌ Task type not found: \(localTask.taskTypeId)")
            return
        }

        let taskId = UUID().uuidString
        print("[TASK_CREATE] Creating task with ID: \(taskId)")

        let task = ProjectTask(
            id: taskId,
            projectId: project.id,
            taskTypeId: localTask.taskTypeId,
            companyId: companyId,
            status: localTask.status,
            taskColor: taskType.color
        )

        // Store custom title if provided
        if let customTitle = localTask.customTitle {
            task.customTitle = customTitle
        }

        task.project = project
        task.taskType = taskType

        // Use task-specific team members if any, otherwise inherit from project
        if !localTask.teamMemberIds.isEmpty {
            let taskMembers = allTeamMembers.filter { localTask.teamMemberIds.contains($0.id) }
            task.teamMembers = taskMembers.map { member in
                let user = User(
                    id: member.id,
                    firstName: member.firstName,
                    lastName: member.lastName,
                    role: UserRole(rawValue: member.role.lowercased()) ?? .fieldCrew,
                    companyId: companyId
                )
                user.email = member.email
                return user
            }
            task.setTeamMemberIds(localTask.teamMemberIds)
        } else {
            task.teamMembers = project.teamMembers
            task.setTeamMemberIds(project.teamMembers.map { $0.id })
        }

        await MainActor.run {
            modelContext.insert(task)
            try? modelContext.save()
            print("[TASK_CREATE] ✅ Task saved locally")
        }

        // Sync task to Bubble immediately
        do {
            print("[TASK_CREATE] 🔄 Syncing task to Bubble...")
            let taskDTO = TaskDTO(
                id: taskId,
                calendarEventId: nil,  // Will be set after calendar event creation
                companyId: companyId,
                completionDate: nil,
                projectId: project.id,
                scheduledDate: nil,
                status: localTask.status.rawValue,
                taskColor: taskType.color,
                taskIndex: nil,
                taskNotes: nil,
                teamMembers: task.teamMembers.map { $0.id },
                type: localTask.taskTypeId,
                createdDate: nil,
                modifiedDate: nil,
                deletedAt: nil
            )

            let _ = try await dataController.apiService.createTask(taskDTO)
            print("[TASK_CREATE] ✅ Task synced to Bubble")
        } catch {
            print("[TASK_CREATE] ⚠️ Failed to sync task to Bubble: \(error)")
            await MainActor.run {
                task.needsSync = true
                try? modelContext.save()
            }
        }

        // Create calendar event for the task if dates exist
        if let startDate = project.startDate, let endDate = project.endDate {
            let calendarEventId = UUID().uuidString

            let eventTitle = localTask.customTitle ?? taskType.display

            // Task-only scheduling migration: type parameter removed
            let calendarEvent = CalendarEvent(
                id: calendarEventId,
                projectId: project.id,
                companyId: companyId,
                title: eventTitle,
                startDate: startDate,
                endDate: endDate,
                color: taskType.color
            )

            calendarEvent.taskId = taskId
            calendarEvent.setTeamMemberIds(task.teamMembers.map { $0.id })
            calendarEvent.teamMembers = task.teamMembers

            task.calendarEvent = calendarEvent
            task.calendarEventId = calendarEventId

            await MainActor.run {
                modelContext.insert(calendarEvent)
                try? modelContext.save()
                print("[TASK_CREATE] ✅ Calendar event created locally")
            }

            // Sync calendar event to Bubble immediately
            do {
                print("[TASK_CREATE] 🔄 Syncing calendar event to Bubble...")
                let formatter = ISO8601DateFormatter()
                let calendarEventDTO = CalendarEventDTO(
                    id: calendarEventId,
                    color: taskType.color,
                    companyId: companyId,
                    projectId: project.id,
                    taskId: taskId,
                    duration: 1,
                    endDate: formatter.string(from: endDate),
                    startDate: formatter.string(from: startDate),
                    teamMembers: task.teamMembers.map { $0.id },
                    title: eventTitle,
                    createdDate: nil,
                    modifiedDate: nil,
                    deletedAt: nil
                )

                let _ = try await dataController.apiService.createAndLinkCalendarEvent(calendarEventDTO)
                print("[TASK_CREATE] ✅ Calendar event synced to Bubble")
            } catch {
                print("[TASK_CREATE] ⚠️ Failed to sync calendar event to Bubble: \(error)")
                await MainActor.run {
                    calendarEvent.needsSync = true
                    try? modelContext.save()
                }
            }
        }

        print("[TASK_CREATE] ✅ Task creation complete")
    }
}

// MARK: - Expandable Section Component

struct ExpandableSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    let onDelete: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(title: String, icon: String = "square.grid.2x2", isExpanded: Binding<Bool>, onDelete: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self._isExpanded = isExpanded
        self.onDelete = onDelete
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                // Header with icon and title inside the border
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(title)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    if let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                // Divider between header and content
                Divider()
                    .background(Color.white.opacity(0.1))

                // Content area
                VStack(spacing: 0) {
                    content()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }
}

// MARK: - Simple Task Form Sheet

struct SimpleTaskFormSheet: View {
    let allTaskTypes: [TaskType]
    let allTeamMembers: [TeamMember]
    let editingTask: LocalTask?
    let onSave: (LocalTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTaskTypeId: String?
    @State private var customTitle: String = ""
    @State private var selectedStatus: TaskStatus = .booked
    @State private var useCustomTitle: Bool = false
    @State private var selectedTeamMemberIds: Set<String> = []

    init(allTaskTypes: [TaskType], allTeamMembers: [TeamMember], editingTask: LocalTask? = nil, onSave: @escaping (LocalTask) -> Void) {
        self.allTaskTypes = allTaskTypes
        self.allTeamMembers = allTeamMembers
        self.editingTask = editingTask
        self.onSave = onSave

        if let task = editingTask {
            _selectedTaskTypeId = State(initialValue: task.taskTypeId)
            _customTitle = State(initialValue: task.customTitle ?? "")
            _selectedStatus = State(initialValue: task.status)
            _useCustomTitle = State(initialValue: task.customTitle != nil)
            _selectedTeamMemberIds = State(initialValue: Set(task.teamMemberIds))
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Task Type Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TASK TYPE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            if allTaskTypes.isEmpty {
                                Text("No task types available. Contact your admin to add task types.")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .padding()
                            } else {
                                VStack(spacing: 1) {
                                    ForEach(allTaskTypes, id: \.id) { taskType in
                                        Button(action: {
                                            selectedTaskTypeId = taskType.id
                                        }) {
                                            HStack(spacing: 12) {
                                                if let icon = taskType.icon {
                                                    Image(systemName: icon)
                                                        .font(.system(size: 18))
                                                        .foregroundColor(Color(hex: taskType.color))
                                                        .frame(width: 24)
                                                }

                                                Text(taskType.display)
                                                    .font(OPSStyle.Typography.body)
                                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                                Spacer()

                                                if selectedTaskTypeId == taskType.id {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                                } else {
                                                    Image(systemName: "circle")
                                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                }
                                            }
                                            .padding(12)
                                            .background(
                                                selectedTaskTypeId == taskType.id
                                                    ? OPSStyle.Colors.primaryAccent.opacity(0.1)
                                                    : OPSStyle.Colors.background
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                        }

                        // Custom Title Toggle
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $useCustomTitle) {
                                Text("USE CUSTOM TITLE")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .tint(OPSStyle.Colors.primaryAccent)

                            if useCustomTitle {
                                TextField("Enter custom task title", text: $customTitle)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.words)
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                        }

                        // Status Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("STATUS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Menu {
                                ForEach(TaskStatus.allCases, id: \.self) { status in
                                    Button(action: {
                                        selectedStatus = status
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
                            }
                        }

                        // Team Member Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ASSIGN TEAM (OPTIONAL)")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            if !allTeamMembers.isEmpty {
                                VStack(spacing: 1) {
                                    ForEach(allTeamMembers, id: \.id) { member in
                                        Button(action: {
                                            if selectedTeamMemberIds.contains(member.id) {
                                                selectedTeamMemberIds.remove(member.id)
                                            } else {
                                                selectedTeamMemberIds.insert(member.id)
                                            }
                                        }) {
                                            HStack(spacing: 12) {
                                                Circle()
                                                    .fill(OPSStyle.Colors.primaryAccent)
                                                    .frame(width: 32, height: 32)
                                                    .overlay(
                                                        Text(member.initials)
                                                            .font(.system(size: 12, weight: .semibold))
                                                            .foregroundColor(.white)
                                                    )

                                                Text("\(member.firstName) \(member.lastName)")
                                                    .font(OPSStyle.Typography.body)
                                                    .foregroundColor(OPSStyle.Colors.primaryText)

                                                Spacer()

                                                if selectedTeamMemberIds.contains(member.id) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                                } else {
                                                    Image(systemName: "circle")
                                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                }
                                            }
                                            .padding(12)
                                            .background(
                                                selectedTeamMemberIds.contains(member.id)
                                                    ? OPSStyle.Colors.primaryAccent.opacity(0.1)
                                                    : OPSStyle.Colors.background
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            } else {
                                Text("No team members available")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    .padding()
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(editingTask == nil ? "ADD TASK" : "EDIT TASK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        var task = LocalTask(
                            id: editingTask?.id ?? UUID(),
                            taskTypeId: selectedTaskTypeId!,
                            customTitle: useCustomTitle && !customTitle.isEmpty ? customTitle : nil,
                            status: selectedStatus
                        )
                        task.teamMemberIds = Array(selectedTeamMemberIds)
                        onSave(task)
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(selectedTaskTypeId != nil ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .disabled(selectedTaskTypeId == nil)
                }
            }
        }
    }
}

// MARK: - Local Task Model

struct LocalTask: Identifiable, Equatable {
    let id: UUID
    var taskTypeId: String
    var customTitle: String?
    var status: TaskStatus
    var teamMemberIds: [String] = []

    static func == (lhs: LocalTask, rhs: LocalTask) -> Bool {
        lhs.id == rhs.id &&
        lhs.taskTypeId == rhs.taskTypeId &&
        lhs.customTitle == rhs.customTitle &&
        lhs.status == rhs.status &&
        lhs.teamMemberIds == rhs.teamMemberIds
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
