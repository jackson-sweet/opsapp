//
//  VariantDetailView.swift
//  OPS
//
//  Detail screen for a single CatalogVariant. Owns the in-place
//  quantity adjustment controls, threshold overrides, and the SAVE
//  pipeline that persists everything via `CatalogRepository`.
//

import SwiftUI
import SwiftData
import PhotosUI

struct VariantDetailView: View {
    let row: EnrichedVariantRow

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var canAdjustStock: Bool { permissionStore.can("catalog.stock.adjust") }
    private var canManage:       Bool { permissionStore.can("catalog.manage") }

    @State private var localQuantity: Double
    @State private var skuText: String
    @State private var warningText: String
    @State private var criticalText: String
    @State private var exactQuantityText: String
    @State private var customDeltaText: String = ""
    @State private var imagePickerItem: PhotosPickerItem? = nil
    @State private var pendingFamilyImage: UIImage? = nil
    @State private var isSaving: Bool = false
    @State private var isAdjusting: Bool = false
    @State private var isUploadingFamilyImage: Bool = false
    @State private var isSavingTags: Bool = false
    @State private var showingVariantEditor: Bool = false
    @State private var showingFamilySetupEditor: Bool = false
    @State private var selectedTagIds: Set<String>
    @State private var errorMessage: String? = nil
    @State private var imageErrorMessage: String? = nil

    // USED IN reverse-link queries — surfaces every active Product that
    // references either this variant directly (recipe row) or this
    // variant's family head (recipe row or stock-linked product).
    @Query private var allProductMaterials: [ProductMaterial]
    @Query private var allProductsForUsage: [Product]
    @Query private var allTags: [CatalogTag]

    init(row: EnrichedVariantRow) {
        self.row = row
        _localQuantity = State(initialValue: row.variant.quantity)
        _skuText = State(initialValue: row.variant.sku ?? "")
        _warningText = State(initialValue: row.variant.warningThreshold.map { String($0) } ?? "")
        _criticalText = State(initialValue: row.variant.criticalThreshold.map { String($0) } ?? "")
        _exactQuantityText = State(initialValue: StockNumberFormatter.quantity(row.variant.quantity))
        _selectedTagIds = State(initialValue: row.tagIds)
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var companyTags: [CatalogTag] {
        allTags
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// True when any field other than quantity has changed. Quantity uses
    /// its own optimistic-update path (the +/- buttons commit on tap).
    private var isDirty: Bool {
        let trimmedSku = skuText.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalSku = row.variant.sku ?? ""
        if trimmedSku != originalSku { return true }
        let parsedWarning = Double(warningText.trimmingCharacters(in: .whitespacesAndNewlines))
        if parsedWarning != row.variant.warningThreshold { return true }
        let parsedCritical = Double(criticalText.trimmingCharacters(in: .whitespacesAndNewlines))
        if parsedCritical != row.variant.criticalThreshold { return true }
        return false
    }

    private var statusText: String {
        let status = currentThresholdStatus()
        switch status {
        case .normal:   return "ON HAND"
        case .warning:  return "BELOW WARNING"
        case .critical: return "BELOW CRITICAL"
        }
    }

    private func currentThresholdStatus() -> ThresholdStatus {
        if let critical = effectiveCritical(), localQuantity <= critical { return .critical }
        if let warning = effectiveWarning(), localQuantity <= warning { return .warning }
        return .normal
    }

    private func effectiveWarning() -> Double? {
        if let parsed = Double(warningText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return row.family.defaultWarningThreshold ?? row.category?.defaultWarningThreshold
    }

    private func effectiveCritical() -> Double? {
        if let parsed = Double(criticalText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return row.family.defaultCriticalThreshold ?? row.category?.defaultCriticalThreshold
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        header
                        if canManage {
                            familySetupCard
                        }
                        familyImageCard
                        quantityCard
                        usedInCard
                        if canManage {
                            thresholdsCard
                            skuCard
                        }
                        if canManage || !selectedTagIds.isEmpty {
                            tagsCard
                        }
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("VARIANT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                if isDirty && canManage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await save() }
                        } label: {
                            Text("SAVE")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(isSaving
                                                 ? OPSStyle.Colors.tertiaryText
                                                 : OPSStyle.Colors.primaryAccent)
                        }
                        .disabled(isSaving)
                        .accessibilityLabel("Save variant")
                        .accessibilityHint(isSaving ? "Variant save is already running." : "Saves SKU and threshold changes.")
                        .accessibilityValue(isSaving ? "Saving" : "Ready")
                    }
                }
            }
        }
        .sheet(isPresented: $showingVariantEditor) {
            VariantFormSheet(initialFamily: row.family, existingVariant: row.variant)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showingFamilySetupEditor) {
            CatalogSetupFlowSheet(existingFamily: row.family)
                .environmentObject(dataController)
        }
        .onChange(of: imagePickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadPickedFamilyImage(newItem) }
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(row.family.name)
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            if !row.variantLabel.isEmpty {
                Text(row.variantLabel)
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            if let sku = row.variant.sku, !sku.isEmpty {
                Text(sku)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }

    private var quantityCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// QUANTITY")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            HStack(spacing: OPSStyle.Layout.spacing3) {
                Button {
                    adjustQuantity(by: -1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 56, height: 56)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .disabled(isAdjusting || localQuantity <= 0 || !canAdjustStock)
                .opacity(canAdjustStock ? 1.0 : 0.4)
                .accessibilityLabel("Decrease quantity")

                VStack(spacing: 2) {
                    Text(quantityString)
                        .font(OPSStyle.Typography.displayQuantity)
                        .foregroundColor(currentThresholdStatus().color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let unit = row.unit?.display {
                        Text(unit)
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity)

                Button {
                    adjustQuantity(by: 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 56, height: 56)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .disabled(isAdjusting || !canAdjustStock)
                .opacity(canAdjustStock ? 1.0 : 0.4)
                .accessibilityLabel("Increase quantity")
            }

            quickAdjustGrid
            exactQuantityControl
            customDeltaControl
            statusChip
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

    private var familyImageCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// ITEM IMAGE")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                familyImagePreview

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(row.family.name)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(2)
                    Text(row.variantLabel.isEmpty ? "Family image" : row.variantLabel)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(2)

                    if canManage {
                        PhotosPicker(
                            selection: $imagePickerItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Text(imageUploadButtonText)
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(isUploadingFamilyImage ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        }
                        .disabled(isUploadingFamilyImage)
                        .accessibilityLabel("Replace item image")
                        .accessibilityHint(row.family.imageUrl == nil ? "Uploads a family image." : "Replaces the current family image.")
                        .accessibilityValue(isUploadingFamilyImage ? "Uploading" : "Ready")
                    }
                }

                Spacer()
            }

            if let imageErrorMessage {
                Text(imageErrorMessage)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.errorText)
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

    @ViewBuilder
    private var familyImagePreview: some View {
        if let pendingFamilyImage {
            Image(uiImage: pendingFamilyImage)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(imagePreviewBorder)
                .accessibilityLabel("Pending item image")
        } else if let imageUrl = row.family.imageUrl,
                  let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    imagePlaceholder(systemName: "photo")
                case .empty:
                    ProgressView()
                        .tint(OPSStyle.Colors.tertiaryText)
                @unknown default:
                    imagePlaceholder(systemName: "photo")
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            .overlay(imagePreviewBorder)
            .accessibilityLabel("Catalog item image")
        } else {
            imagePlaceholder(systemName: "photo")
                .frame(width: 84, height: 84)
                .overlay(imagePreviewBorder)
                .accessibilityLabel("No catalog item image")
        }
    }

    private var imagePreviewBorder: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
    }

    private func imagePlaceholder(systemName: String) -> some View {
        ZStack {
            OPSStyle.Colors.subtleBackground
            Image(systemName: systemName)
                .font(.system(size: OPSStyle.Layout.IconSize.lg))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    private var statusChip: some View {
        let status = currentThresholdStatus()
        let warning = effectiveWarning()
        let critical = effectiveCritical()

        return HStack(spacing: OPSStyle.Layout.spacing2) {
            Circle()
                .fill(status.color)
                .frame(
                    width: OPSStyle.Layout.Indicator.dotMD,
                    height: OPSStyle.Layout.Indicator.dotMD
                )
                .accessibilityHidden(true)
            Text(statusText)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(status.color)
            Spacer()
            if let critical = critical {
                Text("crit \(formatThreshold(critical))")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            if let warning = warning {
                Text("warn \(formatThreshold(warning))")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stock status")
        .accessibilityValue(statusAccessibilityValue(status: status, warning: warning, critical: critical))
    }

    private var quickAdjustColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: OPSStyle.Layout.spacing1), count: count)
    }

    private var quickAdjustGrid: some View {
        LazyVGrid(
            columns: quickAdjustColumns,
            spacing: OPSStyle.Layout.spacing1
        ) {
            ForEach(StockQuantityAdjustment.presetDeltas, id: \.self) { delta in
                Button {
                    adjustQuantity(by: delta)
                } label: {
                    Text(delta > 0 ? "+\(StockNumberFormatter.quantity(delta))" : "-\(StockNumberFormatter.quantity(abs(delta)))")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                        .background(OPSStyle.Colors.subtleBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .disabled(isAdjusting || !canAdjustStock || StockQuantityAdjustment.targetQuantity(current: localQuantity, delta: delta) == nil)
                .opacity(canAdjustStock ? 1.0 : 0.4)
                .accessibilityLabel(delta > 0 ? "Add \(StockNumberFormatter.quantity(delta))" : "Subtract \(StockNumberFormatter.quantity(abs(delta)))")
            }
        }
    }

    private var exactQuantityControl: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            CatalogFieldLabel("Set count")
            HStack(spacing: OPSStyle.Layout.spacing2) {
                TextField(quantityString, text: $exactQuantityText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(CatalogTextFieldStyle())
                Button {
                    applyExactQuantity()
                } label: {
                    Text("SET")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(canApplyExactQuantity ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .frame(width: 64, height: OPSStyle.Layout.touchTargetMin)
                        .background(OPSStyle.Colors.subtleBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .disabled(!canApplyExactQuantity)
                .accessibilityLabel("Set exact quantity")
            }
        }
    }

    private var customDeltaControl: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            CatalogFieldLabel("Custom adjustment")
            HStack(spacing: OPSStyle.Layout.spacing2) {
                TextField("37", text: $customDeltaText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(CatalogTextFieldStyle())
                Button {
                    applyCustomDelta(sign: 1)
                } label: {
                    Text("ADD")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(canApplyCustomDelta(sign: 1) ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .frame(width: 64, height: OPSStyle.Layout.touchTargetMin)
                        .background(OPSStyle.Colors.subtleBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .disabled(!canApplyCustomDelta(sign: 1))
                .accessibilityLabel("Add custom quantity")

                Button {
                    applyCustomDelta(sign: -1)
                } label: {
                    Text("SUB")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(canApplyCustomDelta(sign: -1) ? OPSStyle.Colors.errorText : OPSStyle.Colors.tertiaryText)
                        .frame(width: 64, height: OPSStyle.Layout.touchTargetMin)
                        .background(OPSStyle.Colors.subtleBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .disabled(!canApplyCustomDelta(sign: -1))
                .accessibilityLabel("Subtract custom quantity")
            }
        }
    }

    private var thresholdsCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// THRESHOLDS")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Override the family or category default to set a per-variant threshold. Leave blank to inherit.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            CatalogFieldLabel("Warning")
            TextField(warningPlaceholder, text: $warningText)
                .keyboardType(.decimalPad)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Critical")
            TextField(criticalPlaceholder, text: $criticalText)
                .keyboardType(.decimalPad)
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

    private var skuCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// SKU & UNIT")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            CatalogFieldLabel("SKU")
            TextField("", text: $skuText)
                .textFieldStyle(CatalogTextFieldStyle())

            HStack {
                CatalogFieldLabel("Unit")
                Spacer()
                Text(row.unit?.display ?? "—")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            HStack {
                CatalogFieldLabel("Family")
                Spacer()
                Text(row.family.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            if let category = row.category {
                HStack {
                    CatalogFieldLabel("Category")
                    Spacer()
                    Text(category.name)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Button {
                showingVariantEditor = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack {
                    Text("EDIT VARIANT OPTIONS")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit variant options")
            .accessibilityHint("Opens the variant option editor.")
            .accessibilityValue(row.variantLabel.isEmpty ? "Base variant" : row.variantLabel)
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

    private var familySetupCard: some View {
        Button {
            showingFamilySetupEditor = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("// STOCK FAMILY")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("EDIT STOCK SETUP")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit stock setup")
        .accessibilityHint("Opens Catalog Setup for \(row.family.name).")
        .accessibilityValue(row.family.name)
    }

    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// TAGS")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            tagChips

            if canManage && !companyTags.isEmpty {
                Menu {
                    ForEach(companyTags) { tag in
                        Button {
                            var next = selectedTagIds
                            if next.contains(tag.id) {
                                next.remove(tag.id)
                            } else {
                                next.insert(tag.id)
                            }
                            Task { await saveFamilyTags(next) }
                        } label: {
                            Label(tag.name, systemImage: selectedTagIds.contains(tag.id) ? "checkmark" : "")
                        }
                    }
                } label: {
                    Text(isSavingTags ? "// SAVING TAGS" : "// SET TAGS")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(isSavingTags ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .disabled(isSavingTags)
                .accessibilityLabel("Set tags")
                .accessibilityHint("Opens the tag picker for this stock family.")
                .accessibilityValue(isSavingTags ? "Saving" : "\(selectedTagIds.count) selected")
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

    @ViewBuilder
    private var tagChips: some View {
        let tagNames = resolveTagNames()
        if tagNames.isEmpty {
            Text("—")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(tagNames, id: \.self) { name in
                        Text(name.uppercased())
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }
                }
            }
        }
    }

    // MARK: - USED IN reverse links

    /// One row in the USED IN card. Either a recipe reference (qty per
    /// unit text) or a direct stock-linked product (stock-linked label).
    private struct UsedInRow: Identifiable {
        let id: String         // product.id
        let product: Product
        let detail: String
    }

    /// Every active company product that consumes this variant or family.
    /// Two sources: recipe rows in `product_materials` (where the row
    /// pins this variant OR the family head) and direct stock links on
    /// the product itself (`linked_catalog_item_id`).
    private var usedInRows: [UsedInRow] {
        let variantId = row.variant.id
        let familyId = row.family.id
        let recipeMaterials = allProductMaterials.filter { mat in
            mat.catalogVariantId == variantId || mat.catalogItemId == familyId
        }
        let productsById = Dictionary(uniqueKeysWithValues:
            allProductsForUsage
                .filter { $0.companyId == companyId && $0.isActive }
                .map { ($0.id, $0) }
        )
        var rows: [UsedInRow] = []
        var seen = Set<String>()

        for mat in recipeMaterials {
            guard let product = productsById[mat.productId], !seen.contains(product.id) else { continue }
            let qty = formatThreshold(mat.quantityPerUnit)
            rows.append(UsedInRow(id: product.id, product: product, detail: "\(qty) per unit"))
            seen.insert(product.id)
        }
        for product in productsById.values where product.linkedCatalogItemId == familyId {
            if seen.contains(product.id) { continue }
            rows.append(UsedInRow(id: product.id, product: product, detail: "stock-linked"))
            seen.insert(product.id)
        }
        return rows.sorted { $0.product.name.localizedCaseInsensitiveCompare($1.product.name) == .orderedAscending }
    }

    private var usedInCard: some View {
        let rows = usedInRows
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// USED IN · \(rows.count) PRODUCT\(rows.count == 1 ? "" : "S")")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            if rows.isEmpty {
                Text("// NOT USED IN ANY PRODUCT YET — RECIPE LINKS WILL APPEAR HERE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(rows) { usedRow in
                    NavigationLink {
                        ProductDetailView(product: usedRow.product)
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: usedRow.product.category3Way.iconName)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(usedRow.product.name)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(1)
                                Text(usedRow.detail)
                                    .font(OPSStyle.Typography.metadata)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(usedRow.product.name)
                    .accessibilityValue(usedRow.detail)
                    .accessibilityHint("Opens this product.")
                    .simultaneousGesture(TapGesture().onEnded { _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    })
                }
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

    // MARK: - Quantity adjustment

    /// Optimistic in-place adjustment. The local quantity bumps immediately
    /// and the SwiftData model is updated so the parent grid/list reflects
    /// the change before the network call completes. On failure we revert
    /// and surface an inline error.
    private func adjustQuantity(by delta: Double) {
        guard let next = StockQuantityAdjustment.targetQuantity(current: localQuantity, delta: delta) else { return }
        setQuantity(to: next)
    }

    private func setQuantity(to next: Double) {
        let previous = localQuantity
        guard next != previous else { return }
        let medium = UIImpactFeedbackGenerator(style: .medium)
        medium.impactOccurred()

        localQuantity = next
        exactQuantityText = StockNumberFormatter.quantity(next)
        row.variant.quantity = next
        try? modelContext.save()
        isAdjusting = true
        errorMessage = nil

        Task { @MainActor in
            let repo = CatalogRepository(companyId: companyId)
            do {
                let dto = try await repo.adjustVariantQuantity(row.variant.id, newQuantity: next)
                localQuantity = dto.quantity
                exactQuantityText = StockNumberFormatter.quantity(dto.quantity)
                row.variant.quantity = dto.quantity
                row.variant.lastSyncedAt = Date()
                try? modelContext.save()

                // Best-effort audit row in `inventory_deductions`. Failures
                // here don't block the user — the quantity update already
                // succeeded, so we log the error but keep going.
                let deductionId = UUID().uuidString
                let userId = dataController.currentUser?.id
                try? await repo.recordVariantDeduction(
                    id: deductionId,
                    catalogVariantId: row.variant.id,
                    previousQuantity: previous,
                    newQuantity: next,
                    deductedBy: userId,
                    reason: "manual_adjustment"
                )
            } catch {
                // Revert optimistic update.
                localQuantity = previous
                exactQuantityText = StockNumberFormatter.quantity(previous)
                row.variant.quantity = previous
                try? modelContext.save()
                errorMessage = error.localizedDescription
            }
            isAdjusting = false
        }
    }

    private var canApplyExactQuantity: Bool {
        canAdjustStock &&
        !isAdjusting &&
        StockQuantityAdjustment.exactQuantity(from: exactQuantityText, current: localQuantity) != nil
    }

    private func applyExactQuantity() {
        guard canApplyExactQuantity,
              let next = StockQuantityAdjustment.exactQuantity(from: exactQuantityText, current: localQuantity)
        else { return }
        setQuantity(to: next)
    }

    private func canApplyCustomDelta(sign: Double) -> Bool {
        canAdjustStock &&
        !isAdjusting &&
        StockQuantityAdjustment.customTargetQuantity(from: customDeltaText, sign: sign, current: localQuantity) != nil
    }

    private func applyCustomDelta(sign: Double) {
        guard canApplyCustomDelta(sign: sign),
              let next = StockQuantityAdjustment.customTargetQuantity(from: customDeltaText, sign: sign, current: localQuantity)
        else { return }
        setQuantity(to: next)
        customDeltaText = ""
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedSku = skuText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWarning = warningText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCritical = criticalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedWarning = Double(trimmedWarning)
        let parsedCritical = Double(trimmedCritical)

        let update = UpdateCatalogVariantDTO(
            sku: trimmedSku.isEmpty ? nil : trimmedSku,
            quantity: localQuantity,
            priceOverride: row.variant.priceOverride,
            unitCostOverride: row.variant.unitCostOverride,
            warningThreshold: parsedWarning,
            criticalThreshold: parsedCritical,
            unitId: row.variant.unitId,
            setNullSku: trimmedSku.isEmpty && row.variant.sku != nil,
            setNullWarningThreshold: trimmedWarning.isEmpty && row.variant.warningThreshold != nil,
            setNullCriticalThreshold: trimmedCritical.isEmpty && row.variant.criticalThreshold != nil
        )

        let repo = CatalogRepository(companyId: companyId)
        do {
            let dto = try await repo.updateVariant(row.variant.id, fields: update)
            row.variant.sku = dto.sku
            row.variant.quantity = dto.quantity
            exactQuantityText = StockNumberFormatter.quantity(dto.quantity)
            row.variant.warningThreshold = dto.warningThreshold
            row.variant.criticalThreshold = dto.criticalThreshold
            row.variant.lastSyncedAt = Date()
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private var quantityString: String {
        StockNumberFormatter.quantity(localQuantity)
    }

    private func statusAccessibilityValue(
        status: ThresholdStatus,
        warning: Double?,
        critical: Double?
    ) -> String {
        var parts = [statusText, "quantity \(quantityString)"]
        if let critical {
            parts.append("critical \(formatThreshold(critical))")
        }
        if let warning {
            parts.append("warning \(formatThreshold(warning))")
        }
        return parts.joined(separator: ", ")
    }

    private var warningPlaceholder: String {
        let inherited = row.family.defaultWarningThreshold ?? row.category?.defaultWarningThreshold
        return inherited.map { "Inherited: \(formatThreshold($0))" } ?? "—"
    }

    private var criticalPlaceholder: String {
        let inherited = row.family.defaultCriticalThreshold ?? row.category?.defaultCriticalThreshold
        return inherited.map { "Inherited: \(formatThreshold($0))" } ?? "—"
    }

    private func formatThreshold(_ value: Double) -> String {
        StockNumberFormatter.quantity(value)
    }

    @MainActor
    private func uploadPickedFamilyImage(_ item: PhotosPickerItem) async {
        imageErrorMessage = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            imageErrorMessage = "// IMAGE LOAD FAILED"
            return
        }

        pendingFamilyImage = image
        isUploadingFamilyImage = true
        defer { isUploadingFamilyImage = false }

        do {
            let url = try await ProductThumbnailUploader.shared.uploadCatalogItemImage(
                image,
                catalogItemId: row.family.id,
                companyId: companyId
            )
            var patch = UpdateCatalogItemDTO()
            patch.imageUrl = url.absoluteString
            let dto = try await CatalogRepository(companyId: companyId).updateFamily(row.family.id, fields: patch)
            row.family.imageUrl = dto.imageUrl
            row.family.lastSyncedAt = Date()
            try? modelContext.save()
            pendingFamilyImage = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            imageErrorMessage = "// IMAGE UPLOAD FAILED"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func saveFamilyTags(_ nextTagIds: Set<String>) async {
        guard nextTagIds != selectedTagIds else { return }
        let previousTagIds = selectedTagIds
        selectedTagIds = nextTagIds
        isSavingTags = true
        errorMessage = nil
        defer { isSavingTags = false }

        do {
            let dtos = try await CatalogRepository(companyId: companyId)
                .replaceFamilyTags(catalogItemId: row.family.id, tagIds: nextTagIds)
            applyFamilyTagDTOs(dtos)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            selectedTagIds = previousTagIds
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func applyFamilyTagDTOs(_ dtos: [CatalogItemTagDTO]) {
        let familyId = row.family.id
        let descriptor = FetchDescriptor<CatalogItemTag>(
            predicate: #Predicate { $0.catalogItemId == familyId }
        )
        if let existing = try? modelContext.fetch(descriptor) {
            for join in existing {
                modelContext.delete(join)
            }
        }
        for dto in dtos {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
        selectedTagIds = Set(dtos.map(\.tagId))
        try? modelContext.save()
    }

    /// Resolve tag names from family-level CatalogItemTag records via @Query
    /// at the parent level — at this layer we already have `row.tagIds` from
    /// the enrichment, but we need the names. A lightweight FetchDescriptor
    /// keeps this isolated to detail.
    private func resolveTagNames() -> [String] {
        guard !selectedTagIds.isEmpty else { return [] }
        return allTags.filter { selectedTagIds.contains($0.id) && $0.deletedAt == nil }
            .map(\.name)
            .sorted()
    }

    private var imageUploadButtonText: String {
        if isUploadingFamilyImage { return "// UPLOADING" }
        return row.family.imageUrl == nil ? "// UPLOAD IMAGE" : "// REPLACE IMAGE"
    }
}
