//
//  ScheduleConnectivityStrip.swift
//  OPS
//
//  Persistent status strip shown under the schedule header whenever the device
//  can't reach the server (offline, or connected but an unusable connection).
//  It reassures the operator that the schedule on screen is the last synced
//  copy, not live — so a stale schedule is never silently trusted in the field.
//  Hidden entirely (no chrome) the moment the connection is good again.
//

import SwiftUI

struct ScheduleConnectivityStrip: View {
    @ObservedObject var connectivity: ConnectivityManager

    /// Fully offline vs. connected-but-too-weak-to-sync. Both mean "what you see
    /// may be stale," but the label tells the operator which one they're in.
    private var isOffline: Bool { connectivity.state.status == .offline }

    /// Show whenever a sync can't be attempted (offline OR unusable quality).
    private var shouldShow: Bool { !connectivity.shouldAttemptSync }

    var body: some View {
        if shouldShow {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: isOffline ? "wifi.slash" : "wifi.exclamationmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.warningStatus)

                Text(isOffline
                     ? "// NO CONNECTION · SHOWING LAST SYNCED"
                     : "// WEAK SIGNAL · SHOWING LAST SYNCED")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .glassSurface()
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing2)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isOffline
                                ? "No connection. Showing your last synced schedule."
                                : "Weak signal. Showing your last synced schedule.")
        }
    }
}
