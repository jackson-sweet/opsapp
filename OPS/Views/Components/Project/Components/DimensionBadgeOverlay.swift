//
//  DimensionBadgeOverlay.swift
//  OPS
//
//  Phase F — small SF Symbol overlay rendered on photo thumbnails that
//  back a LiDAR dimensioned capture. Spec §3.7 calls for "a small
//  dimension icon badge" on gallery thumbnails. Per the Phase F brief:
//  12 pt `ruler` symbol, white with a 0.6-stroke black halo for sunlight
//  legibility, anchored bottom-right of the thumbnail.
//
//  Visibility rule (decided by caller via `isDimensioned`):
//    • `project_photos.source == 'measurement'`, OR
//    • a `project_photo_annotations` row exists for the photo URL with a
//      non-null `dimensions` jsonb.
//
//  The caller computes that boolean once at the parent level (typically
//  via a SwiftData fetch keyed on `photoURL`) and passes it down — keeps
//  the badge a leaf view with zero data-layer coupling.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.7
//

import SwiftUI

public struct DimensionBadgeOverlay: View {

    /// When false, the view renders an empty placeholder (zero impact on
    /// hit testing or layout). Always set explicitly by the caller — the
    /// default `false` keeps unwired call sites benign.
    public let isDimensioned: Bool

    /// Icon point size — defaults to 12 per spec brief. Allow override for
    /// callers that need to scale on dense grids (e.g., 6-column photo wall).
    public var iconPointSize: CGFloat

    /// Inset from the bottom-right corner of the host thumbnail.
    public var cornerInset: CGFloat

    public init(
        isDimensioned: Bool,
        iconPointSize: CGFloat = 12,
        cornerInset: CGFloat = 4
    ) {
        self.isDimensioned = isDimensioned
        self.iconPointSize = iconPointSize
        self.cornerInset = cornerInset
    }

    public var body: some View {
        if isDimensioned {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    badge
                }
            }
            .padding(cornerInset)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Dimensioned photo")
        }
    }

    private var badge: some View {
        ZStack {
            // Black halo for sunlight legibility (0.6 pt stroke equivalent —
            // achieved by stacking the icon at offsets in 4 directions).
            ForEach(haloOffsets.indices, id: \.self) { index in
                let offset = haloOffsets[index]
                Image(systemName: "ruler")
                    .font(.system(size: iconPointSize, weight: .semibold))
                    .foregroundColor(.black)
                    .offset(x: offset.x, y: offset.y)
            }
            Image(systemName: "ruler")
                .font(.system(size: iconPointSize, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    /// Eight-way offset matrix at 0.6 pt — produces a continuous black halo
    /// around the white glyph at near-zero memory cost (no `Canvas`,
    /// `compositingGroup`, or filter required).
    private var haloOffsets: [CGPoint] {
        let r: CGFloat = 0.6
        return [
            CGPoint(x: -r, y: -r), CGPoint(x:  0, y: -r), CGPoint(x:  r, y: -r),
            CGPoint(x: -r, y:  0),                          CGPoint(x:  r, y:  0),
            CGPoint(x: -r, y:  r), CGPoint(x:  0, y:  r), CGPoint(x:  r, y:  r),
        ]
    }
}

// MARK: - Convenience helper for the parent grid view

extension DimensionBadgeOverlay {
    /// Returns the set of photo URLs that should display the badge, given a
    /// list of `PhotoAnnotation` SwiftData models. A photo is "dimensioned"
    /// if there exists an annotation for it with non-nil `dimensionsData`.
    /// Parent views compute this once and pass a containment check down.
    ///
    /// Internal because `PhotoAnnotation` is a SwiftData @Model with internal
    /// access. The view itself stays public.
    static func dimensionedURLs(in annotations: [PhotoAnnotation]) -> Set<String> {
        var result = Set<String>()
        for a in annotations where a.dimensionsData != nil && a.deletedAt == nil {
            result.insert(a.photoURL)
            if let renderedPhotoURL = a.renderedPhotoURL, !renderedPhotoURL.isEmpty {
                result.insert(renderedPhotoURL)
            }
        }
        return result
    }

    /// Returns the source-photo URL → rendered-deliverable URL map for saved
    /// dimensioned captures. Gallery views use this to show the burned-in PNG
    /// when it exists while keeping `photoURL` as the source asset pointer.
    static func renderedDeliverableURLsBySource(
        in annotations: [PhotoAnnotation]
    ) -> [String: String] {
        var result: [String: String] = [:]
        for a in annotations where a.dimensionsData != nil && a.deletedAt == nil {
            guard let renderedPhotoURL = a.renderedPhotoURL, !renderedPhotoURL.isEmpty else {
                continue
            }
            result[a.photoURL] = renderedPhotoURL
        }
        return result
    }
}
