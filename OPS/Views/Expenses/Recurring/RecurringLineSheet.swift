//
//  RecurringLineSheet.swift
//  OPS
//
//  What a recurring reimbursement line is, opened from an expense list. The
//  line is office-owned — never edited as an expense — so it opens here
//  instead of the expense form: the month it pays for, where it stands, and
//  the arrangement behind it. No receipt, no alarm.
//
//  Approvers also get the two verbs that matter for one month: EDIT the
//  arrangement, or SKIP this month while it is unpaid (UNDO rides the toast).
//

import SwiftUI

struct RecurringLineSheet: View {
    let line: ExpenseDTO
    /// The line's envelope has been paid out — its month can no longer be skipped.
    let batchIsPaid: Bool
    /// May change recurring reimbursements (`expenses.approve`, scope all).
    let canManage: Bool
    /// The company's batches, for the editor's preview.
    let batches: [ExpenseBatchDTO]
    /// Display name for a user id.
    let nameFor: (String) -> String
    /// Runs after a command lands so the list behind refreshes.
    var onChanged: () -> Void = {}

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RecurringReimbursementViewModel()
    @State private var editorMode: RecurringSheetMode?

    private var setup: ExpenseRecurringReimbursementDTO? {
        viewModel.setup(for: line)
    }

    private var status: ExpenseStatus? { ExpenseStatus(rawValue: line.status) }

    private var canSkip: Bool {
        canManage && status == .approved && !batchIsPaid && line.recurringPeriod != nil
    }

    private var skipPending: Bool {
        viewModel.inFlight == .skip(line.id)
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    header
                    facts
                    Text(canManage
                         ? "[ No receipt needed. Filed with their expenses every month. ]"
                         : "[ No receipt needed. Added by the office every month. ]")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    if canManage {
                        actions
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing4)
                .padding(.bottom, OPSStyle.Layout.spacing4)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(OPSStyle.Colors.background)
        .interactiveDismissDisabled(viewModel.inFlight != nil)
        .sheet(item: $editorMode) { mode in
            RecurringReimbursementSheet(
                viewModel: viewModel,
                mode: mode,
                batches: batches,
                people: [],
                nameFor: nameFor,
                onChanged: onChanged
            )
            .environmentObject(dataController)
        }
        .task {
            guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else { return }
            viewModel.setup(companyId: companyId)
            await viewModel.load()
        }
        .trackScreen("Expenses.RecurringLine")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.recurring)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .accessibilityHidden(true)
                Text("RECURRING REIMBURSEMENT")
                    .font(OPSStyle.Typography.metadata)
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.text3)
            }

            Text(line.merchantName ?? setup?.name ?? "—")
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(2)

            Text(BooksFormat.exact(line.amount, code: line.currency ?? setup?.currency ?? "USD"))
                .font(OPSStyle.Typography.dataValueLg)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.text)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Facts

    private var facts: some View {
        VStack(spacing: 0) {
            factRow("PAYS FOR", value: line.recurringPeriod.map(ExpenseRecurring.formatMonth) ?? "—")
            divider
            HStack {
                factLabel("STATUS")
                Spacer()
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Circle()
                        .fill(OPSStyle.Colors.olive)
                        .frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)
                    Text(status == .reimbursed ? "PAID" : "APPROVED")
                        .font(OPSStyle.Typography.metadata)
                        .kerning(1.2)
                        .foregroundColor(OPSStyle.Colors.olive)
                }
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            if canManage {
                divider
                factRow("PAID TO", value: nameFor(line.submittedBy), mono: false)
            }
            if let setup {
                divider
                factRow("EVERY MONTH", value: arrangement(setup))
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private func arrangement(_ setup: ExpenseRecurringReimbursementDTO) -> String {
        let since = ExpenseRecurring.formatMonth(setup.firstPeriod)
        guard let last = setup.lastPeriod else { return "SINCE \(since)" }
        return "\(since) – \(ExpenseRecurring.formatMonth(last))"
    }

    private func factRow(_ label: String, value: String, mono: Bool = true) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            factLabel(label)
            Spacer(minLength: OPSStyle.Layout.spacing2)
            Text(value)
                .font(mono ? OPSStyle.Typography.caption : OPSStyle.Typography.body)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .accessibilityElement(children: .combine)
    }

    private func factLabel(_ label: String) -> some View {
        Text(label)
            .font(OPSStyle.Typography.metadata)
            .kerning(1.2)
            .foregroundColor(OPSStyle.Colors.text3)
    }

    private var divider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.line)
            .frame(height: OPSStyle.Layout.Border.standard)
    }

    // MARK: - Actions (approvers)

    private var actions: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if let setup { editorMode = .edit(setupId: setup.id) }
            } label: {
                Text("EDIT")
            }
            .opsSecondaryButtonStyle()
            .disabled(setup == nil || viewModel.inFlight != nil)
            .accessibilityHint("Change the amount, end it, or delete it")

            if canSkip, let period = line.recurringPeriod {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    skip()
                } label: {
                    if skipPending {
                        ProgressView().tint(OPSStyle.Colors.text2)
                    } else {
                        Text("SKIP \(ExpenseRecurring.formatMonth(period))")
                    }
                }
                .opsSecondaryButtonStyle()
                .disabled(viewModel.inFlight != nil)
                .accessibilityHint("Leave this month out. Undo from the confirmation.")
            }
        }
    }

    private func skip() {
        Task {
            let outcome = await viewModel.skip(line, onChanged: onChanged)
            // A skipped month leaves the list; so does its sheet.
            if outcome == .done { dismiss() }
        }
    }
}
