//
//  ExpensesListView.swift
//  OPS
//
//  Review Expenses hub — segmented picker for Review / History tabs,
//  settings gear in header, expense settings link at bottom.
//

import SwiftUI

struct ExpensesListView: View {
    var embedded: Bool = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ExpenseViewModel()
    @EnvironmentObject private var dataController: DataController
    @State private var selectedTab: ReviewTab = .review
    @State private var showExpenseSettings = false

    enum ReviewTab: String, CaseIterable {
        case review = "REVIEW"
        case history = "HISTORY"
    }

    // MARK: - Filtered Batches

    private var selectedPeriodBatches: [ExpenseBatchDTO] {
        viewModel.reviewBatches
    }

    private var needsReviewBatches: [ExpenseBatchDTO] {
        selectedPeriodBatches.filter { batchStatus($0).needsReview }
    }

    private var autoApprovedBatches: [ExpenseBatchDTO] {
        selectedPeriodBatches.filter { batchStatus($0) == .autoApproved }
    }

    private var approvedBatches: [ExpenseBatchDTO] {
        selectedPeriodBatches.filter {
            let s = batchStatus($0)
            return s == .approved || s == .partiallyApproved
        }
    }

    private var rejectedBatches: [ExpenseBatchDTO] {
        selectedPeriodBatches.filter { batchStatus($0) == .rejected }
    }

    // Hero summary
    private var totalCrewExpenses: Double {
        selectedPeriodBatches.compactMap(\.totalAmount).reduce(0, +)
    }

    private var approvedTotal: Double {
        selectedPeriodBatches.compactMap(\.approvedAmount).reduce(0, +)
    }

    private var pendingTotal: Double {
        max(totalCrewExpenses - approvedTotal, 0)
    }

    private var approvedFraction: Double {
        guard totalCrewExpenses > 0 else { return 0 }
        return min(approvedTotal / totalCrewExpenses, 1.0)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if !embedded {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
            }

            VStack(spacing: 0) {
                // Header with gear button
                if !embedded {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: OPSStyle.Icons.chevronLeft)
                                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .frame(width: 44, height: 44)

                        Spacer()

                        Text("REVIEW EXPENSES")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        Button(action: { showExpenseSettings = true }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                // Segmented picker
                tabToggle
                    .padding(.top, 16)

                // Hero summary
                heroSummaryBar
                    .padding(.top, 12)

                // Tab content
                ScrollView {
                    VStack(spacing: 20) {
                        switch selectedTab {
                        case .review:
                            reviewContent
                        case .history:
                            historyContent
                        }

                        // Expense Settings at bottom
                        expenseSettingsFooter
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .trackScreen("Expenses")
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showExpenseSettings) {
            ExpenseSettingsView(viewModel: viewModel)
                .environmentObject(dataController)
        }
        .task {
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                viewModel.setup(companyId: companyId)
                await viewModel.loadBatchesForReview()
            }
        }
    }

    // MARK: - Tab Toggle

    private var tabToggle: some View {
        HStack(spacing: 0) {
            ForEach(ReviewTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(OPSStyle.Animation.fast) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: OPSStyle.Layout.spacing1) {
                        Text(tab.rawValue)
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(
                                selectedTab == tab
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.tertiaryText
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OPSStyle.Layout.spacing2)

                        Rectangle()
                            .fill(
                                selectedTab == tab
                                    ? OPSStyle.Colors.primaryAccent
                                    : Color.clear
                            )
                            .frame(height: 2)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Hero Summary Bar

    private var heroSummaryBar: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CREW EXPENSES")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(totalCrewExpenses, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        legendDot(color: OPSStyle.Colors.successStatus, label: "APPROVED")
                        legendDot(color: OPSStyle.Colors.primaryAccent, label: "PENDING")
                    }
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(OPSStyle.Colors.successStatus)
                        .frame(width: geometry.size.width * approvedFraction, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text(approvedTotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.successStatus)
                Text("approved")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                Text(pendingTotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text("pending")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, 20)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Review Content

    private var reviewContent: some View {
        VStack(spacing: 20) {
            if needsReviewBatches.isEmpty && autoApprovedBatches.isEmpty {
                reviewEmptyState
            } else {
                if !needsReviewBatches.isEmpty {
                    batchSection(
                        title: "\(needsReviewBatches.count) NEED REVIEW",
                        batches: needsReviewBatches
                    )
                }

                if !autoApprovedBatches.isEmpty {
                    batchSection(
                        title: "\(autoApprovedBatches.count) AUTO-APPROVED",
                        batches: autoApprovedBatches
                    )
                }
            }
        }
    }

    // MARK: - History Content

    private var historyContent: some View {
        VStack(spacing: 20) {
            if approvedBatches.isEmpty && rejectedBatches.isEmpty {
                reviewEmptyState
            } else {
                if !approvedBatches.isEmpty {
                    batchSection(
                        title: "APPROVED",
                        batches: approvedBatches
                    )
                }

                if !rejectedBatches.isEmpty {
                    batchSection(
                        title: "REJECTED",
                        batches: rejectedBatches
                    )
                }
            }
        }
    }

    // MARK: - Batch Section

    private func batchSection(title: String, batches: [ExpenseBatchDTO]) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 20)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2),
                    GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2)
                ],
                spacing: OPSStyle.Layout.spacing2
            ) {
                ForEach(batches) { batch in
                    NavigationLink(destination: ExpenseBatchReviewView(batch: batch, viewModel: viewModel)) {
                        batchCard(batch)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Batch Card

    private func batchCard(_ batch: ExpenseBatchDTO) -> some View {
        let status = batchStatus(batch)
        let statusColor = batchStatusColor(status)

        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(batch.batchNumber)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            Text(batch.totalAmount ?? 0, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

            if let start = batch.periodStart {
                Text(formatPeriodShort(start))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(status.displayName)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(statusColor)
            }

            if let amendment = batch.amendmentNumber, amendment > 0 {
                Text("AMENDMENT \(amendment)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Expense Settings Footer

    private var expenseSettingsFooter: some View {
        Button {
            showExpenseSettings = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "gearshape")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 28, alignment: .center)

                Text("Expense Settings")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Empty State

    private var reviewEmptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("NO INVOICES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("No expense invoices to show.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func batchStatus(_ batch: ExpenseBatchDTO) -> ExpenseBatchStatus {
        ExpenseBatchStatus(rawValue: batch.status) ?? .pendingReview
    }

    private func batchStatusColor(_ status: ExpenseBatchStatus) -> Color {
        switch status {
        case .pendingReview:     return OPSStyle.Colors.warningStatus
        case .submitted:         return OPSStyle.Colors.primaryAccent
        case .approved:          return OPSStyle.Colors.successStatus
        case .partiallyApproved: return OPSStyle.Colors.warningStatus
        case .rejected:          return OPSStyle.Colors.errorStatus
        case .autoApproved:      return OPSStyle.Colors.successStatus
        }
    }

    private func formatPeriodShort(_ dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let isoFull = ISO8601DateFormatter()

        var date: Date?
        date = iso.date(from: dateString)
        if date == nil { date = isoFull.date(from: dateString) }
        guard let resolved = date else { return dateString }

        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: resolved)
    }
}

// MARK: - Hashable Conformance

extension ExpenseDTO: Hashable {
    static func == (lhs: ExpenseDTO, rhs: ExpenseDTO) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
