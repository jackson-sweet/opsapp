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
    @ObservedObject private var permissionStore = PermissionStore.shared

    // Tutorial environment
    @Environment(\.tutorialMode) private var tutorialMode

    // State variables for various sheets and actions
    @State private var showCompleteConfirmation = false
    @State private var showExpenseForm = false
    @State private var showProjectDetails = false
    @State private var showImagePicker = false
    /// Bug 0a07ca47 — separate sheet for the multi-capture camera so
    /// the user can take a stack of photos in one continuous session.
    /// The library path keeps using ImagePicker so non-camera flows
    /// stay simple.
    @State private var showCameraBatch = false
    /// Bug 0a07ca47 — confirmation dialog for picking between camera
    /// multi-capture and library when the user taps the Photo action.
    @State private var showPhotoSourceChooser = false
    @State private var selectedImages: [UIImage] = []
    @State private var processingImage = false
    @State private var isAddingPhotos = false // Prevent duplicate additions

    @StateObject private var expenseViewModel = ExpenseViewModel()

    /// Bug aa3ec6d7 — when a task is active for this project, surface
    /// the Complete action first and re-label it "Complete [TaskType]"
    /// so a tap completes the selected task, not the parent project.
    private var activeTask: ProjectTask? {
        guard let activeTaskID = appState.activeTaskID else { return nil }
        return project.tasks.first(where: { $0.id == activeTaskID })
    }

    /// Whether the MEASURE entry should render in the bar. Pure function of
    /// (feature flag, device capability) — same gate exercised by
    /// `MeasureActionButton.shouldRender(...)`, evaluated here so the divider
    /// layout has access to the same answer.
    private var showMeasureEntry: Bool {
        MeasureActionButton.shouldRender(
            flagEnabled: permissionStore.isFeatureEnabled(MeasurementFlag.dimensionedCapture),
            capability: CaptureCapability.detect().capability
        )
    }

    private var orderedActions: [ProjectAction] {
        let base = ProjectAction.allCases
        guard activeTask != nil else { return base }
        // Move Complete to the front; preserve relative order of the rest.
        return [.complete] + base.filter { $0 != .complete }
    }

    private var completeLabel: String {
        if let task = activeTask {
            // taskType.display is the bare type name ("Demo", "Punchlist"); we
            // prefix with "Complete" to match the bug ask.
            let typeName = task.taskType?.display ?? "Task"
            return "Complete \(typeName)"
        }
        return "Complete"
    }

    private var completeAlert: Alert {
        if let task = activeTask {
            let typeName = task.taskType?.display ?? "Task"
            return Alert(
                title: Text("Complete \(typeName)"),
                message: Text("Mark this \(typeName.lowercased()) as complete?"),
                primaryButton: .default(Text("Complete")) {
                    completeActiveTask(task)
                },
                secondaryButton: .cancel()
            )
        }
        return Alert(
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

    private var actionEntries: [ProjectActionBarEntry] {
        var entries = orderedActions.map { action in
            ProjectActionBarEntry.project(
                action,
                icon: action.iconName(isRouting: inProgressManager.isRouting),
                label: action == .complete
                    ? completeLabel
                    : action.label(isRouting: inProgressManager.isRouting)
            )
        }

        if showMeasureEntry {
            entries.append(.measure)
        }

        return entries
    }

    var body: some View {
        let entries = actionEntries

        // Bug 5eaa471d — mirror ProjectQuickActionsBar: horizontal scroll so
        // long labels (e.g. "COMPLETE PUNCHLIST") and the optional MEASURE
        // entry stay on a single line and overflow past the screen edge
        // instead of wrapping into a multi-row grid.
        ScrollView(.horizontal, showsIndicators: false) {
            OPSActionBar {
                HStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        actionButton(for: entry)
                            .frame(minWidth: 64)

                        if index < entries.count - 1 {
                            Spacer().frame(width: 16)
                            Rectangle()
                                .fill(OPSStyle.Colors.cardBorderSubtle)
                                .frame(width: 1, height: 32)
                            Spacer().frame(width: 16)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        // Bug aa3ec6d7 — confirmation copy + action follow whichever entity
        // (project or active task) the Complete button currently targets.
        // The alert content is computed once per render via `completeAlert`
        // so we can branch on `activeTask` cleanly.
        .alert(isPresented: $showCompleteConfirmation) { completeAlert }
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
        // Bug 0a07ca47 / 02222904 — choose between the multi-shot
        // camera and the library picker before opening anything. The
        // camera path opens CameraBatchView (live preview + stack),
        // the library path opens the standard PHPicker.
        .confirmationDialog(
            "Add Photos",
            isPresented: $showPhotoSourceChooser,
            titleVisibility: .visible
        ) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photos") {
                    showCameraBatch = true
                }
            }
            Button("Choose from Library") {
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Capture photos with the camera or pick existing ones from your library.")
        }
        // Library-only picker. The camera path lives in showCameraBatch.
        .sheet(isPresented: $showImagePicker, onDismiss: {
            isAddingPhotos = false
        }) {
            ImagePicker(
                images: $selectedImages,
                allowsEditing: false,
                sourceType: .photoLibrary,
                selectionLimit: 10,
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
        // Bug 0a07ca47 — multi-capture camera. Stays open between
        // shots, accumulates a stack, and returns the whole batch on
        // Done. Skip the addPhotosToProject scheduler dance — the
        // user already explicitly committed inside the camera UI.
        .fullScreenCover(isPresented: $showCameraBatch) {
            CameraBatchView { capturedImages in
                guard !capturedImages.isEmpty, !isAddingPhotos else { return }
                isAddingPhotos = true
                selectedImages = capturedImages
                addPhotosToProject()
            }
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

    @ViewBuilder
    private func actionButton(for entry: ProjectActionBarEntry) -> some View {
        switch entry {
        case .project(let action, let icon, let label):
            OPSActionBarButton(
                icon: icon,
                label: label
            ) {
                handleAction(action)
            }
            .modifier(ActionButtonHighlightModifier(action: action))
        case .measure:
            // Phase G — MEASURE entry. Renders only when the LiDAR feature
            // flag is enabled AND the device supports depth-aware capture
            // (LiDAR or visual SLAM). Hidden by default; flips visible
            // once `feature.measurement.dimensioned_capture` is flipped ON
            // remotely. Spec §3.1 + §10.3.
            MeasureActionButton(project: project)
        }
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
            // Bug aa3ec6d7 — when an active task is selected for this
            // project, the same shared confirmation dialog now branches on
            // `activeTask` to confirm the task instead of the project.
            // Surface the dialog regardless; the alert closure picks the
            // right copy + action.
            showCompleteConfirmation = true
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
            // Bug 0a07ca47 — show source chooser instead of going
            // straight to the library. Lets the user pick between the
            // multi-capture camera and gallery import.
            showPhotoSourceChooser = true
        }
    }
    
    // Mark project as complete
    private func markProjectComplete() {
        // Show a simple confirmation dialog
        showCompleteConfirmation = true
    }

    /// Bug aa3ec6d7 — flip the active task to completed using the same
    /// centralised path TaskDetailsView uses, keeping local + remote state
    /// aligned. Clearing the active task ID after success collapses the
    /// action bar back to its default project-completion shape on the next
    /// render, so the UI doesn't leave a stale "Complete [Type]" button
    /// pointing at a finished task.
    private func completeActiveTask(_ task: ProjectTask) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        Task {
            do {
                try await dataController.updateTaskStatus(task: task, to: .completed)
                await MainActor.run {
                    if appState.activeTaskID == task.id {
                        appState.activeTaskID = nil
                    }
                    let success = UINotificationFeedbackGenerator()
                    success.notificationOccurred(.success)
                }
            } catch {
                print("[PROJECT_ACTION_BAR] ❌ Failed to complete task \(task.id): \(error)")
            }
        }
    }
    
    private func updateProjectStatus(_ status: Status) {
        Task {
            // Update project status and exit project mode when completed
            // Always force sync for user-initiated status changes in the UI
            try? await dataController.updateProjectStatus(
                project: project,
                to: status
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

        Task {
            do {
                // Use ImageSyncManager if available
                if let imageSyncManager = dataController.imageSyncManager {

                    // Process all images through the ImageSyncManager.
                    // Bug 35c400c2 — saveImages already appends the new
                    // URLs onto project.projectImagesString and saves the
                    // model context. Do NOT append a second time here;
                    // doing so was the root cause of every Done click
                    // duplicating photos in the carousel.
                    let urls = await imageSyncManager.saveImages(selectedImages, for: project)

                    await MainActor.run {
                        if !urls.isEmpty {
                            // Mark the project for sync priority bump so
                            // the next outbound pass surfaces the new
                            // photo set fast.
                            project.syncPriority = 2

                            if let modelContext = dataController.modelContext {
                                try? modelContext.save()
                            }
                        }
                        // Always reset state — empty result means upload
                        // failed, but the in-flight placeholders have
                        // already been cleared by saveImages's defer.
                        selectedImages.removeAll()
                        processingImage = false
                        isAddingPhotos = false
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

private enum ProjectActionBarEntry: Identifiable {
    case project(ProjectAction, icon: String, label: String)
    case measure

    var id: String {
        switch self {
        case .project(let action, _, _):
            return action.id
        case .measure:
            return "measure"
        }
    }

    var label: String {
        switch self {
        case .project(_, _, let label):
            return label
        case .measure:
            return "MEASURE"
        }
    }
}

private extension ProjectAction {
    var id: String {
        switch self {
        case .navigate: return "navigate"
        case .complete: return "complete"
        case .receipt:  return "receipt"
        case .details:  return "details"
        case .photo:    return "photo"
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
