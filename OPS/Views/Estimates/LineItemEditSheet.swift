//
//  LineItemEditSheet.swift
//  OPS
//
//  Bottom sheet for editing or creating a line item on an estimate.
//  Adapts to selected Product richness — flat products show the basic form,
//  configurable products surface inline option controls + live unit-price
//  preview. Snapshot is persisted on save.
//

import SwiftUI
import SwiftData

struct LineItemEditSheet: View {
    let estimateId: String
    @ObservedObject var viewModel: EstimateViewModel
    var editing: EstimateLineItem? = nil
    var product: Product? = nil

    @Environment(\.dismiss) private var dismiss

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

    private let resolver = ProductConfigurationResolver()

    private var productOptions: [ProductOption] {
        guard let p = product else { return [] }
        return allOptions
            .filter { $0.productId == p.id }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private var productOptionValues: [ProductOptionValue] {
        let optionIds = Set(productOptions.map(\.id))
        return allOptionValues.filter { optionIds.contains($0.optionId) }
    }

    private var productModifiers: [ProductPricingModifier] {
        guard let p = product else { return [] }
        return allModifiers.filter { $0.productId == p.id }
    }

    private var resolution: ProductConfigurationResolver.Resolution? {
        guard let p = product, !productOptions.isEmpty else { return nil }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    sectionHeader("DESCRIPTION")
                    TextField("Line item name", text: $description)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
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
                                        ? OPSStyle.Colors.primaryAccent.opacity(0.2)
                                        : OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
                                    )
                                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                            .stroke(
                                                type == t ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder,
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text("QTY")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            TextField("1", text: $quantity)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.decimalPad)
                                .padding(OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("UNIT")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            TextField("hr", text: $unit)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .padding(OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                        }
                        .frame(width: 80)

                        if resolution == nil {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("UNIT PRICE")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                TextField("$0", text: $unitPrice)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .keyboardType(.decimalPad)
                                    .padding(OPSStyle.Layout.spacing2)
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    if !productOptions.isEmpty, let p = product, let res = resolution {
                        configurationPanel(product: p, resolution: res)
                    }

                    VStack(spacing: 0) {
                        toggleRow("Optional?", isOn: $isOptional)
                        Divider().background(OPSStyle.Colors.cardBorder)
                        toggleRow("Taxable?", isOn: $isTaxable)
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    HStack {
                        Text("LINE TOTAL")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Spacer()
                        Text(lineTotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(OPSStyle.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)

                    Button(editing != nil ? "SAVE CHANGES" : "ADD LINE ITEM") { save() }
                        .opsPrimaryButtonStyle()
                        .disabled(!isValid || isSaving)
                        .opacity(isValid ? 1 : 0.5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    if editing != nil {
                        Button("DELETE LINE ITEM") { deleteItem() }
                            .opsDestructiveButtonStyle()
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }
                }
                .padding(.top, OPSStyle.Layout.spacing3)
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
                Text(String(format: "$%.2f / %@", resolution.unitPrice, product.pricingUnit.rawValue))
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }

            if let qty = Double(quantity) {
                HStack {
                    Text("TOTAL")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer()
                    Text(String(format: "$%.2f", resolution.unitPrice * qty))
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    @ViewBuilder
    private func optionRow(_ opt: ProductOption) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(opt.name.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 110, alignment: .leading)

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
        let values = allOptionValues
            .filter { $0.optionId == opt.id }
            .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
        let currentId: String? = {
            if case .selectId(let id) = configuredOptions[opt.id] { return id }
            return nil
        }()
        let currentLabel = values.first { $0.id == currentId }?.value ?? (opt.defaultValue ?? "—")

        Menu {
            ForEach(values) { v in
                Button(v.value) {
                    configuredOptions[opt.id] = .selectId(v.id)
                }
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(currentLabel)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Image(OPSStyle.Icons.chevronDown)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    @ViewBuilder
    private func integerControl(_ opt: ProductOption) -> some View {
        let current: Int = {
            if case .integer(let n) = configuredOptions[opt.id] { return n }
            return 0
        }()
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                let next = max(0, current - 1)
                configuredOptions[opt.id] = .integer(next)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 36, height: 36)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Text("\(current)")
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(minWidth: 36)

            Button {
                let next = min(999, current + 1)
                configuredOptions[opt.id] = .integer(next)
            } label: {
                Image(OPSStyle.Icons.plus)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 36, height: 36)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .buttonStyle(PlainButtonStyle())
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
        .tint(OPSStyle.Colors.primaryAccent)
        .labelsHidden()
    }

    // MARK: - Components

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
        .tint(OPSStyle.Colors.primaryAccent)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
    }

    // MARK: - Hydration

    private func hydrateFromInputs() {
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
            if let json = item.configuredOptionsJSON {
                configuredOptions = decodeConfiguredOptions(json)
            }
        } else if let p = product {
            description = p.name
            type = p.type
            unit = p.pricingUnit.rawValue
            productId = p.id
            unitPrice = String(format: "%.2f", p.basePrice)
            isTaxable = p.taxable
            seedDefaultsForOptions()
        }
    }

    private func seedDefaultsForOptions() {
        for opt in productOptions {
            if configuredOptions[opt.id] != nil { continue }
            switch opt.kind {
            case .select:
                let values = allOptionValues
                    .filter { $0.optionId == opt.id }
                    .sorted { ($0.sortOrder, $0.value) < ($1.sortOrder, $1.value) }
                let match = values.first { $0.value == opt.defaultValue } ?? values.first
                if let m = match { configuredOptions[opt.id] = .selectId(m.id) }
            case .integer:
                let n = Int(opt.defaultValue ?? "0") ?? 0
                configuredOptions[opt.id] = .integer(n)
            case .boolean:
                let b = (opt.defaultValue ?? "false").lowercased() == "true"
                configuredOptions[opt.id] = .boolean(b)
            }
        }
    }

    private func decodeConfiguredOptions(_ json: String) -> [String: ProductConfigurationResolver.OptionValue] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var result: [String: ProductConfigurationResolver.OptionValue] = [:]
        for (key, value) in raw {
            if let s = value as? String {
                result[key] = .selectId(s)
            } else if let n = value as? Int {
                result[key] = .integer(n)
            } else if let b = value as? Bool {
                result[key] = .boolean(b)
            } else if let d = value as? Double {
                result[key] = .integer(Int(d))
            }
        }
        return result
    }

    // MARK: - Actions

    private func save() {
        isSaving = true
        let generator = UINotificationFeedbackGenerator()
        Task {
            defer { isSaving = false }
            let res = resolution
            let configuredJSON: String? = {
                guard let res = res else { return nil }
                guard let data = try? JSONEncoder().encode(res.serializedOptions),
                      let str = String(data: data, encoding: .utf8) else { return nil }
                return str
            }()

            if let item = editing {
                let priceForUpdate: Double? = res?.unitPrice ?? Double(unitPrice)
                await viewModel.updateLineItem(
                    id: item.id,
                    estimateId: estimateId,
                    description: description,
                    quantity: Double(quantity),
                    unitPrice: priceForUpdate,
                    isOptional: isOptional
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
