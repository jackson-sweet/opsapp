//
//  OPSCounterRow.swift
//  OPS
//
//  The house −/+ counter row: the sanctioned control for a bounded numeric
//  value. MOBILE.md §13 bans stock `Stepper` — its hit targets are far under
//  44pt and it carries Apple's visual language, not OPS's. This is the same
//  pattern `StairCounterRow` established in the deck stair sheet, lifted into
//  the shared component set so every numeric form uses one control.
//
//  Anatomy: uppercase mono label, optional support line beneath it, the value in
//  tabular mono at full strength, then a nested −/+ pair with 44pt targets and
//  disabled ends (never a silent clamp — a dead button tells the operator they
//  have hit the limit).
//

import SwiftUI
import UIKit

struct OPSCounterRow: View {
    let label: String
    /// Preformatted value — always mono, always formatted (`3 TUBES`, `9'6"`),
    /// never a raw float.
    let value: String
    /// Optional second line under the label: the calculator's suggestion, a
    /// sharing note, a unit reminder.
    var support: String?
    let canDecrement: Bool
    let canIncrement: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    /// Dims the value when the line is at zero, so a zeroed form reads as
    /// deliberately empty rather than merely unfilled.
    var isZero: Bool = false

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(label.uppercased())
                    .font(OPSStyle.Typography.metadata)
                    .kerning(1.4)
                    .foregroundColor(OPSStyle.Colors.text3)
                if let support, !support.isEmpty {
                    Text(support)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)

            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(isZero ? OPSStyle.Colors.textMute : OPSStyle.Colors.text)
                .monospacedDigit()

            HStack(spacing: 0) {
                stepButton(systemImage: "minus", enabled: canDecrement, action: onDecrement)
                    .accessibilityLabel("Decrease \(label)")
                Divider()
                    .frame(height: OPSStyle.Layout.touchTargetMin / 2)
                    .overlay(OPSStyle.Colors.line)
                stepButton(systemImage: "plus", enabled: canIncrement, action: onIncrement)
                    .accessibilityLabel("Increase \(label)")
            }
            .nestedCard()
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .accessibilityElement(children: .contain)
        .accessibilityValue(value)
    }

    private func stepButton(
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: systemImage)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(enabled ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

extension OPSCounterRow {
    /// Integer convenience: bounds the value, formats it with an optional unit
    /// suffix, and wires both buttons to a single binding.
    init(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        unit: String? = nil,
        support: String? = nil
    ) {
        let current = value.wrappedValue
        self.label = label
        self.value = unit.map { "\(current) \($0)" } ?? "\(current)"
        self.support = support
        self.canDecrement = current > range.lowerBound
        self.canIncrement = current < range.upperBound
        self.isZero = current == 0
        self.onDecrement = { value.wrappedValue = max(range.lowerBound, current - step) }
        self.onIncrement = { value.wrappedValue = min(range.upperBound, current + step) }
    }
}
