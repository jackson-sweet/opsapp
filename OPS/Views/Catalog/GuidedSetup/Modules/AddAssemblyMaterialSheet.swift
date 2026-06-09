//
//  AddAssemblyMaterialSheet.swift
//  OPS
//
//  Add one material line to an assembly: name, your cost, quantity, unit.
//  Returns a draft to the assembly builder; the material is created on commit.
//

import SwiftUI
import SwiftData

struct AddAssemblyMaterialSheet: View {
    let companyId: String
    let onAdd: (AssemblyMaterialDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var allUnits: [CatalogUnit]

    @State private var draft = AssemblyMaterialDraft()
    @State private var showingUnitCreate = false
    @FocusState private var nameFocused: Bool

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    private func isNumber(_ raw: String) -> Bool {
        let cleaned = raw.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) != nil
    }

    private var canAdd: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isNumber(draft.costText) && isNumber(draft.qtyText)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("// MATERIAL")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("ADD A MATERIAL")
                            .font(OPSStyle.Typography.pageTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        CatalogFieldLabel("Name")
                        TextField("e.g. Top rail", text: $draft.name)
                            .textFieldStyle(CatalogTextFieldStyle())
                            .focused($nameFocused)

                        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                CatalogFieldLabel("Your cost")
                                TextField("0", text: $draft.costText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(CatalogTextFieldStyle())
                            }
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                CatalogFieldLabel("Qty per job")
                                TextField("1", text: $draft.qtyText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(CatalogTextFieldStyle())
                            }
                        }

                        CatalogFieldLabel("Unit")
                        UnitPickerField(
                            selectedUnitId: $draft.unitId,
                            companyUnits: companyUnits,
                            canCreateNew: true,
                            onCreateRequested: { showingUnitCreate = true },
                            allowFlatRate: false
                        )
                    }
                    .padding(OPSStyle.Layout.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nestedCard()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)

            OPSFloatingButtonBar {
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    Button { dismiss() } label: { Text("CANCEL") }
                        .opsSecondaryButtonStyle()
                    Button {
                        onAdd(draft)
                        dismiss()
                    } label: { Text("ADD") }
                        .opsPrimaryButtonStyle(isDisabled: !canAdd)
                        .disabled(!canAdd)
                }
            }
        }
        .sheet(isPresented: $showingUnitCreate) {
            InlineCreateUnitSheet(companyId: companyId) { draft.unitId = $0 }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { nameFocused = true }
        }
    }
}
