//
//  NewLinkedProductSheet.swift
//  OPS
//
//  Mini quick-add form for a new Product, pre-bound to a TaskType. Lives
//  inside TaskTypeSheet's LINKED PRODUCTS section. Three required fields
//  (name + price + unit) and the rest defaults to safe values — full
//  authoring still lives in QuickAddProductSheet / ProductDetailView /
//  web. The point is to keep the operator inside the task-type sheet so
//  they can wire up an end-to-end workflow without context-switching.
//

import SwiftUI
import SwiftData

struct NewLinkedProductSheet: View {
    /// Pre-bound parent. Both the legacy text column and the uuid FK are
    /// written with this value at create time.
    let taskTypeId: String
    let companyId: String

    /// Fires with the newly-saved product so the parent sheet can refresh
    /// its LINKED PRODUCTS list.
    let onSave: (Product) -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allUnits: [CatalogUnit]

    @State private var name: String = ""
    @State private var priceString: String = ""
    @State private var selectedUnitId: String? = nil
    @State private var isSaving: Bool = false
    @State private var priceParseError: Bool = false
    @State private var errorMessage: String? = nil

    @FocusState private var nameFieldFocused: Bool

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    private var selectedUnit: CatalogUnit? {
        guard let id = selectedUnitId else { return nil }
        return companyUnits.first(where: { $0.id == id })
    }

    private var canSave: Bool {
        if isSaving { return false }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if priceString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if Double(priceString.trimmingCharacters(in: .whitespacesAndNewlines)) == nil { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        nameField
                        priceRow
                        if let errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                        helperText
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
                .dismissKeyboardOnTap()
            }
            .navigationTitle("NEW LINKED PRODUCT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        } else {
                            Text("SAVE")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(canSave
                                                 ? OPSStyle.Colors.primaryAccent
                                                 : OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                nameFieldFocused = true
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("NAME")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField("e.g. Picket Rail Install", text: $name)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .focused($nameFieldFocused)
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    private var priceRow: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("PRICE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                TextField("0", text: $priceString)
                    .keyboardType(.decimalPad)
                    .font(OPSStyle.Typography.body)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(priceParseError
                                    ? OPSStyle.Colors.errorText
                                    : OPSStyle.Colors.cardBorder,
                                    lineWidth: OPSStyle.Layout.Border.standard)
                    )
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
                Text("UNIT")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                unitPicker
            }
        }
    }

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
        } label: {
            HStack(spacing: 8) {
                Text(selectedUnit?.display ?? "Flat rate")
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
    }

    private var helperText: some View {
        Text("This product will be created as a LABOR service and linked to this task type. Edit category, SKU, options on the catalog screen later.")
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @MainActor
    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrice = priceString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedPrice = Double(trimmedPrice) else {
            priceParseError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let unit = selectedUnit
        // `pricingUnit(for:)` lives in CatalogManageHelpers.swift; same helper
        // QuickAddProductSheet uses so the enum stays in lockstep with the
        // unit FK across both create paths.
        let pricingUnitRaw = pricingUnit(for: unit).rawValue

        let dto = CreateProductDTO(
            companyId: companyId,
            name: trimmedName,
            description: nil,
            basePrice: parsedPrice,
            unitCost: nil,
            unit: unit?.display,
            pricingUnit: pricingUnitRaw,
            unitId: unit?.id,
            category: nil,
            categoryId: nil,
            sku: nil,
            thumbnailUrl: nil,
            kind: ProductKind.service.rawValue,
            type: LineItemType.labor.rawValue,
            isTaxable: true,
            taskTypeId: taskTypeId,
            taskTypeRef: taskTypeId,
            linkedCatalogItemId: nil
        )

        let repo = ProductRepository(companyId: companyId)
        do {
            let created = try await repo.create(dto)
            let model = created.toModel()
            modelContext.insert(model)
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSave(model)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}
