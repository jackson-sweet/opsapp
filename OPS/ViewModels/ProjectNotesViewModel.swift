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
    /// Photo annotations that carry a non-empty note — surfaced in the
    /// activity feed alongside regular text notes.
    @Published var annotations: [PhotoAnnotation] = []
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
    /// The read half of the note repository. Defaults to `repository`;
    /// injectable so the local-first paint order can be asserted against a fetch
    /// that has deliberately not resolved yet.
    private var noteFetcher: ProjectNoteFetching?
    /// The one narrow server RPC that writes a created note's rail rows.
    /// Internal so tests can substitute a spy — production always drives the
    /// shared repository.
    var noteSyncer: NoteCreatedNotifying = NotificationRepository.shared
    private var companyId: String?
    private var currentUserId: String?
    private(set) var allTeamMembers: [TeamMember] = []

    private var modelContext: ModelContext?
    private weak var dataController: DataController?
    private var notificationObserver: NSObjectProtocol?
    @Published var composeMentionSpans: [ProjectNoteMentionSpan] = []
    @Published var composeSelectedRange = NSRange(location: 0, length: 0)

    init(projectId: String) {
        self.projectId = projectId
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func setup(
        companyId: String,
        currentUserId: String,
        teamMembers: [TeamMember],
        modelContext: ModelContext,
        dataController: DataController? = nil,
        noteFetcher: ProjectNoteFetching? = nil
    ) {
        self.companyId = companyId
        self.currentUserId = currentUserId
        self.allTeamMembers = teamMembers
        self.modelContext = modelContext
        self.dataController = dataController
        let repository = ProjectNoteRepository(companyId: companyId)
        self.repository = repository
        self.noteFetcher = noteFetcher ?? repository

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
        error = nil

        // Local first, synchronously, before anything touches the network. The
        // activity feed is already on disk; making the operator watch a spinner
        // while a round-trip decides whether anything changed is the screen
        // feeling slow for no reason. The network merge below repaints over
        // this. ActivityTabView's spinner condition is
        // `isLoading && notes.isEmpty && annotations.isEmpty`, so a painted
        // local feed suppresses it without any UI change.
        loadNotesFromLocal()

        guard let fetcher = noteFetcher else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await fetcher.fetchForProject(projectId)
            // Upsert into SwiftData
            if let context = modelContext {
                Self.mergeFetchedNotes(dtos, projectId: projectId, context: context)
            }
            loadNotesFromLocal()
            error = nil
        } catch {
            if !(error is CancellationError) {
                self.error = FieldErrorHandler.userFriendlyMessage(for: error)
            }
            // Fall back to local data
            loadNotesFromLocal()
        }
    }

    /// Merge fetched note DTOs into SwiftData with ONE project-scoped fetch
    /// instead of a per-note FetchDescriptor — N store round-trips on the
    /// main actor was a measured screen-open cost. Static so it is testable
    /// against an in-memory container.
    static func mergeFetchedNotes(
        _ dtos: [ProjectNoteDTO], projectId: String, context: ModelContext
    ) {
        let pid = projectId
        let descriptor = FetchDescriptor<ProjectNote>(
            predicate: #Predicate { $0.projectId == pid }
        )
        let existingById = Dictionary(
            ((try? context.fetch(descriptor)) ?? []).map {
                ($0.id.lowercased(), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )
        for dto in dtos {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            if let existing = existingById[dto.id.lowercased()] {
                // Bug f9e00eb9 — a row with un-pushed local changes (a pending
                // delete tombstone or edit) is the source of truth until its
                // sync op lands. Overwriting from a stale server snapshot here
                // resurrected just-deleted notes ("delete does not work").
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

    private func loadNotesFromLocal() {
        guard let context = modelContext else { return }
        let pid = projectId
        let descriptor = FetchDescriptor<ProjectNote>(
            predicate: #Predicate { $0.projectId == pid && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        notes = (try? context.fetch(descriptor)) ?? []
        loadAnnotationsFromLocal()
    }

    /// Loads photo annotations with non-empty notes from local SwiftData.
    /// Called after every note reload so the unified feed stays in sync.
    private func loadAnnotationsFromLocal() {
        guard let context = modelContext else { return }
        let pid = projectId
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate { $0.projectId == pid && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        // Surface annotations that carry markup OR a text note (see
        // AnnotationFeedPolicy). Drawing-only markups now show as "marked up a
        // photo"; pure dimensioned captures (no overlay, no note) stay out.
        annotations = all.filter {
            AnnotationFeedPolicy.belongsInFeed(annotationURL: $0.annotationURL, note: $0.note)
        }
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
        error = nil
        let rawText = newNoteText
        let hasImages = !pendingImages.isEmpty
        let hasVisibleText = !rawText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        guard hasVisibleText || hasImages else {
            return
        }
        let text = hasVisibleText ? rawText : ""

        guard let repo = repository,
              let companyId = companyId,
              let currentUserId = currentUserId else {
            self.error = "Not signed in — please restart the app"
            print("[NOTES] postNote guard failed: repo=\(repository != nil) companyId=\(self.companyId ?? "nil") userId=\(self.currentUserId ?? "nil")")
            return
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
            error = "Select the teammate again before posting."
            return
        }
        let mentionedIds = mentionPlan.mentionedUserIds

        // Upload images if any. Bug ad97e11c — operators expect any photo
        // attached to a comment to appear in the project gallery alongside
        // camera/library photos. The previous note-only path uploaded each
        // photo to a separate `notes/<co>/<proj>/` S3 folder and only mirrored
        // the URL into the project's local gallery; without a `dataController`
        // injected into the ViewModel the Supabase update was skipped, no
        // `project_photos` row was written for the web client portal, and on
        // the next inbound sync the local addition was clobbered by server
        // state — so the photo silently vanished from the gallery.
        //
        // The fix routes comment-attached photos through
        // `ImageSyncManager.saveImages`, the canonical project-photo pipeline
        // shared with the project-level camera/library buttons. One photo,
        // one S3 object (in the project folder), mirrored into:
        //   - project.projectImagesString (local gallery carousel)
        //   - projects.project_images on Supabase (cross-device gallery)
        //   - a project_photos row (web client portal)
        //   - the in-flight tile carousel (operator sees a spinner while
        //     bytes climb to S3)
        // The returned publicUrls are reused for `note.attachments` so the
        // same S3 object is referenced from both the comment thread and the
        // project gallery — never duplicated.
        var attachmentURLs: [String] = []
        if hasImages {
            isUploading = true
            let imagesToUpload = pendingImages

            if let imageSyncManager = dataController?.imageSyncManager,
               let project = fetchProject() {
                // Primary path — canonical project-photo pipeline. Handles
                // online (S3 upload + Supabase + project_photos), offline
                // (local URLs + pending-upload queue + retry timer), and
                // permanent rejection (failed-tile carousel + auto-bug).
                // notifyCrew:false — the note-added notification below already
                // tells assigned crew about this post; saveImages skips its
                // own "photos added" notification so a photo-bearing note
                // doesn't fire two notifications for one action.
                attachmentURLs = await imageSyncManager.saveImages(imagesToUpload, for: project, notifyCrew: false)

                if attachmentURLs.isEmpty {
                    // Every image was rejected and no local placeholder
                    // landed either. Surface so the user can retry — posting
                    // a comment with no attached photos when they intended to
                    // attach some would hide the failure.
                    print("[NOTES] saveImages returned no URLs for \(imagesToUpload.count) image(s)")
                    self.error = "Photo upload failed. Try again."
                    isUploading = false
                    return
                }

                // Bump outbound sync priority so the gallery additions
                // propagate to crew on other devices on the next sync pass.
                project.syncPriority = 2
                try? modelContext?.save()
            } else {
                // Cold-start race fallback — DataController has not yet
                // booted ImageSyncManager (rare, possible during first
                // navigation into the project before init finishes). Use
                // the legacy note-only S3 upload path so the comment can
                // still post, then mirror the URLs into the project's
                // gallery via the local-write helper. The fallback does
                // not insert project_photos rows (the web portal won't
                // see them) — the cold-start window is narrow enough that
                // we accept that gap rather than block the post.
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
                await addAttachmentsToProjectGallery(attachmentURLs)
            }
            isUploading = false
        }

        // Bug d77b49a2 — when the user uploads photos with no caption, leave
        // the content empty rather than substituting the literal "Photo".
        // The image attachments speak for themselves; the placeholder added
        // visual noise to every photo-only comment.
        let noteContent = mentionPlan.content
        let notificationText = ProjectNoteMentionParser.displayText(
            from: noteContent
        )

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
        // Refresh any open photo-comment thread that references this note
        // (bugs 488778ac / 4353812f — a comment must show in the feed live).
        ProjectNoteChangeSignal.post(projectId: projectId)
        newNoteText = ""
        composeMentionSpans = []
        composeSelectedRange = NSRange(location: 0, length: 0)
        pendingImages = []
        showMentionPicker = false
        showAllTeamOption = false
        mentionSuggestions = []
        NotificationCenter.default.post(name: Notification.Name("WizardNotePosted"), object: nil)

        do {
            // Retry through a transient signal blip — a single timeout used to
            // surface a raw "request timed out" and delete the post outright.
            let created = try await NetworkRetry.run(maxAttempts: 3, baseDelaySeconds: 0.5) {
                try await repo.create(dto)
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
            loadNotesFromLocal()
            ProjectNoteChangeSignal.post(projectId: projectId)
            error = nil
            ToastCenter.shared.present(Feedback.Project.notePosted)

            // Rail rows + pushes for this note — mentions and the assigned-crew
            // broadcast both. One server call, always: the RPC derives every
            // recipient from the note row it just stored, so the client no
            // longer decides who hears about this.
            await dispatchNoteCreatedNotifications(
                noteId: created.id,
                noteText: notificationText,
                attachmentURLs: attachmentURLs
            )
        } catch {
            if !(error is CancellationError) {
                // Field-friendly copy (e.g. "Connection timed out. Try moving to
                // a better signal area.") instead of the raw NSURLError text.
                self.error = FieldErrorHandler.userFriendlyMessage(for: error)
                // Preserve the operator's typed note so they don't lose their
                // work — restore it into the composer for a one-tap retry. Any
                // attached photos already landed on the project via saveImages.
                newNoteText = text
                composeMentionSpans = selectedMentionSpans
                composeSelectedRange = NSRange(
                    location: (text as NSString).length,
                    length: 0
                )
            }
            // Revert: remove the optimistic note that failed to sync (notes have
            // no outbound retry queue, so a kept needsSync note would never push).
            if let context = modelContext {
                let optimisticId = optimisticNote.id
                let descriptor = FetchDescriptor<ProjectNote>(predicate: #Predicate { $0.id == optimisticId })
                if let orphan = (try? context.fetch(descriptor))?.first {
                    context.delete(orphan)
                    try? context.save()
                }
            }
            loadNotesFromLocal()
            ProjectNoteChangeSignal.post(projectId: projectId)
        }
    }

    // MARK: - Project Lookup

    /// Fetch the Project model for this view model's project id from the
    /// shared SwiftData context. Returns nil if the context is missing or
    /// the project no longer exists locally. The returned instance is the
    /// same identity SwiftUI is observing, so mutations are visible to
    /// every view bound to the project.
    private func fetchProject() -> Project? {
        guard let context = modelContext else { return nil }
        let pid = projectId
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == pid })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Gallery Sync (cold-start fallback)

    /// Local-write helper used only by the cold-start fallback path in
    /// `postNote()` — when `ImageSyncManager` is not yet available, this
    /// appends note-attachment URLs into the project's gallery string and
    /// queues a Supabase update so the gallery stays consistent across
    /// devices. The primary path uses `ImageSyncManager.saveImages` which
    /// also writes `project_photos` rows for the web portal; this fallback
    /// intentionally does not, to keep the fallback simple. No-op when
    /// called with an empty URL list.
    private func addAttachmentsToProjectGallery(_ urls: [String]) async {
        guard !urls.isEmpty, let context = modelContext else { return }

        guard let project = fetchProject() else { return }

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
                projectId: projectId,
                fields: [
                    "project_images": .array(gallery.map { .string($0) })
                ]
            )
        } catch {
            print("[NOTES] Failed to queue project_images sync op: \(error)")
        }
    }

    // MARK: - Delete

    func deleteNote(_ note: ProjectNote, deletePhoto: Bool = false) async {
        error = nil
        // Capture the note's photo URLs before deletion so we can optionally
        // prune them once the note is tombstoned.
        let photoURLs: [String] = {
            var urls = note.attachments.filter { !$0.isEmpty }
            if let photo = note.photoURL, !photo.isEmpty { urls.append(photo) }
            return Array(Set(urls))
        }()

        // Bug f9e00eb9 — a one-shot repo.softDelete() reverted the tombstone on
        // any timeout (field users on flaky signal watched the note reappear)
        // and never retried. Route the delete through the durable sync queue:
        // tombstone locally + record a delete op the engine retries until it
        // lands. Offline-safe; the merge guard (needsSync) stops a concurrent
        // fetch from resurrecting the pending tombstone.
        if let dataController = dataController {
            guard dataController.deleteProjectNote(note: note) else {
                error = "Couldn't delete. Try again."
                return
            }
            loadNotesFromLocal()
            ProjectNoteChangeSignal.post(projectId: projectId)
            // A photo posted with a note is mirrored into the project gallery
            // and a project_photos row, so tombstoning the note alone leaves the
            // photo in the carousel. When the user opts to remove the photo too,
            // prune every photo this note owned that no surviving note references.
            if deletePhoto {
                await removeNotePhotosFromProject(photoURLs)
            }
            error = nil
            return
        }

        // Fallback — DataController not yet injected (cold-start race). Legacy
        // direct path with optimistic revert.
        guard let repo = repository else {
            error = "Couldn't delete. Try again."
            return
        }
        note.deletedAt = Date()
        try? modelContext?.save()
        loadNotesFromLocal()
        ProjectNoteChangeSignal.post(projectId: projectId)

        do {
            try await repo.softDelete(note.id)
            if deletePhoto {
                await removeNotePhotosFromProject(photoURLs)
            }
            error = nil
        } catch {
            // Revert on failure
            note.deletedAt = nil
            try? modelContext?.save()
            loadNotesFromLocal()
            ProjectNoteChangeSignal.post(projectId: projectId)
            if !(error is CancellationError) {
                self.error = FieldErrorHandler.userFriendlyMessage(for: error)
            }
        }
    }

    /// Remove a deleted note's photos from the project gallery so they stop
    /// appearing in the Activity carousel. Prunes only URLs that no surviving
    /// note still references (the just-deleted note is already out of `notes`
    /// after `loadNotesFromLocal()`). Mirrors `addAttachmentsToProjectGallery`
    /// in reverse and additionally soft-deletes the local + remote
    /// `project_photos` rows.
    ///
    /// NOTE: `ImageSyncManager.deleteImage` only clears the local file cache —
    /// it does NOT touch the gallery CSV or `project_photos` — so the removal
    /// must be done explicitly here.
    private func removeNotePhotosFromProject(_ urls: [String]) async {
        let prunable = urls.filter { commentCount(forPhotoURL: $0) == 0 }
        guard !prunable.isEmpty,
              let context = modelContext,
              let project = fetchProject() else { return }

        // 1) Drop from the legacy CSV gallery (local mirror of project_images).
        var gallery = project.getProjectImageURLs()
        let csvCountBefore = gallery.count
        gallery.removeAll { prunable.contains($0) }
        let csvChanged = gallery.count != csvCountBefore
        if csvChanged {
            project.setProjectImageURLs(gallery)
            project.needsSync = true
            project.syncPriority = 2
        }

        // 2) Soft-delete the local ProjectPhoto rows so the @Query-backed
        //    carousel drops them immediately.
        let pid = projectId
        let descriptor = FetchDescriptor<ProjectPhoto>(
            predicate: #Predicate { $0.projectId == pid && $0.deletedAt == nil }
        )
        let localPhotos = (try? context.fetch(descriptor)) ?? []
        for photo in localPhotos where prunable.contains(photo.url) {
            photo.deletedAt = Date()
        }

        try? context.save()

        // 3) Push the CSV change to Supabase (canonical write side).
        if csvChanged, let dataController = dataController {
            do {
                try await dataController.updateProjectFields(
                    projectId: projectId,
                    fields: [
                        "project_images": .array(gallery.map { .string($0) })
                    ]
                )
            } catch {
                print("[NOTES] Failed to queue project_images removal: \(error)")
            }
        }

        // 4) Soft-delete the remote project_photos rows (web portal + other
        //    devices). Best-effort per URL.
        struct ProjectPhotoSoftDelete: Encodable { let deleted_at: String }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        for url in prunable {
            do {
                try await SupabaseService.shared.client
                    .from("project_photos")
                    .update(ProjectPhotoSoftDelete(deleted_at: nowISO))
                    .eq("project_id", value: projectId)
                    .eq("url", value: url)
                    .execute()
            } catch {
                print("[NOTES] Failed to soft-delete remote project_photos for \(url): \(error)")
            }
        }
    }

    // MARK: - Mention Handling

    /// Pure helper. Given the current text and the team roster, returns the
    /// picker state the UI should show. Returns `nil` when there is no
    /// active `@` mention (picker should be hidden). Shared with
    /// `ActivityEntryView` so the inline edit field can drive the same
    /// teammate picker as the compose bar (bug 162364de).
    nonisolated static func mentionMatch(
        for text: String,
        in members: [TeamMember]
    ) -> (suggestions: [TeamMember], showAllTeam: Bool)? {
        let selection = NSRange(
            location: (text as NSString).length,
            length: 0
        )
        guard let match = ProjectNoteMentionEditor.match(
            in: text,
            selectedRange: selection,
            members: members
        ) else {
            return nil
        }
        return (
            suggestions: match.suggestions,
            showAllTeam: match.showAllTeam
        )
    }

    /// Pure helper. Replace the trailing partial `@…` token in `text` with
    /// the fully-resolved mention name plus a trailing space. Used by both
    /// the compose-bar pipeline and the edit-mode picker.
    nonisolated static func textInserting(mention name: String, into text: String) -> String {
        let selection = NSRange(
            location: (text as NSString).length,
            length: 0
        )
        return ProjectNoteMentionEditor.replacingActiveMention(
            with: name,
            in: text,
            selectedRange: selection
        )?.text ?? text
    }

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
        showMentionPicker = !match.suggestions.isEmpty || match.showAllTeam
    }

    func insertMentionTrigger() {
        let utf16Text = newNoteText as NSString
        let safeSelection = NSMaxRange(composeSelectedRange)
            <= utf16Text.length
            ? composeSelectedRange
            : NSRange(location: utf16Text.length, length: 0)
        let mutable = NSMutableString(string: newNoteText)
        mutable.replaceCharacters(in: safeSelection, with: "@")
        composeMentionSpans = ProjectNoteMentionEditor
            .adjustingMentionSpans(
                composeMentionSpans,
                replacing: safeSelection,
                with: "@"
            )
        newNoteText = mutable as String
        composeSelectedRange = NSRange(
            location: safeSelection.location + 1,
            length: 0
        )
        handleMentionInput(newNoteText)
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
        if let replacement = ProjectNoteMentionEditor
            .replacingActiveMention(
                with: member.fullName,
                in: newNoteText,
                selectedRange: composeSelectedRange,
                mentionSpans: composeMentionSpans,
                recipient: .user(id: member.id),
                visibleMentionText: visibleText
            ) {
            newNoteText = replacement.text
            composeMentionSpans = replacement.mentionSpans
            composeSelectedRange = replacement.selectedRange
        }
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
        if let replacement = ProjectNoteMentionEditor
            .replacingActiveMention(
                with: "All Team",
                in: newNoteText,
                selectedRange: composeSelectedRange,
                mentionSpans: composeMentionSpans,
                recipient: .allTeam
            ) {
            newNoteText = replacement.text
            composeMentionSpans = replacement.mentionSpans
            composeSelectedRange = replacement.selectedRange
        }
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
    func updateNoteContent(
        _ note: ProjectNote,
        newContent: String,
        identitySpans: [ProjectNoteMentionSpan] = []
    ) async -> Bool {
        error = nil
        guard modelContext != nil else {
            error = "Couldn't save. Try again."
            return false
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
            error = "Select the teammate again before saving."
            return false
        }
        let mentionEventId = UUID().uuidString.lowercased()

        // Durable path — queue the edit through the sync engine so it retries
        // through a signal blip and survives offline (mirrors the delete fix).
        // The merge guard keeps a stale server snapshot from clobbering the
        // un-pushed edit before its op lands.
        if let dataController = dataController,
           dataController.updateProjectNoteContent(
               note: note,
               content: plan.content,
               mentionedUserIds: plan.mentionedUserIds,
               mentionEventId: mentionEventId
           ) {
            loadNotesFromLocal()
            ProjectNoteChangeSignal.post(projectId: projectId)
            error = nil
            return true
        }

        // Never downgrade to a direct RPC. That transaction commits an
        // immutable event; without a persisted dependent dispatch, app exit or
        // continued outage could strand delivery permanently.
        error = "Couldn't save. Try again."
        return false
    }

    // MARK: - Note Notifications

    /// Fan out one created note's notifications.
    ///
    /// Every rail row this note produces — the @mention rows and the
    /// assigned-crew broadcast — is written by `notify_note_created`, a narrow
    /// SECURITY DEFINER RPC that derives the author, the mentions, and the
    /// crew from the stored note row and renders the copy server-side. The
    /// client stopped writing `notifications` rows directly at the 2026-07-15
    /// hardening: app-role INSERT is revoked, so the old per-recipient insert
    /// loops 42501'd on every post and both surfaces went silently dead.
    ///
    /// The RPC reports back the ids that received NEW rail rows, and the push
    /// lanes target exactly those. Push and rail can no longer disagree about
    /// who was told — which is also why a failed RPC sends no push at all:
    /// with no rail row written there is nothing for a push to match.
    ///
    /// Internal rather than private: this is the seam the notification tests
    /// drive, since `postNote`'s create path is a live network call.
    func dispatchNoteCreatedNotifications(
        noteId: String,
        noteText: String,
        attachmentURLs: [String]
    ) async {
        guard let fanout = try? await noteSyncer.notifyNoteCreated(noteId: noteId) else {
            print("[PROJECT NOTES] notify_note_created failed for note \(noteId) — no rail rows written, so no push sent")
            return
        }
        let plan = ProjectNotePushPlan(fanout: fanout)
        guard !plan.isEmpty else { return }

        // Push copy only — the rail's own copy is rendered server-side.
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
        let firstImageUrl = attachmentURLs.first

        for userId in plan.mentionUserIds {
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

        guard !plan.teamUserIds.isEmpty else { return }
        do {
            try await OneSignalService.shared.notifyProjectNoteAdded(
                userIds: plan.teamUserIds,
                authorName: authorName,
                notePreview: noteText,
                photoCount: attachmentURLs.count,
                projectName: projectName,
                projectId: projectId,
                noteId: noteId,
                imageUrl: firstImageUrl
            )
        } catch {
            print("[PROJECT NOTES] Failed to send push note-added notification: \(error)")
        }
    }
}

/// Seam for `notify_note_created` — the single narrow RPC that writes a
/// created note's rail rows. Conformed to by `NotificationRepository`; tests
/// substitute a spy. Declared once here and shared with
/// `PhotoCommentsViewModel`, which drives the same RPC for photo comments.
protocol NoteCreatedNotifying {
    @discardableResult
    func notifyNoteCreated(noteId: String) async throws -> NotificationRepository.NoteCreatedFanout
}

extension NotificationRepository: NoteCreatedNotifying {}

/// The push lanes a plain project note opens, derived from nothing but the
/// server's fanout — the client no longer computes a recipient of its own, so
/// a push cannot reach someone whose rail row was never written.
///
/// A plain note has no photo owner to notify, so the fanout's `photoOwnerId`
/// is deliberately dropped here; that lane belongs to `PhotoCommentsViewModel`.
struct ProjectNotePushPlan: Equatable {
    /// One push each. The server already excluded the author and anyone whose
    /// rail row it did not write (a re-call is idempotent per note).
    let mentionUserIds: [String]
    /// One batched push for the whole assigned crew — never a per-recipient
    /// loop. Empty means no broadcast push.
    let teamUserIds: [String]

    init(fanout: NotificationRepository.NoteCreatedFanout) {
        self.mentionUserIds = fanout.mentionUserIds
        self.teamUserIds = fanout.teamUserIds
    }

    /// No recipient received a rail row, so there is nothing to push.
    var isEmpty: Bool {
        mentionUserIds.isEmpty && teamUserIds.isEmpty
    }
}
