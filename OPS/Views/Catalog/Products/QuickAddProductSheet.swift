//
//  QuickAddProductSheet.swift
//  OPS
//
//  ≤ 8s product entry: name, price, unit + an Advanced disclosure for the
//  rare day-one fields. Inserts the returned ProductDTO into the local
//  SwiftData context so the new row shows up in CatalogProductsListView
//  before the next sync round.
//

import SwiftUI
import SwiftData

struct QuickAddProductSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Required core
    @State private var name: String = ""
    @State private var priceString: String = ""
    @State private var pricingUnit: ProductPricingUnit = .flatRate

    // Advanced (optional)
    @State private var showAdvanced: Bool = false
    @State private var productDescription: String = ""
    @State private var sku: String = ""
    @State private var category: String = ""
    @State private var unitCostString: String = ""
    @State private var lineItemType: LineItemType = .other
    @State private var kind: ProductKind = .service
    @State private var taxable: Bool = true

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var priceParseError: Bool = false
    @State private var unitCostParseError: Bool = false

    @FocusState private var nameFieldFocused: Bool

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
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
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        coreFields
                        advancedDisclosure
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                        saveButton
                    }
                    .padding(OPSStyle.Layout.spacing3)
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
                // the ≤ 8s entry budget hinges on no extra taps before input.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    nameFieldFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                    pricingUnitPicker
                }
            }
        }
    }

    private var pricingUnitPicker: some View {
        Picker("Unit", selection: $pricingUnit) {
            ForEach(ProductPricingUnit.allCases, id: \.self) { unit in
                Text(unitDisplay(unit)).tag(unit)
            }
        }
        .pickerStyle(.menu)
        .tint(OPSStyle.Colors.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func unitDisplay(_ unit: ProductPricingUnit) -> String {
        switch unit {
        case .flatRate:    return "Flat"
        case .each:        return "Each"
        case .linearFoot:  return "Per ft"
        case .sqft:        return "Per sqft"
        case .hour:        return "Per hour"
        case .day:         return "Per day"
        }
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
                        CatalogFieldLabel("Category")
                        TextField("Optional", text: $category)
                            .textFieldStyle(CatalogTextFieldStyle())
                    }
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
                        Text("Unit cost must be a number")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.errorText)
                    }
                }

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

    // MARK: - Save

    private var saveButton: some View {
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
        .padding(.top, OPSStyle.Layout.spacing2)
    }

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

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedDescription = productDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSku = sku.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedUnitCost = trimmedUnitCost.isEmpty ? nil : Double(trimmedUnitCost)

        let dto = CreateProductDTO(
            companyId: companyId,
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            basePrice: parsedPrice,
            unitCost: parsedUnitCost,
            unit: nil,
            pricingUnit: pricingUnit.rawValue,
            category: trimmedCategory.isEmpty ? nil : trimmedCategory,
            sku: trimmedSku.isEmpty ? nil : trimmedSku,
            kind: kind.rawValue,
            type: lineItemType.rawValue,
            isTaxable: taxable,
            taskTypeId: nil
        )

        let repo = ProductRepository(companyId: companyId)
        do {
            let createdDTO = try await repo.create(dto)
            applyCreatedDTO(createdDTO)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    private func applyCreatedDTO(_ dto: ProductDTO) {
        let model = dto.toModel()
        modelContext.insert(model)
        try? modelContext.save()
    }
}
