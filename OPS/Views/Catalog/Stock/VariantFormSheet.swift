//
//  VariantFormSheet.swift
//  OPS
//
//  Create-new-variant sheet (also used for full edit when launched from a
//  family with options the user wants to retag). Loads the family's
//  options so the form can render one Picker per option, then upserts
//  the variant + its option-value joins through `CatalogRepository`.
//

import SwiftUI
import SwiftData

struct VariantFormSheet: View {
    /// The family this variant belongs to. When `nil`, the user picks one.
    let initialFamily: CatalogItem?
    /// Existing variant to edit, or `nil` to create a new variant.
    let existingVariant: CatalogVariant?

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allFamilies: [CatalogItem]
    @Query private var allOptions: [CatalogOption]
    @Query private var allOptionValues: [CatalogOptionValue]
    @Query private var allUnits: [CatalogUnit]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]

    @State private var selectedFamilyId: String? = nil
    @State private var skuText: String = ""
    @State private var quantityText: String = "0"
    @State private var warningText: String = ""
    @State private var criticalText: String = ""
    @State private var selectedUnitId: String? = nil
    /// Map of option id → selected option value id. One entry per option
    /// on the chosen family.
    @State private var optionSelections: [String: String] = [:]

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    init(initialFamily: CatalogItem? = nil, existingVariant: CatalogVariant? = nil) {
        self.initialFamily = initialFamily
        self.existingVariant = existingVariant
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var isEditing: Bool { existingVariant != nil }

    private var companyFamilies: [CatalogItem] {
        allFamilies
            .filter { $0.companyId == companyId && $0.deletedAt == nil && $0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    private var familyOptions: [CatalogOption] {
        guard let id = selectedFamilyId else { return [] }
        return allOptions
            .filter { $0.catalogItemId == id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func valuesFor(option: CatalogOption) -> [CatalogOptionValue] {
        allOptionValues
            .filter { $0.optionId == option.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        familyPickerSection
                        coreFieldsSection
                        if !familyOptions.isEmpty {
                            optionsSection
                        }
                        thresholdsSection
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle(isEditing ? "EDIT VARIANT" : "NEW VARIANT")
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
                        Text("SAVE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(canSave
                                             ? OPSStyle.Colors.primaryAccent
                                             : OPSStyle.Colors.tertiaryText)
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .onAppear { loadInitial() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var familyPickerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("FAMILY")
            CatalogFieldLabel("Family")
            Picker("Family", selection: $selectedFamilyId) {
                Text("Select…").tag(String?.none)
                ForEach(companyFamilies) { family in
                    Text(family.name).tag(Optional(family.id))
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
            .disabled(isEditing)
        }
    }

    @ViewBuilder
    private var coreFieldsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("DETAILS")
            CatalogFieldLabel("SKU")
            TextField("", text: $skuText)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Quantity")
            TextField("0", text: $quantityText)
                .keyboardType(.decimalPad)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Unit")
            Picker("Unit", selection: $selectedUnitId) {
                Text("Inherit from family").tag(String?.none)
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
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("OPTIONS")
            ForEach(familyOptions) { option in
                CatalogFieldLabel(option.name)
                Picker(option.name, selection: Binding(
                    get: { optionSelections[option.id] ?? "" },
                    set: { optionSelections[option.id] = $0 }
                )) {
                    Text("Select…").tag("")
                    ForEach(valuesFor(option: option)) { value in
                        Text(value.value).tag(value.id)
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
            }
        }
    }

    @ViewBuilder
    private var thresholdsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("THRESHOLDS (OPTIONAL)")
            CatalogFieldLabel("Warning")
            TextField("Inherit", text: $warningText)
                .keyboardType(.decimalPad)
                .textFieldStyle(CatalogTextFieldStyle())
            CatalogFieldLabel("Critical")
            TextField("Inherit", text: $criticalText)
                .keyboardType(.decimalPad)
                .textFieldStyle(CatalogTextFieldStyle())
        }
    }

    // MARK: - Validation

    private var canSave: Bool {
        guard let _ = selectedFamilyId else { return false }
        // Every option on the family must have a selection (single-variant
        // families have zero options and trivially pass).
        for option in familyOptions {
            let v = optionSelections[option.id] ?? ""
            if v.isEmpty { return false }
        }
        return Double(quantityText.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    // MARK: - Persistence

    private func loadInitial() {
        if let initialFamily = initialFamily {
            selectedFamilyId = initialFamily.id
            selectedUnitId = initialFamily.defaultUnitId
        }
        guard let variant = existingVariant else { return }
        selectedFamilyId = variant.catalogItemId
        skuText = variant.sku ?? ""
        quantityText = String(variant.quantity)
        warningText = variant.warningThreshold.map { String($0) } ?? ""
        criticalText = variant.criticalThreshold.map { String($0) } ?? ""
        selectedUnitId = variant.unitId

        // Pre-fill option selections from existing joins.
        let existingJoins = allVariantOptionValues
            .filter { $0.variantId == variant.id }
        let valueIdSet = Set(existingJoins.map(\.optionValueId))
        for option in familyOptions {
            if let pair = allOptionValues.first(where: {
                valueIdSet.contains($0.id) && $0.optionId == option.id
            }) {
                optionSelections[option.id] = pair.id
            }
        }
    }

    @MainActor
    private func save() async {
        guard canSave, let familyId = selectedFamilyId else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let parsedQuantity = Double(quantityText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let parsedWarning = Double(warningText.trimmingCharacters(in: .whitespacesAndNewlines))
        let parsedCritical = Double(criticalText.trimmingCharacters(in: .whitespacesAndNewlines))
        let trimmedSku = skuText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sku: String? = trimmedSku.isEmpty ? nil : trimmedSku

        let repo = CatalogRepository(companyId: companyId)
        do {
            let dto: CatalogVariantDTO
            if let existing = existingVariant {
                let update = UpdateCatalogVariantDTO(
                    sku: sku,
                    quantity: parsedQuantity,
                    priceOverride: existing.priceOverride,
                    unitCostOverride: existing.unitCostOverride,
                    warningThreshold: parsedWarning,
                    criticalThreshold: parsedCritical,
                    unitId: selectedUnitId
                )
                dto = try await repo.updateVariant(existing.id, fields: update)
            } else {
                let create = CreateCatalogVariantDTO(
                    companyId: companyId,
                    catalogItemId: familyId,
                    sku: sku,
                    quantity: parsedQuantity,
                    priceOverride: nil,
                    unitCostOverride: nil,
                    warningThreshold: parsedWarning,
                    criticalThreshold: parsedCritical,
                    unitId: selectedUnitId
                )
                dto = try await repo.createVariant(create)

                // Insert option-value joins for the new variant.
                for (_, valueId) in optionSelections where !valueId.isEmpty {
                    try await repo.createVariantOptionValue(variantId: dto.id, optionValueId: valueId)
                }
            }

            applyDTOToLocal(dto, joinSelections: optionSelections)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyDTOToLocal(_ dto: CatalogVariantDTO, joinSelections: [String: String]) {
        let descriptor = FetchDescriptor<CatalogVariant>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.sku = dto.sku
            existing.quantity = dto.quantity
            existing.priceOverride = dto.priceOverride
            existing.unitCostOverride = dto.unitCostOverride
            existing.warningThreshold = dto.warningThreshold
            existing.criticalThreshold = dto.criticalThreshold
            existing.unitId = dto.unitId
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }

        // Mirror the option-value joins for new variants. Editing an
        // existing variant's option values is a separate flow (web-only
        // for the moment) so we only touch joins on create.
        if existingVariant == nil {
            for (_, valueId) in joinSelections where !valueId.isEmpty {
                let join = CatalogVariantOptionValue(variantId: dto.id, optionValueId: valueId)
                join.lastSyncedAt = Date()
                modelContext.insert(join)
            }
        }
        try? modelContext.save()
    }
}
