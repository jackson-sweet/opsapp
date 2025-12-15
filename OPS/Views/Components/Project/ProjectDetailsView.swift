//
//  ProjectDetailsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-25.
//

import SwiftUI
import UIKit
import MapKit
import CoreLocation
// Import team member components

struct ProjectDetailsView: View {
    @Bindable var project: Project
    var isEditMode: Bool = false
    @Environment(\.dismiss) var dismiss
    @State private var noteText: String
    @State private var originalNoteText: String
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var appState: AppState
    @State private var showingPhotoViewer = false
    @State private var selectedPhotoIndex: Int = 0
    @State private var showingImagePicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var processingImages = false
    @State private var showingNetworkError = false
    @State private var networkErrorMessage = ""
    // REMOVED: No longer tracking photo deletion state
    @State private var showingUnsavedChangesAlert = false
    @State private var showingClientContact = false
    @State private var isRefreshingClient = false
    @State private var showingScheduler = false
    @State private var showingAddressEditor = false
    @State private var editedAddress: String = ""
    @State private var isEditingAddress = false  // Inline address editing mode
    @State private var addressMapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var isGeocodingAddress = false
    @State private var addressDebounceTask: Task<Void, Never>?
    @StateObject private var addressSearchCompleter = AddressSearchCompleter()
    @State private var showingCompletionSheet = false
    @State private var showingCompletionAlert = false
    @State private var showingDeleteAlert = false
    @State private var refreshTrigger = false  // Toggle to force view refresh
    @State private var isNotesExpanded = false
    @State private var isEditingTitle = false
    @State private var editedTitle: String = ""
    @State private var showingAddTaskSheet = false
    @State private var selectedTeamMember: User? = nil
    @State private var isTeamExpanded = false

    // Initialize with project's existing notes
    init(project: Project, isEditMode: Bool = false) {
        self._project = Bindable(wrappedValue: project)
        self.isEditMode = isEditMode
        let notes = project.notes ?? ""
        self._noteText = State(initialValue: notes)
        self._originalNoteText = State(initialValue: notes)

        // Initialize address map region to project's location
        if let coordinate = project.coordinate {
            self._addressMapRegion = State(initialValue: MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
        
        // Debug output to help troubleshoot issues
        
        // New debug output for navigation
        
        // Debug project team member information
        
        // Team member debugging removed - no longer needed
        
        // Convert project to JSON for complete debugging
        do {
            let projectDict: [String: Any] = [
                "id": project.id,
                "title": project.title,
                "clientName": project.effectiveClientName,
                "address": project.address ?? "",
                "status": project.status.rawValue,
                "teamMemberIdsString": project.teamMemberIdsString,
                "teamMemberIds": project.getTeamMemberIds(),
                "teamMembersCount": project.teamMembers.count,
                "projectImagesCount": project.getProjectImages().count,
                "needsSync": project.needsSync,
                "startDate": project.startDate?.description ?? "nil",
                "endDate": project.endDate?.description ?? "nil"
            ]
            
            let _ = try JSONSerialization.data(withJSONObject: projectDict, options: .prettyPrinted)
            // JSON debugging removed - no longer needed
        } catch {
        }
    }
    
    var body: some View {
        mainView
            .navigationBarHidden(true)
            .overlay(saveNotificationOverlay)
            .fullScreenCover(isPresented: $showingPhotoViewer) {
                photoViewerContent
            }
            .sheet(isPresented: $showingImagePicker) {
                imagePickerContent
            }
            .confirmationDialog(
                "Unsaved Changes",
                isPresented: $showingUnsavedChangesAlert,
                titleVisibility: .visible
            ) {
                unsavedChangesButtons
            } message: {
                Text("You have unsaved changes to your notes. Would you like to save them before leaving?")
            }
            .onAppear(perform: handleOnAppear)
            .onDisappear(perform: handleOnDisappear)
            .alert("Network Error", isPresented: $showingNetworkError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(networkErrorMessage)
            }
            .sheet(isPresented: $showingClientContact) {
                clientContactSheet
            }
            .sheet(item: $selectedTeamMember) { member in
                ContactDetailView(user: member)
                    .environmentObject(dataController)
            }
            .sheet(isPresented: $showingScheduler) {
                CalendarSchedulerSheet(
                    isPresented: $showingScheduler,
                    itemType: .project(project),
                    currentStartDate: project.startDate,
                    currentEndDate: project.endDate,
                    onScheduleUpdate: { startDate, endDate in
                        handleScheduleUpdate(startDate: startDate, endDate: endDate)
                    },
                    onClearDates: {
                        handleClearDates()
                    }
                )
                .environmentObject(dataController)
            }
            .sheet(isPresented: $showingCompletionSheet) {
                TaskCompletionChecklistSheet(project: project, onComplete: {
                    markProjectComplete()
                })
                .environmentObject(dataController)
            }
            .sheet(isPresented: $showingAddressEditor) {
                AddressEditorSheet(
                    address: $editedAddress,
                    onSave: {
                        saveAddress()
                    },
                    onCancel: {
                        showingAddressEditor = false
                    }
                )
            }
            .sheet(isPresented: $showingAddTaskSheet) {
                TaskFormSheet(
                    mode: .create,
                    preselectedProjectId: project.id,
                    onSave: { _ in
                        // No manual refresh needed - @Bindable project automatically updates when tasks change
                    }
                )
                .environmentObject(dataController)
            }
    }

    // MARK: - Main View Components

    private var mainView: some View {
        ZStack {
            Color.black
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                headerView
                scrollableContent
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 6) {
            headerTopRow
            headerTitleRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .background(Color.black)
    }

    private var headerTopRow: some View {
        HStack {
            StatusBadge.forJobStatus(project.status)

            Spacer()

            doneButton
        }
    }

    private var doneButton: some View {
        Button("Done") {
            checkForUnsavedChanges()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white)
        .foregroundColor(Color.black)
        .cornerRadius(OPSStyle.Layout.buttonRadius)
        .font(OPSStyle.Typography.bodyBold)
    }

    private var headerTitleRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row
            HStack {
                if isEditingTitle {
                    TextField("Project Title", text: $editedTitle)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                        .textFieldStyle(PlainTextFieldStyle())
                        .submitLabel(.done)
                        .onSubmit {
                            saveTitle()
                        }
                } else {
                    Text(project.title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Spacer()
            }

            // Client name
            Text(project.effectiveClientName.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineLimit(1)

            // Metadata row
            HStack(spacing: 12) {
                // Address
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle")
                        .font(.system(size: 11))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(project.address?.components(separatedBy: ",").first ?? "No address")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }

                // Calendar icon + date
                HStack(spacing: 4) {
                    Image(systemName: OPSStyle.Icons.calendar)
                        .font(.system(size: 11))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    if let startDate = project.computedStartDate {
                        Text(DateHelper.simpleDateString(from: startDate))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    } else {
                        Text("—")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                // Team icon + count
                HStack(spacing: 4) {
                    Image(systemName: OPSStyle.Icons.personTwo)
                        .font(.system(size: 11))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("\(project.teamMembers.count)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                // Task icon + count
                HStack(spacing: 4) {
                    Image(systemName: OPSStyle.Icons.task)
                        .font(.system(size: 11))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("\(project.tasks.count)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()
            }
        }
    }

    private var scrollableContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                locationSection
                projectInfoSection
                tasksSection
                photosSection

                if project.status != .completed && project.status != .closed {
                    Spacer()
                        .frame(height: 40)

                    completeButton
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if project.status == .completed {
                    Spacer()
                        .frame(height: 40)

                    closeJobButton
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if canEditProjectSettings() {
                    deleteButton
                }
            }
            .padding(.top, 16)
            .animation(.easeInOut(duration: 0.3), value: project.status)
        }
    }

    // MARK: - Sheet Contents

    private var photoViewerContent: some View {
        FullScreenPhotoViewer(
            photos: project.getProjectImages(),
            initialIndex: selectedPhotoIndex,
            onDismiss: { showingPhotoViewer = false }
        )
    }

    private var imagePickerContent: some View {
        ImagePicker(
            images: $selectedImages,
            allowsEditing: false,
            selectionLimit: 10,
            onSelectionComplete: {
                showingImagePicker = false

                if !selectedImages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        addPhotosToProject()
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var unsavedChangesButtons: some View {
        Button("Save Changes", role: .none) {
            saveNotes()
            dismiss()
        }

        Button("Discard Changes", role: .destructive) {
            dismiss()
        }

        Button("Cancel", role: .cancel) { }
    }

    @ViewBuilder
    private var clientContactSheet: some View {
        if let client = project.client {
            ContactDetailView(client: client, project: project)
                .presentationDragIndicator(.visible)
                .environmentObject(dataController)
        } else {
            let clientTeamMember = TeamMember(
                id: "client-\(project.id)",
                firstName: project.effectiveClientName.components(separatedBy: " ").first ?? project.effectiveClientName,
                lastName: project.effectiveClientName.components(separatedBy: " ").dropFirst().joined(separator: " "),
                role: "Client",
                avatarURL: nil,
                email: project.effectiveClientEmail,
                phone: project.effectiveClientPhone
            )

            ContactDetailView(teamMember: clientTeamMember)
                .presentationDragIndicator(.visible)
                .environmentObject(dataController)
        }
    }

    // MARK: - Actions

    private func handleOnAppear() {
        // Track screen view for analytics
        AnalyticsManager.shared.trackScreenView(screenName: .projectDetails, screenClass: "ProjectDetailsView")

        DispatchQueue.main.async {
            if let appState = dataController.appState {
                if InProgressManager.shared.isRouting && appState.activeProjectID != project.id {
                    appState.activeProjectID = project.id
                }
            }
        }

        locationManager.requestPermissionIfNeeded()

        if let clientId = project.clientId, !clientId.isEmpty {
            refreshClientData(clientId: clientId, forceRefresh: true)
        }

        // NOTE: Team members are computed from tasks during sync (CentralizedSyncManager)
        // and when tasks are modified (TaskFormSheet). Do NOT compute here as it
        // causes view dismissal due to model changes during onAppear.
    }

    private func handleOnDisappear() {
        notificationTimer?.invalidate()
        notificationTimer = nil
    }

    private func handleScheduleUpdate(startDate: Date, endDate: Date) {
        print("🔄 handleScheduleUpdate called - New dates: \(startDate) to \(endDate)")

        // Update project dates using centralized function
        Task {
            do {
                try await dataController.updateProjectDates(project: project, startDate: startDate, endDate: endDate)
                print("✅ Project dates updated and synced")

                // Force view refresh to show updated dates
                await MainActor.run {
                    refreshTrigger.toggle()
                }
            } catch {
                print("❌ Failed to sync schedule update: \(error)")
            }
        }
    }

    private func handleClearDates() {
        print("🗑️ handleClearDates called - Clearing project dates")

        Task {
            do {
                // Clear project dates using centralized function
                try await dataController.updateProjectDates(project: project, startDate: nil, endDate: nil, clearDates: true)
                print("✅ Project dates cleared and synced")

                // Force view refresh to show cleared dates
                await MainActor.run {
                    refreshTrigger.toggle()
                    // Notify calendar views to refresh
                    dataController.calendarEventsDidChange.toggle()
                }
            } catch {
                print("❌ Failed to clear dates: \(error)")
            }
        }
    }


    // Project header section with title and date
    private var projectHeaderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Project title with task count if applicable
            HStack(alignment: .top, spacing: 12) {
                Text(project.title)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)

                // Show task count if project has tasks
                if !project.tasks.isEmpty {
                    Text("\(project.tasks.count) \(project.tasks.count == 1 ? "TASK" : "TASKS")")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(OPSStyle.Colors.cardBackgroundDark)
                        )
                        .padding(.top, 4)
                }

                Spacer()
            }

            // Client info
            VStack(alignment: .leading, spacing: 4) {
                Text("CLIENT")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text(project.effectiveClientName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
            }
        }
    }
    
    // Location map
    private var locationSection: some View {
        SectionCard(
            icon: OPSStyle.Icons.jobSite,
            title: "Location",
            actionIcon: "arrow.triangle.turn.up.right.circle.fill",
            actionLabel: "Directions",
            onAction: {
                openInMaps(coordinate: project.coordinate, address: project.address ?? "")
            }
        ) {
            VStack(spacing: 16) {

            // Address field
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ADDRESS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()

                    // Edit button for admin/office crew
                    if canEditProjectSettings() && !isEditingAddress {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                editedAddress = project.address ?? ""
                                isEditingAddress = true
                            }
                        }) {
                            Image(systemName: OPSStyle.Icons.pencil)
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }

                    // Save/Cancel buttons when editing
                    if isEditingAddress {
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editedAddress = project.address ?? ""
                                    isEditingAddress = false
                                }
                                addressSearchCompleter.clear()
                            }
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Button("Save") {
                                saveAddress()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingAddress = false
                                }
                                addressSearchCompleter.clear()
                            }
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                }

                if isEditingAddress {
                    VStack(spacing: 0) {
                        // Editable TextField with autocomplete
                        TextField("Enter address", text: $editedAddress)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.9))
                            .textContentType(.fullStreetAddress)
                            .autocorrectionDisabled(true)
                            .submitLabel(.done)
                            .padding(12)
                            .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .onSubmit {
                                if editedAddress != project.address {
                                    saveAddress()
                                }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingAddress = false
                                }
                                addressSearchCompleter.clear()
                            }
                            .onChange(of: editedAddress) { oldValue, newValue in
                                // Update search suggestions
                                addressSearchCompleter.searchFragment = newValue

                                // Debounce geocoding for map update
                                addressDebounceTask?.cancel()
                                addressDebounceTask = Task {
                                    try? await Task.sleep(nanoseconds: 800_000_000)
                                    if !Task.isCancelled && !newValue.isEmpty {
                                        await geocodeAddressInline(newValue)
                                    }
                                }
                            }

                        // Address suggestions dropdown
                        if !addressSearchCompleter.results.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(addressSearchCompleter.results, id: \.self) { result in
                                    Button(action: {
                                        selectAddressSuggestion(result)
                                    }) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(result.title)
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(OPSStyle.Colors.primaryText)
                                            if !result.subtitle.isEmpty {
                                                Text(result.subtitle)
                                                    .font(OPSStyle.Typography.caption)
                                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if result != addressSearchCompleter.results.last {
                                        Divider()
                                            .background(OPSStyle.Colors.secondaryText.opacity(0.2))
                                    }
                                }
                            }
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .padding(.top, 4)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    // Read-only text
                    Text(project.address ?? "No address")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isEditingAddress)

            // Map view - larger and more prominent
            ZStack(alignment: .bottomTrailing) {
                MiniMapView(
                    coordinate: isEditingAddress ? addressMapRegion.center : project.coordinate,
                    address: isEditingAddress ? editedAddress : (project.address ?? "")
                ) {
                    openInMaps(
                        coordinate: isEditingAddress ? addressMapRegion.center : project.coordinate,
                        address: isEditingAddress ? editedAddress : (project.address ?? "")
                    )
                }
                .frame(height: 180)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                
                
                // Directions button on map
                Button(action: {
                    openInMaps(
                        coordinate: isEditingAddress ? addressMapRegion.center : project.coordinate,
                        address: isEditingAddress ? editedAddress : (project.address ?? "")
                    )
                }) {
                    HStack {
                        // NOTE: Missing icon in OPSStyle - "arrow.triangle.turn.up.right.diamond.fill" (directions)
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 14))

                        Text("Directions")
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(OPSStyle.Colors.cardBackground)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .padding(12)
            }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Info Sections

    // Project Info section - groups client, schedule, description, notes, team fields
    private var projectInfoSection: some View {
        SectionCard(
            icon: "doc.text",
            title: "Project Details"
        ) {
            VStack(spacing: 16) {
                // Client field
                clientField

                // Schedule field
                scheduleField

                // Description field (only if exists)
                if let description = project.projectDescription, !description.isEmpty {
                    descriptionField
                }

                // Team Notes field
                teamNotesField

                // Assigned Team field
                assignedTeamField
            }
        }
        .padding(.horizontal)
        .id(refreshTrigger)
    }

    private var clientField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIENT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button(action: {
                showingClientContact = true
            }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.effectiveClientName)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        // Show email if available
                        if let email = project.effectiveClientEmail {
                            Text(email)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }

                    Spacer()

                    // Contact indicators
                    HStack(spacing: 8) {
                        Image(systemName: OPSStyle.Icons.phoneFill)
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .opacity(project.effectiveClientPhone != nil ? 1.0 : 0.3)

                        Image(systemName: OPSStyle.Icons.envelopeFill)
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .opacity(project.effectiveClientEmail != nil ? 1.0 : 0.3)
                    }

                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var scheduleField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCHEDULE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(alignment: .leading, spacing: 0) {
                if project.tasks.isEmpty {
                    // No tasks - show create prompt
                    HStack(spacing: 8) {
                        Text("No tasks to schedule. Create one?")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Spacer()
                        
                        Button(action: {
                            showingAddTaskSheet = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                Text("Add Task")
                                    .font(OPSStyle.Typography.caption)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                } else if project.computedStartDate == nil {
                    HStack(){
                        // Has tasks but not scheduled
                        Text("Not Scheduled")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                    }
                    } else {
                    // Has scheduled tasks
                    HStack(spacing: 16) {
                        // Start date
                        VStack(alignment: .leading, spacing: 4) {
                            Text("START DATE")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            if let startDate = project.computedStartDate {
                                Text(formatDate(startDate))
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                        }

                        Spacer()

                        // End date (only show if valid)
                        if let endDate = project.computedEndDate,
                           let startDate = project.computedStartDate,
                           endDate >= startDate {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("END DATE")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                                Text(formatDate(endDate))
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
            )
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DESCRIPTION")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text(project.projectDescription ?? "")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                )
        }
    }

    private var teamNotesField: some View {
        NotesDisplayField(
            title: "Team Notes",
            notes: project.notes ?? "",
            isExpanded: $isNotesExpanded,
            editedNotes: $noteText,
            canEdit: true,  // All users including field crew can edit team notes
            onSave: saveNotes
        )
    }

    private var assignedTeamField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ASSIGNED TEAM")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(alignment: .leading, spacing: 0) {
                if project.tasks.isEmpty {
                    // No tasks - show create prompt
                    HStack(spacing: 8) {
                        Text("No tasks to assign to. Create one?")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Spacer()
                        
                        Button(action: {
                            showingAddTaskSheet = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                Text("Add Task")
                                    .font(OPSStyle.Typography.caption)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                } else if project.teamMembers.isEmpty {
                    
                    HStack(){
                        // Has tasks but no team assigned
                        Text("No team assigned")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                    }
                    
                    
                } else {
                    // Has team members
                    let displayedMembers = isTeamExpanded ? project.teamMembers : Array(project.teamMembers.prefix(3))
                    let hiddenCount = project.teamMembers.count - 3

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayedMembers.enumerated()), id: \.element.id) { index, member in
                            Button(action: {
                                selectedTeamMember = member
                            }) {
                                HStack(spacing: 12) {
                                    UserAvatar(user: member, size: 32)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(member.fullName)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)

                                        Text(member.role.displayName)
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }

                                    Spacer()

                                    Image(systemName: OPSStyle.Icons.chevronRight)
                                        .font(.system(size: 12))
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Add divider between items (not after last one)
                            if index < displayedMembers.count - 1 {
                                Divider()
                                    .background(OPSStyle.Colors.inputFieldBorder.opacity(0.5))
                            }
                        }

                        // Show more/less button when there are more than 3 members
                        if hiddenCount > 0 {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isTeamExpanded.toggle()
                                }
                            }) {
                                HStack {
                                    Text(isTeamExpanded ? "Show less" : "+\(hiddenCount) more")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)

                                    Spacer()

                                    Image(systemName: isTeamExpanded ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                                        .font(.system(size: 12))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                                .padding(.top, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
    }

    // Notes section (DEPRECATED - now in projectInfoSection)
    private var notesSection: some View {
        SectionCard(
            icon: OPSStyle.Icons.notes,
            title: "Project Notes",
            contentPadding: EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16)
        ) {
            VStack(spacing: 0) {
                // Expand/collapse button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isNotesExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text(isNotesExpanded ? "Hide Notes" : "Show Notes")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                        Spacer()

                        Image(systemName: isNotesExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.vertical, 12)

                // Expandable notes content
                if isNotesExpanded {
                    Divider()
                        .background(OPSStyle.Colors.cardBorder)
                        .padding(.bottom, 12)

                    ExpandableNotesView(
                        notes: project.notes ?? "",
                        isExpanded: $isNotesExpanded,
                        editedNotes: $noteText,
                        onSave: saveNotes
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    // Project info (DEPRECATED - now split into individual sections)
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Card-based info items
            VStack(spacing: 1) {
                // Client card with tap interaction
                Button(action: {
                    showingClientContact = true
                }) {
                    HStack {
                        infoRow(
                            icon: "person",
                            title: "CLIENT",
                            value: project.effectiveClientName.uppercased(),
                            valueColor: OPSStyle.Colors.primaryText,
                            showChevron: true
                        )
                        
                        // Always show contact indicators with availability status
                        HStack(spacing: 6) {
                            Image(systemName: OPSStyle.Icons.phoneFill)
                                .font(.system(size: 18))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .opacity(project.effectiveClientPhone != nil ? 1.0 : 0.2)

                            Image(systemName: OPSStyle.Icons.envelopeFill)
                                .font(.system(size: 18))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .opacity(project.effectiveClientEmail != nil ? 1.0 : 0.2)
                        }
                        .padding(.trailing, 12)
                        
                    }.background(OPSStyle.Colors.cardBackgroundDark)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Dates row - show computed dates from tasks
                HStack(spacing: 0) {
                    // Start date (show computed date from tasks)
                    HStack(spacing: 12) {
                        Image(systemName: OPSStyle.Icons.schedule)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("START DATE")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            if let startDate = project.computedStartDate {
                                Text(formatDate(startDate))
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            } else {
                                Text("No scheduled tasks")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // End date (only show if valid - exists and on or after start date)
                    if let endDate = project.computedEndDate,
                       let startDate = project.computedStartDate,
                       endDate >= startDate {
                        HStack(spacing: 12) {
                            Image(systemName: OPSStyle.Icons.calendarBadgeCheckmark)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("COMPLETION DATE")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Text(formatDate(endDate))
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .id(refreshTrigger)  // Force refresh when dates change
                
                // Description card
                if let description = project.projectDescription, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: OPSStyle.Icons.description)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .frame(width: 24)
                            
                            Text("DESCRIPTION")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        
                        Text(description)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                }
                
                // Notes section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: OPSStyle.Icons.notes)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 24)

                        Text("PROJECT NOTES")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Spacer()

                        Image(systemName: isNotesExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isNotesExpanded.toggle()
                        }
                    }

                    // Expandable notes view
                    ExpandableNotesView(
                        notes: project.notes ?? "",
                        isExpanded: $isNotesExpanded,
                        editedNotes: $noteText,
                        onSave: saveNotes
                    )
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OPSStyle.Colors.cardBackgroundDark)
            }
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
    
    // Helper to get color for status - using the OPSStyle's official status colors
    private func getStatusColor(_ status: Status) -> Color {
        return OPSStyle.Colors.statusColor(for: status)
    }
    
    // Helper to create consistent info rows
    private func infoRow(icon: String, title: String, value: String, valueColor: Color = .white, showChevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 24)
            
            // Title and value
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(value)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(valueColor)
            }
            
            Spacer()

            if showChevron {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
    }
    // Photos section with improved styling
    private var photosSection: some View {
        SectionCard(
            icon: OPSStyle.Icons.photo,
            title: "Project Photos",
            contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        ) {
            photoContentView
        }
        .padding(.horizontal)
    }
    
    // Photo content view to break up complexity
    private var photoContentView: some View {
        VStack(spacing: 12) {
            // Photo display (empty state or grid)
            photoDisplayView

            // Add photos button
            addPhotosButton
                .padding(.horizontal)

            // Loading indicator for processing images
            if processingImages {
                processingIndicator
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
    
    // Photo display - either empty state or grid of photos
    private var photoDisplayView: some View {
        let photos = project.getProjectImages()

        if photos.isEmpty {
            return AnyView(emptyPhotosView)
        } else {
            return AnyView(
                photoGridView(photos: photos)
            )
        }
    }
    
    // Empty state when no photos
    private var emptyPhotosView: some View {
        VStack(spacing: 16) {
            // NOTE: Missing icon in OPSStyle - "photo.on.rectangle.angled" (empty photo state)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("No photos added yet")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("Tap the button below to add photos to this project")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // Grid view for photos
    private func photoGridView(photos: [String]) -> some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                        photoThumbnailView(url: url, index: index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .frame(height: 142) // 110 image + 32 padding
            
            // Photo count indicator
            HStack {
                // NOTE: Missing icon in OPSStyle - "photo.stack" (photo count indicator)
                Image(systemName: "photo.stack")
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .font(.system(size: 14))
                
                Text("\(photos.count) \(photos.count == 1 ? "photo" : "photos")")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
    
    // Individual photo thumbnail
    private func photoThumbnailView(url: String, index: Int) -> some View {
        PhotoThumbnail(url: url, project: project)
            .frame(width: 110, height: 110)
            .cornerRadius(8)
            .shadow(color: Color.black, radius: 4, x: 0, y: 2)
            .contentShape(Rectangle())
            .onTapGesture { [index] in  // Explicitly capture index
                print("DEBUG: Photo tapped at index \(index)")
                selectedPhotoIndex = index
                showingPhotoViewer = true
            }
            // Simple scale animation on tap
            .hoverEffect(.lift)
    }
    
    // REMOVED: No longer need to track long press for deletion
    
    // Add photos button
    private var addPhotosButton: some View {
        Button(action: {
            showingImagePicker = true
        }) {
            HStack(spacing: 8) {
                // NOTE: Missing icon in OPSStyle - "plus.viewfinder" (add photos)
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 16, weight: .medium))

                Text("ADD PHOTOS")
                    .font(OPSStyle.Typography.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(OPSStyle.Colors.primaryAccent)
            .foregroundColor(.white)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .disabled(processingImages)
        .padding(.horizontal)
    }

    // Processing indicator
    private var processingIndicator: some View {
        HStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
            Text("Processing images...")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.top, 4)
        .padding(.horizontal)
    }
    
    // Save notification overlay
    private var saveNotificationOverlay: some View {
        Group {
            if showingSaveNotification {
                saveNotificationContent
            }
        }
    }
    
    // Content of the save notification
    private var saveNotificationContent: some View {
        VStack {
            Spacer()


            HStack {
                Image(systemName: OPSStyle.Icons.complete)
                    .foregroundColor(OPSStyle.Colors.successStatus)
                    .font(.system(size: 16))
                
                Text("Notes saved")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .shadow(color: Color.black, radius: 5, x: 0, y: 2)
            
            Spacer().frame(height: 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: showingSaveNotification)
        .zIndex(100)
    }
    
    // Tasks section
    private var tasksSection: some View {
        SectionCard(
            icon: OPSStyle.Icons.task,
            title: "Tasks",
            count: project.tasks.count,
            actionIcon: "plus.circle",
            actionLabel: "Add",
            onAction: {
                showingAddTaskSheet = true
            },
            contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        ) {
            TaskListView(project: project)
                .environmentObject(dataController)
                .environmentObject(appState)
        }
        .padding(.horizontal)
    }

    private var completeButton: some View {
        Button(action: {
            let incompleteTasks = project.tasks.filter { $0.status != .completed && $0.status != .cancelled }
            if !incompleteTasks.isEmpty {
                showingCompletionAlert = true
            } else {
                markProjectComplete()
            }
        }) {
            Text("MARK PROJECT COMPLETE")
                .font(OPSStyle.Typography.bodyBold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                )
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .alert("Complete Project", isPresented: $showingCompletionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Complete All") {
                markProjectCompleteWithTasks()
            }
        } message: {
            let incompleteTasks = project.tasks.filter { $0.status != .completed && $0.status != .cancelled }
            Text("This project has \(incompleteTasks.count) incomplete task\(incompleteTasks.count == 1 ? "" : "s"). All incomplete tasks will be marked as completed.")
        }
    }

    private var closeJobButton: some View {
        let closedColor = OPSStyle.Colors.statusColor(for: .closed)
        return Button(action: {
            markProjectClosed()
        }) {
            Text("CLOSE JOB")
                .font(OPSStyle.Typography.bodyBold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundColor(closedColor)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(closedColor, lineWidth: 1)
                )
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var deleteButton: some View {
        Button(action: {
            showingDeleteAlert = true
        }) {
            Text("DELETE PROJECT")
                .font(OPSStyle.Typography.bodyBold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundColor(OPSStyle.Colors.errorStatus)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.errorStatus, lineWidth: 1)
                )
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .deleteConfirmation(
            isPresented: $showingDeleteAlert,
            itemName: "Project",
            message: "Are you sure you want to delete this project? This action cannot be undone.",
            onConfirm: deleteProject
        )
    }

    // Check if user can edit project settings
    private func canEditProjectSettings() -> Bool {
        guard let currentUser = dataController.currentUser else { return false }
        return currentUser.role != .fieldCrew
    }

    private func markProjectComplete() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()

        Task {
            // Auto-complete all incomplete tasks when marking project complete
            let incompleteTasks = project.tasks.filter { $0.status != .completed && $0.status != .cancelled }

            for task in incompleteTasks {
                do {
                    try await dataController.updateTaskStatus(task: task, to: .completed)
                    print("[PROJECT_COMPLETE] ✅ Task \(task.id) marked complete")
                } catch {
                    print("[PROJECT_COMPLETE] ❌ Failed to complete task \(task.id): \(error)")
                }
            }

            // Then update project status
            try? await dataController.syncManager?.updateProjectStatus(
                projectId: project.id,
                status: .completed,
                forceSync: true
            )
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }

    private func markProjectClosed() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()

        // Dismiss first with animation, then update status
        // This prevents the status change from causing view updates during dismissal
        dismiss()

        // Update status after dismissal animation starts
        Task {
            // Small delay to let dismissal animation begin
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            try? await dataController.syncManager?.updateProjectStatus(
                projectId: project.id,
                status: .closed,
                forceSync: true
            )
        }
    }

    private func markProjectCompleteWithTasks() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()

        Task {
            let incompleteTasks = project.tasks.filter { $0.status != .completed && $0.status != .cancelled }

            for task in incompleteTasks {
                do {
                    // Use centralized status update function
                    try await dataController.updateTaskStatus(task: task, to: .completed)
                    print("[PROJECT_COMPLETE] ✅ Task \(task.id) marked complete")
                } catch {
                    print("[PROJECT_COMPLETE] ❌ Failed to sync task \(task.id): \(error)")
                }
            }

            await MainActor.run {
                Task {
                    try? await dataController.syncManager?.updateProjectStatus(
                        projectId: project.id,
                        status: .completed,
                        forceSync: true
                    )
                }
            }

            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func deleteProject() {
        // Capture values needed for deletion before any async work
        let projectId = project.id
        let projectTitle = project.title
        let controller = dataController

        print("[PROJECT_DETAILS] 🗑️ Starting project deletion for: \(projectTitle)")

        // STEP 1: Delete locally FIRST (while view is still valid)
        // This uses the centralized deleteProject which handles local deletion immediately
        Task {
            do {
                // Get a fresh reference and delete
                if let projectToDelete = controller.getProject(id: projectId) {
                    try await controller.deleteProject(projectToDelete)
                    print("[PROJECT_DETAILS] ✅ Project deleted successfully")
                }

                // STEP 2: Dismiss AFTER local deletion is complete
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("[PROJECT_DETAILS] ❌ Failed to delete project: \(error)")
                // Still dismiss on error to avoid stuck state
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }

    // Helper to format date
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    @State private var showingSaveNotification = false
    @State private var notificationTimer: Timer?
    
    private func saveTitle() {
        guard !editedTitle.isEmpty, editedTitle != project.title else {
            isEditingTitle = false
            return
        }

        // Haptic feedback on save
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Update locally and sync to API
        Task {
            do {
                project.title = editedTitle
                project.needsSync = true
                try dataController.modelContext?.save()

                // Sync to API
                let updates = ["title": editedTitle]
                try await dataController.apiService.updateProject(id: project.id, updates: updates)

                await MainActor.run {
                    project.needsSync = false
                    project.lastSyncedAt = Date()
                    try? dataController.modelContext?.save()
                    isEditingTitle = false
                    showSaveNotification()
                }
            } catch {
                print("❌ Failed to save title: \(error)")
            }
        }
    }

    private func saveNotes() {
        // Haptic feedback on save
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Use centralized function for immediate sync
        Task {
            do {
                try await dataController.updateProjectNotes(project: project, notes: noteText)
                await MainActor.run {
                    showSaveNotification()
                }
            } catch {
                print("❌ Failed to save notes: \(error)")
            }
        }
    }
    
    private func showSaveNotification() {
        // Cancel any existing timer
        notificationTimer?.invalidate()
        
        // Show the notification
        showingSaveNotification = true
        
        // Set a timer to hide it after 2 seconds
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            DispatchQueue.main.async {
                showingSaveNotification = false
            }
        }
        
        // Update the original notes to match current notes after saving
        originalNoteText = noteText
    }
    
    private func checkForUnsavedChanges() {
        // Compare current notes with original notes
        if noteText != originalNoteText {
            // We have unsaved changes, show the alert
            showingUnsavedChangesAlert = true
        } else {
            // No changes, dismiss immediately
            dismiss()
        }
    }
    
    // Function to add multiple photos to the project
    private func addPhotosToProject() {
        // Start loading indicator
        processingImages = true
        
        // Debug log
        
        Task {
            do {
                // Use the ImageSyncManager if available
                if let imageSyncManager = dataController.imageSyncManager {
                    // Process all images through the ImageSyncManager
                    let urls = await imageSyncManager.saveImages(selectedImages, for: project)
                    
                    if !urls.isEmpty {
                        // ImageSyncManager already added the images to the project
                        // We just need to clear the UI state
                        
                        await MainActor.run {
                            // Clear selected images and hide loading
                            selectedImages.removeAll()
                            processingImages = false
                        }
                    } else {
                        await MainActor.run {
                            processingImages = false
                            showingNetworkError = true
                            networkErrorMessage = "Failed to upload images to the server. Please check your network connection and try again."
                        }
                    }
                } else {
                    // Fallback to direct processing if ImageSyncManager is not available
                    
                    // Process each image
                    for (_, image) in selectedImages.enumerated() {
                        // Debug log
                        
                        // Compress image
                        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                            continue
                        }
                        
                        // Generate a unique filename
                        let timestamp = Date().timeIntervalSince1970
                        let filename = "project_\(project.id)_\(timestamp)_\(UUID().uuidString).jpg"
                        
                        // Save image data to file system with the key as the URL
                        let localURL = "local://project_images/\(filename)"
                        
                        // Store the image in file system
                        let success = ImageFileManager.shared.saveImage(data: imageData, localID: localURL)
                        if success {
                            
                            // Add to project's images
                            var currentImages = project.getProjectImages()
                            currentImages.append(localURL)
                            
                            await MainActor.run {
                                project.setProjectImageURLs(currentImages)
                                project.needsSync = true
                            }
                        }
                        
                        // Small delay for UI responsiveness
                        if selectedImages.count > 1 {
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds per image
                        }
                    }
                    
                    // Save all changes
                    await MainActor.run {
                        if let modelContext = dataController.modelContext {
                            try? modelContext.save()
                        }
                        
                        // Clear selected images and hide loading
                        selectedImages.removeAll()
                        processingImages = false
                    }
                }
            } catch {
                // Handle error
                await MainActor.run {
                    processingImages = false
                }
            }
        }
    }
    
    /// REMOVED: Photo deletion functionality as requested
    // We're now only allowing users to add photos without deleting them
    
    // MARK: - Client Data Refresh
    
    private func refreshClientData(clientId: String, forceRefresh: Bool = false) {
        // Skip if already refreshing
        guard !isRefreshingClient else { 
            return 
        }
        isRefreshingClient = true
        
        
        Task {
            do {
                // Get the sync manager from data controller
                guard let syncManager = dataController.syncManager else {
                    isRefreshingClient = false
                    return
                }
                
                // Refresh just this one client
                try? await syncManager.refreshSingleClient(clientId: clientId)
                
                
                // Update UI on main thread
                await MainActor.run {
                    isRefreshingClient = false
                }
            } catch {
                await MainActor.run {
                    isRefreshingClient = false
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func openInMaps(coordinate: CLLocationCoordinate2D?, address: String) {
        if let coordinate = coordinate {
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            mapItem.name = address
            mapItem.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
        } else {
            // Fallback to address-based search
            let searchQuery = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "maps://?q=\(searchQuery)") {
                UIApplication.shared.open(url)
            }
        }
    }

    @MainActor
    private func selectAddressSuggestion(_ suggestion: MKLocalSearchCompletion) {
        // Build full address from suggestion
        let fullAddress = "\(suggestion.title), \(suggestion.subtitle)"
        editedAddress = fullAddress

        // Clear suggestions
        addressSearchCompleter.clear()

        // Geocode the selected address
        Task {
            await geocodeAddressInline(fullAddress)
        }
    }

    @MainActor
    private func geocodeAddressInline(_ address: String) async {
        isGeocodingAddress = true

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)

            if let location = placemarks.first?.location {
                addressMapRegion = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
        } catch {
            print("❌ Geocoding failed: \(error.localizedDescription)")
        }

        isGeocodingAddress = false
    }

    private func saveAddress() {
        showingAddressEditor = false

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Use centralized function for immediate sync
        Task {
            do {
                try await dataController.updateProjectAddress(project: project, address: editedAddress)
            } catch {
                print("❌ Failed to save address: \(error)")
            }
        }
    }
}

// MARK: - AddressSearchCompleter

class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var searchFragment: String = "" {
        didSet {
            if searchFragment.isEmpty {
                results = []
            } else {
                completer.queryFragment = searchFragment
            }
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = completer.results
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("❌ Address search completer error: \(error.localizedDescription)")
    }

    func clear() {
        searchFragment = ""
        results = []
    }
}

// MARK: - AddressEditorSheet (Legacy - kept for compatibility)

struct AddressEditorSheet: View {
    @Binding var address: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var isGeocodingAddress = false
    @State private var isReverseGeocoding = false
    @State private var lastUserTypedAddress: String = ""
    @State private var lastCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    @State private var isUserEditingText = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            ZStack {
                MapViewWithCallback(
                    region: $region,
                    onRegionChange: { newRegion in
                        guard !isUserEditingText else { return }

                        let newCoord = newRegion.center
                        if abs(newCoord.latitude - lastCoordinate.latitude) > 0.001 ||
                           abs(newCoord.longitude - lastCoordinate.longitude) > 0.001 {
                            lastCoordinate = newCoord

                            debounceTask?.cancel()
                            debounceTask = Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                if !Task.isCancelled {
                                    await MainActor.run {
                                        reverseGeocodeCoordinate(newCoord)
                                    }
                                }
                            }
                        }
                    }
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()

                    VStack(alignment: .leading, spacing: 16) {
                        Text("ADDRESS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        TextField("Enter address or drag map", text: $address, onEditingChanged: { isEditing in
                            isUserEditingText = isEditing
                        })
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocorrectionDisabled(true)
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .onChange(of: address) { _, newValue in
                                if newValue != lastUserTypedAddress && isUserEditingText {
                                    lastUserTypedAddress = newValue

                                    debounceTask?.cancel()
                                    debounceTask = Task {
                                        try? await Task.sleep(nanoseconds: 800_000_000)
                                        if !Task.isCancelled {
                                            await MainActor.run {
                                                geocodeAddress(newValue)
                                            }
                                        }
                                    }
                                }
                            }

                        if isGeocodingAddress || isReverseGeocoding {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                    .scaleEffect(0.8)
                                Text(isGeocodingAddress ? "Updating map..." : "Finding address...")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }
                    }
                    .padding(20)
                    .background(.ultraThinMaterial.opacity(0.95))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }

                VStack(spacing: 4) {
                    // NOTE: Missing icon in OPSStyle - "scope" (address editor crosshair)
                    Image(systemName: "scope")
                        .font(.system(size: 32))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)

                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(width: 6, height: 6)
                }
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .navigationTitle("EDIT ADDRESS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(address.isEmpty)
                }
            }
            .toolbarBackground(OPSStyle.Colors.cardBackgroundDark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            lastUserTypedAddress = address
            geocodeAddress(address)
        }
    }

    private func geocodeAddress(_ addressString: String) {
        guard !addressString.isEmpty else { return }

        isGeocodingAddress = true

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(addressString) { placemarks, error in
            DispatchQueue.main.async {
                isGeocodingAddress = false

                if let placemark = placemarks?.first,
                   let location = placemark.location {
                    withAnimation {
                        region.center = location.coordinate
                    }
                }
            }
        }
    }

    private func reverseGeocodeCoordinate(_ coordinate: CLLocationCoordinate2D) {
        guard !isGeocodingAddress, !isUserEditingText else { return }

        isReverseGeocoding = true

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                isReverseGeocoding = false

                guard !isUserEditingText else { return }

                if let placemark = placemarks?.first {
                    var addressComponents: [String] = []

                    if let subThoroughfare = placemark.subThoroughfare {
                        addressComponents.append(subThoroughfare)
                    }
                    if let thoroughfare = placemark.thoroughfare {
                        addressComponents.append(thoroughfare)
                    }
                    if let locality = placemark.locality {
                        addressComponents.append(locality)
                    }
                    if let administrativeArea = placemark.administrativeArea {
                        addressComponents.append(administrativeArea)
                    }
                    if let postalCode = placemark.postalCode {
                        addressComponents.append(postalCode)
                    }

                    let newAddress = addressComponents.joined(separator: ", ")
                    if !newAddress.isEmpty {
                        address = newAddress
                        lastUserTypedAddress = newAddress
                    }
                }
            }
        }
    }
}

struct MapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct MapViewWithCallback: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let onRegionChange: (MKCoordinateRegion) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if abs(mapView.region.center.latitude - region.center.latitude) > 0.001 ||
           abs(mapView.region.center.longitude - region.center.longitude) > 0.001 {
            mapView.setRegion(region, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewWithCallback

        init(_ parent: MapViewWithCallback) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                self.parent.region = mapView.region
                self.parent.onRegionChange(mapView.region)
            }
        }
    }
}

struct ProjectDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a sample project for preview
        let sampleProject = Project(id: "preview-123", title: "Sample Construction Project", status: .inProgress)

        // Set additional properties
        // Client name comes from client relationship
        sampleProject.address = "123 Main Street, Springfield, IL"
        sampleProject.startDate = Date()
        sampleProject.endDate = Date().addingTimeInterval(60*60*24*30) // 30 days later
        sampleProject.notes = "This is a sample project for preview purposes."

        return ProjectDetailsView(project: sampleProject)
            .environmentObject(DataController())
            .preferredColorScheme(.dark)
    }
}

// Full screen photo viewer with swipe navigation
struct FullScreenPhotoViewer: View {
    let photos: [String]
    let initialIndex: Int
    let onDismiss: () -> Void
    
    @State private var currentIndex: Int
    @Environment(\.colorScheme) private var colorScheme
    
    init(photos: [String], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Photo gallery with swipe
            TabView(selection: $currentIndex) {
                ForEach(0..<photos.count, id: \.self) { index in
                    ZoomablePhotoView(url: photos[index])
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            
            // UI controls overlay
            VStack {
                // Top bar with close button and counter
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: OPSStyle.Icons.xmark)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("\(currentIndex + 1) of \(photos.count)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black)
                        .cornerRadius(20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 48)
                
                Spacer()
            }
        }
        .statusBar(hidden: true)
        .preferredColorScheme(.dark)
    }
}

// Zoomable photo view for individual photos
struct ZoomablePhotoView: View {
    let url: String
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var isLoading = true
    @State private var showingSaveDialog = false
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var lastScaleValue: CGFloat = 1.0
    @State private var pinchCenter: CGPoint? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale, anchor: .center)
                        .offset(offset)
                        .onLongPressGesture {
                            // Show save dialog on long press
                            showingSaveDialog = true
                        }
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    // Calculate the scale change
                                    let delta = value / lastScaleValue
                                    lastScaleValue = value
                                    
                                    // Apply zoom
                                    let newScale = min(max(scale * delta, 1), 5)
                                    
                                    if newScale > 1 {
                                        // Calculate zoom-to-pinch-point offset
                                        if pinchCenter == nil {
                                            // Store the initial pinch center
                                            pinchCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                        }
                                        
                                        // Adjust offset based on zoom center
                                        let scaleDiff = newScale - scale
                                        if let center = pinchCenter {
                                            let offsetX = (center.x - geometry.size.width / 2) * scaleDiff
                                            let offsetY = (center.y - geometry.size.height / 2) * scaleDiff
                                            offset.width -= offsetX
                                            offset.height -= offsetY
                                        }
                                    }
                                    
                                    scale = newScale
                                }
                                .onEnded { _ in
                                    // Always reset to 1x when fingers are lifted
                                    withAnimation(.spring()) {
                                        scale = 1.0
                                        offset = .zero
                                        lastScaleValue = 1.0
                                        pinchCenter = nil
                                    }
                                }
                        )
                        .highPriorityGesture(
                            // Only allow drag when zoomed in
                            scale > 1 ? DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: offset.width + value.translation.width,
                                        height: offset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    // Keep offset when zoomed
                                } : nil
                        )
                } else if isLoading {
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Loading image...")
                            .foregroundColor(.gray)
                            .padding(.top, 10)
                    }
                } else {
                    VStack {
                        Image(systemName: OPSStyle.Icons.exclamationmarkTriangle)
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text("Failed to load image")
                            .foregroundColor(.gray)
                            .padding(.top, 10)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear(perform: loadImage)
        .alert("Save Image", isPresented: $showingSaveDialog) {
            Button("Save to Camera Roll") {
                saveImageToPhotos()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Would you like to save this image to your camera roll?")
        }
        .alert("Save Result", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveAlertMessage)
        }
    }
    
    private func loadImage() {
        guard image == nil else { return }
        
        isLoading = true
        
        // First check in-memory cache for quick loading
        if let cachedImage = ImageCache.shared.get(forKey: url) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = cachedImage
            }
            return
        }
        
        // Then try to load from file system using ImageFileManager
        if let loadedImage = ImageFileManager.shared.loadImage(localID: url) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = loadedImage
                
                // Cache in memory for faster access next time
                ImageCache.shared.set(loadedImage, forKey: url)
            }
            return
        }
        
        // For legacy support: try UserDefaults if not found in file system
        if url.hasPrefix("local://") || (url.contains("opsapp.co/") && url.contains("/img/")) {
            if let base64String = UserDefaults.standard.string(forKey: url),
               let imageData = Data(base64Encoded: base64String),
               let loadedImage = UIImage(data: imageData) {
                
                // Migrate to file system for future use
                _ = ImageFileManager.shared.saveImage(data: imageData, localID: url)
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.image = loadedImage
                    
                    // Cache in memory
                    ImageCache.shared.set(loadedImage, forKey: url)
                }
                return
            }
        }
        
        // Handle remote URLs
        var normalizedURL = url
        
        // Handle // prefix by adding https:
        if url.hasPrefix("//") {
            normalizedURL = "https:" + url
        }
        
        // If not found locally, try to load from network
        guard let imageURL = URL(string: normalizedURL) else {
            isLoading = false
            return
        }
        
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, 
                   !(200...299).contains(httpResponse.statusCode) {
                    return
                }
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                    
                    // Cache the remote image in file system
                    _ = ImageFileManager.shared.saveImage(data: data, localID: normalizedURL)
                    
                    // Also cache in memory
                    ImageCache.shared.set(loadedImage, forKey: normalizedURL)
                } else {
                }
            }
        }.resume()
    }
    
    private func saveImageToPhotos() {
        guard let imageToSave = image else {
            saveAlertMessage = "No image to save"
            showingSaveAlert = true
            return
        }
        
        UIImageWriteToSavedPhotosAlbum(imageToSave, nil, nil, nil)
        saveAlertMessage = "Image saved to your camera roll"
        showingSaveAlert = true
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        saveAlertMessage = "Image saved to Photos"
        showingSaveAlert = true
    }
}

struct DarkLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            configuration.content
                .font(OPSStyle.Typography.body)
        }
    }
}
 
