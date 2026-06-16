//
//  SyncStatusIndicator.swift
//  OPS
//
//  Displays sync status and alerts user about pending syncs
//

import SwiftUI

/// Compact indicator showing pending sync status
struct SyncStatusIndicator: View {
    @EnvironmentObject private var dataController: DataController

    var body: some View {
        if dataController.hasPendingSyncs && !dataController.isConnected {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.warningStatus)

                Text("\(dataController.pendingSyncCount) pending")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(
                Capsule()
                    .fill(OPSStyle.Colors.warningStatus.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        } else if dataController.isSyncing {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // Tactical loading bar instead of circular progress
                TacticalLoadingBarAnimated(
                    barCount: 6,
                    barWidth: 2,
                    barHeight: 6,
                    spacing: 3,
                    emptyColor: OPSStyle.Colors.primaryAccent.opacity(0.3),
                    fillColor: OPSStyle.Colors.primaryAccent
                )

                Text("SYNCING")
                    .font(OPSStyle.Typography.smallCaption.weight(.bold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .tracking(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.95))
            )
            .overlay(
                Capsule()
                    .strokeBorder(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }
}

#Preview {
    ZStack {
        OPSStyle.Colors.background

        VStack(spacing: OPSStyle.Layout.spacing3_5) {
            SyncStatusIndicator()

            Button("Show Alert") {
                // Preview button
            }
        }
    }
    .environmentObject(DataController())
}
