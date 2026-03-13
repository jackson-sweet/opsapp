//
//  MapFilterChips.swift
//  OPS
//
//  Filter chips for the map: TODAY and ALL PROJECTS.
//  Mutually exclusive toggles that control which project pins are visible.
//

import SwiftUI

struct MapFilterChips: View {

    @Binding var filterMode: MapFilterMode

    var body: some View {
        HStack(spacing: 8) {
            chipButton(label: "TODAY [TASKS]", mode: .today)
            chipButton(label: "ACTIVE", mode: .active)
            chipButton(label: "ALL", mode: .all)
            Spacer()
        }
    }

    // MARK: - Chip Button

    @ViewBuilder
    private func chipButton(label: String, mode: MapFilterMode) -> some View {
        let isActive = filterMode == mode

        Button {
            withAnimation(OPSStyle.Animation.standard) {
                filterMode = mode
            }
        } label: {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(
                    isActive
                        ? OPSStyle.Colors.primaryText
                        : OPSStyle.Colors.secondaryText
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            isActive
                                ? OPSStyle.Colors.primaryAccent
                                : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44) // Minimum touch target
    }
}
