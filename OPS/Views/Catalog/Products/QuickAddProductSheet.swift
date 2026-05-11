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
import PhotosUI

struct QuickAddProductSheet: View {
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

    // Thumbnail picker state. The image is held locally until the product
    // is saved — then we upload it via ProductThumbnailUploader and PATCH
    // the new URL onto the just-created row. Picker uses PhotosUI's
    // PhotosPicker (single image, .images filter) for parity with
    // EmployeeProfileView's avatar flow.
    @State private var thumbnailPickerItem: PhotosPickerItem? = nil
    @State private var thumbnailImage: UIImage? = nil
    /// Becomes non-nil when the product is saved successfully but the
    /// follow-up Storage upload fails. The user can tap to retry without
    /// rolling back the (already-created) product.
    @State private var thumbnailUploadFailedProductId: String? = nil
    @State private var isUploadingThumbnail: Bool = false

    private var canManageProducts: Bool { permissionStore.can("catalog.products.manage") }

    /// User-pinned preference. When ON, a successful save resets the form
    /// (keeping category + unit selections) and refocuses the name field
    /// instead of dismissing — so the user can keep loading new products
    /// without re-opening the sheet between each one.
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
                            if canManageProducts {
                                thumbnailField
                            }
                            categoryField
                            advancedDisclosure
                            footerNote
                            errorRow
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }
                    // Tap-outside dismisses the keyboard so the user can
                    // reach the SAVE bar without first tapping a non-field
                    // element to lower the keyboard.
                    .dismissKeyboardOnTap()

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

    // MARK: - Thumbnail picker (uploads after save)

    @ViewBuilder
    private var thumbnailField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("THUMBNAIL")

            if let image = thumbnailImage {
                // Picked-state: preview the image with REPLACE + REMOVE
                // controls. Layout matches the rest of the form (card
                // background, hairline border) so it doesn't feel like
                // a stowaway component.
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder,
                                        lineWidth: OPSStyle.Layout.Border.standard)
                        )

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        PhotosPicker(
                            selection: $thumbnailPickerItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Text("// REPLACE")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .padding(.vertical, OPSStyle.Layout.spacing1)
                                .frame(minHeight: OPSStyle.Layout.touchTargetMin / 2)
                        }
                        .accessibilityLabel("Replace thumbnail")

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            thumbnailImage = nil
                            thumbnailPickerItem = nil
                        } label: {
                            Text("// REMOVE")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.errorText)
                                .padding(.vertical, OPSStyle.Layout.spacing1)
                                .frame(minHeight: OPSStyle.Layout.touchTargetMin / 2)
                        }
                        .accessibilityLabel("Remove thumbnail")
                    }

                    Spacer()
                }
            } else {
                // Empty-state: tap target large enough for gloves, voice
                // matches the rest of the form ("// + ADD ..."). PhotosPicker
                // is the same flavour used in EmployeeProfileView so the
                // permission affordance is consistent across the app.
                PhotosPicker(
                    selection: $thumbnailPickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "plus")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("// + ADD THUMBNAIL")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                    }
                    .padding(OPSStyle.Layout.spacing2)
                    .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard, alignment: .leading)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
                .accessibilityLabel("Add thumbnail")
            }
        }
        .onChange(of: thumbnailPickerItem) { _, newItem in
            // Load the picked photo into a UIImage so the preview can
            // render and so we have something to hand to the uploader at
            // save time. Mirrors the same Transferable + UIImage flow used
            // in ImagePickerView.
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        thumbnailImage = image
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
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

                liveMarginReadout

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

    /// Computed margin from the parsed price + unit cost. Returns nil when
    /// either field is empty/invalid or price is 0 (avoids divide-by-zero
    /// and avoids displaying a misleading `100%` when cost happens to be
    /// blank).
    private var liveMarginPercent: Double? {
        let trimmedPrice = priceString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCost = unitCostString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let price = Double(trimmedPrice), price > 0 else { return nil }
        guard let cost = Double(trimmedCost), cost >= 0 else { return nil }
        return ((price - cost) / price) * 100
    }

    /// Live margin readout under the SKU/Unit cost row. Shown only when
    /// both fields parse and price > 0. JetBrains Mono numbers per the
    /// OPS number rules — tabular lining via `.monospacedDigit()` so a
    /// 9 → 10 transition doesn't shift the row.
    @ViewBuilder
    private var liveMarginReadout: some View {
        if let margin = liveMarginPercent {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("// MARGIN")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                Text(formattedMargin(margin))
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(margin >= 0
                                     ? OPSStyle.Colors.tertiaryText
                                     : OPSStyle.Colors.errorText)
            }
        }
    }

    /// Formats the margin as a whole-percent integer with a trailing `%`.
    /// Negative margins (cost above price) format with a leading `-` and
    /// render in error color.
    private func formattedMargin(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return "\(rounded)%"
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

    // MARK: - Error row with RETRY

    /// Renders the save error inline with a RETRY button that re-fires
    /// the save Task. Hidden when there's no error. The retry button is
    /// styled as a hairline secondary action so the error message reads
    /// as the primary signal — RETRY is the cue, not the headline.
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
                    // If the product itself created OK and only the
                    // thumbnail upload failed, retry just the upload —
                    // re-running save() would attempt a duplicate insert
                    // and trip the local name-uniqueness pre-check.
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
                .accessibilityLabel("Retry saving product")
                .disabled(isSaving || isUploadingThumbnail)
            }
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
            Text("Need options or pricing modifiers? Save here, then open this product on web → Options.")
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
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)

            saveAndAddAnotherToggle
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing2)
                .padding(.bottom, OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.background)
    }

    /// Pinned-preference toggle. Kept under the save button so the user
    /// can flip it before tapping save — and a 60+pt touch target on the
    /// label means gloves can find it. The setting persists across sheet
    /// dismissals via @AppStorage.
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

        // Local name uniqueness pre-check. Catches the obvious duplicate
        // before we burn a network round-trip — but it's intentionally
        // local-only; a true uniqueness guarantee would need a server-side
        // unique index on (company_id, lower(trim(name))) which is out of
        // scope for this UI fix. If the user goes around it (two devices
        // creating the same name simultaneously), the server still wins.
        let lowerName = trimmedName.lowercased()
        let duplicate = allProducts.first { existing in
            existing.companyId == companyId &&
            existing.isActive &&
            existing.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == lowerName
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

        // Resolve picker selections to the Product schema.
        let selectedUnit = companyUnits.first(where: { $0.id == selectedUnitId })
        let selectedCategory = companyCategories.first(where: { $0.id == selectedCategoryId })
        let categoryName = selectedCategory?.name
        // `pricingUnit(for:)` is the shared helper in CatalogManageHelpers.swift —
        // both create and edit flows use the same mapping so the legacy
        // ProductPricingUnit enum stays in lockstep with the FK.
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
            categoryId: selectedCategory?.id,
            sku: trimmedSku.isEmpty ? nil : trimmedSku,
            thumbnailUrl: nil,
            kind: kind.rawValue,
            type: lineItemType.rawValue,
            isTaxable: taxable,
            taskTypeId: nil
        )

        let repo = ProductRepository(companyId: companyId)
        do {
            let createdDTO = try await repo.create(dto)
            applyCreatedDTO(createdDTO)

            // Phase 4 — thumbnail upload happens AFTER product create so
            // we have a productId for the object path. Failure here does
            // NOT roll back the product; we surface a retry affordance
            // and keep the row visible. Better degrade-gracefully than
            // block the create.
            var thumbnailUploadFailed = false
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
                    thumbnailUploadFailed = true
                    thumbnailUploadFailedProductId = createdDTO.id
                    print("[QuickAddProduct] Thumbnail upload failed: \(error)")
                }
                isUploadingThumbnail = false
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)

            if thumbnailUploadFailed {
                // Stay on the sheet so the user sees the inline retry CTA.
                // Surface as an explicit (recoverable) error message.
                errorMessage = "// THUMBNAIL UPLOAD FAILED — TAP RETRY TO TRY AGAIN"
                return
            }

            if saveAndAddAnother {
                // Keep the sheet open and re-prime for another row. We
                // intentionally retain category + unit + advanced settings
                // (kind, line item type, taxable) so a user batch-loading
                // products of the same shape doesn't have to re-pick them
                // every save. Only the per-row fields reset.
                resetForNextEntry()
            } else {
                dismiss()
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    /// Retries just the thumbnail upload for a product that was already
    /// successfully created. Wired into the inline RETRY action when
    /// `thumbnailUploadFailedProductId` is set so the user doesn't have
    /// to re-enter all the form fields.
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

    /// Applies the just-uploaded thumbnail URL to the local SwiftData copy
    /// of the product so the catalog list refreshes without waiting for
    /// the next sync pass.
    @MainActor
    private func applyThumbnailURL(_ url: String?, productId: String) {
        guard let url else { return }
        let descriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.id == productId }
        )
        if let local = try? modelContext.fetch(descriptor).first {
            local.thumbnailUrl = url
            try? modelContext.save()
        }
    }

    /// Clears per-row fields after a successful save when the
    /// save-and-add-another toggle is on. Category, unit, and advanced
    /// settings stay so the next product inherits the same shape.
    @MainActor
    private func resetForNextEntry() {
        name = ""
        priceString = ""
        productDescription = ""
        sku = ""
        unitCostString = ""
        priceParseError = false
        unitCostParseError = false
        errorMessage = nil
        // Thumbnail is per-row — clear so the next product doesn't
        // accidentally inherit the previous product's image.
        thumbnailImage = nil
        thumbnailPickerItem = nil
        thumbnailUploadFailedProductId = nil
        // Refocus the name field on the next runloop tick so the keyboard
        // stays up across the save→reset transition without flickering.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            nameFieldFocused = true
        }
    }

    private func applyCreatedDTO(_ dto: ProductDTO) {
        let model = dto.toModel()
        modelContext.insert(model)
        try? modelContext.save()
    }
}
