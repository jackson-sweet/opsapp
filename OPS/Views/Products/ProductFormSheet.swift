//
//  ProductFormSheet.swift
//  OPS
//
//  Bottom sheet for creating or editing a product/service in the catalog.
//

import SwiftUI

struct ProductFormSheet: View {
    var editing: Product? = nil
    var onSave: () async -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var productDescription = ""
    @State private var type: LineItemType = .labor
    @State private var defaultPrice = ""
    @State private var unitCost = ""
    @State private var unit = ""
    @State private var taxable = true
    @State private var isSaving = false
    @State private var error: String? = nil

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Double(defaultPrice) ?? 0) >= 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    // Name
                    sectionHeader("NAME")
                    TextField("Product or service name", text: $name)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Description
                    sectionHeader("DESCRIPTION")
                    TextField("Optional description...", text: $productDescription, axis: .vertical)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(3...6)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Type picker
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
                                                type == t ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.1),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Price + Unit Cost + Unit
                    sectionHeader("PRICING")
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DEFAULT PRICE")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            TextField("$0", text: $defaultPrice)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.decimalPad)
                                .padding(OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("UNIT COST")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            TextField("$0", text: $unitCost)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.decimalPad)
                                .padding(OPSStyle.Layout.spacing2)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .frame(width: 80)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Taxable toggle
                    VStack(spacing: 0) {
                        Toggle(isOn: $taxable) {
                            Text("Taxable?")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .tint(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                    // Save button
                    Button(editing != nil ? "SAVE CHANGES" : "ADD PRODUCT") { save() }
                        .opsPrimaryButtonStyle()
                        .disabled(!isValid || isSaving)
                        .opacity(isValid ? 1 : 0.5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationTitle(editing != nil ? "EDIT PRODUCT" : "NEW PRODUCT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .onAppear {
                if let prod = editing {
                    name = prod.name
                    productDescription = prod.productDescription ?? ""
                    type = prod.type
                    defaultPrice = String(format: "%.2f", prod.defaultPrice)
                    unitCost = prod.unitCost.map { String(format: "%.2f", $0) } ?? ""
                    unit = prod.unit ?? ""
                    taxable = prod.taxable
                }
            }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(OPSStyle.Layout.largeCornerRadius)
        .presentationDragIndicator(.visible)
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

    // MARK: - Actions

    private func save() {
        guard let companyId = dataController.currentUser?.companyId else { return }
        let repo = ProductRepository(companyId: companyId)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if let prod = editing {
                    let dto = UpdateProductDTO(
                        name: name,
                        description: productDescription.isEmpty ? nil : productDescription,
                        unitPrice: Double(defaultPrice),
                        costPrice: Double(unitCost),
                        unit: unit.isEmpty ? nil : unit,
                        type: type.rawValue
                    )
                    _ = try await repo.update(prod.id, fields: dto)
                } else {
                    let dto = CreateProductDTO(
                        companyId: companyId,
                        name: name,
                        description: productDescription.isEmpty ? nil : productDescription,
                        unitPrice: Double(defaultPrice) ?? 0,
                        costPrice: Double(unitCost),
                        unit: unit.isEmpty ? nil : unit,
                        type: type.rawValue
                    )
                    _ = try await repo.create(dto)
                }
                await onSave()
                if self.error == nil { dismiss() }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
