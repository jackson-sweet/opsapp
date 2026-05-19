//
//  RecurringExpenseEditSheet.swift
//  OPS
//
//  Create / edit / delete a recurring expense. Powers the recurring outflow
//  layer of the forecast. Save round-trips to RecurringExpenseRepository.
//

import SwiftUI

struct RecurringExpenseEditSheet: View {
    @ObservedObject var viewModel: CashflowForecastViewModel
    let existing: RecurringExpenseDTO?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var amount: String = ""
    @State private var cadence: RecurringCadence = .monthly
    @State private var nextDueDate: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date()
    @State private var notes: String = ""
    @State private var saving: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("EXPENSE") {
                    TextField("Name (e.g. Shop rent)", text: $name)
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                }
                Section("SCHEDULE") {
                    Picker("CADENCE", selection: $cadence) {
                        ForEach(RecurringCadence.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    DatePicker("NEXT DUE", selection: $nextDueDate, displayedComponents: .date)
                    Toggle("HAS END DATE", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker(
                            "END DATE",
                            selection: $endDate,
                            in: nextDueDate...,
                            displayedComponents: .date
                        )
                    }
                }
                Section("NOTES (OPTIONAL)") {
                    TextField("", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            Task { await delete() }
                        } label: {
                            Text("DELETE")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "ADD RECURRING" : "EDIT RECURRING")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("SAVE") { Task { await save() } }
                        .disabled(name.isEmpty || Double(amount) == nil || saving)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .task { hydrate() }
        }
    }

    private func hydrate() {
        guard let e = existing else { return }
        name = e.name
        amount = String(e.amount)
        cadence = RecurringCadence(rawValue: e.cadence) ?? .monthly
        if let due = SupabaseDate.parseDateOnly(e.nextDueDate) { nextDueDate = due }
        if let endStr = e.endDate, let end = SupabaseDate.parseDateOnly(endStr) {
            hasEndDate = true
            endDate = end
        }
        notes = e.notes ?? ""
    }

    private func save() async {
        guard let value = Double(amount) else { return }
        saving = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let repo = RecurringExpenseRepository(companyId: viewModel.companyIdForExternalUse)
        let endStr: String? = hasEndDate ? SupabaseDate.formatDate(endDate) : nil

        do {
            if let e = existing {
                _ = try await repo.update(e.id, fields: UpdateRecurringExpenseDTO(
                    name: name,
                    amount: value,
                    cadence: cadence.rawValue,
                    nextDueDate: SupabaseDate.formatDate(nextDueDate),
                    endDate: endStr,
                    categoryId: nil,
                    notes: notes.isEmpty ? nil : notes
                ))
            } else {
                _ = try await repo.create(CreateRecurringExpenseDTO(
                    companyId: viewModel.companyIdForExternalUse,
                    name: name,
                    amount: value,
                    currency: "USD",
                    cadence: cadence.rawValue,
                    nextDueDate: SupabaseDate.formatDate(nextDueDate),
                    endDate: endStr,
                    categoryId: nil,
                    notes: notes.isEmpty ? nil : notes,
                    createdBy: nil
                ))
            }
            await viewModel.load()
            saving = false
            dismiss()
        } catch {
            saving = false
        }
    }

    private func delete() async {
        guard let e = existing else { return }
        saving = true
        let repo = RecurringExpenseRepository(companyId: viewModel.companyIdForExternalUse)
        try? await repo.softDelete(e.id)
        await viewModel.load()
        saving = false
        dismiss()
    }
}
