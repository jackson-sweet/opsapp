//
//  ZoomablePhotoView.swift
//  OPS
//
//  Pinch-to-zoom photo viewer for a single image URL.
//  Used by PhotoCommentViewer for full-screen photo browsing.
//

import SwiftUI

struct ZoomablePhotoView: View {
    let url: String

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
                imageContent(image)
            } else if isLoading {
                ProgressView()
                    .tint(OPSStyle.Colors.secondaryText)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: OPSStyle.Layout.IconSize.xl))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .onAppear { loadImage() }
    }

    // MARK: - Image Content

    @ViewBuilder
    private func imageContent(_ uiImage: UIImage) -> some View {
        let base = Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
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

        if scale > 1 {
            // Zoomed in: attach both pinch and drag.
            // Drag is needed for panning. This will block TabView swiping,
            // which is correct — when zoomed, panning takes priority.
            base.gesture(
                SimultaneousGesture(
                    magnifyGesture,
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            )
        } else {
            // Normal zoom: only pinch gesture.
            // No DragGesture so TabView receives swipes for page changes.
            base.gesture(magnifyGesture)
        }
    }

    private var magnifyGesture: some Gesture {
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
            }
    }

    // MARK: - Image Loading

    private func loadImage() {
        isLoading = true
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url

        // Asset catalog
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
