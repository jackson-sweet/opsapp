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
                Image("ops.close")
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
                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
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
                    Image("ops.share")
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
                    Image(OPSStyle.Icons.chevronRight)
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

/// Gallery variant of ZoomablePhotoView with download-prompt for remote photos.
/// Uses UIScrollView under the hood for native iOS Photos zoom/pan behavior.
struct GalleryZoomablePhotoView: View {
    let url: String
    let isOnDevice: Bool
    let onDownload: () -> Void
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            OPSStyle.Colors.background

            if let image = image {
                GalleryNativeZoomableImageView(image: image, onSingleTap: onTap)
            } else if !isOnDevice {
                // Remote photo — download prompt
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Image("ops.download")
                        .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Button(action: {
                        Task {
                            _ = await PhotoDownloadManager.shared.downloadPhoto(url)
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
                Image("ops.photo")
                    .font(.system(size: OPSStyle.Layout.IconSize.xl))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .onAppear { if isOnDevice { loadImage() } }
    }

    private func loadImage() {
        isLoading = true
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url

        if !url.contains("://") && !url.hasPrefix("//"), let assetImage = UIImage(named: url) {
            image = assetImage
            isLoading = false
            return
        }

        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            image = cached
            isLoading = false
            return
        }

        if let loaded = ImageFileManager.shared.loadImage(localID: url) ?? ImageFileManager.shared.loadImage(localID: cacheKey) {
            image = loaded
            ImageCache.shared.set(loaded, forKey: cacheKey)
            isLoading = false
            return
        }

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

/// UIKit-backed zoomable image for the gallery viewer.
/// Identical behavior to NativeZoomableImageView in ZoomablePhotoView.swift.
private struct GalleryNativeZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var onSingleTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> GalleryZoomingScrollView {
        let scrollView = GalleryZoomingScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.isScrollEnabled = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        scrollView.zoomImageView = imageView
        context.coordinator.imageView = imageView

        // Snap back to 1× when pinch ends
        if let pinchGR = scrollView.pinchGestureRecognizer {
            pinchGR.addTarget(
                context.coordinator,
                action: #selector(Coordinator.handlePinch(_:))
            )
        }

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: GalleryZoomingScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        guard let imageView = context.coordinator.imageView else { return }

        if imageView.image !== image {
            imageView.image = image
            scrollView.zoomScale = 1.0
            scrollView.isScrollEnabled = false
            scrollView.setNeedsLayout()
        }
    }

    class GalleryZoomingScrollView: UIScrollView {
        weak var zoomImageView: UIImageView?
        var lastLayoutSize: CGSize = .zero

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let imageView = zoomImageView, let image = imageView.image else { return }
            let boundsSize = bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }
            guard zoomScale <= minimumZoomScale + 0.01 else { return }
            guard boundsSize != lastLayoutSize else { return }
            lastLayoutSize = boundsSize

            let imageSize = image.size
            let wScale = boundsSize.width / imageSize.width
            let hScale = boundsSize.height / imageSize.height
            let fitScale = min(wScale, hScale)
            let fittedW = imageSize.width * fitScale
            let fittedH = imageSize.height * fitScale

            imageView.frame = CGRect(
                x: (boundsSize.width - fittedW) / 2,
                y: (boundsSize.height - fittedH) / 2,
                width: fittedW,
                height: fittedH
            )
            contentSize = CGSize(width: fittedW, height: fittedH)
        }
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onSingleTap: (() -> Void)?

        init(onSingleTap: (() -> Void)?) {
            self.onSingleTap = onSingleTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView = imageView else { return }
            let boundsSize = scrollView.bounds.size
            let frameSize = imageView.frame.size
            let atMinimum = scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01

            if atMinimum {
                scrollView.contentInset = .zero
                scrollView.isScrollEnabled = false
            } else {
                let xInset = max(0, (boundsSize.width - frameSize.width) / 2)
                let yInset = max(0, (boundsSize.height - frameSize.height) / 2)
                scrollView.contentInset = UIEdgeInsets(
                    top: yInset, left: xInset, bottom: yInset, right: xInset
                )
                scrollView.isScrollEnabled = true
            }
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat
        ) {
            if scale <= scrollView.minimumZoomScale + 0.01 {
                scrollView.contentInset = .zero
                scrollView.isScrollEnabled = false
                if let sv = scrollView as? GalleryZoomingScrollView {
                    sv.lastLayoutSize = .zero
                    sv.setNeedsLayout()
                    sv.layoutIfNeeded()
                }
            }
        }

        /// Snaps back to 1× when pinch gesture ends.
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .ended || gesture.state == .cancelled else { return }
            guard let scrollView = gesture.view as? UIScrollView else { return }

            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let location = gesture.location(in: imageView)
                let targetScale: CGFloat = 2.5
                let w = scrollView.bounds.width / targetScale
                let h = scrollView.bounds.height / targetScale
                let rect = CGRect(
                    x: location.x - w / 2,
                    y: location.y - h / 2,
                    width: w,
                    height: h
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            onSingleTap?()
        }
    }
}

// RoundedCorner and cornerRadius(_:corners:) extension already defined in RouteDirectionsView.swift
