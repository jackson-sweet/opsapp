//
//  CategoryPickerField.swift
//  OPS
//
//  Reusable CatalogCategory picker for the kind-tailored create sheets.
//  Extracts the Menu + "+ NEW" pattern from QuickAddProductSheet so each
//  new sheet (NewService / NewGood / NewBundle) consumes the same widget
//  without duplicating boilerplate. The parent owns the inline-create
//  sheet state — we only fire a callback when the operator picks the
//  "+ NEW CATEGORY…" affordance.
//

import SwiftUI

struct CategoryPickerField: View {
    @Binding var selectedCategoryId: String?
    let companyCategories: [CatalogCategory]
    let canCreateNew: Bool
    let onCreateRequested: () -> Void

    var body: some View {
        Menu {
            Button {
                selectedCategoryId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("None", systemImage: selectedCategoryId == nil ? "checkmark" : "")
            }
            ForEach(companyCategories) { category in
                Button {
                    selectedCategoryId = category.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if selectedCategoryId == category.id {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
            if canCreateNew {
                Divider()
                Button {
                    onCreateRequested()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("New category…", systemImage: "plus")
                }
            }
        } label: {
            menuLabel(text: selectedDisplay)
        }
    }

    private var selectedDisplay: String {
        guard let id = selectedCategoryId,
              let cat = companyCategories.first(where: { $0.id == id })
        else { return "None" }
        return cat.name
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
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}
