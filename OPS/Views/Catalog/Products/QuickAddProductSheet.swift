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

    // Inline create sheets — opened from the "+ NEW …" menu items so the
    // user never has to dismiss this sheet, navigate elsewhere, then come
    // back. The new row's id is returned via callback and selected here.
    @State private var showingNewCategorySheet: Bool = false
    @State private var showingNewUnitSheet: Bool = false

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
        .sheet(isPresented: $showingNewCategorySheet) {
            InlineCreateCategorySheet(companyId: companyId) { newId in
                // Adopt the new category as the picker's selection so the
                // user lands back here with their just-created row chosen.
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
        guard let id = selectedUnitId,
              let unit = companyUnits.first(where: { $0.id == id })
        else { return "Flat rate" }
        return unit.display
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
        guard let id = selectedCategoryId,
              let category = companyCategories.first(where: { $0.id == id })
        else { return "None" }
        return category.name
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
            unitId: selectedUnit?.id,
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

// MARK: - Inline Create Category Sheet

/// Minimal "+ NEW CATEGORY…" sheet — name only. The full Categories
/// management screen handles parent nesting, sort order, color, and
/// thresholds; this sheet is for the user who realized mid-product-create
/// that they need a new category and wants it in two taps.
private struct InlineCreateCategorySheet: View {
    let companyId: String
    let onCreated: (String) -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allCategories: [CatalogCategory]

    @State private var name: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    @FocusState private var nameFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    /// Sort order for the new row — append to the end of the company's
    /// existing categories so the picker keeps a stable order.
    private var nextSortOrder: Int {
        let local = allCategories.filter { $0.companyId == companyId && $0.deletedAt == nil }
        let max = local.map(\.sortOrder).max() ?? 0
        return max + 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            CatalogSectionHeader("CATEGORY")
                            CatalogFieldLabel("Name")
                            TextField("e.g. Hardware", text: $name)
                                .textFieldStyle(CatalogTextFieldStyle())
                                .focused($nameFocused)
                                .submitLabel(.done)
                                .onSubmit { Task { await save() } }
                        }
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("NEW CATEGORY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        } else {
                            Text("SAVE")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(canSave
                                    ? OPSStyle.Colors.primaryAccent
                                    : OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    nameFocused = true
                }
            }
        }
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }

    @MainActor
    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let dto = CreateCatalogCategoryDTO(
            companyId: companyId,
            name: trimmed,
            parentId: nil,
            sortOrder: nextSortOrder,
            colorHex: nil,
            defaultWarningThreshold: nil,
            defaultCriticalThreshold: nil
        )

        do {
            let repo = CatalogRepository(companyId: companyId)
            let created = try await repo.createCategory(dto)
            // Insert into local store so the parent picker sees the new row
            // before the next sync round.
            let model = created.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCreated(created.id)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Inline Create Unit Sheet

/// Minimal "+ NEW UNIT…" sheet — display + dimension. Abbreviation,
/// default flag, and sort order can be edited later from the full Units
/// management screen.
private struct InlineCreateUnitSheet: View {
    let companyId: String
    let onCreated: (String) -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allUnits: [CatalogUnit]

    @State private var display: String = ""
    @State private var dimension: String = "count"
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    @FocusState private var displayFocused: Bool

    /// The six dimension values match the Postgres check constraint on
    /// catalog_units.dimension. Display labels are user-friendly; the
    /// raw value goes to Supabase.
    private static let dimensions: [(raw: String, label: String)] = [
        ("count",  "Count"),
        ("length", "Length"),
        ("area",   "Area"),
        ("volume", "Volume"),
        ("mass",   "Mass"),
        ("time",   "Time"),
    ]

    private var canSave: Bool {
        !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    private var nextSortOrder: Int {
        let local = allUnits.filter { $0.companyId == companyId && $0.deletedAt == nil }
        let max = local.map(\.sortOrder).max() ?? 0
        return max + 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            CatalogSectionHeader("UNIT")
                            CatalogFieldLabel("Display")
                            TextField("e.g. BOARD FT", text: $display)
                                .textFieldStyle(CatalogTextFieldStyle())
                                .focused($displayFocused)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .submitLabel(.done)
                                .onSubmit { Task { await save() } }

                            CatalogFieldLabel("Dimension")
                            dimensionPicker
                        }
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("NEW UNIT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        } else {
                            Text("SAVE")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(canSave
                                    ? OPSStyle.Colors.primaryAccent
                                    : OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    displayFocused = true
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }

    private var dimensionPicker: some View {
        Picker("Dimension", selection: $dimension) {
            ForEach(Self.dimensions, id: \.raw) { entry in
                Text(entry.label).tag(entry.raw)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: dimension) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @MainActor
    private func save() async {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let dto = CreateCatalogUnitDTO(
            companyId: companyId,
            display: trimmed,
            abbreviation: nil,
            dimension: dimension,
            isDefault: false,
            sortOrder: nextSortOrder
        )

        do {
            let repo = CatalogRepository(companyId: companyId)
            let created = try await repo.createUnit(dto)
            let model = created.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCreated(created.id)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}
