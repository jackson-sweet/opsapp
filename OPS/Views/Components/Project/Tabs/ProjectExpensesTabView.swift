//
//  ProjectExpensesTabView.swift
//  OPS
//
//  Integrates the existing expense system filtered to this project.
//  Uses ExpenseRepository.fetchByProject() and existing ExpenseCard component.
//

import SwiftUI

struct ProjectExpensesTabView: View {
    @ObservedObject var viewModel: ProjectDetailsViewModel
    @ObservedObject var expenseViewModel: ExpenseViewModel
    let onAddExpense: () -> Void
    let onTapExpense: (ExpenseDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Running total card (hidden when no expenses)
            if !viewModel.projectExpenses.isEmpty {
                totalCard
            }

            // Expense list
            if viewModel.isLoadingExpenses {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    Spacer()
                }
                .padding(.vertical, OPSStyle.Layout.spacing4)
            } else if !viewModel.projectExpenses.isEmpty {
                expenseList
            }

            // Add expense button
            Button(action: onAddExpense) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "plus")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    Text("ADD EXPENSE")
                        .font(OPSStyle.Typography.captionBold)
                    Spacer()
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(14)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            Spacer()
                .frame(height: 200)
        }
        .padding(.top, OPSStyle.Layout.spacing3)
        .task {
            await viewModel.loadExpenses()
        }
    }

    // MARK: - Total Card

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(formatCurrency(viewModel.expenseTotal))
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.accountingCost)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("No expenses for this project")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("Add your first expense to start tracking costs")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }

    // MARK: - Expense List

    private var expenseList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.projectExpenses, id: \.id) { expense in
                let category = expenseViewModel.categories.first { $0.id == expense.categoryId }

                ExpenseCard(
                    expense: expense,
                    categoryName: category?.name,
                    categoryIcon: category?.icon,
                    submittedByName: viewModel.submitterName(for: expense),
                    canDelete: viewModel.canDeleteExpense(expense),
                    onTap: { onTapExpense(expense) },
                    onSwipeLeft: {
                        Task { await expenseViewModel.deleteExpense(expense.id) }
                    }
                )

                if expense.id != viewModel.projectExpenses.last?.id {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorderSubtle)
                        .frame(height: 1)
                }
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Helpers

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}
