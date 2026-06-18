//
//  ModifiersReadOnlyView.swift
//  OPS
//
//  Read-only renderer for ProductPricingModifier rows. Each modifier
//  becomes a one-liner like "When Mount Surface = Concrete → +$5.00 per
//  unit" so the operator can confirm the rule set without leaving iOS.
//

import SwiftUI

struct ModifiersReadOnlyView: View {
    let modifiers: [ProductPricingModifier]
    let options: [ProductOption]
    let optionValues: [ProductOptionValue]

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            ForEach(modifiers) { modifier in
                row(modifier)
            }
        }
    }

    @ViewBuilder
    private func row(_ modifier: ProductPricingModifier) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(triggerSentence(modifier))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                effectChip(modifier)
                Spacer()
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    private func triggerSentence(_ modifier: ProductPricingModifier) -> String {
        let optionName = options.first(where: { $0.id == modifier.optionId })?.name ?? "Option"
        if let triggerValueId = modifier.triggerValueId,
           let value = optionValues.first(where: { $0.id == triggerValueId }) {
            return "When \(optionName) = \(value.value) → \(effectClause(modifier))"
        }
        if let min = modifier.triggerIntMin, let max = modifier.triggerIntMax {
            if min == max {
                return "When \(optionName) = \(min) → \(effectClause(modifier))"
            }
            return "When \(optionName) is \(min)–\(max) → \(effectClause(modifier))"
        }
        if let min = modifier.triggerIntMin {
            return "When \(optionName) ≥ \(min) → \(effectClause(modifier))"
        }
        if let max = modifier.triggerIntMax {
            return "When \(optionName) ≤ \(max) → \(effectClause(modifier))"
        }
        return "When \(optionName) is set → \(effectClause(modifier))"
    }

    private func effectClause(_ modifier: ProductPricingModifier) -> String {
        let amountString = formatAmount(modifier.amount, kind: modifier.modifierKind)
        switch modifier.modifierKind {
        case .addPerUnit:        return "\(amountString) per unit"
        case .addFlat:           return "\(amountString) flat"
        case .addPerCount:       return "\(amountString) per count"
        case .multiplyUnitPrice: return "× \(formatMultiplier(modifier.amount)) unit price"
        }
    }

    private func formatAmount(_ amount: Double, kind: PricingModifierKind) -> String {
        if kind == .multiplyUnitPrice {
            return formatMultiplier(amount)
        }
        let sign = amount >= 0 ? "+" : "−"
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let absString = formatter.string(from: NSNumber(value: abs(amount))) ?? "$0"
        return "\(sign)\(absString)"
    }

    private func formatMultiplier(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: amount)) ?? "1"
    }

    private func effectChip(_ modifier: ProductPricingModifier) -> some View {
        Text(modifierKindLabel(modifier.modifierKind))
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private func modifierKindLabel(_ kind: PricingModifierKind) -> String {
        switch kind {
        case .addPerUnit:        return "ADD PER UNIT"
        case .addFlat:           return "ADD FLAT"
        case .addPerCount:       return "ADD PER COUNT"
        case .multiplyUnitPrice: return "MULTIPLY UNIT"
        }
    }
}
