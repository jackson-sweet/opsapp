//
//  ProjectDetailsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-25.
//

import SwiftUI
import UIKit
import MapKit
// Import team member components

struct ProjectDetailsView: View {
    let project: Project
    @Environment(\.dismiss) var dismiss
    @State private var noteText: String
    @State private var originalNoteText: String
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var locationManager: LocationManager
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
    
    // Initialize with project's existing notes
    init(project: Project) {
        self.project = project
        let notes = project.notes ?? ""
        self._noteText = State(initialValue: notes)
        self._originalNoteText = State(initialValue: notes)
        
        // Debug output to help troubleshoot issues
        
        // New debug output for navigation
        
        // Debug project team member information
        
        // Team member debugging removed - no longer needed
        
        // Convert project to JSON for complete debugging
        do {
            let projectDict: [String: Any] = [
                "id": project.id,
                "title": project.title,
                "clientName": project.clientName,
                "address": project.address,
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
            print("Error converting project to JSON: \(error.localizedDescription)")
        }
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            Color.black
                .edgesIgnoringSafeArea(.all)
            
            // Main content
            VStack(spacing: 0) {
                // Modern header with frosted glass effect
                ZStack {
                    // Blurred background
                    BlurView(style: .dark)
                        .edgesIgnoringSafeArea(.top)
                    
                    // Header content
                    VStack(spacing: 8) {
                        // Top row with status and buttons
                        HStack {
                            // Status badge
                            StatusBadge.forJobStatus(project.status)
                            
                            Spacer()
                            
                            // Done button
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
                        
                        // Title row
                        HStack {
                            // Title with subtle separator line below
                            Text(project.title.uppercased())
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.white)
                            
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 90)
                .background(Color.black)
                
                // Main scrollable content
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // Location map - more visual prominence
                        locationSection
                        
                        // Project info with notes - streamlined cards
                        infoSection
                        
                        // Tasks section (show when project is task-based or could be)
                        if project.eventType == .task {
                            tasksSection
                        }
                        
                        // Photos - improved grid layout
                        photosSection
                        
                        // Team members - moved to bottom
                        teamSection
                        
                        // Bottom padding
                        Spacer()
                            .frame(height: 80)
                    }
                    .padding(.top, 16)
                }
            }
        }
        .navigationBarHidden(true)
        // Save notification overlay 
        .overlay(saveNotificationOverlay)
        // Full-screen photo viewer
        .fullScreenCover(isPresented: $showingPhotoViewer) {
            FullScreenPhotoViewer(
                photos: project.getProjectImages(),
                initialIndex: selectedPhotoIndex,
                onDismiss: { showingPhotoViewer = false }
            )
        }
        // Image picker for adding multiple photos
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                images: $selectedImages, 
                allowsEditing: false,
                selectionLimit: 10,
                onSelectionComplete: {
                    // Close the picker immediately
                    showingImagePicker = false
                    
                    // Process images when selection is complete
                    if !selectedImages.isEmpty {
                        // Use slight delay to ensure UI dismissal completes first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            addPhotosToProject()
                        }
                    }
                }
            )
        }
        .confirmationDialog(
            "Unsaved Changes",
            isPresented: $showingUnsavedChangesAlert,
            titleVisibility: .visible
        ) {
            Button("Save Changes", role: .none) {
                saveNotes()
                dismiss()
            }
            
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes to your notes. Would you like to save them before leaving?")
        }
        .onAppear {
            DispatchQueue.main.async {
                // Make sure appState has our current project set as active
                if let appState = dataController.appState, appState.activeProject == nil {
                    appState.activeProject = project
                }
            }
            
            // Request location permission when project details are viewed
            locationManager.requestPermissionIfNeeded()
            
            // Always refresh client data when opening project details
            // This ensures we have the latest client information
            if let clientId = project.clientId, !clientId.isEmpty {
                refreshClientData(clientId: clientId, forceRefresh: true)
            }
        }
        .onDisappear {
            // Make sure to clean up the timer when view disappears
            notificationTimer?.invalidate()
            notificationTimer = nil
        }
        .alert("Network Error", isPresented: $showingNetworkError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(networkErrorMessage)
        }
        // Client contact sheet
        .sheet(isPresented: $showingClientContact) {
            // Pass the actual Client object if available, otherwise create a temporary one
            if let client = project.client {
                TeamMemberDetailView(client: client, project: project)
                    .presentationDragIndicator(.visible)
                    .environmentObject(dataController)
            } else {
                // Fallback: Create a temporary TeamMember for client contact
                let clientTeamMember = TeamMember(
                    id: "client-\(project.id)",
                    firstName: project.effectiveClientName.components(separatedBy: " ").first ?? project.effectiveClientName,
                    lastName: project.effectiveClientName.components(separatedBy: " ").dropFirst().joined(separator: " "),
                    role: "Client",
                    avatarURL: nil,
                    email: project.effectiveClientEmail,
                    phone: project.effectiveClientPhone
                )
                
                TeamMemberDetailView(teamMember: clientTeamMember)
                    .presentationDragIndicator(.visible)
                    .environmentObject(dataController)
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
                if project.eventType == .task && !project.tasks.isEmpty {
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
        VStack(alignment: .leading, spacing: 16) {
            // Location section label
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text("LOCATION")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                Button(action: {
                    openInMaps(coordinate: project.coordinate, address: project.address)
                }) {
                    Text("Get Directions")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                }
            }
            .padding(.horizontal)
            
            // Address text
            Text(project.address)
                .font(OPSStyle.Typography.body)
                .foregroundColor(.white)
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            // Map view - larger and more prominent
            ZStack(alignment: .bottomTrailing) {
                MiniMapView(
                    coordinate: project.coordinate, 
                    address: project.address
                ) {
                    openInMaps(coordinate: project.coordinate, address: project.address)
                }
                .frame(height: 180)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                
                
                // Directions button on map
                Button(action: {
                    openInMaps(coordinate: project.coordinate, address: project.address)
                }) {
                    HStack {
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
            .padding(.horizontal)
        }
    }
    
    // Project info
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
                            Image(systemName: "phone.fill")
                                .font(.system(size: 18))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .opacity(project.effectiveClientPhone != nil ? 1.0 : 0.2)
                            
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 18))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .opacity(project.effectiveClientEmail != nil ? 1.0 : 0.2)
                        }
                        .padding(.trailing, 12)
                        
                    }.background(OPSStyle.Colors.cardBackgroundDark)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Dates row - show start date or "Unscheduled", show end date if valid
                HStack(spacing: 0) {
                    // Start date (show actual date or "Unscheduled")
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("START DATE")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            if let startDate = project.startDate {
                                Text(formatDate(startDate))
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            } else {
                                Text("Unscheduled")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // End date (only show if valid - exists and on or after start date)
                    if let endDate = project.endDate,
                       let startDate = project.startDate,
                       endDate >= startDate {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.checkmark")
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
                
                // Description card
                if let description = project.projectDescription, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "text.alignleft")
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
                        Image(systemName: "note.text")
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 24)
                        
                        Text("PROJECT NOTES")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    // Expandable notes view
                    ExpandableNotesView(
                        notes: project.notes ?? "",
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
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
    }
    
    // Team members section with modern styling
    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section heading outside the card (consistent with other sections)
            HStack {
                Image(systemName: "person.2")
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text("TEAM MEMBERS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Team members content
            ProjectTeamView(project: project)
                .padding(.horizontal)
        }
    }
    
    // Photos section with improved styling
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section heading with icon
            HStack {
                Image(systemName: "photo")
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text("PROJECT PHOTOS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Photo content
            photoContentView
        }
    }
    
    // Photo content view to break up complexity
    private var photoContentView: some View {
        VStack(spacing: 12) {
            // Photo display (empty state or grid)
            photoDisplayView
            
            // Add photos button
            addPhotosButton
            
            // Loading indicator for processing images
            if processingImages {
                processingIndicator
            }
        }
    }
    
    // Photo display - either empty state or grid of photos
    private var photoDisplayView: some View {
        let photos = project.getProjectImages()
        
        if photos.isEmpty {
            return AnyView(emptyPhotosView)
        } else {
            return AnyView(
                VStack(spacing: 0) {
                    photoGridView(photos: photos)
                }
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal)
            )
        }
    }
    
    // Empty state when no photos
    private var emptyPhotosView: some View {
        VStack(spacing: 16) {
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
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
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
            .onTapGesture {
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
                Image(systemName: "checkmark.circle.fill")
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
        TaskListView(project: project)
            .environmentObject(dataController)
    }
    
    // Check if user can edit project settings
    private func canEditProjectSettings() -> Bool {
        guard let currentUser = dataController.currentUser else { return false }
        return currentUser.role != .fieldCrew
    }
    
    // Helper to format date
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    @State private var showingSaveNotification = false
    @State private var notificationTimer: Timer?
    
    private func saveNotes() {
        // Use the SyncManager to handle both local saving and API synchronization
        if let syncManager = dataController.syncManager {
            let success = syncManager.updateProjectNotes(projectId: project.id, notes: noteText)
            
            if success {
                showSaveNotification()
            } else {
                print("⚠️ Failed to save project notes using SyncManager, trying fallback")
                
                // Fallback approach if SyncManager method fails
                project.notes = noteText
                project.needsSync = true
                
                if let modelContext = dataController.modelContext {
                    do {
                        try modelContext.save()
                        showSaveNotification()
                    } catch {
                        print("❌ Error saving notes locally: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Fallback if SyncManager is not available
            project.notes = noteText
            project.needsSync = true
            
            if let modelContext = dataController.modelContext {
                try? modelContext.save()
                showSaveNotification()
                
                // Also post notes to API if we're online
                if dataController.isConnected {
                    Task {
                        do {
                            // Call the API endpoint to update notes
                            try await dataController.apiService.updateProjectNotes(
                                id: project.id,
                                notes: noteText
                            )
                            
                            // If successful, mark as synced
                            await MainActor.run {
                                project.needsSync = false
                                project.lastSyncedAt = Date()
                                try? modelContext.save()
                            }
                            
                        } catch {
                            print("❌ Error syncing project notes to API: \(error.localizedDescription)")
                            // Leave needsSync = true so it will be tried again later
                        }
                    }
                }
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
                    for (index, image) in selectedImages.enumerated() {
                        // Debug log
                        
                        // Compress image
                        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                            print("⚠️ Failed to compress image \(index + 1)")
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
                print("❌ Error processing images: \(error.localizedDescription)")
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
            print("📱 Already refreshing client, skipping duplicate request")
            return 
        }
        isRefreshingClient = true
        
        print("🔄 ProjectDetailsView: Refreshing client \(clientId) for project '\(project.title)'")
        
        Task {
            do {
                // Get the sync manager from data controller
                guard let syncManager = dataController.syncManager else {
                    print("❌ No sync manager available")
                    isRefreshingClient = false
                    return
                }
                
                // Refresh just this one client
                await syncManager.refreshSingleClient(clientId: clientId, for: project, forceRefresh: forceRefresh)
                
                print("✅ Client refresh completed for '\(project.client?.name ?? "Unknown")'")
                
                // Update UI on main thread
                await MainActor.run {
                    isRefreshingClient = false
                }
            } catch {
                print("❌ Failed to refresh client: \(error)")
                await MainActor.run {
                    isRefreshingClient = false
                }
            }
        }
    }
}

struct ProjectDetailsView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a sample project for preview
        let sampleProject = Project(id: "preview-123", title: "Sample Construction Project", status: .inProgress)
        
        // Set additional properties
        sampleProject.clientName = "ABC Construction"
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
                        Image(systemName: "xmark")
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
                        Image(systemName: "exclamationmark.triangle")
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
                    print("ZoomablePhotoView: Error loading image: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, 
                   !(200...299).contains(httpResponse.statusCode) {
                    print("ZoomablePhotoView: HTTP Error: \(httpResponse.statusCode)")
                    return
                }
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                    
                    // Cache the remote image in file system
                    _ = ImageFileManager.shared.saveImage(data: data, localID: normalizedURL)
                    
                    // Also cache in memory
                    ImageCache.shared.set(loadedImage, forKey: normalizedURL)
                } else {
                    print("ZoomablePhotoView: Failed to create image from data")
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
 
