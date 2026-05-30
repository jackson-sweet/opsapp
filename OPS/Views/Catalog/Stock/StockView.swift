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

    @State private var selectedCategoryId: String? = nil
    @State private var selectedTagId: String? = nil
    @State private var thresholdFilter: ThresholdFilter = .all
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
        let optionsById = Dictionary(uniqueKeysWithValues: allOptions.map { ($0.id, $0) })

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
                _ = optionsById // silence unused warning when family has 0 options
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

        return rows.filter { row in
            // Category filter — variant matches if family's category matches.
            if let cid = selectedCategoryId, row.category?.id != cid { return false }
            // Tag filter — variant matches if family carries the tag.
            if let tid = selectedTagId, !row.tagIds.contains(tid) { return false }
            // Threshold filter.
            switch thresholdFilter {
            case .all: break
            case .warning: if row.thresholdStatus == .normal { return false }
            case .critical: if row.thresholdStatus != .critical { return false }
            }
            return true
        }
    }

    private var hasBelowThreshold: Bool {
        enrichedVariants(applyFilters: false).contains { $0.thresholdStatus != .normal }
    }

    private var totalVariantCount: Int {
        enrichedVariants(applyFilters: false).count
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
                ThresholdFilterMenu(
                    selected: $thresholdFilter
                )
                if selectedCategoryId != nil || selectedTagId != nil || thresholdFilter != .all {
                    Button {
                        selectedCategoryId = nil
                        selectedTagId = nil
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
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Spacer()
            Text(hasAnyData ? "// NO VARIANTS MATCH FILTERS" : "// NO STOCK YET")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(hasAnyData
                 ? "Adjust the filters above."
                 : "Add a family from the + button to start tracking stock.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Chip label

struct ChipLabel: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text(text)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
            Image(OPSStyle.Icons.chevronDown)
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
                    isActive ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
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
                Image(OPSStyle.Icons.alert)
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
                Image(OPSStyle.Icons.chevronRight)
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

