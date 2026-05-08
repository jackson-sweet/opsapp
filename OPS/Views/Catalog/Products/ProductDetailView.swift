//
//  ProductDetailView.swift
//  OPS
//
//  Detail screen for a single Product. Combines a lightweight in-place
//  editor for base fields (name, base price, pricing unit, taxable,
//  active) with read-only sub-views that surface the product's options,
//  pricing modifiers, and recipe rows. Authoring those richer fields
//  lives on web for now; the iOS detail keeps you confident the rules
//  are wired correctly.
//

import SwiftUI
import SwiftData

struct ProductDetailView: View {
    let product: Product

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var canManageProducts: Bool { permissionStore.can("catalog.products.manage") }

    @Query private var allOptions: [ProductOption]
    @Query private var allOptionValues: [ProductOptionValue]
    @Query private var allModifiers: [ProductPricingModifier]
    @Query private var allMaterials: [ProductMaterial]
    @Query private var allCategories: [CatalogCategory]
    @Query private var allUnits: [CatalogUnit]

    // Editable mirror of product base fields. Reset when `product.id`
    // changes so navigating between detail screens picks up the right
    // baseline without leaking edits across products.
    @State private var name: String
    @State private var basePriceString: String
    @State private var taxable: Bool
    @State private var isActive: Bool

    /// Selected CatalogUnit id. nil = no unit (treated as flat-rate).
    /// Hydrated from `product.unitId` on init.
    @State private var selectedUnitId: String?

    /// Selected CatalogCategory id. nil = none. Hydrated from
    /// `product.categoryId` on init.
    @State private var selectedCategoryId: String?

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var priceParseError: Bool = false

    /// Drives presentation of the recipe edit sheet. The read-only
    /// `RecipeReadOnlyView` remains; this sheet supplements it for users
    /// who can manage products.
    @State private var showingRecipeManageSheet: Bool = false

    /// Inline create sheets — opened from the "+ NEW …" menu items so the
    /// user never has to leave the detail screen, navigate elsewhere, then
    /// return. The new row's id is returned via callback and selected here.
    @State private var showingNewCategorySheet: Bool = false
    @State private var showingNewUnitSheet: Bool = false

    init(product: Product) {
        self.product = product
        _name = State(initialValue: product.name)
        _basePriceString = State(initialValue: Self.priceFieldString(product.basePrice))
        _taxable = State(initialValue: product.taxable)
        _isActive = State(initialValue: product.isActive)
        _selectedUnitId = State(initialValue: product.unitId)
        _selectedCategoryId = State(initialValue: product.categoryId)
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyCategories: [CatalogCategory] {
        allCategories
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    /// Current CatalogUnit selection resolved against the local @Query.
    /// Used both to render the picker label and to derive the legacy
    /// `pricingUnit` enum + `unit` string at save time.
    private var selectedCatalogUnit: CatalogUnit? {
        guard let id = selectedUnitId else { return nil }
        return companyUnits.first(where: { $0.id == id })
    }

    private var selectedCatalogCategory: CatalogCategory? {
        guard let id = selectedCategoryId else { return nil }
        return companyCategories.first(where: { $0.id == id })
    }

    private var productOptions: [ProductOption] {
        allOptions
            .filter { $0.productId == product.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var productOptionValues: [ProductOptionValue] {
        let optionIds = Set(productOptions.map(\.id))
        return allOptionValues.filter { optionIds.contains($0.optionId) }
    }

    private var productModifiers: [ProductPricingModifier] {
        allModifiers.filter { $0.productId == product.id }
    }

    private var productMaterials: [ProductMaterial] {
        allMaterials.filter { $0.productId == product.id }
    }

    private var hasChanges: Bool {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) != product.name { return true }
        let trimmedPrice = basePriceString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Double(trimmedPrice), parsed != product.basePrice { return true }
        if selectedUnitId != product.unitId { return true }
        if selectedCategoryId != product.categoryId { return true }
        if taxable != product.taxable { return true }
        if isActive != product.isActive { return true }
        return false
    }

    private var canSave: Bool {
        guard hasChanges, !isSaving else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return false }
        let trimmedPrice = basePriceString.trimmingCharacters(in: .whitespacesAndNewlines)
        if Double(trimmedPrice) == nil { return false }
        return true
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    headerSection
                    coreCard
                    categoryCard
                    if !productOptions.isEmpty {
                        optionsSection
                    }
                    if !productModifiers.isEmpty {
                        modifiersSection
                    }
                    // Show the recipe section any time there are materials,
                    // OR when the operator can manage products — managers
                    // need the EDIT entry point even on an empty recipe so
                    // they can add the first row.
                    if !productMaterials.isEmpty || canManageProducts {
                        recipeSection
                    }
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorText)
                    }
                    Color.clear.frame(height: OPSStyle.Layout.spacing5)
                }
                .padding(OPSStyle.Layout.spacing3)
            }
        }
        .navigationTitle("PRODUCT")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasChanges && canManageProducts {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text("SAVE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(canSave
                                             ? OPSStyle.Colors.primaryAccent
                                             : OPSStyle.Colors.tertiaryText)
                    }
                    .disabled(!canSave)
                }
            }
        }
        .trackScreen("Catalog.Products.Detail")
        .sheet(isPresented: $showingRecipeManageSheet) {
            RecipeManageSheet(product: product)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingNewCategorySheet) {
            InlineCreateCategorySheet(companyId: companyId) { newId in
                selectedCategoryId = newId
            }
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingNewUnitSheet) {
            InlineCreateUnitSheet(companyId: companyId) { newId in
                selectedUnitId = newId
            }
            .environmentObject(dataController)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(product.name)
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(2)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                kindChip
                if let sku = product.sku, !sku.isEmpty {
                    Text(sku)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                if let category = product.category, !category.isEmpty {
                    Text(category.uppercased())
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Spacer()
            }
        }
    }

    private var kindChip: some View {
        Text(product.kind.rawValue.uppercased())
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    // MARK: - Core editable fields

    private var coreCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("CORE")

            CatalogFieldLabel("Name")
            TextField("", text: $name)
                .textFieldStyle(CatalogTextFieldStyle())
                .disabled(!canManageProducts)

            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    CatalogFieldLabel("Base price")
                    TextField("0", text: $basePriceString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(CatalogTextFieldStyle())
                        .disabled(!canManageProducts)
                        .onChange(of: basePriceString) { _, newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            priceParseError = !trimmed.isEmpty && Double(trimmed) == nil
                        }
                    if priceParseError {
                        Text("Price must be a number")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.errorText)
                    }
                }
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    CatalogFieldLabel("Unit")
                    if canManageProducts {
                        unitPicker
                    } else {
                        readOnlyMenuLabel(text: selectedUnitDisplay)
                    }
                }
            }

            Toggle(isOn: $taxable) {
                Text("Taxable")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.primaryAccent)
            .disabled(!canManageProducts)
            .onChange(of: taxable) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            Toggle(isOn: $isActive) {
                Text("Active")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.primaryAccent)
            .disabled(!canManageProducts)
            .onChange(of: isActive) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Category card (CatalogCategory-backed)

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("CATEGORY")
            if canManageProducts {
                categoryPicker
            } else {
                readOnlyMenuLabel(text: selectedCategoryDisplay)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Unit picker (CatalogUnit-backed, with inline "+ NEW UNIT")

    private var unitPicker: some View {
        Menu {
            Button {
                selectedUnitId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("Flat rate", systemImage: selectedUnitId == nil ? "checkmark" : "")
            }
            ForEach(companyUnits) { unit in
                Button {
                    selectedUnitId = unit.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if selectedUnitId == unit.id {
                        Label(unit.display, systemImage: "checkmark")
                    } else {
                        Text(unit.display)
                    }
                }
            }
            Divider()
            Button {
                showingNewUnitSheet = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("New unit…", systemImage: "plus")
            }
        } label: {
            menuLabel(text: selectedUnitDisplay)
        }
    }

    private var selectedUnitDisplay: String {
        // Prefer the resolved CatalogUnit; fall back to the legacy free-text
        // unit string so detail screens for products synced before the FK
        // existed still render something sensible.
        if let unit = selectedCatalogUnit { return unit.display }
        if let legacy = product.unit, !legacy.isEmpty { return legacy }
        return "Flat rate"
    }

    // MARK: - Category picker (CatalogCategory-backed)

    private var categoryPicker: some View {
        Menu {
            Button {
                selectedCategoryId = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("None", systemImage: selectedCategoryId == nil ? "checkmark" : "")
            }
            ForEach(companyCategories) { category in
                Button {
                    selectedCategoryId = category.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if selectedCategoryId == category.id {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
            Divider()
            Button {
                showingNewCategorySheet = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("New category…", systemImage: "plus")
            }
        } label: {
            menuLabel(text: selectedCategoryDisplay)
        }
    }

    private var selectedCategoryDisplay: String {
        if let category = selectedCatalogCategory { return category.name }
        if let legacy = product.category, !legacy.isEmpty { return legacy }
        return "None"
    }

    /// Shared visual for both the category and unit Menu labels. Matches
    /// the look of `CatalogTextFieldStyle` so the form reads as one unit
    /// with the text fields above it.
    @ViewBuilder
    private func menuLabel(text: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    /// Read-only sibling of `menuLabel(text:)` — same visual chrome but no
    /// chevron, no tap. Used when the operator lacks `catalog.products.manage`
    /// so they can still see the current selection without an idle picker.
    @ViewBuilder
    private func readOnlyMenuLabel(text: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Sections

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader(title: "OPTIONS · \(productOptions.count)")
            OptionsReadOnlyView(
                options: productOptions,
                optionValues: productOptionValues
            )
        }
    }

    private var modifiersSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader(title: "PRICING MODIFIERS · \(productModifiers.count)")
            ModifiersReadOnlyView(
                modifiers: productModifiers,
                options: productOptions,
                optionValues: productOptionValues
            )
        }
    }

    private var recipeSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            recipeSectionHeader
            if productMaterials.isEmpty {
                Text("// NO MATERIALS YET — TAP EDIT TO BUILD THE RECIPE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(OPSStyle.Layout.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            } else {
                RecipeReadOnlyView(
                    materials: productMaterials,
                    options: productOptions
                )
            }
        }
    }

    /// Recipe-specific header. Mirrors `sectionHeader(title:)` but slots an
    /// EDIT affordance in for users with `catalog.products.manage`. The
    /// read-only renderer below stays visible; the sheet is supplemental.
    private var recipeSectionHeader: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// RECIPE · \(productMaterials.count) ROW\(productMaterials.count == 1 ? "" : "S")")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            if canManageProducts {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingRecipeManageSheet = true
                } label: {
                    Text("EDIT")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, 4)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin / 2)
                }
                .accessibilityLabel("Edit recipe")
            }
            viewOnWebLink
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// \(title)")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            viewOnWebLink
        }
    }

    private var viewOnWebLink: some View {
        Link(destination: URL(string: "https://app.ops.dev/products/\(product.id)")!) {
            Text("VIEW ON WEB →")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, 4)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin / 2)
        }
        .accessibilityHint("Opens this product in the OPS web app")
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrice = basePriceString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let parsedPrice = Double(trimmedPrice) else { return }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        // Build a sparse update that only carries changed fields. The
        // wire-format omits anything we didn't touch so server-side
        // defaults / web-authored values stay intact.
        var fields = UpdateProductDTO()
        if trimmedName != product.name { fields.name = trimmedName }
        if parsedPrice != product.basePrice { fields.basePrice = parsedPrice }
        if taxable != product.taxable { fields.isTaxable = taxable }
        if isActive != product.isActive { fields.isActive = isActive }

        // Unit changed: write all three columns in lockstep (legacy `unit`
        // free-text, FK `unit_id`, and the legacy `pricing_unit` enum). The
        // `pricingUnit(for:)` helper lives in CatalogManageHelpers.swift so
        // create + edit derive the enum the same way.
        if selectedUnitId != product.unitId {
            let unit = selectedCatalogUnit
            fields.unitId = unit?.id
            fields.unit = unit?.display
            fields.pricingUnit = pricingUnit(for: unit).rawValue
        }

        // Category changed: write both legacy `category` (text) and FK
        // `category_id` so reads from either path see the right value.
        if selectedCategoryId != product.categoryId {
            let category = selectedCatalogCategory
            fields.categoryId = category?.id
            fields.category = category?.name
        }

        let repo = ProductRepository(companyId: companyId)
        do {
            let dto = try await repo.update(product.id, fields: fields)
            applyDTOToLocal(dto)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    private func applyDTOToLocal(_ dto: ProductDTO) {
        product.name = dto.name
        product.basePrice = dto.basePrice
        if let pricingUnitRaw = dto.pricingUnit,
           let parsed = ProductPricingUnit(rawValue: pricingUnitRaw) {
            product.pricingUnit = parsed
        }
        if let typeRaw = dto.type, let parsedType = LineItemType(rawValue: typeRaw) {
            product.type = parsedType
        }
        if let kindRaw = dto.kind, let parsedKind = ProductKind(rawValue: kindRaw) {
            product.kind = parsedKind
        }
        product.productDescription = dto.description
        product.unitCost = dto.unitCost
        product.unit = dto.unit
        product.unitId = dto.unitId
        product.category = dto.category
        product.categoryId = dto.categoryId
        product.sku = dto.sku
        product.thumbnailUrl = dto.thumbnailUrl
        product.taxable = dto.isTaxable ?? product.taxable
        product.isActive = dto.isActive
        product.minimumCharge = dto.minimumCharge
        product.minimumQuantity = dto.minimumQuantity
        product.taskTypeId = dto.taskTypeId
        try? modelContext.save()
    }

    private static func priceFieldString(_ value: Double) -> String {
        if value == 0 { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
