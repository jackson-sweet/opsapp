//
//  CategoryGroupSection.swift
//  OPS
//
//  Section view used by `StockListView` to group variants by category
//  with two-level nesting (parent → child → variants). Compact headers
//  preserve hierarchy without adding a card shell per stock item.
//

import SwiftUI

struct CategoryGroupSection: View {
    let parent: CatalogCategory?
    let parentRows: [EnrichedVariantRow]
    let children: [(category: CatalogCategory, rows: [EnrichedVariantRow])]
    let onTap: (EnrichedVariantRow) -> Void
    let onOpenDetail: (EnrichedVariantRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            parentHeader

            VStack(spacing: 0) {
                ForEach(Array(parentRows.enumerated()), id: \.element.id) { index, row in
                    rowButton(row)
                    if index < parentRows.count - 1 || !children.isEmpty {
                        rowDivider
                    }
                }

                ForEach(Array(children.enumerated()), id: \.element.category.id) { childIndex, entry in
                    childHeader(entry.category, count: entry.rows.count)
                    ForEach(Array(entry.rows.enumerated()), id: \.element.id) { rowIndex, row in
                        rowButton(row)
                        if rowIndex < entry.rows.count - 1 || childIndex < children.count - 1 {
                            rowDivider
                        }
                    }
                }
            }
            .glassSurface()
        }
    }

    private func rowButton(_ row: EnrichedVariantRow) -> some View {
        Button { onTap(row) } label: {
            StockListRow(row: row)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onOpenDetail(row)
            } label: {
                Label("OPEN FULL DETAIL", systemImage: OPSStyle.Icons.openDetail)
            }
        }
    }

    private var parentHeader: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(parent.map { "// \($0.name.uppercased())" } ?? "// UNCATEGORIZED")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            Text("\(totalCount)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing1)
        .frame(minHeight: OPSStyle.Layout.chipMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.background)
    }

    private func childHeader(_ category: CatalogCategory, count: Int) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(category.name.uppercased())
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text("\(count)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.chipMinHeight)
        .background(OPSStyle.Colors.surfaceActive)
    }

    private var rowDivider: some View {
        Divider()
            .background(OPSStyle.Colors.separator)
            .padding(.leading, OPSStyle.Layout.spacing5)
    }

    private var totalCount: Int {
        parentRows.count + children.reduce(0) { $0 + $1.rows.count }
    }
}
