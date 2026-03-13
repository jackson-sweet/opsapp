//
//  ProjectActionBar.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI
import PhotosUI
import UIKit

struct ProjectActionBar: View {
    let project: Project
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationManager: LocationManager
    @ObservedObject private var inProgressManager = InProgressManager.shared

    // Tutorial environment
    @Environment(\.tutorialMode) private var tutorialMode

    // State variables for various sheets and actions
    @State private var showCompleteConfirmation = false
    @State private var showExpenseForm = false
    @State private var showProjectDetails = false
    @State private var showImagePicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var processingImage = false
    @State private var isAddingPhotos = false // Prevent duplicate additions
    
    @StateObject private var expenseViewModel = ExpenseViewModel()
    
    var body: some View {
        OPSActionBar {
            HStack(spacing: 0) {
                ForEach(Array(ProjectAction.allCases.enumerated()), id: \.element) { index, action in
                    OPSActionBarButton(
                        icon: action.iconName(isRouting: inProgressManager.isRouting),
                        label: action.label(isRouting: inProgressManager.isRouting)
                    ) {
                        handleAction(action)
                    }
                    .frame(maxWidth: .infinity)
                    .modifier(ActionButtonHighlightModifier(action: action))

                    // Vertical divider between buttons (not after last one)
                    if index < ProjectAction.allCases.count - 1 {
                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorderSubtle)
                            .frame(width: 1, height: 32)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .contentMargins(.bottom, 90)
        // Complete Project Confirmation
        .alert(isPresented: $showCompleteConfirmation) {
            Alert(
                title: Text("Complete Project"),
                message: Text("Are you sure you want to mark this project as complete?"),
                primaryButton: .default(Text("Complete")) {
                    // CENTRALIZED COMPLETION CHECK: If completing project, check for incomplete tasks first
                    if appState.requestProjectCompletion(project) {
                        // No incomplete tasks - proceed with completion
                        updateProjectStatus(.completed)
                    }
                    // If false, the global checklist sheet will be shown via AppState
                },
                secondaryButton: .cancel()
            )
        }
        // Expense Form Sheet
        .sheet(isPresented: $showExpenseForm) {
            ExpenseFormSheet(viewModel: expenseViewModel, prefilledProjectId: project.id)
        }
        // Project Details Sheet
        .sheet(isPresented: $showProjectDetails) {
            NavigationView {
                ProjectDetailsView(project: project)
            }
            .interactiveDismissDisabled(true)
        }
        // Photo Picker for project photos - modified to use both camera and library
        .sheet(isPresented: $showImagePicker, onDismiss: {
            // Reset the flag when sheet is dismissed
            isAddingPhotos = false
        }) {
            ImagePicker(
                images: $selectedImages,
                allowsEditing: true,
                sourceType: .both, // Allow user to choose between camera and library
                selectionLimit: 10, // Allow multiple photos
                onSelectionComplete: {
                    // Only process if not already processing
                    if !isAddingPhotos && !selectedImages.isEmpty {
                        isAddingPhotos = true
                        // Dismiss sheet immediately
                        showImagePicker = false
                        // Process images after sheet dismisses
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            addPhotosToProject()
                        }
                    }
                }
            )
        }
        // Loading overlay when processing image
        .overlay(
            Group {
                if processingImage {
                    ZStack {
                        OPSStyle.Colors.imageOverlay
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            Text("Processing image...")
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(.top, 10)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .padding(.horizontal, 20)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                }
            }
        )
    }
    
    private func handleAction(_ action: ProjectAction) {
        switch action {
        case .navigate:
            // Toggle navigation
            if InProgressManager.shared.isRouting {
                // Stop routing
                InProgressManager.shared.stopRouting()
                
                // Post notification to stop navigation in the new map
                NotificationCenter.default.post(
                    name: Notification.Name("StopNavigation"),
                    object: nil
                )
                
                // Post notification to stop route refresh timer
                NotificationCenter.default.post(
                    name: Notification.Name("StopRouteRefreshTimer"),
                    object: nil
                )
            } else {
                // Start routing to project
                if project.coordinate != nil {
                    // Post notification to start navigation in the new map
                    // The map will handle starting InProgressManager for consistency
                    NotificationCenter.default.post(
                        name: Notification.Name("StartNavigation"),
                        object: nil,
                        userInfo: ["projectId": project.id]
                    )
                    
                    // Post notification to start route refresh timer
                    NotificationCenter.default.post(
                        name: Notification.Name("StartRouteRefreshTimer"),
                        object: nil
                    )
                }
            }
        case .complete:
            // Directly mark the project as completed
            markProjectComplete()
        case .receipt:
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                expenseViewModel.setup(companyId: companyId)
            }
            showExpenseForm = true
        case .details:
            // Tutorial mode: post notification for wrapper to show inline sheet
            if tutorialMode {
                NotificationCenter.default.post(
                    name: Notification.Name("TutorialDetailsTapped"),
                    object: nil,
                    userInfo: ["projectID": project.id]
                )
                // Don't show local sheet - wrapper handles it with inline sheet
                return
            }

            // Check if we have an active task
            if let activeTaskID = appState.activeTaskID,
               let activeTask = project.tasks.first(where: { $0.id == activeTaskID }) {
                // Show task details
                let userInfo: [String: Any] = [
                    "taskID": activeTask.id,
                    "projectID": project.id
                ]

                NotificationCenter.default.post(
                    name: Notification.Name("ShowTaskDetailsFromHome"),
                    object: nil,
                    userInfo: userInfo
                )
            } else {
                // Show project details
                showProjectDetails = true
            }
        case .photo:
            // Take a photo for the project
            showImagePicker = true
        }
    }
    
    // Mark project as complete
    private func markProjectComplete() {
        // Show a simple confirmation dialog
        showCompleteConfirmation = true
    }
    
    private func updateProjectStatus(_ status: Status) {
        Task {
            // Update project status and exit project mode when completed
            // Always force sync for user-initiated status changes in the UI
            try? await dataController.syncManager.updateProjectStatus(
                projectId: project.id,
                status: status,
                forceSync: true // Always force sync for manual status changes
            )
            
            // If marking as complete, exit project mode after a short delay
            if status == .completed {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                appState.exitProjectMode()
            }
        }
    }
    
    private func addPhotosToProject() {
        // Prevent duplicate calls
        guard !processingImage else { return }
        
        // Start loading indicator
        processingImage = true
        
        // Debug log
        
        Task {
            do {
                // Use ImageSyncManager if available
                if let imageSyncManager = dataController.imageSyncManager {
                    
                    // Process all images through the ImageSyncManager
                    let urls = await imageSyncManager.saveImages(selectedImages, for: project)
                    
                    if !urls.isEmpty {
                        // Add URLs to project
                        await MainActor.run {
                            var currentImages = project.getProjectImages()
                            currentImages.append(contentsOf: urls)
                            
                            project.setProjectImageURLs(currentImages)
                            project.needsSync = true
                            project.syncPriority = 2 // Higher priority for image changes
                            
                            // Save changes
                            if let modelContext = dataController.modelContext {
                                do {
                                    try modelContext.save()
                                } catch {
                                }
                            }
                            
                            // Reset state
                            selectedImages.removeAll()
                            processingImage = false
                            isAddingPhotos = false
                        }
                    } else {
                        await MainActor.run {
                            processingImage = false
                            isAddingPhotos = false
                        }
                    }
                } else {
                    // Fallback to direct processing
                    
                    // Process each image
                    for (index, image) in selectedImages.enumerated() {
                        // Debug log
                        
                        // Compress image
                        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                            continue
                        }
                        
                        // Generate a unique filename
                        let timestamp = Date().timeIntervalSince1970
                        let filename = "project_\(project.id)_\(timestamp)_\(UUID().uuidString).jpg"
                        
                        // Save image data to UserDefaults with the key as the URL
                        let localURL = "local://project_images/\(filename)"
                        
                        // Store the image in UserDefaults
                        if let imageBase64 = imageData.base64EncodedString() as String? {
                            UserDefaults.standard.set(imageBase64, forKey: localURL)
                            
                            // Add to project's images
                            await MainActor.run {
                                var currentImages = project.getProjectImages()
                                currentImages.append(localURL)
                                project.setProjectImageURLs(currentImages)
                                project.needsSync = true
                            }
                        }
                        
                        // Small delay to simulate upload process
                        if selectedImages.count > 1 {
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds per image
                        }
                    }
                    
                    // Simulate upload delay for single image
                    if selectedImages.count == 1 {
                        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    }
                    
                    // Save at the end with all changes
                    await MainActor.run {
                        if let modelContext = dataController.modelContext {
                            do {
                                try modelContext.save()
                            } catch {
                            }
                        }
                        
                        selectedImages.removeAll()
                        processingImage = false
                        isAddingPhotos = false
                    }
                }
            } catch {
                await MainActor.run {
                    processingImage = false
                    isAddingPhotos = false
                    selectedImages.removeAll()
                }
            }
        }
    }
}

// MARK: - Project Actions Enum
enum ProjectAction: CaseIterable {
    case navigate
    case complete
    case receipt
    case details
    case photo
    
    static func allCases(isRouting: Bool) -> [ProjectAction] {
        return self.allCases
    }
    
    func iconName(isRouting: Bool) -> String {
        switch self {
        case .navigate: return isRouting ? "location.slash" : "location"
        case .complete: return "checkmark.circle"
        case .receipt: return "doc.text.viewfinder"
        case .details: return "info.circle"
        case .photo: return "camera"
        }
    }

    func label(isRouting: Bool) -> String {
        switch self {
        case .navigate: return isRouting ? "Stop" : "Navigate"
        case .complete: return "Complete"
        case .receipt: return "Receipt"
        case .details: return "Details"
        case .photo: return "Photo"
        }
    }
}

// MARK: - Action Button Highlight Modifier

/// Modifier that adds tutorial highlight to specific action buttons based on tutorial phase
/// Also handles greying out non-highlighted buttons during tutorial
private struct ActionButtonHighlightModifier: ViewModifier {
    let action: ProjectAction

    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase

    func body(content: Content) -> some View {
        content
            .opacity(shouldGreyOut ? 0.3 : 1.0)
            .allowsHitTesting(!shouldGreyOut)
            .overlay(
                Group {
                    if shouldHighlight {
                        PulsingActionHighlight()
                    }
                }
            )
    }

    private var shouldHighlight: Bool {
        guard tutorialMode, let phase = tutorialPhase else { return false }
        switch action {
        case .details:
            return phase == .tapDetails
        case .complete:
            return phase == .completeProject
        default:
            return false
        }
    }

    /// Whether this button should be greyed out during the current tutorial phase
    private var shouldGreyOut: Bool {
        guard tutorialMode, let phase = tutorialPhase else { return false }
        switch phase {
        case .projectStarted:
            // Grey out all buttons during projectStarted (auto-advance phase)
            return true
        case .tapDetails:
            // Grey out all buttons except Details
            return action != .details
        case .completeProject:
            // Grey out all buttons except Complete
            return action != .complete
        default:
            return false
        }
    }
}

/// Pulsing highlight overlay for action buttons
private struct PulsingActionHighlight: View {
    @State private var animatePulse = false
    @State private var isVisible = false

    var body: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
            .stroke(
                TutorialHighlightStyle.color,
                lineWidth: TutorialHighlightStyle.lineWidth
            )
            .opacity(isVisible ? (animatePulse ? TutorialHighlightStyle.pulseOpacity.max : TutorialHighlightStyle.pulseOpacity.min) : 0)
            .padding(-2)
            .onAppear {
                withAnimation(OPSStyle.Animation.standard) {
                    isVisible = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeInOut(duration: TutorialHighlightStyle.pulseDuration).repeatForever(autoreverses: true)) {
                        animatePulse = true
                    }
                }
            }
    }
}

// ReceiptScannerView removed — replaced by ExpenseFormSheet

