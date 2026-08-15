//
//  ValueChipRow.swift
//  OPS
//
//  Single-select value chips — FilterChipRow's exact chip treatment
//  (MOBILE.md §4.3 sanctions the 36pt form-picker chip group) without the
//  dot/count anatomy: these pick a value, they don't filter a list. Shared by
//  the booking sheet (DURATION / HEADS-UP) and notification settings.
//

import SwiftUI
import UIKit

/// Single-select value chips sharing FilterChipRow's exact chip treatment
/// (MOBILE.md §4.3 sanctions the 36pt form-picker chip group) without the
/// dot/count anatomy — these pick a value, they don't filter a list.
struct ValueChipRow: View {
    let options: [Int]
    let selected: Int
    let label: (Int) -> String
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    chip(option)
                }
            }
        }
    }

    // FilterChipRow's exact chip treatment (fill, hairline, radius, type),
    // minus the dot/count anatomy — one chip grammar across the app.
    private func chip(_ option: Int) -> some View {
        let isActive = option == selected
        return Button {
            guard option != selected else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(option)
        } label: {
            Text(label(option))
                .font(OPSStyle.Typography.metadata)
                .fontWeight(.semibold)
                .kerning(1.4)
                .foregroundColor(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
                .textCase(.uppercase)
                .monospacedDigit()
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .frame(minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                        .fill(isActive ? OPSStyle.Colors.line : OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                        .strokeBorder(
                            isActive ? Color.white.opacity(0.20) : OPSStyle.Colors.line,
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label(option))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
