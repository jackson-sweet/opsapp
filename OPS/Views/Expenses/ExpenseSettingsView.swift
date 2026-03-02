//
//  ExpenseSettingsView.swift
//  OPS
//
//  Company-level expense settings — review frequency, thresholds, and policy toggles.
//

import SwiftUI

struct ExpenseSettingsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var dataController: DataController
    @State private var reviewFrequency: ReviewFrequency = .weekly
    @State private var autoApproveThreshold = ""
    @State private var adminApprovalThreshold = ""
    @State private var requireReceiptPhoto = true
    @State private var requireProjectAssignment = false
    @State private var isSaving = false

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    // REVIEW FREQUENCY
                    sectionHeader("REVIEW FREQUENCY")
                        .padding(.top, OPSStyle.Layout.spacing3)
                    reviewFrequencyCard

                    // THRESHOLDS
                    sectionHeader("AUTO-APPROVAL THRESHOLDS")
                    thresholdsCard

                    // POLICY TOGGLES
                    sectionHeader("SUBMISSION POLICY")
                    policyCard
                }
                .padding(.bottom, 100)
            }

            saveFooter
        }
        .navigationTitle("EXPENSE SETTINGS")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                viewModel.setup(companyId: companyId)
                await viewModel.loadSettings()
                populateFromSettings()
            }
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

    // MARK: - Review Frequency Card

    private var reviewFrequencyCard: some View {
        VStack(spacing: 0) {
            ForEach(ReviewFrequency.allCases, id: \.self) { freq in
                Button {
                    reviewFrequency = freq
                } label: {
                    HStack {
                        Text(freq.displayName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(
                                reviewFrequency == freq
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.secondaryText
                            )
                        Spacer()
                        if reviewFrequency == freq {
                            Image(systemName: "checkmark")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                    .background(
                        reviewFrequency == freq
                        ? OPSStyle.Colors.primaryAccent.opacity(0.08)
                        : Color.clear
                    )
                }
                .buttonStyle(PlainButtonStyle())

                if freq != ReviewFrequency.allCases.last {
                    Divider().background(OPSStyle.Colors.cardBorder)
                }
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
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
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                HStack {
                    Text("AUTO-APPROVE UNDER")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("$")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextField("0", text: $autoApproveThreshold)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                    }
                }
                Text("Expenses under this amount are automatically approved.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)

            Divider().background(OPSStyle.Colors.cardBorder)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                HStack {
                    Text("ADMIN APPROVAL OVER")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("$")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextField("0", text: $adminApprovalThreshold)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                    }
                }
                Text("Expenses over this amount require admin approval.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Policy Card

    private var policyCard: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REQUIRE RECEIPT PHOTO")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("Expenses must include a photo of the receipt.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Spacer()
                Toggle("", isOn: $requireReceiptPhoto)
                    .labelsHidden()
                    .tint(OPSStyle.Colors.primaryAccent)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)

            Divider().background(OPSStyle.Colors.cardBorder)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REQUIRE PROJECT ASSIGNMENT")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("Expenses must be assigned to at least one project.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Spacer()
                Toggle("", isOn: $requireProjectAssignment)
                    .labelsHidden()
                    .tint(OPSStyle.Colors.primaryAccent)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        }
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Save Footer

    private var saveFooter: some View {
        HStack {
            if isSaving {
                ProgressView()
                    .tint(OPSStyle.Colors.primaryAccent)
                    .frame(maxWidth: .infinity)
            } else {
                Button("SAVE SETTINGS") {
                    Task { await saveSettings() }
                }
                .opsPrimaryButtonStyle()
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.background)
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

    // MARK: - Data

    private func populateFromSettings() {
        guard let s = viewModel.settings else { return }
        reviewFrequency = ReviewFrequency(rawValue: s.reviewFrequency ?? "") ?? .weekly
        autoApproveThreshold = s.autoApproveThreshold.map { String(format: "%.2f", $0) } ?? ""
        adminApprovalThreshold = s.adminApprovalThreshold.map { String(format: "%.2f", $0) } ?? ""
        requireReceiptPhoto = s.requireReceiptPhoto ?? true
        requireProjectAssignment = s.requireProjectAssignment ?? false
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
    }
}
