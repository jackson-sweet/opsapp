//
//  MeasureActionButton.swift
//  OPS
//
//  Phase G — the MEASURE entry on `ProjectActionBar` for the LiDAR Dimensioned
//  Photo Capture flow. Renders only when:
//    1. `feature.measurement.dimensioned_capture` is enabled for the user, AND
//    2. The device capability is `.lidar` or `.visual` (NOT `.noDepth`)
//
//  Tap presents `DimensionedCaptureView` full-screen. The capture view handles
//  permission gating, capability checks, and dispatches to Phase E's
//  annotation view on shutter. The save closure delegates to Phase F's
//  `DimensionedPhotoSyncManager`, which fires the rail notifications.
//
//  Spec: ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.1 §10.3
//

import SwiftUI

struct MeasureActionButton: View {
    let project: Project

    @EnvironmentObject private var dataController: DataController
    @ObservedObject private var permissionStore = PermissionStore.shared

    @State private var showCapture = false
    @State private var captureMode: DimensionedCaptureView.CaptureMode = .normal
    @State private var pendingErrorBanner: String?

    /// Visibility gate. Pure function of (flag, capability) — exposed for unit
    /// testing. Capability defaults to live device detection but is injectable.
    static func shouldRender(
        flagEnabled: Bool,
        capability: CaptureCapability
    ) -> Bool {
        guard flagEnabled else { return false }
        switch capability {
        case .lidar, .visual: return true
        case .noDepth:        return false
        }
    }

    private var isVisible: Bool {
        Self.shouldRender(
            flagEnabled: permissionStore.isFeatureEnabled(MeasurementFlag.dimensionedCapture),
            capability: CaptureCapability.detect().capability
        )
    }

    var body: some View {
        Group {
            if isVisible {
                OPSActionBarButton(
                    icon: "ruler",
                    label: "Measure"
                ) {
                    captureMode = .normal
                    showCapture = true
                }
                .fullScreenCover(isPresented: $showCapture) {
                    DimensionedCaptureView(
                        mode: captureMode,
                        projectId: project.id,
                        projectName: project.title,
                        companyId: project.companyId,
                        userId: dataController.currentUser?.id ?? "",
                        onSavedSuccessfully: { _ in
                            showCapture = false
                        },
                        onError: { error in
                            pendingErrorBanner = error.localizedDescription
                            showCapture = false
                        },
                        onRequestCalibrationMode: {
                            // Round-trip per spec §5.2: dismiss, re-present
                            // capture view in calibration mode so the user can
                            // reframe a reference object. Annotation view's
                            // measurements are preserved by `existingDimensions`
                            // on the next re-entry.
                            showCapture = false
                            captureMode = .calibration
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                showCapture = true
                            }
                        }
                    )
                }
            }
        }
        .alert(
            "Capture failed",
            isPresented: Binding(
                get: { pendingErrorBanner != nil },
                set: { if !$0 { pendingErrorBanner = nil } }
            ),
            presenting: pendingErrorBanner
        ) { _ in
            Button("OK", role: .cancel) { pendingErrorBanner = nil }
        } message: { msg in
            Text(msg)
        }
    }
}
