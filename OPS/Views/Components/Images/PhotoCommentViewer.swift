//
//  PhotoCommentViewer.swift
//  OPS
//
//  Full-screen photo viewer with comment panel for discussing individual photos.
//  Annotation mode is inline (iOS Photos-style) — no separate modal.
//

import SwiftUI
import SwiftData
import PencilKit

struct PhotoCommentViewer: View {
    let photos: [String]
    let initialIndex: Int
    let onDismiss: () -> Void
    var projectId: String

    @StateObject private var viewModel: PhotoCommentsViewModel
    @EnvironmentObject private var dataController: DataController
    @State private var currentIndex: Int
    @State private var isCommentsExpanded = false
    @FocusState private var isComposeFocused: Bool
    @State private var showOverlay = true
    @State private var autoHideTask: Task<Void, Never>?
    @State private var commentDragOffset: CGFloat = 0
    @State private var dismissDragOffset: CGFloat = 0

    // Annotation state (inline — replaces fullScreenCover)
    @State private var isAnnotating = false
    @State private var annotationDrawing = PKDrawing()
    @State private var annotationImage: UIImage?
    @State private var annotationImageSize: CGSize = .zero
    @State private var annotationIsSaving = false
    @State private var annotationError: String?

    /// Bug 7b43be32 — cached project handle so the visibility toggle
    /// doesn't re-fetch from SwiftData on every body render. Loaded
    /// once in onAppear and refreshed only when the projectId changes
    /// (which it never does for a single viewer instance).
    @State private var cachedProject: Project?
    /// Local mirror of the current photo's visibility state. Updated
    /// from `cachedProject` on photo change and on toggle so the UI
    /// can re-render without re-fetching.
    @State private var currentVisibilityState: Bool = false

    // Remote annotation overlays keyed by photo URL
    @State private var loadedAnnotations: [String: PhotoAnnotationDTO] = [:]
    // Incremented after compositing to force ZoomablePhotoView to reload from cache
    @State private var imageRefreshToken: Int = 0

    init(photos: [String], initialIndex: Int, onDismiss: @escaping () -> Void, projectId: String) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self.projectId = projectId
        self._currentIndex = State(initialValue: initialIndex)
        let url = initialIndex < photos.count ? photos[initialIndex] : ""
        self._viewModel = StateObject(wrappedValue: PhotoCommentsViewModel(photoURL: url, projectId: projectId))
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            if isAnnotating {
                // MARK: Annotation Mode — static photo + canvas (full screen)
                annotationPhotoLayer
                    .ignoresSafeArea()
            } else {
                // MARK: Normal Mode — zoomable photo gallery
                TabView(selection: $currentIndex) {
                    ForEach(0..<photos.count, id: \.self) { index in
                        ZoomablePhotoView(url: photos[index], onTap: toggleOverlay)
                            .id("\(photos[index])_\(imageRefreshToken)")
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                .offset(y: dismissDragOffset)
                .opacity(dismissDragOffset == 0 ? 1.0 : max(0.3, 1.0 - abs(dismissDragOffset) / CGFloat(400)))
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40)
                        .onChanged { value in
                            // Only respond to vertical drags when overlay is showing and comments not expanded
                            guard !isCommentsExpanded && !isComposeFocused else { return }
                            let vertical = value.translation.height
                            let horizontal = abs(value.translation.width)
                            // Only claim vertical if clearly vertical (2× dominance)
                            if abs(vertical) > horizontal * 2 && vertical > 0 {
                                dismissDragOffset = vertical * 0.6
                            }
                        }
                        .onEnded { value in
                            if dismissDragOffset > 120 {
                                withAnimation(OPSStyle.Animation.fast) {
                                    dismissDragOffset = UIScreen.main.bounds.height
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    onDismiss()
                                }
                            } else {
                                withAnimation(OPSStyle.Animation.smooth) {
                                    dismissDragOffset = 0
                                }
                            }
                        }
                )
                .onChange(of: currentIndex) { _, newIndex in
                    guard newIndex < photos.count else { return }
                    viewModel.switchPhoto(to: photos[newIndex])
                    isCommentsExpanded = false
                    withAnimation(OPSStyle.Animation.smooth) {
                        showOverlay = true
                    }
                    scheduleAutoHide()
                    // Bug 7b43be32 — refresh the visibility mirror so
                    // the eye toggle reflects the new photo.
                    refreshVisibilityState()
                }
            }

            // UI Overlays
            if isAnnotating {
                // Annotation toolbar
                VStack(spacing: 0) {
                    annotationToolbar
                        .padding(.horizontal, 16)

                    Spacer()

                    // Error message at bottom (above tool picker)
                    if let annotationError = annotationError {
                        Text(annotationError)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.bottom, OPSStyle.Layout.spacing2)
                    }
                }
                .padding(.top, OPSStyle.Layout.spacing2)
                .transition(.opacity)
            } else if showOverlay {
                // Normal viewer overlay
                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 48)

                    Spacer()

                    commentPanel
                }
                .transition(.opacity)
            }
        }
        .statusBar(hidden: true)
        .preferredColorScheme(.dark)
        .onAppear {
            setupViewModel()
            // Bug 7b43be32 — load + cache the project handle so the
            // visibility toggle reads from a single fetch rather than
            // hitting SwiftData on every body render.
            loadCachedProject()
            Task { await viewModel.loadComments() }
            Task {
                guard let modelContext = dataController.modelContext else { return }
                // Sync any pending (failed upload) annotations
                await PhotoAnnotationSyncManager.shared.syncPendingAnnotations(modelContext: modelContext)
                // Fetch annotation metadata for save/update lookups
                await loadAnnotationMetadata()
                // Composite all annotations into image cache (uses local overlay cache)
                await PhotoAnnotationSyncManager.shared.preCompositeAnnotations(
                    projectId: projectId,
                    modelContext: modelContext
                )
                imageRefreshToken += 1
            }
            scheduleAutoHide()
        }
        .onChange(of: isCommentsExpanded) { _, expanded in
            if expanded { cancelAutoHide() } else { scheduleAutoHide() }
        }
        .onChange(of: isComposeFocused) { _, focused in
            if focused { cancelAutoHide() } else { scheduleAutoHide() }
        }
        .onDisappear {
            cancelAutoHide()
        }
    }

    // MARK: - Annotation Photo + Canvas Layer

    private var annotationPhotoLayer: some View {
        GeometryReader { geometry in
            let fittedSize = fittedImageSize(in: geometry.size)
            ZStack {
                // Full-bleed black background
                Color.black

                // Static photo (no zoom during annotation)
                if let image = annotationImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                }

                // PencilKit canvas overlay — only appears once image size is computed.
                // Size is computed synchronously from the UIImage dimensions + container,
                // eliminating the timing gap of a background GeometryReader.
                if fittedSize.width > 0 && fittedSize.height > 0 {
                    AnnotationCanvas(drawing: $annotationDrawing)
                        .frame(width: fittedSize.width, height: fittedSize.height)
                        .onAppear {
                            annotationImageSize = fittedSize
                        }
                        .onChange(of: fittedSize) { _, newSize in
                            annotationImageSize = newSize
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Compute the aspect-fitted image dimensions within a container, matching
    /// SwiftUI's `.aspectRatio(contentMode: .fit)` layout behavior.
    private func fittedImageSize(in containerSize: CGSize) -> CGSize {
        guard let image = annotationImage,
              image.size.width > 0, image.size.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height
        if imageAspect > containerAspect {
            // Width-constrained
            let width = containerSize.width
            return CGSize(width: width, height: width / imageAspect)
        } else {
            // Height-constrained
            let height = containerSize.height
            return CGSize(width: height * imageAspect, height: height)
        }
    }

    // MARK: - Annotation Toolbar

    private var annotationToolbar: some View {
        HStack {
            // Cancel
            Button(action: cancelAnnotation) {
                Text("CANCEL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

            Spacer()

            // Undo
            Button(action: undoAnnotationStroke) {
                Image(OPSStyle.Icons.undo)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(annotationDrawing.strokes.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            .disabled(annotationDrawing.strokes.isEmpty)

            // Clear
            Button(action: clearAnnotation) {
                Text("CLEAR")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(annotationDrawing.strokes.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.errorStatus)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            .disabled(annotationDrawing.strokes.isEmpty)

            Spacer()

            // Done
            Button(action: { Task { await saveAnnotation() } }) {
                if annotationIsSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                } else {
                    Text("DONE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
            .disabled(annotationIsSaving)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(
            Color.black.opacity(0.6)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        )
    }

    // MARK: - Annotation Actions

    private func startAnnotation() {
        loadAnnotationImage()
        annotationImageSize = .zero
        annotationError = nil
        cancelAutoHide()

        // Restore existing drawing data so the user can add to it, not replace it.
        // Try SwiftData (has full PKDrawing data) first, fall back to clean canvas.
        if currentIndex < photos.count,
           let modelContext = dataController.modelContext {
            let photoURL = photos[currentIndex]
            let descriptor = FetchDescriptor<PhotoAnnotation>(
                predicate: #Predicate { $0.photoURL == photoURL && $0.deletedAt == nil }
            )
            if let existing = try? modelContext.fetch(descriptor).first,
               let drawingData = existing.localDrawingData,
               let restoredDrawing = try? PKDrawing(data: drawingData) {
                annotationDrawing = restoredDrawing
            } else {
                annotationDrawing = PKDrawing()
            }
        } else {
            annotationDrawing = PKDrawing()
        }

        withAnimation(OPSStyle.Animation.fast) {
            isAnnotating = true
        }
    }

    private func cancelAnnotation() {
        withAnimation(OPSStyle.Animation.fast) {
            isAnnotating = false
            annotationDrawing = PKDrawing()
            annotationImage = nil
            annotationError = nil
        }
        scheduleAutoHide()
    }

    private func saveAnnotation() async {
        guard let user = dataController.currentUser,
              let companyId = user.companyId else {
            print("[ANNOTATION] Save failed: no current user or companyId")
            annotationError = "Unable to save — user session unavailable"
            return
        }

        guard let modelContext = dataController.modelContext else {
            print("[ANNOTATION] Save failed: modelContext is nil")
            annotationError = "Unable to save — local storage unavailable"
            return
        }

        guard currentIndex < photos.count else {
            print("[ANNOTATION] Save failed: currentIndex \(currentIndex) out of range")
            annotationError = "Unable to save — photo not found"
            return
        }

        guard annotationImageSize.width > 0 && annotationImageSize.height > 0 else {
            print("[ANNOTATION] Save failed: annotationImageSize is zero")
            annotationError = "Unable to save — image not ready"
            return
        }

        print("[ANNOTATION] Saving: \(annotationDrawing.strokes.count) strokes, imageSize=\(annotationImageSize), photo=\(photos[currentIndex])")

        annotationIsSaving = true
        annotationError = nil

        do {
            // Look up existing annotation for this photo to update rather than duplicate
            let existingId = loadedAnnotations[photos[currentIndex]]?.id

            _ = try await PhotoAnnotationSyncManager.shared.saveAnnotation(
                drawing: annotationDrawing,
                note: "",
                photoURL: photos[currentIndex],
                imageSize: annotationImageSize,
                projectId: projectId,
                companyId: companyId,
                authorId: user.id,
                existingAnnotationId: existingId,
                modelContext: modelContext
            )
            print("[ANNOTATION] Save succeeded")

            // Composite the annotation onto the cached photo so it's
            // immediately visible when the viewer returns to normal mode.
            compositeAnnotationIntoCache()
            imageRefreshToken += 1

            withAnimation(OPSStyle.Animation.fast) {
                isAnnotating = false
                annotationDrawing = PKDrawing()
                annotationImage = nil
            }
            scheduleAutoHide()
        } catch {
            print("[ANNOTATION] Save failed: \(error)")
            annotationError = error.localizedDescription
        }

        annotationIsSaving = false
    }

    private func undoAnnotationStroke() {
        guard !annotationDrawing.strokes.isEmpty else { return }
        var strokes = annotationDrawing.strokes
        strokes.removeLast()
        annotationDrawing = PKDrawing(strokes: strokes)
    }

    private func clearAnnotation() {
        annotationDrawing = PKDrawing()
    }

    /// Render the user's drawing on top of the original photo and write the
    /// composited image into the in-memory cache. When the viewer returns to
    /// normal mode, ZoomablePhotoView picks up the composited version.
    private func compositeAnnotationIntoCache() {
        guard let baseImage = annotationImage,
              annotationImageSize.width > 0, annotationImageSize.height > 0,
              !annotationDrawing.strokes.isEmpty,
              currentIndex < photos.count else { return }

        let originalSize = baseImage.size
        let renderer = UIGraphicsImageRenderer(size: originalSize)
        let composited = renderer.image { _ in
            // Draw original photo at full resolution
            baseImage.draw(in: CGRect(origin: .zero, size: originalSize))
            // Draw annotation scaled from fitted size → original size
            let drawingImage = annotationDrawing.image(
                from: CGRect(origin: .zero, size: annotationImageSize),
                scale: UIScreen.main.scale
            )
            drawingImage.draw(in: CGRect(origin: .zero, size: originalSize))
        }

        let url = photos[currentIndex]
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url
        ImageCache.shared.set(composited, forKey: cacheKey)
        print("[ANNOTATION] Composited annotation into image cache for \(cacheKey)")
    }

    /// Load the ORIGINAL (un-annotated) photo for the annotation canvas.
    /// Skips the in-memory cache because it may contain a composited image
    /// (base + previous annotations). Goes to file system or network instead.
    private func loadAnnotationImage() {
        guard currentIndex < photos.count else { return }
        let url = photos[currentIndex]
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url

        // File system — always has the original, un-composited image
        if let loaded = ImageFileManager.shared.loadImage(localID: url)
            ?? ImageFileManager.shared.loadImage(localID: cacheKey) {
            annotationImage = loaded
            return
        }

        // Network fallback
        guard let imageURL = URL(string: cacheKey) else { return }
        URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data, let loaded = UIImage(data: data) {
                    annotationImage = loaded
                    _ = ImageFileManager.shared.saveImage(data: data, localID: cacheKey)
                }
            }
        }.resume()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(OPSStyle.Icons.xmark)
                    .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(12)
            }

            Spacer()

            Text("\(currentIndex + 1) of \(photos.count)")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    // MARK: - Comment Panel

    private var commentPanel: some View {
        VStack(spacing: 0) {
            commentHeaderBar

            if isCommentsExpanded && !viewModel.comments.isEmpty {
                commentList
                    .padding(.vertical, OPSStyle.Layout.spacing2)
            }

            if viewModel.showMentionPicker {
                mentionSuggestionsBar
            }

            composeBar

            bottomActionBar
        }
        .background {
            ZStack {
                Color.black.opacity(0.60)
                Rectangle().fill(.ultraThinMaterial)
            }
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Comment Header Bar

    private var commentHeaderBar: some View {
        Button(action: {
            withAnimation(OPSStyle.Animation.fast) {
                isCommentsExpanded.toggle()
            }
        }) {
            HStack {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Text("\(viewModel.comments.count) COMMENT\(viewModel.comments.count == 1 ? "" : "S")")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                if !viewModel.comments.isEmpty && !isCommentsExpanded {
                    Text("See more...")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Comment List

    private var commentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.comments, id: \.id) { comment in
                        PhotoCommentRow(
                            comment: comment,
                            authorName: viewModel.authorName(for: comment.authorId),
                            teamMember: viewModel.teamMember(for: comment.authorId),
                            isOwn: viewModel.isOwnComment(comment),
                            isEditing: viewModel.editingNoteId == comment.id,
                            editText: $viewModel.editText,
                            onEdit: { viewModel.startEditing(comment) },
                            onCancelEdit: { viewModel.cancelEditing() },
                            onSaveEdit: { Task { await viewModel.saveEdit() } },
                            onDelete: { Task { await viewModel.deleteComment(comment) } }
                        )
                        .id(comment.id)

                        if comment.id != viewModel.comments.last?.id {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .offset(y: commentDragOffset)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if value.translation.height > 0 {
                        commentDragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    withAnimation(OPSStyle.Animation.fast) {
                        commentDragOffset = 0
                        if value.translation.height > 60 {
                            isCommentsExpanded = false
                        }
                    }
                }
        )
    }

    // MARK: - Mention Suggestions

    private var mentionSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if viewModel.showAllTeamOption {
                    Button(action: { viewModel.insertAllTeamMention() }) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(OPSStyle.Icons.crew)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
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
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                ForEach(viewModel.mentionSuggestions, id: \.id) { member in
                    Button(action: { viewModel.insertMention(member) }) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            TeamMemberAvatar(teamMember: member, size: 24)
                            Text(member.fullName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing1)
        }
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button(action: {
                if !viewModel.newCommentText.contains("@") {
                    viewModel.newCommentText += "@"
                    viewModel.handleMentionInput(viewModel.newCommentText)
                }
            }) {
                Text("@")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(PlainButtonStyle())

            TextField("Comment...", text: $viewModel.newCommentText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .focused($isComposeFocused)
                .onChange(of: viewModel.newCommentText) { _, newValue in
                    viewModel.handleMentionInput(newValue)
                }
                .onSubmit {
                    Task { await viewModel.postComment() }
                }

            Button(action: {
                Task { await viewModel.postComment() }
            }) {
                Image(OPSStyle.Icons.sendFill)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(
                        viewModel.newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? OPSStyle.Colors.tertiaryText
                            : OPSStyle.Colors.primaryAccent
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Bottom Action Bar (Share + Visibility + Annotate)

    /// Bug 7b43be32 — fetch the Project once and cache it. SwiftData
    /// fetches are cheap but @State assignment is cheaper, and the
    /// project pointer doesn't change for the lifetime of this viewer.
    private func loadCachedProject() {
        guard let context = dataController.modelContext else { return }
        let id = projectId
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == id }
        )
        cachedProject = try? context.fetch(descriptor).first
        refreshVisibilityState()
    }

    /// Sync the local visibility mirror from the cached Project. Called
    /// on photo change and after a successful toggle.
    private func refreshVisibilityState() {
        guard currentIndex < photos.count, let project = cachedProject else {
            currentVisibilityState = false
            return
        }
        currentVisibilityState = project.isImageClientVisible(photos[currentIndex])
    }

    private var bottomActionBar: some View {
        OPSActionBar(showBackground: false) {
            HStack {
                OPSActionBarButton(
                    icon: "square.and.arrow.up",
                    label: "SHARE",
                    iconColor: OPSStyle.Colors.primaryAccent,
                    labelColor: OPSStyle.Colors.primaryAccent,
                    action: shareCurrentPhoto
                )

                Spacer()

                // Bug 7b43be32 — per-photo client portal visibility. When
                // ON the photo appears in the customer's portal; when OFF
                // the photo is internal-only. Default is OFF so nothing
                // accidentally goes public until the crew opts each photo
                // in. The icon (eye / eye.slash) and accent colour both
                // change to make the state legible at a glance in sun.
                //
                // Bug 8ff95cd4 — gated on `projects.edit`. Roles without
                // edit permission see the photo but cannot flip whether
                // the customer sees it; same gate that protects every
                // other project-level decision in the app.
                if PermissionStore.shared.can("projects.edit") {
                    OPSActionBarButton(
                        icon: currentVisibilityState ? "eye.fill" : "eye.slash",
                        label: currentVisibilityState ? "VISIBLE" : "HIDDEN",
                        iconColor: currentVisibilityState
                            ? OPSStyle.Colors.successStatus
                            : OPSStyle.Colors.tertiaryText,
                        labelColor: currentVisibilityState
                            ? OPSStyle.Colors.successStatus
                            : OPSStyle.Colors.secondaryText,
                        action: toggleClientVisibility
                    )

                    Spacer()
                }

                OPSActionBarButton(
                    icon: "pencil.tip",
                    label: "ANNOTATE",
                    action: startAnnotation
                )
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    // MARK: - Client Visibility Toggle (Bug 7b43be32)

    /// Toggle the current photo's `is_client_visible` flag. We update the
    /// local Project model first so the UI flips instantly, then push the
    /// change to Supabase. If the network write fails we revert the local
    /// flag and surface a haptic — a stale local value is worse than a
    /// stale optimistic one because the user's next sync would silently
    /// re-flip it.
    private func toggleClientVisibility() {
        // Bug 8ff95cd4 — defense-in-depth permission re-check before
        // dispatching the write. The action-bar button is hidden when
        // the role lacks projects.edit, but a stale UI shouldn't be
        // able to bypass that.
        guard PermissionStore.shared.can("projects.edit") else { return }

        guard currentIndex < photos.count,
              let project = cachedProject,
              let imageSyncManager = dataController.imageSyncManager else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        let url = photos[currentIndex]
        let newValue = !project.isImageClientVisible(url)

        // Optimistic local flip — UI updates immediately so the user
        // never feels the toggle lag behind their tap.
        project.setImageClientVisible(url, visible: newValue)
        try? dataController.modelContext?.save()
        currentVisibilityState = newValue

        // Medium impact on commit — confirms the toggle landed without
        // being noisy in the field.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                try await imageSyncManager.setPhotoClientVisibility(
                    url: url,
                    isVisible: newValue,
                    projectId: project.id
                )
            } catch {
                // Revert local state on server failure — better to flip
                // back than to lie about portal status.
                await MainActor.run {
                    project.setImageClientVisible(url, visible: !newValue)
                    try? dataController.modelContext?.save()
                    currentVisibilityState = !newValue
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
                print("[PHOTO_VIS] Failed to update visibility for \(url): \(error)")
            }
        }
    }

    // MARK: - Share

    private func shareCurrentPhoto() {
        guard currentIndex < photos.count else { return }
        let url = photos[currentIndex]
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url

        guard let image = ImageCache.shared.get(forKey: cacheKey)
                ?? ImageFileManager.shared.loadImage(localID: url)
                ?? ImageFileManager.shared.loadImage(localID: cacheKey) else { return }

        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            var topController = window.rootViewController
            while let presented = topController?.presentedViewController {
                topController = presented
            }
            topController?.present(activityVC, animated: true)
        }
    }

    // MARK: - Overlay Toggle & Auto-Hide

    private func toggleOverlay() {
        withAnimation(OPSStyle.Animation.smooth) {
            showOverlay.toggle()
        }
        if showOverlay {
            scheduleAutoHide()
        } else {
            cancelAutoHide()
        }
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        guard !isCommentsExpanded && !isComposeFocused && !isAnnotating else { return }
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            withAnimation(OPSStyle.Animation.fast) {
                showOverlay = false
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    // MARK: - Remote Annotation Loading

    /// Load annotation metadata from Supabase so we know which photos have
    /// existing annotations (for the existingId lookup when saving).
    private func loadAnnotationMetadata() async {
        guard let user = dataController.currentUser,
              let companyId = user.companyId else { return }

        let repo = PhotoAnnotationRepository(companyId: companyId)
        guard let dtos = try? await repo.fetchForProject(projectId) else { return }

        // Index by photo URL — keep only the most recent per photo.
        // Results are ORDER BY created_at DESC, so first match per URL is newest.
        var byPhoto: [String: PhotoAnnotationDTO] = [:]
        for dto in dtos {
            if byPhoto[dto.photoUrl] == nil {
                byPhoto[dto.photoUrl] = dto
            }
        }
        loadedAnnotations = byPhoto
    }

    // MARK: - Setup

    private func setupViewModel() {
        guard let user = dataController.currentUser,
              let companyId = user.companyId,
              let company = dataController.getCurrentUserCompany(),
              let modelContext = dataController.modelContext else { return }

        viewModel.setup(
            companyId: companyId,
            currentUserId: user.id,
            teamMembers: dataController.getTeamMembers(companyId: companyId).map { TeamMember.fromUser($0) },
            modelContext: modelContext
        )
    }
}

// MARK: - Photo Comment Row

struct PhotoCommentRow: View {
    let comment: ProjectNote
    let authorName: String
    let teamMember: TeamMember?
    let isOwn: Bool
    let isEditing: Bool
    @Binding var editText: String
    let onEdit: () -> Void
    let onCancelEdit: () -> Void
    let onSaveEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            // Header: avatar + name + timestamp + menu
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let member = teamMember {
                    TeamMemberAvatar(teamMember: member, size: 28)
                } else {
                    ZStack {
                        Circle()
                            .fill(OPSStyle.Colors.subtleBackground)
                            .frame(width: 28, height: 28)
                        Text(initials)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(authorName.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text(formatTimestamp(comment.createdAt))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                if isOwn && !isEditing {
                    Menu {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                    }
                }
            }

            // Content or edit field
            if isEditing {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    TextField("Edit comment...", text: $editText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)

                    Button(action: onSaveEdit) {
                        Text("Save")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: onCancelEdit) {
                        Text("Cancel")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                highlightedContent(comment.content)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .confirmationDialog("Delete Comment", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This comment will be permanently deleted.")
        }
    }

    private var initials: String {
        let parts = authorName.split(separator: " ")
        let first = parts.first?.first?.uppercased() ?? ""
        let last = parts.count > 1 ? (parts.last?.first?.uppercased() ?? "") : ""
        return "\(first)\(last)"
    }

    private func highlightedContent(_ text: String) -> Text {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var result = Text("")
        var inMention = false
        var isFirst = true

        for word in words {
            let separator = isFirst ? "" : " "
            isFirst = false
            if word.hasPrefix("@") {
                inMention = true
                result = result + Text(separator + word)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            } else if inMention {
                result = result + Text(separator + word)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                inMention = false
            } else {
                result = result + Text(separator + word)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }
        return result
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Yesterday \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }
}
