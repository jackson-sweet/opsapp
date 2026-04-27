//
//  ProjectNotesViewModel.swift
//  OPS
//
//  ViewModel for the per-project message board.
//

import SwiftUI
import SwiftData

@MainActor
class ProjectNotesViewModel: ObservableObject {
    @Published var notes: [ProjectNote] = []
    @Published var newNoteText: String = ""
    @Published var mentionSuggestions: [TeamMember] = []
    @Published var isLoading = false
    @Published var error: String? = nil
    @Published var showMentionPicker = false
    @Published var showAllTeamOption = false
    @Published var pendingImages: [UIImage] = []
    @Published var isUploading = false

    let projectId: String
    private var repository: ProjectNoteRepository?
    private var companyId: String?
    private var currentUserId: String?
    private var allTeamMembers: [TeamMember] = []
    private var modelContext: ModelContext?
    private weak var dataController: DataController?
    private var notificationObserver: NSObjectProtocol?

    init(projectId: String) {
        self.projectId = projectId
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setup(companyId: String, currentUserId: String, teamMembers: [TeamMember], modelContext: ModelContext, dataController: DataController? = nil) {
        self.companyId = companyId
        self.currentUserId = currentUserId
        self.allTeamMembers = teamMembers
        self.modelContext = modelContext
        self.dataController = dataController
        self.repository = ProjectNoteRepository(companyId: companyId)

        // Listen for realtime note updates
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .projectNoteReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let incomingProjectId = notification.userInfo?["projectId"] as? String,
                  incomingProjectId == self.projectId else { return }
            Task { @MainActor in
                self.loadNotesFromLocal()
            }
        }
    }

    // MARK: - Load

    func loadNotes() async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await repo.fetchForProject(projectId)
            // Upsert into SwiftData
            if let context = modelContext {
                for dto in dtos {
                    let model = dto.toModel()
                    model.lastSyncedAt = Date()
                    model.needsSync = false
                    let noteId = dto.id
                    let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == noteId })
                    if let existing = try? context.fetch(descriptor).first {
                        existing.content = model.content
                        existing.attachmentsJSON = model.attachmentsJSON
                        existing.mentionedUserIdsString = model.mentionedUserIdsString
                        existing.photoURL = model.photoURL
                        existing.updatedAt = model.updatedAt
                        existing.deletedAt = model.deletedAt
                        existing.lastSyncedAt = Date()
                    } else {
                        context.insert(model)
                    }
                }
                try? context.save()
            }
            loadNotesFromLocal()
        } catch {
            if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
            // Fall back to local data
            loadNotesFromLocal()
        }
    }

    private func loadNotesFromLocal() {
        guard let context = modelContext else { return }
        let pid = projectId
        let descriptor = FetchDescriptor<ProjectNote>(
            predicate: #Predicate { $0.projectId == pid && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        notes = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Pending Images

    func addImage(_ image: UIImage) {
        pendingImages.append(image)
    }

    func removeImage(at index: Int) {
        guard pendingImages.indices.contains(index) else { return }
        pendingImages.remove(at: index)
    }

    /// Whether the send button should be enabled (text or images present)
    var canPost: Bool {
        !newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
    }

    // MARK: - Post

    func postNote() async {
        let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImages = !pendingImages.isEmpty
        guard !text.isEmpty || hasImages else { return }

        guard let repo = repository,
              let companyId = companyId,
              let currentUserId = currentUserId else {
            self.error = "Not signed in — please restart the app"
            print("[NOTES] postNote guard failed: repo=\(repository != nil) companyId=\(self.companyId ?? "nil") userId=\(self.currentUserId ?? "nil")")
            return
        }

        // Extract @mentions
        let mentionedIds = extractMentionedUserIds(from: text)

        // Upload images if any
        var attachmentURLs: [String] = []
        if hasImages {
            isUploading = true
            let imagesToUpload = pendingImages
            do {
                attachmentURLs = try await PresignedURLUploadService.shared.uploadNoteImages(
                    imagesToUpload,
                    projectId: projectId,
                    companyId: companyId
                )
            } catch {
                print("[NOTES] Image upload failed: \(error)")
                self.error = "Photo upload failed. Try again."
                isUploading = false
                return
            }
            isUploading = false

            // Also surface comment attachments in the project photo gallery.
            // Without this the image lives only on the note and never appears
            // in the project photo grid — which users expect as the single
            // place to see every photo taken on a project.
            await addAttachmentsToProjectGallery(attachmentURLs)
        }

        // Bug d77b49a2 — when the user uploads photos with no caption, leave
        // the content empty rather than substituting the literal "Photo".
        // The image attachments speak for themselves; the placeholder added
        // visual noise to every photo-only comment.
        let noteContent = text

        let dto = CreateProjectNoteDTO(
            projectId: projectId,
            companyId: companyId,
            authorId: currentUserId,
            content: noteContent,
            mentionedUserIds: mentionedIds,
            attachments: attachmentURLs
        )

        // Optimistic insert
        let optimisticNote = ProjectNote(
            projectId: projectId,
            companyId: companyId,
            authorId: currentUserId,
            content: noteContent
        )
        optimisticNote.mentionedUserIds = mentionedIds
        optimisticNote.attachments = attachmentURLs
        optimisticNote.needsSync = true
        if let context = modelContext {
            context.insert(optimisticNote)
            try? context.save()
        }
        loadNotesFromLocal()
        newNoteText = ""
        pendingImages = []
        showMentionPicker = false
        showAllTeamOption = false
        mentionSuggestions = []
        NotificationCenter.default.post(name: Notification.Name("WizardNotePosted"), object: nil)

        do {
            let created = try await repo.create(dto)
            // Replace optimistic note with server version
            if let context = modelContext {
                let optimisticId = optimisticNote.id
                let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == optimisticId })
                if let existing = try? context.fetch(descriptor).first {
                    context.delete(existing)
                }
                let serverModel = created.toModel()
                serverModel.lastSyncedAt = Date()
                serverModel.needsSync = false
                context.insert(serverModel)
                try? context.save()
            }
            loadNotesFromLocal()

            // Send push notifications for mentions
            await sendMentionNotifications(mentionedIds: mentionedIds, noteText: noteContent, noteId: created.id, attachmentURLs: attachmentURLs)

            // Send push notifications to project team members (excluding author and already-mentioned users)
            await sendNoteAddedNotifications(mentionedIds: mentionedIds, noteText: noteContent, noteId: created.id, attachmentURLs: attachmentURLs)
        } catch {
            if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
            // Revert: remove the optimistic note that failed to sync
            if let context = modelContext {
                let optimisticId = optimisticNote.id
                let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == optimisticId })
                if let orphan = try? context.fetch(descriptor).first {
                    context.delete(orphan)
                    try? context.save()
                }
            }
            loadNotesFromLocal()
        }
    }

    // MARK: - Gallery Sync

    /// Append note-comment attachments to the project's photo gallery and
    /// queue a Supabase sync op so the gallery stays in sync on other
    /// devices. Called from `postNote()` after the note images upload
    /// successfully. No-op when called with an empty URL list.
    private func addAttachmentsToProjectGallery(_ urls: [String]) async {
        guard !urls.isEmpty, let context = modelContext else { return }

        let pid = projectId
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == pid })
        guard let project = try? context.fetch(descriptor).first else { return }

        var gallery = project.getProjectImageURLs()
        var added = false
        for url in urls where !gallery.contains(url) {
            gallery.append(url)
            added = true
        }
        guard added else { return }

        project.setProjectImageURLs(gallery)
        project.needsSync = true
        project.syncPriority = 2
        try? context.save()

        // Queue a Supabase update op via DataController if it was injected.
        // We build the AnyJSON directly here because updateProjectFields'
        // local-apply switch doesn't know about project_images yet — the
        // local write above already covers that side.
        guard let dataController = dataController else { return }
        do {
            try await dataController.updateProjectFields(
                projectId: pid,
                fields: [
                    "project_images": .array(gallery.map { .string($0) })
                ]
            )
        } catch {
            print("[NOTES] Failed to queue project_images sync op: \(error)")
        }
    }

    // MARK: - Delete

    func deleteNote(_ note: ProjectNote) async {
        guard let repo = repository else { return }

        // Optimistic soft delete
        note.deletedAt = Date()
        if let context = modelContext {
            try? context.save()
        }
        loadNotesFromLocal()

        do {
            try await repo.softDelete(note.id)
        } catch {
            // Revert on failure
            note.deletedAt = nil
            if let context = modelContext {
                try? context.save()
            }
            loadNotesFromLocal()
            if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Mention Handling

    func handleMentionInput(_ text: String) {
        // Find the last @ symbol and extract the partial name after it
        guard let atRange = text.range(of: "@", options: .backwards) else {
            showMentionPicker = false
            showAllTeamOption = false
            mentionSuggestions = []
            return
        }

        let afterAt = String(text[atRange.upperBound...])

        // If there's a space after the partial name, mention is complete
        // But not if the text is a prefix of "All Team" (user still typing multi-word mention)
        if afterAt.contains(" ") && afterAt.last == " " {
            let partial = afterAt.trimmingCharacters(in: .whitespaces).lowercased()
            let isPartialAllTeam = "all team".hasPrefix(partial) && partial != "all team"
            let isPartialMemberName = allTeamMembers.contains { member in
                let fullName = member.fullName.lowercased()
                return fullName.hasPrefix(partial) && fullName != partial
            }
            if !isPartialAllTeam && !isPartialMemberName {
                showMentionPicker = false
                showAllTeamOption = false
                mentionSuggestions = []
                return
            }
        }

        let query = afterAt.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            // Show all team members + @All when just "@" is typed
            mentionSuggestions = allTeamMembers
            showAllTeamOption = true
        } else {
            mentionSuggestions = allTeamMembers.filter {
                $0.fullName.lowercased().contains(query) ||
                $0.firstName.lowercased().hasPrefix(query) ||
                $0.lastName.lowercased().hasPrefix(query)
            }
            showAllTeamOption = "all team".hasPrefix(query)
        }
        showMentionPicker = !mentionSuggestions.isEmpty || showAllTeamOption
    }

    func insertMention(_ member: TeamMember) {
        // Replace the partial @mention with the full name
        guard let atRange = newNoteText.range(of: "@", options: .backwards) else { return }
        newNoteText = String(newNoteText[..<atRange.lowerBound]) + "@\(member.fullName) "
        showMentionPicker = false
        showAllTeamOption = false
        mentionSuggestions = []
    }

    func insertAllTeamMention() {
        // Replace the partial @mention with @All Team
        guard let atRange = newNoteText.range(of: "@", options: .backwards) else { return }
        newNoteText = String(newNoteText[..<atRange.lowerBound]) + "@All Team "
        showMentionPicker = false
        showAllTeamOption = false
        mentionSuggestions = []
    }

    /// Look up author name from team members
    func authorName(for authorId: String) -> String {
        if let member = allTeamMembers.first(where: { $0.id == authorId }) {
            return member.fullName
        }
        return "Team Member"
    }

    /// Look up author avatar URL from team members
    func authorAvatarURL(for authorId: String) -> String? {
        allTeamMembers.first(where: { $0.id == authorId })?.avatarURL
    }

    /// Check if the current user authored a note
    func isOwnNote(_ note: ProjectNote) -> Bool {
        note.authorId == currentUserId
    }

    /// Look up TeamMember for a given author ID
    func teamMember(for authorId: String) -> TeamMember? {
        allTeamMembers.first(where: { $0.id == authorId })
    }

    /// Count comments associated with a photo URL
    func commentCount(forPhotoURL url: String) -> Int {
        notes.filter { note in
            note.photoURL == url || note.attachments.contains(url)
        }.count
    }

    /// Update the content of an existing note
    func updateNoteContent(_ note: ProjectNote, newContent: String) async {
        guard let repo = repository, let context = modelContext else { return }
        let oldContent = note.content
        // Optimistic update
        note.content = newContent
        note.updatedAt = Date()
        try? context.save()
        loadNotesFromLocal()

        do {
            try await repo.updateContent(note.id, content: newContent)
        } catch {
            // Revert on failure
            note.content = oldContent
            try? context.save()
            loadNotesFromLocal()
            if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Private Helpers

    private func extractMentionedUserIds(from text: String) -> [String] {
        // @All Team means notify everyone except self
        if text.contains("@All Team") {
            return allTeamMembers
                .filter { $0.id != currentUserId }
                .map { $0.id }
        }

        var ids: [String] = []
        for member in allTeamMembers {
            if text.contains("@\(member.fullName)") {
                ids.append(member.id)
            }
        }
        return ids
    }

    private func sendMentionNotifications(mentionedIds: [String], noteText: String, noteId: String, attachmentURLs: [String] = []) async {
        guard !mentionedIds.isEmpty else { return }
        guard let companyId = companyId else { return }

        let authorName = currentUserId.flatMap { id in
            allTeamMembers.first(where: { $0.id == id })?.fullName
        } ?? "A team member"

        // Get project name for notification
        let projectName: String
        if let context = modelContext {
            let pid = projectId
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == pid })
            projectName = (try? context.fetch(descriptor).first?.title) ?? "a project"
        } else {
            projectName = "a project"
        }

        let firstImageUrl = attachmentURLs.first
        let preview = noteText.count > 100 ? String(noteText.prefix(100)) + "..." : noteText
        let notificationRepo = NotificationRepository()

        for userId in mentionedIds {
            // 1. Create in-app notification in Supabase (guaranteed delivery)
            do {
                let dto = NotificationRepository.CreateNotificationDTO(
                    userId: userId,
                    companyId: companyId,
                    type: "mention",
                    title: "\(authorName) mentioned you",
                    body: "\"\(preview)\" on \(projectName)",
                    projectId: projectId,
                    noteId: noteId,
                    expenseId: nil,
                    batchId: nil,
                    deepLinkType: "projectNotes"
                )
                try await notificationRepo.createNotification(dto)
                print("[PROJECT NOTES] In-app mention notification created for user: \(userId)")
            } catch {
                print("[PROJECT NOTES] Failed to create in-app mention notification for \(userId): \(error)")
            }

            // 2. Send push notification via OneSignal (best-effort)
            do {
                try await OneSignalService.shared.notifyProjectNoteMention(
                    userId: userId,
                    authorName: authorName,
                    notePreview: noteText,
                    projectName: projectName,
                    projectId: projectId,
                    noteId: noteId,
                    imageUrl: firstImageUrl
                )
            } catch {
                print("[PROJECT NOTES] Failed to send push mention notification to \(userId): \(error)")
            }
        }
    }

    /// Notify project team members when a note is added.
    /// Excludes the author (self) and anyone already @mentioned (they got a mention push).
    private func sendNoteAddedNotifications(mentionedIds: [String], noteText: String, noteId: String, attachmentURLs: [String] = []) async {
        guard UserDefaults.standard.bool(forKey: "notifyProjectNoteAdded") else { return }
        guard let currentUserId = currentUserId, let companyId = companyId else { return }

        // Get project and its team member IDs
        guard let context = modelContext else { return }
        let pid = projectId
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == pid })
        guard let project = try? context.fetch(descriptor).first else { return }

        let projectTeamIds = project.getTeamMemberIds()
        guard !projectTeamIds.isEmpty else { return }

        // Exclude: self + already @mentioned users
        let excludeIds = Set([currentUserId] + mentionedIds)
        let recipientIds = projectTeamIds.filter { !excludeIds.contains($0) }
        guard !recipientIds.isEmpty else { return }

        let authorName = allTeamMembers.first(where: { $0.id == currentUserId })?.fullName ?? "A team member"
        let firstImageUrl = attachmentURLs.first
        let preview = noteText.count > 100 ? String(noteText.prefix(100)) + "..." : noteText
        let notificationRepo = NotificationRepository()

        // 1. Create in-app notifications in Supabase for each recipient
        for recipientId in recipientIds {
            do {
                let dto = NotificationRepository.CreateNotificationDTO(
                    userId: recipientId,
                    companyId: companyId,
                    type: "project_note",
                    title: "\(authorName) added a note",
                    body: "\"\(preview)\" on \(project.title)",
                    projectId: projectId,
                    noteId: noteId,
                    expenseId: nil,
                    batchId: nil,
                    deepLinkType: "projectNotes"
                )
                try await notificationRepo.createNotification(dto)
            } catch {
                print("[PROJECT NOTES] Failed to create in-app note-added notification for \(recipientId): \(error)")
            }
        }

        // 2. Send push notification via OneSignal (best-effort)
        do {
            try await OneSignalService.shared.notifyProjectNoteAdded(
                userIds: recipientIds,
                authorName: authorName,
                notePreview: noteText,
                projectName: project.title,
                projectId: projectId,
                noteId: noteId,
                imageUrl: firstImageUrl
            )
        } catch {
            print("[PROJECT NOTES] Failed to send push note-added notification: \(error)")
        }
    }
}
