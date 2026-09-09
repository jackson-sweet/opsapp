//
//  TaskPhotoStrip.swift
//  OPS
//
//  Bug a290934f — a task's photos, shown where the task is.
//
//  Two sizes, one component, because the two places a task's evidence appears
//  are the same list read at different distances:
//
//    `.section` — Task Details › PHOTOS. Someone is ON this task. The strip is
//                 the subject of the card, tiles match the project gallery so
//                 the same photo reads the same size in both places, and it
//                 scrolls as far as the work goes.
//    `.compact` — the pinned TASK NOTES entry. The strip is a footnote under
//                 the instruction it belongs to, so it stays subordinate: four
//                 tiles, then a `+N` that says how much more there is without
//                 pretending to show it.
//
//  Newest first, matching the gallery (bug e7ef2c88): the photo someone just
//  took is the one they are looking for.
//

import SwiftUI

/// What a strip renders — resolved once, off the model, so the view does no
/// work while a feed scrolls.
struct TaskPhotoStripModel: Equatable {
    /// The tiles to draw, newest first.
    let visibleURLs: [String]
    /// How many further photos exist beyond `visibleURLs`. Zero when none.
    let overflowCount: Int

    var isEmpty: Bool { visibleURLs.isEmpty }

    /// - Parameters:
    ///   - urls: the task's photos, already newest-first
    ///     (`ProjectPhotoTaskIndex.urls(forTaskID:)` guarantees the order).
    ///   - limit: how many tiles this surface will draw, or nil for all of them.
    init(urls: [String], limit: Int? = nil) {
        guard let limit, limit > 0, urls.count > limit else {
            self.visibleURLs = urls
            self.overflowCount = 0
            return
        }
        // The overflow tile occupies one slot, so it replaces the last tile it
        // would otherwise have covered rather than being added beside it.
        let shown = limit - 1
        self.visibleURLs = Array(urls.prefix(shown))
        self.overflowCount = urls.count - shown
    }
}

struct TaskPhotoStrip: View {
    enum Size {
        /// Task Details › PHOTOS — the card's subject.
        case section
        /// A footnote strip under a pinned task note.
        case compact

        var tile: CGFloat {
            switch self {
            // The app's one photo-tile size, so a task's photo reads the
            // same as it does in the project gallery.
            case .section: return PhotoThumbnail.tileSize
            case .compact: return OPSStyle.Layout.taskPhotoTileCompactSize
            }
        }

        /// nil means "as far as the work goes" — the section strip scrolls.
        var limit: Int? {
            switch self {
            case .section: return nil
            case .compact: return 4
            }
        }
    }

    let model: TaskPhotoStripModel
    let project: Project
    var size: Size = .section
    /// Server-generated small renditions per url. A tile with one fetches the
    /// thumbnail instead of the multi-MB original.
    var thumbnailByURL: [String: String] = [:]
    /// Index into the task's full photo list — the overflow tile reports the
    /// first photo it stands for, so tapping it opens where it left off.
    let onTap: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(Array(model.visibleURLs.enumerated()), id: \.element) { index, url in
                    Button {
                        onTap(index)
                    } label: {
                        PhotoThumbnail(url: url, project: project, remoteThumbnailURL: thumbnailURL(url))
                            .frame(width: size.tile, height: size.tile)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                    .accessibilityLabel("Photo \(index + 1)")
                }

                if model.overflowCount > 0 {
                    Button {
                        onTap(model.visibleURLs.count)
                    } label: {
                        overflowTile
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                    .accessibilityLabel("\(model.overflowCount) more photos")
                }
            }
        }
    }

    private func thumbnailURL(_ url: String) -> String? {
        guard let value = thumbnailByURL[url], !value.isEmpty else { return nil }
        return value
    }

    private var overflowTile: some View {
        Text("+\(model.overflowCount)")
            .font(OPSStyle.Typography.captionBold)
            .monospacedDigit()
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .frame(width: size.tile, height: size.tile)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}

/// A tapped tile's position in the task's photo list. `fullScreenCover(item:)`
/// needs an `Identifiable`, and index 0 is a legitimate destination — an
/// optional `Int` would be ambiguous the moment the first tile is tapped.
struct TaskPhotoViewerTarget: Identifiable, Equatable {
    let value: Int
    var id: Int { value }
}
