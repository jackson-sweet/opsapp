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
    let onOpenDetail: (EnrichedVariantRow) -> Void

    var body: some View {
        Section {
            // Variants directly under the parent category (or under "Uncategorized").
            ForEach(parentRows) { row in
                rowButton(row, nested: false)
            }
            // Child categories with their variants nested.
            ForEach(children, id: \.category.id) { entry in
                childHeader(entry.category)
                ForEach(entry.rows) { row in
                    rowButton(row, nested: true)
                }
            }
        } header: {
            parentHeader
        }
    }

    @ViewBuilder
    private func rowButton(_ row: EnrichedVariantRow, nested: Bool) -> some View {
        Button { onTap(row) } label: {
            if nested {
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                    Rectangle()
                        .fill(OPSStyle.Colors.separator)
                        .frame(width: OPSStyle.Layout.Border.standard)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                    VariantCard(row: row, scale: 1.0)
                }
                .frame(maxWidth: .infinity)
            } else {
                VariantCard(row: row, scale: 1.0)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onOpenDetail(row)
            } label: {
                Label("Open Full Detail", systemImage: "arrow.up.right.square")
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
