//
//  LineItemEditSheet.swift
//  OPS
//
//  Bottom sheet for editing or creating a line item on an estimate.
//  Adapts to selected Product richness — flat products show the basic form,
//  configurable products surface inline option controls + live unit-price
//  preview. Snapshot is persisted on save.
//
//  Count options (end posts, corners) open blank and stay blank until the
//  operator enters a number; a required option left blank stops the save and
//  is named. The rules live in `LineItemConfigurationForm`.
//

import SwiftUI
import SwiftData

struct LineItemEditSheet: View {
    let estimateId: String
    @ObservedObject var viewModel: EstimateViewModel
    var editing: EstimateLineItem? = nil
    var product: Product? = nil

    @Environment(\.dismiss) private var dismiss

    /// The line's own product when the sheet opens an existing line. The
    /// estimate form hands no product in for an edit, so without this an
    /// existing configurable line would open with no options at all — and a
    /// count it never carried could not be entered on the phone.
    @Query private var linkedProducts: [Product]
    @Query private var allOptions: [ProductOption]
    @Query private var allOptionValues: [ProductOptionValue]
    @Query private var allModifiers: [ProductPricingModifier]

    @State private var description = ""
    @State private var type: LineItemType = .labor
    @State private var quantity = "1"
    @State private var unit = ""
    @State private var unitPrice = ""
    @State private var isOptional = false
    @State private var isTaxable = true
    @State private var isSaving = false
    @State private var productId: String? = nil
    @State private var configuredOptions: [String: ProductConfigurationResolver.OptionValue] = [:]
    @State private var didHydrate = false
    /// Set by a save refused for blank required options. The prompt then
    /// tracks the line live and clears itself once every option is entered.
    @State private var showsMissingOptions = false

    private let resolver = ProductConfigurationResolver()
    private static let saveButtonScrollId = "line_item_save_button"

    init(
        estimateId: String,
        viewModel: EstimateViewModel,
        editing: EstimateLineItem? = nil,
        product: Product? = nil
    ) {
        self.estimateId = estimateId
        self.viewModel = viewModel
        self.editing = editing
        self.product = product
        let linkedProductId = product?.id ?? editing?.productId ?? ""
        _linkedProducts = Query(filter: #Predicate<Product> { $0.id == linkedProductId })
    }

    private var resolvedProduct: Product? {
        product ?? linkedProducts.first
    }

    private var productOptions: [ProductOption] {
        guard let p = resolvedProduct else { return [] }
        return LineItemConfigurationForm.displayOrder(allOptions.filter { $0.productId == p.id })
    }

    private var productOptionValues: [ProductOptionValue] {
        let optionIds = Set(productOptions.map(\.id))
        return allOptionValues.filter { optionIds.contains($0.optionId) }
    }

    private var productModifiers: [ProductPricingModifier] {
        guard let p = resolvedProduct else { return [] }
        return allModifiers.filter { $0.productId == p.id }
    }

    private var resolution: ProductConfigurationResolver.Resolution? {
        guard let p = resolvedProduct, !productOptions.isEmpty else { return nil }
        return resolver.resolve(
            product: p,
            options: productOptions,
            optionValues: productOptionValues,
            modifiers: productModifiers,
            configured: configuredOptions
        )
    }

    private var lineTotal: Double {
        if let res = resolution, let qty = Double(quantity) {
            return res.unitPrice * qty
        }
        let qty = Double(quantity) ?? 0
        let price = Double(unitPrice) ?? 0
        return qty * price
    }

    private var isValid: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Double(quantity) ?? 0) > 0 &&
        (resolution != nil || (Double(unitPrice) ?? 0) >= 0)
    }

    /// Required options with no usable value, in display order. Empty for a
    /// flat product.
    private var missingOptions: [ProductOption] {
        LineItemConfigurationForm.missingRequiredOptions(
            options: productOptions,
            optionValues: productOptionValues,
            configured: configuredOptions
        )
    }

    private var visibleMissingOptionIds: Set<String> {
        showsMissingOptions ? Set(missingOptions.map(\.id)) : []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    sectionHeader("DESCRIPTION")
                    TextField("Line item name", text: $description)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    sectionHeader("TYPE")
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        ForEach(LineItemType.allCases, id: \.self) { t in
                            Button(action: { type = t }) {
                                Text(t.rawValue.uppercased())
                                    .font(OPSStyle.Typography.smallCaption)
                                    .fontWeight(.medium)
                                    .foregroundColor(
                                        type == t ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText
                                    )
                                    .padding(.horizontal, OPSStyle.Layout.spacing2 + 2)
                                    .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
                                    .background(
                                        type == t
                                        ? OPSStyle.Colors.surfaceActive
                                        : OPSStyle.Colors.surfaceInput
                                    )
                                    .cornerRadius(OPSStyle.Layout.chipRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                            .stroke(
                                                type == t ? OPSStyle.Colors.text : OPSStyle.Colors.cardBorder,
                                                lineWidth: OPSStyle.Layout.Border.standard
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    sectionHeader("QUANTITY & PRICE")
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            Text("QTY")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            TextField("1", text: $quantity)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.decimalPad)
                                .padding(OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.surfaceInput)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                        }

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            Text("UNIT")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            TextField("hr", text: $unit)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.surfaceInput)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                        }
                        .frame(width: 80)

                        if resolution == nil {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                Text("UNIT PRICE")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                TextField("$0", text: $unitPrice)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .keyboardType(.decimalPad)
                                    .padding(OPSStyle.Layout.spacing2)
                                    .background(OPSStyle.Colors.surfaceInput)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    if !productOptions.isEmpty, let p = resolvedProduct, let res = resolution {
                        configurationPanel(product: p, resolution: res)
                    }

                    VStack(spacing: 0) {
                        toggleRow("Optional?", isOn: $isOptional)
                        Divider().background(OPSStyle.Colors.separator)
                        toggleRow("Taxable?", isOn: $isTaxable)
                    }
                    .glassSurface()
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    HStack {
                        Text("LINE TOTAL")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Text(BooksFormat.currency(lineTotal))
                            .font(OPSStyle.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)

                    ScrollViewReader { scrollProxy in
                        VStack(spacing: OPSStyle.Layout.spacing3) {
                            if showsMissingOptions, !missingOptions.isEmpty {
                                missingOptionsPrompt(missingOptions)
                                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                                    .transition(.opacity)
                            }

                            Button(editing != nil ? "SAVE CHANGES" : "ADD LINE ITEM") { attemptSave(scrollProxy) }
                                .opsPrimaryButtonStyle()
                                .disabled(!isValid || isSaving)
                                .opacity(isValid ? 1 : 0.5)
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .id(Self.saveButtonScrollId)
                        }
                    }

                    if editing != nil {
                        Button("DELETE LINE ITEM") { deleteItem() }
                            .opsDestructiveButtonStyle()
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }
                }
                .padding(.top, OPSStyle.Layout.spacing3)
                .animation(OPSStyle.Animation.panel, value: showsMissingOptions && !missingOptions.isEmpty)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationTitle(editing != nil ? "EDIT LINE ITEM" : "NEW LINE ITEM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .onAppear {
                hydrateFromInputs()
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(OPSStyle.Layout.largeCornerRadius)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Configuration Panel

    @ViewBuilder
    private func configurationPanel(product: Product, resolution: ProductConfigurationResolver.Resolution) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// CONFIGURATION")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            ForEach(productOptions) { opt in
                optionRow(opt)
            }

            HStack {
                Text("// UNIT PRICE")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                Text("\(BooksFormat.exact(resolution.unitPrice)) / \(product.pricingUnit.rawValue)")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }

            if let qty = Double(quantity) {
                HStack {
                    Text("TOTAL")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer()
                    Text(BooksFormat.exact(resolution.unitPrice * qty))
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    @ViewBuilder
    private func optionRow(_ opt: ProductOption) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            // Rose names a blank required option once a save has been refused
            // for it — paired with the prompt that names it in words.
            Text(opt.name.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(
                    visibleMissingOptionIds.contains(opt.id)
                        ? OPSStyle.Colors.roseTextM
                        : OPSStyle.Colors.secondaryText
                )
                .frame(width: OPSStyle.Layout.optionRowLabelWidth, alignment: .leading)

            Spacer()

            switch opt.kind {
            case .select:
                selectControl(opt)
            case .integer:
                integerControl(opt)
            case .boolean:
                booleanControl(opt)
            }
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    @ViewBuilder
    private func selectControl(_ opt: ProductOption) -> some View {
        let values = LineItemConfigurationForm.sortedValues(for: opt, in: allOptionValues)
        let currentId: String? = {
            if case .selectId(let id) = configuredOptions[opt.id] { return id }
            return nil
        }()
        // Nothing chosen reads "—", never the catalogue default's text: the
        // line carries no value until one is picked.
        let currentValue = values.first { $0.id == currentId }?.value

        Menu {
            ForEach(values) { v in
                Button(v.value) {
                    configuredOptions[opt.id] = .selectId(v.id)
                }
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(currentValue ?? "—")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(currentValue == nil ? OPSStyle.Colors.text3 : OPSStyle.Colors.primaryText)
                Image(systemName: "chevron.down")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    /// A count: "—" until entered, then the number. Minus from blank enters 0
    /// and plus enters 1, so "none" is one tap and reads differently from
    /// "not entered". 0 is the floor — once a count is entered it never goes
    /// back to blank.
    ///
    /// The value is set at the card data size, a full step apart from the −/+
    /// pair, so a blank "—" can never be read as a third minus button. After a
    /// refused save a blank count's "—" turns rose with its label.
    @ViewBuilder
    private func integerControl(_ opt: ProductOption) -> some View {
        let count = LineItemConfigurationForm.count(in: configuredOptions, optionId: opt.id)
        HStack(spacing: OPSStyle.Layout.spacing3) {
            Text(count.map { "\($0)" } ?? "—")
                .font(OPSStyle.Typography.dataValueLg)
                .foregroundColor(
                    visibleMissingOptionIds.contains(opt.id)
                        ? OPSStyle.Colors.roseTextM
                        : (count == nil ? OPSStyle.Colors.text3 : OPSStyle.Colors.text)
                )
                .monospacedDigit()
                .frame(minWidth: OPSStyle.Layout.counterValueMinWidth, alignment: .trailing)
                .accessibilityLabel(count.map { "\($0)" } ?? "Not entered")
                .accessibilityIdentifier("line_item_count_\(opt.id)_value")

            OPSCounterStepper(
                label: opt.name,
                canDecrement: LineItemConfigurationForm.canDecrement(count),
                canIncrement: LineItemConfigurationForm.canIncrement(count),
                onDecrement: {
                    configuredOptions[opt.id] = .integer(LineItemConfigurationForm.decremented(count))
                },
                onIncrement: {
                    configuredOptions[opt.id] = .integer(LineItemConfigurationForm.incremented(count))
                },
                accessibilityIdentifierRoot: "line_item_count_\(opt.id)"
            )
        }
    }

    @ViewBuilder
    private func booleanControl(_ opt: ProductOption) -> some View {
        let current: Bool = {
            if case .boolean(let b) = configuredOptions[opt.id] { return b }
            return false
        }()
        Toggle("", isOn: Binding(
            get: { current },
            set: { configuredOptions[opt.id] = .boolean($0) }
        ))
        .tint(OPSStyle.Colors.text)
        .labelsHidden()
    }

    // MARK: - Components

    /// Shown above the save button after a save is refused: what is missing,
    /// by name. Same rose blocker panel the catalogue flows use.
    private func missingOptionsPrompt(_ missing: [ProductOption]) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(LineItemConfigurationForm.blockedTitle)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.roseTextM)
            Text(LineItemConfigurationForm.blockedMessage(for: missing))
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.roseTextM)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("line_item_missing_options_message")
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.roseFillM)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .stroke(OPSStyle.Colors.roseLineM, lineWidth: OPSStyle.Layout.Border.standard)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .tint(OPSStyle.Colors.text)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    // MARK: - Hydration

    private func hydrateFromInputs() {
        // onAppear can fire again (a menu or keyboard dismissing); hydrate
        // once so it never overwrites what the operator has entered.
        guard !didHydrate else { return }
        didHydrate = true

        if let item = editing {
            description = item.name
            type = item.type
            quantity = item.quantity.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(item.quantity))
                : String(format: "%.1f", item.quantity)
            unit = item.unit ?? ""
            unitPrice = String(format: "%.2f", item.resolvedUnitPrice ?? item.unitPrice)
            isOptional = item.optional
            isTaxable = item.taxable
            productId = item.productId
            configuredOptions = LineItemConfigurationForm.hydrated(
                snapshotJSON: item.configuredOptionsJSON,
                options: productOptions,
                optionValues: productOptionValues
            )
        } else if let p = resolvedProduct {
            description = p.name
            type = p.type
            unit = p.pricingUnit.rawValue
            productId = p.id
            unitPrice = String(format: "%.2f", p.basePrice)
            isTaxable = p.taxable
            configuredOptions = LineItemConfigurationForm.seeded(
                configuredOptions,
                options: productOptions,
                optionValues: productOptionValues
            )
        }
    }

    // MARK: - Actions

    /// The save button. A configurable line with a blank required option is
    /// refused here — named in the prompt, with a warning haptic and a
    /// VoiceOver announcement — and never reaches the server. The prompt opens
    /// directly above the button; the sheet scrolls so the button stays in
    /// view beneath it instead of being pushed out from under the thumb.
    private func attemptSave(_ scrollProxy: ScrollViewProxy) {
        let missing = missingOptions
        guard missing.isEmpty else {
            showsMissingOptions = true
            DispatchQueue.main.async {
                withAnimation(OPSStyle.Animation.panel) {
                    scrollProxy.scrollTo(Self.saveButtonScrollId, anchor: .bottom)
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            UIAccessibility.post(
                notification: .announcement,
                argument: LineItemConfigurationForm.blockedMessage(for: missing)
            )
            return
        }
        save()
    }

    private func save() {
        isSaving = true
        let generator = UINotificationFeedbackGenerator()
        Task {
            defer { isSaving = false }
            let res = resolution
            // A blank count has no key in the snapshot; an entered 0 is the
            // JSON number 0.
            let configuredJSON: String? = res == nil
                ? nil
                : LineItemConfigurationForm.snapshotJSON(configuredOptions)

            if let item = editing {
                let priceForUpdate: Double? = res?.unitPrice ?? Double(unitPrice)
                await viewModel.updateLineItem(
                    id: item.id,
                    estimateId: estimateId,
                    description: description,
                    quantity: Double(quantity),
                    unitPrice: priceForUpdate,
                    isOptional: isOptional,
                    configuredOptionsJSON: configuredJSON,
                    resolvedUnitPrice: res?.unitPrice,
                    resolvedOptionsLabel: res?.label
                )
            } else {
                let priceForCreate = res?.unitPrice ?? (Double(unitPrice) ?? 0)
                await viewModel.addLineItem(
                    estimateId: estimateId,
                    description: description,
                    type: type,
                    quantity: Double(quantity) ?? 1,
                    unitPrice: priceForCreate,
                    isOptional: isOptional,
                    productId: productId,
                    unit: unit.isEmpty ? nil : unit,
                    configuredOptionsJSON: configuredJSON,
                    resolvedUnitPrice: res?.unitPrice,
                    resolvedOptionsLabel: res?.label
                )
            }
            if viewModel.error == nil {
                await MainActor.run { generator.notificationOccurred(.success) }
                dismiss()
            }
        }
    }

    private func deleteItem() {
        guard let item = editing else { return }
        Task {
            await viewModel.deleteLineItem(id: item.id, estimateId: estimateId)
            if viewModel.error == nil { dismiss() }
        }
    }
}
