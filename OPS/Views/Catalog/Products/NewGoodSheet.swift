//
//  NewGoodSheet.swift
//  OPS
//
//  Kind-tailored create sheet for GOODS (physical products). Locks
//  `kind='material'` and `type='MATERIAL'`. Keeps the unit-cost field,
//  the live margin readout, and the thumbnail picker — physical goods
//  benefit from all three. Default pricing unit is "each".
//
//  // SHOW IN STOCK is shown as a hint chip but does NOT eagerly link to
//  the catalog — for v1 the operator wires the goods row into stock via
//  the existing Stock segment flow. The toggle is a discoverability cue;
//  full linkage stays in scope of the dedicated stock UI.
//

import SwiftUI
import SwiftData
import PhotosUI

struct NewGoodSheet: View {
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
    @State private var unitCostString: String = ""
    @State private var productDescription: String = ""
    @State private var sku: String = ""
    @State private var taxable: Bool = true
    @State private var showAdvanced: Bool = false

    // Thumbnail
    @State private var thumbnailPickerItem: PhotosPickerItem? = nil
    @State private var thumbnailImage: UIImage? = nil
    @State private var thumbnailUploadFailedProductId: String? = nil
    @State private var isUploadingThumbnail: Bool = false

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var priceParseError: Bool = false
    @State private var unitCostParseError: Bool = false

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
                            if canManageProducts {
                                thumbnailField
                            }
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
            .navigationTitle("NEW GOOD")
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

    @ViewBuilder
    private var coreFields: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("GOOD")
            CatalogFieldLabel("Name")
            TextField("e.g. 5/4 composite board", text: $name)
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
    private var thumbnailField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("THUMBNAIL")
            ThumbnailPickerField(
                pickerItem: $thumbnailPickerItem,
                image: $thumbnailImage,
                errorMessage: nil
            )
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

                liveMarginReadout

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

    private var liveMarginPercent: Double? {
        let trimmedPrice = priceString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCost = unitCostString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let price = Double(trimmedPrice), price > 0 else { return nil }
        guard let cost = Double(trimmedCost), cost >= 0 else { return nil }
        return ((price - cost) / price) * 100
    }

    @ViewBuilder
    private var liveMarginReadout: some View {
        if let margin = liveMarginPercent {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("// MARGIN")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                Text("\(Int(margin.rounded()))%")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(margin >= 0
                                     ? OPSStyle.Colors.tertiaryText
                                     : OPSStyle.Colors.errorText)
            }
        }
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
                    if thumbnailUploadFailedProductId != nil {
                        Task { await retryThumbnailUpload() }
                    } else {
                        Task { await save() }
                    }
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
                .accessibilityLabel("Retry saving good")
                .disabled(isSaving || isUploadingThumbnail)
            }
        }
    }

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
                        Text("SAVE GOOD")
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
        .tint(OPSStyle.Colors.primaryAccent)
        .onChange(of: saveAndAddAnother) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// Hydrate the default unit to "each" when present. Most goods sell by
    /// the unit; saves an extra tap on the common case.
    private func hydrateDefaultUnit() {
        guard selectedUnitId == nil else { return }
        let match = companyUnits.first { unit in
            let lower = unit.display.lowercased()
            return lower == "each" || lower == "ea" || lower == "unit" || lower == "pc" || lower == "piece"
        }
        selectedUnitId = match?.id
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
        let parsedUnitCost = trimmedUnitCost.isEmpty ? nil : Double(trimmedUnitCost)

        let selectedUnit = companyUnits.first(where: { $0.id == selectedUnitId })
        let selectedCategory = companyCategories.first(where: { $0.id == selectedCategoryId })
        let pricingUnitRaw = pricingUnit(for: selectedUnit).rawValue

        var dto = CreateProductDTO(
            companyId: companyId,
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            basePrice: parsedPrice,
            unitCost: parsedUnitCost,
            unit: selectedUnit?.display,
            pricingUnit: pricingUnitRaw,
            unitId: selectedUnit?.id,
            category: selectedCategory?.name,
            categoryId: selectedCategory?.id,
            sku: trimmedSku.isEmpty ? nil : trimmedSku,
            thumbnailUrl: nil,
            kind: "material",
            type: LineItemType.material.rawValue,
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

            // Thumbnail upload happens AFTER product create so we have a
            // productId for the object path. Failure surfaces a retry CTA;
            // we never roll back the parent row.
            var thumbnailFailed = false
            if let image = thumbnailImage, canManageProducts {
                isUploadingThumbnail = true
                do {
                    let url = try await ProductThumbnailUploader.shared.upload(
                        image,
                        productId: createdDTO.id,
                        companyId: companyId
                    )
                    var patch = UpdateProductDTO()
                    patch.thumbnailUrl = url.absoluteString
                    let patched = try await repo.update(createdDTO.id, fields: patch)
                    applyThumbnailURL(patched.thumbnailUrl, productId: createdDTO.id)
                } catch {
                    thumbnailFailed = true
                    thumbnailUploadFailedProductId = createdDTO.id
                    print("[NewGoodSheet] Thumbnail upload failed: \(error)")
                }
                isUploadingThumbnail = false
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if thumbnailFailed {
                errorMessage = "// THUMBNAIL UPLOAD FAILED — TAP RETRY TO TRY AGAIN"
                return
            }

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
    private func retryThumbnailUpload() async {
        guard let productId = thumbnailUploadFailedProductId,
              let image = thumbnailImage else { return }
        isUploadingThumbnail = true
        defer { isUploadingThumbnail = false }
        errorMessage = nil

        let repo = ProductRepository(companyId: companyId)
        do {
            let url = try await ProductThumbnailUploader.shared.upload(
                image,
                productId: productId,
                companyId: companyId
            )
            var patch = UpdateProductDTO()
            patch.thumbnailUrl = url.absoluteString
            let patched = try await repo.update(productId, fields: patch)
            applyThumbnailURL(patched.thumbnailUrl, productId: productId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            thumbnailUploadFailedProductId = nil
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
    private func applyThumbnailURL(_ url: String?, productId: String) {
        guard let url else { return }
        let descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.id == productId })
        if let local = try? modelContext.fetch(descriptor).first {
            local.thumbnailUrl = url
            try? modelContext.save()
        }
    }

    @MainActor
    private func resetForNextEntry() {
        name = ""
        priceString = ""
        unitCostString = ""
        productDescription = ""
        sku = ""
        priceParseError = false
        unitCostParseError = false
        errorMessage = nil
        thumbnailImage = nil
        thumbnailPickerItem = nil
        thumbnailUploadFailedProductId = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            nameFieldFocused = true
        }
    }
}
