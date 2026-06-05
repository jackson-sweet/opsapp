//
//  ZoomablePhotoView.swift
//  OPS
//
//  Pinch-to-zoom photo viewer for a single image URL.
//  Uses UIScrollView under the hood for native iOS Photos behavior:
//  pinch to zoom, pan when zoomed (with bounce/deceleration),
//  double-tap toggles zoom, single tap toggles overlay.
//  At 1× zoom panning is disabled so TabView page-swiping works.
//

import SwiftUI

struct ZoomablePhotoView: View {
    let url: String
    var onTap: (() -> Void)? = nil

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            OPSStyle.Colors.background

            if let image = image {
                NativeZoomableImageView(image: image, onSingleTap: onTap)
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

        // Durable annotated composite (markup flattened onto the photo), checked
        // BEFORE the raw original so markup survives NSCache eviction and the
        // viewer doesn't drop back to the unmarked photo on a fresh mount.
        if let composited = ImageFileManager.shared.loadCompositedImage(forURL: url) {
            image = composited
            ImageCache.shared.set(composited, forKey: cacheKey)
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

// MARK: - UIKit-backed zoomable image view

/// Wraps UIScrollView to replicate native iOS Photos zoom/pan behavior.
/// At 1× zoom, scrolling is disabled so parent TabView can page-swipe.
/// When zoomed in, UIScrollView handles panning with native physics.
private struct NativeZoomableImageView: UIViewRepresentable {
    let image: UIImage
    var onSingleTap: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> ZoomingScrollView {
        let scrollView = ZoomingScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.isScrollEnabled = false // disabled at 1× so TabView can swipe
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        scrollView.zoomImageView = imageView
        context.coordinator.imageView = imageView

        // Snap back to 1× when pinch ends (temporary peek zoom)
        if let pinchGR = scrollView.pinchGestureRecognizer {
            pinchGR.addTarget(
                context.coordinator,
                action: #selector(Coordinator.handlePinch(_:))
            )
        }

        // Double-tap toggles between 1× and ~2.5×
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // Single tap toggles the overlay (waits for double-tap to fail)
        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: ZoomingScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        guard let imageView = context.coordinator.imageView else { return }

        // If the image changed (TabView recycling), reset zoom and re-layout
        if imageView.image !== image {
            imageView.image = image
            scrollView.zoomScale = 1.0
            scrollView.isScrollEnabled = false
            scrollView.setNeedsLayout()
        }
    }

    // MARK: - ZoomingScrollView

    /// Custom UIScrollView subclass that sizes its image view in layoutSubviews,
    /// ensuring correct layout when the view first appears or bounds change.
    class ZoomingScrollView: UIScrollView {
        weak var zoomImageView: UIImageView?
        var lastLayoutSize: CGSize = .zero

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let imageView = zoomImageView, let image = imageView.image else { return }

            let boundsSize = bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }

            // Only re-layout at 1× zoom to avoid interfering with active zoom
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

    // MARK: - Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var onSingleTap: (() -> Void)?

        init(onSingleTap: (() -> Void)?) {
            self.onSingleTap = onSingleTap
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView = imageView else { return }

            let boundsSize = scrollView.bounds.size
            let frameSize = imageView.frame.size
            let atMinimum = scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01

            if atMinimum {
                // At 1×: clear insets so layoutSubviews centers the image
                scrollView.contentInset = .zero
                scrollView.isScrollEnabled = false
            } else {
                // Zoomed: center via insets when image is smaller than bounds
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
                // Force re-layout to re-center the image properly
                if let sv = scrollView as? ZoomingScrollView {
                    sv.lastLayoutSize = .zero
                    sv.setNeedsLayout()
                    sv.layoutIfNeeded()
                }
            }
        }

        // MARK: Gestures

        /// Snaps back to 1× when pinch gesture ends (temporary peek zoom).
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .ended || gesture.state == .cancelled else { return }
            guard let scrollView = gesture.view as? UIScrollView else { return }

            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                // Zoom out to 1×
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Zoom into tapped point at 2.5×
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
