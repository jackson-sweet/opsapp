//
//  CategoryPicker.swift
//  OPS
//
//  Three-way segmented picker for the user-facing product taxonomy:
//  Service / Material / Fee. Replaces the legacy two-axis confusion of
//  `Kind` (Service/Good) + `Line item type` (Labor/Material/Other) on
//  the New Product sheet (and forward-compatible with ProductDetailView).
//
//  The picker stays styled per OPSStyle — military tactical minimalist,
//  no SwiftUI segmented control because that ships with iOS-default
//  blue and rounded corners that don't match the design system.
//
//  Bug 164e0595 — New Product Sheet redesign.
//

import SwiftUI

struct CategoryPicker: View {
    @Binding var selection: ProductCategory

    /// Fires after `selection` updates so callers can re-default downstream
    /// fields (e.g. flip the `taxable` toggle when category changes, unless
    /// the user has manually overridden it).
    let onChange: ((ProductCategory) -> Void)?

    init(selection: Binding<ProductCategory>, onChange: ((ProductCategory) -> Void)? = nil) {
        self._selection = selection
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                ForEach(ProductCategory.allCases) { category in
                    segment(category)
                }
            }

            Text(selection.helpText)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true) // segment labels announce the meaning already
        }
    }

    @ViewBuilder
    private func segment(_ category: ProductCategory) -> some View {
        let isSelected = (selection == category)
        Button {
            // Skip the haptic + onChange when re-tapping the active segment
            // — avoids double-firing tax-default flips on a no-op touch.
            guard selection != category else { return }
            selection = category
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onChange?(category)
        } label: {
            Text(category.displayLabel)
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(isSelected
                                 ? OPSStyle.Colors.text
                                 : OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(isSelected
                            ? OPSStyle.Colors.surfaceActive
                            : OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(isSelected
                                ? OPSStyle.Colors.text
                                : OPSStyle.Colors.cardBorder,
                                lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Category \(category.displayLabel)")
        .accessibilityHint(category.helpText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
