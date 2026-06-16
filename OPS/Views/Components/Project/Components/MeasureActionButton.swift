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
                    showCapture = true
                }
                .fullScreenCover(isPresented: $showCapture) {
                    DimensionedCaptureView(
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
                        }
                    )
                }
                .errorToast($pendingErrorBanner, label: Feedback.Err.operationFailed)
            }
        }
    }
}
