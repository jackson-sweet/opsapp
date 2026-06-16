//
//  ProductOptionAuthoringSheet.swift
//  OPS
//
//  Reusable authoring surface for product_options, product_option_values,
//  and product_pricing_modifiers. Product detail and Catalog Setup LINKS
//  both present this sheet so sellable configuration is one workflow.
//

import SwiftUI
import SwiftData

struct ProductOptionAuthoringSheet: View {
    let product: Product

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var permissionStore = PermissionStore.shared

    @Query private var allOptions: [ProductOption]
    @Query private var allOptionValues: [ProductOptionValue]
    @Query private var allModifiers: [ProductPricingModifier]

    @State private var optionEditorRequest: ProductOptionEditorRequest?
    @State private var modifierEditorRequest: ProductPricingModifierEditorRequest?
    @State private var pendingOptionDelete: ProductOption?
    @State private var pendingModifierDelete: ProductPricingModifier?
    @State private var isMutating: Bool = false
    @State private var errorMessage: String?

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var canManageProductOptions: Bool {
        permissionStore.can("catalog.products.manage")
    }

    private var productOptions: [ProductOption] {
        allOptions
            .filter { $0.productId == product.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var productOptionValues: [ProductOptionValue] {
        let optionIds = Set(productOptions.map(\.id))
        return allOptionValues
            .filter { optionIds.contains($0.optionId) }
            .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
    }

    private var productModifiers: [ProductPricingModifier] {
        let optionOrder = Dictionary(uniqueKeysWithValues: productOptions.enumerated().map { ($0.element.id, $0.offset) })
        return allModifiers
            .filter { $0.productId == product.id }
            .sorted {
                (optionOrder[$0.optionId] ?? Int.max, $0.amount, $0.id) <
                (optionOrder[$1.optionId] ?? Int.max, $1.amount, $1.id)
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        if !canManageProductOptions {
                            setupBanner(
                                title: "SYS :: READ ONLY",
                                message: "Product option changes require catalog.products.manage.",
                                isError: true
                            )
                        }
                        optionsSection
                        modifiersSection
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
                .dismissKeyboardOnTap()
            }
            .catalogNavigationTitle("OPTIONS")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .accessibilityHint("Closes product option authoring.")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .errorToast($errorMessage, label: Feedback.Err.operationFailed)
        .sheet(item: $optionEditorRequest) { request in
            ProductOptionEditorSheet(
                product: product,
                editingOption: request.option,
                defaultSortOrder: productOptions.count
            )
            .environmentObject(dataController)
        }
        .sheet(item: $modifierEditorRequest) { request in
            ProductPricingModifierEditorSheet(
                product: product,
                editingModifier: request.modifier,
                options: productOptions,
                optionValues: productOptionValues
            )
            .environmentObject(dataController)
        }
        .alert(
            "Remove option?",
            isPresented: Binding(
                get: { pendingOptionDelete != nil },
                set: { if !$0 { pendingOptionDelete = nil } }
            ),
            presenting: pendingOptionDelete
        ) { option in
            Button("Cancel", role: .cancel) { pendingOptionDelete = nil }
            Button("Remove", role: .destructive) {
                Task { await deleteOption(option) }
            }
        } message: { option in
            Text("Remove \(option.name), its values, pricing rules, and mappings?")
        }
        .alert(
            "Remove price rule?",
            isPresented: Binding(
                get: { pendingModifierDelete != nil },
                set: { if !$0 { pendingModifierDelete = nil } }
            ),
            presenting: pendingModifierDelete
        ) { modifier in
            Button("Cancel", role: .cancel) { pendingModifierDelete = nil }
            Button("Remove", role: .destructive) {
                Task { await deleteModifier(modifier) }
            }
        } message: { _ in
            Text("Remove this pricing modifier?")
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                CatalogSectionHeader("OPTIONS - \(productOptions.count)")
                Spacer()
                Button {
                    guard canManageProductOptions else {
                        blockUnauthorizedMutation()
                        return
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    optionEditorRequest = ProductOptionEditorRequest(option: nil)
                } label: {
                    Label("ADD OPTION", systemImage: "plus")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .disabled(isMutating || !canManageProductOptions)
                .accessibilityLabel("Add product option")
                .accessibilityHint(canManageProductOptions ? "Creates a new sellable choice for this product." : "Requires catalog products manage permission.")
                .accessibilityValue(isMutating || !canManageProductOptions ? "Locked" : "Ready")
            }

            if productOptions.isEmpty {
                setupBanner(
                    title: "NO OPTIONS",
                    message: "Add the sellable choices this product needs before it hits an estimate."
                )
            } else {
                ForEach(productOptions) { option in
                    optionRow(option)
                }
            }
        }
        .setupPanel()
    }

    private var modifiersSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                CatalogSectionHeader("PRICE RULES - \(productModifiers.count)")
                Spacer()
                Button {
                    guard canManageProductOptions else {
                        blockUnauthorizedMutation()
                        return
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    modifierEditorRequest = ProductPricingModifierEditorRequest(modifier: nil)
                } label: {
                    Label("ADD RULE", systemImage: "plus")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(productOptions.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .disabled(isMutating || productOptions.isEmpty || !canManageProductOptions)
                .accessibilityLabel("Add price rule")
                .accessibilityHint(productOptions.isEmpty ? "Create an option before adding pricing rules." : "Creates a price rule for this product option set.")
                .accessibilityValue(isMutating || productOptions.isEmpty || !canManageProductOptions ? "Locked" : "Ready")
            }

            if productOptions.isEmpty {
                setupBanner(title: "NO OPTIONS", message: "Create an option before adding pricing rules.")
            } else if productModifiers.isEmpty {
                setupBanner(title: "NO PRICE RULES", message: "Add price impact only where the choice changes the sell price.")
            } else {
                ForEach(productModifiers) { modifier in
                    modifierRow(modifier)
                }
            }
        }
        .setupPanel()
    }

    private func optionRow(_ option: ProductOption) -> some View {
        let values = valuesFor(option)
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(option.name.uppercased())
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        metadataChip(labelForKind(option.kind))
                        if option.required { metadataChip("REQUIRED") }
                        if option.affectsPrice { metadataChip("PRICE") }
                        if option.affectsRecipe { metadataChip("RECIPE") }
                    }
                }
                Spacer(minLength: 0)
                reorderButton(systemName: "chevron.up", disabled: isFirstOption(option) || !canManageProductOptions) {
                    Task { await moveOption(option, delta: -1) }
                }
                reorderButton(systemName: "chevron.down", disabled: isLastOption(option) || !canManageProductOptions) {
                    Task { await moveOption(option, delta: 1) }
                }
                iconButton(
                    systemName: "pencil",
                    color: OPSStyle.Colors.primaryAccent,
                    disabled: !canManageProductOptions,
                    label: "Edit option"
                ) {
                    guard canManageProductOptions else {
                        blockUnauthorizedMutation()
                        return
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    optionEditorRequest = ProductOptionEditorRequest(option: option)
                }
                iconButton(
                    systemName: "trash",
                    color: OPSStyle.Colors.errorText,
                    disabled: !canManageProductOptions,
                    label: "Remove option"
                ) {
                    guard canManageProductOptions else {
                        blockUnauthorizedMutation()
                        return
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    pendingOptionDelete = option
                }
            }

            if let defaultValue = option.defaultValue, !defaultValue.isEmpty {
                Text("DEFAULT - \(defaultValue)")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else if let source = option.optionDefaultSource, !source.isEmpty {
                Text("DEFAULT FROM - \(source)")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            if option.kind == .select {
                if values.isEmpty {
                    Text("NO VALUES")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.errorText)
                } else {
                    valueChips(values)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Product option \(option.name)")
        .accessibilityValue(optionAccessibilityValue(option, values: values))
    }

    private func modifierRow(_ modifier: ProductPricingModifier) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(triggerSentence(modifier))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    metadataChip(labelForModifierKind(modifier.modifierKind))
                }
                Spacer(minLength: 0)
                iconButton(
                    systemName: "pencil",
                    color: OPSStyle.Colors.primaryAccent,
                    disabled: !canManageProductOptions,
                    label: "Edit price rule"
                ) {
                    guard canManageProductOptions else {
                        blockUnauthorizedMutation()
                        return
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    modifierEditorRequest = ProductPricingModifierEditorRequest(modifier: modifier)
                }
                iconButton(
                    systemName: "trash",
                    color: OPSStyle.Colors.errorText,
                    disabled: !canManageProductOptions,
                    label: "Remove price rule"
                ) {
                    guard canManageProductOptions else {
                        blockUnauthorizedMutation()
                        return
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    pendingModifierDelete = modifier
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Price rule")
        .accessibilityValue(triggerSentence(modifier))
    }

    private func valuesFor(_ option: ProductOption) -> [ProductOptionValue] {
        productOptionValues
            .filter { $0.optionId == option.id }
            .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
    }

    private func valueChips(_ values: [ProductOptionValue]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                ForEach(values) { value in
                    metadataChip(value.value)
                }
            }
        }
    }

    private func isFirstOption(_ option: ProductOption) -> Bool {
        productOptions.first?.id == option.id
    }

    private func isLastOption(_ option: ProductOption) -> Bool {
        productOptions.last?.id == option.id
    }

    @MainActor
    private func moveOption(_ option: ProductOption, delta: Int) async {
        guard canManageProductOptions else {
            blockUnauthorizedMutation()
            return
        }
        guard !isMutating,
              let currentIndex = productOptions.firstIndex(where: { $0.id == option.id })
        else { return }
        let targetIndex = currentIndex + delta
        guard productOptions.indices.contains(targetIndex) else { return }

        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        var reordered = productOptions
        reordered.swapAt(currentIndex, targetIndex)
        let repo = ProductRichnessRepository(companyId: companyId)

        do {
            for (index, item) in reordered.enumerated() {
                let fields = UpdateProductOptionDTO(
                    name: item.name,
                    kind: item.kind.rawValue,
                    affectsPrice: item.affectsPrice,
                    affectsRecipe: item.affectsRecipe,
                    required: item.required,
                    defaultValue: item.defaultValue,
                    optionDefaultSource: item.optionDefaultSource,
                    sortOrder: index
                )
                let dto = try await repo.updateOption(item.id, fields: fields)
                ProductOptionLocalStore.upsertOption(dto, in: modelContext)
            }
            try? modelContext.save()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            ToastCenter.shared.present(Feedback.Catalog.optionMoved)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteOption(_ option: ProductOption) async {
        guard canManageProductOptions else {
            blockUnauthorizedMutation()
            pendingOptionDelete = nil
            return
        }
        guard !isMutating else { return }
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        do {
            try await ProductRichnessRepository(companyId: companyId).deleteOption(option.id)
            ProductOptionLocalStore.deleteOption(id: option.id, in: modelContext)
            try? modelContext.save()
            pendingOptionDelete = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            ToastCenter.shared.present(Feedback.Catalog.optionRemoved)
        } catch {
            pendingOptionDelete = nil
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteModifier(_ modifier: ProductPricingModifier) async {
        guard canManageProductOptions else {
            blockUnauthorizedMutation()
            pendingModifierDelete = nil
            return
        }
        guard !isMutating else { return }
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        do {
            try await ProductRichnessRepository(companyId: companyId).deletePricingModifier(modifier.id)
            ProductOptionLocalStore.deleteModifier(id: modifier.id, in: modelContext)
            try? modelContext.save()
            pendingModifierDelete = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            ToastCenter.shared.present(Feedback.Catalog.priceRuleRemoved)
        } catch {
            pendingModifierDelete = nil
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    private func triggerSentence(_ modifier: ProductPricingModifier) -> String {
        let optionName = productOptions.first(where: { $0.id == modifier.optionId })?.name ?? "Option"
        if let triggerValueId = modifier.triggerValueId,
           let value = productOptionValues.first(where: { $0.id == triggerValueId }) {
            return "When \(optionName) = \(value.value) -> \(effectClause(modifier))"
        }
        if let min = modifier.triggerIntMin, let max = modifier.triggerIntMax {
            if min == max {
                return "When \(optionName) = \(min) -> \(effectClause(modifier))"
            }
            return "When \(optionName) is \(min)-\(max) -> \(effectClause(modifier))"
        }
        if let min = modifier.triggerIntMin {
            return "When \(optionName) >= \(min) -> \(effectClause(modifier))"
        }
        if let max = modifier.triggerIntMax {
            return "When \(optionName) <= \(max) -> \(effectClause(modifier))"
        }
        return "When \(optionName) is set -> \(effectClause(modifier))"
    }

    private func effectClause(_ modifier: ProductPricingModifier) -> String {
        switch modifier.modifierKind {
        case .addPerUnit:
            return "\(formatMoney(modifier.amount)) per unit"
        case .addFlat:
            return "\(formatMoney(modifier.amount)) flat"
        case .addPerCount:
            return "\(formatMoney(modifier.amount)) per count"
        case .multiplyUnitPrice:
            return "\(formatNumber(modifier.amount))x unit price"
        }
    }

    private func blockUnauthorizedMutation() {
        errorMessage = ProductOptionAuthoringError.missingManagePermission.localizedDescription
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func optionAccessibilityValue(_ option: ProductOption, values: [ProductOptionValue]) -> String {
        var parts = [labelForKind(option.kind)]
        if option.required { parts.append("required") }
        if option.affectsPrice { parts.append("affects price") }
        if option.affectsRecipe { parts.append("affects recipe") }
        if option.kind == .select {
            parts.append("\(values.count) value\(values.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    private func iconButton(
        systemName: String,
        color: Color,
        disabled: Bool = false,
        label: String,
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(disabled ? OPSStyle.Colors.tertiaryText : color)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
        .buttonStyle(.plain)
        .disabled(isMutating || disabled)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? label)
        .accessibilityValue(isMutating || disabled ? "Locked" : "Ready")
    }

    private func reorderButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(disabled ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
        .buttonStyle(.plain)
        .disabled(disabled || isMutating)
        .accessibilityLabel(systemName == "chevron.up" ? "Move option up" : "Move option down")
        .accessibilityHint("Changes this option's display order.")
        .accessibilityValue(disabled || isMutating ? "Locked" : "Ready")
    }

    private func setupBanner(title: String, message: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(title)
                .font(OPSStyle.Typography.category)
                .foregroundColor(isError ? OPSStyle.Colors.errorText : OPSStyle.Colors.primaryText)
            Text(message)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(isError ? OPSStyle.Colors.errorText : OPSStyle.Colors.cardBorder,
                        lineWidth: OPSStyle.Layout.Border.standard)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }
}

private struct ProductOptionEditorSheet: View {
    let product: Product
    let editingOption: ProductOption?
    let defaultSortOrder: Int

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var permissionStore = PermissionStore.shared

    @Query private var allOptionValues: [ProductOptionValue]

    @State private var name: String
    @State private var kind: ProductOptionKind
    @State private var required: Bool
    @State private var affectsPrice: Bool
    @State private var affectsRecipe: Bool
    @State private var defaultValue: String
    @State private var optionDefaultSource: String
    @State private var valueDrafts: [ProductOptionValueDraft] = []
    @State private var removedValueIds: Set<String> = []
    @State private var didHydrateValues: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    init(product: Product, editingOption: ProductOption?, defaultSortOrder: Int) {
        self.product = product
        self.editingOption = editingOption
        self.defaultSortOrder = defaultSortOrder
        _name = State(initialValue: editingOption?.name ?? "")
        _kind = State(initialValue: editingOption?.kind ?? .select)
        _required = State(initialValue: editingOption?.required ?? true)
        _affectsPrice = State(initialValue: editingOption?.affectsPrice ?? false)
        _affectsRecipe = State(initialValue: editingOption?.affectsRecipe ?? false)
        _defaultValue = State(initialValue: editingOption?.defaultValue ?? "")
        _optionDefaultSource = State(initialValue: editingOption?.optionDefaultSource ?? "")
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var canManageProductOptions: Bool {
        permissionStore.can("catalog.products.manage")
    }

    private var existingValues: [ProductOptionValue] {
        guard let editingOption else { return [] }
        return allOptionValues
            .filter { $0.optionId == editingOption.id }
            .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
    }

    private var canSave: Bool {
        if isSaving { return false }
        if !canManageProductOptions { return false }
        if trimmed(name).isEmpty { return false }
        if kind == .select {
            return !normalizedValueDrafts().isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        if !canManageProductOptions {
                            setupBanner(
                                title: "SYS :: READ ONLY",
                                message: "Product option changes require catalog.products.manage.",
                                isError: true
                            )
                        }
                        coreSection
                        if kind == .select {
                            valuesSection
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
                .dismissKeyboardOnTap()
            }
            .catalogNavigationTitle(editingOption == nil ? "NEW OPTION" : "EDIT OPTION")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text(isSaving ? "SAVING" : "SAVE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(editingOption == nil ? "Create product option" : "Save product option")
                    .accessibilityHint(canSave ? "Saves this option and its values." : "Complete the required option fields first.")
                    .accessibilityValue(isSaving ? "Saving" : (canSave ? "Ready" : "Locked"))
                }
            }
            .onAppear(perform: hydrateValuesIfNeeded)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .errorToast($errorMessage, label: Feedback.Err.operationFailed)
    }

    private var coreSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("OPTION")
            CatalogFieldLabel("Name")
            TextField("", text: $name)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Kind")
            Picker("Kind", selection: $kind) {
                ForEach(ProductOptionKind.allCases, id: \.self) { value in
                    Text(labelForKind(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .tint(OPSStyle.Colors.text)
            .accessibilityLabel("Option kind")
            .accessibilityValue(labelForKind(kind))
            .onChange(of: kind) { _, next in
                if next == .select, valueDrafts.isEmpty {
                    valueDrafts = [ProductOptionValueDraft(value: "")]
                }
            }

            Toggle(isOn: $required) {
                Text("Required")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.text)

            Toggle(isOn: $affectsPrice) {
                Text("Affects price")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.text)

            Toggle(isOn: $affectsRecipe) {
                Text("Affects recipe")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.text)

            CatalogFieldLabel("Default")
            TextField("", text: $defaultValue)
                .textFieldStyle(CatalogTextFieldStyle())

            CatalogFieldLabel("Default source")
            TextField("", text: $optionDefaultSource)
                .textInputAutocapitalization(.never)
                .textFieldStyle(CatalogTextFieldStyle())
        }
        .setupPanel()
    }

    private var valuesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                CatalogSectionHeader("VALUES - \(normalizedValueDrafts().count)")
                Spacer()
                Button {
                    guard canManageProductOptions else {
                        blockUnauthorizedMutation()
                        return
                    }
                    valueDrafts.append(ProductOptionValueDraft(value: ""))
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Label("ADD VALUE", systemImage: "plus")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
                .disabled(!canManageProductOptions)
                .accessibilityLabel("Add option value")
                .accessibilityHint("Adds another value to this select option.")
                .accessibilityValue(canManageProductOptions ? "Ready" : "Locked")
            }

            ForEach($valueDrafts) { $draft in
                valueDraftRow($draft)
            }
        }
        .setupPanel()
    }

    private func valueDraftRow(_ draft: Binding<ProductOptionValueDraft>) -> some View {
        let id = draft.wrappedValue.id
        return HStack(spacing: OPSStyle.Layout.spacing2) {
            TextField("", text: draft.value)
                .textFieldStyle(CatalogTextFieldStyle())
            Button {
                moveValueDraft(id, delta: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .foregroundColor(isFirstValueDraft(id) ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(isFirstValueDraft(id) || !canManageProductOptions)
            .accessibilityLabel("Move value up")
            .accessibilityHint("Moves this value earlier in the list.")
            .accessibilityValue(isFirstValueDraft(id) || !canManageProductOptions ? "Locked" : "Ready")
            Button {
                moveValueDraft(id, delta: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .foregroundColor(isLastValueDraft(id) ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(isLastValueDraft(id) || !canManageProductOptions)
            .accessibilityLabel("Move value down")
            .accessibilityHint("Moves this value later in the list.")
            .accessibilityValue(isLastValueDraft(id) || !canManageProductOptions ? "Locked" : "Ready")
            Button {
                removeValueDraft(id)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(OPSStyle.Colors.errorText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(!canManageProductOptions)
            .accessibilityLabel("Remove option value")
            .accessibilityHint(trimmed(draft.wrappedValue.value).isEmpty ? "Removes this value row." : "Removes \(trimmed(draft.wrappedValue.value)).")
            .accessibilityValue(canManageProductOptions ? "Ready" : "Locked")
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .accessibilityElement(children: .contain)
    }

    private func hydrateValuesIfNeeded() {
        guard !didHydrateValues else { return }
        didHydrateValues = true
        valueDrafts = existingValues.map {
            ProductOptionValueDraft(serverId: $0.id, value: $0.value, sortOrder: $0.sortOrder)
        }
        if editingOption == nil && kind == .select && valueDrafts.isEmpty {
            valueDrafts = [ProductOptionValueDraft(value: "")]
        }
    }

    private func normalizedValueDrafts() -> [ProductOptionValueDraft] {
        valueDrafts.enumerated().compactMap { index, draft in
            let value = trimmed(draft.value)
            guard !value.isEmpty else { return nil }
            return ProductOptionValueDraft(
                id: draft.id,
                serverId: draft.serverId,
                value: value,
                sortOrder: index
            )
        }
    }

    private func validateDraft() -> String? {
        if trimmed(name).isEmpty {
            return "Name is required."
        }
        if kind == .select {
            let values = normalizedValueDrafts()
            if values.isEmpty {
                return "Select options require at least one value."
            }
            let normalizedValues = values.map { normalized($0.value) }
            if Set(normalizedValues).count != normalizedValues.count {
                return "Value names must be unique for this option."
            }
        }
        return nil
    }

    @MainActor
    private func save() async {
        guard canManageProductOptions else {
            blockUnauthorizedMutation()
            return
        }
        guard !isSaving else { return }
        if let validation = validateDraft() {
            errorMessage = validation
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let repo = ProductRichnessRepository(companyId: companyId)
            let optionId: String
            let optionSortOrder = editingOption?.sortOrder ?? defaultSortOrder

            if let editingOption {
                let dto = try await repo.updateOption(
                    editingOption.id,
                    fields: UpdateProductOptionDTO(
                        name: trimmed(name),
                        kind: kind.rawValue,
                        affectsPrice: affectsPrice,
                        affectsRecipe: affectsRecipe,
                        required: required,
                        defaultValue: trimmedOptional(defaultValue),
                        optionDefaultSource: trimmedOptional(optionDefaultSource),
                        sortOrder: optionSortOrder
                    )
                )
                ProductOptionLocalStore.upsertOption(dto, in: modelContext)
                optionId = dto.id
            } else {
                let dto = try await repo.createOption(
                    CreateProductOptionDTO(
                        productId: product.id,
                        name: trimmed(name),
                        kind: kind.rawValue,
                        affectsPrice: affectsPrice,
                        affectsRecipe: affectsRecipe,
                        required: required,
                        defaultValue: trimmedOptional(defaultValue),
                        optionDefaultSource: trimmedOptional(optionDefaultSource),
                        sortOrder: optionSortOrder
                    )
                )
                ProductOptionLocalStore.upsertOption(dto, in: modelContext)
                optionId = dto.id
            }

            let retainedValueIds = try await saveValues(optionId: optionId, repo: repo)
            for staleId in existingValues.map(\.id) where !retainedValueIds.contains(staleId) {
                try await repo.deleteOptionValue(staleId)
                ProductOptionLocalStore.deleteOptionValue(id: staleId, in: modelContext)
            }

            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ToastCenter.shared.present(Feedback.Catalog.optionSaved)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveValues(optionId: String, repo: ProductRichnessRepository) async throws -> Set<String> {
        guard canManageProductOptions else {
            throw ProductOptionAuthoringError.missingManagePermission
        }
        guard kind == .select else { return [] }
        var retainedValueIds: Set<String> = []

        for (index, draft) in normalizedValueDrafts().enumerated() {
            if let serverId = draft.serverId {
                let dto = try await repo.updateOptionValue(
                    serverId,
                    fields: UpdateProductOptionValueDTO(value: draft.value, sortOrder: index)
                )
                guard dto.optionId == optionId else {
                    throw ProductOptionAuthoringError.valueParentMismatch
                }
                ProductOptionLocalStore.upsertOptionValue(dto, in: modelContext)
                retainedValueIds.insert(dto.id)
            } else {
                let dto = try await repo.createOptionValue(
                    CreateProductOptionValueDTO(optionId: optionId, value: draft.value, sortOrder: index)
                )
                guard dto.optionId == optionId else {
                    throw ProductOptionAuthoringError.valueParentMismatch
                }
                ProductOptionLocalStore.upsertOptionValue(dto, in: modelContext)
                retainedValueIds.insert(dto.id)
            }
        }

        return retainedValueIds.subtracting(removedValueIds)
    }

    private func moveValueDraft(_ id: String, delta: Int) {
        guard canManageProductOptions else {
            blockUnauthorizedMutation()
            return
        }
        guard let index = valueDrafts.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard valueDrafts.indices.contains(target) else { return }
        valueDrafts.swapAt(index, target)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func removeValueDraft(_ id: String) {
        guard canManageProductOptions else {
            blockUnauthorizedMutation()
            return
        }
        if let serverId = valueDrafts.first(where: { $0.id == id })?.serverId {
            removedValueIds.insert(serverId)
        }
        valueDrafts.removeAll { $0.id == id }
        if valueDrafts.isEmpty {
            valueDrafts = [ProductOptionValueDraft(value: "")]
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func blockUnauthorizedMutation() {
        errorMessage = ProductOptionAuthoringError.missingManagePermission.localizedDescription
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func isFirstValueDraft(_ id: String) -> Bool {
        valueDrafts.first?.id == id
    }

    private func isLastValueDraft(_ id: String) -> Bool {
        valueDrafts.last?.id == id
    }

    private func setupBanner(title: String, message: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(title)
                .font(OPSStyle.Typography.category)
                .foregroundColor(isError ? OPSStyle.Colors.errorText : OPSStyle.Colors.primaryText)
            Text(message)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(isError ? OPSStyle.Colors.errorText : OPSStyle.Colors.cardBorder,
                        lineWidth: OPSStyle.Layout.Border.standard)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }
}

private struct ProductPricingModifierEditorSheet: View {
    let product: Product
    let editingModifier: ProductPricingModifier?
    let options: [ProductOption]
    let optionValues: [ProductOptionValue]

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var permissionStore = PermissionStore.shared

    @State private var selectedOptionId: String
    @State private var selectedValueId: String
    @State private var triggerIntMin: String
    @State private var triggerIntMax: String
    @State private var modifierKind: PricingModifierKind
    @State private var amountString: String
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    init(
        product: Product,
        editingModifier: ProductPricingModifier?,
        options: [ProductOption],
        optionValues: [ProductOptionValue]
    ) {
        self.product = product
        self.editingModifier = editingModifier
        self.options = options
        self.optionValues = optionValues
        _selectedOptionId = State(initialValue: editingModifier?.optionId ?? options.first?.id ?? "")
        _selectedValueId = State(initialValue: editingModifier?.triggerValueId ?? "")
        _triggerIntMin = State(initialValue: editingModifier?.triggerIntMin.map(String.init) ?? "")
        _triggerIntMax = State(initialValue: editingModifier?.triggerIntMax.map(String.init) ?? "")
        _modifierKind = State(initialValue: editingModifier?.modifierKind ?? .addPerUnit)
        _amountString = State(initialValue: editingModifier.map { formatPlainNumber($0.amount) } ?? "")
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var canManageProductOptions: Bool {
        permissionStore.can("catalog.products.manage")
    }

    private var selectedOption: ProductOption? {
        options.first { $0.id == selectedOptionId }
    }

    private var valuesForSelectedOption: [ProductOptionValue] {
        optionValues
            .filter { $0.optionId == selectedOptionId }
            .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
    }

    private var canSave: Bool {
        !isSaving && canManageProductOptions && normalizedDraft().error == nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        if !canManageProductOptions {
                            setupBanner(
                                title: "SYS :: READ ONLY",
                                message: "Product option changes require catalog.products.manage.",
                                isError: true
                            )
                        }
                        formSection
                        previewSection
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
                .dismissKeyboardOnTap()
            }
            .catalogNavigationTitle(editingModifier == nil ? "NEW RULE" : "EDIT RULE")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text(isSaving ? "SAVING" : "SAVE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(editingModifier == nil ? "Create price rule" : "Save price rule")
                    .accessibilityHint(canSave ? "Saves this pricing modifier." : "Complete the required price rule fields first.")
                    .accessibilityValue(isSaving ? "Saving" : (canSave ? "Ready" : "Locked"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .errorToast($errorMessage, label: Feedback.Err.operationFailed)
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("PRICE RULE")
            CatalogFieldLabel("Option")
            pickerContainer {
                Picker("Option", selection: $selectedOptionId) {
                    ForEach(options) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(OPSStyle.Colors.primaryText)
                .accessibilityLabel("Price rule option")
                .onChange(of: selectedOptionId) { _, _ in
                    selectedValueId = ""
                    triggerIntMin = ""
                    triggerIntMax = ""
                }
            }

            triggerControls

            CatalogFieldLabel("Modifier")
            Picker("Modifier", selection: $modifierKind) {
                ForEach(PricingModifierKind.allCases, id: \.self) { kind in
                    Text(labelForModifierKind(kind)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .tint(OPSStyle.Colors.text)
            .accessibilityLabel("Modifier kind")
            .accessibilityValue(labelForModifierKind(modifierKind))

            CatalogFieldLabel(modifierKind == .multiplyUnitPrice ? "Multiplier" : "Amount")
            TextField(modifierKind == .multiplyUnitPrice ? "1" : "0", text: $amountString)
                .keyboardType(.decimalPad)
                .textFieldStyle(CatalogTextFieldStyle())
        }
        .setupPanel()
    }

    @ViewBuilder
    private var triggerControls: some View {
        if let selectedOption {
            switch selectedOption.kind {
            case .select:
                CatalogFieldLabel("Value")
                pickerContainer {
                    Picker("Value", selection: $selectedValueId) {
                        Text("Pick value").tag("")
                        ForEach(valuesForSelectedOption) { value in
                            Text(value.value).tag(value.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(OPSStyle.Colors.primaryText)
                    .accessibilityLabel("Trigger value")
                }
            case .integer:
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        CatalogFieldLabel("Min")
                        TextField("", text: $triggerIntMin)
                            .keyboardType(.numberPad)
                            .textFieldStyle(CatalogTextFieldStyle())
                    }
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        CatalogFieldLabel("Max")
                        TextField("", text: $triggerIntMax)
                            .keyboardType(.numberPad)
                            .textFieldStyle(CatalogTextFieldStyle())
                    }
                }
            case .boolean:
                setupBanner(title: "BOOLEAN TRIGGER", message: "Rule fires when this option is true.")
            }
        } else {
            setupBanner(title: "NO OPTION", message: "Add an option before creating a price rule.", isError: true)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            CatalogSectionHeader("PREVIEW")
            Text(previewText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .setupPanel()
    }

    private var previewText: String {
        let draft = normalizedDraft()
        if let error = draft.error { return error }
        guard let value = draft.value else { return "Price rule ready." }
        let optionName = selectedOption?.name ?? "Option"
        let effect = effectClause(kind: value.modifierKind, amount: value.amount)
        if let triggerValueId = value.triggerValueId,
           let optionValue = optionValues.first(where: { $0.id == triggerValueId }) {
            return "When \(optionName) = \(optionValue.value) -> \(effect)"
        }
        if let min = value.triggerIntMin, let max = value.triggerIntMax {
            if min == max { return "When \(optionName) = \(min) -> \(effect)" }
            return "When \(optionName) is \(min)-\(max) -> \(effect)"
        }
        if let min = value.triggerIntMin { return "When \(optionName) >= \(min) -> \(effect)" }
        if let max = value.triggerIntMax { return "When \(optionName) <= \(max) -> \(effect)" }
        return "When \(optionName) is true -> \(effect)"
    }

    @MainActor
    private func save() async {
        guard canManageProductOptions else {
            blockUnauthorizedMutation()
            return
        }
        let draft = normalizedDraft()
        guard let value = draft.value else {
            errorMessage = draft.error
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let repo = ProductRichnessRepository(companyId: companyId)
            let dto: ProductPricingModifierDTO
            if let editingModifier {
                dto = try await repo.updatePricingModifier(
                    editingModifier.id,
                    fields: UpdateProductPricingModifierDTO(
                        optionId: value.optionId,
                        triggerValueId: value.triggerValueId,
                        triggerIntMin: value.triggerIntMin,
                        triggerIntMax: value.triggerIntMax,
                        modifierKind: value.modifierKind.rawValue,
                        amount: value.amount
                    )
                )
            } else {
                dto = try await repo.createPricingModifier(
                    CreateProductPricingModifierDTO(
                        productId: product.id,
                        optionId: value.optionId,
                        triggerValueId: value.triggerValueId,
                        triggerIntMin: value.triggerIntMin,
                        triggerIntMax: value.triggerIntMax,
                        modifierKind: value.modifierKind.rawValue,
                        amount: value.amount
                    )
                )
            }
            guard dto.productId == product.id,
                  dto.optionId == value.optionId
            else {
                throw ProductOptionAuthoringError.modifierParentMismatch
            }
            if let triggerValueId = dto.triggerValueId,
               optionValues.first(where: { $0.id == triggerValueId && $0.optionId == dto.optionId }) == nil {
                throw ProductOptionAuthoringError.valueParentMismatch
            }
            ProductOptionLocalStore.upsertModifier(dto, in: modelContext)
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ToastCenter.shared.present(Feedback.Catalog.priceRuleSaved)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    private func blockUnauthorizedMutation() {
        errorMessage = ProductOptionAuthoringError.missingManagePermission.localizedDescription
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func normalizedDraft() -> (value: ProductPricingModifierDraft?, error: String?) {
        guard let option = selectedOption else {
            return (nil, "Pick an option before saving.")
        }
        guard option.productId == product.id else {
            return (nil, "Selected option belongs to another product.")
        }
        guard let amount = Double(trimmed(amountString)) else {
            return (nil, "Amount must be a number.")
        }
        if modifierKind == .multiplyUnitPrice && amount <= 0 {
            return (nil, "Multiplier must be greater than zero.")
        }

        var triggerValueId: String?
        var minValue: Int?
        var maxValue: Int?

        switch option.kind {
        case .select:
            guard !selectedValueId.isEmpty,
                  optionValues.first(where: { $0.id == selectedValueId && $0.optionId == option.id }) != nil
            else {
                return (nil, "Pick a value that belongs to the selected option.")
            }
            triggerValueId = selectedValueId
        case .integer:
            if !trimmed(triggerIntMin).isEmpty {
                guard let parsed = Int(trimmed(triggerIntMin)) else {
                    return (nil, "Min must be a whole number.")
                }
                minValue = parsed
            }
            if !trimmed(triggerIntMax).isEmpty {
                guard let parsed = Int(trimmed(triggerIntMax)) else {
                    return (nil, "Max must be a whole number.")
                }
                maxValue = parsed
            }
            if minValue == nil && maxValue == nil {
                return (nil, "Integer rules need a min, max, or exact value.")
            }
            if let minValue, let maxValue, minValue > maxValue {
                return (nil, "Min cannot exceed max.")
            }
        case .boolean:
            break
        }

        return (
            ProductPricingModifierDraft(
                optionId: option.id,
                triggerValueId: triggerValueId,
                triggerIntMin: minValue,
                triggerIntMax: maxValue,
                modifierKind: modifierKind,
                amount: amount
            ),
            nil
        )
    }

    private func pickerContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    private func setupBanner(title: String, message: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(title)
                .font(OPSStyle.Typography.category)
                .foregroundColor(isError ? OPSStyle.Colors.errorText : OPSStyle.Colors.primaryText)
            Text(message)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(isError ? OPSStyle.Colors.errorText : OPSStyle.Colors.cardBorder,
                        lineWidth: OPSStyle.Layout.Border.standard)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }
}

private enum ProductOptionLocalStore {
    static func upsertOption(_ dto: ProductOptionDTO, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ProductOption>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.productId = dto.productId
            existing.name = dto.name
            existing.kind = ProductOptionKind(rawValue: dto.kind) ?? .select
            existing.affectsPrice = dto.affectsPrice
            existing.affectsRecipe = dto.affectsRecipe
            existing.required = dto.required
            existing.defaultValue = dto.defaultValue
            existing.optionDefaultSource = dto.optionDefaultSource
            existing.sortOrder = dto.sortOrder
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
    }

    static func upsertOptionValue(_ dto: ProductOptionValueDTO, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ProductOptionValue>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.optionId = dto.optionId
            existing.value = dto.value
            existing.sortOrder = dto.sortOrder
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
    }

    static func upsertModifier(_ dto: ProductPricingModifierDTO, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ProductPricingModifier>(predicate: #Predicate { $0.id == dto.id })
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            existing.productId = dto.productId
            existing.optionId = dto.optionId
            existing.triggerValueId = dto.triggerValueId
            existing.triggerIntMin = dto.triggerIntMin
            existing.triggerIntMax = dto.triggerIntMax
            existing.modifierKind = PricingModifierKind(rawValue: dto.modifierKind) ?? .addPerUnit
            existing.amount = dto.amount
            existing.lastSyncedAt = Date()
        } else {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            modelContext.insert(model)
        }
    }

    static func deleteOption(id: String, in modelContext: ModelContext) {
        let values = ((try? modelContext.fetch(FetchDescriptor<ProductOptionValue>())) ?? [])
            .filter { $0.optionId == id }
        let valueIds = Set(values.map(\.id))

        for modifier in ((try? modelContext.fetch(FetchDescriptor<ProductPricingModifier>())) ?? []) {
            if modifier.optionId == id || modifier.triggerValueId.map({ valueIds.contains($0) }) == true {
                modelContext.delete(modifier)
            }
        }
        for mapping in ((try? modelContext.fetch(FetchDescriptor<CatalogProductOptionMapping>())) ?? []) {
            if mapping.productOptionId == id || mapping.productOptionValueId.map({ valueIds.contains($0) }) == true {
                modelContext.delete(mapping)
            }
        }
        for value in values {
            modelContext.delete(value)
        }

        let descriptor = FetchDescriptor<ProductOption>(predicate: #Predicate { $0.id == id })
        if let option = (try? modelContext.fetch(descriptor))?.first {
            modelContext.delete(option)
        }
    }

    static func deleteOptionValue(id: String, in modelContext: ModelContext) {
        for modifier in ((try? modelContext.fetch(FetchDescriptor<ProductPricingModifier>())) ?? []) where modifier.triggerValueId == id {
            modelContext.delete(modifier)
        }
        for mapping in ((try? modelContext.fetch(FetchDescriptor<CatalogProductOptionMapping>())) ?? []) where mapping.productOptionValueId == id {
            modelContext.delete(mapping)
        }

        let descriptor = FetchDescriptor<ProductOptionValue>(predicate: #Predicate { $0.id == id })
        if let value = (try? modelContext.fetch(descriptor))?.first {
            modelContext.delete(value)
        }
    }

    static func deleteModifier(id: String, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ProductPricingModifier>(predicate: #Predicate { $0.id == id })
        if let modifier = (try? modelContext.fetch(descriptor))?.first {
            modelContext.delete(modifier)
        }
    }
}

private struct ProductOptionEditorRequest: Identifiable {
    let id: String = UUID().uuidString
    let option: ProductOption?
}

private struct ProductPricingModifierEditorRequest: Identifiable {
    let id: String = UUID().uuidString
    let modifier: ProductPricingModifier?
}

private struct ProductOptionValueDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var serverId: String?
    var value: String
    var sortOrder: Int = 0
}

private struct ProductPricingModifierDraft {
    var optionId: String
    var triggerValueId: String?
    var triggerIntMin: Int?
    var triggerIntMax: Int?
    var modifierKind: PricingModifierKind
    var amount: Double
}

private enum ProductOptionAuthoringError: LocalizedError {
    case missingManagePermission
    case valueParentMismatch
    case modifierParentMismatch

    var errorDescription: String? {
        switch self {
        case .missingManagePermission:
            return "Product option changes require catalog.products.manage."
        case .valueParentMismatch:
            return "Option value parent validation failed."
        case .modifierParentMismatch:
            return "Pricing modifier parent validation failed."
        }
    }
}

private func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func trimmedOptional(_ value: String) -> String? {
    let next = trimmed(value)
    return next.isEmpty ? nil : next
}

private func normalized(_ value: String) -> String {
    trimmed(value).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
}

private func labelForKind(_ kind: ProductOptionKind) -> String {
    switch kind {
    case .select: return "SELECT"
    case .integer: return "INTEGER"
    case .boolean: return "BOOLEAN"
    }
}

private func labelForModifierKind(_ kind: PricingModifierKind) -> String {
    switch kind {
    case .addPerUnit: return "ADD PER UNIT"
    case .addFlat: return "ADD FLAT"
    case .addPerCount: return "ADD PER COUNT"
    case .multiplyUnitPrice: return "MULTIPLY UNIT"
    }
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

private func formatMoney(_ amount: Double) -> String {
    let sign = amount >= 0 ? "+" : "-"
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 0
    let absString = formatter.string(from: NSNumber(value: abs(amount))) ?? "$0"
    return "\(sign)\(absString)"
}

private func formatNumber(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 3
    return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
}

private func formatPlainNumber(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 3
    return formatter.string(from: NSNumber(value: amount)) ?? String(amount)
}

private func effectClause(kind: PricingModifierKind, amount: Double) -> String {
    switch kind {
    case .addPerUnit:
        return "\(formatMoney(amount)) per unit"
    case .addFlat:
        return "\(formatMoney(amount)) flat"
    case .addPerCount:
        return "\(formatMoney(amount)) per count"
    case .multiplyUnitPrice:
        return "\(formatNumber(amount))x unit price"
    }
}

private extension View {
    func setupPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}
