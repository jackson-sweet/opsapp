// OPS/OPS/DeckBuilder/AR/ARHeightViewModel.swift

import Foundation
import DeckKit
import SwiftUI
import UIKit
import simd

@MainActor
class ARHeightViewModel: ObservableObject {

    // MARK: - State

    enum HeightStage {
        case waitingForPoint1   // "Place deck surface point"
        case waitingForPoint2   // "Place ground point"
        case measured           // "Confirm measurement"
    }

    @Published var stage: HeightStage = .waitingForPoint1
    @Published var point1: SIMD3<Float>?     // deck surface point
    @Published var point2: SIMD3<Float>?     // ground point
    @Published var heightInches: Double?
    @Published var accuracyPercent: Double?
    @Published var isPlaneDetected: Bool = false
    @Published var currentCrosshairPosition: SIMD3<Float>?
    @Published var liveHeightLabel: String = ""
    @Published var showPlaneTimeoutAlert: Bool = false
    private var planeDetectionTask: Task<Void, Never>?

    // MARK: - Haptics

    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let successNotification = UINotificationFeedbackGenerator()

    init() {
        mediumImpact.prepare()
        successNotification.prepare()
        startPlaneDetectionTimeout()
    }

    // MARK: - Plane Detection Timeout

    func startPlaneDetectionTimeout() {
        planeDetectionTask?.cancel()
        showPlaneTimeoutAlert = false
        planeDetectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self, !self.isPlaneDetected else { return }
            self.showPlaneTimeoutAlert = true
        }
    }

    func cancelPlaneDetectionTimeout() {
        planeDetectionTask?.cancel()
        planeDetectionTask = nil
    }

    // MARK: - Point Placement

    func placePoint1(at position: SIMD3<Float>) {
        point1 = position
        stage = .waitingForPoint2
        mediumImpact.impactOccurred()
    }

    func placePoint2(at position: SIMD3<Float>) {
        point2 = position

        guard let p1 = point1 else { return }
        let heightMeters = Double(abs(p1.y - position.y))
        heightInches = ARCoordinateConverter.calculateElevation(deckPointY: Double(p1.y), groundPointY: Double(position.y))
        accuracyPercent = ARCoordinateConverter.heightAccuracy(heightMeters: heightMeters)

        stage = .measured
        successNotification.notificationOccurred(.success)
    }

    // MARK: - Crosshair Update

    func updateCrosshairPosition(_ position: SIMD3<Float>) {
        currentCrosshairPosition = position

        // Show live height from Point 1 to current crosshair Y
        if stage == .waitingForPoint2, let p1 = point1 {
            let heightMeters = Double(abs(p1.y - position.y))
            let inches = heightMeters * 39.3701
            let accuracy = AccuracyModel.estimateAccuracy(distanceMeters: heightMeters)
            let dimLabel = DimensionEngine.formatImperial(inches)
            let accLabel = AccuracyModel.formatAccuracy(dimensionInches: inches, accuracyPercent: accuracy)
            liveHeightLabel = "\(dimLabel) \(accLabel)"
        } else {
            liveHeightLabel = ""
        }
    }

    // MARK: - Reset

    func reset() {
        point1 = nil
        point2 = nil
        heightInches = nil
        accuracyPercent = nil
        stage = .waitingForPoint1
        liveHeightLabel = ""
    }
}
