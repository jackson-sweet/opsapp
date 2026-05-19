//
//  ForecastSettingsSheet.swift
//  OPS
//
//  Forecast settings: low-water threshold + recurring-expense CRUD list.
//  The current-balance update lives in UpdateCurrentBalanceSheet (separate
//  modal) so the forecast header can deep-link directly to it.
//

import SwiftUI

struct ForecastSettingsSheet: View {
    @ObservedObject var viewModel: CashflowForecastViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var thresholdText: String = "5000"
    @State private var allRecurring: [RecurringExpenseDTO] = []
    @State private var editing: RecurringExpenseDTO?
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            Form {
                Section("LOW-WATER THRESHOLD") {
                    TextField("$5,000", text: $thresholdText)
                        .keyboardType(.decimalPad)
                        .onSubmit { Task { await saveThreshold() } }
                }

                Section("RECURRING EXPENSES") {
                    if allRecurring.isEmpty {
                        Text("None yet — add rent, insurance, payroll, subscriptions.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    } else {
                        ForEach(allRecurring, id: \.id) { r in
                            Button { editing = r } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                        Text("\(RecurringCadence(rawValue: r.cadence)?.displayName ?? "MONTHLY") · NEXT \(r.nextDueDate)")
                                            .font(OPSStyle.Typography.microLabel)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                    Spacer()
                                    Text(formatCurrency(r.amount))
                                        .font(OPSStyle.Typography.dataValue)
                                        .monospacedDigit()
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                            }
                        }
                    }
                    Button("+ ADD RECURRING") { showNew = true }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .navigationTitle("FORECAST SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("DONE") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .task { await loadAll() }
            .sheet(item: $editing) { r in
                RecurringExpenseEditSheet(viewModel: viewModel, existing: r)
                    .onDisappear { Task { await loadAll() } }
            }
            .sheet(isPresented: $showNew) {
                RecurringExpenseEditSheet(viewModel: viewModel, existing: nil)
                    .onDisappear { Task { await loadAll() } }
            }
        }
    }

    private func loadAll() async {
        let repo = RecurringExpenseRepository(companyId: viewModel.companyIdForExternalUse)
        if let list = try? await repo.fetchAll() {
            allRecurring = list
        }
        if let settings = try? await ForecastSettingsRepository(companyId: viewModel.companyIdForExternalUse).fetch(),
           let t = settings.lowWaterThreshold {
            thresholdText = String(Int(t))
        }
    }

    private func saveThreshold() async {
        guard let v = Double(thresholdText) else { return }
        let repo = ForecastSettingsRepository(companyId: viewModel.companyIdForExternalUse)
        _ = try? await repo.update(UpdateForecastSettingsDTO(
            lowWaterThreshold: v,
            currentBalance: nil,
            balanceUpdatedAt: nil
        ))
        await viewModel.load()
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$0"
    }
}
