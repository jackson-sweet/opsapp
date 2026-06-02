//
//  ExpensesListView.swift
//  OPS
//
//  Admin expense review hub — period filter, hero summary,
//  full-width batch rows, tab toggle (Needs Review / History).
//

import SwiftUI
import SwiftData

struct ExpensesListView: View {
    var embedded: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel = ExpenseViewModel()
    @EnvironmentObject private var dataController: DataController
    @Query private var teamMembers: [TeamMember]

    @State private var selectedTab: ReviewTab = .needsReview
    @State private var selectedPeriod: String = ""
    @State private var availablePeriods: [String] = []
    @State private var showExpenseSettings = false
    @State private var showAddExpense = false
    @State private var hasAppeared = false

    enum ReviewTab: String, CaseIterable {
        case needsReview = "NEEDS REVIEW"
        case history = "HISTORY"
    }

    // MARK: - Period Filtering

    private var batchesForPeriod: [ExpenseBatchDTO] {
        viewModel.reviewBatches.filter { batch in
            // Filling envelopes are peek-only and have no iOS peek surface —
            // exclude them from the review hub, hero totals, and period pills.
            guard batchStatus(batch) != .open else { return false }
            guard !selectedPeriod.isEmpty else { return true }
            return periodKey(for: batch) == selectedPeriod
        }
    }

    // MARK: - Tab Sections

    private var needsReviewBatches: [ExpenseBatchDTO] {
        batchesForPeriod.filter { batchStatus($0).needsReview }
    }

    private var autoApprovedBatches: [ExpenseBatchDTO] {
        batchesForPeriod.filter { batchStatus($0) == .autoApproved }
    }

    private var approvedBatches: [ExpenseBatchDTO] {
        batchesForPeriod.filter {
            let s = batchStatus($0)
            return s == .approved || s == .partiallyApproved
        }
    }

    private var rejectedBatches: [ExpenseBatchDTO] {
        batchesForPeriod.filter { batchStatus($0) == .rejected }
    }

    // MARK: - Hero Summary

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
            if !embedded {
                OPSStyle.Colors.background.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if !embedded { header }
                periodFilterPills
                heroSummaryCard
                tabToggle
                batchList
            }

            // FAB — hidden when embedded in Books (global FAB handles creation),
            // matching InvoicesListView / EstimatesListView.
            if !embedded {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        addExpenseFAB
                            .padding(.trailing, OPSStyle.Layout.spacing3)
                            .padding(.bottom, OPSStyle.Layout.spacing3)
                    }
                }
            }
        }
        .trackScreen("Expenses")
        // Refresh review batches when an expense is created/submitted anywhere
        // (e.g. the global FAB), since that flow no longer shares this model.
        .onReceive(NotificationCenter.default.publisher(for: .opsExpensesDidChange)) { _ in
            Task { await viewModel.loadBatchesForReview() }
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showExpenseSettings) {
            ExpenseSettingsView(viewModel: viewModel)
                .environmentObject(dataController)
        }
        .sheet(isPresented: $showAddExpense) {
            ExpenseFormSheet(viewModel: viewModel)
                .environmentObject(dataController)
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
                await viewModel.loadBatchesForReview()
                computeAvailablePeriods()
                hasAppeared = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: OPSStyle.Icons.chevronLeft)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)

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
            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2_5)
    }

    // MARK: - Period Filter Pills

    private var periodFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                periodPill(label: "ALL", key: "")

                ForEach(availablePeriods, id: \.self) { period in
                    periodPill(label: periodDisplayLabel(period), key: period)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    private func periodPill(label: String, key: String) -> some View {
        let isSelected = selectedPeriod == key
        return Button {
            withAnimation(OPSStyle.Animation.fast) {
                selectedPeriod = key
            }
        } label: {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(isSelected ? OPSStyle.Colors.primaryAccent.opacity(0.25) : OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Hero Summary Card

    private var heroSummaryCard: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CREW EXPENSES")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(totalCrewExpenses, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        legendDot(color: OPSStyle.Colors.successStatus, label: "APPROVED")
                        legendDot(color: OPSStyle.Colors.primaryAccent, label: "PENDING")
                    }
                }
            }

            // Animated progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(OPSStyle.Colors.successStatus)
                        .frame(width: geometry.size.width * approvedFraction, height: 6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: approvedFraction)
                }
            }
            .frame(height: 6)

            HStack {
                Text(approvedTotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.successStatus)
                    .contentTransition(.numericText())
                Text("approved")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
                Text(pendingTotal, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .contentTransition(.numericText())
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
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    // MARK: - Tab Toggle

    private var tabToggle: some View {
        HStack(spacing: 0) {
            ForEach(ReviewTab.allCases, id: \.self) { tab in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
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
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    // MARK: - Batch List

    private var batchList: some View {
        // Embedded in Books renders inline so the Books page owns the single
        // scroll; standalone keeps its own ScrollView.
        Group {
            if embedded {
                batchListContent
            } else {
                ScrollView { batchListContent }
            }
        }
    }

    private var batchListContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            switch selectedTab {
            case .needsReview:
                needsReviewContent
            case .history:
                historyContent
            }
        }
        .padding(.top, OPSStyle.Layout.spacing3)
        // Standalone clears the in-view FAB + tab bar; embedded only needs rhythm.
        .padding(.bottom, embedded
                 ? OPSStyle.Layout.spacing4
                 : OPSStyle.Layout.touchTargetLarge + OPSStyle.Layout.spacing5 + OPSStyle.Layout.spacing4)
    }

    // MARK: - Needs Review Content

    private var needsReviewContent: some View {
        Group {
            if needsReviewBatches.isEmpty {
                emptyState
            } else {
                batchSection(
                    title: "\(needsReviewBatches.count) NEED REVIEW",
                    batches: needsReviewBatches
                )
            }
        }
    }

    // MARK: - History Content

    private var historyContent: some View {
        Group {
            if autoApprovedBatches.isEmpty && approvedBatches.isEmpty && rejectedBatches.isEmpty {
                emptyState
            } else {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    if !autoApprovedBatches.isEmpty {
                        batchSection(title: "\(autoApprovedBatches.count) AUTO-APPROVED", batches: autoApprovedBatches)
                    }
                    if !approvedBatches.isEmpty {
                        batchSection(title: "APPROVED", batches: approvedBatches)
                    }
                    if !rejectedBatches.isEmpty {
                        batchSection(title: "REJECTED", batches: rejectedBatches)
                    }
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
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(Array(batches.enumerated()), id: \.element.id) { index, batch in
                    NavigationLink(destination: ExpenseBatchDetailView(batch: batch, viewModel: viewModel)) {
                        batchRow(batch)
                    }
                    .buttonStyle(BatchRowButtonStyle())
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 8)
                    .animation(
                        reduceMotion
                            ? .none
                            : OPSStyle.Animation.fast.delay(Double(index) * 0.05),
                        value: hasAppeared
                    )
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
    }

    // MARK: - Batch Row

    private func batchRow(_ batch: ExpenseBatchDTO) -> some View {
        let status = batchStatus(batch)
        let statusColor = batchStatusColor(status)
        let crewName = resolveCrewName(batch.submittedBy)

        return HStack(spacing: OPSStyle.Layout.spacing2) {
            // Crew avatar
            Circle()
                .fill(OPSStyle.Colors.primaryAccent.opacity(0.3))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(crewInitials(batch.submittedBy))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                )

            // Info column
            VStack(alignment: .leading, spacing: 2) {
                Text(crewName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Text(batch.batchNumber)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            // Right column
            VStack(alignment: .trailing, spacing: 2) {
                Text(batch.totalAmount ?? 0, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)
                    Text(status.displayName)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(statusColor)

                    Text("\u{00B7}")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Text(relativeTime(batch.createdAt))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - FAB

    private var addExpenseFAB: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showAddExpense = true
        } label: {
            Image(systemName: OPSStyle.Icons.plus)
                .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .medium))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: OPSStyle.Layout.touchTargetLarge, height: OPSStyle.Layout.touchTargetLarge)
                .background(OPSStyle.Colors.primaryAccent)
                .clipShape(Circle())
        }
        .accessibilityLabel("New Expense")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("NO BATCHES TO REVIEW")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text("Submitted expense batches will appear here.")
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
        case .open:              return OPSStyle.Colors.tertiaryText
        case .pendingReview:     return OPSStyle.Colors.warningStatus
        case .submitted:         return OPSStyle.Colors.primaryAccent
        case .approved:          return OPSStyle.Colors.successStatus
        case .partiallyApproved: return OPSStyle.Colors.warningStatus
        case .rejected:          return OPSStyle.Colors.errorStatus
        case .autoApproved:      return OPSStyle.Colors.successStatus
        }
    }

    private func resolveCrewName(_ userId: String?) -> String {
        guard let userId = userId else { return "UNASSIGNED" }
        if let member = teamMembers.first(where: { $0.id == userId }) {
            return member.fullName.uppercased()
        }
        return userId.prefix(8).uppercased()
    }

    private func crewInitials(_ userId: String?) -> String {
        guard let userId = userId else { return "?" }
        if let member = teamMembers.first(where: { $0.id == userId }) {
            return member.initials
        }
        return String(userId.prefix(2)).uppercased()
    }

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

    private func computeAvailablePeriods() {
        var keys = Set<String>()
        for batch in viewModel.reviewBatches {
            guard batchStatus(batch) != .open else { continue }   // filling envelopes aren't shown here
            let key = periodKey(for: batch)
            if !key.isEmpty { keys.insert(key) }
        }
        availablePeriods = keys.sorted(by: >)
    }

    private func periodDisplayLabel(_ period: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        guard let date = fmt.date(from: period) else { return period.uppercased() }
        let display = DateFormatter()
        display.dateFormat = "MMM yyyy"
        return display.string(from: date).uppercased()
    }

    private func relativeTime(_ dateString: String) -> String {
        let isoDate = ISO8601DateFormatter()
        isoDate.formatOptions = [.withFullDate]
        let isoFull = ISO8601DateFormatter()
        var date: Date?
        date = isoDate.date(from: dateString)
        if date == nil { date = isoFull.date(from: dateString) }
        guard let resolved = date else { return "" }

        let interval = Date().timeIntervalSince(resolved)
        let hours = Int(interval / 3600)
        if hours < 1 { return "now" }
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 30 { return "\(days)d" }
        let months = days / 30
        return "\(months)mo"
    }
}

// MARK: - Batch Row Button Style

private struct BatchRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(OPSStyle.Animation.faster, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }
}

// MARK: - Hashable Conformance

extension ExpenseDTO: Hashable {
    static func == (lhs: ExpenseDTO, rhs: ExpenseDTO) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
