//
//  LocationPermissionView.swift
//  OPS
//
//  Branded explanation screen shown before the iOS system
//  location dialog. Explains why OPS needs location access.
//

import SwiftUI

struct MapLocationPermissionView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Image(OPSStyle.Icons.jobSite)
                .font(.system(size: 36))
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            Text("LOCATION SHARING")
                .font(OPSStyle.Typography.cardSubtitle)
                .tracking(1)
                .foregroundColor(.white)

            Text("OPS uses your location during your shift so your manager can coordinate the team. Location sharing only works when you are clocked in.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineSpacing(4)

            VStack(spacing: 12) {
                // Enable button (solid white primary CTA)
                Button(action: onEnable) {
                    Text("ENABLE LOCATION")
                        .font(OPSStyle.Typography.caption)
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)

                // Skip button (ghost)
                Button(action: onSkip) {
                    Text("NOT NOW")
                        .font(OPSStyle.Typography.caption)
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.background)
    }
}
