// OPS/OPS/DeckBuilder/AR/ARVisualizationViewModel.swift

import Foundation
import DeckKit
import ARKit
import SceneKit
import SwiftUI

@MainActor
class ARVisualizationViewModel: ObservableObject {

    // MARK: - Placement State

    enum PlacementState: Equatable {
        case scanning       // waiting for horizontal plane detection
        case previewing     // ghost deck following camera aim on detected plane
        case placed         // deck anchored at a fixed position on ground
    }

    // MARK: - Published State

    @Published var placementState: PlacementState = .scanning
    @Published var statusMessage: String = "Scanning surface..."
    @Published var showDragHint: Bool = false
    @Published var screenshotImage: UIImage?
    @Published var showingShareSheet: Bool = false
    @Published var showPlaneTimeoutAlert: Bool = false
    private var planeDetectionTask: Task<Void, Never>?

    // MARK: - Data

    let drawingData: DeckDrawingData

    // AR state managed by the view's coordinator (not published)
    var deckNode: SCNNode?
    var deckAnchor: ARAnchor?
    var previewNode: SCNNode?

    // MARK: - Init

    init(drawingData: DeckDrawingData) {
        self.drawingData = drawingData
        startPlaneDetectionTimeout()
    }

    // MARK: - Plane Detection Timeout

    func startPlaneDetectionTimeout() {
        planeDetectionTask?.cancel()
        showPlaneTimeoutAlert = false
        planeDetectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self, self.placementState == .scanning else { return }
            self.showPlaneTimeoutAlert = true
        }
    }

    func cancelPlaneDetectionTimeout() {
        planeDetectionTask?.cancel()
        planeDetectionTask = nil
    }

    // MARK: - State Transitions

    func onPlaneDetected() {
        guard placementState == .scanning else { return }
        cancelPlaneDetectionTimeout()
        placementState = .previewing
        statusMessage = "Tap to place your deck"
    }

    func onTapToPlace(transform: simd_float4x4) {
        guard placementState == .previewing else { return }
        placementState = .placed
        statusMessage = "Placed \u{2713} \u{2014} walk around to explore"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard placementState == .placed else { return }
            statusMessage = ""
            showDragHint = true
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            showDragHint = false
        }
    }

    func onResetPosition() {
        placementState = .previewing
        statusMessage = "Tap to place your deck"
        deckAnchor = nil
        deckNode = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func onDragStart() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func onRotateStart() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func onScreenshotCaptured(_ image: UIImage) {
        screenshotImage = image
        showingShareSheet = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
