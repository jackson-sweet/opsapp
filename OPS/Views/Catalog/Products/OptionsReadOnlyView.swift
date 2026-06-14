//
//  OptionsReadOnlyView.swift
//  OPS
//
//  Read-only renderer for a Product's configurable options. Each option
//  shows kind, default + source, and the allowed values when select-kind.
//  Authoring lives on the web until iOS gets a full editor.
//

import SwiftUI

struct OptionsReadOnlyView: View {
    let options: [ProductOption]
    let optionValues: [ProductOptionValue]

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            ForEach(sortedOptions) { option in
                optionCard(option)
            }
        }
    }

    private var sortedOptions: [ProductOption] {
        options.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private func valuesFor(_ option: ProductOption) -> [ProductOptionValue] {
        optionValues
            .filter { $0.optionId == option.id }
            .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
    }

    @ViewBuilder
    private func optionCard(_ option: ProductOption) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(option.name.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                kindChip(option.kind)
                if option.required {
                    requiredChip
                }
            }

            HStack(spacing: OPSStyle.Layout.spacing3) {
                if option.affectsPrice {
                    metadataChip("PRICE")
                }
                if option.affectsRecipe {
                    metadataChip("RECIPE")
                }
                Spacer()
            }

            if let defaultValue = option.defaultValue, !defaultValue.isEmpty {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("DEFAULT")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(defaultValue)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    if let source = option.optionDefaultSource, !source.isEmpty {
                        Text("← \(source)")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    Spacer()
                }
            } else if let source = option.optionDefaultSource, !source.isEmpty {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("DEFAULT FROM")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(source)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                }
            }

            if option.kind == .select {
                let values = valuesFor(option)
                if !values.isEmpty {
                    valueChips(values)
                } else {
                    Text("// NO VALUES")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func valueChips(_ values: [ProductOptionValue]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                ForEach(values) { value in
                    Text(value.value)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
            }
        }
    }

    private func kindChip(_ kind: ProductOptionKind) -> some View {
        Text(kindLabel(kind))
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private func kindLabel(_ kind: ProductOptionKind) -> String {
        switch kind {
        case .select:  return "SELECT"
        case .integer: return "INTEGER"
        case .boolean: return "BOOLEAN"
        }
    }

    private var requiredChip: some View {
        Text("REQUIRED")
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.warningText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.warningText.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private func metadataChip(_ label: String) -> some View {
        Text(label)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}
