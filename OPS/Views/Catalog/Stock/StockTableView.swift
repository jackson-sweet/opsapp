//
//  StockTableView.swift
//  OPS
//
//  TABLE view mode for the STOCK segment (Bug 217c3d1f). Renders one
//  table per family. Each table's header row enumerates the family's
//  options dynamically (`VARIANT | <option 1> | <option 2> | ... | QTY
//  | THRESH | SKU`); body rows are the family's variants. Each family table
//  scrolls horizontally because column counts vary across families.
//

import SwiftUI

struct StockTableView: View {
    let rows: [EnrichedVariantRow]
    let categories: [CatalogCategory]
    let allOptions: [CatalogOption]
    let allOptionValues: [CatalogOptionValue]
    let allVariantOptionValues: [CatalogVariantOptionValue]

    var onTap: ((EnrichedVariantRow) -> Void)? = nil

    /// Group rows by family id, preserving insertion order so the order
    /// surfaced in StockView's filter pipeline shows through.
    private struct FamilyTable: Identifiable {
        let id: String
        let family: CatalogItem
        let category: CatalogCategory?
        let options: [CatalogOption]
        let rows: [EnrichedVariantRow]
    }

    private struct CategorySection: Identifiable {
        let id: String
        let title: String
        let tables: [FamilyTable]
    }

    private var familyTables: [FamilyTable] {
        let optionsByItemId = Dictionary(grouping: allOptions, by: \.catalogItemId)

        var grouped: [String: [EnrichedVariantRow]] = [:]
        var familyById: [String: CatalogItem] = [:]
        var orderedFamilyIds: [String] = []

        for row in rows {
            if grouped[row.family.id] == nil {
                orderedFamilyIds.append(row.family.id)
            }
            grouped[row.family.id, default: []].append(row)
            familyById[row.family.id] = row.family
        }

        return orderedFamilyIds.compactMap { id in
            guard let family = familyById[id], let rs = grouped[id] else { return nil }
            let options = (optionsByItemId[id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
            return FamilyTable(id: id, family: family, category: rs.first?.category, options: options, rows: rs)
        }
    }

    private var categorySections: [CategorySection] {
        let categoriesById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var grouped: [String: [FamilyTable]] = [:]
        var titles: [String: String] = [:]
        var orderedKeys: [String] = []

        for table in familyTables {
            let key = table.category?.id ?? "__uncategorized"
            if grouped[key] == nil {
                orderedKeys.append(key)
            }
            grouped[key, default: []].append(table)
            titles[key] = categoryTitle(table.category, categoriesById: categoriesById)
        }

        return orderedKeys.compactMap { key in
            guard let tables = grouped[key] else { return nil }
            return CategorySection(id: key, title: titles[key] ?? "UNCATEGORIZED", tables: tables)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                ForEach(categorySections) { section in
                    categorySectionView(section)
                }
                Color.clear.frame(height: 100) // FAB clearance
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
    }

    @ViewBuilder
    private func categorySectionView(_ section: CategorySection) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// \(section.title)")
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing1)

            ForEach(section.tables) { table in
                familyTableView(table)
            }
        }
    }

    @ViewBuilder
    private func familyTableView(_ table: FamilyTable) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Family name header — outside the horizontal scroll so it
            // stays visible regardless of how many option columns exist.
            Text("// \(table.family.name.uppercased())")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing2)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow(for: table)
                    ForEach(table.rows) { row in
                        Button {
                            onTap?(row)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            bodyRow(for: row, options: table.options)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .glassSurface()
    }

    @ViewBuilder
    private func headerRow(for table: FamilyTable) -> some View {
        HStack(spacing: 0) {
            cell("VARIANT", isHeader: true, width: 140, align: .leading)
            ForEach(table.options) { option in
                cell(option.name.uppercased(), isHeader: true, width: 100, align: .leading)
            }
            cell("QTY", isHeader: true, width: 80, align: .trailing)
            cell("THRESH", isHeader: true, width: 96, align: .trailing)
            cell("SKU", isHeader: true, width: 120, align: .leading)
        }
        .frame(height: 36)
        .background(OPSStyle.Colors.surfaceActive)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func bodyRow(for row: EnrichedVariantRow, options: [CatalogOption]) -> some View {
        // Map this variant's option values by option id so we can render
        // the correct cell under each header column.
        let valueByOptionId: [String: CatalogOptionValue] = Dictionary(
            uniqueKeysWithValues: row.optionPairs.map { ($0.option.id, $0.value) }
        )
        HStack(spacing: 0) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                if row.thresholdStatus != .normal {
                    Circle()
                        .fill(row.thresholdStatus.color)
                        .frame(
                            width: OPSStyle.Layout.Indicator.dotSM,
                            height: OPSStyle.Layout.Indicator.dotSM
                        )
                        .accessibilityHidden(true)
                }
                Text(row.variantLabel.isEmpty ? row.family.name : row.variantLabel)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(width: 140, alignment: .leading)

            ForEach(options) { option in
                Text(valueByOptionId[option.id]?.value ?? "—")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .frame(width: 100, alignment: .leading)
                    .lineLimit(1)
            }

            HStack(spacing: 2) {
                Text(quantityText(row))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(row.thresholdStatus.color)
                if let unit = row.unit?.display {
                    Text(unit)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(width: 80, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.thresholdPercentText)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(row.thresholdStatus.color)
                Text(row.thresholdDeltaText)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(width: 96, alignment: .trailing)

            Text(row.variant.sku ?? "—")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
        }
        .frame(height: OPSStyle.Layout.touchTargetMin)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func cell(_ text: String, isHeader: Bool, width: CGFloat, align: Alignment) -> some View {
        Text(text)
            .font(isHeader ? OPSStyle.Typography.category : OPSStyle.Typography.body)
            .foregroundColor(isHeader ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(width: width, alignment: align)
            .lineLimit(1)
    }

    private func quantityText(_ row: EnrichedVariantRow) -> String {
        StockNumberFormatter.quantity(row.variant.quantity)
    }

    private func categoryTitle(
        _ category: CatalogCategory?,
        categoriesById: [String: CatalogCategory]
    ) -> String {
        guard let category else { return "UNCATEGORIZED" }
        if let parentId = category.parentId, let parent = categoriesById[parentId] {
            return "\(parent.name.uppercased()) / \(category.name.uppercased())"
        }
        return category.name.uppercased()
    }
}
