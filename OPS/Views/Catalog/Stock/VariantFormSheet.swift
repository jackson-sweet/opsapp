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
import PhotosUI
import UIKit

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
    @State private var variantNameText: String = ""
    @State private var skuText: String = ""
    @State private var quantityText: String = "0"
    @State private var warningText: String = ""
    @State private var criticalText: String = ""
    @State private var selectedUnitId: String? = nil
    /// Map of option id → selected option value id. One entry per option
    /// on the chosen family.
    @State private var optionSelections: [String: String] = [:]
    @State private var imagePickerItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var imageErrorMessage: String? = nil

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

    private static let identityOptionName = "Variant"

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
        optionsForFamily(selectedFamilyId)
    }

    private var visibleFamilyOptions: [CatalogOption] {
        familyOptions.filter { !isIdentityOption($0) }
    }

    private var selectedFamily: CatalogItem? {
        guard let id = selectedFamilyId else { return nil }
        return allFamilies.first { $0.id == id }
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
                        if selectedFamily != nil {
                            imageSection
                        }
                        coreFieldsSection
                        if !visibleFamilyOptions.isEmpty {
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("CANCEL")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(isEditing ? "EDIT VARIANT" : "NEW VARIANT")
                        .font(OPSStyle.Typography.panelTitle)
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
            .onChange(of: selectedFamilyId) { oldValue, newValue in
                guard oldValue != newValue else { return }
                optionSelections = VariantOptionSelectionState.validSelections(
                    optionSelections,
                    familyOptions: optionsForFamily(newValue),
                    optionValues: allOptionValues
                )
                errorMessage = nil
            }
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
    private var imageSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("IMAGE")
            if pickedImage == nil,
               let urlString = selectedFamily?.imageUrl,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        thumbnailPlaceholder("// IMAGE UNAVAILABLE")
                    case .empty:
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryAccent)
                    @unknown default:
                        thumbnailPlaceholder("// IMAGE")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }

            ThumbnailPickerField(
                pickerItem: $imagePickerItem,
                image: $pickedImage,
                errorMessage: imageErrorMessage
            )
        }
    }

    @ViewBuilder
    private func thumbnailPlaceholder(_ label: String) -> some View {
        Text(label)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.cardBackgroundDark)
    }

    @ViewBuilder
    private var coreFieldsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("DETAILS")
            CatalogFieldLabel("Variant name")
            TextField("e.g. Left return", text: $variantNameText)
                .textFieldStyle(CatalogTextFieldStyle())

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
            ForEach(visibleFamilyOptions) { option in
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
        for option in visibleFamilyOptions {
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
        variantNameText = identityValueText(for: variant) ?? ""
        skuText = variant.sku ?? ""
        quantityText = String(variant.quantity)
        warningText = variant.warningThreshold.map { String($0) } ?? ""
        criticalText = variant.criticalThreshold.map { String($0) } ?? ""
        selectedUnitId = variant.unitId

        optionSelections = VariantOptionSelectionState.selections(
            variantId: variant.id,
            familyOptions: optionsForFamily(variant.catalogItemId),
            optionValues: allOptionValues,
            variantOptionValues: allVariantOptionValues
        )
    }

    @MainActor
    private func save() async {
        guard canSave, let familyId = selectedFamilyId else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let parsedQuantity = Double(quantityText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let sku = CatalogVariantFormPayload.normalizedSKU(skuText)

        let repo = CatalogRepository(companyId: companyId)
        do {
            let dto: CatalogVariantDTO
            if let existing = existingVariant {
                let update = CatalogVariantFormPayload.update(
                    skuText: skuText,
                    quantity: parsedQuantity,
                    priceOverride: existing.priceOverride,
                    unitCostOverride: existing.unitCostOverride,
                    warningThresholdText: warningText,
                    criticalThresholdText: criticalText,
                    unitId: selectedUnitId
                )
                dto = try await repo.updateVariant(existing.id, fields: update)
                let optionValueIds = familyOptions.compactMap { optionSelections[$0.id] }.filter { !$0.isEmpty }
                try await repo.replaceVariantOptionValues(variantId: existing.id, optionValueIds: optionValueIds)
            } else {
                let parsedWarning = Double(warningText.trimmingCharacters(in: .whitespacesAndNewlines))
                let parsedCritical = Double(criticalText.trimmingCharacters(in: .whitespacesAndNewlines))
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
            }

            if let pickedImage {
                try await uploadFamilyImage(pickedImage, familyId: familyId, repo: repo)
            }

            let finalJoinSelections = try await joinSelectionsIncludingIdentity(
                familyId: familyId,
                repo: repo
            )
            try await repo.deleteVariantOptionValues(variantId: dto.id)
            for (_, valueId) in finalJoinSelections where !valueId.isEmpty {
                try await repo.createVariantOptionValue(variantId: dto.id, optionValueId: valueId)
            }

            applyDTOToLocal(dto, joinSelections: finalJoinSelections)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isIdentityOption(_ option: CatalogOption) -> Bool {
        option.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(Self.identityOptionName) == .orderedSame
    }

    private func identityOption(for familyId: String) -> CatalogOption? {
        allOptions.first { option in
            option.catalogItemId == familyId && isIdentityOption(option)
        }
    }

    private func identityValueText(for variant: CatalogVariant) -> String? {
        guard let option = identityOption(for: variant.catalogItemId) else { return nil }
        let joinedValueIds = Set(allVariantOptionValues
            .filter { $0.variantId == variant.id }
            .map(\.optionValueId))
        return allOptionValues.first { value in
            value.optionId == option.id && joinedValueIds.contains(value.id)
        }?.value
    }

    @MainActor
    private func joinSelectionsIncludingIdentity(
        familyId: String,
        repo: CatalogRepository
    ) async throws -> [String: String] {
        var selections = optionSelections
        let trimmedName = variantNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return selections }

        let option = try await ensureIdentityOption(familyId: familyId, repo: repo)
        let value = try await ensureIdentityOptionValue(
            option: option,
            valueText: trimmedName,
            repo: repo
        )
        selections[option.id] = value.id
        return selections
    }

    @MainActor
    private func ensureIdentityOption(
        familyId: String,
        repo: CatalogRepository
    ) async throws -> CatalogOption {
        if let existing = identityOption(for: familyId) {
            return existing
        }

        let nextSort = (allOptions
            .filter { $0.catalogItemId == familyId }
            .map(\.sortOrder)
            .max() ?? 0) + 1
        let dto = try await repo.createOption(CreateCatalogOptionDTO(
            catalogItemId: familyId,
            name: Self.identityOptionName,
            sortOrder: nextSort
        ))
        let model = dto.toModel()
        model.lastSyncedAt = Date()
        modelContext.insert(model)
        try? modelContext.save()
        return model
    }

    @MainActor
    private func ensureIdentityOptionValue(
        option: CatalogOption,
        valueText: String,
        repo: CatalogRepository
    ) async throws -> CatalogOptionValue {
        if let existing = allOptionValues.first(where: {
            $0.optionId == option.id &&
            $0.value.caseInsensitiveCompare(valueText) == .orderedSame
        }) {
            return existing
        }

        let nextSort = (allOptionValues
            .filter { $0.optionId == option.id }
            .map(\.sortOrder)
            .max() ?? 0) + 1
        let dto = try await repo.createOptionValue(CreateCatalogOptionValueDTO(
            optionId: option.id,
            value: valueText,
            sortOrder: nextSort
        ))
        let model = dto.toModel()
        model.lastSyncedAt = Date()
        modelContext.insert(model)
        try? modelContext.save()
        return model
    }

    @MainActor
    private func uploadFamilyImage(
        _ image: UIImage,
        familyId: String,
        repo: CatalogRepository
    ) async throws {
        imageErrorMessage = nil
        let url = try await ProductThumbnailUploader.shared.upload(
            image,
            productId: familyId,
            companyId: companyId
        )
        var update = UpdateCatalogItemDTO()
        update.imageUrl = url.absoluteString
        let dto = try await repo.updateFamily(familyId, fields: update)
        applyFamilyDTOToLocal(dto)
    }

    private func applyFamilyDTOToLocal(_ dto: CatalogItemDTO) {
        let descriptor = FetchDescriptor<CatalogItem>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.imageUrl = dto.imageUrl
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
        try? modelContext.save()
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

        let variantId = dto.id
        let existingJoinDescriptor = FetchDescriptor<CatalogVariantOptionValue>(
            predicate: #Predicate { $0.variantId == variantId }
        )
        if let existingJoins = try? modelContext.fetch(existingJoinDescriptor) {
            for join in existingJoins {
                modelContext.delete(join)
            }
        }
        for (_, valueId) in joinSelections where !valueId.isEmpty {
            let join = CatalogVariantOptionValue(variantId: dto.id, optionValueId: valueId)
            join.lastSyncedAt = Date()
            modelContext.insert(join)
        }
        try? modelContext.save()
    }

    private func optionsForFamily(_ familyId: String?) -> [CatalogOption] {
        guard let familyId else { return [] }
        return allOptions
            .filter { $0.catalogItemId == familyId }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

enum VariantOptionSelectionState {
    static func selections(
        variantId: String,
        familyOptions: [CatalogOption],
        optionValues: [CatalogOptionValue],
        variantOptionValues: [CatalogVariantOptionValue]
    ) -> [String: String] {
        let selectedValueIds = Set(variantOptionValues
            .filter { $0.variantId == variantId }
            .map(\.optionValueId))
        let seed = Dictionary<String, String>(uniqueKeysWithValues: familyOptions.compactMap { option in
            guard let value = optionValues.first(where: {
                selectedValueIds.contains($0.id) && $0.optionId == option.id
            }) else { return nil }
            return (option.id, value.id)
        })
        return validSelections(seed, familyOptions: familyOptions, optionValues: optionValues)
    }

    static func validSelections(
        _ selections: [String: String],
        familyOptions: [CatalogOption],
        optionValues: [CatalogOptionValue]
    ) -> [String: String] {
        var cleaned: [String: String] = [:]
        let valuesById = Dictionary(uniqueKeysWithValues: optionValues.map { ($0.id, $0) })

        for option in familyOptions {
            guard let selectedValueId = selections[option.id],
                  let value = valuesById[selectedValueId],
                  value.optionId == option.id
            else { continue }
            cleaned[option.id] = selectedValueId
        }

        return cleaned
    }
}
