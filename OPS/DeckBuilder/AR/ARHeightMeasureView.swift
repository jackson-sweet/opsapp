// OPS/OPS/DeckBuilder/AR/ARHeightMeasureView.swift

import SwiftUI
import ARKit
import RealityKit
import simd

struct ARHeightMeasureView: View {
    @StateObject private var viewModel = ARHeightViewModel()
    @Environment(\.dismiss) private var dismiss
    let onComplete: (_ heightInches: Double, _ accuracyPercent: Double) -> Void

    var body: some View {
        ZStack {
            ARHeightViewContainer(viewModel: viewModel)
                .ignoresSafeArea()

            VStack {
                heightTopBar
                Spacer()
                heightCrosshair
                Spacer()
                heightBottomControls
            }
        }
        .statusBarHidden(true)
    }

    // MARK: - Top Bar

    private var heightTopBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }

            Spacer()

            Text("Measure Height")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            // Reset button
            if viewModel.stage != .waitingForPoint1 {
                Button {
                    viewModel.reset()
                } label: {
                    Text("Reset")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing4)
    }

    // MARK: - Crosshair + Status

    private var heightCrosshair: some View {
        VStack(spacing: 12) {
            // Point 1 status
            pointStatus(
                label: "Point 1: Deck Surface",
                isPlaced: viewModel.point1 != nil,
                icon: viewModel.point1 != nil ? "checkmark.circle.fill" : "circle"
            )

            // Live height measurement
            if !viewModel.liveHeightLabel.isEmpty {
                Text(viewModel.liveHeightLabel)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }

            // Crosshair
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 2)

            // Point 2 status
            pointStatus(
                label: "Point 2: Ground Level",
                isPlaced: viewModel.point2 != nil,
                icon: viewModel.point2 != nil ? "checkmark.circle.fill" : "circle"
            )

            // Scanning indicator
            if !viewModel.isPlaneDetected {
                Text("Scanning surface...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    private func pointStatus(label: String, isPlaced: Bool, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(isPlaced ? OPSStyle.Colors.successStatus : OPSStyle.Colors.secondaryText)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isPlaced ? OPSStyle.Colors.successStatus : .white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Bottom Controls

    private var heightBottomControls: some View {
        VStack(spacing: 12) {
            // Final measurement display
            if viewModel.stage == .measured,
               let height = viewModel.heightInches,
               let accuracy = viewModel.accuracyPercent {
                let label = DimensionEngine.formatImperial(height)
                let accLabel = AccuracyModel.formatAccuracy(dimensionInches: height, accuracyPercent: accuracy)
                VStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(accLabel)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
                .padding(16)
                .background(Color.black.opacity(0.5))
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            }

            // Action button
            heightActionButton
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing5)
    }

    private var heightActionButton: some View {
        Button {
            switch viewModel.stage {
            case .waitingForPoint1:
                if let pos = viewModel.currentCrosshairPosition {
                    viewModel.placePoint1(at: pos)
                }
            case .waitingForPoint2:
                if let pos = viewModel.currentCrosshairPosition {
                    viewModel.placePoint2(at: pos)
                }
            case .measured:
                if let height = viewModel.heightInches, let accuracy = viewModel.accuracyPercent {
                    onComplete(height, accuracy)
                }
            }
        } label: {
            Text(heightButtonTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(minWidth: 200)
                .padding(.vertical, 16)
                .background(heightButtonColor)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        }
        .disabled(!viewModel.isPlaneDetected && viewModel.stage != .measured)
    }

    private var heightButtonTitle: String {
        switch viewModel.stage {
        case .waitingForPoint1: return "Place Point 1 (Deck)"
        case .waitingForPoint2: return "Place Point 2 (Ground)"
        case .measured: return "Confirm Height"
        }
    }

    private var heightButtonColor: Color {
        viewModel.stage == .measured ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent
    }
}

// MARK: - AR Height View Container

private struct ARHeightViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARHeightViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        config.isAutoFocusEnabled = true
        config.worldAlignment = .gravity

        arView.session.run(config)
        arView.session.delegate = context.coordinator
        context.coordinator.arView = arView

        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.viewModel = viewModel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, ARSessionDelegate {
        var viewModel: ARHeightViewModel
        weak var arView: ARView?

        init(viewModel: ARHeightViewModel) {
            self.viewModel = viewModel
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arView = arView else { return }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)

            // For height measurement, we accept any raycast target — we care about Y position
            if let query = arView.makeRaycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: .any) {
                if let hit = session.raycast(query).first {
                    let position = SIMD3<Float>(
                        hit.worldTransform.columns.3.x,
                        hit.worldTransform.columns.3.y,
                        hit.worldTransform.columns.3.z
                    )
                    Task { @MainActor in
                        self.viewModel.isPlaneDetected = true
                        self.viewModel.updateCrosshairPosition(position)
                    }
                    return
                }
            }

            // Fallback to estimated plane
            if let query = arView.makeRaycastQuery(from: center, allowing: .estimatedPlane, alignment: .any) {
                if let hit = session.raycast(query).first {
                    let position = SIMD3<Float>(
                        hit.worldTransform.columns.3.x,
                        hit.worldTransform.columns.3.y,
                        hit.worldTransform.columns.3.z
                    )
                    Task { @MainActor in
                        self.viewModel.isPlaneDetected = true
                        self.viewModel.updateCrosshairPosition(position)
                    }
                    return
                }
            }

            Task { @MainActor in
                self.viewModel.isPlaneDetected = false
            }
        }
    }
}
