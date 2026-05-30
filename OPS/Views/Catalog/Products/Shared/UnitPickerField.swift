//
//  UnitPickerField.swift
//  OPS
//
//  Reusable CatalogUnit picker. Mirrors `CategoryPickerField` but for the
//  CatalogUnit FK. `allowFlatRate` controls whether the first option is
//  "Flat rate" (nil unitId) — services + goods get it, bundles don't
//  (bundles are always flat-rate at the parent line, so the picker is
//  unnecessary for them).
//

import SwiftUI

struct UnitPickerField: View {
    @Binding var selectedUnitId: String?
    let companyUnits: [CatalogUnit]
    let canCreateNew: Bool
    let onCreateRequested: () -> Void
    /// When true, the menu surfaces a "Flat rate" option that maps to
    /// `selectedUnitId == nil`. When false, the operator must pick a unit.
    let allowFlatRate: Bool

    var body: some View {
        Menu {
            if allowFlatRate {
                Button {
                    selectedUnitId = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("Flat rate", systemImage: selectedUnitId == nil ? "checkmark" : "")
                }
            }
            ForEach(companyUnits) { unit in
                Button {
                    selectedUnitId = unit.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if selectedUnitId == unit.id {
                        Label(unit.display, image: "ops.checkmark")
                    } else {
                        Text(unit.display)
                    }
                }
            }
            if canCreateNew {
                Divider()
                Button {
                    onCreateRequested()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("New unit…", image: "ops.add")
                }
            }
        } label: {
            menuLabel(text: selectedDisplay)
        }
    }

    private var selectedDisplay: String {
        guard let id = selectedUnitId,
              let unit = companyUnits.first(where: { $0.id == id })
        else { return allowFlatRate ? "Flat rate" : "Pick a unit" }
        return unit.display
    }

    @ViewBuilder
    private func menuLabel(text: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
            Spacer()
            Image("ops.chevron-down")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}
