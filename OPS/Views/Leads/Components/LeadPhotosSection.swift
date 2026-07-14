//
//  LeadPhotosSection.swift
//  OPS
//
//  Photos on the lead — the site-condition evidence an operator captures
//  while quoting. Horizontal thumb strip, newest first: queued (still
//  uploading / offline) tiles lead so the operator sees their newest shots
//  immediately, remote tiles follow in server order (web writes newest-last;
//  we reverse). ADD tile only for pipeline.manage; section disappears
//  entirely for a view-only operator with no photos.
//
//  Uploads ride LeadImageService: instant when online, durably queued when
//  not — a QUEUED chip on the tile is the only signal, no toast theater.
//

import SwiftUI

/// One tile in the strip / page in the viewer.
enum LeadPhotoItem: Identifiable, Equatable {
    case remote(String)                       // full public S3 URL
    case queued(PendingLeadImageUpload)       // local bytes awaiting upload

    var id: String {
        switch self {
        case .remote(let url):     return url
        case .queued(let pending): return pending.localURL
        }
    }
}

struct LeadPhotosSection: View {
    let opportunity: Opportunity
    let canManage: Bool
    /// Parent presents the camera / library dialog.
    var onAdd: () -> Void = {}
    /// Parent presents the full-screen viewer at the tapped index.
    var onTap: (_ items: [LeadPhotoItem], _ index: Int) -> Void = { _, _ in }

    @ObservedObject private var imageService = LeadImageService.shared

    /// Queued first (the operator's newest, still syncing), then remote
    /// newest-first.
    var items: [LeadPhotoItem] {
        let queued = imageService.queuedUploads(for: opportunity.id)
            .filter { $0.localURL.hasPrefix("local://") }
            .sorted { $0.timestamp > $1.timestamp }
            .map(LeadPhotoItem.queued)
        let remote = opportunity.images
            .filter { !$0.isEmpty }
            .reversed()
            .map(LeadPhotoItem.remote)
        return queued + remote
    }

    var body: some View {
        let items = self.items
        if items.isEmpty && !canManage {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                PanelSectionHeader(
                    label: "PHOTOS",
                    count: items.isEmpty ? nil : items.count
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                if items.isEmpty {
                    // Empty + can manage — one quiet 48pt affordance, not an
                    // acreage-eating empty state.
                    SheetCTAButton(
                        label: "ADD PHOTOS",
                        icon: "camera",
                        variant: .outline,
                        action: onAdd
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            if canManage {
                                addTile
                            }
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onTap(items, index)
                                } label: {
                                    tile(for: item)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .accessibilityLabel(accessibilityLabel(for: item, index: index))
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    // MARK: - Tiles

    private let tileSize: CGFloat = 84

    private var addTile: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onAdd()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text2)
                Text("ADD")
                    .font(.custom("JetBrainsMono-Medium", size: 9))
                    .kerning(1.2)
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .frame(width: tileSize, height: tileSize)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Add photos")
    }

    @ViewBuilder
    private func tile(for item: LeadPhotoItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            switch item {
            case .remote(let url):
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        brokenTile
                    default:
                        ProgressView()
                            .controlSize(.small)
                            .tint(OPSStyle.Colors.text3)
                    }
                }
            case .queued(let pending):
                if let image = imageService.queuedImage(for: pending) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    brokenTile
                }
            }

            if case .queued = item {
                Text("QUEUED")
                    .font(.custom("JetBrainsMono-Medium", size: 8))
                    .kerning(1.0)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.72))
                    .padding(4)
            }
        }
        .frame(width: tileSize, height: tileSize)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var brokenTile: some View {
        ZStack {
            OPSStyle.Colors.surfaceInput
            Image(systemName: "photo")
                .font(.system(size: 16))
                .foregroundColor(OPSStyle.Colors.textMute)
        }
    }

    private func accessibilityLabel(for item: LeadPhotoItem, index: Int) -> String {
        switch item {
        case .remote:  return "Photo \(index + 1)"
        case .queued:  return "Photo \(index + 1), queued for upload"
        }
    }
}
