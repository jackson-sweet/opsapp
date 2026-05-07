//
//  StockListView.swift
//  OPS
//
//  LIST view mode for the STOCK segment. Variant cards grouped by
//  category with pinned section headers. Supports two-level nesting
//  (parent category → child category → variants); variants on
//  uncategorized families fall under a synthetic "UNCATEGORIZED"
//  parent so nothing is hidden.
//

import SwiftUI

struct StockListView: View {
    let rows: [EnrichedVariantRow]
    var onTap: ((EnrichedVariantRow) -> Void)? = nil

    /// Build the (parent, parentRows, children) groupings used by the
    /// `LazyVStack` below. A row's parent is the row's category's parent,
    /// or the row's category itself when the category is top-level. Rows
    /// without a category land in the synthetic "uncategorized" bucket.
    private struct Group: Identifiable {
        let id: String
        let parent: CatalogCategory?
        let parentRows: [EnrichedVariantRow]
        let children: [(category: CatalogCategory, rows: [EnrichedVariantRow])]
    }

    private var groups: [Group] {
        var byParentId: [String: (category: CatalogCategory?, rows: [EnrichedVariantRow], childRows: [String: [EnrichedVariantRow]], childById: [String: CatalogCategory])] = [:]

        for row in rows {
            if let category = row.category {
                if let parentId = category.parentId {
                    // Row is on a child category.
                    let key = parentId
                    var entry = byParentId[key] ?? (category: nil, rows: [], childRows: [:], childById: [:])
                    var bucket = entry.childRows[category.id] ?? []
                    bucket.append(row)
                    entry.childRows[category.id] = bucket
                    entry.childById[category.id] = category
                    byParentId[key] = entry
                } else {
                    // Row is directly on a parent (top-level) category.
                    let key = category.id
                    var entry = byParentId[key] ?? (category: category, rows: [], childRows: [:], childById: [:])
                    entry.category = category
                    entry.rows.append(row)
                    byParentId[key] = entry
                }
            } else {
                // Uncategorized row.
                let key = "__uncategorized__"
                var entry = byParentId[key] ?? (category: nil, rows: [], childRows: [:], childById: [:])
                entry.rows.append(row)
                byParentId[key] = entry
            }
        }

        // Build ordered Group structs. Parent name drives sort; uncategorized last.
        let sortedKeys = byParentId.keys.sorted { lhs, rhs in
            if lhs == "__uncategorized__" { return false }
            if rhs == "__uncategorized__" { return true }
            let lhsName = byParentId[lhs]?.category?.name ?? ""
            let rhsName = byParentId[rhs]?.category?.name ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        return sortedKeys.compactMap { key in
            guard let entry = byParentId[key] else { return nil }
            let children = entry.childRows
                .map { (childId, rows) -> (category: CatalogCategory, rows: [EnrichedVariantRow]) in
                    (category: entry.childById[childId]!, rows: rows.sorted { $0.family.name < $1.family.name })
                }
                .sorted { $0.category.name.localizedCaseInsensitiveCompare($1.category.name) == .orderedAscending }
            return Group(
                id: key,
                parent: entry.category,
                parentRows: entry.rows.sorted { $0.family.name < $1.family.name },
                children: children
            )
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: OPSStyle.Layout.spacing2, pinnedViews: .sectionHeaders) {
                ForEach(groups) { group in
                    CategoryGroupSection(
                        parent: group.parent,
                        parentRows: group.parentRows,
                        children: group.children,
                        onTap: { row in
                            onTap?(row)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    )
                }
                Color.clear.frame(height: 100) // FAB clearance
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
    }
}
