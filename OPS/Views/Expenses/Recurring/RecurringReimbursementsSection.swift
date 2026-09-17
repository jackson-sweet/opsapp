//
//  RecurringReimbursementsSection.swift
//  OPS
//
//  Expense Settings → RECURRING REIMBURSEMENTS. The one place to see every
//  fixed monthly amount the company pays with expenses (vehicle advertising,
//  phone plans…), what that adds up to this month, and who receives it. Day to
//  day these are handled from a person's batch; this list is for the overview
//  and for setting one up for someone with no batch yet. Rows open the same
//  sheet the batch review uses. Approvers only.
//

import SwiftUI
import SwiftData

struct RecurringReimbursementsSection: View {
    /// The company's batches, for the add sheet's preview.
    let batches: [ExpenseBatchDTO]

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @Query private var users: [User]
    @StateObject private var viewModel = RecurringReimbursementViewModel()
    @State private var sheet: RecurringSheetMode?

    private var canManage: Bool { permissionStore.can("expenses.approve") }

    private var people: [RecurringPerson] {
        RecurringPerson.eligible(
            users: users,
            companyId: dataController.currentUser?.companyId,
            currentUserId: dataController.currentUser?.id,
            currentUserIsAdmin: permissionStore.isAdmin
        )
    }

    private func personName(_ userId: String) -> String {
        guard let user = users.first(where: { $0.id.lowercased() == userId.lowercased() }) else { return "—" }
        return RecurringPerson.displayName(first: user.firstName, last: user.lastName, email: user.email)
    }

    /// People first, then name — the way an owner looks for one.
    private var setups: [ExpenseRecurringReimbursementDTO] {
        viewModel.setups.sorted { lhs, rhs in
            let byPerson = personName(lhs.userId).localizedCaseInsensitiveCompare(personName(rhs.userId))
            if byPerson != .orderedSame { return byPerson == .orderedAscending }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// What goes out this month: started and not yet ended, in company currency.
    private var monthlySummary: String? {
        let month = viewModel.currentMonth
        let running = setups.filter { ExpenseRecurring.isRunning($0, in: month) }
        guard !running.isEmpty else { return nil }
        let currency = viewModel.currency
        let total = running
            .filter { $0.currency.uppercased() == currency }
            .reduce(0) { $0 + $1.amount }
        let people = Set(running.map { $0.userId.lowercased() }).count
        let who = people == 1 ? "1 PERSON" : "\(people) PEOPLE"
        return "\(BooksFormat.exact(total, code: currency)) / MO · \(who)"
    }

    var body: some View {
        if canManage {
            content
                .sheet(item: $sheet) { mode in
                    RecurringReimbursementSheet(
                        viewModel: viewModel,
                        mode: mode,
                        batches: batches,
                        people: people,
                        nameFor: personName
                    )
                    .environmentObject(dataController)
                }
                .task {
                    guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else { return }
                    viewModel.setup(companyId: companyId)
                    await viewModel.load()
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .expenseUpdated)
                        .receive(on: DispatchQueue.main)
                ) { _ in
                    viewModel.scheduleRefresh()
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                Text("RECURRING REIMBURSEMENTS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer(minLength: OPSStyle.Layout.spacing2)
                if let monthlySummary {
                    Text(monthlySummary)
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Text("Fixed amounts added to a person's expenses every month. Pre-approved, no receipt.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            list

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                sheet = .create(person: nil, firstPeriod: nil)
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: OPSStyle.Icons.plus)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                    Text("ADD")
                        .font(OPSStyle.Typography.captionBold)
                }
                .foregroundColor(OPSStyle.Colors.text2)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.snapshot == nil)
            .accessibilityLabel("Add a recurring reimbursement")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    @ViewBuilder
    private var list: some View {
        if viewModel.snapshot == nil {
            if viewModel.loadFailed {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text("// COULDN'T LOAD")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.rose)
                    Spacer()
                    Button("RETRY") {
                        Task { await viewModel.load() }
                    }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                }
            } else {
                ProgressView()
                    .tint(OPSStyle.Colors.text3)
                    .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
                    .accessibilityLabel("Loading recurring reimbursements")
            }
        } else if setups.isEmpty {
            Text("None set up")
                .font(OPSStyle.Typography.smallBody)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        } else {
            VStack(spacing: 0) {
                ForEach(setups) { setup in
                    row(setup)
                    if setup.id != setups.last?.id {
                        Rectangle()
                            .fill(OPSStyle.Colors.line)
                            .frame(height: OPSStyle.Layout.Border.standard)
                            .padding(.leading, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .glassSurface()
        }
    }

    private func row(_ setup: ExpenseRecurringReimbursementDTO) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            sheet = .edit(setupId: setup.id)
        } label: {
            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(setup.name)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Text(personName(setup.userId).uppercased())
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: OPSStyle.Layout.spacing2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(BooksFormat.exact(setup.amount, code: setup.currency)) / MO")
                        .font(OPSStyle.Typography.caption)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text(setup.lastPeriod.map { "LAST \(ExpenseRecurring.formatMonth($0))" }
                         ?? "SINCE \(ExpenseRecurring.formatMonth(setup.firstPeriod))")
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityHint("Change, end or delete")
    }
}
