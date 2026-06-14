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
import UIKit
import SwiftData

public struct DimensionedCaptureView: View {

    /// Distinguishes a fresh capture from a re-entry triggered by the
    /// annotation view's calibrate flow (spec §5.2 — round-trip preserves
    /// existing measurements; `.calibration` re-frames the reference object).
    public enum CaptureMode: Equatable {
        case normal
        case calibration
    }

    /// Optional injection point for previews and unit tests. Production
    /// callers omit this — the view builds a fresh coordinator on first appear.
    private let injectedCoordinator: LiDARCaptureCoordinator?

    // Project context — flows in from `ProjectActionBar`/`MeasureActionButton`
    // and is captured by the save closure when dispatching to Phase F's
    // `DimensionedPhotoSyncManager`. Defaults preserve back-compat with the
    // Phase D preview path that injects a coordinator only.
    public let projectId: String
    public let projectName: String
    public let companyId: String
    public let userId: String

    // Parent-injected closures for post-save routing. The capture view owns
    // the sync call and calibration continuity; the parent owns dismissal +
    // error UX so the action bar can route the user back to the project on
    // success.
    let onSavedSuccessfully: (PhotoAnnotation) -> Void
    let onError: (Error) -> Void

    @StateObject private var coordinatorBox = CoordinatorBox()
    @State private var availability: ARAvailability = .checking
    @State private var meshVisible = false
    @State private var shutterFlash: Double = 0
    @State private var helperStateOverride: HelperTextOverlay.HelperState?
    @State private var errorToast: ErrorToast?
    @State private var levelIndicatorEnabled = true
    @State private var activeMode: CaptureMode
    @State private var pendingAnnotation: AnnotationPresentation?
    @State private var calibrationSession: DimensionedCalibrationSession?
    @State private var saveInFlight = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        coordinator: LiDARCaptureCoordinator? = nil,
        mode: CaptureMode = .normal,
        projectId: String = "",
        projectName: String = "",
        companyId: String = "",
        userId: String = "",
        onSavedSuccessfully: @escaping (PhotoAnnotation) -> Void = { _ in },
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.injectedCoordinator = coordinator
        self._activeMode = State(initialValue: mode)
        self.projectId = projectId
        self.projectName = projectName
        self.companyId = companyId
        self.userId = userId
        self.onSavedSuccessfully = onSavedSuccessfully
        self.onError = onError
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
        .interactiveDismissDisabled(
            activeMode == .calibration || pendingAnnotation != nil || saveInFlight
        )
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
            // Phase E annotation view — Phase G wires the save + calibrate
            // closures to real implementations.
            //
            // onSaveToProject  → DimensionedPhotoSyncManager.sync(...).
            //                    Success persists the returned annotation locally,
            //                    then dismisses. Retryable failures persist the
            //                    queued local stub and leave annotation open.
            // onRequestCalibrate → snapshot dimensions, return to the same
            //                      capture view in calibration mode, then
            //                      reopen this annotation on cancel/success.
            if let presentation = pendingAnnotation {
                let handoff = presentation.handoff
                let assets = handoff.assets
                DimensionedAnnotationView(
                    assets: assets,
                    preloadedPhoto: nil,
                    preloadedDepthMap: handoff.preloadedDepthMap,
                    anchors: handoff.anchors,
                    detectedOpenings: handoff.detectedOpenings,
                    initialCalibration: presentation.initialCalibration,
                    capability: handoff.capability,
                    coplanarOnly: presentation.coplanarOnly,
                    existingDimensions: presentation.existingDimensions,
                    initialHasUnsavedChanges: presentation.hasUnsavedChanges,
                    onRequestCalibrate: { dimensions, hasUnsavedChanges in
                        calibrationSession = DimensionedCalibrationSession(
                            originalHandoff: handoff,
                            originalDimensions: dimensions,
                            originalCoplanarOnly: presentation.coplanarOnly,
                            originalHasUnsavedChanges: hasUnsavedChanges
                        )
                        pendingAnnotation = nil
                        enterCalibrationMode()
                    },
                    onSaveToProject: { dimensions in
                        try await saveFromAnnotation(assets: assets, dimensions: dimensions)
                    },
                    onDismiss: {
                        pendingAnnotation = nil
                        dismiss()
                    }
                )
            }
        }
    }

    // MARK: - Permission + capability gates

    @ViewBuilder
    private var permissionGate: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(OPSStyle.Colors.text2)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                Text("// CAMERA OFF")
                    .font(.buttonLabel)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                Text("Enable camera access in Settings to capture dimensioned photos.")
                    .font(.smallBody)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing5)
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
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
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
        VStack(spacing: OPSStyle.Layout.spacing4) {
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
                .padding(.horizontal, OPSStyle.Layout.spacing5)
            Button("DISMISS") { dismiss() }
                .font(.buttonLabel)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
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
                topBar
                Spacer()
                helperRow(coordinator: coordinator)
                    .padding(.bottom, OPSStyle.Layout.spacing4)
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
                        .padding(.top, OPSStyle.Layout.spacing2_5)
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
    private var topBar: some View {
        HStack {
            if activeMode == .calibration {
                Button {
                    cancelCalibration()
                } label: {
                    Text("CANCEL")
                        .font(.buttonLabel)
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundColor(OPSStyle.Colors.text)
                        .frame(minWidth: 72, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Cancel calibration")

                Spacer()

                Text("// CALIBRATE")
                    .font(.buttonLabel)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundColor(OPSStyle.Colors.text)

                Spacer()

                Color.clear
                    .frame(width: 72, height: 44)
            } else {
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
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    // MARK: - Helper text row + accuracy chip

    @ViewBuilder
    private func helperRow(coordinator: LiDARCaptureCoordinator) -> some View {
        let derived = helperStateOverride ?? helperState(for: coordinator.state)
        HelperTextOverlay(state: derived)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func helperState(for state: LiDARCaptureCoordinator.CaptureState) -> HelperTextOverlay.HelperState {
        if activeMode == .calibration {
            return .calibration
        }
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
        await MainActor.run {
            withAnimation(.opsCurve200) { errorToast = nil }
        }

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
            if activeMode == .calibration {
                Task { await resolveCalibrationCapture(assets) }
                return
            }
            // Show post-capture flash chip for 1.5 s, then push to the Phase E
            // stub annotation view via `.fullScreenCover` (see body). Phase G
            // will move the navigation up to the entry point on
            // `ProjectActionBar` — for now the flow is self-contained so the
            // capture pipeline can be exercised end-to-end.
            withAnimation(.opsCurve200) {
                helperStateOverride = .capturedFlash
            }
            let capability = coordinatorBox.coordinator?.capability ?? .noDepth
            Task {
                let handoff = await Task.detached(priority: .userInitiated) {
                    DimensionedAnnotationHandoffBuilder.build(
                        assets: assets,
                        capability: capability
                    )
                }.value
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    pendingAnnotation = AnnotationPresentation(handoff: handoff)
                }
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

    // MARK: - Calibration mode

    private func enterCalibrationMode() {
        activeMode = .calibration
        helperStateOverride = nil
        withAnimation(.opsCurve200) { errorToast = nil }
        coordinatorBox.coordinator?.reset()
        coordinatorBox.coordinator?.startLiveAim()
    }

    private func cancelCalibration() {
        guard let session = calibrationSession else {
            activeMode = .normal
            dismiss()
            return
        }

        coordinatorBox.coordinator?.reset()
        calibrationSession = nil
        activeMode = .normal
        reopenAnnotation(session.cancelledAnnotation())
    }

    private func resolveCalibrationCapture(_ calibrationAssets: CapturedAssets) async {
        guard let session = calibrationSession else {
            await MainActor.run {
                activeMode = .normal
                showError(toast: ErrorToast(copy: "// CALIBRATION LOST · RETRY"))
                coordinatorBox.coordinator?.reset()
                coordinatorBox.coordinator?.startLiveAim()
            }
            return
        }

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try DimensionedCalibrationResolver.calibrationResult(
                    from: calibrationAssets,
                    hasLiDAR: session.originalHandoff.capability == .lidar
                )
            }.value
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                coordinatorBox.coordinator?.reset()
                calibrationSession = nil
                activeMode = .normal
                reopenAnnotation(session.calibratedAnnotation(with: result))
            }
        } catch {
            await MainActor.run {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showError(toast: .referenceNotFound)
                coordinatorBox.coordinator?.reset()
                coordinatorBox.coordinator?.startLiveAim()
            }
        }
    }

    private func reopenAnnotation(_ resolved: DimensionedResolvedAnnotation) {
        pendingAnnotation = AnnotationPresentation(resolved: resolved)
    }

    // MARK: - Errors

    @ViewBuilder
    private func errorToastView(_ toast: ErrorToast) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
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
            if toast.includesUseUncalibrated {
                Button {
                    cancelCalibration()
                } label: {
                    Text("USE UNCALIBRATED")
                        .font(.panelTitle)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(OPSStyle.Colors.surfaceActive)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .padding(.vertical, OPSStyle.Layout.spacing2)
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
        guard !toast.includesUseUncalibrated else { return }
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
                    if activeMode == .calibration {
                        cancelCalibration()
                    } else {
                        dismiss()
                    }
                }
            }
    }

    // MARK: - Save dispatch (Phase G integration)

    /// Delegates the 3-asset upload + PhotoAnnotation row creation to Phase F's
    /// `DimensionedPhotoSyncManager`. The manager itself fires the three rail
    /// notifications per spec §6. This call site owns local SwiftData continuity
    /// so a remote failure still leaves a retryable local annotation row.
    @MainActor
    private func saveFromAnnotation(
        assets: CapturedAssets,
        dimensions: DimensionsData
    ) async throws -> DimensionedAnnotationSaveResult {
        guard !saveInFlight else {
            throw DimensionedCaptureSaveStoreError.saveAlreadyInFlight
        }
        saveInFlight = true
        defer { saveInFlight = false }
        return try await dispatchSave(assets: assets, dimensions: dimensions)
    }

    /// Returns `.queuedForRetry` only after the queued `PhotoAnnotation` stub
    /// has been saved into SwiftData with its local HEIC/depth/sidecar paths.
    /// The annotation view stays open so the operator sees the retry state.
    @MainActor
    private func dispatchSave(
        assets: CapturedAssets,
        dimensions: DimensionsData
    ) async throws -> DimensionedAnnotationSaveResult {
        do {
            let annotation = try await DimensionedPhotoSyncManager.shared.sync(
                captured: assets,
                dimensions: dimensions,
                projectId: projectId,
                projectName: projectName,
                companyId: companyId,
                userId: userId
            )
            try DimensionedCaptureSaveStore.persistSyncedAnnotation(
                annotation,
                captured: assets,
                modelContext: modelContext
            )
            await MainActor.run {
                pendingAnnotation = nil
                onSavedSuccessfully(annotation)
                dismiss()
            }
            return .synced
        } catch let error as DimensionedSyncError {
            switch error {
            case .queuedForRetry, .annotationInsertFailed:
                _ = try DimensionedCaptureSaveStore.persistQueuedAnnotation(
                    captured: assets,
                    modelContext: modelContext
                )
                return .queuedForRetry
            case .missingLocalAsset, .missingRequiredDepthAsset, .renderedDeliverableFailed:
                throw error
            }
        } catch {
            throw error
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
    struct AnnotationPresentation {
        let handoff: DimensionedAnnotationHandoff
        let existingDimensions: DimensionsData?
        let initialCalibration: DimensionsData.Calibration
        let coplanarOnly: Bool
        let hasUnsavedChanges: Bool

        init(handoff: DimensionedAnnotationHandoff) {
            self.handoff = handoff
            self.existingDimensions = nil
            self.initialCalibration = handoff.initialCalibration
            self.coplanarOnly = handoff.coplanarOnly
            self.hasUnsavedChanges = false
        }

        init(resolved: DimensionedResolvedAnnotation) {
            self.handoff = resolved.handoff
            self.existingDimensions = resolved.dimensions
            self.initialCalibration = resolved.initialCalibration
            self.coplanarOnly = resolved.coplanarOnly
            self.hasUnsavedChanges = resolved.hasUnsavedChanges
        }
    }

    struct AnnotationHandoffConfiguration: Equatable {
        let capability: CaptureCapability
        let initialCalibration: DimensionsData.Calibration
        let hasAuto: Bool
        let hasCalibrate: Bool
        let coplanarOnly: Bool
    }

    enum ARAvailability {
        case checking, ready, denied, unsupported
    }

    static func annotationHandoffConfiguration(
        for capability: CaptureCapability
    ) -> AnnotationHandoffConfiguration {
        let calibration = DimensionsData.Calibration(
            method: capability == .lidar ? .lidar : .none,
            referenceObject: nil,
            scaleFactor: 1.0,
            estimatedAccuracyMeters: capability == .lidar ? 0.025 : 0.05
        )

        return AnnotationHandoffConfiguration(
            capability: capability,
            initialCalibration: calibration,
            hasAuto: false,
            hasCalibrate: capability != .noDepth,
            coplanarOnly: false
        )
    }

    struct ErrorToast: Equatable {
        let copy: String
        var includesOpenSettings: Bool = false
        var includesUseUncalibrated: Bool = false

        static let referenceNotFound = ErrorToast(
            copy: "// ERROR — REFERENCE NOT FOUND · INCREASE LIGHT · RETRY",
            includesUseUncalibrated: true
        )

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
