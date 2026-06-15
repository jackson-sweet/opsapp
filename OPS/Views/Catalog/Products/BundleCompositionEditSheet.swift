//
//  BundleCompositionEditSheet.swift
//  OPS
//
//  Edit-only twin of the children list from NewBundleSheet. Hydrates from
//  the bundle's persisted ProductBundleItem rows, lets the operator add /
//  remove / re-quantify children, then diffs working state vs. persisted on
//  save: inserts new rows, updates qty changes, soft-deletes removed rows,
//  and PATCHes the bundle product with the new effective price + mode.
//

import SwiftUI
import SwiftData

struct BundleCompositionEditSheet: View {
    let product: Product

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Query private var allBundleItems: [ProductBundleItem]
    @Query private var allProducts: [Product]

    @State private var workingChildren: [BundleChildDraft] = []
    @State private var drawerOpen: Bool = false
    @State private var drawerSearch: String = ""

    @State private var pricingMode: BundlePricingMode = .auto
    @State private var overridePriceString: String = ""
    @State private var overridePriceParseError: Bool = false

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var didHydrate: Bool = false

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var persistedGroups: ProductBundleCompositionGroups {
        let rows = allBundleItems
            .filter { $0.bundleProductId == product.id && $0.deletedAt == nil }
        return ProductBundleCompositionGrouping.group(rows)
    }

    private var persistedRequiredItems: [ProductBundleItem] {
        persistedGroups.required
    }

    private var persistedSuggestedItems: [ProductBundleItem] {
        persistedGroups.suggested
    }

    private var persistedSuggestedChildIds: Set<String> {
        Set(persistedSuggestedItems.map(\.childProductId))
    }

    private var productById: [String: Product] {
        Dictionary(uniqueKeysWithValues: allProducts.map { ($0.id, $0) })
    }

    private var eligibleChildren: [Product] {
        allProducts.filter { p in
            p.companyId == companyId
                && p.isActive
                && p.kind != .package
                && p.id != product.id
                && !persistedSuggestedChildIds.contains(p.id)
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

    private var rolledTotal: Double {
        workingChildren.reduce(0) { acc, draft in
            let unit = productById[draft.id]?.basePrice ?? 0
            return acc + unit * draft.quantity
        }
    }

    private var overridePrice: Double? {
        Double(overridePriceString.trimmingCharacters(in: .whitespacesAndNewlines))
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
        if workingChildren.isEmpty { return false }
        if isSaving { return false }
        if pricingMode == .override {
            guard let p = overridePrice, p >= 0 else { return false }
            _ = p
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            childrenSection
                            suggestedAddOnsSection
                            pricingSection
                            errorRow
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }
                    .dismissKeyboardOnTap()
                    saveBar
                }
            }
            .navigationTitle("EDIT BUNDLE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .onAppear { hydrateIfNeeded() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func hydrateIfNeeded() {
        guard !didHydrate else { return }
        didHydrate = true
        workingChildren = persistedRequiredItems.map { item in
            BundleChildDraft(id: item.childProductId,
                             quantity: item.quantity,
                             displayOrder: item.displayOrder)
        }
        if let mode = product.bundlePricingMode,
           let parsed = BundlePricingMode(rawValue: mode) {
            pricingMode = parsed
        }
        if pricingMode == .override {
            overridePriceString = formattedPlainNumber(product.basePrice)
        }
    }

    private func formattedPlainNumber(_ value: Double) -> String {
        if value == 0 { return "" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - Children section (shares visuals w/ NewBundleSheet)

    @ViewBuilder
    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("// CHILDREN · \(workingChildren.count)")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }

            addChildButton
            if drawerOpen {
                drawer
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if workingChildren.isEmpty {
                Text("// NO CHILDREN YET — TAP + ADD CHILD ABOVE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(OPSStyle.Layout.spacing2)
            } else {
                ForEach(workingChildren) { draft in
                    selectedChildRow(draft: draft)
                }
            }
        }
    }

    private var addChildButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : OPSStyle.Animation.panel) {
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
        .accessibilityHint(drawerOpen ? "Hides product search." : "Shows product search.")
        .accessibilityValue(drawerOpen ? "Open" : "Closed")
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
                    .accessibilityLabel("Search products")
                if !drawerSearch.isEmpty {
                    Button { drawerSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    }
                    .accessibilityLabel("Clear product search")
                    .accessibilityHint("Clears the search field.")
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
                        ForEach(filteredDrawerProducts) { p in
                            drawerRow(product: p)
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

    private func drawerRow(product childProduct: Product) -> some View {
        Button {
            addOrIncrement(product: childProduct)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: childProduct.category3Way.iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 24)
                Text(childProduct.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                Text(formattedPrice(childProduct.basePrice))
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
        .accessibilityLabel("Add \(childProduct.name)")
        .accessibilityValue(formattedPrice(childProduct.basePrice))
        .accessibilityHint("Adds this product as a required bundle child.")
    }

    private func addOrIncrement(product childProduct: Product) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let idx = workingChildren.firstIndex(where: { $0.id == childProduct.id }) {
            workingChildren[idx].quantity += 1
        } else {
            let order = workingChildren.map(\.displayOrder).max().map { $0 + 1 } ?? 0
            workingChildren.append(BundleChildDraft(id: childProduct.id, quantity: 1, displayOrder: order))
        }
    }

    @ViewBuilder
    private func selectedChildRow(draft: BundleChildDraft) -> some View {
        let child = productById[draft.id]
        let unitPrice = child?.basePrice ?? 0
        let lineTotal = unitPrice * draft.quantity
        Group {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: child?.category3Way.iconName ?? "questionmark.circle")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(child?.name ?? "—")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineLimit(2)
                            Text(formattedPrice(unitPrice) + " ea")
                                .font(OPSStyle.Typography.metadata)
                                .monospacedDigit()
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        Spacer()
                    }
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        qtyStepper(for: draft)
                        Spacer()
                        Text(formattedPrice(lineTotal))
                            .font(OPSStyle.Typography.metadata)
                            .monospacedDigit()
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
            } else {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: child?.category3Way.iconName ?? "questionmark.circle")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(child?.name ?? "—")
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
            }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(child?.name ?? "Bundle child")
        .accessibilityValue("Quantity \(Int(draft.quantity)), unit \(formattedPrice(unitPrice)), total \(formattedPrice(lineTotal))")
        .accessibilityAction(named: "Remove") {
            removeChild(draft)
        }
    }

    private func qtyStepper(for draft: BundleChildDraft) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                guard let idx = workingChildren.firstIndex(where: { $0.id == draft.id }) else { return }
                if workingChildren[idx].quantity > 1 {
                    workingChildren[idx].quantity -= 1
                } else {
                    workingChildren.remove(at: idx)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .accessibilityLabel("Decrease quantity")
            .accessibilityHint(draft.quantity > 1 ? "Subtracts one from this bundle child." : "Removes this bundle child.")
            Text("× \(Int(draft.quantity))")
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(minWidth: 32)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                guard let idx = workingChildren.firstIndex(where: { $0.id == draft.id }) else { return }
                workingChildren[idx].quantity += 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .accessibilityLabel("Increase quantity")
            .accessibilityHint("Adds one to this bundle child.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("Quantity \(Int(draft.quantity))")
    }

    private func removeChild(_ draft: BundleChildDraft) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        workingChildren.removeAll { $0.id == draft.id }
    }

    @ViewBuilder
    private var suggestedAddOnsSection: some View {
        if !persistedSuggestedItems.isEmpty {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                CatalogSectionHeader("SUGGESTED ADD-ONS")
                ForEach(persistedSuggestedItems) { item in
                    suggestedChildRow(item: item)
                }
            }
        }
    }

    private func suggestedChildRow(item: ProductBundleItem) -> some View {
        let child = productById[item.childProductId]
        let unitPrice = child?.basePrice ?? 0
        let lineTotal = unitPrice * item.quantity
        return HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: child?.category3Way.iconName ?? "questionmark.circle")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(child?.name ?? "—")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Text("× \(Int(item.quantity)) · \(formattedPrice(unitPrice)) ea")
                    .font(OPSStyle.Typography.metadata)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Text("+ \(formattedPrice(lineTotal))")
                .font(OPSStyle.Typography.metadata)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.tertiaryText)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(child?.name ?? "Suggested add-on")
        .accessibilityValue("Quantity \(Int(item.quantity)), unit \(formattedPrice(unitPrice)), add-on total \(formattedPrice(lineTotal))")
    }

    // MARK: - Pricing

    @ViewBuilder
    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("PRICING")
            HStack(spacing: OPSStyle.Layout.spacing1) {
                ForEach(BundlePricingMode.allCases) { mode in
                    modeChip(mode)
                }
            }
            switch pricingMode {
            case .auto:
                rolledReadout
            case .override:
                overrideFields
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
        .accessibilityHint("Sets how the required bundle children determine price.")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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

    // MARK: - Error row

    @ViewBuilder
    private var errorRow: some View {
        if let errorMessage = errorMessage {
            Text(errorMessage)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.errorText)
        }
    }

    // MARK: - Save bar

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
                        Text("SAVE BUNDLE")
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
            .accessibilityLabel("Save bundle")
            .accessibilityHint(canSave ? "Saves required child quantities and bundle pricing." : "Add required children and fix price fields first.")
            .accessibilityValue(isSaving ? "Saving" : (canSave ? "Ready" : "Locked"))
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.background)
    }

    private func formattedPrice(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$0"
    }

    // MARK: - Save (diff against persisted)

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let persistedRequiredByChildId: [String: ProductBundleItem] = Dictionary(
            uniqueKeysWithValues: persistedRequiredItems.map { ($0.childProductId, $0) }
        )
        let workingByChildId: [String: BundleChildDraft] = Dictionary(
            uniqueKeysWithValues: workingChildren.map { ($0.id, $0) }
        )

        let toCreate: [BundleChildDraft] = workingChildren.filter {
            persistedRequiredByChildId[$0.id] == nil
        }
        let toDelete: [ProductBundleItem] = persistedRequiredItems.filter {
            workingByChildId[$0.childProductId] == nil
        }
        let toUpdate: [(ProductBundleItem, BundleChildDraft)] = workingChildren.compactMap { draft in
            guard let existing = persistedRequiredByChildId[draft.id] else { return nil }
            if existing.quantity != draft.quantity || existing.displayOrder != draft.displayOrder {
                return (existing, draft)
            }
            return nil
        }

        let repo = ProductBundleItemRepository(companyId: companyId)
        do {
            // Deletes first → soft-delete via server then mark local
            for row in toDelete {
                try await repo.softDelete(row.id)
                row.deletedAt = Date()
                row.updatedAt = Date()
            }
            // Updates
            for (existing, draft) in toUpdate {
                var patch = UpdateProductBundleItemDTO()
                patch.quantity = draft.quantity
                patch.displayOrder = draft.displayOrder
                let updated = try await repo.update(existing.id, fields: patch)
                existing.quantity = updated.quantity
                existing.displayOrder = updated.displayOrder
                existing.updatedAt = SupabaseDate.parse(updated.updatedAt) ?? Date()
            }
            // Creates
            for draft in toCreate {
                let dto = CreateProductBundleItemDTO(
                    id: UUID().uuidString,
                    companyId: companyId,
                    bundleProductId: product.id,
                    childProductId: draft.id,
                    quantity: draft.quantity,
                    displayOrder: draft.displayOrder
                )
                let created = try await repo.create(dto)
                modelContext.insert(created.toModel())
            }
            try? modelContext.save()

            // PATCH the bundle product itself with effective price + mode
            var patch = UpdateProductDTO()
            patch.basePrice = effectivePrice
            patch.bundlePricingMode = pricingMode.rawValue
            let productRepo = ProductRepository(companyId: companyId)
            let updated = try await productRepo.update(product.id, fields: patch)
            product.basePrice = updated.basePrice
            product.bundlePricingMode = updated.bundlePricingMode
            try? modelContext.save()

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}
