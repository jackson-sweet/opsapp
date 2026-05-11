//
//  InventoryTableView.swift
//  OPS
//
//  TABLE view mode for Inventory (feature 217c3d1f). Rows are items;
//  columns enumerate the company's tags ("BLACK", "WHITE", etc.) plus
//  fixed QTY / UNIT / SKU columns. A cell under a tag column shows a
//  filled bullet when the row carries that tag — turning the spreadsheet
//  "column for black / column for white" layout into a single scroll.
//
//  The full table scrolls horizontally so any tag-count fits without
//  squeezing the name column. Rows stay tappable (open quantity
//  adjustment) and threshold status colors the quantity cell.
//

import SwiftUI

struct InventoryTableView: View {
    let items: [InventoryItem]
    let tags: [InventoryTag]
    var onTap: ((InventoryItem) -> Void)? = nil

    /// Tag columns, sorted alphabetically for predictable layout. Filters
    /// out soft-deleted tags so they don't reserve a column.
    private var tagColumns: [InventoryTag] {
        tags
            .filter { $0.deletedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private let nameColumnWidth: CGFloat = 180
    private let tagColumnWidth: CGFloat = 64
    private let qtyColumnWidth: CGFloat = 70
    private let unitColumnWidth: CGFloat = 56
    private let skuColumnWidth: CGFloat = 110

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    ForEach(items) { item in
                        Button {
                            onTap?(item)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            bodyRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )

            HStack {
                Spacer()
                Text("[ \(items.count) ITEM\(items.count == 1 ? "" : "S") ]")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .padding(.top, OPSStyle.Layout.spacing2)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            cell("ITEM", width: nameColumnWidth, align: .leading, isHeader: true)
            ForEach(tagColumns) { tag in
                cell(tag.name.uppercased(), width: tagColumnWidth, align: .center, isHeader: true)
            }
            cell("QTY", width: qtyColumnWidth, align: .trailing, isHeader: true)
            cell("UNIT", width: unitColumnWidth, align: .leading, isHeader: true)
            cell("SKU", width: skuColumnWidth, align: .leading, isHeader: true)
        }
        .frame(height: 36)
        .background(OPSStyle.Colors.subtleBackground)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Body row

    @ViewBuilder
    private func bodyRow(_ item: InventoryItem) -> some View {
        let status = item.effectiveThresholdStatus()
        let tagIdSet = Set(item.tagIds)

        HStack(spacing: 0) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                if status != .normal {
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(item.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(width: nameColumnWidth, alignment: .leading)

            ForEach(tagColumns) { tag in
                HStack {
                    Spacer()
                    if tagIdSet.contains(tag.id) {
                        Circle()
                            .fill(OPSStyle.Colors.primaryText)
                            .frame(width: 8, height: 8)
                    } else {
                        Text("—")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.5))
                    }
                    Spacer()
                }
                .frame(width: tagColumnWidth)
            }

            Text(formatQuantity(item.quantity))
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(status.color)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(width: qtyColumnWidth, alignment: .trailing)

            Text(item.unit?.display ?? "—")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(width: unitColumnWidth, alignment: .leading)
                .lineLimit(1)

            Text(item.sku ?? "—")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(width: skuColumnWidth, alignment: .leading)
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

    // MARK: - Cell helper

    @ViewBuilder
    private func cell(_ text: String, width: CGFloat, align: Alignment, isHeader: Bool) -> some View {
        Text(text)
            .font(isHeader ? OPSStyle.Typography.category : OPSStyle.Typography.body)
            .foregroundColor(isHeader ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(width: width, alignment: align)
            .lineLimit(1)
    }

    private func formatQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }
}
