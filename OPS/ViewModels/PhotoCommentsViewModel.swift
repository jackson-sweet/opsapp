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
    @Published private(set) var errorFeedbackLabel =
        Feedback.Err.operationFailed

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
    private weak var dataController: DataController?
    private var loadTask: Task<Void, Never>?
    private var notificationObserver: NSObjectProtocol?
    private let createCommentOverride:
        ((CreateProjectNoteDTO) async throws -> ProjectNoteDTO)?
    private let postRetryBaseDelaySeconds: Double
    @Published var composeMentionSpans: [ProjectNoteMentionSpan] = []
    @Published var composeSelectedRange = NSRange(location: 0, length: 0)

    init(
        photoURL: String,
        projectId: String,
        createCommentOverride:
            ((CreateProjectNoteDTO) async throws -> ProjectNoteDTO)? = nil,
        postRetryBaseDelaySeconds: Double = 0.5
    ) {
        self.photoURL = photoURL
        self.projectId = projectId
        self.createCommentOverride = createCommentOverride
        self.postRetryBaseDelaySeconds = postRetryBaseDelaySeconds
    }

    /// Read-only roster for row-scoped edit mention pickers. The mutable source
    /// remains private so setup is still the only place that can replace it.
    var teamMembers: [TeamMember] {
        allTeamMembers
    }

    func mentionIdentityMembers(for note: ProjectNote) -> [TeamMember] {
        var membersById = Dictionary(
            allTeamMembers.map { ($0.id.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for id in note.mentionedUserIds {
            let canonicalId = id.lowercased()
            guard membersById[canonicalId] == nil,
                  let user = dataController?.getUser(id: id) else {
                continue
            }
            membersById[canonicalId] = TeamMember.fromUser(user)
        }
        return Array(membersById.values)
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
                self.loadCommentsFromLocal()
            }
        }
    }

    // MARK: - Load

    func loadComments() async {
        beginAttempt(feedbackLabel: Feedback.Err.requestFailed)
        guard let repo = repository else {
            fail(
                "Couldn't load comments. Try again.",
                feedbackLabel: Feedback.Err.requestFailed
            )
            return
        }
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
                    if let existing = try?
                        ProjectNoteMentionEditSync.fetchProjectNote(
                            matching: dto.id,
                            in: context
                        ) {
                        // Bug f9e00eb9 — never clobber an un-pushed local change
                        // (pending delete/edit) with a stale server snapshot.
                        if existing.needsSync { continue }
                        existing.content = model.content
                        existing.attachmentsJSON = model.attachmentsJSON
                        existing.mentionedUserIdsString = model.mentionedUserIdsString
                        existing.photoURL = model.photoURL
                        existing.eventKind = model.eventKind
                        existing.contentMetadataJSON = model.contentMetadataJSON
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
            error = nil
        } catch {
            if !(error is CancellationError) {
                fail(
                    FieldErrorHandler.userFriendlyMessage(for: error),
                    feedbackLabel: Feedback.Err.requestFailed
                )
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

    @discardableResult
    func postComment() async -> Bool {
        beginAttempt(feedbackLabel: Feedback.Err.saveFailed)
        let text = newCommentText
        guard !text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return false
        }
        guard let companyId = companyId,
              let currentUserId = currentUserId else {
            fail(
                "Couldn't post comment. Try again.",
                feedbackLabel: Feedback.Err.saveFailed
            )
            return false
        }
        let repository = repository
        guard createCommentOverride != nil || repository != nil else {
            fail(
                "Couldn't post comment. Try again.",
                feedbackLabel: Feedback.Err.saveFailed
            )
            return false
        }

        let selectedMentionSpans = composeMentionSpans
        let selectedMentionUserIds: [String] = selectedMentionSpans.compactMap {
            guard case .user(let id) = $0.recipient else { return nil }
            return id
        }
        let mentionPlan = ProjectNoteMentionEditPlan.make(
            content: text,
            teamMembers: allTeamMembers,
            currentUserId: currentUserId,
            identitySpans: selectedMentionSpans,
            preferredMentionedUserIds: selectedMentionUserIds
        )
        guard mentionPlan.unresolvedMentionNames.isEmpty else {
            fail(
                "Select the teammate again before posting.",
                feedbackLabel: Feedback.Err.saveFailed
            )
            return false
        }
        let mentionedIds = mentionPlan.mentionedUserIds
        let persistedContent = mentionPlan.content
        let notificationText = ProjectNoteMentionParser.displayText(
            from: persistedContent
        )

        let dto = CreateProjectNoteDTO(
            projectId: projectId,
            companyId: companyId,
            authorId: currentUserId,
            content: persistedContent,
            mentionedUserIds: mentionedIds,
            photoURL: photoURL
        )

        // Optimistic insert
        let optimisticNote = ProjectNote(
            projectId: projectId,
            companyId: companyId,
            authorId: currentUserId,
            content: persistedContent,
            photoURL: photoURL
        )
        optimisticNote.mentionedUserIds = mentionedIds
        optimisticNote.needsSync = true
        if let context = modelContext {
            context.insert(optimisticNote)
            try? context.save()
        }
        loadCommentsFromLocal()
        // Bugs 488778ac / 4353812f — the feed's ProjectNotesViewModel must learn
        // about this comment immediately, not on next project reopen.
        ProjectNoteChangeSignal.post(projectId: projectId)
        newCommentText = ""
        composeMentionSpans = []
        composeSelectedRange = NSRange(location: 0, length: 0)
        showMentionPicker = false
        showAllTeamOption = false
        mentionSuggestions = []

        do {
            // Retry through a transient signal blip before giving up.
            let created = try await NetworkRetry.run(
                maxAttempts: 3,
                baseDelaySeconds: postRetryBaseDelaySeconds
            ) {
                if let createCommentOverride {
                    return try await createCommentOverride(dto)
                }
                guard let repository else {
                    throw URLError(.unknown)
                }
                return try await repository.create(dto)
            }
            // Replace optimistic note with server version
            if let context = modelContext {
                let optimisticId = optimisticNote.id
                let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == optimisticId })
                if let existing = (try? context.fetch(descriptor))?.first {
                    context.delete(existing)
                }
                let serverModel = created.toModel()
                serverModel.lastSyncedAt = Date()
                serverModel.needsSync = false
                context.insert(serverModel)
                try? context.save()
            }
            loadCommentsFromLocal()
            ProjectNoteChangeSignal.post(projectId: projectId)

            // Send notifications
            await sendMentionNotifications(mentionedIds: mentionedIds, noteText: notificationText, noteId: created.id)
            // Notify the photo's uploader (unless they're the commenter or were
            // already @mentioned above).
            await sendPhotoOwnerNotification(mentionedIds: mentionedIds, noteText: notificationText, noteId: created.id)
            error = nil
            return true
        } catch {
            if !(error is CancellationError) {
                fail(
                    FieldErrorHandler.userFriendlyMessage(for: error),
                    feedbackLabel: Feedback.Err.saveFailed
                )
                // Preserve the operator's typed comment for a one-tap retry.
                newCommentText = text
                composeMentionSpans = selectedMentionSpans
                composeSelectedRange = NSRange(
                    location: (text as NSString).length,
                    length: 0
                )
            }
            // Revert optimistic note
            if let context = modelContext {
                let optimisticId = optimisticNote.id
                let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == optimisticId })
                if let orphan = (try? context.fetch(descriptor))?.first {
                    context.delete(orphan)
                    try? context.save()
                }
            }
            loadCommentsFromLocal()
            return false
        }
    }

    // MARK: - Delete

    @discardableResult
    func deleteComment(_ note: ProjectNote) async -> Bool {
        beginAttempt(feedbackLabel: Feedback.Err.deleteFailed)
        // Durable path — queue the tombstone so it survives a timeout/offline
        // and retries (bug f9e00eb9). The merge guard stops a concurrent fetch
        // from resurrecting the pending delete.
        if let dataController = dataController {
            guard dataController.deleteProjectNote(note: note) else {
                fail(
                    "Couldn't delete comment. Try again.",
                    feedbackLabel: Feedback.Err.deleteFailed
                )
                return false
            }
            loadCommentsFromLocal()
            ProjectNoteChangeSignal.post(projectId: projectId)
            error = nil
            return true
        }

        // Fallback — direct path with optimistic revert.
        guard let repo = repository else {
            fail(
                "Couldn't delete comment. Try again.",
                feedbackLabel: Feedback.Err.deleteFailed
            )
            return false
        }
        note.deletedAt = Date()
        try? modelContext?.save()
        loadCommentsFromLocal()
        ProjectNoteChangeSignal.post(projectId: projectId)

        do {
            try await repo.softDelete(note.id)
            error = nil
            return true
        } catch {
            note.deletedAt = nil
            try? modelContext?.save()
            loadCommentsFromLocal()
            ProjectNoteChangeSignal.post(projectId: projectId)
            if !(error is CancellationError) {
                fail(
                    FieldErrorHandler.userFriendlyMessage(for: error),
                    feedbackLabel: Feedback.Err.deleteFailed
                )
            }
            return false
        }
    }

    // MARK: - Edit

    func startEditing(_ note: ProjectNote) {
        beginAttempt(feedbackLabel: Feedback.Err.saveFailed)
        let draft = ProjectNoteMentionParser.editableDraft(
            in: note.content,
            mentionedUserIds: note.mentionedUserIds,
            teamMembers: mentionIdentityMembers(for: note),
            currentUserId: currentUserId
        )
        editText = draft.text
        editingNoteId = note.id
    }

    func cancelEditing() {
        editingNoteId = nil
        editText = ""
        error = nil
    }

    func saveEdit(
        identitySpans: [ProjectNoteMentionSpan] = []
    ) async {
        beginAttempt(feedbackLabel: Feedback.Err.saveFailed)
        guard let noteId = editingNoteId,
              let context = modelContext else {
            fail(
                "Couldn't save. Try again.",
                feedbackLabel: Feedback.Err.saveFailed
            )
            return
        }
        let newContent = editText
        guard !newContent.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            fail(
                "Enter a comment before saving.",
                feedbackLabel: Feedback.Err.saveFailed
            )
            return
        }

        let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == noteId })
        guard let note = try? context.fetch(descriptor).first else {
            fail(
                "Couldn't save. Try again.",
                feedbackLabel: Feedback.Err.saveFailed
            )
            return
        }
        let plan = ProjectNoteMentionEditPlan.make(
            content: newContent,
            teamMembers: allTeamMembers,
            currentUserId: currentUserId,
            identitySpans: identitySpans,
            baseline: ProjectNoteMentionBaseline(
                content: note.content,
                mentionedUserIds: note.mentionedUserIds
            )
        )
        guard plan.unresolvedMentionNames.isEmpty else {
            fail(
                "Select the teammate again before saving.",
                feedbackLabel: Feedback.Err.saveFailed
            )
            return
        }
        let mentionEventId = UUID().uuidString.lowercased()

        // Durable path — queue the edit so it retries and survives offline.
        if let dataController = dataController,
           dataController.updateProjectNoteContent(
               note: note,
               content: plan.content,
               mentionedUserIds: plan.mentionedUserIds,
               mentionEventId: mentionEventId
           ) {
            loadCommentsFromLocal()
            editingNoteId = nil
            editText = ""
            error = nil
            ProjectNoteChangeSignal.post(projectId: projectId)
            return
        }

        // Never commit the RPC without its durable dispatch record. Keeping the
        // edit open lets the operator retry without creating a stranded event.
        fail(
            "Couldn't save. Try again.",
            feedbackLabel: Feedback.Err.saveFailed
        )
    }

    // MARK: - Switch Photo

    func switchPhoto(to newURL: String) {
        loadTask?.cancel()
        error = nil
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
        if !text.contains("@") {
            composeMentionSpans = []
        }
        guard let match = ProjectNoteMentionEditor.match(
            in: text,
            selectedRange: composeSelectedRange,
            members: mentionableTeamMembers
        ) else {
            showMentionPicker = false
            showAllTeamOption = false
            mentionSuggestions = []
            return
        }
        mentionSuggestions = match.suggestions
        showAllTeamOption = match.showAllTeam
        showMentionPicker = !mentionSuggestions.isEmpty || showAllTeamOption
    }

    func insertMentionTrigger() {
        let utf16Text = newCommentText as NSString
        let safeSelection = NSMaxRange(composeSelectedRange)
            <= utf16Text.length
            ? composeSelectedRange
            : NSRange(location: utf16Text.length, length: 0)
        let mutable = NSMutableString(string: newCommentText)
        mutable.replaceCharacters(in: safeSelection, with: "@")
        composeMentionSpans = ProjectNoteMentionEditor
            .adjustingMentionSpans(
                composeMentionSpans,
                replacing: safeSelection,
                with: "@"
            )
        newCommentText = mutable as String
        composeSelectedRange = NSRange(
            location: safeSelection.location + 1,
            length: 0
        )
        handleMentionInput(newCommentText)
    }

    func insertMention(_ member: TeamMember) {
        guard member.id.lowercased()
                != currentUserId?.lowercased() else {
            showMentionPicker = false
            showAllTeamOption = false
            mentionSuggestions = []
            return
        }
        let visibleText = ProjectNoteMentionParser.visibleMentionText(
            for: member
        )
        guard let replacement = ProjectNoteMentionEditor
            .replacingActiveMention(
                with: member.fullName,
                in: newCommentText,
                selectedRange: composeSelectedRange,
                mentionSpans: composeMentionSpans,
                recipient: .user(id: member.id),
                visibleMentionText: visibleText
            ) else {
            return
        }
        newCommentText = replacement.text
        composeMentionSpans = replacement.mentionSpans
        composeSelectedRange = replacement.selectedRange
        showMentionPicker = false
        showAllTeamOption = false
        mentionSuggestions = []
    }

    private var mentionableTeamMembers: [TeamMember] {
        let current = currentUserId?.lowercased()
        return allTeamMembers.filter {
            $0.id.lowercased() != current
        }
    }

    func insertAllTeamMention() {
        guard let replacement = ProjectNoteMentionEditor
            .replacingActiveMention(
                with: "All Team",
                in: newCommentText,
                selectedRange: composeSelectedRange,
                mentionSpans: composeMentionSpans,
                recipient: .allTeam
            ) else {
            return
        }
        newCommentText = replacement.text
        composeMentionSpans = replacement.mentionSpans
        composeSelectedRange = replacement.selectedRange
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

    private func beginAttempt(feedbackLabel: String) {
        error = nil
        errorFeedbackLabel = feedbackLabel
    }

    private func fail(_ message: String, feedbackLabel: String) {
        errorFeedbackLabel = feedbackLabel
        error = message
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
