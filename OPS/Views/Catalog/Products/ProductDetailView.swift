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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allOptions: [ProductOption]
    @Query private var allOptionValues: [ProductOptionValue]
    @Query private var allModifiers: [ProductPricingModifier]
    @Query private var allMaterials: [ProductMaterial]

    // Editable mirror of product base fields. Reset when `product.id`
    // changes so navigating between detail screens picks up the right
    // baseline without leaking edits across products.
    @State private var name: String
    @State private var basePriceString: String
    @State private var pricingUnit: ProductPricingUnit
    @State private var taxable: Bool
    @State private var isActive: Bool

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var priceParseError: Bool = false

    init(product: Product) {
        self.product = product
        _name = State(initialValue: product.name)
        _basePriceString = State(initialValue: Self.priceFieldString(product.basePrice))
        _pricingUnit = State(initialValue: product.pricingUnit)
        _taxable = State(initialValue: product.taxable)
        _isActive = State(initialValue: product.isActive)
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
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
        if pricingUnit != product.pricingUnit { return true }
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
                    if !productOptions.isEmpty {
                        optionsSection
                    }
                    if !productModifiers.isEmpty {
                        modifiersSection
                    }
                    if !productMaterials.isEmpty {
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
            if hasChanges {
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

            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    CatalogFieldLabel("Base price")
                    TextField("0", text: $basePriceString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(CatalogTextFieldStyle())
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
                    pricingUnitPicker
                }
            }

            Toggle(isOn: $taxable) {
                Text("Taxable")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.primaryAccent)
            .onChange(of: taxable) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            Toggle(isOn: $isActive) {
                Text("Active")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.primaryAccent)
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

    private var pricingUnitPicker: some View {
        Picker("Unit", selection: $pricingUnit) {
            ForEach(ProductPricingUnit.allCases, id: \.self) { unit in
                Text(unitDisplay(unit)).tag(unit)
            }
        }
        .pickerStyle(.menu)
        .tint(OPSStyle.Colors.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .onChange(of: pricingUnit) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func unitDisplay(_ unit: ProductPricingUnit) -> String {
        switch unit {
        case .flatRate:    return "Flat"
        case .each:        return "Each"
        case .linearFoot:  return "Per ft"
        case .sqft:        return "Per sqft"
        case .hour:        return "Per hour"
        case .day:         return "Per day"
        }
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
            sectionHeader(title: "RECIPE · \(productMaterials.count) ROW\(productMaterials.count == 1 ? "" : "S")")
            RecipeReadOnlyView(
                materials: productMaterials,
                options: productOptions
            )
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
        if pricingUnit != product.pricingUnit { fields.pricingUnit = pricingUnit.rawValue }
        if taxable != product.taxable { fields.isTaxable = taxable }
        if isActive != product.isActive { fields.isActive = isActive }

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
        product.category = dto.category
        product.sku = dto.sku
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
