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

struct VariantDetailView: View {
    let row: EnrichedVariantRow

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var canAdjustStock: Bool { permissionStore.can("catalog.stock.adjust") }
    private var canManage:       Bool { permissionStore.can("catalog.manage") }

    @State private var localQuantity: Double
    @State private var skuText: String
    @State private var warningText: String
    @State private var criticalText: String
    @State private var isSaving: Bool = false
    @State private var isAdjusting: Bool = false
    @State private var errorMessage: String? = nil

    // USED IN reverse-link queries — surfaces every active Product that
    // references either this variant directly (recipe row) or this
    // variant's family head (recipe row or stock-linked product).
    @Query private var allProductMaterials: [ProductMaterial]
    @Query private var allProductsForUsage: [Product]

    init(row: EnrichedVariantRow) {
        self.row = row
        _localQuantity = State(initialValue: row.variant.quantity)
        _skuText = State(initialValue: row.variant.sku ?? "")
        _warningText = State(initialValue: row.variant.warningThreshold.map { String($0) } ?? "")
        _criticalText = State(initialValue: row.variant.criticalThreshold.map { String($0) } ?? "")
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
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
                        quantityCard
                        usedInCard
                        if canManage {
                            thresholdsCard
                            skuCard
                        }
                        if !row.tagIds.isEmpty {
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
                    }
                }
            }
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
                    Image("ops.add")
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

    private var tagsCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// TAGS")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Tags live at the family level. Manage them from the catalog kebab.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            tagChips
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
                            Image("ops.chevron-right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    }
                    .buttonStyle(.plain)
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
        let previous = localQuantity
        let next = max(0, previous + delta)
        guard next != previous else { return }
        let medium = UIImpactFeedbackGenerator(style: .medium)
        medium.impactOccurred()

        localQuantity = next
        row.variant.quantity = next
        try? modelContext.save()
        isAdjusting = true
        errorMessage = nil

        Task { @MainActor in
            let repo = CatalogRepository(companyId: companyId)
            do {
                let dto = try await repo.adjustVariantQuantity(row.variant.id, newQuantity: next)
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
                row.variant.quantity = previous
                try? modelContext.save()
                errorMessage = error.localizedDescription
            }
            isAdjusting = false
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let update = CatalogVariantFormPayload.update(
            skuText: skuText,
            quantity: localQuantity,
            priceOverride: row.variant.priceOverride,
            unitCostOverride: row.variant.unitCostOverride,
            warningThresholdText: warningText,
            criticalThresholdText: criticalText,
            unitId: row.variant.unitId
        )

        let repo = CatalogRepository(companyId: companyId)
        do {
            let dto = try await repo.updateVariant(row.variant.id, fields: update)
            row.variant.sku = dto.sku
            row.variant.quantity = dto.quantity
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
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: localQuantity)) ?? "0"
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
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// Resolve tag names from family-level CatalogItemTag records via @Query
    /// at the parent level — at this layer we already have `row.tagIds` from
    /// the enrichment, but we need the names. A lightweight FetchDescriptor
    /// keeps this isolated to detail.
    private func resolveTagNames() -> [String] {
        guard !row.tagIds.isEmpty else { return [] }
        let ids = row.tagIds
        let descriptor = FetchDescriptor<CatalogTag>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { ids.contains($0.id) && $0.deletedAt == nil }
            .map(\.name)
            .sorted()
    }
}
