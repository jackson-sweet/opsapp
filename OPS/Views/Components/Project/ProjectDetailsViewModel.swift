//
//  ProjectDetailsViewModel.swift
//  OPS
//
//  ViewModel for the redesigned ProjectDetailsView.
//  Extracts state management and business logic from the former 5K-line monolith.
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import Supabase

/// Tab options for the redesigned project details view
enum ProjectDetailTab: String, CaseIterable {
    case activity = "ACTIVITY"
    case details = "DETAILS"
    case expenses = "EXPENSES"
    case deck = "DECK"
}

@MainActor
class ProjectDetailsViewModel: ObservableObject {

    // MARK: - Dependencies

    let project: Project
    weak var dataController: DataController?
    weak var appState: AppState?

    // MARK: - Tab State

    @Published var selectedTab: ProjectDetailTab = .activity

    // MARK: - Task Selection

    @Published var selectedTask: ProjectTask? = nil

    // MARK: - Sheet Booleans

    @Published var showingImagePicker = false
    @Published var showingPhotoViewer = false
    @Published var selectedPhotoIndex: Int = 0
    @Published var showingClientContact = false
    @Published var showingAddressEditor = false
    @Published var showingAddTaskSheet = false
    @Published var showingDeleteAlert = false
    @Published var showingUnsavedChangesAlert = false
    @Published var showingCompletionAlert = false
    @Published var showingTaskActionMenu = false
    @Published var showingTaskScheduler = false
    @Published var showingTaskDeleteConfirmation = false
    @Published var showingCancelTaskConfirmation = false
    @Published var showingTaskTeamPicker = false
    @Published var showingNoteImagePicker = false
    @Published var showingNotePhotoViewer = false
    @Published var showingProjectNotes = false
    @Published var showingNetworkError = false
    @Published var networkErrorMessage = ""

    // MARK: - Editing State

    @Published var isEditingTitle = false
    @Published var editedTitle = ""
    @Published var isEditingProjectDetails = false
    @Published var editingProjectDetailsText = ""
    @Published var isEditingAddress = false
    @Published var editedAddress = ""
    @Published var isGeocodingAddress = false
    @Published var isDeleting = false
    @Published var isUpdatingVinylOrderMarker = false

    // MARK: - Photo State

    @Published var selectedImages: [UIImage] = []
    @Published var processingImages = false
    @Published var notePhotoViewerURLs: [String] = []
    @Published var notePhotoViewerIndex: Int = 0

    // MARK: - Task Team Picker

    @Published var selectedTaskTeamMemberIds: Set<String> = []
    @Published var taskTeamMembers: [TeamMember] = []

    // MARK: - Notes

    @Published var noteText: String
    @Published var originalNoteText: String

    // MARK: - Save Notification

    @Published var showingSaveNotification = false
    private var notificationTimer: Timer?

    // MARK: - Expense State

    @Published var projectExpenses: [ExpenseDTO] = []
    @Published var isLoadingExpenses = false
    @Published var expenseError: String? = nil

    // MARK: - Client State

    @Published var isRefreshingClient = false

    // MARK: - Address

    @Published var addressMapRegion: MKCoordinateRegion

    // MARK: - Init

    init(project: Project, initialSelectedTask: ProjectTask? = nil) {
        self.project = project
        self.selectedTask = initialSelectedTask

        let notes = project.notes ?? ""
        self.noteText = notes
        self.originalNoteText = notes

        // Bug d40120ea — use safeRegion so NaN/infinite coords from any
        // upstream geocoder never reach MKCoordinateRegion (which asserts
        // and crashes).
        if let coordinate = project.coordinate,
           let region = Self.safeMapRegion(center: coordinate, delta: 0.01) {
            self.addressMapRegion = region
        } else {
            self.addressMapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }

    /// Build an `MKCoordinateRegion` only when the inputs are finite.
    /// MapKit raises an assertion (which crashes in release) when handed
    /// NaN or infinite center coordinates. Guard every caller through this
    /// helper to keep the save path crash-proof for custom address text.
    private static func safeMapRegion(center: CLLocationCoordinate2D, delta: Double) -> MKCoordinateRegion? {
        guard center.latitude.isFinite,
              center.longitude.isFinite,
              abs(center.latitude) <= 90,
              abs(center.longitude) <= 180,
              delta.isFinite, delta > 0 else {
            return nil
        }
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
        )
    }

    // MARK: - Permissions

    /// Bug G9 — the user has view access to this project ONLY because they were
    /// tagged in a note. They can read and reply to notes, but cannot edit
    /// project details, tasks, schedule, team, etc.
    var isMentionOnlyAccess: Bool {
        guard let userId = dataController?.currentUser?.id else { return false }
        return ProjectAccessHelper.isMentionOnly(project, userId: userId)
    }

    var canEditProject: Bool {
        // Mention-only users cannot edit any project field (Bug G9, Rule 1+2).
        if isMentionOnlyAccess { return false }
        return PermissionStore.shared.can("projects.edit")
    }

    var canEditVinylOrderMarker: Bool {
        canEditProject
            && PermissionStore.shared.isFeatureEnabled("deck_builder")
            && PermissionStore.shared.can("deck_builder.view", requiredScope: "assigned")
    }

    var hasClientContact: Bool {
        project.hasAnyClientContactInfo
    }

    // MARK: - Map Computed Properties

    var projectTaskColorHexes: [String] {
        project.tasks
            .filter { $0.deletedAt == nil && $0.status == .active }
            .map { $0.effectiveColor }
    }

    var pinLabel: String {
        guard let address = project.address, !address.isEmpty else {
            return project.title
        }
        let street = address.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? address
        return street.isEmpty ? project.title : street
    }

    /// Nearby projects for the map (excludes the current project)
    var nearbyProjectPins: [NearbyProjectPin] {
        guard let context = dataController?.modelContext,
              let currentCoord = project.coordinate else { return [] }

        do {
            var descriptor = FetchDescriptor<Project>(
                predicate: #Predicate<Project> { p in
                    p.deletedAt == nil && p.latitude != nil && p.longitude != nil
                }
            )
            descriptor.fetchLimit = 50
            let allProjects = try context.fetch(descriptor)

            return allProjects
                .filter { $0.id != project.id }
                .compactMap { p -> NearbyProjectPin? in
                    guard let coord = p.coordinate else { return nil }
                    let distance = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
                        .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                    // Show projects within ~15 km
                    guard distance < 15_000 else { return nil }
                    return NearbyProjectPin(
                        id: p.id,
                        coordinate: coord,
                        name: p.title,
                        status: p.status,
                        taskColorHexes: p.tasks
                            .filter { $0.deletedAt == nil && $0.status == .active }
                            .map { $0.effectiveColor }
                    )
                }
        } catch {
            print("[PROJECT_DETAILS] Failed to fetch nearby projects: \(error)")
            return []
        }
    }

    // MARK: - Expense Total

    var expenseTotal: Double {
        projectExpenses.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Actions

    func openDirections() {
        guard let address = project.address, !address.isEmpty else { return }
        let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address
        if let url = URL(string: "http://maps.apple.com/?daddr=\(encodedAddress)&dirflg=d") {
            UIApplication.shared.open(url)
        }
    }

    func callPhone(_ phone: String) {
        let cleanedPhone = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        if let url = URL(string: "tel://\(cleanedPhone)") {
            UIApplication.shared.open(url)
        }
    }

    func sendEmail(_ email: String) {
        if let url = URL(string: "mailto:\(email)") {
            UIApplication.shared.open(url)
        }
    }

    func sendText(_ phone: String) {
        let cleanedPhone = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        if let url = URL(string: "sms:\(cleanedPhone)") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Task Actions

    func toggleTaskStatus() {
        guard let task = selectedTask else { return }
        let newStatus = task.status.toggled()

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        Task {
            do {
                try await dataController?.updateTaskStatus(task: task, to: newStatus)
                print("[TASK_TOGGLE] Task \(task.id) status toggled to \(newStatus.displayName)")
            } catch {
                print("[TASK_TOGGLE] Failed to toggle task status: \(error)")
            }
        }
    }

    func deleteSelectedTask() {
        guard let task = selectedTask else { return }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        selectedTask = nil

        Task {
            do {
                try await dataController?.deleteTask(task)
                print("[TASK_DELETE] Task \(task.id) deleted")
            } catch {
                print("[TASK_DELETE] Failed to delete task: \(error)")
            }
        }
    }

    func cancelSelectedTask() {
        guard let task = selectedTask else { return }

        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        Task {
            do {
                try await dataController?.updateTaskStatus(task: task, to: .cancelled)
                print("[TASK_CANCEL] Task \(task.id) cancelled")
            } catch {
                print("[TASK_CANCEL] Failed to cancel task: \(error)")
            }
        }
    }

    // MARK: - Project Actions

    func handleProjectCompletion() {
        guard let appState = appState else { return }
        if appState.requestProjectCompletion(project) {
            markProjectComplete()
        }
    }

    func markProjectComplete() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()

        Task { @MainActor in
            let incompleteTasks = project.tasks.filter { $0.status != .completed && $0.status != .cancelled && $0.deletedAt == nil }
            for task in incompleteTasks {
                do {
                    try await dataController?.updateTaskStatus(task: task, to: .completed)
                } catch {
                    print("[PROJECT_COMPLETE] Failed to complete task \(task.id): \(error)")
                }
            }
            do {
                try await dataController?.updateProjectStatus(
                    project: project,
                    to: .completed
                )
                print("[PROJECT_COMPLETE] ✅ Project marked complete: \(project.title)")
            } catch {
                print("[PROJECT_COMPLETE] ❌ Failed to mark project complete: \(error)")
            }
        }
    }

    func markProjectClosed() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            do {
                try await dataController?.updateProjectStatus(
                    project: project,
                    to: .closed
                )
                print("[PROJECT_CLOSE] Project marked closed: \(project.title)")
            } catch {
                print("[PROJECT_CLOSE] ❌ Failed to mark project closed: \(error)")
            }
        }
    }

    func deleteProject() {
        let projectTitle = project.title
        print("[PROJECT_DETAILS] Starting soft delete for project: \(projectTitle)")

        Task {
            do {
                try await dataController?.deleteProject(project)
                print("[PROJECT_DETAILS] Project '\(projectTitle)' soft deleted successfully")
            } catch {
                print("[PROJECT_DETAILS] Failed to soft delete project: \(error)")
            }
        }
    }

    // MARK: - Title Editing

    func saveTitle() {
        guard !editedTitle.isEmpty, editedTitle != project.title else {
            isEditingTitle = false
            return
        }

        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        Task {
            do {
                project.title = editedTitle
                project.needsSync = true
                try dataController?.modelContext?.save()

                try await dataController?.updateProjectFields(
                    projectId: project.id,
                    fields: ["title": .string(editedTitle)]
                )

                project.needsSync = false
                project.lastSyncedAt = Date()
                try? dataController?.modelContext?.save()
                isEditingTitle = false
                showSaveNotification()
            } catch {
                print("Failed to save title: \(error)")
            }
        }
    }

    // MARK: - Description Editing

    func saveDescription() {
        project.projectDescription = editingProjectDetailsText.isEmpty ? nil : editingProjectDetailsText
        isEditingProjectDetails = false
        editingProjectDetailsText = ""

        Task {
            try? dataController?.modelContext?.save()
            project.needsSync = true
        }
    }

    func setVinylOrdered(_ ordered: Bool) {
        guard canEditVinylOrderMarker,
              let dataController,
              let userId = dataController.currentUser?.id
                    ?? SupabaseService.shared.currentUserId
                    ?? UserDefaults.standard.string(forKey: "currentUserId"),
              !isUpdatingVinylOrderMarker else {
            return
        }

        let now = Date()
        let fields: [String: AnyJSON]
        if ordered {
            fields = [
                ProjectVinylOrderFields.status: .string(ProjectVinylOrderStatus.ordered.rawValue),
                ProjectVinylOrderFields.orderedAt: .string(SupabaseDate.format(now)),
                ProjectVinylOrderFields.orderedBy: .string(userId)
            ]
        } else {
            fields = [
                ProjectVinylOrderFields.status: .string(ProjectVinylOrderStatus.notOrdered.rawValue),
                ProjectVinylOrderFields.orderedAt: .null,
                ProjectVinylOrderFields.orderedBy: .null
            ]
        }

        isUpdatingVinylOrderMarker = true
        Task {
            do {
                try await dataController.updateProjectFields(projectId: project.id, fields: fields)
                await MainActor.run {
                    isUpdatingVinylOrderMarker = false
                    showSaveNotification()
                }
            } catch {
                await MainActor.run {
                    isUpdatingVinylOrderMarker = false
                    networkErrorMessage = "VINYL STATUS FAILED"
                    showingNetworkError = true
                }
                print("[PROJECT_DETAILS] Failed to update vinyl marker: \(error)")
            }
        }
    }

    // MARK: - Address

    /// True while an updateProjectAddress call is in flight. Prevents a
    /// double-tap on SAVE from racing two writes against the same project.
    private var isSavingAddress = false

    func saveAddress() {
        guard !isSavingAddress else {
            print("[PROJECT_DETAILS] ⚠️ Address save already in progress — ignoring")
            return
        }
        isSavingAddress = true

        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Capture on the main actor before hopping to the task.
        let addressToSave = editedAddress

        Task { @MainActor in
            defer { isSavingAddress = false }
            do {
                try await dataController?.updateProjectAddress(project: project, address: addressToSave)
                // Refresh the map region if coordinates changed. safeMapRegion
                // silently rejects NaN/infinite inputs so custom address text
                // that fails geocoding leaves the region on its last valid
                // value rather than crashing MapKit.
                if let coordinate = project.coordinate,
                   let region = Self.safeMapRegion(center: coordinate, delta: 0.01) {
                    addressMapRegion = region
                }
                showSaveNotification()
            } catch {
                // Never crash the save path — address text has already been
                // persisted by updateProjectAddress before its throw point
                // for any non-geocoder error. Log and keep the UI alive.
                print("[PROJECT_DETAILS] Failed to save address: \(error.localizedDescription)")
            }
        }
        showingAddressEditor = false
    }

    /// Called when ProjectDetailsView appears. If the project has a non-empty
    /// address but missing coordinates (legacy Bubble import, failed prior
    /// geocode, or sync race), forward-geocode it now so the map pin snaps
    /// to the right spot instead of falling back to the SF default.
    func geocodeAddressIfNeeded() {
        guard let address = project.address?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty,
              project.coordinate == nil,
              !isGeocodingAddress else {
            return
        }

        isGeocodingAddress = true

        Task { @MainActor in
            defer { isGeocodingAddress = false }

            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.geocodeAddressString(address)
                guard let location = placemarks.first?.location else {
                    print("[PROJECT_DETAILS] Geocode-on-load: no placemarks for \"\(address)\"")
                    return
                }

                // Validate coordinate is finite and in-range before writing.
                // Defensive: a malformed placemark can produce NaN/infinite
                // coords which would crash MapKit when bound to a region.
                let coord = location.coordinate
                guard coord.latitude.isFinite,
                      coord.longitude.isFinite,
                      abs(coord.latitude) <= 90,
                      abs(coord.longitude) <= 180,
                      !(abs(coord.latitude) < 0.0001 && abs(coord.longitude) < 0.0001) else {
                    print("[PROJECT_DETAILS] Geocode-on-load: invalid coord (\(coord.latitude), \(coord.longitude)) for \"\(address)\" — skipping")
                    return
                }

                // Race guard: if the user edited the address while we were
                // awaiting the geocoder, bail rather than stamping stale
                // coords on top of the fresh edit.
                let currentAddress = project.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard currentAddress == address else {
                    print("[PROJECT_DETAILS] Geocode-on-load: address changed mid-flight (\"\(address)\" → \"\(currentAddress)\") — skipping write")
                    return
                }

                // Also skip if saveAddress already hydrated coords while we
                // were awaiting.
                guard project.coordinate == nil else {
                    print("[PROJECT_DETAILS] Geocode-on-load: coords already set — skipping write")
                    return
                }

                // Write back to the project so the map renders and subsequent
                // loads don't repeat the lookup. Queue a sync so the server
                // row gets the coords too.
                project.latitude = coord.latitude
                project.longitude = coord.longitude
                project.needsSync = true
                try? dataController?.modelContext?.save()

                dataController?.syncEngine.recordOperation(
                    entityType: .project,
                    entityId: project.id,
                    operationType: "update",
                    changedFields: [
                        "latitude": coord.latitude,
                        "longitude": coord.longitude
                    ]
                )

                if let region = Self.safeMapRegion(center: location.coordinate, delta: 0.01) {
                    addressMapRegion = region
                }
                print("[PROJECT_DETAILS] ✅ Geocode-on-load hydrated coords for \"\(address)\"")
            } catch {
                print("[PROJECT_DETAILS] Geocode-on-load failed for \"\(address)\": \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Schedule

    func handleTaskScheduleUpdate(startDate: Date, endDate: Date) {
        // Scheduling is gated on calendar.edit, scope-aware (own-scope → only the
        // user's own tasks). Definitive gate for every reschedule entry point.
        guard let task = selectedTask, let dataController, task.canEditSchedule else { return }
        // Route through updateTaskSchedule — the single source of truth, which
        // enqueues an outbound SyncOperation via recordOperation. The previous
        // implementation only mutated the local model and set needsSync, but
        // needsSync is a conflict-resolution flag, NOT an outbound trigger: there
        // is no needsSync sweep for project_tasks (only photos have one), so the
        // schedule updated on-device but never reached the server.
        Task { @MainActor in
            do {
                try await dataController.updateTaskSchedule(
                    task: task, startDate: startDate, endDate: endDate
                )
            } catch {
                print("[PROJECT_DETAILS] Failed to sync task schedule update: \(error)")
            }
        }
    }

    // MARK: - Photos

    func addPhotosToProject(tutorialMode: Bool) {
        if tutorialMode {
            NotificationCenter.default.post(name: Notification.Name("TutorialPhotoAdded"), object: nil)
        }

        let photoCount = selectedImages.count
        processingImages = true

        Task {
            if let imageSyncManager = dataController?.imageSyncManager {
                let urls = await imageSyncManager.saveImages(selectedImages, for: project)
                if !urls.isEmpty {
                    // Track photo capture
                    AnalyticsService.shared.track(
                        eventType: .action,
                        eventName: "photo_captured",
                        properties: ["count": photoCount, "context": "project"]
                    )
                    selectedImages.removeAll()
                    processingImages = false
                } else {
                    processingImages = false
                    showingNetworkError = true
                    networkErrorMessage = "Failed to upload images. Please check your network connection."
                }
            } else {
                // Fallback: compress and save locally
                for image in selectedImages {
                    guard let imageData = image.jpegData(compressionQuality: 0.7) else { continue }
                    let localID = "project_\(project.id)_\(UUID().uuidString).jpg"
                    let success = ImageFileManager.shared.saveImage(data: imageData, localID: localID)
                    if success {
                        var images = project.getProjectImages()
                        images.append("local://project_images/\(localID)")
                        project.setProjectImageURLs(images)
                    }
                }
                // Track photo capture (local fallback path)
                AnalyticsService.shared.track(
                    eventType: .action,
                    eventName: "photo_captured",
                    properties: ["count": photoCount, "context": "project"]
                )
                selectedImages.removeAll()
                processingImages = false
            }
        }
    }

    // MARK: - Expenses

    func loadExpenses() async {
        guard let dc = dataController,
              let companyId = dc.currentUser?.companyId else { return }

        isLoadingExpenses = true
        expenseError = nil

        do {
            let repo = ExpenseRepository(companyId: companyId)
            projectExpenses = try await repo.fetchByProject(project.id)
            isLoadingExpenses = false
        } catch {
            expenseError = error.localizedDescription
            isLoadingExpenses = false
            print("[EXPENSES] Failed to load project expenses: \(error)")
        }
    }

    // MARK: - Task Team

    func loadTaskTeamMembers() {
        guard let companyId = dataController?.currentUser?.companyId,
              let dc = dataController else { return }
        taskTeamMembers = dc.getTeamMembers(companyId: companyId).map { TeamMember.fromUser($0) }
    }

    func saveTaskTeamChanges() {
        guard let task = selectedTask else { return }
        let previousIds = Set(task.getTeamMemberIds())

        if previousIds != selectedTaskTeamMemberIds {
            // Route through the typed `updateTaskTeamMembers` helper instead
            // of the generic `updateTaskFields(team_member_ids: .string(csv))`
            // path. The server column is a Postgres `uuid[]`; a comma-string
            // either fails the cast outright or gets accepted as a single
            // bogus uuid string depending on PostgREST coercion. The typed
            // helper also rolls up project-level team members from tasks and
            // sends push notifications to newly-assigned members — matching
            // the invariants the TaskFormSheet edit path already enforces.
            let memberIds = Array(selectedTaskTeamMemberIds)
            Task { @MainActor in
                do {
                    try await dataController?.updateTaskTeamMembers(task: task, memberIds: memberIds)
                } catch {
                    print("[PROJECT_DETAILS] Failed to save task team members: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Client

    func refreshClientData() {
        guard let clientId = project.clientId, !isRefreshingClient else { return }
        isRefreshingClient = true

        Task {
            try? await dataController?.refreshSingleClient(clientId: clientId)
            isRefreshingClient = false
        }
    }

    // MARK: - Unsaved Changes

    func checkForUnsavedChanges() -> Bool {
        return noteText != originalNoteText
    }

    // MARK: - Save Notification

    func showSaveNotification() {
        notificationTimer?.invalidate()
        showingSaveNotification = true
        notificationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.showingSaveNotification = false
            }
        }
        originalNoteText = noteText
    }

    // MARK: - Helpers

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
