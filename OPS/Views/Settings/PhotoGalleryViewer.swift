//
//  PhotoGalleryViewer.swift
//  OPS
//

import SwiftUI

struct PhotoGalleryViewer: View {
    let photos: [PhotoItem]
    let initialIndex: Int
    let onDismiss: () -> Void

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var downloadManager = PhotoDownloadManager.shared
    @State private var currentIndex: Int
    @State private var showToolbar = true
    @State private var showMetadata = false
    @State private var dragOffset: CGSize = .zero
    @State private var isDraggingDown = false

    init(photos: [PhotoItem], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
    }

    private var currentPhoto: PhotoItem? {
        guard currentIndex >= 0 && currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .edgesIgnoringSafeArea(.all)

            // Photo pager
            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, item in
                    GalleryZoomablePhotoView(
                        url: item.url,
                        isOnDevice: downloadManager.isOnDevice(item.url),
                        onDownload: {
                            Task { await downloadManager.downloadPhoto(item.url) }
                        },
                        onTap: { showToolbar.toggle() }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .edgesIgnoringSafeArea(.all)
            // Swipe-down dismiss gesture
            .offset(y: max(0, dragOffset.height))
            .opacity(isDraggingDown ? Double(1 - (dragOffset.height / 400)) : 1)
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onChanged { value in
                        // Only activate vertical dismiss if gesture is predominantly vertical
                        let isVertical = abs(value.translation.height) > abs(value.translation.width) * 1.5
                        if isVertical && value.translation.height > 0 && !showMetadata {
                            isDraggingDown = true
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        if isDraggingDown && value.translation.height > 150 {
                            withAnimation(OPSStyle.Animation.fast) {
                                dragOffset = .zero
                                isDraggingDown = false
                            }
                            onDismiss()
                        } else {
                            withAnimation(OPSStyle.Animation.fast) {
                                dragOffset = .zero
                                isDraggingDown = false
                            }
                        }
                    }
            )

            // Toolbar overlay
            if showToolbar && !isDraggingDown {
                VStack {
                    // Top bar: [✕]  counter  [ⓘ]
                    topBar

                    Spacer()

                    // Metadata panel (shown when ⓘ tapped)
                    if showMetadata, let photo = currentPhoto {
                        metadataPanel(photo)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .statusBar(hidden: true)
        .onChange(of: currentIndex) { _, _ in
            showMetadata = false
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }

            Spacer()

            Text("\(currentIndex + 1) of \(photos.count)")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            Button(action: {
                withAnimation(OPSStyle.Animation.standard) {
                    showMetadata.toggle()
                }
            }) {
                Image(systemName: showMetadata ? "info.circle.fill" : "info.circle")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .background(
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .edgesIgnoringSafeArea(.top)
        )
    }

    // MARK: - Metadata Panel

    private func metadataPanel(_ photo: PhotoItem) -> some View {
        let isLocal = downloadManager.isOnDevice(photo.url)

        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            // Drag handle
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(OPSStyle.Colors.tertiaryText)
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 8)
            .onTapGesture {
                withAnimation(OPSStyle.Animation.standard) {
                    showMetadata = false
                }
            }

            // Project
            infoRow(icon: OPSStyle.Icons.project, label: photo.projectTitle)

            // Uploader
            if let authorId = photo.authorId, !authorId.isEmpty {
                let uploaderName = lookupUserName(authorId)
                infoRow(icon: OPSStyle.Icons.person, label: uploaderName ?? "Unknown")
            }

            // Date
            infoRow(icon: "calendar", label: photo.date.formatted(date: .long, time: .shortened))

            // Note
            if let note = photo.note {
                infoRow(icon: OPSStyle.Icons.notes, label: note)
            }

            // Storage status
            infoRow(
                icon: isLocal ? "internaldrive" : "icloud.and.arrow.down",
                label: isLocal ? "On Device" : "Not Downloaded"
            )

            // Divider
            OPSStyle.Colors.separator
                .frame(height: 1)
                .padding(.vertical, 4)

            // Share row
            Button(action: shareCurrentPhoto) {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(isLocal ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .frame(width: 20, alignment: .center)

                    Text("Share Photo")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(isLocal ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .disabled(!isLocal)
            .buttonStyle(PlainButtonStyle())

            // Go to Project row
            Button(action: { goToProject(photo.projectId) }) {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: 20, alignment: .center)

                    Text("Go to Project")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, OPSStyle.Layout.spacing4)
        .background(
            OPSStyle.Colors.cardBackgroundDark
                .cornerRadius(OPSStyle.Layout.cardCornerRadius, corners: [.topLeft, .topRight])
        )
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 30 {
                        withAnimation(OPSStyle.Animation.standard) {
                            showMetadata = false
                        }
                    }
                }
        )
    }

    private func infoRow(icon: String, label: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 20, alignment: .center)

            Text(label)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(2)
        }
    }

    // MARK: - Actions

    private func shareCurrentPhoto() {
        guard let photo = currentPhoto else { return }
        let cacheKey = photo.url.hasPrefix("//") ? "https:" + photo.url : photo.url
        guard let image = ImageFileManager.shared.loadImage(localID: photo.url) ??
                         ImageFileManager.shared.loadImage(localID: cacheKey) else { return }

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

    private func goToProject(_ projectId: String) {
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            appState.viewProjectDetailsById(projectId)
        }
    }

    private func lookupUserName(_ userId: String) -> String? {
        guard let companyId = dataController.currentUser?.companyId else { return nil }
        let members = dataController.getTeamMembers(companyId: companyId)
        return members.first(where: { $0.id == userId })?.fullName
    }
}

// MARK: - Zoomable Photo View

struct GalleryZoomablePhotoView: View {
    let url: String
    let isOnDevice: Bool
    let onDownload: () -> Void
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            OPSStyle.Colors.background

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let newScale = lastScale * value
                                    scale = min(max(newScale, 1), 5)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale <= 1 {
                                        withAnimation(OPSStyle.Animation.fast) {
                                            scale = 1
                                            lastScale = 1
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                },
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(OPSStyle.Animation.fast) {
                            if scale > 1 {
                                scale = 1
                                lastScale = 1
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2
                                lastScale = 2
                            }
                        }
                    }
                    .onTapGesture(count: 1) {
                        onTap()
                    }
            } else if !isOnDevice {
                // Remote photo — download prompt
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Button(action: {
                        Task {
                            // Download via manager (handles caching + progress)
                            _ = await PhotoDownloadManager.shared.downloadPhoto(url)
                            // Reload from disk after download completes
                            loadImage()
                        }
                    }) {
                        Text("Download")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing4)
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }
                }
            } else if isLoading {
                ProgressView()
                    .tint(OPSStyle.Colors.secondaryText)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: OPSStyle.Layout.IconSize.xl))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .onAppear { if isOnDevice { loadImage() } }
    }

    private func loadImage() {
        isLoading = true
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url

        // Check asset catalog
        if !url.contains("://") && !url.hasPrefix("//"), let assetImage = UIImage(named: url) {
            image = assetImage
            isLoading = false
            return
        }

        // Memory cache
        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            image = cached
            isLoading = false
            return
        }

        // File system
        if let loaded = ImageFileManager.shared.loadImage(localID: url) ?? ImageFileManager.shared.loadImage(localID: cacheKey) {
            image = loaded
            ImageCache.shared.set(loaded, forKey: cacheKey)
            isLoading = false
            return
        }

        // Network fallback
        guard let imageURL = URL(string: cacheKey) else { isLoading = false; return }
        URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                if let data = data, let loaded = UIImage(data: data) {
                    image = loaded
                    _ = ImageFileManager.shared.saveImage(data: data, localID: cacheKey)
                    ImageCache.shared.set(loaded, forKey: cacheKey)
                }
            }
        }.resume()
    }
}

// RoundedCorner and cornerRadius(_:corners:) extension already defined in RouteDirectionsView.swift
