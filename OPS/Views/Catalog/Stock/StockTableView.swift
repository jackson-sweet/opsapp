//
//  StockTableView.swift
//  OPS
//
//  TABLE is the family audit mode. Identity, on-hand quantity, and threshold
//  delta remain pinned while only the family-specific option band scrolls.
//  Accessibility text sizes switch to fully labeled stacked rows.
//

import SwiftUI

enum StockTablePresentation: Equatable {
    case pinnedAuditColumns
    case stackedRows
}

enum StockTableLayout {
    static func presentation(isAccessibilitySize: Bool) -> StockTablePresentation {
        isAccessibilitySize ? .stackedRows : .pinnedAuditColumns
    }
}

enum StockTableOptionBandLayout: Equatable {
    case empty
    case fitted
    case scrolling

    static func resolve(optionCount: Int) -> StockTableOptionBandLayout {
        switch optionCount {
        case ...0: return .empty
        case 1...2: return .fitted
        default: return .scrolling
        }
    }

    static func visibleColumnCount(optionCount: Int) -> Int {
        optionCount <= 1 ? 1 : 2
    }

    static func scrollingColumnWidth(viewportWidth: CGFloat) -> CGFloat {
        let widthWithTrailingPeek = (viewportWidth - OPSStyle.Layout.spacing3) / 2
        return min(
            OPSStyle.Layout.touchTargetMin * 2,
            max(OPSStyle.Layout.touchTargetMin, widthWithTrailingPeek)
        )
    }
}

enum StockTableThresholdKind: Equatable {
    case warning
    case critical

    var compactLabel: String {
        switch self {
        case .warning: return "WARN"
        case .critical: return "CRIT"
        }
    }

    var comparisonLabel: String { "VS \(compactLabel)" }

    var accessibilityName: String {
        switch self {
        case .warning: return "warning"
        case .critical: return "critical"
        }
    }
}

struct StockTableThresholdReference: Equatable {
    let kind: StockTableThresholdKind
    let value: Double

    static func resolve(warning: Double?, critical: Double?) -> StockTableThresholdReference? {
        if let warning, warning > 0 {
            return StockTableThresholdReference(kind: .warning, value: warning)
        }
        if let critical, critical > 0 {
            return StockTableThresholdReference(kind: .critical, value: critical)
        }
        return nil
    }

    static func resolve(for row: EnrichedVariantRow) -> StockTableThresholdReference? {
        resolve(warning: row.effectiveWarning, critical: row.effectiveCritical)
    }
}

enum StockTableAccessibility {
    static func quantityText(_ row: EnrichedVariantRow) -> String {
        let quantity = StockNumberFormatter.quantity(row.variant.quantity)
        guard let unit = row.unit?.display else { return quantity }
        return "\(quantity) \(unit)"
    }

    static func rowLabel(_ row: EnrichedVariantRow) -> String {
        var parts = [row.variantDisplayName]
        if let sku = row.variant.sku, !sku.isEmpty { parts.append("SKU \(sku)") }
        parts.append("\(quantityText(row)) on hand")
        if let reference = StockTableThresholdReference.resolve(for: row) {
            let limit = StockNumberFormatter.quantity(reference.value)
            parts.append("\(row.thresholdDeltaText) versus \(reference.kind.accessibilityName) limit \(limit)")
        }
        if let status = row.thresholdStatus.label { parts.append(status.lowercased()) }
        return parts.joined(separator: ", ")
    }
}

struct StockTableView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let rows: [EnrichedVariantRow]
    let allOptions: [CatalogOption]
    var onTap: ((EnrichedVariantRow) -> Void)? = nil

    @State private var selectedFamilyId: String?

    private let referenceColumnWidth = OPSStyle.Layout.touchTargetLarge + OPSStyle.Layout.spacing5
    private let quantityColumnWidth = OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing2
    private let deltaColumnWidth = OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing2

    private struct FamilyTable: Identifiable {
        let id: String
        let family: CatalogItem
        let category: CatalogCategory?
        let options: [CatalogOption]
        let rows: [EnrichedVariantRow]
    }

    private var familyTables: [FamilyTable] {
        let optionsByFamily = Dictionary(grouping: allOptions, by: \.catalogItemId)
        var rowsByFamily: [String: [EnrichedVariantRow]] = [:]
        var familyById: [String: CatalogItem] = [:]

        for row in rows {
            rowsByFamily[row.family.id, default: []].append(row)
            familyById[row.family.id] = row.family
        }

        return rowsByFamily.keys.compactMap { familyId in
            guard let family = familyById[familyId], let familyRows = rowsByFamily[familyId] else { return nil }
            return FamilyTable(
                id: familyId,
                family: family,
                category: familyRows.first?.category,
                options: (optionsByFamily[familyId] ?? []).sorted { $0.sortOrder < $1.sortOrder },
                rows: familyRows
            )
        }
        .sorted {
            $0.family.name.localizedCaseInsensitiveCompare($1.family.name) == .orderedAscending
        }
    }

    private var activeFamilyId: String? {
        StockTableSelection.resolve(
            current: selectedFamilyId,
            available: familyTables.map(\.id)
        )
    }

    private var activeTable: FamilyTable? {
        guard let activeFamilyId else { return nil }
        return familyTables.first { $0.id == activeFamilyId }
    }

    private var presentation: StockTablePresentation {
        StockTableLayout.presentation(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let table = activeTable {
                familySelector(table)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing1)
                    .padding(.bottom, OPSStyle.Layout.spacing2)

                ScrollView {
                    switch presentation {
                    case .pinnedAuditColumns:
                        pinnedComparison(table)
                    case .stackedRows:
                        stackedComparison(table)
                    }

                    Color.clear.frame(height: OPSStyle.Layout.spacing5)
                }
            }
        }
    }

    private func familySelector(_ table: FamilyTable) -> some View {
        Menu {
            ForEach(familyTables) { candidate in
                Button {
                    selectedFamilyId = candidate.id
                } label: {
                    StockMenuOptionLabel(
                        title: candidate.family.name,
                        isSelected: candidate.id == table.id
                    )
                }
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(table.family.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(selectorMetadata(table))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: OPSStyle.Layout.spacing2)
                Text("\(table.rows.count)")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .monospacedDigit()
                Image(systemName: OPSStyle.Icons.chevronDown)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .accessibilityLabel("Compare family")
        .accessibilityValue(table.family.name)
        .accessibilityIdentifier("catalog.stock.compare.family")
    }

    private func selectorMetadata(_ table: FamilyTable) -> String {
        let variantLabel = table.rows.count == 1 ? "1 VARIANT" : "\(table.rows.count) VARIANTS"
        guard let category = table.category?.name else { return variantLabel }
        return "\(category.uppercased()) · \(variantLabel)"
    }

    // MARK: - Pinned audit matrix

    private func pinnedComparison(_ table: FamilyTable) -> some View {
        HStack(alignment: .top, spacing: 0) {
            referenceColumn(table)

            optionBand(table)

            quantityColumn(table)
            deltaColumn(table)
        }
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .accessibilityIdentifier("catalog.stock.compare.pinned-matrix")
    }

    @ViewBuilder
    private func optionBand(_ table: FamilyTable) -> some View {
        let layout = StockTableOptionBandLayout.resolve(optionCount: table.options.count)

        switch layout {
        case .empty:
            Color.clear
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

        case .fitted:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(table.options) { option in
                        optionColumn(option, table: table, width: nil)
                            .containerRelativeFrame(
                                .horizontal,
                                count: StockTableOptionBandLayout.visibleColumnCount(
                                    optionCount: table.options.count
                                ),
                                span: 1,
                                spacing: 0
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .scrollDisabled(true)
            .accessibilityLabel("Variant option columns")

        case .scrolling:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(table.options) { option in
                        optionColumn(option, table: table, width: nil)
                            .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in
                                StockTableOptionBandLayout.scrollingColumnWidth(
                                    viewportWidth: length
                                )
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Variant option columns")
        }
    }

    private func referenceColumn(_ table: FamilyTable) -> some View {
        VStack(spacing: 0) {
            headerCell("REFERENCE", width: referenceColumnWidth, alignment: .leading)
            ForEach(table.rows) { row in
                Button { select(row) } label: {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text(referenceText(row))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)
                        if let status = row.thresholdStatus.label {
                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                Circle()
                                    .fill(row.thresholdStatus.color)
                                    .frame(
                                        width: OPSStyle.Layout.Indicator.dotSM,
                                        height: OPSStyle.Layout.Indicator.dotSM
                                    )
                                    .accessibilityHidden(true)
                                Text(status)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(row.thresholdStatus.textColor)
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .frame(width: referenceColumnWidth, height: OPSStyle.Layout.touchTargetStandard, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(rowDivider, alignment: .bottom)
                .accessibilityLabel(rowAccessibilityLabel(row))
                .accessibilityIdentifier("catalog.stock.compare.row.\(row.id)")
            }
        }
        .overlay(columnDivider, alignment: .trailing)
    }

    private func optionColumn(_ option: CatalogOption, table: FamilyTable, width: CGFloat?) -> some View {
        VStack(spacing: 0) {
            headerCell(option.name.uppercased(), width: width, alignment: .leading)
            ForEach(table.rows) { row in
                Button { select(row) } label: {
                    Text(optionValue(for: option, in: row))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .padding(.horizontal, OPSStyle.Layout.spacing1)
                        .frame(width: width, height: OPSStyle.Layout.touchTargetStandard, alignment: .leading)
                        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(rowDivider, alignment: .bottom)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .overlay(columnDivider, alignment: .trailing)
    }

    private func quantityColumn(_ table: FamilyTable) -> some View {
        VStack(spacing: 0) {
            headerCell("ON HAND", width: quantityColumnWidth, alignment: .trailing)
            ForEach(table.rows) { row in
                Button { select(row) } label: {
                    HStack(alignment: .lastTextBaseline, spacing: OPSStyle.Layout.spacing1) {
                        Text(StockNumberFormatter.quantity(row.variant.quantity))
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(row.thresholdStatus.textColor)
                            .monospacedDigit()
                        if let unit = row.unit?.display {
                            Text(unit)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.text3)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .frame(width: quantityColumnWidth, height: OPSStyle.Layout.touchTargetStandard, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(rowDivider, alignment: .bottom)
                .accessibilityHidden(true)
            }
        }
        .overlay(columnDivider, alignment: .leading)
    }

    private func deltaColumn(_ table: FamilyTable) -> some View {
        VStack(spacing: 0) {
            headerCell("VS\nLIMIT", width: deltaColumnWidth, alignment: .trailing)
            ForEach(table.rows) { row in
                Button { select(row) } label: {
                    VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing1) {
                        Text(row.thresholdDeltaText)
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(row.thresholdStatus.textColor)
                            .monospacedDigit()
                        if let reference = StockTableThresholdReference.resolve(for: row) {
                            Text(reference.kind.compactLabel)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.text3)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .frame(width: deltaColumnWidth, height: OPSStyle.Layout.touchTargetStandard, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(rowDivider, alignment: .bottom)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Accessibility-size rows

    private func stackedComparison(_ table: FamilyTable) -> some View {
        LazyVStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(table.rows) { row in
                Button { select(row) } label: {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                            Text(referenceText(row))
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.text)
                            Spacer(minLength: OPSStyle.Layout.spacing2)
                            if let status = row.thresholdStatus.label {
                                Text(status)
                                    .font(OPSStyle.Typography.metadata)
                                    .foregroundColor(row.thresholdStatus.textColor)
                            }
                        }

                        ForEach(table.options) { option in
                            labeledValue(option.name.uppercased(), value: optionValue(for: option, in: row))
                        }

                        Divider().background(OPSStyle.Colors.separator)

                        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
                            labeledValue("ON HAND", value: quantityText(row), color: row.thresholdStatus.textColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            labeledValue(
                                StockTableThresholdReference.resolve(for: row)?.kind.comparisonLabel ?? "VS LIMIT",
                                value: row.thresholdDeltaText,
                                color: row.thresholdStatus.textColor
                            )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                            .fill(OPSStyle.Colors.surfaceInput)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowAccessibilityLabel(row))
                .accessibilityIdentifier("catalog.stock.compare.stacked-row.\(row.id)")
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .accessibilityIdentifier("catalog.stock.compare.stacked")
    }

    private func labeledValue(
        _ label: String,
        value: String,
        color: Color = OPSStyle.Colors.text2
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.text3)
            Text(value)
                .font(OPSStyle.Typography.body)
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shared cells

    private func headerCell(_ text: String, width: CGFloat?, alignment: Alignment) -> some View {
        Text(text)
            .font(OPSStyle.Typography.category)
            .foregroundColor(OPSStyle.Colors.text3)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(minHeight: OPSStyle.Layout.chipMinHeight)
            .lineLimit(2)
            .background(OPSStyle.Colors.surfaceActive)
            .overlay(rowDivider, alignment: .bottom)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.separator)
            .frame(height: OPSStyle.Layout.Border.standard)
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.separator)
            .frame(width: OPSStyle.Layout.Border.standard)
    }

    private func select(_ row: EnrichedVariantRow) {
        onTap?(row)
    }

    private func optionValue(for option: CatalogOption, in row: EnrichedVariantRow) -> String {
        row.optionPairs.first(where: { $0.option.id == option.id })?.value.value ?? "—"
    }

    private func referenceText(_ row: EnrichedVariantRow) -> String {
        if let sku = row.variant.sku, !sku.isEmpty { return sku }
        if !row.variantLabel.isEmpty { return row.variantLabel }
        return row.family.name
    }

    private func quantityText(_ row: EnrichedVariantRow) -> String {
        StockTableAccessibility.quantityText(row)
    }

    private func rowAccessibilityLabel(_ row: EnrichedVariantRow) -> String {
        StockTableAccessibility.rowLabel(row)
    }
}
