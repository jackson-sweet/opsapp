//
//  AutoApproveRuleSheet.swift
//  OPS
//
//  Sheet for creating auto-approve rules — threshold-based automatic approval
//  for invoices or individual line items, optionally scoped to specific members.
//

import SwiftUI

struct AutoApproveRuleSheet: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: AutoApproveRuleType = .lineItem
    @State private var thresholdText: String = ""
    @State private var appliesToAll: Bool = true
    @State private var selectedMemberIds: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // RULE TYPE
                        sectionHeader("RULE TYPE")
                            .padding(.top, OPSStyle.Layout.spacing3)
                        ruleTypeCards

                        // THRESHOLD AMOUNT
                        sectionHeader("THRESHOLD AMOUNT")
                        thresholdCard

                        // ASSIGN TO
                        sectionHeader("ASSIGN TO")
                        assignToCard
                    }
                    .padding(.bottom, OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle("ADD AUTO-APPROVE RULE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("SAVE") {
                        Task { await saveRule() }
                    }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(thresholdText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Rule Type Cards

    private var ruleTypeCards: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            ruleTypeOption(
                type: .invoice,
                title: "INVOICE",
                subtitle: "Auto-approve entire invoices under threshold"
            )
            ruleTypeOption(
                type: .lineItem,
                title: "LINE ITEM",
                subtitle: "Auto-approve individual expenses under threshold"
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func ruleTypeOption(type: AutoApproveRuleType, title: String, subtitle: String) -> some View {
        Button {
            selectedType = type
        } label: {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(
                        selectedType == type
                        ? OPSStyle.Colors.primaryText
                        : OPSStyle.Colors.secondaryText
                    )
                Text(subtitle)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(OPSStyle.Layout.spacing3)
            .nestedCard()
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                    .stroke(
                        selectedType == type
                        ? OPSStyle.Colors.text
                        : Color.clear,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Threshold Card

    private var thresholdCard: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("$")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField("0.00", text: $thresholdText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(.decimalPad)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.surfaceInput)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Assign To Card

    private var assignToCard: some View {
        VStack(spacing: 0) {
            // ALL MEMBERS toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ALL MEMBERS")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                Spacer()
                Toggle("", isOn: $appliesToAll)
                    .labelsHidden()
                    .tint(OPSStyle.Colors.text)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)

            // Individual member selection placeholder
            if !appliesToAll {
                Divider().background(OPSStyle.Colors.line)

                Text("Select individual crew members below")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
            }
        }
        .glassSurface()
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Save

    private func saveRule() async {
        let trimmed = thresholdText.trimmingCharacters(in: .whitespaces)
        guard let threshold = Double(trimmed), threshold > 0 else { return }
        let createdBy = dataController.currentUser?.id ?? ""
        await viewModel.createAutoApproveRule(
            ruleType: selectedType,
            threshold: threshold,
            appliesToAll: appliesToAll,
            memberIds: Array(selectedMemberIds),
            createdBy: createdBy
        )
        dismiss()
    }
}
