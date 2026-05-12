//
//  CapabilityChip.swift
//  OPS
//
//  Text-only chip rendering the device capability state per spec §3.6 / §3.8.
//  No emoji. Cake Mono Light, UPPERCASE. Reused in §5.1 capture view AND
//  §5.2 annotation view (Phase E) — keep the surface minimal.
//

import SwiftUI

struct CapabilityChip: View {
    let capability: CaptureCapability

    var body: some View {
        Text(displayLabel)
            .font(.badgeCake)
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundColor(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .strokeBorder(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
            .accessibilityLabel(Text("Capture capability: \(displayLabel)"))
    }

    // MARK: - Spec mapping (testable surface)

    var displayLabel: String {
        switch capability {
        case .lidar:   return "LIDAR"
        case .visual:  return "VISUAL"
        case .noDepth: return "NO DEPTH"
        }
    }

    /// Background fill — soft-tint earth tone per `ops-design-system` chip pattern.
    var background: Color {
        switch capability {
        case .lidar:   return OPSStyle.Colors.oliveSoft
        case .visual:  return OPSStyle.Colors.tanSoft
        case .noDepth: return Color.white.opacity(0.06)
        }
    }

    /// Border — 30% alpha earth tone hairline so the chip reads on any background.
    var border: Color {
        switch capability {
        case .lidar:   return OPSStyle.Colors.oliveLine
        case .visual:  return OPSStyle.Colors.tanLine
        case .noDepth: return OPSStyle.Colors.line
        }
    }

    /// Foreground — semantic earth tone for state colors per spec §3.6 table.
    var foreground: Color {
        switch capability {
        case .lidar:   return OPSStyle.Colors.olive
        case .visual:  return OPSStyle.Colors.tan
        case .noDepth: return OPSStyle.Colors.textMute
        }
    }
}
