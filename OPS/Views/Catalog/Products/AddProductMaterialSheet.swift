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
//  Draft mode (added bug 164e0595): when `onDraftReady` is supplied
//  instead of `onCreated`, the sheet skips the repo round-trip and bundles
//  the user's selections into a `PendingProductMaterial`. The new-product
//  flow (QuickAddProductSheet) collects these so recipe rows can be
//  authored before the parent Product exists, then committed against the
//  real productId once create returns.
//

import SwiftUI
import SwiftData

/// Staged recipe row used while a brand-new Product is being authored. The
/// productId doesn't exist yet, so the row can't be written; instead it's
/// held in QuickAddProductSheet's local state and committed in a second
/// pass after Product create returns the id.
///
/// Variant-pinned only — same v1 scope as AddProductMaterialSheet's create
/// path. Family-pinned recipes with selectors stay web-only.
struct PendingProductMaterial: Identifiable {
    /// Local-only uuid for list rendering. Discarded once the row is
    /// written; the persisted row's id comes back from the server.
    let id: String
    let catalogVariantId: String
    let familyName: String
    let variantLabel: String
    let quantityPerUnit: Double
    let unitDisplay: String?
    let notes: String?
}

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
    /// Draft-mode callback. When non-nil, `save()` skips the repo call and
    /// hands a PendingProductMaterial back to the caller instead. Mutually
    /// exclusive with create/edit-mode behavior.
    let onDraftReady: ((PendingProductMaterial) -> Void)?

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allFamilies: [CatalogItem]
    @Query private var allVariants: [CatalogVariant]
    @Query private var allUnits: [CatalogUnit]
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

    /// Drives presentation of the Stock-tab Add Family sheet when the
    /// user lands here on a brand-new company (zero families) and wants
    /// to author one without dismissing this sheet, navigating to STOCK,
    /// and coming back. Same idea as the category/unit inline create on
    /// QuickAddProductSheet — empty-state remediation.
    @State private var showingNewFamilySheet: Bool = false

    /// Same idea for variants: when a family has zero variants, the user
    /// can spawn VariantFormSheet pre-bound to the selected family and
    /// author one without leaving this flow.
    @State private var showingNewVariantSheet: Bool = false

    @FocusState private var quantityFocused: Bool

    private var isEditing: Bool { editingMaterial != nil }
    private var isDraftMode: Bool { onDraftReady != nil }
    private var navTitle: String {
        if isEditing { return "EDIT MATERIAL" }
        if isDraftMode { return "ADD COMPONENT" }
        return "ADD MATERIAL"
    }

    /// Default backwards-compat init — create / edit mode against an
    /// existing Product. Lets the existing callers in RecipeManageSheet
    /// stay unchanged.
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
        self.onDraftReady = nil
    }

    /// Draft-mode init — used by QuickAddProductSheet when authoring recipe
    /// rows for a Product that hasn't been created yet. The sheet doesn't
    /// hit the network or SwiftData; it bundles the user's selections into
    /// a `PendingProductMaterial` and hands it back via `onDraftReady`.
    init(
        companyId: String,
        onDraftReady: @escaping (PendingProductMaterial) -> Void
    ) {
        self.productId = ""
        self.companyId = companyId
        self.editingMaterial = nil
        self.onCreated = { _ in }
        self.onDraftReady = onDraftReady
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
        .sheet(isPresented: $showingNewFamilySheet) {
            // The Stock-tab AddFamilySheet doesn't take a callback —
            // dismissal is enough because the SwiftData @Query in this
            // view picks up the new row reactively. Family selection
            // stays nil; the user picks the new family from the picker.
            AddFamilySheet()
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingNewVariantSheet) {
            // Pre-bind to the currently-selected family so the variant
            // form doesn't ask the user to pick the same thing twice.
            // If selectedFamilyId is somehow nil (it shouldn't be — the
            // button only renders when a family is selected and has zero
            // variants), VariantFormSheet falls back to its own family
            // picker.
            VariantFormSheet(initialFamily: selectedFamily)
                .environmentObject(dataController)
        }
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
            // Empty-state remediation. The "+ NEW…" entry points live
            // outside the picker (rather than as a Menu item) so a healthy
            // inventory has zero clutter — see plan Phase 6: only on
            // empty states. Hidden in edit mode.
            if !isEditing && companyFamilies.isEmpty {
                inlineCreateButton(label: "+ NEW FAMILY") {
                    showingNewFamilySheet = true
                }
            }

            CatalogFieldLabel("Variant")
            variantPicker
            if !isEditing && selectedFamilyId != nil && variantsForSelectedFamily.isEmpty {
                inlineCreateButton(label: "+ NEW VARIANT") {
                    showingNewVariantSheet = true
                }
            }
        }
    }

    /// Pill-styled inline create entry point. Distinct from the SAVE
    /// affordance — uses the dimmer cardBorder accent so the user reads
    /// it as a remedial action, not the primary path. Sized to OPS
    /// minimum touch target.
    @ViewBuilder
    private func inlineCreateButton(label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "plus")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                Text(label)
                    .font(OPSStyle.Typography.metadata)
                Spacer()
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
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

        // Draft mode: parent Product doesn't exist yet, so we can't write
        // a real product_materials row. Bundle the selection and hand it
        // back to the caller for staging — QuickAddProductSheet flushes
        // these after the parent product is created.
        if let onDraftReady = onDraftReady {
            let unit = allUnits.first(where: { $0.id == selectedVariant?.unitId })
                       ?? allUnits.first(where: { $0.id == selectedFamily?.defaultUnitId })
            let pending = PendingProductMaterial(
                id: UUID().uuidString,
                catalogVariantId: variantId,
                familyName: selectedFamily?.name ?? "Unknown",
                variantLabel: variantDisplayLabel(for: selectedVariant),
                quantityPerUnit: quantity,
                unitDisplay: unit?.display,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDraftReady(pending)
            dismiss()
            return
        }

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

    /// Best-effort label for a variant: SKU first, then concatenated option
    /// values, falling back to the family name + variant id. Used for the
    /// staged-row display in QuickAddProductSheet so the user can recognise
    /// what they added without opening the row again.
    private func variantDisplayLabel(for variant: CatalogVariant?) -> String {
        guard let variant else { return "Variant" }
        if let sku = variant.sku, !sku.isEmpty { return sku }
        let optionValueIds = allVariantOptionValues
            .filter { $0.variantId == variant.id }
            .map(\.optionValueId)
        let labels = allOptionValues
            .filter { optionValueIds.contains($0.id) }
            .map(\.value)
        if !labels.isEmpty {
            return labels.joined(separator: " · ")
        }
        return selectedFamily?.name ?? "Variant"
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
