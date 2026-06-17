//
//  ActivityTabView.swift
//  OPS
//
//  Chronological mixed feed of photos and notes — the Activity tab.
//  Extracts notes + photos logic from the former ProjectDetailsView.
//

import SwiftUI
import SwiftData

struct ActivityTabView: View {
    @ObservedObject var notesViewModel: ProjectNotesViewModel
    let project: Project
    let onShowImagePicker: () -> Void
    let onShowNoteImagePicker: () -> Void
    let onPhotoTap: ([String], Int) -> Void
    var onProjectPhotoTap: ((Int) -> Void)? = nil
    @Binding var noteFieldFocused: Bool

    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                // Project photos
                projectPhotosSection

                // Compose bar
                composeBar
                    .id("composeBar")

                // Notes feed
                notesFeed

                // Bottom spacer for scroll
                Spacer()
                    .frame(height: 200)
            }
            // Sync FocusState ↔ Binding
            .onChange(of: isTextFieldFocused) { _, newValue in
                noteFieldFocused = newValue
                if newValue {
                    // Scroll compose bar into view above keyboard
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(OPSStyle.Animation.standard) {
                            proxy.scrollTo("composeBar", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: noteFieldFocused) { _, newValue in
                if newValue { isTextFieldFocused = true }
            }
            .onAppear {
                NotificationCenter.default.post(name: Notification.Name("WizardActivityTabViewed"), object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WizardScrollToTarget"))) { notification in
                if let stepId = notification.userInfo?["stepId"] as? String {
                    withAnimation {
                        proxy.scrollTo("wizard_active_\(stepId)", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Notes Feed

    /// Unified chronologically-sorted feed merging notes and annotated photos.
    private var feedItems: [ActivityFeedItem] {
        var items: [ActivityFeedItem] = []
        items += notesViewModel.notes.map { .note($0) }
        items += notesViewModel.annotations.map { .annotation($0) }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    private var notesFeed: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            if notesViewModel.isLoading && notesViewModel.notes.isEmpty && notesViewModel.annotations.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    Spacer()
                }
                .padding(.vertical, OPSStyle.Layout.spacing4)
            } else if feedItems.isEmpty {
                // Empty state
                VStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Image(systemName: "note.text")
                        .font(.system(size: OPSStyle.Layout.IconSize.xl))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("No activity yet")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("Post a note or add photos for your team")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OPSStyle.Layout.spacing5)
            } else {
                ForEach(feedItems) { item in
                    switch item {
                    case .note(let note):
                        ActivityEntryView(
                            note: note,
                            authorName: notesViewModel.authorName(for: note.authorId),
                            teamMember: notesViewModel.teamMember(for: note.authorId),
                            isOwnNote: notesViewModel.isOwnNote(note),
                            mentionNames: notesViewModel.mentionNames,
                            allTeamMembers: notesViewModel.allTeamMembers,
                            onDelete: { deletePhoto in
                                Task { await notesViewModel.deleteNote(note, deletePhoto: deletePhoto) }
                            },
                            onEdit: { newContent in
                                Task { await notesViewModel.updateNoteContent(note, newContent: newContent) }
                            },
                            onPhotoTap: onPhotoTap
                        )
                    case .annotation(let annotation):
                        AnnotationEntryView(
                            annotation: annotation,
                            authorName: notesViewModel.authorName(for: annotation.authorId),
                            teamMember: notesViewModel.teamMember(for: annotation.authorId),
                            onPhotoTap: onPhotoTap
                        )
                    }
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        VStack(spacing: 0) {
            // Pending images strip
            if !notesViewModel.pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(Array(notesViewModel.pendingImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))

                                Button(action: { notesViewModel.removeImage(at: index) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .background(Circle().fill(OPSStyle.Colors.background))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                }
            }

            // Upload progress
            if notesViewModel.isUploading {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    Text("Uploading photos...")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing1)
            }

            // Error banner
            if let error = notesViewModel.error {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    Text(error)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    Spacer()
                    Button {
                        notesViewModel.error = nil
                    } label: {
                        Image(systemName: OPSStyle.Icons.xmark)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing1)
            }

            // Mention suggestions
            if notesViewModel.showMentionPicker {
                mentionSuggestions
            }

            // Input row
            HStack(spacing: OPSStyle.Layout.spacing1) {
                // @ mention button — focuses text field and inserts @
                Button(action: {
                    notesViewModel.newNoteText += "@"
                    notesViewModel.handleMentionInput(notesViewModel.newNoteText)
                    isTextFieldFocused = true
                }) {
                    Image(systemName: OPSStyle.Icons.mention)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 32, height: 32)

                // Camera button
                Button(action: onShowNoteImagePicker) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 32, height: 32)

                TextField("Write a note...", text: $notesViewModel.newNoteText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .focused($isTextFieldFocused)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .onChange(of: notesViewModel.newNoteText) { _, newValue in
                        notesViewModel.handleMentionInput(newValue)
                    }
                    .onSubmit {
                        if notesViewModel.canPost {
                            Task { await notesViewModel.postNote() }
                        }
                    }

                Button(action: {
                    Task { await notesViewModel.postNote() }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                        .foregroundColor(
                            notesViewModel.canPost
                                ? OPSStyle.Colors.primaryAccent
                                : OPSStyle.Colors.tertiaryText
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!notesViewModel.canPost || notesViewModel.isUploading)
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .glassSurface()
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1.5)
                .opacity(isTextFieldFocused ? 1 : 0)
        )
        .animation(OPSStyle.Animation.panel, value: isTextFieldFocused)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
        .wizardTarget("write_note")
    }

    // MARK: - Mention Suggestions

    private var mentionSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // @All Team pill
                if notesViewModel.showAllTeamOption {
                    Button(action: { notesViewModel.insertAllTeamMention() }) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: OPSStyle.Icons.crew)
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(width: 24, height: 24)
                                .background(OPSStyle.Colors.primaryAccent.opacity(0.15))
                                .clipShape(Circle())
                            Text("All Team")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .nestedCard()
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                ForEach(notesViewModel.mentionSuggestions, id: \.id) { member in
                    Button(action: { notesViewModel.insertMention(member) }) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            TeamMemberAvatar(teamMember: member, size: 24)
                            Text(member.fullName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .nestedCard()
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Project Photos

    /// Bug e5310f3d — pull live in-flight uploads off the shared
    /// ImageSyncManager so the carousel can render placeholder cards
    /// while bytes are still climbing to S3. Each placeholder shows the
    /// photo we already have (the UIImage the user picked) plus a
    /// spinner; it dissolves into a real PhotoThumbnail once the upload
    /// settles and the URL lands on the project row.
    @ViewBuilder
    private var projectPhotosSection: some View {
        if let imageSyncManager = dataController.imageSyncManager {
            ProjectPhotosCarousel(
                project: project,
                imageSyncManager: imageSyncManager,
                onPhotoTap: { index in onProjectPhotoTap?(index) }
            )
            .padding(.top, OPSStyle.Layout.spacing3)
        } else {
            // No sync manager available yet — fall back to the static
            // carousel (no upload spinners possible without it).
            staticPhotosCarousel
                .padding(.top, OPSStyle.Layout.spacing3)
        }
    }

    /// Plain carousel without in-flight upload tracking. Used as a
    /// fallback when DataController hasn't booted ImageSyncManager yet
    /// (rare, but possible during cold-start race).
    private var staticPhotosCarousel: some View {
        let photos = project.mergedGalleryImageURLs(using: modelContext)
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text(photos.isEmpty
                     ? "NO PHOTOS"
                     : "\(photos.count) PHOTO\(photos.count == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            if photos.isEmpty {
                Text("Tap the camera to add project photos")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                            Button(action: { onProjectPhotoTap?(index) }) {
                                PhotoThumbnail(url: url, project: project)
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .wizardTarget(index == 0 ? "view_photo" : "")
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
            }
        }
    }
}

// MARK: - Activity Feed Item

/// Unified wrapper used to sort notes and photo-annotation comments into a
/// single chronological feed without creating a heavyweight view model.
private enum ActivityFeedItem: Identifiable {
    case note(ProjectNote)
    case annotation(PhotoAnnotation)

    var id: String {
        switch self {
        case .note(let n): return "note-\(n.id)"
        case .annotation(let a): return "annotation-\(a.id)"
        }
    }

    var createdAt: Date {
        switch self {
        case .note(let n): return n.createdAt
        case .annotation(let a): return a.createdAt
        }
    }
}

// MARK: - Annotation Entry View

/// Activity feed card for a photo annotation that carries a text note.
/// Shows the annotated photo thumbnail on the left so the crew can immediately
/// see which photo the comment refers to, then the author, timestamp, and note.
private struct AnnotationEntryView: View {
    let annotation: PhotoAnnotation
    let authorName: String
    let teamMember: TeamMember?
    let onPhotoTap: (([String], Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: avatar + name + "commented on a photo" + timestamp
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let member = teamMember {
                    TeamMemberAvatar(teamMember: member, size: 28)
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.background)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(authorName.prefix(1)).uppercased())
                                .font(OPSStyle.Typography.status)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text(AnnotationFeedPolicy.actionLabel(annotationURL: annotation.annotationURL))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Text(relativeTimestamp)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            // Photo thumbnail + note side by side
            HStack(alignment: .top, spacing: 10) {
                // Thumbnail — tapping opens the photo viewer on this image
                Button(action: {
                    onPhotoTap?([annotation.photoURL], 0)
                }) {
                    PhotoThumbnail(url: annotation.photoURL, project: nil)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // Note text — omitted for a markup-only card; the marked-up
                // thumbnail carries the meaning on its own.
                if !annotation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(annotation.note)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .glassSurface()
    }

    private var relativeTimestamp: String {
        let interval = Date().timeIntervalSince(annotation.createdAt)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: annotation.createdAt)
    }
}

// MARK: - ProjectPhotosCarousel (Bug e5310f3d)

/// Carousel that observes `ImageSyncManager` so it can render
/// placeholder upload cards alongside completed photos. The
/// placeholders crossfade in when an upload starts, show a spinner
/// over a dimmed thumbnail of the picked image, and dissolve out when
/// the URL lands on the project row.
///
/// Each resolved photo tile also carries a per-photo client-portal
/// visibility toggle (eye icon) so the crew can opt individual photos
/// in or out of the web client portal without leaving the activity feed.
private struct ProjectPhotosCarousel: View {
    let project: Project
    @ObservedObject var imageSyncManager: ImageSyncManager
    let onPhotoTap: (Int) -> Void

    @EnvironmentObject private var dataController: DataController
    @Query private var syncedPhotos: [ProjectPhoto]

    init(project: Project, imageSyncManager: ImageSyncManager, onPhotoTap: @escaping (Int) -> Void) {
        self.project = project
        self.imageSyncManager = imageSyncManager
        self.onPhotoTap = onPhotoTap
        let pid = project.id
        _syncedPhotos = Query(
            filter: #Predicate<ProjectPhoto> { $0.projectId == pid && $0.deletedAt == nil },
            sort: [SortDescriptor(\ProjectPhoto.createdAt, order: .forward)]
        )
    }

    var body: some View {
        // Canonical gallery list: synced project_photos ∪ legacy CSV, deduped.
        // @Query keeps it live as inbound/realtime sync lands teammates' photos.
        let photos = project.mergedGalleryImageURLs(syncedPhotoURLs: syncedPhotos.map(\.url))
        let pending = imageSyncManager.currentInFlightUploads(for: project.id)
        // Split in-flight tiles into actively-uploading vs failed. The
        // UPLOADING badge counts only the spinners; failed tiles show
        // their own red-badged state and shouldn't inflate the upload
        // count after a permanent rejection.
        let uploadingCount = pending.lazy.filter { !$0.failed }.count
        let totalCount = photos.count + pending.count

        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text(totalCount == 0
                     ? "NO PHOTOS"
                     : "\(totalCount) PHOTO\(totalCount == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                if uploadingCount > 0 {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            .scaleEffect(0.7)
                        Text("UPLOADING \(uploadingCount)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            // 0.2s crossfade so the UPLOADING badge feels confident, not
            // jumpy. Matches OPSStyle.Animation.fast.
            .animation(OPSStyle.Animation.fast, value: uploadingCount)

            if totalCount == 0 {
                Text("Tap the camera to add project photos")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                            ZStack(alignment: .topTrailing) {
                                Button(action: { onPhotoTap(index) }) {
                                    PhotoThumbnail(url: url, project: project)
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .wizardTarget(index == 0 ? "view_photo" : "")
                                .transition(.opacity)
                                .overlay(alignment: .topLeading) {
                                    // Bug 189ace29 — sync-fail badge mirrors the
                                    // visibility eye on the opposite corner:
                                    // same 22pt circle, same 4pt outside-the-
                                    // corner offset.
                                    if !project.isImageSynced(url) {
                                        PhotoSyncFailBadge()
                                            .offset(x: -4, y: -4)
                                            .allowsHitTesting(false)
                                    }
                                }

                                // Per-photo client-portal visibility toggle.
                                // Filled eye = visible to client, slashed = hidden.
                                CarouselVisibilityButton(
                                    url: url,
                                    project: project,
                                    dataController: dataController
                                )
                                .offset(x: 4, y: -4)
                            }
                        }

                        // In-flight placeholders ride after the saved
                        // photos so the user sees their pick land on
                        // the right side of the carousel and slide left
                        // into the row once the upload finishes.
                        //
                        // Auto-bug-reporting (May-12 follow-up): failed
                        // tiles stay rendered with a red badge so the
                        // user knows the photo did NOT make it. Tap
                        // retries (transient) or dismisses (permanent).
                        ForEach(pending) { upload in
                            UploadingPhotoTile(
                                upload: upload,
                                onRetry: {
                                    Task {
                                        await imageSyncManager.retryFailedInFlightUpload(
                                            id: upload.id,
                                            for: project.id
                                        )
                                    }
                                },
                                onDismiss: {
                                    imageSyncManager.dismissFailedInFlightUpload(
                                        id: upload.id,
                                        for: project.id
                                    )
                                }
                            )
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .animation(OPSStyle.Animation.fast, value: pending.map { $0.id })
                    .animation(OPSStyle.Animation.fast, value: photos.count)
                }
            }
        }
    }
}

// MARK: - Carousel Visibility Button

/// Eye icon that marks a single project photo as visible / hidden in
/// the client portal. Tapping writes the change to the local model and
/// syncs to project_photos.is_client_visible on Supabase.
///
/// Bug 8ff95cd4 — gated on `projects.edit`. Crew without edit
/// permission and mention-only viewers never see the toggle.
private struct CarouselVisibilityButton: View {
    let url: String
    let project: Project
    let dataController: DataController

    @State private var isSyncing = false

    private var isVisible: Bool {
        project.isImageClientVisible(url)
    }

    private var canToggle: Bool {
        PermissionStore.shared.can("projects.edit")
    }

    var body: some View {
        if !canToggle {
            EmptyView()
        } else {
            toggleButton
        }
    }

    private var toggleButton: some View {
        Button(action: toggleVisibility) {
            ZStack {
                Circle()
                    .fill(isSyncing
                          ? Color.black.opacity(0.45)
                          : (isVisible
                             ? OPSStyle.Colors.primaryAccent.opacity(0.9)
                             : Color.black.opacity(0.55)))
                    .frame(width: 22, height: 22)

                if isSyncing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: isVisible ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
        .accessibilityLabel(isVisible ? "Hide from client portal" : "Show to client portal")
        .disabled(isSyncing)
    }

    private func toggleVisibility() {
        guard !isSyncing else { return }
        // Bug 8ff95cd4 — defense-in-depth permission re-check before
        // dispatching the write.
        guard canToggle else { return }
        let newVisible = !isVisible

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Optimistic local write
        project.setImageClientVisible(url, visible: newVisible)
        try? dataController.modelContext?.save()

        isSyncing = true
        Task {
            defer { Task { @MainActor in isSyncing = false } }
            do {
                try await dataController.imageSyncManager?.setPhotoClientVisibility(
                    url: url,
                    isVisible: newVisible,
                    projectId: project.id
                )
            } catch {
                // Revert optimistic write on failure
                await MainActor.run {
                    project.setImageClientVisible(url, visible: !newVisible)
                    try? dataController.modelContext?.save()
                }
                print("[CLIENT_VISIBILITY] Failed to sync for \(url): \(error)")
            }
        }
    }
}

/// Small tile showing the user's just-picked image dimmed under a
/// circular spinner. Replaces a `PhotoThumbnail` only while the upload
/// is in flight. Pulses gently so the user knows the upload is alive.
/// Bug e5310f3d + May-12 auto-bug-reporting follow-up. Renders an in-flight
/// upload as either a spinner (default) or a red-badged failed tile with a
/// tap-to-retry primary action and a long-press dismiss. Failed tiles stay
/// in the carousel until the user acks them — silent disappearance was the
/// May-12 outage UX, and we never repeat it.
private struct UploadingPhotoTile: View {
    let upload: InFlightUpload
    let onRetry: () -> Void
    let onDismiss: () -> Void
    @State private var pulse = false

    var body: some View {
        Group {
            if upload.failed {
                failedTile
            } else {
                pendingTile
            }
        }
    }

    private var pendingTile: some View {
        ZStack {
            Image(uiImage: upload.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 72, height: 72)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(OPSStyle.Colors.imageOverlay)
                )
                .opacity(pulse ? 0.85 : 1.0)

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
        }
        .frame(width: 72, height: 72)
        .accessibilityLabel("Uploading photo")
        .onAppear {
            // Subtle 1.2s breathing pulse — not a strobe — so a slow
            // network feels alive without being distracting in the field.
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var failedTile: some View {
        Button(action: onRetry) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: upload.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 72, height: 72)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .fill(Color.black.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .strokeBorder(OPSStyle.Colors.errorStatus, lineWidth: 1.5)
                    )

                // Red corner badge — tap-to-retry primary affordance lives
                // on the whole tile, the badge is a visual signal.
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.errorStatus)
                        .frame(width: 18, height: 18)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .offset(x: 4, y: -4)

                // "RETRY" label centered for clarity when the tile is small.
                Text("RETRY")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 6)
                    .padding(.bottom, 6)
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(
            upload.lastError.map { "Upload failed: \($0). Tap to retry, long-press to dismiss." }
                ?? "Upload failed. Tap to retry, long-press to dismiss."
        )
        .contextMenu {
            Button(role: .destructive, action: onDismiss) {
                Label("Dismiss", systemImage: "trash")
            }
        }
    }
}
