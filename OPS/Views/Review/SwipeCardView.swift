//
//  SwipeCardView.swift
//  OPS
//
//  Full-bleed photo card for project payment review.
//  Loads up to 3 most recent project photos; stacks non-portrait images vertically.
//

import SwiftUI

struct SwipeCardView: View {
    let project: Project
    let daysSinceCompleted: Int
    let showFinancialInfo: Bool
    let onTap: () -> Void

    @State private var heroImages: [UIImage] = []
    @State private var isLoadingImage = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed photo(s)
            projectPhoto

            // Top gradient for header/hints visibility
            VStack {
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.55), .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                Spacer()
            }

            // Bottom gradient for text readability
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                startPoint: .center,
                endPoint: .bottom
            )

            // Project info overlay
            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                // Days overdue badge
                Text("\(daysSinceCompleted) DAYS AGO")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius).fill(daysSinceCompleted > 30
                            ? OPSStyle.Colors.errorStatus
                            : OPSStyle.Colors.warningStatus)
                    )

                // Project name
                Text(project.title.uppercased())
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                    .lineLimit(2)

                // Client name
                Text(project.effectiveClientName.uppercased())
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(OPSStyle.Layout.spacing3_5)
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        // Reload whenever the underlying project identity changes. The card
        // stack recycles a fixed set of slot views as it advances, so .onAppear
        // would not re-fire when a slot is reassigned to a new project —
        // leaving the previous project's photo under the new project's labels.
        // Keying the load on project.id reloads on every reassignment, and
        // SwiftUI cancels the prior in-flight load so a slow fetch can't land on
        // the wrong card.
        .task(id: project.id) { await loadHeroImages() }
    }

    // MARK: - Photo Display

    @ViewBuilder
    private var projectPhoto: some View {
        let stackable = heroImages.filter { $0.size.width >= $0.size.height }

        if stackable.count >= 2 {
            // Stack non-portrait photos vertically
            GeometryReader { geo in
                let count = min(stackable.count, 3)
                VStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in
                        Image(uiImage: stackable[i])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height / CGFloat(count))
                            .clipped()
                    }
                }
            }
        } else if let image = heroImages.first {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        } else if isLoadingImage {
            ZStack {
                statusGradientFallback
                ProgressView()
                    .tint(.white)
            }
        } else {
            statusGradientFallback
        }
    }

    private var statusGradientFallback: some View {
        LinearGradient(
            colors: [
                project.status.color.opacity(0.4),
                OPSStyle.Colors.background
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    // MARK: - Image Loading

    @MainActor
    private func loadHeroImages() async {
        // Reset slot state up front: a recycled card slot still holds the prior
        // project's images, so clear them and show the loading state until the
        // new project's photos resolve — otherwise the old photo flashes under
        // the new labels.
        heroImages = []
        isLoadingImage = true

        let photos = project.getProjectImages()
        guard !photos.isEmpty else {
            isLoadingImage = false
            return
        }

        let recentPhotos = Array(photos.suffix(3))

        var loaded: [UIImage] = []
        for photoKey in recentPhotos {
            if Task.isCancelled { return }
            if let img = await loadSingleImage(photoKey) {
                loaded.append(img)
            }
        }

        // A reassigned slot cancels this task; bail before publishing so a stale
        // load never overwrites the current project's images.
        if Task.isCancelled { return }
        heroImages = loaded
        isLoadingImage = false
    }

    private func loadSingleImage(_ photoKey: String) async -> UIImage? {
        let cacheKey = photoKey.hasPrefix("//") ? "https:" + photoKey : photoKey

        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            return cached
        }

        if let loaded = ImageFileManager.shared.loadImage(localID: photoKey) {
            ImageCache.shared.set(loaded, forKey: cacheKey)
            return loaded
        }

        guard let url = URL(string: cacheKey) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                ImageCache.shared.set(img, forKey: cacheKey)
                return img
            }
        } catch {}

        return nil
    }
}
