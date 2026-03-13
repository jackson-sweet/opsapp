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

/// Tab options for the redesigned project details view
enum ProjectDetailTab: String, CaseIterable {
    case activity = "ACTIVITY"
    case details = "DETAILS"
    case expenses = "EXPENSES"
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
    @Published var showingScheduler = false
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

        if let coordinate = project.coordinate {
            self.addressMapRegion = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        } else {
            self.addressMapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }

    // MARK: - Permissions

    var canEditProject: Bool {
        return PermissionStore.shared.can("projects.edit")
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

        Task {
            let incompleteTasks = project.tasks.filter { $0.status != .completed && $0.status != .cancelled }
            for task in incompleteTasks {
                do {
                    try await dataController?.updateTaskStatus(task: task, to: .completed)
                } catch {
                    print("[PROJECT_COMPLETE] Failed to complete task \(task.id): \(error)")
                }
            }
            try? await dataController?.syncManager?.updateProjectStatus(
                projectId: project.id,
                status: .completed,
                forceSync: true
            )
        }
    }

    func markProjectClosed() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()

        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            try? await dataController?.syncManager?.updateProjectStatus(
                projectId: project.id,
                status: .closed,
                forceSync: true
            )
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

                try await dataController?.syncManager.updateProjectFields(
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

    // MARK: - Address

    func saveAddress() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        Task {
            do {
                try await dataController?.updateProjectAddress(project: project, address: editedAddress)
            } catch {
                print("Failed to save address: \(error)")
            }
        }
        showingAddressEditor = false
    }

    // MARK: - Schedule

    func handleScheduleUpdate(startDate: Date, endDate: Date) {
        Task {
            do {
                try await dataController?.updateProjectDates(project: project, startDate: startDate, endDate: endDate)
            } catch {
                print("Failed to update schedule: \(error)")
            }
        }
    }

    func handleClearDates() {
        Task {
            do {
                try await dataController?.updateProjectDates(project: project, startDate: nil, endDate: nil, clearDates: true)
            } catch {
                print("Failed to clear dates: \(error)")
            }
        }
    }

    func handleTaskScheduleUpdate(startDate: Date, endDate: Date) {
        guard let task = selectedTask else { return }
        task.updateDates(startDate: startDate, endDate: endDate)
        task.needsSync = true
        try? dataController?.modelContext?.save()
    }

    // MARK: - Photos

    func addPhotosToProject(tutorialMode: Bool) {
        if tutorialMode {
            NotificationCenter.default.post(name: Notification.Name("TutorialPhotoAdded"), object: nil)
        }

        processingImages = true

        Task {
            if let imageSyncManager = dataController?.imageSyncManager {
                let urls = await imageSyncManager.saveImages(selectedImages, for: project)
                if !urls.isEmpty {
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
        guard let company = dataController?.getCurrentUserCompany() else { return }
        taskTeamMembers = company.teamMembers
    }

    func saveTaskTeamChanges() {
        guard let task = selectedTask else { return }
        let previousIds = Set(task.getTeamMemberIds())

        if previousIds != selectedTaskTeamMemberIds {
            task.setTeamMemberIds(Array(selectedTaskTeamMemberIds))
            task.needsSync = true
            try? dataController?.modelContext?.save()

            Task {
                try? await dataController?.syncManager?.updateTaskTeamMembers(
                    taskId: task.id,
                    memberIds: Array(selectedTaskTeamMemberIds)
                )
            }
        }
    }

    // MARK: - Client

    func refreshClientData() {
        guard let clientId = project.clientId, !isRefreshingClient else { return }
        isRefreshingClient = true

        Task {
            try? await dataController?.syncManager?.refreshSingleClient(clientId: clientId)
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
