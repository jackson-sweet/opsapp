//
//  NewBundleSheet.swift
//  OPS
//
//  Kind-tailored create sheet for BUNDLES. Locks `kind='package'` and
//  `type='OTHER'`. Implements the V4 hybrid layout from the design spec:
//  inline child-picker drawer + selected-children list with quantity
//  steppers + AUTO/OVERRIDE pricing toggle.
//
//  Validation: name non-empty, ≥1 child, override price parses if mode is
//  override. Bundles cannot nest in v1 — the drawer filters out other
//  package-kind products, and save double-checks before commit.
//
//  Partial-failure UX: if the parent Product create succeeds but child row
//  inserts fail, the sheet stays open with an inline RETRY pointing at the
//  unflushed children. Same degrade-gracefully pattern QuickAddProductSheet
//  used for thumbnails — never roll back the parent.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Local-only enum tracking which pricing strategy the operator picked.
/// Persists as `products.bundle_pricing_mode` (text 'auto' | 'override').
enum BundlePricingMode: String, CaseIterable, Identifiable {
    case auto
    case override

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .auto:     return "AUTO"
        case .override: return "OVERRIDE"
        }
    }
}

/// Per-row draft held in @State while the operator composes the bundle.
/// Flushed to public.product_bundle_items as CreateProductBundleItemDTO
/// rows only on save — no optimistic writes mid-edit.
struct BundleChildDraft: Identifiable, Hashable {
    let id: String           // childProductId — products row id
    var quantity: Double
    var displayOrder: Int
}

struct NewBundleSheet: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allProducts: [Product]
    @Query private var allCategories: [CatalogCategory]
    @Query private var allTaskTypes: [TaskType]

    // Required core
    @State private var name: String = ""
    @State private var productDescription: String = ""
    @State private var selectedCategoryId: String? = nil
    @State private var selectedTaskTypeId: String? = nil

    // Pricing
    @State private var pricingMode: BundlePricingMode = .auto
    @State private var overridePriceString: String = ""
    @State private var taxable: Bool = true

    // Composition
    @State private var children: [BundleChildDraft] = []
    @State private var drawerOpen: Bool = false
    @State private var drawerSearch: String = ""

    // Thumbnail
    @State private var thumbnailPickerItem: PhotosPickerItem? = nil
    @State private var thumbnailImage: UIImage? = nil
    @State private var thumbnailUploadFailedProductId: String? = nil
    @State private var isUploadingThumbnail: Bool = false

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var overridePriceParseError: Bool = false

    // Partial-failure retry state
    @State private var unflushedChildrenForProductId: String? = nil
    @State private var unflushedChildren: [BundleChildDraft] = []

    @State private var showingNewCategorySheet: Bool = false
    @State private var showingTaskTypePicker: Bool = false

    private var canManageProducts: Bool { permissionStore.can("catalog.products.manage") }

    @FocusState private var nameFieldFocused: Bool

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyCategories: [CatalogCategory] {
        allCategories
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var companyTaskTypes: [TaskType] {
        allTaskTypes
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.displayOrder, $0.display) < ($1.displayOrder, $1.display) }
    }

    private var selectedTaskType: TaskType? {
        guard let selectedTaskTypeId else { return nil }
        return companyTaskTypes.first(where: { $0.id == selectedTaskTypeId })
    }

    /// Active company products that can be children of a bundle.
    /// Excludes other bundles (no nesting in v1) and the bundle's own
    /// shell (irrelevant here because the shell isn't created yet).
    private var eligibleChildren: [Product] {
        allProducts.filter { product in
            product.companyId == companyId
                && product.isActive
                && product.kind != .package
        }
    }

    private var filteredDrawerProducts: [Product] {
        let trimmed = drawerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = eligibleChildren
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !trimmed.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
            ($0.productDescription ?? "").localizedCaseInsensitiveContains(trimmed) ||
            ($0.sku ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var productById: [String: Product] {
        Dictionary(uniqueKeysWithValues: allProducts.map { ($0.id, $0) })
    }

    /// Sum of `child.basePrice × quantity` for every selected child. Used
    /// for both AUTO pricing (becomes the bundle's base_price) and as a
    /// reference total under OVERRIDE pricing.
    private var rolledTotal: Double {
        children.reduce(0) { acc, draft in
            let unit = productById[draft.id]?.basePrice ?? 0
            return acc + unit * draft.quantity
        }
    }

    private var overridePrice: Double? {
        let trimmed = overridePriceString.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed)
    }

    private var effectivePrice: Double {
        switch pricingMode {
        case .auto: return rolledTotal
        case .override: return overridePrice ?? 0
        }
    }

    private var marginPercent: Double? {
        guard pricingMode == .override,
              let price = overridePrice, price > 0 else { return nil }
        return ((price - rolledTotal) / price) * 100
    }

    private var canSave: Bool {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if children.isEmpty { return false }
        if pricingMode == .override {
            guard let p = overridePrice, p >= 0 else { return false }
            _ = p  // silence unused warning if compiler ever gets picky
        }
        if isSaving { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        sheetHeader
                        identitySection
                        taskTypeSection
                        compositionSection
                        pricingCard
                        detailSection
                        Color.clear.frame(height: 132)
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
                .dismissKeyboardOnTap()
                saveBar
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
                    Text("NEW BUNDLE")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    nameFieldFocused = true
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingNewCategorySheet) {
            InlineCreateCategorySheet(companyId: companyId) { newId in
                selectedCategoryId = newId
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

    // MARK: - Form sections

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("PACKAGE PRODUCTS")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Build one sellable line from the parts, labor, and goods underneath it.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("IDENTITY")
            CatalogFieldLabel("Name")
            TextField("Standard deck package", text: $name)
                .textFieldStyle(CatalogTextFieldStyle())
                .focused($nameFieldFocused)
                .submitLabel(.next)

            CatalogFieldLabel("Category")
            CategoryPickerField(
                selectedCategoryId: $selectedCategoryId,
                companyCategories: companyCategories,
                canCreateNew: canManageProducts,
                onCreateRequested: { showingNewCategorySheet = true }
            )

            CatalogFieldLabel("Description")
            TextField("What this bundle includes", text: $productDescription, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(CatalogTextFieldStyle())
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

    private var taskTypeSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                CatalogSectionHeader("TASK LINK")
                Text("· OPTIONAL")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingTaskTypePicker = true
            } label: {
                taskTypePickerLabel
            }
            .buttonStyle(.plain)

            Text("Set a task type when this bundle should create or group field work on the schedule.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
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

    private var taskTypePickerLabel: some View {
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
            Text(selectedTaskType?.display ?? "Pick task type")
                .font(OPSStyle.Typography.body)
                .foregroundColor(selectedTaskTypeId == nil ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var compositionSection: some View {
        childrenSection
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private var pricingCard: some View {
        pricingSection
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    @ViewBuilder
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("DETAIL")
            taxableToggle
            if canManageProducts {
                thumbnailField
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

    // MARK: - Children section

    @ViewBuilder
    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("// COMPOSITION · \(children.count)")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }

            addChildButton
            if drawerOpen {
                drawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if children.isEmpty {
                Text("// NO CHILDREN YET — TAP + ADD CHILD ABOVE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(OPSStyle.Layout.spacing2)
            } else {
                ForEach(children) { draft in
                    selectedChildRow(draft: draft)
                }
            }
        }
    }

    private var addChildButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeInOut(duration: 0.18)) {
                drawerOpen.toggle()
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: drawerOpen ? "minus" : "plus")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text(drawerOpen ? "// CLOSE PICKER" : "// + ADD CHILD")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Spacer()
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4),
                            lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(drawerOpen ? "Close child picker" : "Open child picker")
    }

    @ViewBuilder
    private var drawer: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                TextField("Search products…", text: $drawerSearch)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !drawerSearch.isEmpty {
                    Button { drawerSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )

            if filteredDrawerProducts.isEmpty {
                Text("// NO PRODUCTS MATCH")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
            } else {
                ScrollView {
                    LazyVStack(spacing: OPSStyle.Layout.spacing1) {
                        ForEach(filteredDrawerProducts) { product in
                            drawerRow(product: product)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.7))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func drawerRow(product: Product) -> some View {
        Button {
            addOrIncrement(product: product)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: product.category3Way.iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 24)
                Text(product.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(formattedPrice(product.basePrice))
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(product.name)")
    }

    private func addOrIncrement(product: Product) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let idx = children.firstIndex(where: { $0.id == product.id }) {
            children[idx].quantity += 1
        } else {
            let order = children.map(\.displayOrder).max().map { $0 + 1 } ?? 0
            children.append(BundleChildDraft(id: product.id, quantity: 1, displayOrder: order))
        }
    }

    private func selectedChildRow(draft: BundleChildDraft) -> some View {
        let product = productById[draft.id]
        let unitPrice = product?.basePrice ?? 0
        let lineTotal = unitPrice * draft.quantity
        return HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: product?.category3Way.iconName ?? "questionmark.circle")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(product?.name ?? "—")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Text(formattedPrice(unitPrice) + " ea")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            qtyStepper(for: draft)
            Text(formattedPrice(lineTotal))
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                removeChild(draft)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func qtyStepper(for draft: BundleChildDraft) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Button {
                decrement(draft)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 36, height: 36)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .accessibilityLabel("Decrease quantity")
            Text("× \(Int(draft.quantity))")
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(minWidth: 32)
            Button {
                increment(draft)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 36, height: 36)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .accessibilityLabel("Increase quantity")
        }
    }

    private func increment(_ draft: BundleChildDraft) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let idx = children.firstIndex(where: { $0.id == draft.id }) else { return }
        children[idx].quantity += 1
    }

    private func decrement(_ draft: BundleChildDraft) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard let idx = children.firstIndex(where: { $0.id == draft.id }) else { return }
        if children[idx].quantity > 1 {
            children[idx].quantity -= 1
        } else {
            children.remove(at: idx)
        }
    }

    private func removeChild(_ draft: BundleChildDraft) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        children.removeAll { $0.id == draft.id }
    }

    // MARK: - Pricing section

    @ViewBuilder
    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("PRICING")
            modeSegmented
            switch pricingMode {
            case .auto:
                rolledReadout
            case .override:
                overrideFields
            }
        }
    }

    private var modeSegmented: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            ForEach(BundlePricingMode.allCases) { mode in
                modeChip(mode)
            }
        }
    }

    private func modeChip(_ mode: BundlePricingMode) -> some View {
        let isSelected = pricingMode == mode
        return Button {
            guard pricingMode != mode else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            pricingMode = mode
        } label: {
            Text(mode.displayLabel)
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(isSelected ? OPSStyle.Colors.buttonText : OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder,
                                lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pricing mode \(mode.displayLabel.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rolledReadout: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// ROLLED TOTAL")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            Text(formattedPrice(rolledTotal))
                .font(OPSStyle.Typography.bodyBold)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    @ViewBuilder
    private var overrideFields: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            CatalogFieldLabel("Override price")
            TextField("0", text: $overridePriceString)
                .keyboardType(.decimalPad)
                .textFieldStyle(CatalogTextFieldStyle())
                .onChange(of: overridePriceString) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    overridePriceParseError = !trimmed.isEmpty && Double(trimmed) == nil
                }
            if overridePriceParseError {
                Text("Price must be a number")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.errorText)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("// ROLLED SUM")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                Text(formattedPrice(rolledTotal))
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.top, OPSStyle.Layout.spacing1)

            if let margin = marginPercent {
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
    }

    // MARK: - Thumbnail + taxable

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

    private var taxableToggle: some View {
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

    // MARK: - Error row

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
                    if unflushedChildrenForProductId != nil {
                        Task { await retryUnflushedChildren() }
                    } else if thumbnailUploadFailedProductId != nil {
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
                .accessibilityLabel("Retry saving bundle")
                .disabled(isSaving || isUploadingThumbnail)
            }
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        OPSFloatingButtonBar {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                errorRow
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.tertiaryText))
                                .scaleEffect(0.75)
                            Text("SAVING")
                        }
                    } else {
                        Text("SAVE BUNDLE")
                    }
                }
                .opsPrimaryButtonStyle(isDisabled: !canSave)
                .disabled(!canSave)
            }
        }
    }

    private func formattedPrice(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard !children.isEmpty else {
            errorMessage = "// BUNDLE NEEDS AT LEAST ONE CHILD"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        // Defense: re-verify no children are packages (drawer filters already,
        // but a stale Product reference shouldn't slip through).
        for draft in children {
            guard let product = productById[draft.id] else {
                errorMessage = "// CHILD REFERENCE MISSING — REMOVE AND RE-ADD"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            if product.kind == .package {
                errorMessage = "// BUNDLES CANNOT CONTAIN OTHER BUNDLES — REMOVE \(product.name.uppercased())"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
        }
        if pricingMode == .override {
            guard let p = overridePrice, p >= 0 else {
                overridePriceParseError = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            _ = p
        }
        // Duplicate-name pre-check
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
        let selectedCategory = companyCategories.first(where: { $0.id == selectedCategoryId })

        var dto = CreateProductDTO(
            companyId: companyId,
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            basePrice: effectivePrice,
            unitCost: nil,
            unit: nil,
            pricingUnit: ProductPricingUnit.flatRate.rawValue,
            unitId: nil,
            category: selectedCategory?.name,
            categoryId: selectedCategory?.id,
            sku: nil,
            thumbnailUrl: nil,
            kind: "package",
            type: LineItemType.other.rawValue,
            isTaxable: taxable,
            taskTypeId: selectedTaskTypeId,
            taskTypeRef: selectedTaskTypeId,
            linkedCatalogItemId: nil
        )
        dto.bundlePricingMode = pricingMode.rawValue

        let productRepo = ProductRepository(companyId: companyId)
        do {
            let createdDTO = try await productRepo.create(dto)
            let model = createdDTO.toModel()
            modelContext.insert(model)
            try? modelContext.save()

            // Flush child rows. Partial failures keep the bundle alive and
            // surface a retry CTA — never roll back the parent product.
            var failedChildren: [BundleChildDraft] = []
            let bundleRepo = ProductBundleItemRepository(companyId: companyId)
            for draft in children {
                let childDTO = CreateProductBundleItemDTO(
                    id: UUID().uuidString,
                    companyId: companyId,
                    bundleProductId: createdDTO.id,
                    childProductId: draft.id,
                    quantity: draft.quantity,
                    displayOrder: draft.displayOrder
                )
                do {
                    let createdRow = try await bundleRepo.create(childDTO)
                    let rowModel = createdRow.toModel()
                    modelContext.insert(rowModel)
                } catch {
                    failedChildren.append(draft)
                    print("[NewBundleSheet] Child insert failed for \(draft.id): \(error)")
                }
            }
            try? modelContext.save()

            // Thumbnail upload — same degrade-gracefully pattern as goods.
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
                    let patched = try await productRepo.update(createdDTO.id, fields: patch)
                    applyThumbnailURL(patched.thumbnailUrl, productId: createdDTO.id)
                } catch {
                    thumbnailFailed = true
                    thumbnailUploadFailedProductId = createdDTO.id
                    print("[NewBundleSheet] Thumbnail upload failed: \(error)")
                }
                isUploadingThumbnail = false
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)

            if !failedChildren.isEmpty {
                unflushedChildren = failedChildren
                unflushedChildrenForProductId = createdDTO.id
                errorMessage = "// \(failedChildren.count) CHILD ROW(S) FAILED — TAP RETRY TO TRY AGAIN"
                return
            }
            if thumbnailFailed {
                errorMessage = "// THUMBNAIL UPLOAD FAILED — TAP RETRY TO TRY AGAIN"
                return
            }
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func retryUnflushedChildren() async {
        guard let bundleId = unflushedChildrenForProductId, !unflushedChildren.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let bundleRepo = ProductBundleItemRepository(companyId: companyId)
        var stillFailing: [BundleChildDraft] = []
        for draft in unflushedChildren {
            let childDTO = CreateProductBundleItemDTO(
                id: UUID().uuidString,
                companyId: companyId,
                bundleProductId: bundleId,
                childProductId: draft.id,
                quantity: draft.quantity,
                displayOrder: draft.displayOrder
            )
            do {
                let createdRow = try await bundleRepo.create(childDTO)
                let rowModel = createdRow.toModel()
                modelContext.insert(rowModel)
            } catch {
                stillFailing.append(draft)
                print("[NewBundleSheet] Retry child insert failed for \(draft.id): \(error)")
            }
        }
        try? modelContext.save()

        unflushedChildren = stillFailing
        if stillFailing.isEmpty {
            unflushedChildrenForProductId = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = "// \(stillFailing.count) CHILD ROW(S) STILL FAILING — TAP RETRY TO TRY AGAIN"
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
            dismiss()
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
}
