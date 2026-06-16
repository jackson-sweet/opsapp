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
            ForEach(Self.orderedDimensions, id: \.self) { dimension in
                if !units(in: dimension).isEmpty {
                    Section(dimensionTitle(dimension)) {
                        ForEach(units(in: dimension)) { unit in
                            unitButton(unit)
                        }
                    }
                }
            }
            if !otherDimensionUnits.isEmpty {
                Section("Other") {
                    ForEach(otherDimensionUnits) { unit in
                        unitButton(unit)
                    }
                }
            }
            if canCreateNew {
                Divider()
                Button {
                    onCreateRequested()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("New unit…", systemImage: "plus")
                }
            }
        } label: {
            menuLabel(text: selectedDisplay)
        }
    }

    // MARK: - Dimension grouping

    /// Dimension order for the grouped menu, most-common first. Mirrors the
    /// `catalog_units.dimension` CHECK values.
    private static let orderedDimensions = ["count", "length", "area", "volume", "mass", "time"]

    private func units(in dimension: String) -> [CatalogUnit] {
        companyUnits.filter { $0.dimension == dimension }
    }

    /// Any units carrying a dimension outside the known set — surfaced under
    /// an "Other" section so nothing silently disappears from the picker.
    private var otherDimensionUnits: [CatalogUnit] {
        let known = Set(Self.orderedDimensions)
        return companyUnits.filter { !known.contains($0.dimension) }
    }

    private func dimensionTitle(_ dimension: String) -> String {
        switch dimension {
        case "count":  return "Count"
        case "length": return "Length"
        case "area":   return "Area"
        case "volume": return "Volume"
        case "mass":   return "Weight"
        case "time":   return "Time"
        default:       return dimension.capitalized
        }
    }

    @ViewBuilder
    private func unitButton(_ unit: CatalogUnit) -> some View {
        Button {
            selectedUnitId = unit.id
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            if selectedUnitId == unit.id {
                Label(unit.display, systemImage: "checkmark")
            } else {
                Text(unit.display)
            }
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
            Image(systemName: "chevron.down")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .background(OPSStyle.Colors.surfaceInput)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}
