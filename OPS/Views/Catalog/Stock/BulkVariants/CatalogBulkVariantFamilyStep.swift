//
//  CatalogBulkVariantFamilyStep.swift
//  OPS
//

import SwiftUI

struct CatalogBulkVariantFamilyRow: Identifiable, Equatable {
    let id: String
    let name: String
    let variantCount: Int
    let axesText: String
    let searchText: String
    let isSelectable: Bool
    let issue: String?
}

struct CatalogBulkVariantFamilyStep: View {
    @ObservedObject var model: CatalogBulkVariantExpansionModel
    let families: [CatalogBulkVariantFamilyRow]
    let selectableFamilyIds: Set<String>

    private var filteredFamilies: [CatalogBulkVariantFamilyRow] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return families }
        return families.filter { $0.searchText.localizedCaseInsensitiveContains(query) }
    }

    private var filteredSelectableIds: [String] {
        filteredFamilies.filter(\.isSelectable).map(\.id)
    }

    private var allFilteredSelected: Bool {
        !filteredSelectableIds.isEmpty
            && filteredSelectableIds.allSatisfy(model.selectedFamilyIds.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("CHOOSE FAMILIES")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.text)
                Text("Choose every stock family that gets the same new option.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            searchField
            selectionControl

            if filteredFamilies.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(filteredFamilies) { family in
                        familyRow(family)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.search)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text3)
            TextField("SEARCH FAMILIES", text: $model.searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Search stock families")
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .frame(
                            width: OPSStyle.Layout.touchTargetMin,
                            height: OPSStyle.Layout.touchTargetMin
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear family search")
            }
        }
        .padding(.leading, OPSStyle.Layout.spacing3)
        .padding(.trailing, OPSStyle.Layout.spacing2)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .background(OPSStyle.Colors.surfaceInput)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        }
    }

    private var selectionControl: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("\(model.selectedFamilyIds.count) SELECTED")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(model.selectedFamilyIds.isEmpty ? OPSStyle.Colors.text3 : OPSStyle.Colors.text)
                .monospacedDigit()
            Spacer()
            Button(allFilteredSelected ? "CLEAR VISIBLE" : "SELECT VISIBLE") {
                if allFilteredSelected {
                    model.clearVisible(filteredSelectableIds)
                } else {
                    model.selectAllVisible(filteredSelectableIds, selectableFamilyIds: selectableFamilyIds)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(filteredSelectableIds.isEmpty ? OPSStyle.Colors.textMute : OPSStyle.Colors.text2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .disabled(filteredSelectableIds.isEmpty)
            .accessibilityHint("Applies to the families in the current search results.")
        }
    }

    private func familyRow(_ family: CatalogBulkVariantFamilyRow) -> some View {
        let selected = model.selectedFamilyIds.contains(family.id)
        return Button {
            model.toggleFamily(family.id, selectableFamilyIds: selectableFamilyIds)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: selected ? OPSStyle.Icons.checkmarkSquareFill : OPSStyle.Icons.square)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(
                        family.isSelectable
                            ? (selected ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                            : OPSStyle.Colors.textMute
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(family.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(family.isSelectable ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(family.issue ?? family.axesText)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(family.issue == nil ? OPSStyle.Colors.text3 : OPSStyle.Colors.roseTextM)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("\(family.variantCount)")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(family.isSelectable ? OPSStyle.Colors.text2 : OPSStyle.Colors.textMute)
                    .monospacedDigit()
                    .accessibilityLabel("\(family.variantCount) active variants")
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetLarge)
            .background(selected ? OPSStyle.Colors.surfaceSelected : OPSStyle.Colors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                    .stroke(
                        selected ? OPSStyle.Colors.activeSegmentBorder : OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!family.isSelectable)
        .accessibilityLabel(family.name)
        .accessibilityValue(selected ? "Selected" : (family.issue ?? "Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("NO FAMILIES FOUND")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
            Text("Try a different family, category, option, or value.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text2)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }
}
