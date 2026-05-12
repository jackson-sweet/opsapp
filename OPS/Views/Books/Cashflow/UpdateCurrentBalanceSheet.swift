//
//  UpdateCurrentBalanceSheet.swift
//  OPS
//
//  Modal for entering the current bank balance. Anchors the entire forecast.
//  Save commits to expense_settings via ForecastSettingsRepository and stamps
//  `forecast_balance_updated_at`.
//

import SwiftUI

struct UpdateCurrentBalanceSheet: View {
    @ObservedObject var viewModel: CashflowForecastViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var balanceText: String = ""
    @State private var saving: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("$0", text: $balanceText)
                        .keyboardType(.decimalPad)
                        .font(OPSStyle.Typography.dataValueLg)
                        .monospacedDigit()
                } header: {
                    Text("CURRENT BANK BALANCE")
                        .font(OPSStyle.Typography.microLabel)
                } footer: {
                    Text("Enter your actual cash on hand. The forecast extends this number forward based on scheduled inflows and outflows.")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .navigationTitle("UPDATE BALANCE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("SAVE") { Task { await save() } }
                        .disabled(Double(balanceText) == nil || saving)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }

    private func save() async {
        guard let value = Double(balanceText) else { return }
        saving = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let repo = ForecastSettingsRepository(companyId: viewModel.companyIdForExternalUse)
        let payload = UpdateForecastSettingsDTO(
            lowWaterThreshold: nil,
            currentBalance: value,
            balanceUpdatedAt: SupabaseDate.format(Date())
        )
        _ = try? await repo.update(payload)
        await viewModel.load()
        saving = false
        dismiss()
    }
}
