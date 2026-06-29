//
//  MeasureActionButton.swift
//  OPS
//
//  Phase G — the MEASURE entry on `ProjectActionBar` for the LiDAR Dimensioned
//  Photo Capture flow. Release builds render when the rollout flag is on.
//  Debug builds also render a dev override when the flag is off so hardware
//  and capture flow testing is obvious. No-depth devices get a limitation
//  screen instead of a silent hidden action when the entry is visible.
//
//  Tap presents `DimensionedCaptureView` full-screen. The capture view handles
//  permission gating, capability checks, and dispatches to Phase E's
//  annotation view on shutter. The save closure delegates to Phase F's
//  `DimensionedPhotoSyncManager`, which fires the rail notifications.
//
//  Spec: ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §3.1 §10.3
//

import SwiftUI

enum MeasurementEntryState: Equatable {
    case hidden
    case capture(developerFlagOverride: Bool)
    case unavailable(MeasurementUnavailableReason)
}

enum MeasurementUnavailableReason: Equatable {
    case hardwareUnsupported
    case featureFlagDisabled
    case featureFlagAndHardware
}

struct MeasureActionButton: View {
    let project: Project

    @EnvironmentObject private var dataController: DataController
    @ObservedObject private var permissionStore = PermissionStore.shared

    @State private var showCapture = false
    @State private var showUnavailable = false
    @State private var pendingErrorBanner: String?

    /// Visibility gate. Release builds fail closed when the rollout flag is
    /// off; debug/dev builds keep the entry visible so the test path is obvious.
    static func shouldRender(
        flagEnabled: Bool,
        capability: CaptureCapability,
        developerMode: Bool = defaultDeveloperMode
    ) -> Bool {
        entryState(
            flagEnabled: flagEnabled,
            capability: capability,
            developerMode: developerMode
        ) != .hidden
    }

    static func entryState(
        flagEnabled: Bool,
        capability: CaptureCapability,
        developerMode: Bool = defaultDeveloperMode
    ) -> MeasurementEntryState {
        if flagEnabled {
            switch capability {
            case .lidar, .visual:
                return .capture(developerFlagOverride: false)
            case .noDepth:
                return .unavailable(.hardwareUnsupported)
            }
        }

        guard developerMode else { return .hidden }
        switch capability {
        case .lidar, .visual:
            return .capture(developerFlagOverride: true)
        case .noDepth:
            return .unavailable(.featureFlagAndHardware)
        }
    }

    static func usesDeveloperFlagOverride(
        flagEnabled: Bool,
        capability: CaptureCapability,
        developerMode: Bool = defaultDeveloperMode
    ) -> Bool {
        entryState(
            flagEnabled: flagEnabled,
            capability: capability,
            developerMode: developerMode
        ).developerFlagOverride
    }

    static var defaultDeveloperMode: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private var entryState: MeasurementEntryState {
        Self.entryState(
            flagEnabled: permissionStore.isFeatureEnabled(MeasurementFlag.dimensionedCapture),
            capability: CaptureCapability.detect().capability
        )
    }

    var body: some View {
        Group {
            if entryState != .hidden {
                OPSActionBarButton(
                    icon: "ruler",
                    label: "Measure"
                ) {
                    switch entryState {
                    case .capture:
                        showCapture = true
                    case .unavailable:
                        showUnavailable = true
                    case .hidden:
                        break
                    }
                }
                .fullScreenCover(isPresented: $showCapture) {
                    DimensionedCaptureView(
                        projectId: project.id,
                        projectName: project.title,
                        companyId: project.companyId,
                        userId: dataController.currentUser?.id ?? "",
                        developerFlagOverride: entryState.developerFlagOverride,
                        onSavedSuccessfully: { _ in
                            showCapture = false
                        },
                        onError: { error in
                            pendingErrorBanner = error.localizedDescription
                            showCapture = false
                        }
                    )
                }
                .fullScreenCover(isPresented: $showUnavailable) {
                    MeasurementUnavailableView(
                        reason: entryState.unavailableReason ?? .hardwareUnsupported,
                        onDismiss: { showUnavailable = false }
                    )
                }
                .errorToast($pendingErrorBanner, label: Feedback.Err.operationFailed)
            }
        }
    }
}

private extension MeasurementEntryState {
    var developerFlagOverride: Bool {
        if case .capture(let developerFlagOverride) = self {
            return developerFlagOverride
        }
        return false
    }

    var unavailableReason: MeasurementUnavailableReason? {
        if case .unavailable(let reason) = self {
            return reason
        }
        return nil
    }
}

private struct MeasurementUnavailableView: View {
    let reason: MeasurementUnavailableReason
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            Image(systemName: reason.icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(OPSStyle.Colors.text2)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                Text(reason.title)
                    .font(.buttonLabel)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                Text(reason.body)
                    .font(.smallBody)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing5)
            }

            Button("DISMISS") { onDismiss() }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background.ignoresSafeArea())
    }
}

private extension MeasurementUnavailableReason {
    var icon: String {
        switch self {
        case .hardwareUnsupported, .featureFlagAndHardware:
            return "arkit"
        case .featureFlagDisabled:
            return "flag.slash"
        }
    }

    var title: String {
        switch self {
        case .hardwareUnsupported:
            return "// NO DEPTH"
        case .featureFlagDisabled:
            return "// MEASURE FLAG OFF"
        case .featureFlagAndHardware:
            return "// MEASURE UNAVAILABLE"
        }
    }

    var body: String {
        switch self {
        case .hardwareUnsupported:
            return "LiDAR or ARKit is required for dimensioned capture on this device."
        case .featureFlagDisabled:
            return "Remote flag feature.measurement.dimensioned_capture is off."
        case .featureFlagAndHardware:
            return "Remote flag is off and this device cannot run AR dimensioned capture."
        }
    }
}
