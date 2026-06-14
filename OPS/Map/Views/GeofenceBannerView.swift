//
//  GeofenceBannerView.swift
//  OPS
//
//  Frosted-glass banner that slides down for clock-in (arrival) and clock-out (departure) prompts.
//  Auto-dismisses after 15 seconds via GeofenceManager.
//

import SwiftUI

struct GeofenceBannerView: View {
    let event: GeofenceManager.GeofenceEvent
    let type: BannerType
    let onAction: () -> Void
    let onDismiss: () -> Void

    enum BannerType {
        case arrival
        case departure

        var actionLabel: String {
            switch self {
            case .arrival: return "CLOCK IN"
            case .departure: return "CLOCK OUT"
            }
        }

        var prefix: String {
            switch self {
            case .arrival: return "ARRIVED AT"
            case .departure: return "LEAVING"
            }
        }

        var dotColor: Color {
            switch self {
            case .arrival: return OPSStyle.Colors.successStatus
            case .departure: return OPSStyle.Colors.warningStatus
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Status line
            HStack(spacing: 6) {
                Circle()
                    .fill(type.dotColor)
                    .frame(width: 8, height: 8)

                Text(type.prefix)
                    .font(OPSStyle.Typography.microLabel)
                    .tracking(0.5)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()
            }

            // Project name
            Text(event.projectName.uppercased())
                .font(OPSStyle.Typography.caption)
                .tracking(0.5)
                .foregroundColor(.white)
                .lineLimit(1)

            // Address
            if !event.address.isEmpty {
                Text(event.address)
                    .font(OPSStyle.Typography.smallBody)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }

            // Action row
            HStack {
                // Primary action button (solid white)
                Button(action: onAction) {
                    Text(type.actionLabel)
                        .font(OPSStyle.Typography.smallCaption)
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.background)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                // Dismiss button (ghost)
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(OPSStyle.Typography.cardBody)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, OPSStyle.Layout.spacing1)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }
}
