//
//  ExpensesListView.swift
//  OPS
//
//  List of all expenses — grouped by month > project, filter by status, swipe actions, FAB for new expense.
//

import SwiftUI
import SwiftData

struct ExpensesListView: View {
    var embedded: Bool = false

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
                OPSStyle.Colors.background.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Search + filter
                searchAndFilter
                    .padding(.top, OPSStyle.Layout.spacing2)

                Divider().background(OPSStyle.Colors.separator)

                // Content
                if viewModel.isLoading && viewModel.expenses.isEmpty {
                    Spacer()
                    TacticalLoadingBarAnimated()
                    Spacer()
                } else if viewModel.filteredExpenses.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.groupedExpenses) { monthGroup in
                                monthSection(monthGroup)
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .padding(.bottom, 80)
                    }
                    .refreshable {
                        await viewModel.loadAll()
                    }
                }
            }

            // FAB
            expensesFAB
        }
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
                viewModel.setup(companyId: companyId)
                await viewModel.loadAll()
            }
        }
        .onAppear {
            if expandedMonths.isEmpty {
                expandedMonths.insert(Self.currentMonthKey)
            }
        }
    }

    // MARK: - Month Section

    @ViewBuilder
    private func monthSection(_ monthGroup: ExpenseViewModel.ExpenseMonthGroup) -> some View {
        let isExpanded = expandedMonths.contains(monthGroup.id)

        VStack(spacing: 12) {
            // Month header — CollapsibleSection style
            HStack(spacing: 8) {
                Text("[ \(monthGroup.monthLabel) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Rectangle()
                    .fill(OPSStyle.Colors.secondaryText.opacity(0.3))
                    .frame(height: 1)

                Text("[ \(monthGroup.totalCount) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Image(systemName: isExpanded ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if isExpanded {
                        expandedMonths.remove(monthGroup.id)
                    } else {
                        expandedMonths.insert(monthGroup.id)
                    }
                }
            }

            if isExpanded {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    // Unallocated expenses — flat under month
                    ForEach(monthGroup.unallocated) { expense in
                        expenseCardView(expense)
                    }

                    // Project sub-groups
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
            // Project sub-header — indented
            HStack(spacing: 6) {
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
                    .font(.system(size: OPSStyle.Layout.IconSize.xs - 2, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.leading, OPSStyle.Layout.spacing2)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
            // Auto-expand project groups by default
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
            onTap: { editingExpense = expense },
            onSwipeRight: {
                if expense.status == ExpenseStatus.draft.rawValue {
                    Task { await viewModel.submitExpense(expense.id) }
                }
            },
            onSwipeLeft: {
                let status = ExpenseStatus(rawValue: expense.status)
                guard status != .approved && status != .reimbursed else { return }
                Task { await viewModel.deleteExpense(expense.id) }
            }
        )
    }

    // MARK: - Search & Filter

    private var searchAndFilter: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            // Search field
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
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Filter chips
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
                                    ? OPSStyle.Colors.primaryAccent.opacity(0.2)
                                    : OPSStyle.Colors.cardBackgroundDark
                                )
                                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(
                                            viewModel.selectedFilter == filter
                                            ? OPSStyle.Colors.primaryAccent
                                            : OPSStyle.Colors.cardBorder,
                                            lineWidth: OPSStyle.Layout.Border.standard
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: OPSStyle.Icons.expense)
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(viewModel.expenses.isEmpty ? "NO EXPENSES YET" : "NO EXPENSES MATCH FILTER")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            if viewModel.expenses.isEmpty {
                Text("Submit your first expense to get started.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                Button("NEW EXPENSE") { showNewExpenseSheet = true }
                    .opsPrimaryButtonStyle()
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
            }
            Spacer()
        }
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

// MARK: - Hashable Conformance

extension ExpenseDTO: Hashable {
    static func == (lhs: ExpenseDTO, rhs: ExpenseDTO) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
