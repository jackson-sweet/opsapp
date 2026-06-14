//
//  ProjectPhotosGrid.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-28.
//

import SwiftUI
import SwiftData

struct ProjectPhotosGrid: View {
    let project: Project
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPhotoIndex: Int? = nil
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var processingImage = false
    @State private var showingDeleteConfirmation = false
    @State private var photoDeleteTarget: ProjectPhotoDeleteTarget?
    @State private var longPressingPhotoIndex: Int? = nil
    @State private var showingNetworkError = false
    @State private var networkErrorMessage = ""
    /// Phase F — set of photo URLs for this project that carry a dimensioned
    /// capture (non-null `dimensions` jsonb on the matching annotation row).
    @State private var dimensionedURLs: Set<String> = []
    @State private var renderedURLsBySource: [String: String] = [:]
    @State private var renderedDeliverableURLs: [String] = []
    @EnvironmentObject private var dataController: DataController
    
    // Three-column grid with minimal spacing
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Black background for optimal photo viewing
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    let photoItems = displayedPhotoItems(from: project.getProjectImages())
                    
                    if photoItems.isEmpty {
                        emptyStateView
                    } else {
                        // Grid layout of photos
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(Array(photoItems.enumerated()), id: \.element.id) { index, item in
                                    ZStack(alignment: .topLeading) {
                                        PhotoThumbnail(
                                            url: item.displayURL,
                                            project: project,
                                            isDimensioned: dimensionedURLs.contains(item.displayURL)
                                                || dimensionedURLs.contains(item.sourceURL)
                                        )
                                            .aspectRatio(1, contentMode: .fill)
                                            .clipped()
                                            .contentShape(Rectangle())

                                        // Bug 189ace29 — inset 4pt inside the cell
                                        // because the 2pt grid spacing leaves no
                                        // room to protrude past the corner like the
                                        // smaller carousels do.
                                        if !project.isImageSynced(item.syncStatusURL) {
                                            PhotoSyncFailBadge()
                                                .padding(OPSStyle.Layout.spacing1)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    .scaleEffect(longPressingPhotoIndex == index ? 0.9 : 1.0) // Scale down when pressed
                                    .overlay(
                                        // Show a subtle delete icon overlay during long press
                                        ZStack {
                                            if longPressingPhotoIndex == index {
                                                OPSStyle.Colors.modalOverlay

                                                Image(systemName: "trash")
                                                    .font(.system(size: OPSStyle.Layout.IconSize.xl))
                                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                            }
                                        }
                                    )
                                    .onTapGesture {
                                        // View photo in viewer
                                        selectedPhotoIndex = index
                                    }
                                    .onLongPressGesture(minimumDuration: 0.5) {
                                        // Long press action
                                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                        impactFeedback.prepare()
                                        impactFeedback.impactOccurred()
                                        
                                        // Reset visual state
                                        longPressingPhotoIndex = nil
                                        
                                        // Show delete confirmation
                                        photoDeleteTarget = item.deleteTarget
                                        showingDeleteConfirmation = true
                                    } onPressingChanged: { isPressing in
                                        // Visual feedback while pressing - happens immediately
                                        withAnimation(OPSStyle.Animation.fast) {
                                            longPressingPhotoIndex = isPressing ? index : nil
                                        }
                                    }
                                }
                            }
                            .padding(2)
                        }
                    }
                }
                
                // Camera button - fixed at bottom
                VStack {
                    Spacer()
                    
                    Button(action: { showingCamera = true }) {
                        HStack {
                            Image(systemName: OPSStyle.Icons.photo)
                            Text("Add Photo")
                                .font(OPSStyle.Typography.bodyEmphasis)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(height: 56)
                        .frame(maxWidth: .infinity)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.largeCornerRadius)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.bottom, OPSStyle.Layout.spacing3)
                    }
                    .disabled(processingImage)
                }
                
                // Loading overlay when processing image
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
                    .edgesIgnoringSafeArea(.all)
                }
            }
            .navigationBarTitle("Project Photos", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .task(id: project.id) {
                await refreshDimensionedURLs()
                // Re-composite on the grid's own appearance. ProjectDetailsView
                // pre-composites when the project opens, but full-resolution
                // composites can be evicted from ImageCache before the user
                // drills into this full-screen grid. Compositing again here
                // re-posts .annotationsComposited per photo while these
                // thumbnails are mounted, so markup shows without a tap-through.
                await PhotoAnnotationSyncManager.shared.preCompositeAnnotations(
                    projectId: project.id,
                    modelContext: modelContext
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .annotationsComposited)) { _ in
                Task { await refreshDimensionedURLs() }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: Binding<PhotoViewerItem?>(
            get: { selectedPhotoIndex.map { PhotoViewerItem(index: $0) } },
            set: { item in selectedPhotoIndex = item?.index }
        )) { item in
            let photoItems = displayedPhotoItems(from: project.getProjectImages())
            BasicPhotoViewer(
                photos: photoItems.map(\.displayURL),
                sourcePhotos: photoItems.map(\.sourceURL),
                initialIndex: item.index,
                onDismiss: { selectedPhotoIndex = nil },
                projectId: project.id
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingCamera) {
            ImagePicker(
                images: Binding<[UIImage]>(
                    get: { cameraImage != nil ? [cameraImage!] : [] },
                    set: { images in
                        if let first = images.first {
                            cameraImage = first
                        }
                    }
                ), 
                selectionLimit: 1,
                onSelectionComplete: {
                    // Close the picker immediately
                    showingCamera = false
                    
                    // Process image when selection is complete
                    if let image = cameraImage {
                        // Use slight delay to ensure UI dismissal completes first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            addPhotoToProject(image)
                        }
                    }
                }
            )
        }
        // Network error alert
        .alert("Network Error", isPresented: $showingNetworkError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(networkErrorMessage)
        }
        // Delete confirmation alert
        .alert("Delete Photo?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                photoDeleteTarget = nil
            }
            Button("Delete", role: .destructive) {
                if let target = photoDeleteTarget {
                    deletePhoto(target)
                }
            }
        } message: {
            Text("Are you sure you want to delete this photo? This action cannot be undone.")
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Spacer()
            
            Image(systemName: OPSStyle.Icons.photos)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("No Photos")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Add photos to document this project")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button(action: { showingCamera = true }) {
                HStack {
                    Image(systemName: OPSStyle.Icons.photo)
                    Text("Add Photo")
                        .font(OPSStyle.Typography.bodyEmphasis)
                }
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(height: 56)
                .frame(width: 220)
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(OPSStyle.Layout.largeCornerRadius)
                .padding(.bottom, 40)
            }
        }
    }
}

// Simple wrapper to make an index Identifiable
struct PhotoViewerItem: Identifiable {
    let id = UUID()
    let index: Int
}

// Clean thumbnail with loading state
struct PhotoThumbnail: View {
    let url: String
    let project: Project? // Optional to maintain backward compatibility
    /// Phase F — driven by the parent grid. When true, overlays a small
    /// `ruler` SF Symbol bottom-right per the LiDAR Dimensioned Capture spec
    /// §3.7. Default false keeps legacy callers unchanged.
    var isDimensioned: Bool = false
    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            OPSStyle.Colors.cardBorder

            if let image = image {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }

                // Bug 189ace29 — the sync-fail badge used to render here as
                // a tiny inside-the-clip indicator, which both clipped the
                // glyph and didn't visually mirror the client-visibility
                // eye on the opposite corner. The badge is now a sibling
                // component (PhotoSyncFailBadge) rendered alongside the
                // visibility eye by each carousel/grid callsite so the
                // two corners read as a matched pair.
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            // Phase F — dimensioned-capture badge overlay (bottom-right).
            DimensionBadgeOverlay(isDimensioned: isDimensioned)
        }
        .onAppear(perform: loadImage)
        .onReceive(NotificationCenter.default.publisher(for: .annotationsComposited)) { _ in
            reloadFromCache()
        }
        // Identity is the photo URL alone. An earlier fix keyed identity on
        // "\(url)-\(UUID())" to force a reload when the URL changed — but the
        // per-instance UUID is regenerated on every struct init, so every
        // parent re-render minted a fresh identity. That discarded @State
        // (the composited markup grabbed via .annotationsComposited) and tore
        // down the subscription, so the raw photo loaded back in. The gallery
        // carousel re-renders constantly (reactive @Query / @ObservedObject),
        // which is why markup never stuck on thumbnails. Keying on `url` alone
        // still forces a reload when the URL changes, while letting the
        // composited image survive re-renders.
        .id(url)
    }

    /// Re-read the image after a composite pass. In-memory first; then the
    /// durable on-disk composite, so a thumbnail whose cache entry was already
    /// evicted still swaps in the markup when `.annotationsComposited` fires.
    private func reloadFromCache() {
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url
        if let updated = ImageCache.shared.get(forKey: cacheKey) {
            image = updated
        } else if let composited = ImageFileManager.shared.loadCompositedImage(forURL: url) {
            image = composited
            ImageCache.shared.set(composited, forKey: cacheKey)
        }
    }

    private func loadImage() {
        guard image == nil else { return }

        isLoading = true

        // Check if this is an asset catalog name (no URL prefix)
        // Asset catalog names don't contain "://" or start with "//"
        let isAssetName = !url.contains("://") && !url.hasPrefix("//")

        if isAssetName {
            // Try to load from asset catalog (demo images)
            if let assetImage = UIImage(named: url) {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.image = assetImage
                    // Cache in memory
                    ImageCache.shared.set(assetImage, forKey: url)
                }
                return
            }
        }

        // Normalize URL at the start for consistent caching
        // Handle // prefix by adding https:
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url

        // First check in-memory cache
        if let cachedImage = ImageCache.shared.get(forKey: cacheKey) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = cachedImage
            }
            return
        }

        // Durable annotated composite (markup flattened onto the photo), checked
        // BEFORE the raw original. The in-memory cache holds barely one full-
        // resolution composite, so a thumbnail scrolled into view long after the
        // .annotationsComposited posts fired would otherwise resolve the raw and
        // lose its marks. The on-disk composite makes markup mount-time durable.
        if let composited = ImageFileManager.shared.loadCompositedImage(forURL: url) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = composited
                ImageCache.shared.set(composited, forKey: cacheKey)
            }
            return
        }

        // Then try to load from file system using ImageFileManager
        // ImageFileManager also normalizes URLs internally for consistent file paths
        if let loadedImage = ImageFileManager.shared.loadImage(localID: url) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = loadedImage

                // Cache in memory for faster access next time
                ImageCache.shared.set(loadedImage, forKey: cacheKey)
            }
            return
        }

        // For legacy support: try UserDefaults if not found in file system
        if url.hasPrefix("local://") {
            if let base64String = UserDefaults.standard.string(forKey: url),
               let imageData = Data(base64Encoded: base64String),
               let loadedImage = UIImage(data: imageData) {

                // Migrate to file system for future use
                _ = ImageFileManager.shared.saveImage(data: imageData, localID: url)

                DispatchQueue.main.async {
                    self.isLoading = false
                    self.image = loadedImage

                    // Cache in memory
                    ImageCache.shared.set(loadedImage, forKey: cacheKey)
                }
                return
            }
        }

        // If not found locally, try to load from network
        guard let imageURL = URL(string: cacheKey) else {
            isLoading = false
            return
        }

        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error {
                    print("Image load error: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    print("Image load failed with status: \(httpResponse.statusCode)")
                    return
                }

                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage

                    // Cache the remote image locally in file system
                    _ = ImageFileManager.shared.saveImage(data: data, localID: cacheKey)

                    // Also cache in memory
                    ImageCache.shared.set(loadedImage, forKey: cacheKey)
                }
            }
        }.resume()
    }
}

/// Bug 189ace29 — corner badge for an unsynced project photo. Sized and
/// styled to mirror `ClientVisibilityButton` (22pt filled circle, 10pt
/// semibold glyph) so the two opposite-corner overlays read as a
/// matched pair. Rendered by the consuming carousel/grid as a sibling
/// of the thumbnail so it can sit `4pt` outside the corner like the
/// visibility eye instead of being clipped inside the rounded
/// rectangle.
struct PhotoSyncFailBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(OPSStyle.Colors.errorStatus)
                .frame(width: 22, height: 22)

            Image(systemName: "icloud.slash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .accessibilityLabel("Photo not synced")
    }
}

// Super simple photo viewer with no fancy animations - just works
struct BasicPhotoViewer: View {
    let photos: [String]
    let sourcePhotos: [String]
    let initialIndex: Int
    let onDismiss: () -> Void
    var projectId: String? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex: Int
    @State private var showingAnnotation = false

    init(
        photos: [String],
        sourcePhotos: [String]? = nil,
        initialIndex: Int,
        onDismiss: @escaping () -> Void,
        projectId: String? = nil
    ) {
        self.photos = photos
        self.sourcePhotos = sourcePhotos ?? photos
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self.projectId = projectId
        self._currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            TabView(selection: $currentIndex) {
                ForEach(0..<photos.count, id: \.self) { index in
                    SinglePhotoView(
                        url: photos[index],
                        onDismiss: onDismiss
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .background(OPSStyle.Colors.background)
            .edgesIgnoringSafeArea(.all)
            .statusBar(hidden: true)

            // Controls overlay
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.xl))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(OPSStyle.Layout.spacing3_5)
                    }
                }

                Spacer()

                if let projectId = projectId {
                    HStack {
                        Spacer()
                        Button(action: { showingAnnotation = true }) {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Image(systemName: "pencil.tip")
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                Text("ANNOTATE")
                                    .font(OPSStyle.Typography.captionBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.background)
                            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        }
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing5)
                    .fullScreenCover(isPresented: $showingAnnotation) {
                        if currentIndex < photos.count {
                            PhotoAnnotationView(
                                photoURL: sourcePhotoURL(at: currentIndex),
                                projectId: projectId,
                                existingAnnotation: existingAnnotation(at: currentIndex)
                            )
                        }
                    }
                }
            }
        }
    }

    private func sourcePhotoURL(at index: Int) -> String {
        guard sourcePhotos.indices.contains(index) else { return photos[index] }
        return sourcePhotos[index]
    }

    private func existingAnnotation(at index: Int) -> PhotoAnnotation? {
        let sourceURL = sourcePhotoURL(at: index)
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate {
                $0.photoURL == sourceURL && $0.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }
}

// Ultra simple photo view with zoom only
struct SinglePhotoView: View {
    let url: String
    let onDismiss: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    // Magnification gesture for zooming
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(value, 1), 3)
                            }
                            .onEnded { _ in
                                if scale < 1 {
                                    withAnimation(OPSStyle.Animation.standard) {
                                        scale = 1
                                    }
                                }
                            }
                    )
                    // Double tap to toggle zoom
                    .onTapGesture(count: 2) {
                        withAnimation(OPSStyle.Animation.standard) {
                            scale = scale > 1 ? 1 : 2
                        }
                    }
            } else if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                Text("Failed to load image")
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .onAppear(perform: loadImage)
    }
    
    private func loadImage() {
        guard image == nil else { return }

        isLoading = true

        // Check if this is an asset catalog name (no URL prefix)
        // Asset catalog names don't contain "://" or start with "//"
        let isAssetName = !url.contains("://") && !url.hasPrefix("//")

        if isAssetName {
            // Try to load from asset catalog (demo images)
            if let assetImage = UIImage(named: url) {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.image = assetImage
                    // Cache in memory
                    ImageCache.shared.set(assetImage, forKey: url)
                }
                return
            }
        }

        // Normalize URL at the start for consistent caching
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url

        // First check in-memory cache
        if let cachedImage = ImageCache.shared.get(forKey: cacheKey) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = cachedImage
            }
            return
        }

        // Durable annotated composite before the raw original — keeps markup
        // visible in the full-screen viewer after NSCache eviction.
        if let composited = ImageFileManager.shared.loadCompositedImage(forURL: url) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = composited
                ImageCache.shared.set(composited, forKey: cacheKey)
            }
            return
        }

        // Then try to load from file system using ImageFileManager
        if let loadedImage = ImageFileManager.shared.loadImage(localID: url) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = loadedImage

                // Cache in memory for faster access next time
                ImageCache.shared.set(loadedImage, forKey: cacheKey)
            }
            return
        }

        // For legacy support: try UserDefaults if not found in file system
        if url.hasPrefix("local://") {
            if let base64String = UserDefaults.standard.string(forKey: url),
               let imageData = Data(base64Encoded: base64String),
               let loadedImage = UIImage(data: imageData) {

                // Migrate to file system for future use
                _ = ImageFileManager.shared.saveImage(data: imageData, localID: url)

                DispatchQueue.main.async {
                    self.isLoading = false
                    self.image = loadedImage

                    // Cache in memory
                    ImageCache.shared.set(loadedImage, forKey: cacheKey)
                }
                return
            }
        }

        // If not found locally, try to load from network
        guard let imageURL = URL(string: cacheKey) else {
            isLoading = false
            return
        }

        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error {
                    print("Image load error: \(error.localizedDescription)")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    print("Image load failed with status: \(httpResponse.statusCode)")
                    return
                }

                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage

                    // Cache the remote image locally in file system
                    _ = ImageFileManager.shared.saveImage(data: data, localID: cacheKey)

                    // Also cache in memory
                    ImageCache.shared.set(loadedImage, forKey: cacheKey)
                }
            }
        }.resume()
    }
}

// MARK: - Project Photo Management
extension ProjectPhotosGrid {
    fileprivate func displayedPhotoItems(from sourceURLs: [String]) -> [ProjectPhotoDisplayItem] {
        ProjectPhotoDisplayMapper.items(
            sourceURLs: sourceURLs,
            renderedURLsBySource: renderedURLsBySource,
            renderedDeliverableURLs: renderedDeliverableURLs
        )
    }

    /// Phase F — pulls `PhotoAnnotation` rows with non-null dimensions for this
    /// project and converts them into the URL set consumed by `PhotoThumbnail`.
    @MainActor
    fileprivate func refreshDimensionedURLs() async {
        let projectId = project.id
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate {
                $0.projectId == projectId
                    && $0.dimensionsData != nil
                    && $0.deletedAt == nil
            }
        )
        guard let annotations = try? modelContext.fetch(descriptor) else { return }
        dimensionedURLs = DimensionBadgeOverlay.dimensionedURLs(in: annotations)
        renderedURLsBySource = DimensionBadgeOverlay.renderedDeliverableURLsBySource(in: annotations)
        renderedDeliverableURLs = annotations
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { $0.renderedPhotoURL?.isEmpty == false ? $0.renderedPhotoURL : nil }
    }

    static func annotationMatchesDeleteTarget(
        _ annotation: PhotoAnnotation,
        sourceURL: String,
        renderedURL: String?
    ) -> Bool {
        if annotation.photoURL == sourceURL {
            return true
        }

        guard let renderedURL, !renderedURL.isEmpty else {
            return false
        }

        return annotation.renderedPhotoURL == renderedURL
    }

    /// Delete a single photo from the project
    private func deletePhoto(_ target: ProjectPhotoDeleteTarget) {
        Task {
            switch target {
            case .projectImage(let sourceURL):
                await deleteProjectImagePhoto(sourceURL)
            case .annotation(let sourceURL, let renderedURL):
                await deleteAnnotationBackedPhoto(sourceURL: sourceURL, renderedURL: renderedURL)
            }
        }
    }

    private func deleteProjectImagePhoto(_ sourceURL: String) async {
        // Get current project images
        var currentImages = project.getProjectImages()

        // Remove the specified image
        guard let index = currentImages.firstIndex(of: sourceURL) else {
            await MainActor.run {
                photoDeleteTarget = nil
            }
            return
        }

        currentImages.remove(at: index)

        // Use ImageSyncManager if available
        if let imageSyncManager = dataController.imageSyncManager {
            // Delete the image through the ImageSyncManager
            let success = await imageSyncManager.deleteImage(sourceURL, from: project)

            if success {
            } else {
            }
        } else {
            // Fallback to direct file deletion if ImageSyncManager is not available

            // Clean up file storage
            if sourceURL.hasPrefix("local://") {
                _ = ImageFileManager.shared.deleteImage(localID: sourceURL)
            }

            // Also clean up UserDefaults (for legacy support)
            UserDefaults.standard.removeObject(forKey: sourceURL)
        }

        let renderedURL = await MainActor.run {
            renderedURLsBySource[sourceURL]
        }
        let deletePlan = await MainActor.run {
            let deletePlan = renderedURL.map {
                markMatchingAnnotationsDeleted(sourceURL: sourceURL, renderedURL: $0)
            } ?? ProjectPhotoAnnotationDeletePlan(remoteSoftDeleteCandidates: [], localOnlyCandidateIDs: [])

            project.setProjectImageURLs(currentImages)
            project.needsSync = true
            project.syncPriority = 2 // Higher priority for image changes

            removeDeletedRenderedState(sourceURL: sourceURL, renderedURL: renderedURL)
            saveModelChanges()
            photoDeleteTarget = nil
            return deletePlan
        }

        await softDeleteAnnotationsRemotely(deletePlan.remoteSoftDeleteCandidates)
    }

    private func deleteAnnotationBackedPhoto(sourceURL: String, renderedURL: String) async {
        let deletePlan = await MainActor.run {
            let deletePlan = markMatchingAnnotationsDeleted(sourceURL: sourceURL, renderedURL: renderedURL)
            removeDeletedRenderedState(sourceURL: sourceURL, renderedURL: renderedURL)
            saveModelChanges()
            photoDeleteTarget = nil
            return deletePlan
        }

        await softDeleteAnnotationsRemotely(deletePlan.remoteSoftDeleteCandidates)
    }

    @MainActor
    private func markMatchingAnnotationsDeleted(
        sourceURL: String,
        renderedURL: String?
    ) -> ProjectPhotoAnnotationDeletePlan {
        let projectId = project.id
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate {
                $0.projectId == projectId
                    && $0.deletedAt == nil
            }
        )
        guard let annotations = try? modelContext.fetch(descriptor) else {
            return ProjectPhotoAnnotationDeletePlan(remoteSoftDeleteCandidates: [], localOnlyCandidateIDs: [])
        }

        let now = Date()
        let matches = annotations.filter {
            Self.annotationMatchesDeleteTarget($0, sourceURL: sourceURL, renderedURL: renderedURL)
        }

        for annotation in matches {
            annotation.deletedAt = now
            annotation.updatedAt = now
            annotation.needsSync = ProjectPhotoAnnotationDeletePlanner.shouldMarkNeedsSyncAfterLocalDelete(
                annotationID: annotation.id
            )

            // Invalidate the durable markup composite immediately so the disk
            // bytes are reclaimed now and nothing serves the deleted markup
            // before the next preComposite reconciliation pass runs.
            ImageFileManager.shared.deleteCompositedImage(forURL: annotation.photoURL)
            let cacheKey = annotation.photoURL.hasPrefix("//")
                ? "https:" + annotation.photoURL
                : annotation.photoURL
            ImageCache.shared.remove(forKey: cacheKey)
        }

        let candidates = matches.map {
            ProjectPhotoAnnotationDeleteCandidate(id: $0.id, companyId: $0.companyId)
        }
        return ProjectPhotoAnnotationDeletePlanner.plan(candidates: candidates)
    }

    @MainActor
    private func markAnnotationDeleteSynced(id: String) {
        let descriptor = FetchDescriptor<PhotoAnnotation>(
            predicate: #Predicate { $0.id == id }
        )
        guard let annotation = try? modelContext.fetch(descriptor).first else {
            return
        }

        annotation.needsSync = false
        annotation.lastSyncedAt = Date()
        saveModelChanges()
    }

    @MainActor
    private func removeDeletedRenderedState(sourceURL: String, renderedURL: String?) {
        let updated = ProjectPhotoAnnotationDeletePlanner.removingRenderedState(
            sourceURL: sourceURL,
            renderedURL: renderedURL,
            from: ProjectPhotoRenderedDeleteState(
                dimensionedURLs: dimensionedURLs,
                renderedURLsBySource: renderedURLsBySource,
                renderedDeliverableURLs: renderedDeliverableURLs
            )
        )
        dimensionedURLs = updated.dimensionedURLs
        renderedURLsBySource = updated.renderedURLsBySource
        renderedDeliverableURLs = updated.renderedDeliverableURLs
    }

    @MainActor
    private func saveModelChanges() {
        do {
            try modelContext.save()
        } catch {
        }
    }

    private func softDeleteAnnotationsRemotely(_ candidates: [ProjectPhotoAnnotationDeleteCandidate]) async {
        for candidate in candidates {
            do {
                let repository = await MainActor.run {
                    PhotoAnnotationRepository(companyId: candidate.companyId)
                }
                try await repository.softDelete(candidate.id)
                await markAnnotationDeleteSynced(id: candidate.id)
            } catch {
                await AutoBugReporter.shared.reportIfPermanent(
                    error,
                    screen: "ProjectPhotosGrid.deletePhoto",
                    suspectedFile: "ProjectPhotosGrid.swift",
                    summary: "Rendered photo annotation delete failed for \(candidate.id): \(error.localizedDescription)",
                    metadata: [
                        "annotation_id": candidate.id,
                        "company_id": candidate.companyId
                    ]
                )
                DebugLogger.shared.log(
                    "Rendered photo annotation delete failed for \(candidate.id): \(error)",
                    level: .warning,
                    category: "ProjectPhotosGrid"
                )
            }
        }
    }

    private func addPhotoToProject(_ image: UIImage) {
        // Start loading indicator
        processingImage = true
        
        
        Task {
            // Use the ImageSyncManager if available
            if let imageSyncManager = dataController.imageSyncManager {

                // Process the image through the ImageSyncManager
                let urls = await imageSyncManager.saveImages([image], for: project)

                if let url = urls.first, !url.isEmpty {
                    // ImageSyncManager already added the image to the project

                    await MainActor.run {
                        // Track photo capture
                        AnalyticsService.shared.track(
                            eventType: .action,
                            eventName: "photo_captured",
                            properties: ["count": 1, "context": "project"]
                        )
                        // Clear selected image and hide loading
                        cameraImage = nil
                        processingImage = false
                    }
                } else {
                    await MainActor.run {
                        processingImage = false
                        showingNetworkError = true
                        networkErrorMessage = "Failed to upload image to the server. Please check your network connection and try again."
                    }
                }
            } else {
                // Fallback to ImageFileManager if ImageSyncManager is not available
                
                // Compress image for storage
                guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                    await MainActor.run {
                        processingImage = false
                    }
                    return
                }
                
                // Generate a unique filename
                let timestamp = Date().timeIntervalSince1970
                let filename = "project_\(project.id)_\(timestamp)_\(UUID().uuidString).jpg"
                let localURL = "local://project_images/\(filename)"
                
                // Store the image in file system
                let success = ImageFileManager.shared.saveImage(data: imageData, localID: localURL)
                
                if success {
                    
                    // Add to project's images
                    await MainActor.run {
                        var currentImages = project.getProjectImages()
                        currentImages.append(localURL)
                        
                        project.setProjectImageURLs(currentImages)
                        project.needsSync = true
                        project.syncPriority = 2
                        
                        if let modelContext = dataController.modelContext {
                            do {
                                try modelContext.save()
                            } catch {
                            }
                        }
                        
                        // Clear selected image and hide loading
                        cameraImage = nil
                        processingImage = false
                    }
                } else {
                    await MainActor.run {
                        processingImage = false
                    }
                }
            }
        }
    }
}
