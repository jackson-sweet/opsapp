//
//  SwipeCardView.swift
//  OPS
//

import SwiftUI

struct SwipeCardView: View {
    let project: Project
    let daysSinceCompleted: Int
    let showFinancialInfo: Bool
    let onTap: () -> Void

    @State private var heroImage: UIImage?
    @State private var isLoadingImage = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background: most recent project photo or fallback
            projectPhoto

            // Bottom gradient overlay for text readability
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
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(daysSinceCompleted > 30
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
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onAppear { loadHeroImage() }
    }

    // MARK: - Photo

    @ViewBuilder
    private var projectPhoto: some View {
        if let image = heroImage {
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
                OPSStyle.Colors.cardBackgroundDark
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    // MARK: - Image Loading

    private func loadHeroImage() {
        let photos = project.getProjectImages()
        guard let lastPhoto = photos.last else {
            isLoadingImage = false
            return
        }

        let cacheKey = lastPhoto.hasPrefix("//") ? "https:" + lastPhoto : lastPhoto

        // Check cache first
        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            heroImage = cached
            isLoadingImage = false
            return
        }

        // Try file system
        if let loadedImage = ImageFileManager.shared.loadImage(localID: lastPhoto) {
            ImageCache.shared.set(loadedImage, forKey: cacheKey)
            heroImage = loadedImage
            isLoadingImage = false
            return
        }

        // Load from network
        guard let url = URL(string: cacheKey) else {
            isLoadingImage = false
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = UIImage(data: data) {
                    ImageCache.shared.set(img, forKey: cacheKey)
                    await MainActor.run {
                        heroImage = img
                        isLoadingImage = false
                    }
                } else {
                    await MainActor.run { isLoadingImage = false }
                }
            } catch {
                await MainActor.run { isLoadingImage = false }
            }
        }
    }
}
