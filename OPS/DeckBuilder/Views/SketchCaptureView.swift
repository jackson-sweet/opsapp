// OPS/OPS/DeckBuilder/Views/SketchCaptureView.swift

import SwiftUI
import VisionKit
import UIKit

// MARK: - DocumentScannerView (VisionKit Wrapper)

/// Wraps Apple's `VNDocumentCameraViewController` for capturing a hand-drawn sketch.
/// Provides auto-crop and perspective correction via the document scanner.
/// Returns the first scanned page only — deck sketches are single-page.
struct SketchDocumentScannerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: SketchDocumentScannerView

        init(_ parent: SketchDocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // Take only the first page — a deck sketch is a single sheet
            guard scan.pageCount > 0 else {
                parent.onCancel()
                return
            }
            let image = scan.imageOfPage(at: 0)
            parent.onCapture(image)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.onError(error)
        }
    }
}

// MARK: - ScanProgressBar

/// Custom progress bar matching OPS design system.
/// Background: cardBackground. Fill: primaryAccent. Animates width based on progress.
private struct ScanProgressBar: View {
    let progress: Double

    private let barHeight: CGFloat = 6
    private let barCornerRadius: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: barCornerRadius)
                    .fill(OPSStyle.Colors.cardBackground)
                    .frame(height: barHeight)

                // Fill
                RoundedRectangle(cornerRadius: barCornerRadius)
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(
                        width: max(0, geometry.size.width * CGFloat(min(max(progress, 0), 1))),
                        height: barHeight
                    )
                    .animation(OPSStyle.Animation.standard, value: progress)
            }
        }
        .frame(height: barHeight)
    }
}

// MARK: - SketchCaptureView

/// The main capture view for the scan-paper-sketch feature.
/// Presented as `.fullScreenCover` from the creation picker.
///
/// Flow:
/// 1. Opens the VisionKit document scanner (auto-crop + perspective correction)
/// 2. On capture, runs `SketchScanPipeline` and shows processing progress
/// 3. On success, presents `SketchCleanupView` for edge cleanup and dimension review
/// 4. On failure, shows retry/cancel options
struct SketchCaptureView: View {
    // MARK: - Properties

    let projectId: String?
    let companyId: String
    let userId: String?
    let onComplete: (SketchScanResult) -> Void

    // MARK: - State

    @StateObject private var pipeline = SketchScanPipeline()
    @State private var capturedImage: UIImage?
    @State private var showingScanner = true
    @State private var showingCleanup = false
    @State private var scannerError: String?
    @Environment(\.dismiss) private var dismiss

    // MARK: - Haptic Generators

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let errorNotification = UINotificationFeedbackGenerator()

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            if showingScanner && capturedImage == nil {
                scannerLayer
            } else if capturedImage != nil && pipeline.stage != .complete && pipeline.stage != .failed {
                processingLayer
            } else if pipeline.stage == .failed {
                errorLayer
            } else if pipeline.stage == .complete && pipeline.result != nil {
                // Invisible placeholder — cleanup view presented via fullScreenCover
                Color.clear
            }
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            showingScanner = false
            Task {
                await pipeline.process(image: image)
            }
        }
        .onChange(of: pipeline.stage) { oldValue, newValue in
            handleStageChange(from: oldValue, to: newValue)
        }
        .fullScreenCover(isPresented: $showingCleanup) {
            if let scanResult = pipeline.result {
                SketchCleanupView(
                    scanResult: scanResult,
                    projectId: projectId,
                    companyId: companyId,
                    userId: userId
                ) { finalResult in
                    showingCleanup = false
                    onComplete(finalResult)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Scanner Layer

    /// The VisionKit document camera — full screen.
    private var scannerLayer: some View {
        SketchDocumentScannerView(
            onCapture: { image in
                capturedImage = image
            },
            onCancel: {
                dismiss()
            },
            onError: { error in
                scannerError = error.localizedDescription
                self.pipeline.error = error.localizedDescription
                self.pipeline.stage = .failed
            }
        )
        .ignoresSafeArea()
    }

    // MARK: - Processing Layer

    /// Shows a thumbnail of the captured sketch at reduced opacity with a centered progress card.
    private var processingLayer: some View {
        ZStack {
            // Captured image thumbnail at 30% opacity as background context
            if let capturedImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.3)
                    .ignoresSafeArea()
            }

            // Dark overlay for readability
            OPSStyle.Colors.background.opacity(0.6)
                .ignoresSafeArea()

            // Progress card
            VStack(spacing: OPSStyle.Layout.spacing4) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    .scaleEffect(1.5)

                Text(pipeline.stage.rawValue)
                    .font(OPSStyle.Typography.heading)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .animation(.none, value: pipeline.stage)

                ScanProgressBar(progress: pipeline.progress)
                    .frame(maxWidth: 240)

                Text("\(Int(pipeline.progress * 100))%")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing5)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(OPSStyle.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            )
        }
    }

    // MARK: - Error Layer

    /// Shows the error message with retry and cancel buttons.
    private var errorLayer: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Spacer()

            // Error icon
            Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                .font(.system(size: 40))
                .foregroundColor(OPSStyle.Colors.errorStatus)

            // Error title
            Text("Scan Failed")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)

            // Error detail
            Text(pipeline.error ?? scannerError ?? "An unknown error occurred.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing5)

            Spacer()

            // Action buttons
            VStack(spacing: OPSStyle.Layout.spacing2) {
                // Try Again
                Button {
                    resetForRetry()
                } label: {
                    Text("Try Again")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .fill(OPSStyle.Colors.primaryAccent)
                        )
                }

                // Cancel
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
    }

    // MARK: - Stage Change Handling

    /// Fires haptic feedback on each pipeline stage transition.
    /// Light impact for intermediate stages, medium impact for completion, error notification for failure.
    private func handleStageChange(from oldValue: SketchScanPipeline.ScanStage, to newValue: SketchScanPipeline.ScanStage) {
        switch newValue {
        case .complete:
            mediumImpact.impactOccurred()
            // Auto-present cleanup view on successful completion
            if pipeline.result != nil {
                showingCleanup = true
            }
        case .failed:
            errorNotification.notificationOccurred(.error)
        case .idle:
            break
        default:
            // Light impact on each intermediate stage change
            if oldValue != newValue {
                lightImpact.impactOccurred()
            }
        }
    }

    // MARK: - Reset

    /// Resets all state to re-enter the document scanner.
    private func resetForRetry() {
        capturedImage = nil
        scannerError = nil
        pipeline.stage = .idle
        pipeline.progress = 0.0
        pipeline.result = nil
        pipeline.error = nil
        showingScanner = true
        showingCleanup = false
    }
}
