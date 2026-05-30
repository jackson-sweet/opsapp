//
//  RecipeManageSheet.swift
//  OPS
//
//  Outer manage sheet for a Product's recipe (its ProductMaterial rows).
//  Lists every row with an inline delete affordance, surfaces an empty
//  state when no rows exist, and exposes a primary action for opening
//  AddProductMaterialSheet to insert new rows. The list refreshes via
//  @Query reacting to SwiftData inserts and deletes — no manual refresh
//  trigger needed after the inner sheet returns.
//
//  Destructive deletes go through a confirmation alert per OPS field
//  conventions: any irreversible action requires explicit re-tap so a
//  gloved finger doesn't wipe a recipe row by accident.
//

import SwiftUI
import SwiftData

struct RecipeManageSheet: View {
    let product: Product

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allMaterials: [ProductMaterial]
    @Query private var allOptions: [ProductOption]
    @Query private var allFamilies: [CatalogItem]
    @Query private var allVariants: [CatalogVariant]
    @Query private var allCatalogOptions: [CatalogOption]
    @Query private var allCatalogOptionValues: [CatalogOptionValue]
    @Query private var allVariantOptionValues: [CatalogVariantOptionValue]
    @Query private var allUnits: [CatalogUnit]

    @State private var showingAddSheet: Bool = false
    @State private var editingMaterial: ProductMaterial? = nil
    @State private var pendingDelete: ProductMaterial? = nil
    @State private var isDeleting: Bool = false
    @State private var errorMessage: String? = nil

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var productMaterials: [ProductMaterial] {
        allMaterials
            .filter { $0.productId == product.id }
            .sorted { ($0.id) < ($1.id) }
    }

    private var productOptions: [ProductOption] {
        allOptions
            .filter { $0.productId == product.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        if productMaterials.isEmpty {
                            emptyState
                        } else {
                            recipeList
                        }
                        addButton
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
            .navigationTitle("RECIPE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingAddSheet) {
            AddProductMaterialSheet(
                productId: product.id,
                companyId: companyId,
                onCreated: { _ in
                    // The inner sheet inserts into SwiftData and dismisses
                    // itself; @Query refreshes the list automatically.
                }
            )
            .environmentObject(dataController)
        }
        .sheet(item: $editingMaterial) { material in
            // Reuse the same sheet in edit mode — identity pickers lock,
            // only quantity + notes are mutable. See AddProductMaterialSheet
            // for the create/update branching logic.
            AddProductMaterialSheet(
                productId: product.id,
                companyId: companyId,
                editingMaterial: material,
                onCreated: { _ in
                    // The inner sheet has already mutated the SwiftData
                    // row and dismissed itself; @Query reflects the change.
                }
            )
            .environmentObject(dataController)
        }
        .alert("Remove material?",
               isPresented: Binding(
                   get: { pendingDelete != nil },
                   set: { if !$0 { pendingDelete = nil } }
               ),
               presenting: pendingDelete) { material in
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Remove", role: .destructive) {
                Task { await delete(material) }
            }
        } message: { _ in
            Text("Remove this material from the recipe?")
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Text("// NO MATERIALS YET — TAP + ADD MATERIAL")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }

    // MARK: - Recipe list

    @ViewBuilder
    private var recipeList: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("MATERIALS · \(productMaterials.count)")
            ForEach(productMaterials) { material in
                row(material)
            }
        }
    }

    @ViewBuilder
    private func row(_ material: ProductMaterial) -> some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(displayLine(material))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.leading)
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    pinChip(material)
                    if let scaledLabel = scaledByLabel(material) {
                        metadataChip(scaledLabel)
                    }
                    Spacer()
                }
                if let notes = material.notes, !notes.isEmpty {
                    Text(notes)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            editButton(material)
            deleteButton(material)
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

    /// Pencil button — opens AddProductMaterialSheet in edit mode for
    /// this row. Family + variant lock; quantity + notes are mutable.
    /// Sized to OPS minimum touch target (44pt) so the row exposes both
    /// edit and delete without crowding gloves on either.
    @ViewBuilder
    private func editButton(_ material: ProductMaterial) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            editingMaterial = material
        } label: {
            Image(OPSStyle.Icons.edit)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: OPSStyle.Layout.touchTargetMin,
                       height: OPSStyle.Layout.touchTargetMin)
        }
        .accessibilityLabel("Edit material")
        .disabled(isDeleting)
    }

    @ViewBuilder
    private func deleteButton(_ material: ProductMaterial) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            pendingDelete = material
        } label: {
            Image(OPSStyle.Icons.delete)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.brick)
                .frame(width: OPSStyle.Layout.touchTargetMin,
                       height: OPSStyle.Layout.touchTargetMin)
        }
        .accessibilityLabel("Remove material")
        .disabled(isDeleting)
    }

    // MARK: - Add button

    @ViewBuilder
    private var addButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingAddSheet = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(OPSStyle.Icons.plus)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                Text("ADD MATERIAL")
                    .font(OPSStyle.Typography.buttonLabel)
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Row helpers (lifted from RecipeReadOnlyView so the manage
    // sheet renders the same way the read-only product detail does)

    private func displayLine(_ material: ProductMaterial) -> String {
        let qty = formatQuantity(material.quantityPerUnit)
        let unit = unitDisplay(material)
        let qtyClause = unit.isEmpty ? qty : "\(qty)/\(unit)"

        if let variantId = material.catalogVariantId,
           let variant = allVariants.first(where: { $0.id == variantId }),
           let family = allFamilies.first(where: { $0.id == variant.catalogItemId }) {
            let variantSuffix = variantSuffix(for: variant)
            return variantSuffix.isEmpty
                ? "\(family.name) — \(qtyClause)"
                : "\(family.name) · \(variantSuffix) — \(qtyClause)"
        }

        if let itemId = material.catalogItemId,
           let family = allFamilies.first(where: { $0.id == itemId }) {
            let selectorClause = selectorPhrase(material)
            return selectorClause.isEmpty
                ? "\(family.name) — \(qtyClause)"
                : "\(family.name) (\(selectorClause)) — \(qtyClause)"
        }

        return "Unresolved material — \(qtyClause)"
    }

    private func variantSuffix(for variant: CatalogVariant) -> String {
        let familyOptions = allCatalogOptions
            .filter { $0.catalogItemId == variant.catalogItemId }
            .sorted { $0.sortOrder < $1.sortOrder }
        let variantValueIds = Set(allVariantOptionValues
            .filter { $0.variantId == variant.id }
            .map { $0.optionValueId })
        let valuesById = Dictionary(uniqueKeysWithValues: allCatalogOptionValues.map { ($0.id, $0) })

        var parts: [String] = []
        for option in familyOptions {
            if let v = variantValueIds
                .compactMap({ valuesById[$0] })
                .first(where: { $0.optionId == option.id }) {
                parts.append(v.value)
            }
        }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        if let sku = variant.sku, !sku.isEmpty { return sku }
        return ""
    }

    private func selectorPhrase(_ material: ProductMaterial) -> String {
        guard
            let json = material.variantSelectorJSON,
            let data = json.data(using: .utf8),
            let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return "" }
        return raw
            .map { key, value in "\(key) = \(stringify(value))" }
            .sorted()
            .joined(separator: ", ")
    }

    private func stringify(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let b = value as? Bool { return b ? "true" : "false" }
        return "\(value)"
    }

    private func pinChip(_ material: ProductMaterial) -> some View {
        let label: String = {
            if material.catalogVariantId != nil { return "VARIANT" }
            if material.catalogItemId != nil { return "FAMILY" }
            return "UNRESOLVED"
        }()
        return Text(label)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private func scaledByLabel(_ material: ProductMaterial) -> String? {
        guard let optionId = material.scaledByOptionId,
              let option = productOptions.first(where: { $0.id == optionId }) else { return nil }
        return "SCALED BY \(option.name.uppercased())"
    }

    private func unitDisplay(_ material: ProductMaterial) -> String {
        if let unitId = material.unitId,
           let unit = allUnits.first(where: { $0.id == unitId }) {
            return unit.display
        }
        return ""
    }

    private func formatQuantity(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func metadataChip(_ label: String) -> some View {
        Text(label)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    // MARK: - Delete

    @MainActor
    private func delete(_ material: ProductMaterial) async {
        guard !isDeleting else { return }
        let id = material.id

        isDeleting = true
        defer { isDeleting = false }
        errorMessage = nil

        let repo = ProductRichnessRepository(companyId: companyId)
        do {
            try await repo.deleteMaterial(id)
            modelContext.delete(material)
            try? modelContext.save()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            pendingDelete = nil
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
            pendingDelete = nil
        }
    }
}
