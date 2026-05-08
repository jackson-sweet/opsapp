//
//  AddProductMaterialSheet.swift
//  OPS
//
//  Inner sheet that authors a single ProductMaterial recipe row from the
//  iOS catalog. Two-tier Menu picker: outer choice is a CatalogItem
//  (family), inner choice is a CatalogVariant within that family. Once
//  the user has a variant + a numeric quantity-per-unit, Save calls
//  ProductRichnessRepository.createMaterial, inserts the returned row
//  into SwiftData, and fires the onCreated callback so the outer manage
//  sheet's @Query refreshes.
//
//  v1 scope intentionally narrows to variant-pinned rows — the advanced
//  family-pin (catalogItemId + variantSelectorJSON) and scaledByOptionId
//  authoring stays on web. Comment in `save()` documents this so future
//  contributors don't think the omission was an oversight.
//

import SwiftUI
import SwiftData

struct AddProductMaterialSheet: View {
    let productId: String
    let companyId: String
    /// When non-nil, the sheet renders in edit mode: family + variant
    /// pickers are locked to the row's identity, only quantity and notes
    /// are mutable, and Save calls `updateMaterial` instead of
    /// `createMaterial`. Identity changes (re-pinning to a different
    /// variant) require delete + re-add per the recipe row identity model
    /// — this matches the CHECK constraint on the table.
    let editingMaterial: ProductMaterial?
    let onCreated: (ProductMaterialDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allFamilies: [CatalogItem]
    @Query private var allVariants: [CatalogVariant]
    @Query private var allOptions: [CatalogOption]
    @Query private var allOptionValues: [CatalogOptionValue]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]

    @State private var selectedFamilyId: String? = nil
    @State private var selectedVariantId: String? = nil
    @State private var quantityString: String = ""
    @State private var notes: String = ""

    @State private var isSaving: Bool = false
    @State private var quantityParseError: Bool = false
    @State private var errorMessage: String? = nil

    @FocusState private var quantityFocused: Bool

    private var isEditing: Bool { editingMaterial != nil }
    private var navTitle: String { isEditing ? "EDIT MATERIAL" : "ADD MATERIAL" }

    /// Default backwards-compat init — create-mode only. Lets the existing
    /// callers in RecipeManageSheet stay unchanged. Edit callers pass
    /// `editingMaterial:` explicitly.
    init(
        productId: String,
        companyId: String,
        editingMaterial: ProductMaterial? = nil,
        onCreated: @escaping (ProductMaterialDTO) -> Void
    ) {
        self.productId = productId
        self.companyId = companyId
        self.editingMaterial = editingMaterial
        self.onCreated = onCreated
    }

    // MARK: - Filtered company data

    private var companyFamilies: [CatalogItem] {
        allFamilies
            .filter { $0.companyId == companyId && $0.deletedAt == nil && $0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var variantsForSelectedFamily: [CatalogVariant] {
        guard let familyId = selectedFamilyId else { return [] }
        return allVariants
            .filter { $0.companyId == companyId
                && $0.catalogItemId == familyId
                && $0.deletedAt == nil
                && $0.isActive }
            .sorted { lhs, rhs in
                // Sort by SKU when present; fall back to id for stability.
                let l = lhs.sku ?? lhs.id
                let r = rhs.sku ?? rhs.id
                return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
            }
    }

    private var selectedFamily: CatalogItem? {
        guard let id = selectedFamilyId else { return nil }
        return companyFamilies.first(where: { $0.id == id })
    }

    private var selectedVariant: CatalogVariant? {
        guard let id = selectedVariantId else { return nil }
        return allVariants.first(where: { $0.id == id })
    }

    private var canSave: Bool {
        guard !isSaving else { return false }
        // In edit mode, family + variant identity is fixed by the row.
        // Family-pinned rows have selectedVariantId == nil, so the create
        // path's variant guard would block save. Edit mode only requires
        // a positive quantity.
        if !isEditing {
            guard selectedFamilyId != nil,
                  selectedVariantId != nil
            else { return false }
        }
        let trimmed = quantityString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = Double(trimmed),
              parsed > 0
        else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        materialSection
                        quantitySection
                        notesSection
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
                .dismissKeyboardOnTap()
            }
            .navigationTitle(navTitle)
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
            .onAppear { hydrateFromEditingMaterial() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Pre-fills the form when entering edit mode. Family/variant come
    /// from the row's existing pin; quantity + notes come from the row's
    /// current values. Variant-pinned rows hydrate fully; family-pinned
    /// rows (catalogItemId set, catalogVariantId nil) hydrate just the
    /// family — the iOS sheet doesn't author family-pinned rows but it
    /// can edit their quantity/notes via the same form.
    private func hydrateFromEditingMaterial() {
        guard let row = editingMaterial else { return }
        if let variantId = row.catalogVariantId,
           let variant = allVariants.first(where: { $0.id == variantId }) {
            selectedFamilyId = variant.catalogItemId
            selectedVariantId = variant.id
        } else if let itemId = row.catalogItemId {
            selectedFamilyId = itemId
            selectedVariantId = nil
        }
        quantityString = formatQuantityForField(row.quantityPerUnit)
        notes = row.notes ?? ""
    }

    private func formatQuantityForField(_ value: Double) -> String {
        if value == 0 { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - Material section (two-tier picker)

    @ViewBuilder
    private var materialSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("MATERIAL")

            CatalogFieldLabel("Family")
            familyPicker
            if companyFamilies.isEmpty {
                Text("// NO FAMILIES YET — ADD STOCK BEFORE BUILDING A RECIPE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            CatalogFieldLabel("Variant")
            variantPicker
            if selectedFamilyId != nil && variantsForSelectedFamily.isEmpty {
                Text("// NO VARIANTS ON THIS FAMILY — AUTHOR ONE FIRST")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }

    private var familyPicker: some View {
        // Identity-locked when editing: changing family means re-pinning
        // the row to a different variant, which the schema CHECK constraint
        // disallows in-place. Edit mode renders the family as a static
        // chip-styled label so the user sees what they're editing.
        Menu {
            if companyFamilies.isEmpty {
                Text("No families")
            } else {
                ForEach(companyFamilies) { family in
                    Button {
                        if selectedFamilyId != family.id {
                            // Switching family invalidates the variant choice.
                            selectedVariantId = nil
                        }
                        selectedFamilyId = family.id
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if selectedFamilyId == family.id {
                            Label(family.name, systemImage: "checkmark")
                        } else {
                            Text(family.name)
                        }
                    }
                }
            }
        } label: {
            menuLabel(text: selectedFamily?.name ?? "Select family")
        }
        .disabled(companyFamilies.isEmpty || isEditing)
    }

    private var variantPicker: some View {
        Menu {
            if variantsForSelectedFamily.isEmpty {
                Text("No variants")
            } else {
                ForEach(variantsForSelectedFamily) { variant in
                    Button {
                        selectedVariantId = variant.id
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        if selectedVariantId == variant.id {
                            Label(variantLabel(variant), systemImage: "checkmark")
                        } else {
                            Text(variantLabel(variant))
                        }
                    }
                }
            }
        } label: {
            menuLabel(text: selectedVariantDisplay)
        }
        .disabled(selectedFamilyId == nil || variantsForSelectedFamily.isEmpty || isEditing)
    }

    private var selectedVariantDisplay: String {
        guard let variant = selectedVariant else {
            return selectedFamilyId == nil ? "Pick family first" : "Select variant"
        }
        return variantLabel(variant)
    }

    /// Variant label using the option-value join chain. Mirrors the
    /// pattern used in `OrderDetailView.variantLabel(for:)`. Falls back
    /// to "FAMILY · sku" if the variant has no option joins (single-
    /// variant family) and finally to "FAMILY" if there's no SKU either.
    private func variantLabel(_ variant: CatalogVariant) -> String {
        let familyName = allFamilies.first(where: { $0.id == variant.catalogItemId })?.name ?? ""

        let familyOptions = allOptions
            .filter { $0.catalogItemId == variant.catalogItemId }
            .sorted { $0.sortOrder < $1.sortOrder }

        let variantValueIds = Set(allVariantOptionValues
            .filter { $0.variantId == variant.id }
            .map { $0.optionValueId })

        let valuesById = Dictionary(uniqueKeysWithValues: allOptionValues.map { ($0.id, $0) })

        var parts: [String] = []
        for option in familyOptions {
            if let v = variantValueIds
                .compactMap({ valuesById[$0] })
                .first(where: { $0.optionId == option.id }) {
                parts.append(v.value)
            }
        }

        if !parts.isEmpty {
            return "\(familyName) · \(parts.joined(separator: " · "))"
        }
        if let sku = variant.sku, !sku.isEmpty {
            return "\(familyName) · \(sku)"
        }
        return familyName
    }

    // MARK: - Quantity section

    @ViewBuilder
    private var quantitySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("QUANTITY")
            CatalogFieldLabel("Per product unit")
            TextField("e.g. 1.5", text: $quantityString)
                .keyboardType(.decimalPad)
                .textFieldStyle(CatalogTextFieldStyle())
                .focused($quantityFocused)
                .onChange(of: quantityString) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        quantityParseError = false
                    } else if let parsed = Double(trimmed) {
                        quantityParseError = parsed <= 0
                    } else {
                        quantityParseError = true
                    }
                }
            if quantityParseError {
                Text("Quantity must be a positive number")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.errorText)
            }
        }
    }

    // MARK: - Notes section

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("NOTES")
            TextField("Optional", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(CatalogTextFieldStyle())
        }
    }

    // MARK: - Menu label visual (matches CatalogTextFieldStyle)

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

    // MARK: - Save

    @MainActor
    private func save() async {
        guard canSave,
              let parsedQuantity = Double(quantityString.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = ProductRichnessRepository(companyId: companyId)

        if let editing = editingMaterial {
            await runUpdate(
                repo: repo,
                row: editing,
                quantity: parsedQuantity,
                notes: trimmedNotes
            )
        } else {
            await runCreate(
                repo: repo,
                quantity: parsedQuantity,
                notes: trimmedNotes
            )
        }
    }

    @MainActor
    private func runCreate(
        repo: ProductRichnessRepository,
        quantity: Double,
        notes trimmedNotes: String
    ) async {
        guard let variantId = selectedVariantId else { return }

        // v1 scope: variant-pinned rows only. Family-pinned recipe rows
        // (catalogItemId + variantSelectorJSON) and scaledByOptionId
        // (e.g. corner hardware kits scaled by Corners count) stay
        // authored on web — too many degrees of freedom to surface on
        // iOS without a heavier picker. The mutually-exclusive CHECK
        // constraint on (catalog_variant_id, catalog_item_id) means we
        // pass nil for catalogItemId here.
        let dto = CreateProductMaterialDTO(
            productId: productId,
            catalogVariantId: variantId,
            catalogItemId: nil,
            variantSelector: nil,
            quantityPerUnit: quantity,
            scaledByOptionId: nil,
            unitId: nil,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )

        do {
            let createdDTO = try await repo.createMaterial(dto)
            let model = createdDTO.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCreated(createdDTO)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func runUpdate(
        repo: ProductRichnessRepository,
        row: ProductMaterial,
        quantity: Double,
        notes trimmedNotes: String
    ) async {
        // Build a sparse patch that only carries fields the user actually
        // touched. Identity columns (catalogVariantId / catalogItemId /
        // variantSelector) are intentionally excluded — see UpdateProductMaterialDTO.
        var fields = UpdateProductMaterialDTO()
        if quantity != row.quantityPerUnit {
            fields.quantityPerUnit = quantity
        }
        let normalizedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        if normalizedNotes != row.notes {
            fields.notes = normalizedNotes
        }

        do {
            let updatedDTO = try await repo.updateMaterial(row.id, fields: fields)
            // Apply the canonical server payload to the local row in-place
            // — keeps SwiftData consistent without an extra full-table sync.
            row.quantityPerUnit = updatedDTO.quantityPerUnit
            row.notes = updatedDTO.notes
            row.unitId = updatedDTO.unitId
            row.scaledByOptionId = updatedDTO.scaledByOptionId
            row.lastSyncedAt = Date()
            row.needsSync = false
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // The onCreated callback name is a legacy from create-only;
            // edit callers ignore it. Fire it anyway so any future caller
            // wanting a "save happened" hook keeps a consistent contract.
            onCreated(updatedDTO)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}
