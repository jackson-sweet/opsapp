//
//  ProjectImagesSection.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-28.
//

import SwiftUI
import SwiftData

struct ProjectImagesSection: View {
    let project: Project
    @State private var selectedImageURL: String?
    /// Phase F — populated on appear via a SwiftData fetch of
    /// `PhotoAnnotation` rows for this project that carry a non-null
    /// `dimensionsData`. Drives the per-thumbnail `ruler` badge overlay.
    @State private var dimensionedURLs: Set<String> = []
    @State private var renderedURLsBySource: [String: String] = [:]
    @State private var renderedDeliverableURLs: [String] = []
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Section header - always visible immediately
            Text("PHOTOS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            let imageItems = displayedPhotoItems(from: project.getProjectImages())
            
            if imageItems.isEmpty {
                // Empty state - shown immediately if no images
                emptyState
            } else {
                VStack(spacing: 8) {
                    // Image grid - images load independently
                    imageGrid(items: imageItems)

                    // Show message if there are unsynced images
                    if !project.getUnsyncedImages().isEmpty {
                        unsyncedImagesMessage
                    }
                }
            }
        }
        .task(id: project.id) { await refreshDimensionedURLs() }
        .onReceive(NotificationCenter.default.publisher(for: .annotationsComposited)) { _ in
            Task { await refreshDimensionedURLs() }
        }
        .fullScreenCover(item: $selectedImageURL) { url in
            // Full screen image view
            ZStack(alignment: .topTrailing) {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
                
                ProjectImageView(urlString: url, project: project, size: CGSize(width: UIScreen.main.bounds.width - 40, height: 400))
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                
                Button(action: { selectedImageURL = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.xl))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(20)
                }
            }
        }
    }

    private func displayedPhotoItems(from sourceURLs: [String]) -> [ProjectPhotoDisplayItem] {
        ProjectPhotoDisplayMapper.items(
            sourceURLs: sourceURLs,
            renderedURLsBySource: renderedURLsBySource,
            renderedDeliverableURLs: renderedDeliverableURLs
        )
    }
    
    // Empty state view
    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(OPSStyle.Icons.photo)
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))

            Text("No photos added yet")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(OPSStyle.Layout.spacing4)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    // Message about unsynced images
    private var unsyncedImagesMessage: some View {
        HStack {
            Image(systemName: "icloud.slash")
                .foregroundColor(OPSStyle.Colors.errorStatus)
            
            Text("Some images are not synced. They will be uploaded when network is available.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.warningStatus.opacity(0.1))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
    }
    
    // Image grid
    private func imageGrid(items: [ProjectPhotoDisplayItem]) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2),
            GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2)
        ], spacing: OPSStyle.Layout.spacing2) {
            ForEach(items) { item in
                ProjectImageView(
                    urlString: item.displayURL,
                    project: project,
                    isDimensioned: dimensionedURLs.contains(item.displayURL)
                        || dimensionedURLs.contains(item.sourceURL),
                    syncStatusURLString: item.syncStatusURL
                )
                .onTapGesture {
                    selectedImageURL = item.displayURL
                }
            }
        }
    }

    /// Fetches `PhotoAnnotation` rows for this project that carry a non-null
    /// `dimensionsData` blob and converts them into the URL set consumed by
    /// the per-thumbnail badge. Re-runs when the surrounding annotations
    /// recomposite (so a newly-saved dimensioned capture lights up the badge
    /// without requiring a tab switch).
    @MainActor
    private func refreshDimensionedURLs() async {
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
}
