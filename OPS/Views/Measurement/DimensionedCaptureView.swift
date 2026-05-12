//
//  DimensionedCaptureView.swift
//  OPS
//
//  Phase D — the live AR capture screen for the LiDAR Dimensioned Photo
//  Capture feature. Spec: §5.1 of
//  ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md
//
//  Responsibilities:
//    1. Own a `LiDARCaptureCoordinator`, call `startLiveAim()` on appear,
//       observe its `@Published state` to drive chrome.
//    2. Render the live AR feed via `ARCaptureViewRepresentable` (binds to
//       `coordinator.arSession` — see that file's notes on why we don't use
//       RealityKit `ARView` directly).
//    3. Drive the helper text state machine, reticle pulse, level indicator,
//       capability chip, and shutter flash per spec §5.1 + §5.3.
//    4. Handle camera permission, AR-unsupported, error toasts, and dismissal.
//
//  Phase E will replace `DimensionedAnnotationView` with the real annotation
//  surface. Phase G wires the entry point on `ProjectActionBar`. This view
//  has no parent-imposed dependencies — it is presented modally by the
//  upstream caller.
//

import SwiftUI
import AVFoundation
import ARKit

public struct DimensionedCaptureView: View {

    /// Optional injection point for previews and unit tests. Production
    /// callers omit this — the view builds a fresh coordinator on first appear.
    private let injectedCoordinator: LiDARCaptureCoordinator?

    @StateObject private var coordinatorBox = CoordinatorBox()
    @State private var availability: ARAvailability = .checking
    @State private var meshVisible = false
    @State private var shutterFlash: Double = 0
    @State private var helperStateOverride: HelperTextOverlay.HelperState?
    @State private var errorToast: ErrorToast?
    @State private var levelIndicatorEnabled = true
    @State private var pendingAnnotation: CapturedAssets?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(coordinator: LiDARCaptureCoordinator? = nil) {
        self.injectedCoordinator = coordinator
    }

    public var body: some View {
        ZStack {
            // Canvas — never `Color.black`, always the OPS background token per spec §5.1.
            OPSStyle.Colors.background
                .ignoresSafeArea()

            switch availability {
            case .checking:
                ProgressView()
                    .tint(OPSStyle.Colors.text)

            case .denied:
                permissionGate

            case .unsupported:
                unsupportedGate

            case .ready:
                if let coordinator = coordinatorBox.coordinator {
                    captureScene(coordinator: coordinator)
                }
            }
        }
        .statusBarHidden(true)
        .gesture(swipeDownToDismiss)
        .task { await prepare() }
        .onDisappear {
            coordinatorBox.coordinator?.reset()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { pendingAnnotation != nil },
                set: { presented in if !presented { pendingAnnotation = nil } }
            )
        ) {
            // Phase E will replace this stub with the real annotation view.
            // Dismissing the cover returns to the capture view; dismissing the
            // capture view (the parent of this cover) closes the whole modal.
            if let assets = pendingAnnotation {
                DimensionedAnnotationView(assets: assets)
            }
        }
    }

    // MARK: - Permission + capability gates

    @ViewBuilder
    private var permissionGate: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(OPSStyle.Colors.text2)

            VStack(spacing: 8) {
                Text("// CAMERA OFF")
                    .font(.buttonLabel)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                Text("Enable camera access in Settings to capture dimensioned photos.")
                    .font(.smallBody)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("OPEN SETTINGS")
                    .font(.buttonLabel)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundColor(OPSStyle.Colors.text)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.opsAccent)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
            }
            .frame(minHeight: 60) // field-first per ops-ios/CLAUDE.md

            Button("DISMISS") { dismiss() }
                .font(.buttonLabel)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundColor(OPSStyle.Colors.text2)
        }
    }

    @ViewBuilder
    private var unsupportedGate: some View {
        VStack(spacing: 24) {
            Image(systemName: "arkit")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(OPSStyle.Colors.text2)
            Text("// NO DEPTH")
                .font(.buttonLabel)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text)
            Text("This device cannot run dimensioned capture. AR support is required.")
                .font(.smallBody)
                .foregroundColor(OPSStyle.Colors.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("DISMISS") { dismiss() }
                .font(.buttonLabel)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(OPSStyle.Colors.surfaceActive)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                .frame(minHeight: 60)
        }
    }

    // MARK: - The actual capture surface

    @ViewBuilder
    private func captureScene(coordinator: LiDARCaptureCoordinator) -> some View {
        ZStack {
            ARCaptureViewRepresentable(coordinator: coordinator, meshVisible: $meshVisible)
                .ignoresSafeArea()

            // Center overlays — reticle pulses only on opening lock, level
            // hairline floats through the middle of the viewfinder.
            ZStack {
                LevelIndicatorOverlay(isEnabled: levelIndicatorEnabled)
                    .ignoresSafeArea(edges: .top) // hairline can extend full-width
                ReticleOverlay(isLocked: coordinator.state == .openingLocked)
            }

            // Chrome
            VStack(spacing: 0) {
                topBar(coordinator: coordinator)
                Spacer()
                helperRow(coordinator: coordinator)
                    .padding(.bottom, 24)
                bottomBar(coordinator: coordinator)
            }

            // Shutter flash — white overlay, two-stage ramp per §5.3 row 3.
            Color.white
                .opacity(shutterFlash)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            // Error toast (auto-dismisses)
            if let toast = errorToast {
                VStack {
                    errorToastView(toast)
                        .padding(.top, 12)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onChange(of: coordinator.state) { _, newState in
            handleStateChange(newState)
        }
    }

    // MARK: - Top bar

    @ViewBuilder
    private func topBar(coordinator: LiDARCaptureCoordinator) -> some View {
        HStack {
            // 44×44 hit area for the title is overkill — keep it inline.
            Text("MEASURE")
                .font(.buttonLabel)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundColor(OPSStyle.Colors.text)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, 8)
    }

    // MARK: - Helper text row + accuracy chip

    @ViewBuilder
    private func helperRow(coordinator: LiDARCaptureCoordinator) -> some View {
        let derived = helperStateOverride ?? helperState(for: coordinator.state)
        HelperTextOverlay(state: derived)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func helperState(for state: LiDARCaptureCoordinator.CaptureState) -> HelperTextOverlay.HelperState {
        switch state {
        case .idle, .warmingUp:    return .initializing
        case .ready:               return .aimAtOpening
        case .searching:           return .searching
        case .wallDetected:        return .wallDetected
        case .openingLocked:       return .openingLocked
        case .capturing:           return .openingLocked   // ride through capture on last good copy
        case .captured:            return .capturedFlash
        case .failed:              return .aimAtOpening
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private func bottomBar(coordinator: LiDARCaptureCoordinator) -> some View {
        HStack(alignment: .center) {
            torchToggle()

            Spacer()

            ShutterButton(
                action: { Task { await fireShutter(coordinator: coordinator) } },
                isEnabled: shutterEnabled(for: coordinator.state)
            )

            Spacer()

            CapabilityChip(capability: coordinator.capability)
                .frame(maxWidth: 100, alignment: .center)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    @State private var torchOn = false

    @ViewBuilder
    private func torchToggle() -> some View {
        Button {
            toggleTorch()
        } label: {
            Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(torchOn ? OPSStyle.Colors.tan : OPSStyle.Colors.text2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Torch")
        .accessibilityValue(torchOn ? "on" : "off")
    }

    private func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            let next = !torchOn
            try device.setTorchModeOn(level: next ? AVCaptureDevice.maxAvailableTorchLevel : 0.0)
            if !next { device.torchMode = .off }
            device.unlockForConfiguration()
            torchOn = next
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            // Torch failure is non-fatal — surface a brief toast so the user
            // knows the affordance didn't work and isn't left tapping it.
            showError(toast: ErrorToast(copy: "// TORCH UNAVAILABLE"))
        }
    }

    // MARK: - Shutter

    private func shutterEnabled(for state: LiDARCaptureCoordinator.CaptureState) -> Bool {
        switch state {
        case .ready, .wallDetected, .openingLocked: return true
        default: return false
        }
    }

    private func fireShutter(coordinator: LiDARCaptureCoordinator) async {
        // Two-stage flash — 80 ms ramp up, medium impact haptic at peak, 160 ms ramp down.
        // Reduced motion: single 150 ms opacity transition (§5.3 row 3 fallback).
        if reduceMotion {
            withAnimation(.linear(duration: 0.15)) { shutterFlash = 1.0 }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.linear(duration: 0.15)) { shutterFlash = 0.0 }
        } else {
            withAnimation(.opsCurve200) { shutterFlash = 1.0 }
            // Haptic at flash peak — the §5.3 row 3 "Medium impact at flash peak".
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.opsCurve200) { shutterFlash = 0.0 }
        }

        await coordinator.capture()
        // .captured / .failed transitions are picked up in `handleStateChange`.
    }

    // MARK: - State transition side effects

    private func handleStateChange(_ state: LiDARCaptureCoordinator.CaptureState) {
        switch state {
        case .captured(let assets):
            // Show post-capture flash chip for 1.5 s, then push to the Phase E
            // stub annotation view via `.fullScreenCover` (see body). Phase G
            // will move the navigation up to the entry point on
            // `ProjectActionBar` — for now the flow is self-contained so the
            // capture pipeline can be exercised end-to-end.
            withAnimation(.opsCurve200) {
                helperStateOverride = .capturedFlash
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { pendingAnnotation = assets }
            }
        case .failed(let error):
            showError(toast: ErrorToast.from(captureError: error))
        default:
            // Clear any sticky override once we leave .captured.
            if helperStateOverride == .capturedFlash {
                helperStateOverride = nil
            }
        }
    }

    // MARK: - Errors

    @ViewBuilder
    private func errorToastView(_ toast: ErrorToast) -> some View {
        HStack(spacing: 8) {
            Text(toast.copy)
                .font(.panelTitle)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.rose)
            if toast.includesOpenSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("OPEN SETTINGS")
                        .font(.panelTitle)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(OPSStyle.Colors.opsAccent.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OPSStyle.Colors.glassDenseApprox)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .strokeBorder(OPSStyle.Colors.roseLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
        .shadow(color: Color.black.opacity(0.5), radius: 4, y: 2)
        .onTapGesture { withAnimation(.opsCurve200) { errorToast = nil } }
    }

    private func showError(toast: ErrorToast) {
        withAnimation(.opsCurve200) { errorToast = toast }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                withAnimation(.opsCurve200) { errorToast = nil }
            }
        }
    }

    // MARK: - Swipe-down dismissal

    private var swipeDownToDismiss: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                // Apple Measure convention — vertical drag > 80 pt dismisses.
                if value.translation.height > 80 && abs(value.translation.width) < 80 {
                    dismiss()
                }
            }
    }

    // MARK: - Bootstrapping

    private func prepare() async {
        // 1. Camera permission
        let permission = AVCaptureDevice.authorizationStatus(for: .video)
        switch permission {
        case .denied, .restricted:
            availability = .denied
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { availability = .denied; return }
        default:
            break
        }

        // 2. AR support
        guard ARWorldTrackingConfiguration.isSupported else {
            availability = .unsupported
            return
        }

        // 3. Coordinator — either the injected one (tests/previews) or fresh.
        let coordinator = injectedCoordinator ?? LiDARCaptureCoordinator()

        // 4. Capability gate — `.noDepth` short-circuits to the unsupported screen
        //    with copy that explains why (matches spec §3.8 fallback ladder).
        if coordinator.capability == .noDepth {
            availability = .unsupported
            return
        }

        coordinatorBox.coordinator = coordinator
        availability = .ready

        // 5. Kick off the live-aim session — coordinator handles idempotency.
        coordinator.startLiveAim()
    }
}

// MARK: - Helper types

extension DimensionedCaptureView {
    enum ARAvailability {
        case checking, ready, denied, unsupported
    }

    struct ErrorToast: Equatable {
        let copy: String
        var includesOpenSettings: Bool = false

        static func from(captureError: LiDARCaptureCoordinator.CaptureError) -> ErrorToast {
            switch captureError {
            case .capabilityInsufficient:
                return ErrorToast(copy: "// NO DEPTH · DEVICE NOT SUPPORTED")
            case .cameraPermissionDenied:
                return ErrorToast(copy: "// CAMERA OFF · ENABLE IN SETTINGS", includesOpenSettings: true)
            case .arSessionFailed:
                return ErrorToast(copy: "// TRACKING LOST · HOLD STEADY")
            case .avCaptureFailed:
                return ErrorToast(copy: "// CAPTURE FAILED · TRY AGAIN")
            case .persistenceFailed:
                return ErrorToast(copy: "// SAVE FAILED · RETRY")
            case .noActiveSession:
                return ErrorToast(copy: "// SESSION INACTIVE · REOPEN")
            }
        }
    }
}

/// Boxes the coordinator so we can keep it as an `ObservableObject` without
/// recreating it across SwiftUI updates. The `prepare()` task assigns once
/// the permission + capability gates pass.
@MainActor
final class CoordinatorBox: ObservableObject {
    @Published var coordinator: LiDARCaptureCoordinator?
}
