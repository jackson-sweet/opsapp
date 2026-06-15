//
//  StockView.swift
//  OPS
//
//  STOCK segment of the CATALOG tab. Variant-aware shell with three view
//  modes (LIST / GRID / TABLE), three filter chips (category / tag /
//  threshold), and a threshold banner that surfaces when any variant has
//  fallen below its effective warning or critical level.
//
//  All view modes consume the same `EnrichedVariantRow` collection — a
//  variant joined to its family, category, unit, tag IDs, and option
//  values — so each mode can render the same data with its own emphasis.
//

import SwiftUI
import SwiftData

// MARK: - View modes

enum StockViewMode: String, CaseIterable, Identifiable {
    case list = "LIST"
    case grid = "GRID"
    case table = "TABLE"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .list:  return "list.bullet"
        case .grid:  return "square.grid.2x2"
        case .table: return "tablecells"
        }
    }
}

// MARK: - Threshold filter

enum ThresholdFilter: String, CaseIterable, Identifiable {
    case all = "ALL"
    case warning = "WARNING+"
    case critical = "CRITICAL"
    var id: String { rawValue }
}

// MARK: - Stock sort

enum StockSortMode: String, CaseIterable, Identifiable {
    case category = "CATEGORY"
    case family = "FAMILY"
    case lowStock = "LOW STOCK"
    case quantity = "QUANTITY"

    var id: String { rawValue }
}

// MARK: - Option filters

struct StockOptionFilterValue: Identifiable, Hashable {
    let key: String
    let display: String
    var id: String { key }
}

struct StockOptionFilterAxis: Identifiable, Hashable {
    let key: String
    let display: String
    let values: [StockOptionFilterValue]
    var id: String { key }
}

// MARK: - Enriched row

/// A single variant joined with everything the view modes need to render
/// it without re-querying SwiftData per cell. Built once per parent body
/// computation by `StockView`.
struct EnrichedVariantRow: Identifiable, Hashable {
    let variant: CatalogVariant
    let family: CatalogItem
    let category: CatalogCategory?
    let unit: CatalogUnit?
    let tagIds: Set<String>
    /// Ordered list of (option, optionValue) tuples for this variant, sorted by option sortOrder.
    /// Used by TABLE mode for column rendering and by LIST/GRID for the variant label.
    let optionPairs: [(option: CatalogOption, value: CatalogOptionValue)]

    var id: String { variant.id }

    /// Variant label like "Black · Topmount". Empty when the family has
    /// no options (single-variant family).
    var variantLabel: String {
        optionPairs.map(\.value.value).joined(separator: " · ")
    }

    /// Full field-facing identity. SKU stays available as metadata, but the
    /// primary name is family + option values because live catalog schema
    /// has no variant-name column.
    var variantDisplayName: String {
        guard !variantLabel.isEmpty else { return family.name }
        return "\(family.name) · \(variantLabel)"
    }

    /// Effective thresholds: variant override → family default → category default.
    var effectiveWarning: Double? {
        variant.warningThreshold ?? family.defaultWarningThreshold ?? category?.defaultWarningThreshold
    }

    var effectiveCritical: Double? {
        variant.criticalThreshold ?? family.defaultCriticalThreshold ?? category?.defaultCriticalThreshold
    }

    var thresholdStatus: ThresholdStatus {
        if let critical = effectiveCritical, variant.quantity <= critical { return .critical }
        if let warning = effectiveWarning, variant.quantity <= warning { return .warning }
        return .normal
    }

    /// Primary reference for stock proximity. Warning is preferred because it
    /// represents the reorder line; critical is the fallback when only the
    /// emergency line is configured.
    var thresholdReference: Double? {
        if let warning = effectiveWarning, warning > 0 { return warning }
        if let critical = effectiveCritical, critical > 0 { return critical }
        return nil
    }

    var thresholdRatio: Double? {
        guard let reference = thresholdReference, reference > 0 else { return nil }
        return variant.quantity / reference
    }

    var thresholdPercentText: String {
        guard let ratio = thresholdRatio else { return "—" }
        return "\(Int((ratio * 100).rounded()))%"
    }

    var thresholdDeltaText: String {
        guard let reference = thresholdReference else { return "—" }
        let delta = variant.quantity - reference
        let formatted = StockNumberFormatter.quantity(abs(delta))
        if delta == 0 { return "0" }
        return delta > 0 ? "+\(formatted)" : "-\(formatted)"
    }

    var searchText: String {
        ([family.name, family.itemDescription, category?.name, variant.sku, unit?.display, unit?.abbreviation, variantLabel, variantDisplayName]
            + optionPairs.flatMap { [$0.option.name, $0.value.value] })
            .compactMap { $0 }
            .joined(separator: " ")
    }

    static func == (lhs: EnrichedVariantRow, rhs: EnrichedVariantRow) -> Bool {
        lhs.variant.id == rhs.variant.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(variant.id)
    }
}

// MARK: - StockView

struct StockView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @AppStorage("catalog.stock.viewMode") private var viewModeRaw: String = StockViewMode.list.rawValue
    @AppStorage("catalog.stock.sortMode") private var sortModeRaw: String = StockSortMode.family.rawValue

    @State private var selectedCategoryId: String? = nil
    @State private var selectedTagId: String? = nil
    @State private var thresholdFilter: ThresholdFilter = .all
    @State private var selectedOptionValueKeys: [String: String] = [:]
    @State private var selectedRow: EnrichedVariantRow? = nil

    @Query private var allVariants: [CatalogVariant]
    @Query private var allFamilies: [CatalogItem]
    @Query private var allCategories: [CatalogCategory]
    @Query private var allUnits: [CatalogUnit]
    @Query private var allTags: [CatalogTag]
    @Query private var allItemTags: [CatalogItemTag]
    @Query private var allOptions: [CatalogOption]
    @Query private var allOptionValues: [CatalogOptionValue]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var viewMode: StockViewMode {
        StockViewMode(rawValue: viewModeRaw) ?? .list
    }

    private func setViewMode(_ mode: StockViewMode) {
        viewModeRaw = mode.rawValue
    }

    private var sortMode: StockSortMode {
        StockSortMode(rawValue: sortModeRaw) ?? .family
    }

    private func setSortMode(_ mode: StockSortMode) {
        sortModeRaw = mode.rawValue
    }

    // MARK: - Filter source data

    private var companyCategories: [CatalogCategory] {
        allCategories
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var companyTags: [CatalogTag] {
        allTags
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: - Enriched rows

    /// Build all `EnrichedVariantRow`s for the company, optionally applying
    /// the active filter chips. Recomputed every body — cheap on small
    /// stock lists; can be memoized if profiling shows it matters.
    func enrichedVariants(applyFilters: Bool) -> [EnrichedVariantRow] {
        let categoriesById = Dictionary(uniqueKeysWithValues: companyCategories.map { ($0.id, $0) })
        let unitsById = Dictionary(uniqueKeysWithValues: allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .map { ($0.id, $0) })
        let familiesById = Dictionary(uniqueKeysWithValues: allFamilies
            .filter { $0.companyId == companyId && $0.deletedAt == nil && $0.isActive }
            .map { ($0.id, $0) })

        let optionsByItemId = Dictionary(grouping: allOptions, by: \.catalogItemId)
        let optionValuesById = Dictionary(uniqueKeysWithValues: allOptionValues.map { ($0.id, $0) })

        let variantOptionValuesByVariantId = Dictionary(grouping: allVariantOptionValues, by: \.variantId)
        let tagIdsByItemId = Dictionary(grouping: allItemTags, by: \.catalogItemId)
            .mapValues { Set($0.map(\.tagId)) }

        let companyVariants = allVariants.filter {
            $0.companyId == companyId && $0.deletedAt == nil && $0.isActive
        }

        let rows: [EnrichedVariantRow] = companyVariants.compactMap { variant in
            guard let family = familiesById[variant.catalogItemId] else { return nil }
            let category = family.categoryId.flatMap { categoriesById[$0] }
            let unit = (variant.unitId ?? family.defaultUnitId).flatMap { unitsById[$0] }
            let tagIds = tagIdsByItemId[family.id] ?? []

            // Build ordered option-value pairs for this variant.
            let familyOptions = (optionsByItemId[family.id] ?? [])
                .sorted { $0.sortOrder < $1.sortOrder }
            let variantOptionValueIds = Set((variantOptionValuesByVariantId[variant.id] ?? [])
                .map(\.optionValueId))
            var optionPairs: [(option: CatalogOption, value: CatalogOptionValue)] = []
            for option in familyOptions {
                if let pair = variantOptionValueIds
                    .compactMap({ optionValuesById[$0] })
                    .first(where: { $0.optionId == option.id }) {
                    optionPairs.append((option: option, value: pair))
                }
            }

            return EnrichedVariantRow(
                variant: variant,
                family: family,
                category: category,
                unit: unit,
                tagIds: tagIds,
                optionPairs: optionPairs
            )
        }

        guard applyFilters else { return rows }

        let filtered = rows.filter { row in
            // Category filter — variant matches if family's category matches.
            if let cid = selectedCategoryId, row.category?.id != cid { return false }
            // Tag filter — variant matches if family carries the tag.
            if let tid = selectedTagId, !row.tagIds.contains(tid) { return false }
            // Attribute filters — variant matches if each selected option axis
            // has a value with the same normalized text. Option/value ids are
            // family-scoped, so text is the cross-family source of truth here.
            if !StockAttributeFiltering.matches(row, selectedValueKeys: selectedOptionValueKeys) { return false }
            // Threshold filter.
            switch thresholdFilter {
            case .all: break
            case .warning: if row.thresholdStatus == .normal { return false }
            case .critical: if row.thresholdStatus != .critical { return false }
            }
            return true
        }

        return StockRowOrdering.sorted(filtered, mode: sortMode)
    }

    private var hasBelowThreshold: Bool {
        enrichedVariants(applyFilters: false).contains { $0.thresholdStatus != .normal }
    }

    private var totalVariantCount: Int {
        enrichedVariants(applyFilters: false).count
    }

    private var optionFilterAxes: [StockOptionFilterAxis] {
        StockAttributeFiltering.axes(from: enrichedVariants(applyFilters: false))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            viewModeToggle
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)

            filterRow
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing2)

            if hasBelowThreshold {
                ThresholdBanner(
                    rows: enrichedVariants(applyFilters: false),
                    onTap: {
                        thresholdFilter = .warning
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing2)
            }

            content
        }
        .sheet(item: $selectedRow) { row in
            VariantDetailView(row: row)
                .environmentObject(dataController)
        }
    }

    // MARK: - Sub-views

    private var viewModeToggle: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            ForEach(StockViewMode.allCases) { mode in
                Button {
                    setViewMode(mode)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(
                            viewMode == mode
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                        )
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(viewMode == mode
                                      ? OPSStyle.Colors.subtleBackground
                                      : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(
                                    viewMode == mode
                                        ? OPSStyle.Colors.cardBorder
                                        : Color.clear,
                                    lineWidth: OPSStyle.Layout.Border.standard
                                )
                        )
                }
                .accessibilityLabel("\(mode.rawValue) view")
                .accessibilityAddTraits(viewMode == mode ? [.isSelected] : [])
            }
            Spacer()
            Text("\(totalVariantCount)")
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("variants")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                CategoryFilterMenu(
                    selectedId: $selectedCategoryId,
                    categories: companyCategories
                )
                TagFilterMenu(
                    selectedId: $selectedTagId,
                    tags: companyTags
                )
                ForEach(optionFilterAxes) { axis in
                    OptionValueFilterMenu(
                        axis: axis,
                        selectedValueKey: Binding(
                            get: { selectedOptionValueKeys[axis.key] },
                            set: { newValue in
                                if let newValue {
                                    selectedOptionValueKeys[axis.key] = newValue
                                } else {
                                    selectedOptionValueKeys.removeValue(forKey: axis.key)
                                }
                            }
                        )
                    )
                }
                ThresholdFilterMenu(
                    selected: $thresholdFilter
                )
                StockSortMenu(selected: sortMode, onSelect: setSortMode)
                if selectedCategoryId != nil || selectedTagId != nil || !selectedOptionValueKeys.isEmpty || thresholdFilter != .all {
                    Button {
                        selectedCategoryId = nil
                        selectedTagId = nil
                        selectedOptionValueKeys.removeAll()
                        thresholdFilter = .all
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text("CLEAR")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.errorText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .frame(height: 32)
                    }
                    .accessibilityLabel("Clear filters")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let rows = enrichedVariants(applyFilters: true)

        if rows.isEmpty {
            emptyState
        } else {
            switch viewMode {
            case .list:
                StockListView(
                    rows: rows,
                    categories: companyCategories,
                    onTap: { selectedRow = $0 }
                )
                    .trackScreen("Catalog.Stock.List")
            case .grid:
                StockGridView(rows: rows, onTap: { selectedRow = $0 })
                    .trackScreen("Catalog.Stock.Grid")
            case .table:
                StockTableView(
                    rows: rows,
                    categories: companyCategories,
                    allOptions: allOptions,
                    allOptionValues: allOptionValues,
                    allVariantOptionValues: allVariantOptionValues,
                    onTap: { selectedRow = $0 }
                )
                .trackScreen("Catalog.Stock.Table")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let hasAnyData = totalVariantCount > 0
        if hasAnyData {
            // NO VARIANTS MATCH FILTERS — filters are active but nothing matches.
            VStack(spacing: OPSStyle.Layout.spacing2) {
                Spacer()
                Text("// NO VARIANTS MATCH FILTERS")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("Adjust the filters above.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // NO STOCK YET — stock system is empty.
            let canManage = PermissionStore.shared.can("catalog.manage")
            VStack(spacing: OPSStyle.Layout.spacing3) {
                Spacer()
                Text("// NO STOCK YET")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("Let's build your stock system.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                if canManage {
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            NotificationCenter.default.post(
                                name: Notification.Name("OpenGuidedStockSetup"),
                                object: nil
                            )
                        } label: {
                            Text("SET UP STOCK")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(OPSStyle.Colors.buttonText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(OPSStyle.Layout.buttonRadius)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, OPSStyle.Layout.spacing4)
                        .accessibilityLabel("Set up stock")
                        .accessibilityHint("Opens the guided stock setup flow.")

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            NotificationCenter.default.post(
                                name: Notification.Name("OpenCatalogSetup"),
                                object: nil
                            )
                        } label: {
                            Text("// ADVANCED")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .frame(height: OPSStyle.Layout.touchTargetMin)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Advanced stock setup")
                        .accessibilityHint("Opens the advanced catalog setup sheet.")
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Filter menus

struct CategoryFilterMenu: View {
    @Binding var selectedId: String?
    let categories: [CatalogCategory]

    private var label: String {
        guard let id = selectedId,
              let match = categories.first(where: { $0.id == id })
        else { return "CATEGORY" }
        return match.name.uppercased()
    }

    var body: some View {
        Menu {
            Button {
                selectedId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("All", systemImage: selectedId == nil ? "checkmark" : "")
            }
            ForEach(categories) { category in
                Button {
                    selectedId = category.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label(category.name, systemImage: selectedId == category.id ? "checkmark" : "")
                }
            }
        } label: {
            ChipLabel(text: label, isActive: selectedId != nil)
        }
        .accessibilityLabel("Category filter")
    }
}

struct TagFilterMenu: View {
    @Binding var selectedId: String?
    let tags: [CatalogTag]

    private var label: String {
        guard let id = selectedId,
              let match = tags.first(where: { $0.id == id })
        else { return "TAG" }
        return match.name.uppercased()
    }

    var body: some View {
        Menu {
            Button {
                selectedId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("All", systemImage: selectedId == nil ? "checkmark" : "")
            }
            ForEach(tags) { tag in
                Button {
                    selectedId = tag.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label(tag.name, systemImage: selectedId == tag.id ? "checkmark" : "")
                }
            }
        } label: {
            ChipLabel(text: label, isActive: selectedId != nil)
        }
        .accessibilityLabel("Tag filter")
    }
}

struct ThresholdFilterMenu: View {
    @Binding var selected: ThresholdFilter

    var body: some View {
        Menu {
            ForEach(ThresholdFilter.allCases) { filter in
                Button {
                    selected = filter
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label(filter.rawValue, systemImage: selected == filter ? "checkmark" : "")
                }
            }
        } label: {
            ChipLabel(
                text: selected == .all ? "THRESHOLD" : selected.rawValue,
                isActive: selected != .all
            )
        }
        .accessibilityLabel("Threshold filter")
    }
}

struct OptionValueFilterMenu: View {
    let axis: StockOptionFilterAxis
    @Binding var selectedValueKey: String?

    private var label: String {
        guard let selectedValueKey,
              let match = axis.values.first(where: { $0.key == selectedValueKey })
        else { return axis.display.uppercased() }
        return "\(axis.display): \(match.display)".uppercased()
    }

    var body: some View {
        Menu {
            Button {
                selectedValueKey = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("All", systemImage: selectedValueKey == nil ? "checkmark" : "")
            }
            ForEach(axis.values) { value in
                Button {
                    selectedValueKey = value.key
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label(value.display, systemImage: selectedValueKey == value.key ? "checkmark" : "")
                }
            }
        } label: {
            ChipLabel(text: label, isActive: selectedValueKey != nil)
        }
        .accessibilityLabel("\(axis.display) filter")
    }
}

struct StockSortMenu: View {
    let selected: StockSortMode
    let onSelect: (StockSortMode) -> Void

    var body: some View {
        Menu {
            ForEach(StockSortMode.allCases) { mode in
                Button {
                    onSelect(mode)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label(mode.rawValue, systemImage: selected == mode ? "checkmark" : "")
                }
            }
        } label: {
            ChipLabel(text: "SORT: \(selected.rawValue)", isActive: selected != .family)
        }
        .accessibilityLabel("Stock sort")
    }
}

// MARK: - Chip label

struct ChipLabel: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text(text)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(isActive ? OPSStyle.Colors.subtleBackground : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .stroke(
                    isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
    }
}

// MARK: - Stock helpers

enum StockTextKey {
    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum StockNumberFormatter {
    static func quantity(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}

enum StockAttributeFiltering {
    static func matches(_ row: EnrichedVariantRow, selectedValueKeys: [String: String]) -> Bool {
        for (optionKey, valueKey) in selectedValueKeys {
            let hasMatch = row.optionPairs.contains { pair in
                StockTextKey.normalize(pair.option.name) == optionKey &&
                StockTextKey.normalize(pair.value.value) == valueKey
            }
            if !hasMatch { return false }
        }
        return true
    }

    static func axes(from rows: [EnrichedVariantRow]) -> [StockOptionFilterAxis] {
        var axisDisplayByKey: [String: String] = [:]
        var valuesByAxis: [String: [String: String]] = [:]

        for row in rows {
            for pair in row.optionPairs {
                let optionKey = StockTextKey.normalize(pair.option.name)
                let valueKey = StockTextKey.normalize(pair.value.value)
                guard !optionKey.isEmpty, !valueKey.isEmpty else { continue }
                axisDisplayByKey[optionKey] = pair.option.name
                valuesByAxis[optionKey, default: [:]][valueKey] = pair.value.value
            }
        }

        return axisDisplayByKey.keys.sorted { lhs, rhs in
            (axisDisplayByKey[lhs] ?? lhs).localizedCaseInsensitiveCompare(axisDisplayByKey[rhs] ?? rhs) == .orderedAscending
        }.compactMap { key in
            let values = (valuesByAxis[key] ?? [:])
                .map { StockOptionFilterValue(key: $0.key, display: $0.value) }
                .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
            guard !values.isEmpty else { return nil }
            return StockOptionFilterAxis(key: key, display: axisDisplayByKey[key] ?? key, values: values)
        }
    }
}

enum StockQuantityAdjustment {
    static let presetDeltas: [Double] = [-100, -50, -10, -5, 5, 10, 50, 100]

    static func targetQuantity(current: Double, delta: Double) -> Double? {
        let next = current + delta
        guard next >= 0, next != current else { return nil }
        return next
    }

    static func exactQuantity(from text: String, current: Double) -> Double? {
        guard let parsed = parseQuantity(text), parsed >= 0, parsed != current else { return nil }
        return parsed
    }

    static func customTargetQuantity(from text: String, sign: Double, current: Double) -> Double? {
        guard sign == 1 || sign == -1,
              let parsed = parseQuantity(text),
              abs(parsed) > 0
        else { return nil }
        return targetQuantity(current: current, delta: abs(parsed) * sign)
    }

    private static func parseQuantity(_ text: String) -> Double? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}

enum StockRowOrdering {
    static func sorted(_ rows: [EnrichedVariantRow], mode: StockSortMode) -> [EnrichedVariantRow] {
        rows.sorted { lhs, rhs in
            switch mode {
            case .category:
                return compareCategory(lhs, rhs)
            case .family:
                return compareFamily(lhs, rhs)
            case .quantity:
                if lhs.variant.quantity != rhs.variant.quantity {
                    return lhs.variant.quantity < rhs.variant.quantity
                }
                return compareFamily(lhs, rhs)
            case .lowStock:
                return compareLowStock(lhs, rhs)
            }
        }
    }

    private static func compareCategory(_ lhs: EnrichedVariantRow, _ rhs: EnrichedVariantRow) -> Bool {
        switch (lhs.category, rhs.category) {
        case let (lhsCategory?, rhsCategory?):
            if lhsCategory.sortOrder != rhsCategory.sortOrder {
                return lhsCategory.sortOrder < rhsCategory.sortOrder
            }
            let categoryCompare = lhsCategory.name.localizedCaseInsensitiveCompare(rhsCategory.name)
            if categoryCompare != .orderedSame { return categoryCompare == .orderedAscending }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return compareFamily(lhs, rhs)
    }

    private static func compareLowStock(_ lhs: EnrichedVariantRow, _ rhs: EnrichedVariantRow) -> Bool {
        let lhsRank = thresholdRank(lhs)
        let rhsRank = thresholdRank(rhs)
        if lhsRank != rhsRank { return lhsRank < rhsRank }

        switch (lhs.thresholdRatio, rhs.thresholdRatio) {
        case let (l?, r?) where l != r:
            return l < r
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return compareFamily(lhs, rhs)
        }
    }

    private static func thresholdRank(_ row: EnrichedVariantRow) -> Int {
        switch row.thresholdStatus {
        case .critical: return 0
        case .warning:  return 1
        case .normal:   return row.thresholdRatio == nil ? 3 : 2
        }
    }

    private static func compareFamily(_ lhs: EnrichedVariantRow, _ rhs: EnrichedVariantRow) -> Bool {
        let familyCompare = lhs.family.name.localizedCaseInsensitiveCompare(rhs.family.name)
        if familyCompare != .orderedSame { return familyCompare == .orderedAscending }
        let lhsLabel = lhs.variantLabel.isEmpty ? lhs.variant.sku ?? "" : lhs.variantLabel
        let rhsLabel = rhs.variantLabel.isEmpty ? rhs.variant.sku ?? "" : rhs.variantLabel
        return lhsLabel.localizedCaseInsensitiveCompare(rhsLabel) == .orderedAscending
    }
}

// MARK: - Threshold banner

/// Aggregate banner shown when any variant has fallen below its effective
/// warning or critical threshold. Tapping pivots the threshold filter to
/// surface only the affected variants.
struct ThresholdBanner: View {
    let rows: [EnrichedVariantRow]
    let onTap: () -> Void

    private var criticalCount: Int {
        rows.filter { $0.thresholdStatus == .critical }.count
    }

    private var warningCount: Int {
        rows.filter { $0.thresholdStatus == .warning }.count
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BELOW THRESHOLD")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if criticalCount > 0 {
                            Text("\(criticalCount) critical")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                        if warningCount > 0 {
                            Text("\(warningCount) warning")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.warningText)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.warningBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.warningStatus, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(criticalCount) critical, \(warningCount) warning. Filter to view.")
    }
}
