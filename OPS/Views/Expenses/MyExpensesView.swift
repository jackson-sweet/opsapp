//
//  MyExpensesView.swift
//  OPS
//
//  Personal expense list — search, filter, month/project grouping, submit for review, FAB.
//

import SwiftUI
import SwiftData

struct MyExpensesView: View {
    /// When embedded in the Books page (which owns the single scroll + provides
    /// the global FAB), drop the inner ScrollView, the redundant header, and the
    /// in-view FAB — matching the other embedded list views.
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ExpenseViewModel()
    @EnvironmentObject private var dataController: DataController
    @Query private var allProjects: [Project]
    @State private var showNewExpenseSheet = false
    @State private var editingExpense: ExpenseDTO? = nil
    @State private var searchText = ""
    @State private var expandedMonths: Set<String> = []
    @State private var expandedProjects: Set<String> = []

    private static var currentMonthKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if !embedded {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
            }

            VStack(spacing: 0) {
                // Header — the Books page provides its own AppHeader + segment
                // picker, so hide this redundant one when embedded.
                if !embedded {
                    SettingsHeader(
                        title: "My Expenses",
                        onBackTapped: { dismiss() }
                    )
                }

                // Content — embedded renders inline (Books owns the single
                // scroll); standalone keeps its ScrollView + pull-to-refresh.
                if viewModel.isLoading && viewModel.expenses.isEmpty {
                    if embedded {
                        TacticalLoadingBarAnimated()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OPSStyle.Layout.spacing5)
                    } else {
                        Spacer()
                        TacticalLoadingBarAnimated()
                        Spacer()
                    }
                } else if viewModel.expenses.isEmpty {
                    emptyState
                } else if embedded {
                    expensesScrollContent
                } else {
                    ScrollView {
                        expensesScrollContent
                    }
                    .refreshable {
                        await viewModel.loadAll()
                    }
                }
            }

            // FAB — hidden when embedded in Books (global FAB handles creation).
            if !embedded {
                expensesFAB
            }
        }
        .trackScreen("MyExpenses")
        // Refresh when an expense is created/updated anywhere (e.g. the global
        // FAB), since that flow no longer shares this view's model.
        .onReceive(NotificationCenter.default.publisher(for: .opsExpensesDidChange)) { _ in
            Task { await viewModel.loadAll() }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(item: $editingExpense) { expense in
            ExpenseFormSheet(viewModel: viewModel, editing: expense)
        }
        .sheet(isPresented: $showNewExpenseSheet) {
            ExpenseFormSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
        .task {
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                let user = dataController.currentUser
                let userName = [user?.firstName, user?.lastName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                viewModel.setup(
                    companyId: companyId,
                    currentUserId: user?.id,
                    currentUserName: userName.isEmpty ? nil : userName
                )
                await viewModel.loadAll()
            }
        }
        .onAppear {
            if expandedMonths.isEmpty {
                expandedMonths.insert(Self.currentMonthKey)
            }
        }
    }

    // MARK: - Filling Total + Finish Nudge

    /// Draft (unfinished) lines — captured but not yet added. Drives the nudge.
    private var draftExpenses: [ExpenseDTO] {
        viewModel.expenses.filter { $0.status == ExpenseStatus.draft.rawValue }
    }

    /// Low-key running total of the current filling envelope. Hidden when
    /// nothing is filling this period.
    @ViewBuilder
    private var fillingStrip: some View {
        if let f = viewModel.currentFilling {
            HStack {
                Text(f.periodLabel.isEmpty ? "FILLING" : "FILLING · \(f.periodLabel)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                Text(f.total, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
        }
    }

    /// Gentle reminder to finish captured-but-unsent receipts (snap-a-stack
    /// drafts). Hidden when there are none.
    @ViewBuilder
    private var finishNudge: some View {
        let count = draftExpenses.count
        if count > 0 {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.receipt)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) RECEIPT\(count == 1 ? "" : "S") TO FINISH")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("Add the details to send \(count == 1 ? "it" : "them") in.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                Spacer()
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Expenses List

    /// The scrollable body, shared by the embedded (inline) and standalone
    /// (own ScrollView) layouts.
    private var expensesScrollContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing3_5) {
            searchAndFilter
            finishNudge
            fillingStrip
            if viewModel.filteredExpenses.isEmpty {
                filterEmptyState
            } else {
                expensesList
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
        // Standalone clears the in-view FAB; embedded only needs strip rhythm.
        .padding(.bottom, embedded
                 ? OPSStyle.Layout.spacing4
                 : OPSStyle.Layout.touchTargetLarge + OPSStyle.Layout.spacing4 + OPSStyle.Layout.spacing2_5)
    }

    private var expensesList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.groupedExpenses) { monthGroup in
                monthSection(monthGroup)
            }
        }
    }

    // MARK: - Month Section

    @ViewBuilder
    private func monthSection(_ monthGroup: ExpenseViewModel.ExpenseMonthGroup) -> some View {
        let isExpanded = expandedMonths.contains(monthGroup.id)

        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("[ \(monthGroup.monthLabel) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Rectangle()
                    .fill(OPSStyle.Colors.separator)
                    .frame(height: 1)

                Text("[ \(monthGroup.totalCount) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Image(systemName: isExpanded ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(OPSStyle.Animation.standard) {
                    if isExpanded {
                        expandedMonths.remove(monthGroup.id)
                    } else {
                        expandedMonths.insert(monthGroup.id)
                    }
                }
            }

            if isExpanded {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(monthGroup.unallocated) { expense in
                        expenseCardView(expense)
                    }

                    ForEach(monthGroup.projectGroups) { projectGroup in
                        projectSubSection(projectGroup, monthId: monthGroup.id)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Project Sub-Section

    @ViewBuilder
    private func projectSubSection(_ projectGroup: ExpenseViewModel.ProjectExpenseGroup, monthId: String) -> some View {
        let compositeKey = "\(monthId)_\(projectGroup.projectId)"
        let isExpanded = expandedProjects.contains(compositeKey)
        let projectName = allProjects.first(where: { $0.id == projectGroup.projectId })?.title ?? projectGroup.projectId

        VStack(spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: OPSStyle.Icons.folderFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text(projectName.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)

                Spacer()

                Text("[ \(projectGroup.expenses.count) ]")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Image(systemName: isExpanded ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.leading, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(OPSStyle.Animation.standard) {
                    if isExpanded {
                        expandedProjects.remove(compositeKey)
                    } else {
                        expandedProjects.insert(compositeKey)
                    }
                }
            }

            if isExpanded {
                ForEach(projectGroup.expenses) { expense in
                    expenseCardView(expense)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            if !expandedProjects.contains(compositeKey) {
                expandedProjects.insert(compositeKey)
            }
        }
    }

    // MARK: - Expense Card

    private func expenseCardView(_ expense: ExpenseDTO) -> some View {
        ExpenseCard(
            expense: expense,
            categoryName: expense.category?.name,
            categoryIcon: expense.category?.icon,
            batchStatus: viewModel.batchStatus(for: expense),
            onTap: { editingExpense = expense },
            onSwipeLeft: {
                let status = ExpenseStatus(rawValue: expense.status)
                // Delete only draft / rejected lines — submitted/approved/paid are locked here.
                guard status == .draft || status == .rejected else { return }
                Task { await viewModel.deleteExpense(expense.id) }
            }
        )
    }

    // MARK: - Search & Filter

    private var searchAndFilter: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Image(systemName: OPSStyle.Icons.search)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                TextField("Search expenses...", text: $searchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .onChange(of: searchText) { _, newValue in
                        viewModel.searchText = newValue
                    }
                if !searchText.isEmpty {
                    Button { searchText = ""; viewModel.searchText = "" } label: {
                        Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(ExpenseViewModel.ExpenseFilter.allCases, id: \.self) { filter in
                        Button(action: { viewModel.selectedFilter = filter }) {
                            Text(filter.rawValue)
                                .font(OPSStyle.Typography.smallCaption)
                                .fontWeight(viewModel.selectedFilter == filter ? .semibold : .regular)
                                .foregroundColor(
                                    viewModel.selectedFilter == filter
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.tertiaryText
                                )
                                .padding(.horizontal, OPSStyle.Layout.spacing2 + 2)
                                .padding(.vertical, OPSStyle.Layout.spacing1 + 2)
                                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                                .background(
                                    viewModel.selectedFilter == filter
                                    ? OPSStyle.Colors.surfaceActive
                                    : OPSStyle.Colors.cardBackgroundDark
                                )
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(
                                            viewModel.selectedFilter == filter
                                            ? OPSStyle.Colors.text
                                            : OPSStyle.Colors.cardBorder,
                                            lineWidth: OPSStyle.Layout.Border.standard
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: OPSStyle.Icons.expense)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("NO EXPENSES YET")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text("Submit your first expense to get started.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)
            Button(action: { showNewExpenseSheet = true }) {
                Text("NEW EXPENSE")
                    .font(OPSStyle.Typography.bodyBold)
            }
            .opsPrimaryButtonStyle()
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            Spacer()
        }
    }

    private var filterEmptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.expense)
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("NO EXPENSES MATCH FILTER")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }

    // MARK: - FAB

    private var expensesFAB: some View {
        Button {
            showNewExpenseSheet = true
        } label: {
            Image(systemName: OPSStyle.Icons.plus)
                .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .medium))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: OPSStyle.Layout.touchTargetLarge, height: OPSStyle.Layout.touchTargetLarge)
                .background(OPSStyle.Colors.primaryAccent)
                .clipShape(Circle())
        }
        .padding(OPSStyle.Layout.spacing3)
        .accessibilityLabel("New Expense")
    }
}
