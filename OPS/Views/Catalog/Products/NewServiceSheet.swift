//
//  NewServiceSheet.swift
//  OPS
//
//  Kind-tailored create sheet for SERVICE products. Locks `kind='service'`
//  and `type='LABOR'`. No unit-cost field, no margin readout, no thumbnail
//  — services are pure labor + time, not physical goods. Default unit
//  hydrates to the company's "Hours" CatalogUnit when present.
//
//  Voice: title is // NEW SERVICE, save bar reads // SAVE SERVICE so the
//  operator sees confirmation of what kind of row they're committing.
//

import SwiftUI
import SwiftData

struct NewServiceSheet: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allCategories: [CatalogCategory]
    @Query private var allUnits: [CatalogUnit]
    @Query private var allProducts: [Product]

    // Required core
    @State private var name: String = ""
    @State private var priceString: String = ""
    @State private var selectedUnitId: String? = nil
    @State private var selectedCategoryId: String? = nil

    // Optional
    @State private var productDescription: String = ""
    @State private var sku: String = ""
    @State private var taxable: Bool = true
    @State private var showAdvanced: Bool = false

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var priceParseError: Bool = false

    // Inline create sheets
    @State private var showingNewCategorySheet: Bool = false
    @State private var showingNewUnitSheet: Bool = false

    private var canManageProducts: Bool { permissionStore.can("catalog.products.manage") }

    @AppStorage("catalog.product.saveAndAddAnother") private var saveAndAddAnother: Bool = false

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
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if priceString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if isSaving { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            coreFields
                            folderField
                            advancedDisclosure
                            errorRow
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }
                    .dismissKeyboardOnTap()
                    saveBar
                }
            }
            .navigationTitle("NEW SERVICE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .onAppear {
                hydrateDefaultUnit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    nameFieldFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    // MARK: - Core

    @ViewBuilder
    private var coreFields: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("SERVICE")
            CatalogFieldLabel("Name")
            TextField("e.g. Hourly carpentry", text: $name)
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
                    UnitPickerField(
                        selectedUnitId: $selectedUnitId,
                        companyUnits: companyUnits,
                        canCreateNew: canManageProducts,
                        onCreateRequested: { showingNewUnitSheet = true },
                        allowFlatRate: true
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var folderField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("CATEGORY")
            CategoryPickerField(
                selectedCategoryId: $selectedCategoryId,
                companyCategories: companyCategories,
                canCreateNew: canManageProducts,
                onCreateRequested: { showingNewCategorySheet = true }
            )
        }
    }

    @ViewBuilder
    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                CatalogFieldLabel("Description")
                TextField("Optional", text: $productDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(CatalogTextFieldStyle())

                CatalogFieldLabel("SKU")
                TextField("Optional", text: $sku)
                    .textFieldStyle(CatalogTextFieldStyle())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)

                Toggle(isOn: $taxable) {
                    Text("Taxable")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .tint(OPSStyle.Colors.text)
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

    @ViewBuilder
    private var errorRow: some View {
        if let errorMessage = errorMessage {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                Text(errorMessage)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.errorText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await save() }
                } label: {
                    Text("RETRY")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.primaryAccent,
                                        lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .accessibilityLabel("Retry saving service")
                .disabled(isSaving)
            }
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider().background(OPSStyle.Colors.separator)
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView().tint(OPSStyle.Colors.buttonText)
                    } else {
                        Text("SAVE SERVICE")
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
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)

            saveAndAddAnotherToggle
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing2)
                .padding(.bottom, OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.background)
    }

    private var saveAndAddAnotherToggle: some View {
        Toggle(isOn: $saveAndAddAnother) {
            Text("// SAVE AND ADD ANOTHER")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .tint(OPSStyle.Colors.text)
        .onChange(of: saveAndAddAnother) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Defaults

    /// Hydrate the default pricing unit to "Hours" when the company has one.
    /// Services bill by the hour more often than not, and pre-selecting saves
    /// a tap on the most common case. Falls back to nil (flat rate) when no
    /// matching unit exists — operator can still pick anything from the menu.
    private func hydrateDefaultUnit() {
        guard selectedUnitId == nil else { return }
        let match = companyUnits.first { unit in
            let lower = unit.display.lowercased()
            return lower == "hour" || lower == "hours" || lower == "hr" || lower == "hrs"
        }
        selectedUnitId = match?.id
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrice = priceString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { return }
        guard let parsedPrice = Double(trimmedPrice) else {
            priceParseError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        // Local duplicate-name pre-check (same pattern as QuickAddProductSheet).
        let lowerName = trimmedName.lowercased()
        let duplicate = allProducts.first { existing in
            existing.companyId == companyId &&
            existing.isActive &&
            existing.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowerName
        }
        if duplicate != nil {
            errorMessage = "// NAME ALREADY USED — pick a different name or edit the existing product"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedDescription = productDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSku = sku.trimmingCharacters(in: .whitespacesAndNewlines)

        let selectedUnit = companyUnits.first(where: { $0.id == selectedUnitId })
        let selectedCategory = companyCategories.first(where: { $0.id == selectedCategoryId })
        let pricingUnitRaw = pricingUnit(for: selectedUnit).rawValue

        var dto = CreateProductDTO(
            companyId: companyId,
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            basePrice: parsedPrice,
            unitCost: nil,
            unit: selectedUnit?.display,
            pricingUnit: pricingUnitRaw,
            unitId: selectedUnit?.id,
            category: selectedCategory?.name,
            categoryId: selectedCategory?.id,
            sku: trimmedSku.isEmpty ? nil : trimmedSku,
            thumbnailUrl: nil,
            kind: "service",
            type: LineItemType.labor.rawValue,
            isTaxable: taxable,
            taskTypeId: nil,
            taskTypeRef: nil,
            linkedCatalogItemId: nil
        )
        dto.bundlePricingMode = nil

        let repo = ProductRepository(companyId: companyId)
        do {
            let createdDTO = try await repo.create(dto)
            let model = createdDTO.toModel()
            modelContext.insert(model)
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if saveAndAddAnother {
                resetForNextEntry()
            } else {
                dismiss()
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func resetForNextEntry() {
        name = ""
        priceString = ""
        productDescription = ""
        sku = ""
        priceParseError = false
        errorMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            nameFieldFocused = true
        }
    }
}
