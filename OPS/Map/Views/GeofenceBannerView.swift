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
        VStack(alignment: .leading, spacing: 8) {
            // Status line
            HStack(spacing: 6) {
                Circle()
                    .fill(type.dotColor)
                    .frame(width: 8, height: 8)

                Text(type.prefix)
                    .font(Font.custom("Kosugi-Regular", size: 11))
                    .tracking(0.5)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()
            }

            // Project name
            Text(event.projectName.uppercased())
                .font(Font.custom("Kosugi-Regular", size: 13))
                .tracking(0.5)
                .foregroundColor(.white)
                .lineLimit(1)

            // Address
            if !event.address.isEmpty {
                Text(event.address)
                    .font(Font.custom("Mohave-Light", size: 13))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }

            // Action row
            HStack {
                // Primary action button (solid white)
                Button(action: onAction) {
                    Text(type.actionLabel)
                        .font(Font.custom("Kosugi-Regular", size: 12))
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.background)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
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
                        .font(Font.custom("Mohave-Regular", size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.horizontal, 16)
    }
}
