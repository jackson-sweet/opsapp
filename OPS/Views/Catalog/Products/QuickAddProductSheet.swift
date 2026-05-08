//
//  QuickAddProductSheet.swift
//  OPS
//
//  Fast product entry that respects the catalog backbone. Category and
//  unit pull from the user's existing CatalogCategory / CatalogUnit
//  rows so the new Product slots into the same vocabulary the Stock
//  side already uses — no more orphan free-text strings.
//
//  Save button is pinned to the sheet bottom so it stays reachable
//  when the advanced disclosure is open. A footer note tells the user
//  options / modifiers / recipes are still authored on web (replaces
//  the prior fake 'Full Setup' FAB alert).
//

import SwiftUI
import SwiftData

struct QuickAddProductSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allCategories: [CatalogCategory]
    @Query private var allUnits: [CatalogUnit]

    // Required core
    @State private var name: String = ""
    @State private var priceString: String = ""

    /// Selected CatalogUnit id. nil = no unit (treated as flat-rate).
    @State private var selectedUnitId: String? = nil

    /// Selected CatalogCategory id. nil = none. The Product schema stores
    /// `category` as free text — we pick the CatalogCategory's name into
    /// that column at save so Stock and Products read the same vocabulary
    /// without a schema change.
    @State private var selectedCategoryId: String? = nil

    // Advanced (optional)
    @State private var showAdvanced: Bool = false
    @State private var productDescription: String = ""
    @State private var sku: String = ""
    @State private var unitCostString: String = ""
    @State private var lineItemType: LineItemType = .other
    @State private var kind: ProductKind = .service
    @State private var taxable: Bool = true

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var priceParseError: Bool = false
    @State private var unitCostParseError: Bool = false

    @FocusState private var nameFieldFocused: Bool

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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !priceString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            coreFields
                            categoryField
                            advancedDisclosure
                            footerNote
                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.errorText)
                            }
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }

                    saveBar
                }
            }
            .navigationTitle("NEW PRODUCT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .onAppear {
                // Auto-focus name so the user can start typing immediately —
                // the entry budget hinges on no extra taps before input.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    nameFieldFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Core fields

    @ViewBuilder
    private var coreFields: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("PRODUCT")
            CatalogFieldLabel("Name")
            TextField("e.g. Composite deck install", text: $name)
                .textFieldStyle(CatalogTextFieldStyle())
                .focused($nameFieldFocused)
                .submitLabel(.next)

            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    CatalogFieldLabel("Price")
                    TextField("0", text: $priceString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(CatalogTextFieldStyle())
                        .onChange(of: priceString) { _, newValue in
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
                    unitPicker
                }
            }
        }
    }

    // MARK: - Unit picker (CatalogUnit-backed)

    private var unitPicker: some View {
        Picker("Unit", selection: $selectedUnitId) {
            Text("Flat rate").tag(String?.none)
            ForEach(companyUnits) { unit in
                Text(unit.display).tag(Optional(unit.id))
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
        .onChange(of: selectedUnitId) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Category picker (CatalogCategory-backed, free-text on save)

    @ViewBuilder
    private var categoryField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("CATEGORY")
            categoryPicker
        }
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $selectedCategoryId) {
            Text("None").tag(String?.none)
            ForEach(companyCategories) { category in
                Text(category.name).tag(Optional(category.id))
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
        .onChange(of: selectedCategoryId) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Advanced

    @ViewBuilder
    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                CatalogFieldLabel("Description")
                TextField("Optional", text: $productDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(CatalogTextFieldStyle())

                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        CatalogFieldLabel("SKU")
                        TextField("Optional", text: $sku)
                            .textFieldStyle(CatalogTextFieldStyle())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                    }
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        CatalogFieldLabel("Unit cost")
                        TextField("0", text: $unitCostString)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(CatalogTextFieldStyle())
                            .onChange(of: unitCostString) { _, newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                unitCostParseError = !trimmed.isEmpty && Double(trimmed) == nil
                            }
                        if unitCostParseError {
                            Text("Must be a number")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                }

                CatalogFieldLabel("Kind")
                kindPicker

                CatalogFieldLabel("Line item type")
                lineItemTypePicker

                Toggle(isOn: $taxable) {
                    Text("Taxable")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .tint(OPSStyle.Colors.primaryAccent)
                .onChange(of: taxable) { _, _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .padding(.top, OPSStyle.Layout.spacing2)
        } label: {
            Text("// ADVANCED")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .tint(OPSStyle.Colors.primaryAccent)
    }

    private var kindPicker: some View {
        Picker("Kind", selection: $kind) {
            Text("Service").tag(ProductKind.service)
            Text("Good").tag(ProductKind.good)
        }
        .pickerStyle(.segmented)
        .onChange(of: kind) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private var lineItemTypePicker: some View {
        Picker("Line item type", selection: $lineItemType) {
            ForEach(LineItemType.allCases, id: \.self) { value in
                Text(value.rawValue).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: lineItemType) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Footer note

    @ViewBuilder
    private var footerNote: some View {
        // Replaces the prior fake 'Full Setup' FAB button. Honest about
        // the iOS limitation without exposing a tappable dead-end.
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "info.circle")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Need options, modifiers, or a recipe? Edit this product on web after saving.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    // MARK: - Save bar (pinned)

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider().background(OPSStyle.Colors.separator)
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView()
                            .tint(OPSStyle.Colors.buttonText)
                    } else {
                        Text("SAVE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(canSave ? OPSStyle.Colors.buttonText : OPSStyle.Colors.tertiaryText)
                    }
                    Spacer()
                }
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder,
                                lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .disabled(!canSave)
            .padding(OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrice = priceString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnitCost = unitCostString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { return }
        guard let parsedPrice = Double(trimmedPrice) else {
            priceParseError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        if !trimmedUnitCost.isEmpty, Double(trimmedUnitCost) == nil {
            unitCostParseError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedDescription = productDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSku = sku.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedUnitCost = trimmedUnitCost.isEmpty ? nil : Double(trimmedUnitCost)

        // Resolve picker selections to the Product schema.
        let selectedUnit = companyUnits.first(where: { $0.id == selectedUnitId })
        let selectedCategory = companyCategories.first(where: { $0.id == selectedCategoryId })
        let categoryName = selectedCategory?.name
        let pricingUnitRaw = pricingUnit(for: selectedUnit).rawValue

        let dto = CreateProductDTO(
            companyId: companyId,
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            basePrice: parsedPrice,
            unitCost: parsedUnitCost,
            unit: selectedUnit?.display,
            pricingUnit: pricingUnitRaw,
            category: categoryName,
            sku: trimmedSku.isEmpty ? nil : trimmedSku,
            kind: kind.rawValue,
            type: lineItemType.rawValue,
            isTaxable: taxable,
            taskTypeId: nil
        )

        let repo = ProductRepository(companyId: companyId)
        do {
            let createdDTO = try await repo.create(dto)
            applyCreatedDTO(createdDTO)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    /// Maps a CatalogUnit to the closest ProductPricingUnit enum case.
    /// The enum is what drives display formatting elsewhere in the app
    /// (estimate line items, product list price suffix). nil unit means
    /// flat-rate. The mapping is best-effort by dimension because the
    /// enum's six cases don't cover every possible custom unit display.
    private func pricingUnit(for unit: CatalogUnit?) -> ProductPricingUnit {
        guard let unit = unit else { return .flatRate }

        let display = unit.display.lowercased()
        let dimension = unit.dimension.lowercased()

        if display.contains("hour") || display == "hr" { return .hour }
        if display.contains("day")  { return .day }

        switch dimension {
        case "length": return .linearFoot
        case "area":   return .sqft
        case "time":
            // Generic "time" without an obvious hour/day signal — fall
            // back to flatRate rather than guess wrong.
            return .flatRate
        case "count":  return .each
        default:       return .flatRate
        }
    }

    private func applyCreatedDTO(_ dto: ProductDTO) {
        let model = dto.toModel()
        modelContext.insert(model)
        try? modelContext.save()
    }
}
