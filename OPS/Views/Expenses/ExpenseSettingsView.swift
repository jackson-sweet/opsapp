//
//  ExpenseSettingsView.swift
//  OPS
//
//  Company-level expense settings — review frequency, thresholds,
//  policy toggles, auto-approve rules, and category management.
//

import SwiftUI

struct ExpenseSettingsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @State private var reviewFrequency: ReviewFrequency = .weekly
    @State private var autoApproveThreshold = ""
    @State private var adminApprovalThreshold = ""
    @State private var requireReceiptPhoto = true
    @State private var requireProjectAssignment = false
    @State private var isSaving = false
    @State private var showAddRuleSheet = false
    @State private var hasChanges = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Expense Settings",
                    onBackTapped: {
                        if hasChanges { Task { await saveSettings() } }
                        dismiss()
                    }
                )

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {

                        // CATEGORIES (navigation link)
                        categoriesLink
                            .padding(.top, OPSStyle.Layout.spacing3)

                        // REVIEW SCHEDULE
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            sectionHeader("REVIEW SCHEDULE")
                            reviewFrequencyRow
                        }

                        // THRESHOLDS
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            sectionHeader("APPROVAL THRESHOLDS")
                            thresholdsCard
                        }

                        // SUBMISSION POLICY
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            sectionHeader("SUBMISSION POLICY")
                            policyCard
                        }

                        // AUTO-APPROVE RULES
                        autoApproveRulesSection

                    }
                    .padding(.bottom, OPSStyle.Layout.spacing5)
                }
            }
        }
        .trackScreen("Settings.Expenses")
        .navigationBarBackButtonHidden(true)
        .task {
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                viewModel.setup(companyId: companyId)
                await viewModel.loadSettings()
                await viewModel.loadAutoApproveRules()
                await viewModel.loadCategories()
                populateFromSettings()
            }
        }
        .sheet(isPresented: $showAddRuleSheet) {
            AutoApproveRuleSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - Categories Link

    private var categoriesLink: some View {
        NavigationLink(destination: ExpenseCategorySettingsView(viewModel: viewModel).environmentObject(dataController)) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: "tag.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: OPSStyle.Layout.IconSize.lg)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Expense Categories")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("\(viewModel.categories.count) categories")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                Image(OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Review Frequency Row

    private var reviewFrequencyRow: some View {
        HStack {
            Text("Review Period")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            Menu {
                ForEach(ReviewFrequency.allCases, id: \.self) { freq in
                    Button {
                        reviewFrequency = freq
                        hasChanges = true
                    } label: {
                        HStack {
                            Text(freq.displayName)
                            if reviewFrequency == freq {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(reviewFrequency.displayName)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    Image(OPSStyle.Icons.chevronDown)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
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
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Thresholds Card

    private var thresholdsCard: some View {
        VStack(spacing: 0) {
            // Auto-approve threshold
            thresholdRow(
                label: "Auto-Approve Under",
                hint: "Expenses below this are automatically approved",
                text: $autoApproveThreshold
            )

            Divider().background(OPSStyle.Colors.cardBorder)

            // Admin approval threshold
            thresholdRow(
                label: "Admin Approval Over",
                hint: "Expenses above this require admin sign-off",
                text: $adminApprovalThreshold
            )
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func thresholdRow(label: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack {
                Text(label)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer()
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text("$")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    TextField("0", text: text)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                        .onChange(of: text.wrappedValue) { _, _ in hasChanges = true }
                }
            }
            Text(hint)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }

    // MARK: - Policy Card

    private var policyCard: some View {
        VStack(spacing: 0) {
            policyToggle(
                title: "Require Receipt Photo",
                hint: "Crew must attach a receipt image",
                isOn: $requireReceiptPhoto
            )

            Divider().background(OPSStyle.Colors.cardBorder)

            policyToggle(
                title: "Require Project Assignment",
                hint: "Expenses must be assigned to a project",
                isOn: $requireProjectAssignment
            )
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func policyToggle(title: String, hint: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(hint)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue },
                set: { newValue in
                    isOn.wrappedValue = newValue
                    hasChanges = true
                }
            ))
            .labelsHidden()
            .tint(OPSStyle.Colors.primaryAccent)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }

    // MARK: - Auto-Approve Rules Section

    private var autoApproveRulesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader("AUTO-APPROVE RULES")

            if viewModel.autoApproveRules.isEmpty {
                // Empty state
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("No auto-approve rules configured.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    addRuleButton
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OPSStyle.Layout.spacing3)
            } else {
                ForEach(viewModel.autoApproveRules, id: \.id) { rule in
                    autoApproveRuleRow(rule)
                }
                addRuleButton
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func autoApproveRuleRow(_ rule: AutoApproveRuleDTO) -> some View {
        let pillColor = rule.ruleType == "invoice" ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.warningStatus
        let typeLabel = AutoApproveRuleType(rawValue: rule.ruleType)?.displayName ?? rule.ruleType.uppercased()
        let memberLabel = rule.appliesToAll ? "All members" : "\(rule.members?.count ?? 0) members"

        return HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text(typeLabel)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.buttonText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                        .fill(pillColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Under \(formatRuleCurrency(rule.thresholdAmount))")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text(memberLabel)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isActive },
                set: { newValue in
                    Task { await viewModel.toggleAutoApproveRule(rule.id, isActive: newValue) }
                }
            ))
            .labelsHidden()
            .tint(OPSStyle.Colors.successStatus)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var addRuleButton: some View {
        Button {
            showAddRuleSheet = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(OPSStyle.Icons.plus)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                Text("ADD RULE")
                    .font(OPSStyle.Typography.captionBold)
            }
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Helpers

    private func formatRuleCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    // MARK: - Data

    private func populateFromSettings() {
        guard let s = viewModel.settings else { return }
        reviewFrequency = ReviewFrequency(rawValue: s.reviewFrequency ?? "") ?? .weekly
        autoApproveThreshold = s.autoApproveThreshold.map { String(format: "%.0f", $0) } ?? ""
        adminApprovalThreshold = s.adminApprovalThreshold.map { String(format: "%.0f", $0) } ?? ""
        requireReceiptPhoto = s.requireReceiptPhoto ?? true
        requireProjectAssignment = s.requireProjectAssignment ?? false
        hasChanges = false
    }

    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }
        let companyId = dataController.currentUser?.companyId ?? ""
        let dto = ExpenseSettingsDTO(
            companyId: companyId,
            reviewFrequency: reviewFrequency.rawValue,
            autoApproveThreshold: Double(autoApproveThreshold),
            adminApprovalThreshold: Double(adminApprovalThreshold),
            requireReceiptPhoto: requireReceiptPhoto,
            requireProjectAssignment: requireProjectAssignment
        )
        await viewModel.saveSettings(dto)
        hasChanges = false
    }
}
