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
        case .queued(let pending): return pending.id
        }
    }
}

enum LeadPhotoStripItem: Identifiable, Equatable {
    case importing(String)
    case photo(LeadPhotoItem)

    var id: String {
        switch self {
        case .importing(let id): return id
        case .photo(let photo):  return photo.id
        }
    }
}

enum LeadPhotoStripPresentation {
    static func items(
        reservationIDs: [String],
        queued: [PendingLeadImageUpload],
        remoteURLs: [String]
    ) -> [LeadPhotoStripItem] {
        let orderedQueued = queued.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return (lhs.batchIndex ?? 0) < (rhs.batchIndex ?? 0)
        }
        let queuedByID = Dictionary(
            uniqueKeysWithValues: orderedQueued.map { ($0.id, $0) }
        )
        let reservedItems = reservationIDs.map { id -> LeadPhotoStripItem in
            if let pending = queuedByID[id] {
                return .photo(.queued(pending))
            }
            return .importing(id)
        }
        let reservationSet = Set(reservationIDs)
        let otherQueued = orderedQueued
            .filter { !reservationSet.contains($0.id) }
            .map { LeadPhotoStripItem.photo(.queued($0)) }
        let remote = remoteURLs
            .filter { !$0.isEmpty }
            .reversed()
            .map { LeadPhotoStripItem.photo(.remote($0)) }
        return reservedItems + otherQueued + remote
    }
}

struct LeadPhotosSection: View {
    let opportunity: Opportunity
    let canManage: Bool
    var importingPhotoIDs: [String] = []
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
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                return (lhs.batchIndex ?? 0) < (rhs.batchIndex ?? 0)
            }
            .map(LeadPhotoItem.queued)
        let remote = opportunity.images
            .filter { !$0.isEmpty }
            .reversed()
            .map(LeadPhotoItem.remote)
        return queued + remote
    }

    var stripItems: [LeadPhotoStripItem] {
        LeadPhotoStripPresentation.items(
            reservationIDs: importingPhotoIDs,
            queued: imageService.queuedUploads(for: opportunity.id)
                .filter { $0.localURL.hasPrefix("local://") },
            remoteURLs: opportunity.images
        )
    }

    /// Document-row form (Leads redesign spec §5.9): the PHOTOS row's content
    /// region — no header, no outer padding; the details document supplies
    /// the label column. Empty + view-only renders the document's `—` blank.
    var body: some View {
        let photoItems = self.items
        let stripItems = self.stripItems
        if stripItems.isEmpty && !canManage {
            Text("—")
                .font(.custom("Mohave-Medium", size: 14))
                .foregroundColor(OPSStyle.Colors.textMute)
        } else if stripItems.isEmpty {
            // Empty + can manage — one quiet tile-sized affordance.
            addTile
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    if canManage {
                        addTile
                    }
                    ForEach(stripItems) { stripItem in
                        switch stripItem {
                        case .importing:
                            importingTile
                        case .photo(let item):
                            Button {
                                guard let index = photoItems.firstIndex(of: item) else { return }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onTap(photoItems, index)
                            } label: {
                                tile(for: item)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel(
                                accessibilityLabel(
                                    for: item,
                                    index: photoItems.firstIndex(of: item) ?? 0
                                )
                            )
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Tiles

    private let tileSize: CGFloat = 84

    private var importingTile: some View {
        ZStack {
            OPSStyle.Colors.fillNeutralDim
            Image(systemName: "photo")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .frame(width: tileSize, height: tileSize)
        .clipShape(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.buttonRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.buttonRadius,
                style: .continuous
            )
            .strokeBorder(
                OPSStyle.Colors.line,
                lineWidth: OPSStyle.Layout.Border.standard
            )
        )
        .accessibilityHidden(true)
    }

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
