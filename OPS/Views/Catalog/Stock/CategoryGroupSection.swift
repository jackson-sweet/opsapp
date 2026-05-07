//
//  CategoryGroupSection.swift
//  OPS
//
//  Section view used by `StockListView` to group variants by category
//  with two-level nesting (parent → child → variants). Pinned section
//  headers keep the active category visible during scroll.
//

import SwiftUI

struct CategoryGroupSection: View {
    let parent: CatalogCategory?
    let parentRows: [EnrichedVariantRow]
    let children: [(category: CatalogCategory, rows: [EnrichedVariantRow])]
    let onTap: (EnrichedVariantRow) -> Void

    var body: some View {
        Section {
            // Variants directly under the parent category (or under "Uncategorized").
            ForEach(parentRows) { row in
                Button { onTap(row) } label: {
                    VariantCard(row: row, scale: 1.0)
                }
                .buttonStyle(.plain)
            }
            // Child categories with their variants nested.
            ForEach(children, id: \.category.id) { entry in
                childHeader(entry.category)
                ForEach(entry.rows) { row in
                    Button { onTap(row) } label: {
                        VariantCard(row: row, scale: 1.0)
                            .padding(.leading, OPSStyle.Layout.spacing3)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            parentHeader
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
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.background)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func childHeader(_ category: CatalogCategory) -> some View {
        Text(category.name)
            .font(OPSStyle.Typography.category)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
            .padding(.bottom, OPSStyle.Layout.spacing1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalCount: Int {
        parentRows.count + children.reduce(0) { $0 + $1.rows.count }
    }
}
