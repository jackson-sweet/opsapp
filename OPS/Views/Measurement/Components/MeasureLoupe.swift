//
//  MeasureLoupe.swift
//  OPS
//
//  2× zoom loupe that appears under the finger when a measurement point is
//  being drag-refined (spec §5.2 Loupe behavior). Matches Apple Measure:
//  the loupe samples the photo around the touch point, magnifies it 2×,
//  and renders it with a crosshair reticle in the centre.
//
//  Clamping (spec §5.2 "Loupe clamps to screen edges"): the loupe view
//  itself shifts to stay fully on-screen. When the finger nears an edge,
//  the loupe's screen position is adjusted while the SAMPLE point stays
//  under the finger — so the magnified content still represents what the
//  finger is touching.
//
//  Implementation: the parent provides the photo as a UIImage plus the
//  current touch in photo-pixel coordinates. We render a tightly-cropped
//  square sample, scale it 2× via SwiftUI `Image.interpolation(.high)`,
//  and overlay a 1-pixel crosshair.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §5.2
//

import SwiftUI
import UIKit

public struct MeasureLoupe: View {

    /// The photo being annotated.
    public let photo: UIImage
    /// Touch point in photo-pixel space.
    public let touchPhotoPixel: CGPoint
    /// Touch point in view (screen) space. Used by the parent to position
    /// the loupe; this view itself only consumes `loupeOrigin`.
    public let touchScreenPoint: CGPoint
    /// Available screen area for clamping. Loupe will stay inside this rect.
    public let canvasBounds: CGRect

    public static let diameter: CGFloat = 120
    public static let zoom: CGFloat = 2.0
    /// Vertical offset above the finger so the loupe doesn't hide under the
    /// touch. Apple Measure offsets ~80 pt above touch.
    public static let touchOffset: CGFloat = 90

    public init(photo: UIImage,
                touchPhotoPixel: CGPoint,
                touchScreenPoint: CGPoint,
                canvasBounds: CGRect) {
        self.photo = photo
        self.touchPhotoPixel = touchPhotoPixel
        self.touchScreenPoint = touchScreenPoint
        self.canvasBounds = canvasBounds
    }

    public var body: some View {
        let sample = sampleImage()
        ZStack {
            Circle()
                .fill(Color.black)
                .overlay(
                    Image(uiImage: sample)
                        .interpolation(.high)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                )
            crosshair
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .position(clampedScreenPosition)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Sample

    /// Crops a square `sampleSidePhotoPx × sampleSidePhotoPx` region of the
    /// photo centred on `touchPhotoPixel`. We want a region that, when
    /// rendered at `diameter` points and `zoom` magnification, gives a 2×
    /// view of the photo at native pixel density.
    private var sampleSidePhotoPx: CGFloat {
        // diameter pt at 2x zoom == diameter/2 sampled pt of photo, in pixels
        // we operate on the UIImage's pixel space (scale-corrected size).
        return Self.diameter / Self.zoom * photo.scale
    }

    private func sampleImage() -> UIImage {
        let side = sampleSidePhotoPx
        let half = side / 2
        let sampleRect = CGRect(
            x: touchPhotoPixel.x * photo.scale - half,
            y: touchPhotoPixel.y * photo.scale - half,
            width: side,
            height: side
        )
        guard let cgImage = photo.cgImage else { return photo }
        // Crop with bounds clamping: out-of-bounds cropping is undefined on
        // CGImage, so we use a renderer that paints a black background then
        // draws the photo at the correct offset.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: side, height: side)))
            let origin = CGPoint(
                x: -sampleRect.origin.x,
                y: -sampleRect.origin.y
            )
            UIImage(cgImage: cgImage).draw(at: origin)
        }
    }

    // MARK: - Crosshair

    private var crosshair: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 18, height: 1)
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 1, height: 18)
        }
    }

    // MARK: - Clamping

    /// Position the loupe centre at `touchScreenPoint - (0, touchOffset)`,
    /// then clamp so the loupe rect stays inside `canvasBounds`.
    private var clampedScreenPosition: CGPoint {
        let desired = CGPoint(
            x: touchScreenPoint.x,
            y: touchScreenPoint.y - Self.touchOffset
        )
        let half = Self.diameter / 2
        let minX = canvasBounds.minX + half
        let maxX = canvasBounds.maxX - half
        let minY = canvasBounds.minY + half
        let maxY = canvasBounds.maxY - half
        return CGPoint(
            x: min(max(desired.x, minX), maxX),
            y: min(max(desired.y, minY), maxY)
        )
    }
}
