//
//  ExpenseReviewDashboardView.swift
//  OPS
//
//  Admin expense review dashboard — two-tab toggle (Needs Review / History),
//  period picker, hero summary bar, and two-column invoice grid.
//

import SwiftUI

struct ExpenseReviewDashboardView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var dataController: DataController
    @State private var selectedTab: ReviewTab = .needsReview
    @State private var selectedPeriod: String = ""
    @State private var availablePeriods: [String] = []

    enum ReviewTab: String, CaseIterable {
        case needsReview = "NEEDS REVIEW"
        case history     = "HISTORY"
    }

    // MARK: - Filtered Batches

    private var batchesForPeriod: [ExpenseBatchDTO] {
        viewModel.reviewBatches.filter { batch in
            guard !selectedPeriod.isEmpty else { return true }
            return periodKey(for: batch) == selectedPeriod
        }
    }

    // Needs Review tab sections
    private var needsReviewBatches: [ExpenseBatchDTO] {
        batchesForPeriod.filter { batchStatus($0).needsReview }
    }

    private var autoApprovedBatches: [ExpenseBatchDTO] {
        batchesForPeriod.filter { batchStatus($0) == .autoApproved }
    }

    // History tab sections
    private var approvedBatches: [ExpenseBatchDTO] {
        batchesForPeriod.filter {
            let s = batchStatus($0)
            return s == .approved || s == .partiallyApproved
        }
    }

    private var rejectedBatches: [ExpenseBatchDTO] {
        batchesForPeriod.filter { batchStatus($0) == .rejected }
    }

    // Hero summary values
    private var totalCrewExpenses: Double {
        batchesForPeriod.compactMap(\.totalAmount).reduce(0, +)
    }

    private var approvedTotal: Double {
        batchesForPeriod.compactMap(\.approvedAmount).reduce(0, +)
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
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                tabToggle
                periodPicker
                heroSummaryBar

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        switch selectedTab {
                        case .needsReview:
                            needsReviewContent
                        case .history:
                            historyContent
                        }
                    }
                    .padding(.top, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing5)
                }
            }
        }
        .trackScreen("ExpenseReview")
        .task {
            await viewModel.loadBatchesForReview()
            computeAvailablePeriods()
        }
    }

    // MARK: - Tab Toggle (Underline Segmented Control)

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
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Period Picker (Horizontal Pills)

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(availablePeriods, id: \.self) { period in
                    Button {
                        withAnimation(OPSStyle.Animation.fast) {
                            selectedPeriod = period
                        }
                    } label: {
                        Text(periodDisplayLabel(period))
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(
                                selectedPeriod == period
                                    ? OPSStyle.Colors.primaryText
                                    : OPSStyle.Colors.secondaryText
                            )
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .background(
                                selectedPeriod == period
                                    ? OPSStyle.Colors.primaryAccent.opacity(0.25)
                                    : OPSStyle.Colors.cardBackgroundDark
                            )
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(
                                        selectedPeriod == period
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
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
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

            // Progress bar
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
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
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

    // MARK: - Needs Review Content

    private var needsReviewContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            if needsReviewBatches.isEmpty && autoApprovedBatches.isEmpty {
                emptyState
            } else {
                // Needs Review section
                if !needsReviewBatches.isEmpty {
                    batchSection(
                        title: "\(needsReviewBatches.count) NEED REVIEW",
                        batches: needsReviewBatches
                    )
                }

                // Auto-Approved section
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
        VStack(spacing: OPSStyle.Layout.spacing3) {
            if approvedBatches.isEmpty && rejectedBatches.isEmpty {
                emptyState
            } else {
                // Approved section
                if !approvedBatches.isEmpty {
                    batchSection(
                        title: "APPROVED",
                        batches: approvedBatches
                    )
                }

                // Rejected section
                if !rejectedBatches.isEmpty {
                    batchSection(
                        title: "REJECTED",
                        batches: rejectedBatches
                    )
                }
            }
        }
    }

    // MARK: - Batch Section (Header + Grid)

    private func batchSection(title: String, batches: [ExpenseBatchDTO]) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader(title)

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
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Batch Card (Grid Cell)

    private func batchCard(_ batch: ExpenseBatchDTO) -> some View {
        let status = batchStatus(batch)
        let statusColor = batchStatusColor(status)

        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            // Batch number
            Text(batch.batchNumber)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            // Total amount
            Text(batch.totalAmount ?? 0, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

            // Period label
            if let start = batch.periodStart {
                Text(formatPeriodShort(start))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }

            // Status badge
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(status.displayName)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(statusColor)
            }

            // Amendment indicator
            if let amendment = batch.amendmentNumber, amendment > 0 {
                Text("AMENDMENT \(amendment)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("NO INVOICES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("No expense invoices for this period.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
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

    /// Extract yyyy-MM period key from a batch's periodStart
    private func periodKey(for batch: ExpenseBatchDTO) -> String {
        guard let start = batch.periodStart else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let isoFull = ISO8601DateFormatter()

        var date: Date?
        date = iso.date(from: start)
        if date == nil { date = isoFull.date(from: start) }
        guard let resolved = date else { return "" }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: resolved)
    }

    /// Compute available periods from loaded batches, sorted descending
    private func computeAvailablePeriods() {
        var keys = Set<String>()
        for batch in viewModel.reviewBatches {
            let key = periodKey(for: batch)
            if !key.isEmpty { keys.insert(key) }
        }
        let sorted = keys.sorted(by: >)
        availablePeriods = sorted

        // Default to most recent period
        if selectedPeriod.isEmpty, let first = sorted.first {
            selectedPeriod = first
        }
    }

    /// Convert "2026-03" to "MAR 2026"
    private func periodDisplayLabel(_ period: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        guard let date = fmt.date(from: period) else { return period.uppercased() }
        let display = DateFormatter()
        display.dateFormat = "MMM yyyy"
        return display.string(from: date).uppercased()
    }

    /// Format an ISO date string to short period label (e.g. "Mar 1 – Mar 31")
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
