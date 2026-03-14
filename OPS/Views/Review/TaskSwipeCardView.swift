//
//  TaskSwipeCardView.swift
//  OPS
//
//  Full-bleed photo card for task completion review.
//  Loads up to 3 most recent project photos; stacks non-portrait images vertically.
//

import SwiftUI

struct TaskSwipeCardView: View {
    let task: ProjectTask
    let scheduledDaysAgo: Int
    let onTap: () -> Void
    var badgeOverride: (text: String, color: Color)? = nil

    @State private var heroImages: [UIImage] = []
    @State private var isLoadingImage = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed photo(s)
            projectPhoto

            // Task color stripe at top
            VStack {
                Rectangle()
                    .fill(Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent)
                    .frame(height: 4)
                Spacer()
            }

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

            // Task info overlay
            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                // Date badge
                Text(dateBadgeText)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius).fill(dateBadgeColor)
                    )

                // Task name
                Text(task.displayTitle.uppercased())
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                    .lineLimit(2)

                // Project title
                if let projectTitle = task.project?.title {
                    Text(projectTitle.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                // Client name
                if let clientName = task.project?.effectiveClientName {
                    Text(clientName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onAppear { loadHeroImages() }
    }

    // MARK: - Date Badge

    private var dateBadgeText: String {
        if let override = badgeOverride { return override.text }
        if scheduledDaysAgo == 0 {
            return "TODAY"
        } else {
            return "\(scheduledDaysAgo) DAYS AGO"
        }
    }

    private var dateBadgeColor: Color {
        if let override = badgeOverride { return override.color }
        if scheduledDaysAgo == 0 {
            return OPSStyle.Colors.successStatus
        } else if scheduledDaysAgo < 7 {
            return OPSStyle.Colors.warningStatus
        } else {
            return OPSStyle.Colors.errorStatus
        }
    }

    // MARK: - Photo Display

    @ViewBuilder
    private var projectPhoto: some View {
        let stackable = heroImages.filter { $0.size.width >= $0.size.height }

        if stackable.count >= 2 {
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
                taskGradientFallback
                ProgressView()
                    .tint(.white)
            }
        } else {
            taskGradientFallback
        }
    }

    private var taskGradientFallback: some View {
        LinearGradient(
            colors: [
                (Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent).opacity(0.4),
                OPSStyle.Colors.cardBackgroundDark
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    // MARK: - Image Loading

    private func loadHeroImages() {
        guard let project = task.project else {
            isLoadingImage = false
            return
        }

        let photos = project.getProjectImages()
        guard !photos.isEmpty else {
            isLoadingImage = false
            return
        }

        let recentPhotos = Array(photos.suffix(3))

        Task {
            var loaded: [UIImage] = []
            for photoKey in recentPhotos {
                if let img = await loadSingleImage(photoKey) {
                    loaded.append(img)
                }
            }
            await MainActor.run {
                heroImages = loaded
                isLoadingImage = false
            }
        }
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
