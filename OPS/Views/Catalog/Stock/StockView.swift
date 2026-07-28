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

    var displayLabel: String { rawValue }

    var icon: String {
        switch self {
        case .list:  return OPSStyle.Icons.listBullet
        case .grid:  return OPSStyle.Icons.grid
        case .table: return OPSStyle.Icons.table
        }
    }

    var operatorPurpose: StockModePurpose {
        switch self {
        case .list:  return .scan
        case .grid:  return .find
        case .table: return .compare
        }
    }

    var accessibilityHint: String {
        switch operatorPurpose {
        case .scan:    return "Scan and adjust every stock variant."
        case .find:    return "Find stock by product family."
        case .compare: return "Compare the variants in one family."
        }
    }
}

enum StockModePurpose: String, Hashable {
    case scan
    case find
    case compare
}

// MARK: - Threshold filter

enum ThresholdFilter: String, CaseIterable, Identifiable {
    case all = "ALL"
    case warning = "WARNING+"
    case critical = "CRITICAL"
    var id: String { rawValue }

    var accessibilityValue: String {
        switch self {
        case .all: return "All thresholds"
        case .warning: return "Warning and critical"
        case .critical: return "Critical only"
        }
    }
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
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("catalog.stock.viewMode") private var viewModeRaw: String = StockViewMode.list.rawValue
    @AppStorage("catalog.stock.sortMode") private var sortModeRaw: String = StockSortMode.family.rawValue

    @State private var selectedCategoryId: String? = nil
    @State private var selectedTagId: String? = nil
    @State private var thresholdFilter: ThresholdFilter = .all
    @State private var selectedOptionValueKeys: [String: String] = [:]
    @State private var searchText: String = ""
    @State private var isSearchPresented: Bool = false
    @State private var isReducedMotionSearchMounted: Bool = false
    @State private var isReducedMotionSearchOpaque: Bool = false
    @State private var quickAdjustRow: EnrichedVariantRow? = nil
    @State private var pendingDetailRow: EnrichedVariantRow? = nil
    @State private var detailRow: EnrichedVariantRow? = nil
    @FocusState private var isSearchFocused: Bool

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

    /// Only controls that can change the current stock result belong in the
    /// filter rail. Unused setup categories/tags stay out of the scan surface.
    private var stockFilterCategories: [CatalogCategory] {
        let categoriesById = Dictionary(uniqueKeysWithValues: companyCategories.map { ($0.id, $0) })
        let visibleIds = StockFilterScope.categoryIds(
            rows: enrichedVariants(applyFilters: false),
            categoriesById: categoriesById
        )
        return companyCategories
            .filter { visibleIds.contains($0.id) }
            .sorted {
                StockCategoryHierarchy.isOrderedBefore($0, $1, categoriesById: categoriesById)
            }
    }

    private var stockFilterTags: [CatalogTag] {
        let visibleIds = StockFilterScope.tagIds(rows: enrichedVariants(applyFilters: false))
        return companyTags.filter { visibleIds.contains($0.id) }
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
            if !StockSearch.matches(row.searchText, query: searchText) { return false }
            // Category filter — variant matches if family's category matches.
            if !StockCategoryFiltering.matches(
                rowCategory: row.category,
                selectedCategoryId: selectedCategoryId,
                categoriesById: categoriesById
            ) { return false }
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

        return StockRowOrdering.sorted(filtered, mode: sortMode, categories: companyCategories)
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

    private var isSearchVisible: Bool {
        isSearchPresented || !searchText.isEmpty
    }

    // MARK: - Body

    var body: some View {
        let filteredRows = enrichedVariants(applyFilters: true)

        VStack(spacing: 0) {
            workbar(filteredCount: filteredRows.count)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)

            searchArea

            filterRow
                .padding(.bottom, OPSStyle.Layout.spacing2)

            if hasBelowThreshold {
                ThresholdBanner(
                    rows: enrichedVariants(applyFilters: false),
                    opensSuggestedOrders: permissionStore.can("catalog.orders.view"),
                    onTap: {
                        if permissionStore.can("catalog.orders.view") {
                            NotificationCenter.default.post(
                                name: Notification.Name("OpenCatalogOrders"),
                                object: nil,
                                userInfo: ["subSegment": OrdersSubSegment.suggested.rawValue]
                            )
                        } else {
                            thresholdFilter = .warning
                        }
                    }
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing2)
            }

            content(rows: filteredRows)
        }
        .animation(reduceMotion ? nil : OPSStyle.Animation.panel, value: isSearchPresented)
        .onAppear {
            if reduceMotion {
                updateReducedMotionSearch(isVisible: isSearchVisible)
            }
        }
        .onChange(of: isSearchVisible) { _, isVisible in
            if reduceMotion {
                updateReducedMotionSearch(isVisible: isVisible)
            } else if !isVisible {
                isSearchFocused = false
            }
        }
        .onChange(of: reduceMotion) { _, isEnabled in
            if isEnabled {
                updateReducedMotionSearch(isVisible: isSearchVisible)
            } else {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isReducedMotionSearchMounted = false
                    isReducedMotionSearchOpaque = false
                }
            }
        }
        .sheet(item: $quickAdjustRow, onDismiss: deliverPendingDetail) { row in
            StockQuickAdjustSheet(
                row: row,
                onOpenFullDetail: {
                    pendingDetailRow = row
                    quickAdjustRow = nil
                }
            )
            .environmentObject(dataController)
        }
        .sheet(item: $detailRow) { row in
            VariantDetailView(row: row)
                .environmentObject(dataController)
        }
    }

    // MARK: - Sub-views

    private func workbar(filteredCount: Int) -> some View {
        StockModeWorkbar(
            selectedMode: viewMode,
            filteredCount: filteredCount,
            totalCount: totalVariantCount,
            isSearchActive: isSearchVisible,
            onSelectMode: { mode in
                setViewMode(mode)
            },
            onToggleSearch: {
                isSearchPresented.toggle()
            }
        )
    }

    @ViewBuilder
    private var searchArea: some View {
        if reduceMotion {
            if isSearchVisible || isReducedMotionSearchMounted {
                stockSearchField
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing2)
                    .opacity(isReducedMotionSearchOpaque ? 1 : 0)
                    .allowsHitTesting(isSearchVisible)
                    .accessibilityHidden(!isSearchVisible)
            }
        } else if isSearchVisible {
            stockSearchField
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing2)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear {
                    if isSearchPresented {
                        isSearchFocused = true
                    }
                }
        }
    }

    private func updateReducedMotionSearch(isVisible: Bool) {
        if isVisible {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isReducedMotionSearchMounted = true
            }

            Task { @MainActor in
                await Task.yield()
                guard reduceMotion, isSearchVisible else { return }
                withAnimation(OPSStyle.Animation.reducedFallback) {
                    isReducedMotionSearchOpaque = true
                }
                if isSearchPresented {
                    isSearchFocused = true
                }
            }
        } else {
            isSearchFocused = false
            guard isReducedMotionSearchMounted else {
                isReducedMotionSearchOpaque = false
                return
            }

            withAnimation(
                OPSStyle.Animation.reducedFallback,
                completionCriteria: .logicallyComplete
            ) {
                isReducedMotionSearchOpaque = false
            } completion: {
                guard !isSearchVisible else { return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isReducedMotionSearchMounted = false
                }
            }
        }
    }

    private var stockSearchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.search)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            TextField("SEARCH STOCK", text: $searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .accessibilityIdentifier("catalog.stock.search.field")

            Button {
                if searchText.isEmpty {
                    isSearchPresented = false
                } else {
                    searchText = ""
                }
            } label: {
                Image(systemName: searchText.isEmpty ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.xmarkCircleFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(searchText.isEmpty ? "Close search" : "Clear search")
        }
        .padding(.leading, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.inputHeight)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var filterRow: some View {
        StockFilterRail {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if StockFilterVisibility.categoryChangesResults(
                    rows: enrichedVariants(applyFilters: false),
                    categories: stockFilterCategories,
                    categoriesById: Dictionary(uniqueKeysWithValues: companyCategories.map { ($0.id, $0) })
                ) {
                    CategoryFilterMenu(
                        selectedId: $selectedCategoryId,
                        categories: stockFilterCategories
                    )
                }
                if !stockFilterTags.isEmpty {
                    TagFilterMenu(
                        selectedId: $selectedTagId,
                        tags: stockFilterTags
                    )
                }
                ForEach(optionFilterAxes) { axis in
                    if StockFilterVisibility.optionAxisChangesResults(
                        axis: axis,
                        rows: enrichedVariants(applyFilters: false)
                    ) {
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
                }
                ThresholdFilterMenu(
                    selected: $thresholdFilter
                )
                StockSortMenu(selected: sortMode, onSelect: setSortMode)
                if selectedCategoryId != nil || selectedTagId != nil || !selectedOptionValueKeys.isEmpty || thresholdFilter != .all {
                    Button {
                        clearFilters(includeSearch: false)
                    } label: {
                        Text("CLEAR")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.text2)
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .frame(minHeight: OPSStyle.Layout.chipMinHeight)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                    .fill(OPSStyle.Colors.surfaceInput)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                    .stroke(
                                        OPSStyle.Colors.line,
                                        lineWidth: OPSStyle.Layout.Border.standard
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filters")
                }
            }
        }
    }

    @ViewBuilder
    private func content(rows: [EnrichedVariantRow]) -> some View {
        if rows.isEmpty {
            emptyState
        } else {
            switch viewMode {
            case .list:
                StockListView(
                    rows: rows,
                    categories: companyCategories,
                    groupByCategory: sortMode == .category,
                    onTap: { quickAdjustRow = $0 },
                    onOpenDetail: { detailRow = $0 }
                )
                    .trackScreen("Catalog.Stock.List")
            case .grid:
                StockGridView(
                    rows: rows,
                    onTap: { quickAdjustRow = $0 },
                    onOpenDetail: { detailRow = $0 }
                )
                    .trackScreen("Catalog.Stock.Grid")
            case .table:
                StockTableView(
                    rows: rows,
                    allOptions: allOptions,
                    onTap: { quickAdjustRow = $0 }
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
                Text("Adjust the search or filters above.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Button {
                    clearFilters(includeSearch: true)
                } label: {
                    Text("CLEAR SEARCH + FILTERS")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.primaryText)
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
                .buttonStyle(.plain)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // NO STOCK YET — stock system is empty.
            let canManage = permissionStore.can("catalog.manage")
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
                            NotificationCenter.default.post(
                                name: Notification.Name("OpenGuidedStockSetup"),
                                object: nil
                            )
                        } label: {
                            Text("SET UP STOCK")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(OPSStyle.Colors.buttonText)
                                .frame(maxWidth: .infinity)
                                .frame(height: OPSStyle.Layout.bottomCTAHeight)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(OPSStyle.Layout.buttonRadius)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, OPSStyle.Layout.spacing4)
                        .accessibilityLabel("Set up stock")
                        .accessibilityHint("Opens the guided stock setup flow.")

                        Button {
                            NotificationCenter.default.post(
                                name: Notification.Name("OpenCatalogSetup"),
                                object: nil
                            )
                        } label: {
                            Text("// ADVANCED")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
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

    private func clearFilters(includeSearch: Bool) {
        selectedCategoryId = nil
        selectedTagId = nil
        selectedOptionValueKeys.removeAll()
        thresholdFilter = .all
        if includeSearch { searchText = "" }
    }

    private func deliverPendingDetail() {
        guard let pendingDetailRow else { return }
        self.pendingDetailRow = nil
        detailRow = pendingDetailRow
    }
}

// MARK: - Mode workbar

/// Shared compact command surface for the three Stock jobs. At accessibility
/// sizes the modes get their own row so labels grow instead of shrinking.
struct StockModeWorkbar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedMode: StockViewMode
    let filteredCount: Int
    let totalCount: Int
    let isSearchActive: Bool
    let onSelectMode: (StockViewMode) -> Void
    let onToggleSearch: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    modePicker
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        searchButton
                        countLabel
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    modePicker
                        .layoutPriority(1)
                    searchButton
                    countLabel
                }
            }
        }
    }

    private var modePicker: some View {
        let modes = StockViewMode.allCases

        return HStack(spacing: 0) {
            ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                Button {
                    onSelectMode(mode)
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: mode.icon)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text(mode.displayLabel)
                            .font(OPSStyle.Typography.metadata)
                    }
                    .foregroundColor(
                        selectedMode == mode
                            ? OPSStyle.Colors.text
                            : OPSStyle.Colors.text3
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minWidth: OPSStyle.Layout.segmentedItemMinWidth)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.segmentedItemRadius)
                            .fill(selectedMode == mode ? OPSStyle.Colors.surfaceSelected : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.segmentedItemRadius)
                            .stroke(
                                selectedMode == mode
                                    ? OPSStyle.Colors.activeSegmentBorder
                                    : Color.clear,
                                lineWidth: OPSStyle.Layout.Border.standard
                            )
                    )
                    .overlay(alignment: .top) {
                        if selectedMode == mode {
                            Rectangle()
                                .fill(OPSStyle.Colors.activeSegmentHighlight)
                                .frame(height: OPSStyle.Layout.Border.standard)
                                .padding(.horizontal, OPSStyle.Layout.spacing1)
                                .padding(.top, OPSStyle.Layout.Border.standard)
                        }
                    }
                    .animation(OPSStyle.Animation.hover, value: selectedMode)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.displayLabel) view")
                .accessibilityHint(mode.accessibilityHint)
                .accessibilityAddTraits(selectedMode == mode ? [.isSelected] : [])
                .accessibilityIdentifier("catalog.stock.mode.\(mode.rawValue.lowercased())")

                if index < modes.count - 1 {
                    let nextMode = modes[index + 1]
                    Rectangle()
                        .fill(
                            selectedMode == mode || selectedMode == nextMode
                                ? Color.clear
                                : OPSStyle.Colors.nestedBorder
                        )
                        .frame(
                            width: OPSStyle.Layout.Border.standard,
                            height: OPSStyle.Layout.spacing3
                        )
                }
            }
        }
        .padding(OPSStyle.Layout.segmentedControlInset)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.segmentedControlRadius)
                .fill(OPSStyle.Colors.surfaceSegmented)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.segmentedControlRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var searchButton: some View {
        Button(action: onToggleSearch) {
            Image(systemName: OPSStyle.Icons.search)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(isSearchActive ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                .frame(width: OPSStyle.Layout.touchTargetMin)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(isSearchActive ? OPSStyle.Colors.surfaceSelected : OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            isSearchActive ? OPSStyle.Colors.activeChipBorder : OPSStyle.Colors.line,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search stock")
        .accessibilityValue(isSearchActive ? "Active" : "Inactive")
        .accessibilityIdentifier("catalog.stock.search.toggle")
    }

    private var countLabel: some View {
        Text(filteredCount == totalCount ? "\(totalCount)" : "\(filteredCount)/\(totalCount)")
            .font(OPSStyle.Typography.dataValue)
            .foregroundColor(OPSStyle.Colors.text3)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("\(filteredCount) of \(totalCount) stock variants")
    }
}

// MARK: - Filter menus

private struct StockFilterViewportWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct StockFilterContentFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Full-bleed filter rail with canvas-aligned content. Edge fades appear only
/// when more controls exist in that direction, so they never cover a terminal
/// chip or imply scrolling when the row already fits.
private struct StockFilterRail<Content: View>: View {
    @Namespace private var coordinateSpace
    @State private var viewportWidth: CGFloat = 0
    @State private var contentFrame: CGRect = .zero

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var hasOverflow: Bool {
        contentFrame.width > viewportWidth + OPSStyle.Layout.Border.standard
    }

    private var canScrollLeading: Bool {
        hasOverflow && contentFrame.minX < -OPSStyle.Layout.Border.standard
    }

    private var canScrollTrailing: Bool {
        hasOverflow && contentFrame.maxX > viewportWidth + OPSStyle.Layout.Border.standard
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: StockFilterContentFrameKey.self,
                            value: proxy.frame(in: .named(coordinateSpace))
                        )
                    }
                }
        }
        .coordinateSpace(name: coordinateSpace)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: StockFilterViewportWidthKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(StockFilterViewportWidthKey.self) { viewportWidth = $0 }
        .onPreferenceChange(StockFilterContentFrameKey.self) { contentFrame = $0 }
        .overlay(alignment: .leading) {
            if canScrollLeading {
                Rectangle()
                    .fill(OPSStyle.Layout.Gradients.carouselFadeLeft)
                    .frame(width: OPSStyle.Layout.spacing3_5)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            if canScrollTrailing {
                Rectangle()
                    .fill(OPSStyle.Layout.Gradients.carouselFadeRight)
                    .frame(width: OPSStyle.Layout.spacing3_5)
                    .allowsHitTesting(false)
            }
        }
    }
}

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
            } label: {
                StockMenuOptionLabel(title: "All", isSelected: selectedId == nil)
            }
            ForEach(categories) { category in
                Button {
                    selectedId = category.id
                } label: {
                    StockMenuOptionLabel(title: category.name, isSelected: selectedId == category.id)
                }
            }
        } label: {
            ChipLabel(text: label, isActive: selectedId != nil)
        }
        .accessibilityLabel("Category filter")
        .accessibilityValue(
            selectedId.flatMap { id in categories.first(where: { $0.id == id })?.name }
                ?? "All categories"
        )
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
            } label: {
                StockMenuOptionLabel(title: "All", isSelected: selectedId == nil)
            }
            ForEach(tags) { tag in
                Button {
                    selectedId = tag.id
                } label: {
                    StockMenuOptionLabel(title: tag.name, isSelected: selectedId == tag.id)
                }
            }
        } label: {
            ChipLabel(text: label, isActive: selectedId != nil)
        }
        .accessibilityLabel("Tag filter")
        .accessibilityValue(
            selectedId.flatMap { id in tags.first(where: { $0.id == id })?.name }
                ?? "All tags"
        )
    }
}

struct ThresholdFilterMenu: View {
    @Binding var selected: ThresholdFilter

    var body: some View {
        Menu {
            ForEach(ThresholdFilter.allCases) { filter in
                Button {
                    selected = filter
                } label: {
                    StockMenuOptionLabel(title: filter.rawValue, isSelected: selected == filter)
                }
            }
        } label: {
            ChipLabel(
                text: selected == .all ? "THRESHOLD" : selected.rawValue,
                isActive: selected != .all
            )
        }
        .accessibilityLabel("Threshold filter")
        .accessibilityValue(selected.accessibilityValue)
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
            } label: {
                StockMenuOptionLabel(title: "All", isSelected: selectedValueKey == nil)
            }
            ForEach(axis.values) { value in
                Button {
                    selectedValueKey = value.key
                } label: {
                    StockMenuOptionLabel(title: value.display, isSelected: selectedValueKey == value.key)
                }
            }
        } label: {
            ChipLabel(text: label, isActive: selectedValueKey != nil)
        }
        .accessibilityLabel("\(axis.display) filter")
        .accessibilityValue(
            selectedValueKey.flatMap { key in axis.values.first(where: { $0.key == key })?.display }
                ?? "All values"
        )
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
                } label: {
                    StockMenuOptionLabel(title: mode.rawValue, isSelected: selected == mode)
                }
            }
        } label: {
            ChipLabel(text: "SORT: \(selected.rawValue)", isActive: selected != .family)
        }
        .accessibilityLabel("Stock sort")
        .accessibilityValue(selected.rawValue.capitalized)
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
            Image(systemName: OPSStyle.Icons.chevronDown)
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .frame(minHeight: OPSStyle.Layout.chipMinHeight)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(isActive ? OPSStyle.Colors.surfaceSelected : OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .stroke(
                    isActive ? OPSStyle.Colors.activeChipBorder : OPSStyle.Colors.line,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
    }
}

struct StockMenuOptionLabel: View {
    let title: String
    let isSelected: Bool

    @ViewBuilder
    var body: some View {
        if isSelected {
            Label(title, systemImage: OPSStyle.Icons.checkmark)
        } else {
            Text(title)
        }
    }
}

// MARK: - Stock helpers

enum StockSearch {
    static func matches(_ candidate: String, query: String) -> Bool {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map { StockTextKey.normalize(String($0)) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return true }

        let normalizedCandidate = StockTextKey.normalize(candidate)
        return terms.allSatisfy(normalizedCandidate.contains)
    }
}

enum StockCategoryFiltering {
    static func matches(
        rowCategory: CatalogCategory?,
        selectedCategoryId: String?,
        categoriesById: [String: CatalogCategory]
    ) -> Bool {
        guard let selectedCategoryId else { return true }
        var current = rowCategory
        var visited = Set<String>()

        while let category = current, visited.insert(category.id).inserted {
            if category.id == selectedCategoryId { return true }
            current = category.parentId.flatMap { categoriesById[$0] }
        }
        return false
    }
}

enum StockFilterScope {
    static func categoryIds(
        rows: [EnrichedVariantRow],
        categoriesById: [String: CatalogCategory]
    ) -> Set<String> {
        var result = Set<String>()
        for row in rows {
            var current = row.category
            var visited = Set<String>()
            while let category = current, visited.insert(category.id).inserted {
                result.insert(category.id)
                current = category.parentId.flatMap { categoriesById[$0] }
            }
        }
        return result
    }

    static func tagIds(rows: [EnrichedVariantRow]) -> Set<String> {
        rows.reduce(into: Set<String>()) { result, row in
            result.formUnion(row.tagIds)
        }
    }
}

enum StockFilterVisibility {
    static func categoryChangesResults(
        rows: [EnrichedVariantRow],
        categories: [CatalogCategory],
        categoriesById: [String: CatalogCategory]
    ) -> Bool {
        guard !rows.isEmpty else { return false }
        return categories.contains { category in
            let matchCount = rows.filter {
                StockCategoryFiltering.matches(
                    rowCategory: $0.category,
                    selectedCategoryId: category.id,
                    categoriesById: categoriesById
                )
            }.count
            return matchCount > 0 && matchCount < rows.count
        }
    }

    static func optionAxisChangesResults(
        axis: StockOptionFilterAxis,
        rows: [EnrichedVariantRow]
    ) -> Bool {
        guard !rows.isEmpty else { return false }
        return axis.values.contains { value in
            let selected = [axis.key: value.key]
            let matchCount = rows.filter {
                StockAttributeFiltering.matches($0, selectedValueKeys: selected)
            }.count
            return matchCount > 0 && matchCount < rows.count
        }
    }
}

enum StockCategoryHierarchy {
    static func isOrderedBefore(
        _ lhs: CatalogCategory,
        _ rhs: CatalogCategory,
        categoriesById: [String: CatalogCategory]
    ) -> Bool {
        let lhsPath = path(to: lhs, categoriesById: categoriesById)
        let rhsPath = path(to: rhs, categoriesById: categoriesById)
        let sharedCount = min(lhsPath.count, rhsPath.count)

        for index in 0..<sharedCount {
            let left = lhsPath[index]
            let right = rhsPath[index]
            if left.id == right.id { continue }
            if left.sortOrder != right.sortOrder { return left.sortOrder < right.sortOrder }
            let nameOrder = left.name.localizedCaseInsensitiveCompare(right.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return left.id < right.id
        }
        return lhsPath.count < rhsPath.count
    }

    private static func path(
        to category: CatalogCategory,
        categoriesById: [String: CatalogCategory]
    ) -> [CatalogCategory] {
        var path = [category]
        var current = category
        var visited: Set<String> = [category.id]

        while let parentId = current.parentId,
              visited.insert(parentId).inserted,
              let parent = categoriesById[parentId] {
            path.insert(parent, at: 0)
            current = parent
        }
        return path
    }
}

struct StockGridLayout: Equatable {
    let columnCount: Int
    let showsSecondaryMetadata: Bool
}

enum StockGridDensity {
    static func clampedScale(_ value: Double) -> Double {
        min(
            max(value, Double(OPSStyle.Inventory.CardScale.minScale)),
            Double(OPSStyle.Inventory.CardScale.maxScale)
        )
    }

    static func layout(for scale: Double) -> StockGridLayout {
        let clamped = clampedScale(scale)
        if clamped < Double(OPSStyle.Inventory.CardScale.tagVisibilityThreshold) {
            return StockGridLayout(columnCount: 3, showsSecondaryMetadata: false)
        }
        let expandedThreshold = Double(
            (OPSStyle.Inventory.CardScale.metadataVisibilityThreshold + OPSStyle.Inventory.CardScale.maxScale) / 2
        )
        if clamped > expandedThreshold {
            return StockGridLayout(columnCount: 1, showsSecondaryMetadata: true)
        }
        return StockGridLayout(columnCount: 2, showsSecondaryMetadata: true)
    }

    static func adjustedScale(from scale: Double, towardLargerCards: Bool) -> Double {
        let stops = [
            Double(OPSStyle.Inventory.CardScale.minScale),
            Double(OPSStyle.Inventory.CardScale.metadataVisibilityThreshold),
            Double(OPSStyle.Inventory.CardScale.maxScale)
        ]
        let current = clampedScale(scale)

        if towardLargerCards {
            return stops.first(where: { $0 > current }) ?? Double(OPSStyle.Inventory.CardScale.maxScale)
        }
        return stops.reversed().first(where: { $0 < current }) ?? Double(OPSStyle.Inventory.CardScale.minScale)
    }

    static func accessibilityValue(for scale: Double) -> String {
        let layout = layout(for: scale)
        switch layout.columnCount {
        case 3: return "Compact, 3 columns"
        case 1: return "Expanded, 1 column"
        default: return "Standard, 2 columns"
        }
    }
}

enum StockTableSelection {
    static func resolve(current: String?, available: [String]) -> String? {
        if let current, available.contains(current) { return current }
        return available.first
    }
}

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
    static func sorted(
        _ rows: [EnrichedVariantRow],
        mode: StockSortMode,
        categories: [CatalogCategory] = []
    ) -> [EnrichedVariantRow] {
        let categoriesById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return rows.sorted { lhs, rhs in
            switch mode {
            case .category:
                return compareCategory(lhs, rhs, categoriesById: categoriesById)
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

    private static func compareCategory(
        _ lhs: EnrichedVariantRow,
        _ rhs: EnrichedVariantRow,
        categoriesById: [String: CatalogCategory]
    ) -> Bool {
        switch (lhs.category, rhs.category) {
        case let (lhsCategory?, rhsCategory?):
            if lhsCategory.id != rhsCategory.id {
                return StockCategoryHierarchy.isOrderedBefore(
                    lhsCategory,
                    rhsCategory,
                    categoriesById: categoriesById
                )
            }
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
/// warning or critical threshold. Tapping opens the suggested-order review
/// when permitted, with a low-stock filter fallback for read-only operators.
struct ThresholdBanner: View {
    let rows: [EnrichedVariantRow]
    let opensSuggestedOrders: Bool
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
                Image(systemName: OPSStyle.Icons.alert)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.warningStatus)

                if criticalCount > 0 {
                    Text("\(criticalCount) CRITICAL")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.roseTextM)
                }
                if criticalCount > 0 && warningCount > 0 {
                    Text("·")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                if warningCount > 0 {
                    Text("\(warningCount) LOW")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tanTextM)
                }

                Spacer()
                Text("REVIEW")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                Image(systemName: OPSStyle.Icons.forward)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(OPSStyle.Colors.warningBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.warningStatus, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(criticalCount) critical, \(warningCount) warning")
        .accessibilityHint(
            opensSuggestedOrders
                ? "Opens suggested orders."
                : "Filters stock to low and critical items."
        )
    }
}
