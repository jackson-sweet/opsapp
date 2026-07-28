//
//  StockListView.swift
//  OPS
//
//  LIST view mode for the STOCK segment. Variants render as a dense
//  operational register, with optional category grouping. Supports two-level nesting
//  (parent category → child category → variants); variants on
//  uncategorized families fall under a synthetic "UNCATEGORIZED"
//  parent so nothing is hidden.
//

import SwiftUI

struct StockListView: View {
    let rows: [EnrichedVariantRow]
    /// All categories the user can see, used to resolve a child's parent
    /// even when the parent has no rows of its own. Without this, child-only
    /// parents (e.g. "Hardware" / "Fasteners" with rows only under their
    /// children) rendered with a nil parent and the header collapsed to
    /// "UNCATEGORIZED" (bug 9a4bcfae).
    let categories: [CatalogCategory]
    /// Category grouping is itself a sort mode. Other sorts remain globally
    /// ordered instead of being silently regrouped and re-sorted by family.
    let groupByCategory: Bool
    var onTap: ((EnrichedVariantRow) -> Void)? = nil
    var onOpenDetail: ((EnrichedVariantRow) -> Void)? = nil

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
        let categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        var byParentId: [String: (category: CatalogCategory?, rows: [EnrichedVariantRow], childRows: [String: [EnrichedVariantRow]], childById: [String: CatalogCategory])] = [:]

        for row in rows {
            if let category = row.category {
                if let parentId = category.parentId {
                    // Row is on a child category. Resolve the parent up front
                    // from `categoryById` — relying on a row also being
                    // directly on the parent leaves parents with only nested
                    // rows nameless.
                    let key = parentId
                    let resolvedParent = categoryById[parentId]
                    var entry = byParentId[key] ?? (category: resolvedParent, rows: [], childRows: [:], childById: [:])
                    if entry.category == nil { entry.category = resolvedParent }
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

        // Build ordered Group structs. The explicit category order drives sort;
        // names break ties and uncategorized remains last.
        let sortedKeys = byParentId.keys.sorted { lhs, rhs in
            if lhs == "__uncategorized__" { return false }
            if rhs == "__uncategorized__" { return true }
            let lhsCategory = byParentId[lhs]?.category ?? categoryById[lhs]
            let rhsCategory = byParentId[rhs]?.category ?? categoryById[rhs]
            if lhsCategory?.sortOrder != rhsCategory?.sortOrder {
                return (lhsCategory?.sortOrder ?? .max) < (rhsCategory?.sortOrder ?? .max)
            }
            let lhsName = lhsCategory?.name ?? ""
            let rhsName = rhsCategory?.name ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        return sortedKeys.compactMap { key in
            guard let entry = byParentId[key] else { return nil }
            // Fall back to the resolved category when the entry was created
            // for a parent that only has children-with-rows. The categoryById
            // lookup is the source of truth for parent names.
            let parent = entry.category ?? categoryById[key]
            let children = entry.childRows
                .map { (childId, rows) -> (category: CatalogCategory, rows: [EnrichedVariantRow]) in
                    (category: entry.childById[childId]!, rows: rows)
                }
                .sorted {
                    if $0.category.sortOrder != $1.category.sortOrder {
                        return $0.category.sortOrder < $1.category.sortOrder
                    }
                    return $0.category.name.localizedCaseInsensitiveCompare($1.category.name) == .orderedAscending
                }
            return Group(
                id: key,
                parent: parent,
                parentRows: entry.rows,
                children: children
            )
        }
    }

    var body: some View {
        ScrollView {
            if groupByCategory {
                LazyVStack(spacing: OPSStyle.Layout.spacing3) {
                    ForEach(groups) { group in
                        CategoryGroupSection(
                            parent: group.parent,
                            parentRows: group.parentRows,
                            children: group.children,
                            onTap: handleTap,
                            onOpenDetail: handleOpenDetail
                        )
                    }
                    Color.clear.frame(height: OPSStyle.Layout.spacing5)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing1)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowButton(row)
                        if index < rows.count - 1 {
                            Divider()
                                .background(OPSStyle.Colors.separator)
                                .padding(.leading, OPSStyle.Layout.spacing5)
                        }
                    }
                }
                .glassSurface()
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing1)

                Color.clear.frame(height: OPSStyle.Layout.spacing5)
            }
        }
    }

    private func handleTap(_ row: EnrichedVariantRow) {
        onTap?(row)
    }

    private func handleOpenDetail(_ row: EnrichedVariantRow) {
        onOpenDetail?(row)
    }

    private func rowButton(_ row: EnrichedVariantRow) -> some View {
        Button { handleTap(row) } label: {
            StockListRow(row: row)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { handleOpenDetail(row) } label: {
                Label("OPEN FULL DETAIL", systemImage: OPSStyle.Icons.openDetail)
            }
        }
    }
}
