// OPS/OPS/DeckBuilder/Views/ImageAdjustmentView.swift
//
// Brightness / contrast adjustment step inserted between perspective
// correction and the scan pipeline. Phone cameras under fluorescent shop
// lights or with shadows produce washed-out or low-contrast captures that
// the edge-detection pipeline mishandles. Letting the user dial brightness
// and contrast salvages many bad captures. Bug b03444db (a).

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct ImageAdjustmentView: View {
    let image: UIImage
    let onApply: (UIImage) -> Void
    let onCancel: () -> Void

    /// CIColorControls.brightness — bias added to all channels. 0 = identity.
    @State private var brightness: Double = 0
    /// CIColorControls.contrast — multiplied around mid-grey. 1 = identity.
    @State private var contrast: Double = 1
    @State private var previewImage: UIImage?
    @State private var isApplying: Bool = false

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    /// CIContext re-used across slider drags. Reusing the context avoids
    /// re-initialising the GPU pipeline on every value change — a fresh
    /// context per drag tick produced visible stutters on older devices.
    private static let renderContext = CIContext()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            OPSScreenHeader(
                "Adjust Tone",
                leading: {
                    Button {
                        lightImpact.impactOccurred()
                        onCancel()
                    } label: {
                        Text("Back")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            )
            .padding(.top, OPSStyle.Layout.spacing4)
            .padding(.bottom, OPSStyle.Layout.spacing3)

            Text("Boost contrast to make the deck lines stand out from the paper. Brighten faded photos so the scan can see the edges.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
                .padding(.bottom, OPSStyle.Layout.spacing3)

            // Live preview
            if let preview = previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OPSStyle.Colors.cardBackground)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OPSStyle.Colors.cardBackground)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
            }

            // Sliders
            VStack(spacing: OPSStyle.Layout.spacing3) {
                sliderRow(
                    label: "BRIGHTNESS",
                    value: $brightness,
                    range: -0.5...0.5,
                    formatted: percentageBrightness
                )
                sliderRow(
                    label: "CONTRAST",
                    value: $contrast,
                    range: 0.5...2.0,
                    formatted: percentageContrast
                )

                Button {
                    lightImpact.impactOccurred()
                    brightness = 0
                    contrast = 1
                    refreshPreview()
                } label: {
                    Text("Reset")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.top, OPSStyle.Layout.spacing4)

            Spacer(minLength: OPSStyle.Layout.spacing4)

            // Apply
            Button {
                lightImpact.impactOccurred()
                applyAdjustment()
            } label: {
                if isApplying {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.buttonText))
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                } else {
                    Text("Use This Image")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                }
            }
            .disabled(isApplying)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .fill(OPSStyle.Colors.primaryAccent.opacity(isApplying ? 0.5 : 1.0))
            )
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .onAppear {
            // Pre-warm the preview so the user sees the image immediately on
            // open instead of waiting until they touch a slider.
            refreshPreview()
        }
        .onChange(of: brightness) { _, _ in refreshPreview() }
        .onChange(of: contrast) { _, _ in refreshPreview() }
    }

    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        formatted: (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack {
                Text(label)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text(formatted(value.wrappedValue))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            Slider(value: value, in: range)
                .tint(OPSStyle.Colors.primaryAccent)
        }
    }

    // MARK: - Preview

    /// Re-render the preview at a downscaled size so slider drags stay
    /// responsive even on older devices. The Apply step uses the full-size
    /// image so the scan pipeline sees the original resolution.
    private func refreshPreview() {
        let target = scaledImage(image, maxDimension: 1024)
        guard let cgImage = target.cgImage else { return }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIColorControls") else { return }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        // Saturation untouched (1.0) — line drawings rarely benefit from desat.
        filter.setValue(1.0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage,
              let cg = Self.renderContext.createCGImage(output, from: output.extent) else { return }
        previewImage = UIImage(cgImage: cg, scale: target.scale, orientation: target.imageOrientation)
    }

    // MARK: - Apply Adjustment

    private func applyAdjustment() {
        // If the user left both sliders at identity, skip the round-trip
        // through CIFilter — saves time and keeps the original byte-for-byte.
        if abs(brightness) < 0.001 && abs(contrast - 1.0) < 0.001 {
            mediumImpact.impactOccurred()
            onApply(image)
            return
        }
        isApplying = true
        let b = brightness
        let c = contrast
        let src = image
        Task.detached(priority: .userInitiated) {
            let adjusted = applyColorControls(image: src, brightness: b, contrast: c) ?? src
            await MainActor.run {
                isApplying = false
                mediumImpact.impactOccurred()
                onApply(adjusted)
            }
        }
    }

    private nonisolated func applyColorControls(image: UIImage, brightness: Double, contrast: Double) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        filter.setValue(1.0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Helpers

    /// Downscale an image so the largest side is `maxDimension` pixels. Used
    /// only for the live preview; the Apply step keeps the original
    /// resolution so the scan pipeline gets the full image quality.
    private func scaledImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return image }
        let ratio = maxDimension / largest
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func percentageBrightness(_ value: Double) -> String {
        let pct = Int(value * 200.0)  // -0.5...0.5 maps to -100%...100%
        return pct >= 0 ? "+\(pct)%" : "\(pct)%"
    }

    private func percentageContrast(_ value: Double) -> String {
        let pct = Int((value - 1.0) * 100.0)
        return pct >= 0 ? "+\(pct)%" : "\(pct)%"
    }
}
