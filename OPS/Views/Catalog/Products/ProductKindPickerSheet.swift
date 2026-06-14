//
//  ProductKindPickerSheet.swift
//  OPS
//
//  Bottom sheet presented when the FAB is tapped on the PRODUCTS segment.
//  Three large cards — SERVICE / GOOD / BUNDLE — let the operator pick
//  the kind of sellable they're authoring before landing on a tailored
//  create sheet (NewServiceSheet / NewGoodSheet / NewBundleSheet).
//
//  FEE is intentionally not offered here — fees in v1 are a power-user
//  path entered via the legacy Material/Other route on web. Most field
//  ops won't author fees from iOS; the field matrix in the design spec
//  only surfaces the three primary kinds.
//

import SwiftUI

struct ProductKindPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Fires with the picked category — `.service`, `.material` (a.k.a. GOOD),
    /// or `.bundle`. The parent translates this into one of the kind-tailored
    /// create-sheet flags.
    let onPick: (ProductCategory) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    Text("// CREATE SELLABLE")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.top, OPSStyle.Layout.spacing2)

                    card(for: .service)
                    card(for: .material)
                    card(for: .bundle)

                    Spacer()
                }
                .padding(OPSStyle.Layout.spacing3)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func card(for category: ProductCategory) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onPick(category)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: category.iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("// \(category.displayLabel)")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text(category.helpText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create \(category.displayLabel.lowercased())")
        .accessibilityHint(category.helpText)
    }
}
