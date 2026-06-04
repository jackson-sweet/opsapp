//
//  PhotoCommentsViewModel.swift
//  OPS
//
//  ViewModel for photo-level comments in the full-screen photo viewer.
//

import SwiftUI
import SwiftData

@MainActor
class PhotoCommentsViewModel: ObservableObject {
    @Published var comments: [ProjectNote] = []
    @Published var newCommentText: String = ""
    @Published var mentionSuggestions: [TeamMember] = []
    @Published var showMentionPicker = false
    @Published var showAllTeamOption = false
    @Published var isLoading = false
    @Published var error: String? = nil

    // Edit state
    @Published var editingNoteId: String? = nil
    @Published var editText: String = ""

    private(set) var photoURL: String
    let projectId: String
    private var repository: ProjectNoteRepository?
    private var companyId: String?
    private var currentUserId: String?
    private var allTeamMembers: [TeamMember] = []
    private var modelContext: ModelContext?
    private var loadTask: Task<Void, Never>?
    private var notificationObserver: NSObjectProtocol?

    init(photoURL: String, projectId: String) {
        self.photoURL = photoURL
        self.projectId = projectId
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setup(companyId: String, currentUserId: String, teamMembers: [TeamMember], modelContext: ModelContext) {
        self.companyId = companyId
        self.currentUserId = currentUserId
        self.allTeamMembers = teamMembers
        self.modelContext = modelContext
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
                self.loadCommentsFromLocal()
            }
        }
    }

    // MARK: - Load

    func loadComments() async {
        guard let repo = repository else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Fetch notes with photo_url match
            let photoDtos = try await repo.fetchForPhoto(photoURL, projectId: projectId)

            // Upsert into SwiftData
            if let context = modelContext {
                for dto in photoDtos {
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
            loadCommentsFromLocal()
        } catch {
            if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
            loadCommentsFromLocal()
        }
    }

    private func loadCommentsFromLocal() {
        guard let context = modelContext else { return }
        let pid = projectId
        let url = photoURL
        let descriptor = FetchDescriptor<ProjectNote>(
            predicate: #Predicate { $0.projectId == pid && $0.deletedAt == nil && $0.photoURL == url },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        var results = (try? context.fetch(descriptor)) ?? []

        // Also find notes whose attachments contain this photo URL (legacy notes with photo as attachment)
        let attachmentDescriptor = FetchDescriptor<ProjectNote>(
            predicate: #Predicate { $0.projectId == pid && $0.deletedAt == nil && $0.photoURL == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let attachmentNotes = (try? context.fetch(attachmentDescriptor)) ?? []
        for note in attachmentNotes {
            if note.attachments.contains(url) && !results.contains(where: { $0.id == note.id }) {
                results.append(note)
            }
        }

        // Sort merged results by createdAt
        results.sort { $0.createdAt < $1.createdAt }
        comments = results
    }

    // MARK: - Post

    func postComment() async {
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let repo = repository,
              let companyId = companyId,
              let currentUserId = currentUserId else { return }

        let mentionedIds = extractMentionedUserIds(from: text)

        let dto = CreateProjectNoteDTO(
            projectId: projectId,
            companyId: companyId,
            authorId: currentUserId,
            content: text,
            mentionedUserIds: mentionedIds,
            photoURL: photoURL
        )

        // Optimistic insert
        let optimisticNote = ProjectNote(
            projectId: projectId,
            companyId: companyId,
            authorId: currentUserId,
            content: text,
            photoURL: photoURL
        )
        optimisticNote.mentionedUserIds = mentionedIds
        optimisticNote.needsSync = true
        if let context = modelContext {
            context.insert(optimisticNote)
            try? context.save()
        }
        loadCommentsFromLocal()
        newCommentText = ""
        showMentionPicker = false
        showAllTeamOption = false
        mentionSuggestions = []

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
            loadCommentsFromLocal()

            // Send notifications
            await sendMentionNotifications(mentionedIds: mentionedIds, noteText: text, noteId: created.id)
            // Notify the photo's uploader (unless they're the commenter or were
            // already @mentioned above).
            await sendPhotoOwnerNotification(mentionedIds: mentionedIds, noteText: text, noteId: created.id)
        } catch {
            if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
            // Revert optimistic note
            if let context = modelContext {
                let optimisticId = optimisticNote.id
                let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == optimisticId })
                if let orphan = try? context.fetch(descriptor).first {
                    context.delete(orphan)
                    try? context.save()
                }
            }
            loadCommentsFromLocal()
        }
    }

    // MARK: - Delete

    func deleteComment(_ note: ProjectNote) async {
        guard let repo = repository else { return }
        note.deletedAt = Date()
        if let context = modelContext {
            try? context.save()
        }
        loadCommentsFromLocal()

        do {
            try await repo.softDelete(note.id)
        } catch {
            note.deletedAt = nil
            if let context = modelContext {
                try? context.save()
            }
            loadCommentsFromLocal()
            if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Edit

    func startEditing(_ note: ProjectNote) {
        editingNoteId = note.id
        editText = note.content
    }

    func cancelEditing() {
        editingNoteId = nil
        editText = ""
    }

    func saveEdit() async {
        guard let noteId = editingNoteId,
              let repo = repository,
              let context = modelContext else { return }
        let newContent = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newContent.isEmpty else { return }

        let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == noteId })
        guard let note = try? context.fetch(descriptor).first else { return }

        let oldContent = note.content
        note.content = newContent
        note.updatedAt = Date()
        try? context.save()
        loadCommentsFromLocal()
        editingNoteId = nil
        editText = ""

        do {
            try await repo.updateContent(noteId, content: newContent)
        } catch {
            note.content = oldContent
            try? context.save()
            loadCommentsFromLocal()
            if !(error is CancellationError) {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Switch Photo

    func switchPhoto(to newURL: String) {
        loadTask?.cancel()
        photoURL = newURL
        comments = []
        editingNoteId = nil
        editText = ""
        loadTask = Task {
            await loadComments()
        }
    }

    // MARK: - Mention Handling

    func handleMentionInput(_ text: String) {
        guard let atRange = text.range(of: "@", options: .backwards) else {
            showMentionPicker = false
            showAllTeamOption = false
            mentionSuggestions = []
            return
        }

        let afterAt = String(text[atRange.upperBound...])

        // Don't dismiss if user is still typing a multi-word mention like "All Team"
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
        guard let atRange = newCommentText.range(of: "@", options: .backwards) else { return }
        newCommentText = String(newCommentText[..<atRange.lowerBound]) + "@\(member.fullName) "
        showMentionPicker = false
        showAllTeamOption = false
        mentionSuggestions = []
    }

    func insertAllTeamMention() {
        guard let atRange = newCommentText.range(of: "@", options: .backwards) else { return }
        newCommentText = String(newCommentText[..<atRange.lowerBound]) + "@All Team "
        showMentionPicker = false
        showAllTeamOption = false
        mentionSuggestions = []
    }

    /// Look up author name from team members
    func authorName(for authorId: String) -> String {
        allTeamMembers.first(where: { $0.id == authorId })?.fullName ?? "Team Member"
    }

    /// Look up TeamMember for a given author ID
    func teamMember(for authorId: String) -> TeamMember? {
        allTeamMembers.first(where: { $0.id == authorId })
    }

    /// Check if the current user authored a note
    func isOwnComment(_ note: ProjectNote) -> Bool {
        note.authorId == currentUserId
    }

    // MARK: - Private Helpers

    private func extractMentionedUserIds(from text: String) -> [String] {
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

    private func sendMentionNotifications(mentionedIds: [String], noteText: String, noteId: String) async {
        guard !mentionedIds.isEmpty, let companyId = companyId else { return }

        let authorName = currentUserId.flatMap { id in
            allTeamMembers.first(where: { $0.id == id })?.fullName
        } ?? "A team member"

        let projectName: String
        if let context = modelContext {
            let pid = projectId
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == pid })
            projectName = (try? context.fetch(descriptor).first?.title) ?? "a project"
        } else {
            projectName = "a project"
        }

        let preview = noteText.count > 100 ? String(noteText.prefix(100)) + "..." : noteText
        let notificationRepo = NotificationRepository()

        for userId in mentionedIds {
            // Create in-app notification
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
            } catch {
                print("[PHOTO COMMENTS] Failed to create in-app mention notification for \(userId): \(error)")
            }
            // Send push
            do {
                try await OneSignalService.shared.notifyProjectNoteMention(
                    userId: userId,
                    authorName: authorName,
                    notePreview: noteText,
                    projectName: projectName,
                    projectId: projectId,
                    noteId: noteId
                )
            } catch {
                print("[PHOTO COMMENTS] Failed to send mention notification to \(userId): \(error)")
            }
        }
    }

    /// Notify the photo's uploader when someone else comments on their photo.
    /// The uploader is resolved from `project_photos.uploaded_by` for this
    /// photo URL. Excludes the commenter (self) and anyone already @mentioned
    /// (they received a mention notification). Best-effort.
    private func sendPhotoOwnerNotification(mentionedIds: [String], noteText: String, noteId: String) async {
        guard let companyId = companyId, let currentUserId = currentUserId else { return }

        // Resolve the photo's uploader from project_photos.
        struct OwnerRow: Decodable { let uploaded_by: String? }
        let ownerId: String?
        do {
            let rows: [OwnerRow] = try await SupabaseService.shared.client
                .from("project_photos")
                .select("uploaded_by")
                .eq("project_id", value: projectId)
                .eq("url", value: photoURL)
                .limit(1)
                .execute()
                .value
            ownerId = rows.first?.uploaded_by
        } catch {
            print("[PHOTO COMMENTS] Failed to resolve photo owner for comment notification: \(error)")
            return
        }

        guard let ownerId = ownerId, !ownerId.isEmpty,
              ownerId != currentUserId,
              !mentionedIds.contains(ownerId) else { return }

        let authorName = allTeamMembers.first(where: { $0.id == currentUserId })?.fullName ?? "A team member"
        let projectName: String = {
            guard let context = modelContext else { return "a project" }
            let pid = projectId
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == pid })
            return (try? context.fetch(descriptor).first?.title) ?? "a project"
        }()
        let preview = noteText.count > 100 ? String(noteText.prefix(100)) + "..." : noteText

        // In-app notification (guaranteed delivery)
        do {
            let dto = NotificationRepository.CreateNotificationDTO(
                userId: ownerId,
                companyId: companyId,
                type: "photo_comment",
                title: "\(authorName) commented on your photo",
                body: "\"\(preview)\" on \(projectName)",
                projectId: projectId,
                noteId: noteId,
                expenseId: nil,
                batchId: nil,
                deepLinkType: "projectNotes"
            )
            try await NotificationRepository().createNotification(dto)
        } catch {
            print("[PHOTO COMMENTS] Failed to create in-app photo-comment notification for \(ownerId): \(error)")
        }

        // Push (best-effort)
        do {
            try await OneSignalService.shared.notifyPhotoComment(
                userId: ownerId,
                authorName: authorName,
                notePreview: noteText,
                projectName: projectName,
                projectId: projectId,
                noteId: noteId,
                imageUrl: photoURL
            )
        } catch {
            print("[PHOTO COMMENTS] Failed to send photo-comment push to \(ownerId): \(error)")
        }
    }
}
