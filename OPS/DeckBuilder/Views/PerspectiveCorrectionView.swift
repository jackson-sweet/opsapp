// OPS/OPS/DeckBuilder/Views/PerspectiveCorrectionView.swift
//
// Manual perspective-correction step inserted between PhotosPicker and the
// scan pipeline. The previous flow ran VNDetectDocumentSegmentationRequest
// silently and trusted the detected quad — but a builder's drawing
// photographed off-axis or with extra paper around the sketch needs the
// user's eyes on the corners. Bug 3ecfdbd4.
//
// The view pre-fills the four corner handles with the auto-detected quad
// (so the typical case is one tap to confirm) and lets the user drag any
// corner to refine. CIPerspectiveCorrection applies the final transform.

import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct PerspectiveCorrectionView: View {
    let image: UIImage
    let onApply: (UIImage) -> Void
    let onCancel: () -> Void

    /// Corners in NORMALIZED image coordinates (0...1, origin top-left). We
    /// store normalized so the handles stay anchored to the same point on
    /// the image regardless of how the view sizes the displayed image.
    @State private var topLeft: CGPoint = CGPoint(x: 0.05, y: 0.05)
    @State private var topRight: CGPoint = CGPoint(x: 0.95, y: 0.05)
    @State private var bottomLeft: CGPoint = CGPoint(x: 0.05, y: 0.95)
    @State private var bottomRight: CGPoint = CGPoint(x: 0.95, y: 0.95)

    @State private var isDetecting: Bool = true
    @State private var isApplying: Bool = false

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    lightImpact.impactOccurred()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                Spacer()
                Text("Adjust Corners")
                    .font(OPSStyle.Typography.heading)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                // Symmetry spacer so the title is visually centred
                Text("Cancel")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.top, OPSStyle.Layout.spacing4)
            .padding(.bottom, OPSStyle.Layout.spacing3)

            // Guidance
            Text("Drag the four corners to match the edges of the sketch. Pinch and drag the image-rest area is fine — the corners snap to your finger.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
                .padding(.bottom, OPSStyle.Layout.spacing3)

            // Image with corner handles
            GeometryReader { geometry in
                let imageRect = aspectFitRect(
                    imageSize: image.size,
                    in: geometry.size
                )

                ZStack(alignment: .topLeading) {
                    // Background
                    OPSStyle.Colors.cardBackground

                    // Image
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    // Quad outline + handles overlay
                    QuadOverlay(
                        topLeft: cornerInView(topLeft, imageRect: imageRect),
                        topRight: cornerInView(topRight, imageRect: imageRect),
                        bottomLeft: cornerInView(bottomLeft, imageRect: imageRect),
                        bottomRight: cornerInView(bottomRight, imageRect: imageRect)
                    )
                    .allowsHitTesting(false)

                    // Draggable handles — separate from the outline so each
                    // handle hit area is generous (44pt) without obscuring
                    // adjacent corners.
                    cornerHandle(position: cornerInView(topLeft, imageRect: imageRect)) { newPos in
                        topLeft = normalizedPoint(newPos, imageRect: imageRect)
                    }
                    cornerHandle(position: cornerInView(topRight, imageRect: imageRect)) { newPos in
                        topRight = normalizedPoint(newPos, imageRect: imageRect)
                    }
                    cornerHandle(position: cornerInView(bottomLeft, imageRect: imageRect)) { newPos in
                        bottomLeft = normalizedPoint(newPos, imageRect: imageRect)
                    }
                    cornerHandle(position: cornerInView(bottomRight, imageRect: imageRect)) { newPos in
                        bottomRight = normalizedPoint(newPos, imageRect: imageRect)
                    }

                    // Detecting indicator overlay
                    if isDetecting {
                        Color.black.opacity(0.4)
                            .overlay(
                                VStack(spacing: OPSStyle.Layout.spacing2) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                    Text("Detecting edges…")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                            )
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)

            Spacer(minLength: OPSStyle.Layout.spacing4)

            // Apply button
            Button {
                lightImpact.impactOccurred()
                applyCorrection()
            } label: {
                if isApplying {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.buttonText))
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                } else {
                    Text("Apply")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                }
            }
            .disabled(isApplying || isDetecting)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .fill(OPSStyle.Colors.primaryAccent.opacity(isApplying || isDetecting ? 0.5 : 1.0))
            )
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .onAppear {
            detectInitialCorners()
        }
    }

    // MARK: - Corner Handle

    private func cornerHandle(position: CGPoint, onChange: @escaping (CGPoint) -> Void) -> some View {
        Circle()
            .fill(OPSStyle.Colors.primaryAccent)
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .frame(width: 44, height: 44)  // Generous hit target
            .contentShape(Rectangle())
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onChange(value.location)
                    }
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
    }

    // MARK: - Coordinate Helpers

    /// Compute the rect the image actually occupies inside the available
    /// container after .scaledToFit. SwiftUI doesn't expose this directly,
    /// so we replicate the math: pick the smaller of the available
    /// width/height ratios against the image's aspect ratio.
    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = container.width / container.height
        let displaySize: CGSize
        if imageAspect > containerAspect {
            // Image is wider — fits to container width
            displaySize = CGSize(width: container.width, height: container.width / imageAspect)
        } else {
            // Image is taller — fits to container height
            displaySize = CGSize(width: container.height * imageAspect, height: container.height)
        }
        let origin = CGPoint(
            x: (container.width - displaySize.width) / 2,
            y: (container.height - displaySize.height) / 2
        )
        return CGRect(origin: origin, size: displaySize)
    }

    /// Normalized (0...1) image-space → view-space.
    private func cornerInView(_ normalized: CGPoint, imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + normalized.x * imageRect.width,
            y: imageRect.minY + normalized.y * imageRect.height
        )
    }

    /// View-space → normalized (0...1) image-space, clamped to the image rect.
    private func normalizedPoint(_ viewPoint: CGPoint, imageRect: CGRect) -> CGPoint {
        guard imageRect.width > 0, imageRect.height > 0 else { return .zero }
        let nx = (viewPoint.x - imageRect.minX) / imageRect.width
        let ny = (viewPoint.y - imageRect.minY) / imageRect.height
        return CGPoint(
            x: max(0, min(1, nx)),
            y: max(0, min(1, ny))
        )
    }

    // MARK: - Auto-Detection

    /// Run VNDetectDocumentSegmentationRequest to pre-fill the four corners
    /// with the detected quad. The user can drag from there to refine.
    private func detectInitialCorners() {
        guard let cgImage = image.cgImage else {
            isDetecting = false
            return
        }
        Task.detached(priority: .userInitiated) {
            let request = VNDetectDocumentSegmentationRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                if let observation = request.results?.first as? VNRectangleObservation {
                    // Vision uses normalized coordinates with origin at the
                    // bottom-left. Flip Y so our top-left convention works.
                    let tl = CGPoint(x: observation.topLeft.x, y: 1 - observation.topLeft.y)
                    let tr = CGPoint(x: observation.topRight.x, y: 1 - observation.topRight.y)
                    let bl = CGPoint(x: observation.bottomLeft.x, y: 1 - observation.bottomLeft.y)
                    let br = CGPoint(x: observation.bottomRight.x, y: 1 - observation.bottomRight.y)
                    await MainActor.run {
                        self.topLeft = tl
                        self.topRight = tr
                        self.bottomLeft = bl
                        self.bottomRight = br
                        self.isDetecting = false
                    }
                    return
                }
            } catch {
                // Fall through to default corners
            }
            await MainActor.run {
                self.isDetecting = false
            }
        }
    }

    // MARK: - Apply Correction

    private func applyCorrection() {
        isApplying = true
        let imgW = image.size.width
        let imgH = image.size.height

        // Convert normalized (top-left origin) to CIImage pixel space (bottom-left origin).
        // CIImage extent.height equals the image pixel height when constructed
        // from cgImage, so multiply by image dimensions and flip Y.
        let pixelTL = CGPoint(x: topLeft.x * imgW, y: (1 - topLeft.y) * imgH)
        let pixelTR = CGPoint(x: topRight.x * imgW, y: (1 - topRight.y) * imgH)
        let pixelBL = CGPoint(x: bottomLeft.x * imgW, y: (1 - bottomLeft.y) * imgH)
        let pixelBR = CGPoint(x: bottomRight.x * imgW, y: (1 - bottomRight.y) * imgH)

        Task.detached(priority: .userInitiated) {
            let corrected = correctedImage(
                source: image,
                topLeft: pixelTL,
                topRight: pixelTR,
                bottomLeft: pixelBL,
                bottomRight: pixelBR
            )
            await MainActor.run {
                isApplying = false
                mediumImpact.impactOccurred()
                onApply(corrected ?? image)
            }
        }
    }

    /// Apply CIPerspectiveCorrection with the given pixel-space corners.
    private nonisolated func correctedImage(
        source: UIImage,
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint
    ) -> UIImage? {
        guard let cgImage = source.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg, scale: source.scale, orientation: source.imageOrientation)
    }
}

// MARK: - Quad Outline

/// Dashed outline connecting the four corners. Drawn separately from the
/// handles so it stays purely visual and doesn't intercept handle drags.
private struct QuadOverlay: View {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint

    var body: some View {
        Path { path in
            path.move(to: topLeft)
            path.addLine(to: topRight)
            path.addLine(to: bottomRight)
            path.addLine(to: bottomLeft)
            path.closeSubpath()
        }
        .stroke(
            OPSStyle.Colors.primaryAccent,
            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
        )
    }
}
