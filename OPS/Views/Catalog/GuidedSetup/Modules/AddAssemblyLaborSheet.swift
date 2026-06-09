//
//  AddAssemblyLaborSheet.swift
//  OPS
//
//  Add one labor line to an assembly: name, sell rate, your cost, hours.
//  Returns a draft to the assembly builder; the labor service is created on commit.
//

import SwiftUI

struct AddAssemblyLaborSheet: View {
    let onAdd: (AssemblyLaborDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draft = AssemblyLaborDraft()
    @FocusState private var nameFocused: Bool

    private func isNumber(_ raw: String) -> Bool {
        let cleaned = raw.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) != nil
    }

    private var marginPercent: Double? {
        let s = draft.sellText.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        let c = draft.costText.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let sell = Double(s), sell > 0, let cost = Double(c) else { return nil }
        return ((sell - cost) / sell) * 100
    }

    private var canAdd: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isNumber(draft.costText) && isNumber(draft.hoursText)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

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

                        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                CatalogFieldLabel("Sell / hr")
                                TextField("0", text: $draft.sellText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(CatalogTextFieldStyle())
                            }
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                CatalogFieldLabel("Your cost / hr")
                                TextField("0", text: $draft.costText)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(CatalogTextFieldStyle())
                            }
                        }

                        if let margin = marginPercent {
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

                        CatalogFieldLabel("Hours per job")
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { nameFocused = true }
        }
    }
}
