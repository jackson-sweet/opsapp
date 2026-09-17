//
//  RecurringReimbursementSheet.swift
//  OPS
//
//  Add a recurring reimbursement, or change / end / delete one. Setting one up
//  is rare, so the sheet lives behind quiet actions; its job is to say exactly
//  what will happen before anything commits:
//
//    add    → which months are filed now, and which of those were already paid
//             out (their line lands on the next batch)
//    save   → unpaid months follow the change; paid months stay as paid
//    end    → last-month picker floored at the latest month already filed
//    delete → only while no month has been paid (a setup made in error)
//
//  The database is the authority for every rule; a refusal arrives as a toast.
//  Commands carry the setup's `updated_at` from when the form opened, so an
//  edit made elsewhere in the meantime is refused rather than overwritten.
//

import SwiftUI

enum RecurringSheetMode: Identifiable, Equatable {
    /// `person` is fixed when opened from a person's batch and chosen in the
    /// sheet otherwise. `firstPeriod` defaults to this month; a batch passes
    /// its own period.
    case create(person: RecurringPerson?, firstPeriod: String?)
    case edit(setupId: String)

    var id: String {
        switch self {
        case .create(let person, let firstPeriod):
            return "create-\(person?.id ?? "anyone")-\(firstPeriod ?? "now")"
        case .edit(let setupId):
            return "edit-\(setupId)"
        }
    }
}

struct RecurringReimbursementSheet: View {
    @ObservedObject var viewModel: RecurringReimbursementViewModel
    let mode: RecurringSheetMode
    /// The company's batches — the placement preview reads the person's own.
    let batches: [ExpenseBatchDTO]
    /// Who can receive one, when the person is chosen in the sheet.
    let people: [RecurringPerson]
    /// Display name for a user id (the setup's person when editing).
    let nameFor: (String) -> String
    /// Runs after a command lands, before the sheet closes.
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    private enum Stage { case form, end }

    private enum PickerKind: String, Identifiable {
        case person, firstMonth, lastMonth
        var id: String { rawValue }
    }

    @State private var stage: Stage = .form
    @State private var personId: String?
    @State private var name = ""
    @State private var amountText = ""
    @State private var firstPeriod = ""
    @State private var lastPeriod = ""
    /// The setup as it was when the form opened — its `updated_at` is the
    /// concurrency token every command sends.
    @State private var seededSetup: ExpenseRecurringReimbursementDTO?
    @State private var hasSeeded = false
    @State private var picker: PickerKind?
    @State private var confirm: OPSConfirmConfig?
    @FocusState private var amountFocused: Bool

    // MARK: - Derived

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private var fixedPerson: RecurringPerson? {
        if case .create(let person, _) = mode { return person }
        return nil
    }

    /// Live months when loaded (skips and new months show up), the seeded
    /// copy otherwise.
    private var displayedSetup: ExpenseRecurringReimbursementDTO? {
        guard case .edit(let setupId) = mode else { return nil }
        return viewModel.setup(id: setupId) ?? seededSetup
    }

    private var currentMonth: String { viewModel.currentMonth }

    private var moneyCurrency: String {
        displayedSetup?.currency ?? viewModel.currency
    }

    private var amount: Double? { ExpenseRecurring.parseAmount(amountText) }

    private var normalizedName: String? { ExpenseRecurring.normalizedName(name) }

    private var amountIsInvalid: Bool {
        !amountText.trimmingCharacters(in: .whitespaces).isEmpty && amount == nil
    }

    private var personName: String? {
        if let setup = displayedSetup { return nameFor(setup.userId) }
        if let fixedPerson { return fixedPerson.name }
        guard let personId else { return nil }
        return people.first(where: { $0.id == personId })?.name
    }

    private var preview: ExpenseRecurring.PlacementPreview? {
        guard isCreate, let personId, !firstPeriod.isEmpty else { return nil }
        return ExpenseRecurring.placementPreview(
            firstPeriod: firstPeriod,
            currentMonth: currentMonth,
            userId: personId,
            batches: batches
        )
    }

    private var endChoices: [String] {
        guard let setup = displayedSetup else { return [] }
        return ExpenseRecurring.endMonthOptions(
            firstPeriod: setup.firstPeriod,
            latestFiled: ExpenseRecurring.latestFiledPeriod(setup.lines),
            currentMonth: currentMonth
        )
    }

    private var deletable: Bool {
        guard let setup = displayedSetup else { return false }
        return ExpenseRecurring.canDelete(setup.lines)
    }

    private var busy: Bool { viewModel.inFlight != nil }

    private var unchanged: Bool {
        guard let seededSetup, let amount else { return false }
        return normalizedName == seededSetup.name && amount == seededSetup.amount
    }

    private var canSubmit: Bool {
        guard !busy, hasSeeded, normalizedName != nil, amount != nil else { return false }
        return isCreate ? personId != nil : (seededSetup != nil && !unchanged)
    }

    private var submitPending: Bool {
        switch viewModel.inFlight {
        case .create?, .update?: return true
        default: return false
        }
    }

    private var endPending: Bool {
        if case .end? = viewModel.inFlight { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        if let personName {
                            Text("Paid to \(personName) with their expenses")
                                .font(OPSStyle.Typography.smallBody)
                                .foregroundColor(OPSStyle.Colors.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        switch stage {
                        case .form: formStage
                        case .end: endStage
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.touchTargetLarge + OPSStyle.Layout.spacing5)
                    .disabled(busy || !hasSeeded)
                }
                .scrollDismissesKeyboard(.interactively)

                footer
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(stage == .form ? "CANCEL" : "BACK") {
                        if stage == .end {
                            withAnimation(OPSStyle.Animation.panel) { stage = .form }
                        } else {
                            dismiss()
                        }
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(busy ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                    .disabled(busy)
                }
                ToolbarItem(placement: .principal) {
                    Text("RECURRING REIMBURSEMENT")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .sheet(item: $picker) { kind in
            optionSheet(kind)
        }
        .opsConfirm($confirm)
        .task { await seedIfNeeded() }
    }

    // MARK: - Form stage

    private var formStage: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            if isCreate && fixedPerson == nil {
                RecurringPickerRow(
                    label: "Person",
                    value: people.first(where: { $0.id == personId })?.name,
                    placeholder: "Choose a person"
                ) { picker = .person }
            }

            FormField(
                title: "Name",
                placeholder: "Vehicle advertising",
                text: $name,
                autocapitalization: .sentences
            )
            .onChange(of: name) { _, newValue in
                let clamped = ExpenseRecurring.clampedName(newValue)
                if clamped != newValue { name = clamped }
            }

            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
                amountField
                if isCreate {
                    RecurringPickerRow(
                        label: "First month",
                        value: firstPeriod.isEmpty ? nil : ExpenseRecurring.formatMonth(firstPeriod),
                        mono: true
                    ) { picker = .firstMonth }
                } else {
                    sinceField
                }
            }

            previewLines

            if displayedSetup != nil {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Button("END") { openEnd() }
                        .opsSecondaryCompactButtonStyle()
                        .accessibilityHint("Choose the last month it pays for")
                    if deletable {
                        Button("DELETE") { confirmDelete() }
                            .opsSecondaryCompactButtonStyle()
                            .accessibilityHint("Remove it and every month. For one set up by mistake.")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, OPSStyle.Layout.spacing2)
            }
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("EVERY MONTH")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(OPSStyle.Typography.trackingStandard)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(moneyCurrency)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                TextField(
                    "",
                    text: $amountText,
                    prompt: Text("0.00")
                        .font(OPSStyle.Typography.cardSubtitle)
                        .foregroundColor(OPSStyle.Colors.text3)
                )
                .font(OPSStyle.Typography.cardSubtitle)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.text)
                .tint(OPSStyle.Colors.text)
                .keyboardType(.decimalPad)
                .focused($amountFocused)
                .accessibilityLabel("Amount every month")
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.inputHeight)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(amountBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .animation(OPSStyle.Animation.hover, value: amountFocused)
            .onChange(of: amountFocused) { _, focused in
                // Settle what was typed into the stored form (`350` → `350.00`).
                guard !focused, let parsed = ExpenseRecurring.parseAmount(amountText) else { return }
                amountText = ExpenseRecurring.amountText(parsed)
            }

            if amountIsInvalid {
                Text("0.01 TO 10,000.00")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.rose)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amountBorder: Color {
        if amountIsInvalid { return OPSStyle.Colors.rose }
        return amountFocused ? OPSStyle.Colors.inputFieldBorderFocus : OPSStyle.Colors.inputFieldBorder
    }

    /// When an existing one started — a fact, not a field.
    private var sinceField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("SINCE")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(OPSStyle.Typography.trackingStandard)
            Text(displayedSetup.map { ExpenseRecurring.formatMonth($0.firstPeriod) } ?? "—")
                .font(OPSStyle.Typography.cardSubtitle)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.text2)
                .frame(minHeight: OPSStyle.Layout.inputHeight, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - What happens — stated before commit

    @ViewBuilder
    private var previewLines: some View {
        if let preview {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                if preview.startsLater {
                    bracketLine("Starts \(ExpenseRecurring.formatMonth(firstPeriod)). Nothing is added before then.")
                } else {
                    let money = amount.map { BooksFormat.exact($0, code: moneyCurrency) } ?? "—"
                    bracketLine("Adds \(money) for \(ExpenseRecurring.formatMonths(preview.filedNow)) now, then every month.")
                }
                if !preview.paidOut.isEmpty {
                    bracketLine(
                        "\(ExpenseRecurring.formatMonths(preview.paidOut)) already paid out. Those months go on the next batch.",
                        color: OPSStyle.Colors.tan
                    )
                }
            }
        }

        if let setup = displayedSetup {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                bracketLine("Unpaid months change to the new amount. Paid months stay as paid.")
                if let last = setup.lastPeriod {
                    HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                        bracketLine("Last month \(ExpenseRecurring.formatMonth(last)).")
                        Button("REMOVE END") { removeEnd() }
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.text2)
                            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                            .contentShape(Rectangle())
                            .accessibilityHint("Run it every month again")
                    }
                } else {
                    bracketLine("Runs every month until you end it.")
                }
            }
        }
    }

    private func bracketLine(_ text: String, color: Color = OPSStyle.Colors.text3) -> some View {
        Text("[ \(text) ]")
            .font(OPSStyle.Typography.metadata)
            .monospacedDigit()
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - End stage

    private var endStage: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            RecurringPickerRow(
                label: "Last month",
                value: lastPeriod.isEmpty ? nil : ExpenseRecurring.formatMonth(lastPeriod),
                mono: true
            ) { picker = .lastMonth }

            if !lastPeriod.isEmpty {
                bracketLine("Nothing is added after \(ExpenseRecurring.formatMonth(lastPeriod)). Months already on a batch stay.")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        OPSFloatingButtonBar {
            switch stage {
            case .form:
                Button(action: submit) {
                    footerLabel(isCreate ? "ADD" : "SAVE", pending: submitPending)
                }
                .opsPrimaryButtonStyle(isDisabled: !canSubmit)
                .disabled(!canSubmit)
            case .end:
                Button(action: confirmEnd) {
                    footerLabel("END AFTER \(ExpenseRecurring.formatMonth(lastPeriod))", pending: endPending)
                }
                .opsPrimaryButtonStyle(isDisabled: busy || lastPeriod.isEmpty)
                .disabled(busy || lastPeriod.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func footerLabel(_ title: String, pending: Bool) -> some View {
        if pending {
            ProgressView()
                .tint(OPSStyle.Colors.opsAccent)
                .accessibilityLabel("Saving")
        } else {
            Text(title)
        }
    }

    // MARK: - Pickers

    @ViewBuilder
    private func optionSheet(_ kind: PickerKind) -> some View {
        switch kind {
        case .person:
            RecurringOptionSheet(
                title: "PERSON",
                options: people.map { .init(id: $0.id, label: $0.name) },
                selectedId: personId,
                emptyLabel: "NO ACTIVE TEAMMATES"
            ) { personId = $0 }
        case .firstMonth:
            RecurringOptionSheet(
                title: "FIRST MONTH",
                options: ExpenseRecurring.monthOptions(current: currentMonth).map {
                    .init(id: $0, label: ExpenseRecurring.formatMonth($0))
                },
                selectedId: firstPeriod,
                mono: true
            ) { firstPeriod = $0 }
        case .lastMonth:
            RecurringOptionSheet(
                title: "LAST MONTH",
                options: endChoices.map { .init(id: $0, label: ExpenseRecurring.formatMonth($0)) },
                selectedId: lastPeriod,
                mono: true
            ) { lastPeriod = $0 }
        }
    }

    // MARK: - Seeding

    private func seedIfNeeded() async {
        guard !hasSeeded else { return }
        // Months follow the company calendar and edits need the live record.
        if viewModel.snapshot == nil {
            await viewModel.load()
        }
        switch mode {
        case .create(let person, let first):
            personId = person?.id
            firstPeriod = first.map(ExpenseRecurring.monthStart) ?? currentMonth
        case .edit(let setupId):
            var found = viewModel.setup(id: setupId)
            if found == nil {
                // A setup added elsewhere since the list loaded — read again once.
                await viewModel.load()
                found = viewModel.setup(id: setupId)
            }
            guard let setup = found else {
                // Gone, or the read failed — there is nothing safe to edit.
                ToastCenter.shared.present(
                    viewModel.loadFailed ? Feedback.Recurring.loadFailed : Feedback.Recurring.refused(.removed)
                )
                dismiss()
                return
            }
            seededSetup = setup
            name = setup.name
            amountText = ExpenseRecurring.amountText(setup.amount)
            firstPeriod = setup.firstPeriod
        }
        hasSeeded = true
    }

    // MARK: - Commands

    private func submit() {
        guard canSubmit, let amount, let name = normalizedName else { return }
        amountFocused = false
        Task {
            let outcome: RecurringReimbursementViewModel.Outcome
            if let seededSetup {
                outcome = await viewModel.update(seededSetup, name: name, amount: amount)
            } else if let personId {
                outcome = await viewModel.create(
                    userId: personId,
                    name: name,
                    amount: amount,
                    firstPeriod: firstPeriod
                )
            } else {
                return
            }
            finish(outcome)
        }
    }

    private func openEnd() {
        amountFocused = false
        lastPeriod = ExpenseRecurring.defaultEndMonth(options: endChoices, currentMonth: currentMonth)
        withAnimation(OPSStyle.Animation.panel) { stage = .end }
    }

    private func confirmEnd() {
        guard let seededSetup, !lastPeriod.isEmpty, !busy else { return }
        let month = lastPeriod
        Task { finish(await viewModel.end(seededSetup, lastPeriod: month)) }
    }

    private func removeEnd() {
        guard let seededSetup, !busy else { return }
        Task { finish(await viewModel.end(seededSetup, lastPeriod: nil)) }
    }

    private func confirmDelete() {
        guard let seededSetup else { return }
        confirm = OPSConfirmConfig(
            title: "DELETE RECURRING REIMBURSEMENT?",
            message: "Removes every month from its batch. For one set up by mistake.",
            verb: "DELETE",
            isDestructive: true
        ) {
            Task { finish(await viewModel.delete(seededSetup)) }
        }
    }

    /// Close on success, and on a refusal that means this form is out of date
    /// (reopening shows the current truth). Any other refusal keeps the
    /// operator's entry so they can fix it.
    private func finish(_ outcome: RecurringReimbursementViewModel.Outcome) {
        guard outcome == .done || outcome.invalidatesForm else { return }
        onChanged()
        dismiss()
    }
}
