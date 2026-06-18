//
//  AddAssemblyLaborSheet.swift
//  OPS
//
//  Add one labor line to an assembly: name, the unit it's priced in (per hour by
//  default, or piecework per ft / sq ft / each), a sell rate, your cost, and the
//  quantity per job. Returns a draft to the assembly builder; the labor service
//  is created on commit. Cost + margin hide when the operator isn't tracking cost.
//

import SwiftUI
import SwiftData

struct AddAssemblyLaborSheet: View {
    let companyId: String
    let trackCost: Bool
    let onAdd: (AssemblyLaborDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var allUnits: [CatalogUnit]

    @State private var draft = AssemblyLaborDraft()
    @State private var showingUnitCreate = false
    @FocusState private var nameFocused: Bool

    private var companyUnits: [CatalogUnit] {
        allUnits
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.display) < ($1.sortOrder, $1.display) }
    }

    private var selectedUnit: CatalogUnit? { companyUnits.first { $0.id == draft.unitId } }
    /// "hr" / "ft" / "sq ft" — drives the rate-field labels. Defaults to "hr".
    private var unitSuffix: String { selectedUnit?.display.lowercased() ?? "hr" }
    /// "Hours per job" when hourly; "Qty per job (ft)" otherwise.
    private var qtyLabel: String {
        guard let u = selectedUnit, u.dimension != "time" else { return "Hours per job" }
        return "Qty per job (\(u.display.lowercased()))"
    }

    private func isNumber(_ raw: String) -> Bool {
        let cleaned = raw.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) != nil
    }

    private func isBlank(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var marginPercent: Double? {
        let s = draft.sellText.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        let c = draft.costText.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let sell = Double(s), sell > 0, let cost = Double(c) else { return nil }
        return ((sell - cost) / sell) * 100
    }

    private var canAdd: Bool {
        // Name + quantity required; sell + cost optional (cost hidden when not tracking).
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isNumber(draft.hoursText)
            && (isBlank(draft.sellText) || isNumber(draft.sellText))
            && (isBlank(draft.costText) || isNumber(draft.costText))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("// LABOR")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("ADD LABOR")
                            .font(OPSStyle.Typography.pageTitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        CatalogFieldLabel("Name")
                        TextField("e.g. Rail install labor", text: $draft.name)
                            .textFieldStyle(CatalogTextFieldStyle())
                            .focused($nameFocused)

                        CatalogFieldLabel("Unit")
                        UnitPickerField(
                            selectedUnitId: $draft.unitId,
                            companyUnits: companyUnits,
                            canCreateNew: true,
                            onCreateRequested: { showingUnitCreate = true },
                            allowFlatRate: false
                        )

                        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                CatalogFieldLabel("Sell / \(unitSuffix)")
                                TextField("0", text: $draft.sellText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(CatalogTextFieldStyle())
                            }
                            if trackCost {
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                    CatalogFieldLabel("Your cost / \(unitSuffix)")
                                    TextField("0", text: $draft.costText)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(CatalogTextFieldStyle())
                                }
                            }
                        }

                        if trackCost, let margin = marginPercent {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Text("// MARGIN")
                                    .font(OPSStyle.Typography.metadata)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                Spacer()
                                Text("\(Int(margin.rounded()))%")
                                    .font(OPSStyle.Typography.metadata)
                                    .monospacedDigit()
                                    .foregroundColor(margin >= 0 ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.errorText)
                            }
                        }

                        CatalogFieldLabel(qtyLabel)
                        TextField("1", text: $draft.hoursText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(CatalogTextFieldStyle())
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
            if draft.unitId == nil {
                draft.unitId = companyUnits.first { $0.dimension == "time" && $0.display.lowercased() == "hr" }?.id
                    ?? companyUnits.first { $0.dimension == "time" }?.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { nameFocused = true }
        }
    }
}
