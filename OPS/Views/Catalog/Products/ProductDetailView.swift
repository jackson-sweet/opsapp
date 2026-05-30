//
//  ProductDetailView.swift
//  OPS
//
//  Detail screen for a single Product. Combines a lightweight in-place
//  editor for base fields (name, base price, pricing unit, taxable,
//  active) with read-only sub-views that surface the product's options,
//  pricing modifiers, and recipe rows. Authoring those richer fields
//  lives on web for now; the iOS detail keeps you confident the rules
//  are wired correctly.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ProductDetailView: View {
    let product: Product

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var canManageProducts: Bool { permissionStore.can("catalog.products.manage") }

    @Query private var allOptions: [ProductOption]
    @Query private var allOptionValues: [ProductOptionValue]
    @Query private var allModifiers: [ProductPricingModifier]
    @Query private var allMaterials: [ProductMaterial]
    @Query private var allCategories: [CatalogCategory]
    @Query private var allUnits: [CatalogUnit]
    @Query private var allTaskTypes: [TaskType]
    @Query private var allBundleItems: [ProductBundleItem]
    @Query private var allProductsForBundle: [Product]

    // Editable mirror of product base fields. Reset when `product.id`
    // changes so navigating between detail screens picks up the right
    // baseline without leaking edits across products.
    @State private var name: String
    @State private var basePriceString: String
    @State private var taxable: Bool
    @State private var isActive: Bool

    /// Selected CatalogUnit id. nil = no unit (treated as flat-rate).
    /// Hydrated from `product.unitId` on init.
    @State private var selectedUnitId: String?

    /// Selected CatalogCategory id. nil = none. Hydrated from
    /// `product.categoryId` on init.
    @State private var selectedCategoryId: String?

    /// Task type link. Hydrated from `product.taskTypeRef` (or its legacy
    /// `taskTypeId` text mirror if the row predates the FK column). The
    /// picker writes both columns in lockstep on save so reads from any
    /// path land on the same parent.
    @State private var selectedTaskTypeId: String?
    @State private var showingTaskTypePicker: Bool = false

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var priceParseError: Bool = false

    /// Drives presentation of the recipe edit sheet. The read-only
    /// `RecipeReadOnlyView` remains; this sheet supplements it for users
    /// who can manage products.
    @State private var showingRecipeManageSheet: Bool = false

    /// Drives presentation of the bundle composition edit sheet. Only
    /// surfaced when `product.kind == .package` and the operator can
    /// manage products.
    @State private var showingBundleEditSheet: Bool = false

    /// Inline create sheets — opened from the "+ NEW …" menu items so the
    /// user never has to leave the detail screen, navigate elsewhere, then
    /// return. The new row's id is returned via callback and selected here.
    @State private var showingNewCategorySheet: Bool = false
    @State private var showingNewUnitSheet: Bool = false

    /// Picker selection for the thumbnail. Picking a new image triggers
    /// the upload pipeline (resize → JPEG → Storage upload → PATCH on
    /// products.thumbnail_url) without dropping out of the detail screen.
    @State private var thumbnailPickerItem: PhotosPickerItem? = nil
    @State private var isUploadingThumbnail: Bool = false
    @State private var thumbnailErrorMessage: String? = nil

    init(product: Product) {
        self.product = product
        _name = State(initialValue: product.name)
        _basePriceString = State(initialValue: Self.priceFieldString(product.basePrice))
        _taxable = State(initialValue: product.taxable)
        _isActive = State(initialValue: product.isActive)
        _selectedUnitId = State(initialValue: product.unitId)
        _selectedCategoryId = State(initialValue: product.categoryId)
        // Prefer the uuid FK; fall back to the legacy text column for rows
        // synced before the FK was added. Empty strings round-trip through
        // Supabase as nil — coerce explicitly.
        let hydratedTaskTypeId: String? = {
            if let ref = product.taskTypeRef, !ref.isEmpty { return ref }
            if let legacy = product.taskTypeId, !legacy.isEmpty { return legacy }
            return nil
        }()
        _selectedTaskTypeId = State(initialValue: hydratedTaskTypeId)
    }

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

    private var companyTaskTypes: [TaskType] {
        allTaskTypes
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.displayOrder, $0.display) < ($1.displayOrder, $1.display) }
    }

    private var selectedTaskType: TaskType? {
        guard let id = selectedTaskTypeId else { return nil }
        return companyTaskTypes.first(where: { $0.id == id })
    }

    /// LABOR-type products require a task type to participate in the
    /// estimate→tasks pipeline. Material and Fee products can save
    /// without one — their `taskTypeRef` stays nil (or carries a stale
    /// reference from a previous LABOR life, harmlessly).
    private var requiresTaskType: Bool {
        product.type == .labor
    }

    /// Truth check for the persisted product's task type, normalized so an
    /// empty string compares equal to nil. Used inside `hasChanges` so the
    /// SAVE button doesn't activate on a no-op selection that round-trips
    /// the same FK.
    private var persistedTaskTypeId: String? {
        if let ref = product.taskTypeRef, !ref.isEmpty { return ref }
        if let legacy = product.taskTypeId, !legacy.isEmpty { return legacy }
        return nil
    }

    /// Current CatalogUnit selection resolved against the local @Query.
    /// Used both to render the picker label and to derive the legacy
    /// `pricingUnit` enum + `unit` string at save time.
    private var selectedCatalogUnit: CatalogUnit? {
        guard let id = selectedUnitId else { return nil }
        return companyUnits.first(where: { $0.id == id })
    }

    private var selectedCatalogCategory: CatalogCategory? {
        guard let id = selectedCategoryId else { return nil }
        return companyCategories.first(where: { $0.id == id })
    }

    private var productOptions: [ProductOption] {
        allOptions
            .filter { $0.productId == product.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var productOptionValues: [ProductOptionValue] {
        let optionIds = Set(productOptions.map(\.id))
        return allOptionValues.filter { optionIds.contains($0.optionId) }
    }

    private var productModifiers: [ProductPricingModifier] {
        allModifiers.filter { $0.productId == product.id }
    }

    private var productMaterials: [ProductMaterial] {
        allMaterials.filter { $0.productId == product.id }
    }

    private var hasChanges: Bool {
        if name.trimmingCharacters(in: .whitespacesAndNewlines) != product.name { return true }
        let trimmedPrice = basePriceString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Double(trimmedPrice), parsed != product.basePrice { return true }
        if selectedUnitId != product.unitId { return true }
        if selectedCategoryId != product.categoryId { return true }
        if selectedTaskTypeId != persistedTaskTypeId { return true }
        if taxable != product.taxable { return true }
        if isActive != product.isActive { return true }
        return false
    }

    private var canSave: Bool {
        guard hasChanges, !isSaving else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return false }
        let trimmedPrice = basePriceString.trimmingCharacters(in: .whitespacesAndNewlines)
        if Double(trimmedPrice) == nil { return false }
        if requiresTaskType && selectedTaskTypeId == nil { return false }
        return true
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    thumbnailSection
                    headerSection
                    coreCard
                    categoryCard
                    taskTypeCard
                    if !productOptions.isEmpty {
                        optionsSection
                    }
                    if !productModifiers.isEmpty {
                        modifiersSection
                    }
                    // Branch on kind: bundles replace the recipe section
                    // with a BUNDLE COMPOSITION section. Everything else
                    // keeps the recipe affordance.
                    if product.kind == .package {
                        bundleCompositionSection
                    } else if !productMaterials.isEmpty || canManageProducts {
                        recipeSection
                    }
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorText)
                    }
                    Color.clear.frame(height: OPSStyle.Layout.spacing5)
                }
                .padding(OPSStyle.Layout.spacing3)
            }
        }
        .navigationTitle(product.category3Way.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasChanges && canManageProducts {
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
                    .disabled(!canSave)
                }
            }
        }
        .trackScreen("Catalog.Products.Detail")
        .sheet(isPresented: $showingRecipeManageSheet) {
            RecipeManageSheet(product: product)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingBundleEditSheet) {
            BundleCompositionEditSheet(product: product)
                .environmentObject(dataController)
        }
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
        .sheet(isPresented: $showingTaskTypePicker) {
            TaskTypePickerSheet(
                selectedTaskTypeId: selectedTaskTypeId,
                onSelect: { picked in
                    selectedTaskTypeId = picked.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            )
            .environmentObject(dataController)
        }
    }

    // MARK: - Thumbnail

    /// Aspect ratio for both the preview tile and the empty placeholder
    /// so the layout doesn't jump between states.
    private var thumbnailAspect: CGFloat { 16.0 / 10.0 }

    /// Thumbnail tile at the top of the detail. Renders the remote image
    /// when present, a tap-to-add placeholder when the user can manage
    /// products and the row has no image, and a "// NO IMAGE" placeholder
    /// in read-only mode when there's nothing to show. Either way the
    /// placeholder reserves the same vertical space as the live tile.
    @ViewBuilder
    private var thumbnailSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if let urlString = product.thumbnailUrl,
               let url = URL(string: urlString) {
                thumbnailWithImage(url: url)
            } else if canManageProducts {
                thumbnailEmptyPicker
            } else {
                thumbnailPlaceholder(label: "// NO IMAGE")
            }

            if let thumbnailErrorMessage {
                Text(thumbnailErrorMessage)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.errorText)
            }
        }
        .onChange(of: thumbnailPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadPickedThumbnail(newItem) }
        }
    }

    @ViewBuilder
    private func thumbnailWithImage(url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderInner(label: "// IMAGE FAILED TO LOAD")
                case .empty:
                    placeholderInner(label: "// LOADING…")
                @unknown default:
                    placeholderInner(label: "// LOADING…")
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(thumbnailAspect, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )

            if canManageProducts {
                PhotosPicker(
                    selection: $thumbnailPickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text(isUploadingThumbnail ? "// UPLOADING…" : "// REPLACE")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                .fill(OPSStyle.Colors.background.opacity(0.7))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                .stroke(OPSStyle.Colors.cardBorder,
                                        lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .padding(OPSStyle.Layout.spacing2)
                .disabled(isUploadingThumbnail)
                .accessibilityLabel("Replace thumbnail")
            }
        }
    }

    /// Empty-state picker — full-width tap target the user can hit with
    /// gloves. Same aspect ratio as the live tile so swapping in/out of
    /// the image state doesn't jump the layout.
    @ViewBuilder
    private var thumbnailEmptyPicker: some View {
        PhotosPicker(
            selection: $thumbnailPickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            placeholderInner(label: isUploadingThumbnail
                             ? "// UPLOADING…"
                             : "// + ADD THUMBNAIL")
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(thumbnailAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .disabled(isUploadingThumbnail)
        .accessibilityLabel("Add thumbnail")
    }

    /// Display-only placeholder used in read-only mode (no manage perm).
    @ViewBuilder
    private func thumbnailPlaceholder(label: String) -> some View {
        placeholderInner(label: label)
            .frame(maxWidth: .infinity)
            .aspectRatio(thumbnailAspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    /// Shared inner content for every placeholder state — keeps the
    /// background + label rendering identical across empty / loading /
    /// failed / read-only modes.
    @ViewBuilder
    private func placeholderInner(label: String) -> some View {
        HStack {
            Spacer()
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    // MARK: - Thumbnail upload

    /// Loads the picker item into a UIImage, uploads it via
    /// ProductThumbnailUploader, then PATCHes `products.thumbnail_url`.
    /// Any failure surfaces inline (`thumbnailErrorMessage`) without
    /// rolling back the row — matches the QuickAddProductSheet pattern.
    @MainActor
    private func uploadPickedThumbnail(_ item: PhotosPickerItem) async {
        thumbnailErrorMessage = nil
        guard canManageProducts else { return }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            thumbnailErrorMessage = "// COULD NOT READ SELECTED IMAGE"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isUploadingThumbnail = true
        defer { isUploadingThumbnail = false }

        do {
            let url = try await ProductThumbnailUploader.shared.upload(
                image,
                productId: product.id,
                companyId: companyId
            )
            var patch = UpdateProductDTO()
            patch.thumbnailUrl = url.absoluteString
            let repo = ProductRepository(companyId: companyId)
            let dto = try await repo.update(product.id, fields: patch)
            applyDTOToLocal(dto)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            thumbnailErrorMessage = "// UPLOAD FAILED — TRY AGAIN"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            print("[ProductDetailView] Thumbnail upload failed: \(error)")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(product.name)
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(2)
            HStack(spacing: OPSStyle.Layout.spacing2) {
                kindChip
                if let sku = product.sku, !sku.isEmpty {
                    Text(sku)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                if let category = product.category, !category.isEmpty {
                    Text(category.uppercased())
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Spacer()
            }
        }
    }

    private var kindChip: some View {
        Text(product.category3Way.displayLabel)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    // MARK: - Core editable fields

    private var coreCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("CORE")

            CatalogFieldLabel("Name")
            TextField("", text: $name)
                .textFieldStyle(CatalogTextFieldStyle())
                .disabled(!canManageProducts)

            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    CatalogFieldLabel("Base price")
                    TextField("0", text: $basePriceString)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(CatalogTextFieldStyle())
                        .disabled(!canManageProducts)
                        .onChange(of: basePriceString) { _, newValue in
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
                    if canManageProducts {
                        unitPicker
                    } else {
                        readOnlyMenuLabel(text: selectedUnitDisplay)
                    }
                }
            }

            Toggle(isOn: $taxable) {
                Text("Taxable")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.primaryAccent)
            .disabled(!canManageProducts)
            .onChange(of: taxable) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            Toggle(isOn: $isActive) {
                Text("Active")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.primaryAccent)
            .disabled(!canManageProducts)
            .onChange(of: isActive) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
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

    // MARK: - Task type card (required when product type is LABOR)

    /// Surface the task-type linkage that previously lived only in the
    /// DTO / Supabase column. Without this card, operators editing a
    /// LABOR product had no way to see or change which workflow it feeds
    /// — task generation just silently fell through to the unset path.
    private var taskTypeCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                CatalogSectionHeader("TASK TYPE")
                if requiresTaskType {
                    Text("· REQUIRED")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.errorText)
                } else {
                    Text("· OPTIONAL")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Spacer()
            }
            if canManageProducts {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingTaskTypePicker = true
                } label: {
                    taskTypeMenuLabel
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                taskTypeMenuLabel
            }
            taskTypeHelperRow
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

    private var taskTypeMenuLabel: some View {
        let display = selectedTaskType?.display ?? "Pick a task type"
        let swatch: Color? = {
            guard let hex = selectedTaskType?.color else { return nil }
            return Color(hex: hex)
        }()
        return HStack(spacing: OPSStyle.Layout.spacing2) {
            if let swatch {
                Circle()
                    .fill(swatch)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(swatch.opacity(0.6), lineWidth: 1))
            }
            Text(display)
                .font(OPSStyle.Typography.body)
                .foregroundColor(selectedTaskTypeId == nil
                                 ? OPSStyle.Colors.tertiaryText
                                 : OPSStyle.Colors.primaryText)
                .lineLimit(1)
            Spacer()
            if canManageProducts {
                Image("ops.chevron-down")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(
                    (requiresTaskType && selectedTaskTypeId == nil)
                        ? OPSStyle.Colors.errorText
                        : OPSStyle.Colors.cardBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
    }

    @ViewBuilder
    private var taskTypeHelperRow: some View {
        if requiresTaskType {
            Text(selectedTaskTypeId == nil
                 ? "Pick the workflow this product belongs to — required for LABOR. Tasks on the schedule will inherit this type."
                 : "Tasks generated from this product land under this task type on the schedule.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(selectedTaskTypeId == nil
                                 ? OPSStyle.Colors.errorText
                                 : OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Optional — only LABOR products drive task generation. Set it if you want this product grouped on the schedule.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Category card (CatalogCategory-backed)

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("CATEGORY")
            if canManageProducts {
                categoryPicker
            } else {
                readOnlyMenuLabel(text: selectedCategoryDisplay)
            }
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
                        Label(unit.display, image: "ops.checkmark")
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
                Label("New unit…", image: "ops.add")
            }
        } label: {
            menuLabel(text: selectedUnitDisplay)
        }
    }

    private var selectedUnitDisplay: String {
        // Prefer the resolved CatalogUnit; fall back to the legacy free-text
        // unit string so detail screens for products synced before the FK
        // existed still render something sensible.
        if let unit = selectedCatalogUnit { return unit.display }
        if let legacy = product.unit, !legacy.isEmpty { return legacy }
        return "Flat rate"
    }

    // MARK: - Category picker (CatalogCategory-backed)

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
                        Label(category.name, image: "ops.checkmark")
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
                Label("New category…", image: "ops.add")
            }
        } label: {
            menuLabel(text: selectedCategoryDisplay)
        }
    }

    private var selectedCategoryDisplay: String {
        if let category = selectedCatalogCategory { return category.name }
        if let legacy = product.category, !legacy.isEmpty { return legacy }
        return "None"
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
            Image("ops.chevron-down")
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

    /// Read-only sibling of `menuLabel(text:)` — same visual chrome but no
    /// chevron, no tap. Used when the operator lacks `catalog.products.manage`
    /// so they can still see the current selection without an idle picker.
    @ViewBuilder
    private func readOnlyMenuLabel(text: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineLimit(1)
            Spacer()
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

    // MARK: - Sections

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader(title: "OPTIONS · \(productOptions.count)")
            OptionsReadOnlyView(
                options: productOptions,
                optionValues: productOptionValues
            )
        }
    }

    private var modifiersSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader(title: "PRICING MODIFIERS · \(productModifiers.count)")
            ModifiersReadOnlyView(
                modifiers: productModifiers,
                options: productOptions,
                optionValues: productOptionValues
            )
        }
    }

    private var recipeSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            recipeSectionHeader
            if productMaterials.isEmpty {
                Text("// NO MATERIALS YET — TAP EDIT TO BUILD THE RECIPE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(OPSStyle.Layout.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            } else {
                RecipeReadOnlyView(
                    materials: productMaterials,
                    options: productOptions
                )
            }
        }
    }

    // MARK: - Bundle composition

    /// Active bundle child rows for this product, sorted by display order.
    private var bundleItemsForProduct: [ProductBundleItem] {
        allBundleItems
            .filter { $0.bundleProductId == product.id && $0.deletedAt == nil }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    /// Lookup map of every product the operator can reach — used by the
    /// read-only renderer to render child names + per-unit prices.
    private var childProductsByIdMap: [String: Product] {
        Dictionary(uniqueKeysWithValues: allProductsForBundle.map { ($0.id, $0) })
    }

    private var bundleChildCount: Int { bundleItemsForProduct.count }

    @ViewBuilder
    private var bundleCompositionSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            bundleCompositionHeader
            BundleCompositionReadOnlyView(
                bundleProduct: product,
                bundleItems: bundleItemsForProduct,
                childProductsById: childProductsByIdMap
            )
        }
    }

    private var bundleCompositionHeader: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// COMPOSITION · \(bundleChildCount) ITEM\(bundleChildCount == 1 ? "" : "S")")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            if canManageProducts {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingBundleEditSheet = true
                } label: {
                    Text("EDIT")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, 4)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin / 2)
                }
                .accessibilityLabel("Edit bundle composition")
            }
            viewOnWebLink
        }
    }

    /// Recipe-specific header. Mirrors `sectionHeader(title:)` but slots an
    /// EDIT affordance in for users with `catalog.products.manage`. The
    /// read-only renderer below stays visible; the sheet is supplemental.
    private var recipeSectionHeader: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// RECIPE · \(productMaterials.count) ROW\(productMaterials.count == 1 ? "" : "S")")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            if canManageProducts {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingRecipeManageSheet = true
                } label: {
                    Text("EDIT")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, 4)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin / 2)
                }
                .accessibilityLabel("Edit recipe")
            }
            viewOnWebLink
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// \(title)")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            viewOnWebLink
        }
    }

    private var viewOnWebLink: some View {
        Link(destination: URL(string: "https://app.ops.dev/products/\(product.id)")!) {
            Text("VIEW ON WEB →")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, 4)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin / 2)
        }
        .accessibilityHint("Opens this product in the OPS web app")
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrice = basePriceString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let parsedPrice = Double(trimmedPrice) else { return }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        // Build a sparse update that only carries changed fields. The
        // wire-format omits anything we didn't touch so server-side
        // defaults / web-authored values stay intact.
        var fields = UpdateProductDTO()
        if trimmedName != product.name { fields.name = trimmedName }
        if parsedPrice != product.basePrice { fields.basePrice = parsedPrice }
        if taxable != product.taxable { fields.isTaxable = taxable }
        if isActive != product.isActive { fields.isActive = isActive }

        // Unit changed: write all three columns in lockstep (legacy `unit`
        // free-text, FK `unit_id`, and the legacy `pricing_unit` enum). The
        // `pricingUnit(for:)` helper lives in CatalogManageHelpers.swift so
        // create + edit derive the enum the same way.
        if selectedUnitId != product.unitId {
            let unit = selectedCatalogUnit
            fields.unitId = unit?.id
            fields.unit = unit?.display
            fields.pricingUnit = pricingUnit(for: unit).rawValue
        }

        // Category changed: write both legacy `category` (text) and FK
        // `category_id` so reads from either path see the right value.
        if selectedCategoryId != product.categoryId {
            let category = selectedCatalogCategory
            fields.categoryId = category?.id
            fields.category = category?.name
        }

        // Task type changed: write both the legacy text column and the
        // uuid FK so old code paths (web app pre-Phase 13, in-flight
        // estimates) and new code paths (Service-category resolver) see
        // the same parent. The empty-string → nil coercion lives in the
        // model accessor; here we just hand the raw uuid through.
        if selectedTaskTypeId != persistedTaskTypeId {
            fields.taskTypeRef = selectedTaskTypeId
            fields.taskTypeId = selectedTaskTypeId
        }

        let repo = ProductRepository(companyId: companyId)
        do {
            let dto = try await repo.update(product.id, fields: fields)
            applyDTOToLocal(dto)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    private func applyDTOToLocal(_ dto: ProductDTO) {
        product.name = dto.name
        product.basePrice = dto.basePrice
        if let pricingUnitRaw = dto.pricingUnit,
           let parsed = ProductPricingUnit(rawValue: pricingUnitRaw) {
            product.pricingUnit = parsed
        }
        if let typeRaw = dto.type, let parsedType = LineItemType(rawValue: typeRaw) {
            product.type = parsedType
        }
        if let kindRaw = dto.kind, let parsedKind = ProductKind(rawValue: kindRaw) {
            product.kind = parsedKind
        }
        product.productDescription = dto.description
        product.unitCost = dto.unitCost
        product.unit = dto.unit
        product.unitId = dto.unitId
        product.category = dto.category
        product.categoryId = dto.categoryId
        product.sku = dto.sku
        product.thumbnailUrl = dto.thumbnailUrl
        product.taxable = dto.isTaxable ?? product.taxable
        product.isActive = dto.isActive
        product.minimumCharge = dto.minimumCharge
        product.minimumQuantity = dto.minimumQuantity
        product.taskTypeId = dto.taskTypeId
        product.taskTypeRef = dto.taskTypeRef
        product.bundlePricingMode = dto.bundlePricingMode
        try? modelContext.save()
    }

    private static func priceFieldString(_ value: Double) -> String {
        if value == 0 { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
