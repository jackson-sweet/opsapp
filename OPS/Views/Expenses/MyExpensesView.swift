//
//  MyExpensesView.swift
//  OPS
//
//  Personal expense list — search, filter, month/project grouping, submit for review, FAB.
//

import SwiftUI
import SwiftData

struct MyExpensesView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ExpenseViewModel()
    @EnvironmentObject private var dataController: DataController
    @Query private var allProjects: [Project]
    @State private var showNewExpenseSheet = false
    @State private var editingExpense: ExpenseDTO? = nil
    @State private var searchText = ""
    @State private var expandedMonths: Set<String> = []
    @State private var expandedProjects: Set<String> = []
    @State private var isSubmitting = false
    @State private var showSubmitLoadingOverlay = false
    @State private var submitLoadingComplete = false
    @State private var showEditWarning = false
    @State private var pendingEditExpense: ExpenseDTO? = nil
    @AppStorage("hideExpenseEditWarning") private var hideEditWarning = false
    @State private var showSubmitSelectionSheet = false
    @State private var selectedExpenseIdsForSubmit: Set<String> = []

    private static var currentMonthKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "My Expenses",
                    onBackTapped: { dismiss() }
                )

                // Content
                if viewModel.isLoading && viewModel.expenses.isEmpty {
                    Spacer()
                    TacticalLoadingBarAnimated()
                    Spacer()
                } else if viewModel.expenses.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing3_5) {
                            // Search + filter
                            searchAndFilter

                            // Submit for Review
                            submitForReviewButton

                            // Expense list grouped by month
                            if viewModel.filteredExpenses.isEmpty {
                                filterEmptyState
                            } else {
                                expensesList
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.top, OPSStyle.Layout.spacing3)
                        .padding(.bottom, 100)
                    }
                    .refreshable {
                        await viewModel.loadAll()
                    }
                }
            }

            // FAB
            expensesFAB
        }
        .trackScreen("MyExpenses")
        .navigationBarBackButtonHidden(true)
        .overlay {
            if showSubmitLoadingOverlay {
                submitLoadingOverlay
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseFormSheet(viewModel: viewModel, editing: expense)
        }
        .sheet(isPresented: $showNewExpenseSheet) {
            ExpenseFormSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSubmitSelectionSheet) {
            submitSelectionSheet
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
        .confirmationDialog(
            "Editing will cancel your current submission. You will need to resubmit after making changes.",
            isPresented: $showEditWarning,
            titleVisibility: .visible
        ) {
            Button("Edit Anyway") {
                if let expense = pendingEditExpense {
                    editingExpense = expense
                    pendingEditExpense = nil
                }
            }
            Button("Edit & Don't Ask Again") {
                hideEditWarning = true
                if let expense = pendingEditExpense {
                    editingExpense = expense
                    pendingEditExpense = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingEditExpense = nil
            }
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

    // MARK: - Submit for Review

    /// All draft expenses eligible for submission
    private var draftExpenses: [ExpenseDTO] {
        viewModel.expenses.filter { $0.status == ExpenseStatus.draft.rawValue }
    }

    /// Selected expenses that are missing required fields (photo or project)
    private var selectedExpensesWithIssues: [(expense: ExpenseDTO, missingPhoto: Bool, missingProject: Bool)] {
        let requirePhoto = viewModel.settings?.requireReceiptPhoto ?? false
        let requireProject = viewModel.settings?.requireProjectAssignment ?? false
        guard requirePhoto || requireProject else { return [] }

        return draftExpenses
            .filter { selectedExpenseIdsForSubmit.contains($0.id) }
            .compactMap { expense in
                let missingPhoto = requirePhoto && (expense.receiptImageUrl == nil || expense.receiptImageUrl!.isEmpty)
                let missingProject = requireProject && (expense.allocations == nil || expense.allocations!.isEmpty)
                guard missingPhoto || missingProject else { return nil }
                return (expense, missingPhoto, missingProject)
            }
    }

    private var canSubmitSelected: Bool {
        !selectedExpenseIdsForSubmit.isEmpty && selectedExpensesWithIssues.isEmpty
    }

    private var submitForReviewButton: some View {
        let count = draftExpenses.count

        return Button {
            guard !isSubmitting, count > 0 else { return }
            // Pre-select all draft expenses
            selectedExpenseIdsForSubmit = Set(draftExpenses.map { $0.id })
            showSubmitSelectionSheet = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                Text("SUBMIT EXPENSES")
                    .font(OPSStyle.Typography.captionBold)
                if count > 0 {
                    Text("(\(count))")
                        .font(OPSStyle.Typography.captionBold)
                }
            }
            .foregroundColor(count > 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSStyle.Layout.spacing3)
            .background(count > 0 ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.2))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .disabled(isSubmitting || count == 0)
    }

    private func submitExpensesForReview() {
        isSubmitting = true
        showSubmitLoadingOverlay = true
        submitLoadingComplete = false

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            // Submit each selected expense individually through the always-bundle
            // path. Each attaches to the correct period or per-job batch.
            // ViewModel already has the submitter context from setup().
            let ids = Array(selectedExpenseIdsForSubmit)
            var submitFailures = 0
            for id in ids {
                let before = viewModel.error
                await viewModel.submitExpense(id)
                if viewModel.error != nil && viewModel.error != before {
                    submitFailures += 1
                }
            }
            await viewModel.loadAll()

            // Surface bundling errors instead of swallowing.
            let succeeded = submitFailures == 0
            await MainActor.run {
                if succeeded {
                    withAnimation(OPSStyle.Animation.standard) {
                        submitLoadingComplete = true
                    }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(OPSStyle.Animation.standard) {
                            showSubmitLoadingOverlay = false
                            isSubmitting = false
                        }
                    }
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showSubmitLoadingOverlay = false
                    isSubmitting = false
                    if viewModel.error == nil {
                        viewModel.error = "\(submitFailures) of \(ids.count) expense\(ids.count == 1 ? "" : "s") could not be submitted. Pull to refresh and try again."
                    }
                }
            }
        }
    }

    /// Full-screen loading overlay for submit action
    private var submitLoadingOverlay: some View {
        ZStack {
            OPSStyle.Colors.background.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: OPSStyle.Layout.spacing4) {
                Spacer()

                if submitLoadingComplete {
                    // Success state
                    Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                        .foregroundColor(OPSStyle.Colors.successStatus)
                        .transition(.scale.combined(with: .opacity))

                    Text("EXPENSES SUBMITTED")
                        .font(OPSStyle.Typography.headingBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .transition(.opacity)

                    Text("Your expenses are now under review.")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .transition(.opacity)
                } else {
                    // Loading state
                    TacticalLoadingBarAnimated()
                        .frame(width: 120)

                    Text("SUBMITTING EXPENSES")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .tracking(1)
                }

                Spacer()
            }
        }
        .animation(OPSStyle.Animation.standard, value: submitLoadingComplete)
    }

    // MARK: - Submit Selection Sheet

    private var submitSelectionSheet: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { showSubmitSelectionSheet = false } label: {
                        Text("CANCEL")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .frame(height: OPSStyle.Layout.touchTargetMin)

                    Spacer()

                    Text("REVIEW SUBMISSION")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    // Select/deselect all
                    Button {
                        if selectedExpenseIdsForSubmit.count == draftExpenses.count {
                            selectedExpenseIdsForSubmit.removeAll()
                        } else {
                            selectedExpenseIdsForSubmit = Set(draftExpenses.map { $0.id })
                        }
                    } label: {
                        Text(selectedExpenseIdsForSubmit.count == draftExpenses.count ? "NONE" : "ALL")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(height: OPSStyle.Layout.touchTargetMin)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3)

                // Count summary
                HStack {
                    Text("\(selectedExpenseIdsForSubmit.count) of \(draftExpenses.count) expenses selected")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()

                    let selectedTotal = draftExpenses
                        .filter { selectedExpenseIdsForSubmit.contains($0.id) }
                        .reduce(0.0) { $0 + $1.amount }
                    Text(selectedTotal, format: .currency(code: "USD").precision(.fractionLength(2)))
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.vertical, OPSStyle.Layout.spacing2)

                Rectangle()
                    .fill(OPSStyle.Colors.separator)
                    .frame(height: 1)

                // Expense list
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(draftExpenses) { expense in
                            let isSelected = selectedExpenseIdsForSubmit.contains(expense.id)

                            Button {
                                withAnimation(OPSStyle.Animation.fast) {
                                    if isSelected {
                                        selectedExpenseIdsForSubmit.remove(expense.id)
                                    } else {
                                        selectedExpenseIdsForSubmit.insert(expense.id)
                                    }
                                }
                            } label: {
                                HStack(spacing: OPSStyle.Layout.spacing3) {
                                    // Selection indicator
                                    Image(systemName: isSelected ? OPSStyle.Icons.checkmarkCircleFill : OPSStyle.Icons.circle)
                                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                                        .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)

                                    // Expense details
                                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                        Text(expense.merchantName ?? "Unknown")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .lineLimit(1)

                                        if let categoryName = expense.category?.name {
                                            Text(categoryName)
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        }

                                        // Missing required fields warning
                                        if isSelected, let issue = selectedExpensesWithIssues.first(where: { $0.expense.id == expense.id }) {
                                            HStack(spacing: OPSStyle.Layout.spacing1) {
                                                Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                                                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                                let missing = [
                                                    issue.missingPhoto ? "receipt photo" : nil,
                                                    issue.missingProject ? "project" : nil
                                                ].compactMap { $0 }.joined(separator: ", ")
                                                Text("Missing \(missing)")
                                                    .font(OPSStyle.Typography.smallCaption)
                                            }
                                            .foregroundColor(OPSStyle.Colors.warningStatus)
                                        }
                                    }

                                    Spacer()

                                    Text(expense.amount, format: .currency(code: expense.currency ?? "USD").precision(.fractionLength(2)))
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                                .opacity(isSelected ? 1.0 : 0.5)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Rectangle()
                                .fill(OPSStyle.Colors.separator)
                                .frame(height: 1)
                                .padding(.leading, OPSStyle.Layout.spacing5 + OPSStyle.Layout.spacing4)
                        }
                    }
                    .padding(.bottom, OPSStyle.Layout.spacing4)
                }

                // Submission blocker message
                if !selectedExpensesWithIssues.isEmpty {
                    let issueCount = selectedExpensesWithIssues.count
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text("\(issueCount) expense\(issueCount == 1 ? " is" : "s are") missing required fields")
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing2)
                }

                // Submit button
                Button {
                    isSubmitting = true
                    showSubmitSelectionSheet = false
                    submitExpensesForReview()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        Text("SUBMIT \(selectedExpenseIdsForSubmit.count) EXPENSE\(selectedExpenseIdsForSubmit.count == 1 ? "" : "S")")
                            .font(OPSStyle.Typography.bodyBold)
                    }
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(canSubmitSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.3))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(!canSubmitSelected)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing4)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Expenses List

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
                withAnimation(OPSStyle.Animation.smooth) {
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
                withAnimation(OPSStyle.Animation.smooth) {
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
            onTap: { editingExpense = expense },
            onEdit: {
                let status = ExpenseStatus(rawValue: expense.status) ?? .draft
                if status == .submitted && !hideEditWarning {
                    pendingEditExpense = expense
                    showEditWarning = true
                } else {
                    editingExpense = expense
                }
            },
            onSwipeRight: {
                if expense.status == ExpenseStatus.draft.rawValue {
                    Task { await viewModel.submitExpense(expense.id) }
                }
            },
            onSwipeLeft: {
                let status = ExpenseStatus(rawValue: expense.status)
                // Only allow deletion of draft and rejected expenses — not submitted, approved, or reimbursed
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
                                    ? OPSStyle.Colors.primaryAccent.opacity(0.2)
                                    : OPSStyle.Colors.cardBackgroundDark
                                )
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
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
