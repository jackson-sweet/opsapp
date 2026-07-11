//
//  ExpenseBucketQueue.swift
//  OPS
//
//  The console's working queue — renders the selected bucket as
//  hairline-separated ledger rows (the Money-tab row family), grouped by
//  person where the work is person-shaped (TO REVIEW / TO PAY), month-grouped
//  where it's reference (PAID). WITH CREW rides underneath every bucket as a
//  quiet expandable footer: findable, never in the way. Pure presentation —
//  the wrapper resolves names, owns navigation, and executes actions.
//

import SwiftUI

struct ExpenseBucketQueue: View {
    let bucket: ExpenseBucket
    let split: ExpenseBucketSplit
    let lineStats: [String: ExpenseBatchLineStats]
    let autoSubmitGraceDays: Int
    let canApprove: Bool
    let nameFor: (String?) -> String
    let onOpen: (ExpenseBatchDTO) -> Void
    let onApprove: (ExpenseBatchDTO) -> Void
    let onPay: (ExpenseBatchDTO) -> Void
    let onApproveGroup: (ExpensePersonGroup) -> Void
    let onPayGroup: (ExpensePersonGroup) -> Void

    /// Snapshot/preview support — start WITH CREW expanded.
    var initialCrewExpanded: Bool = false

    @State private var openRowID: String?
    @State private var crewExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            switch bucket {
            case .review: reviewQueue
            case .pay:    payQueue
            case .paid:   paidLedger
            case .crew:   EmptyView()   // crew renders as the footer below, never a primary queue
            }

            crewFooter
        }
        .onAppear { crewExpanded = initialCrewExpanded }
        .onChange(of: bucket) { _, _ in openRowID = nil }
    }

    // MARK: - TO REVIEW

    @ViewBuilder
    private var reviewQueue: some View {
        if split.review.isEmpty {
            emptyState(hero: "$0", label: "NOTHING WAITING ON YOU")
        } else {
            ForEach(ExpenseBuckets.reviewPersonGroups(split.review)) { group in
                personHeader(
                    group,
                    subline: sinceLabel(group),
                    actionLabel: "APPROVE \(cleanBatches(in: group).count)",
                    actionEnabled: canApprove && !cleanBatches(in: group).isEmpty,
                    action: { onApproveGroup(group) }
                )
                ForEach(group.batches) { batch in
                    reviewRow(batch)
                }
            }
        }
    }

    private func reviewRow(_ batch: ExpenseBatchDTO) -> some View {
        let stats = lineStats[batch.id]
        let flagged = stats?.flagged ?? 0
        return BooksSwipeRow(
            rowID: "batch-\(batch.id)",
            leading: (canApprove && flagged == 0) ? [approveAction(batch)] : [],
            openRowID: $openRowID
        ) {
            batchRow(
                primary: periodLabel(batch),
                amount: batch.totalAmount ?? 0,
                amountColor: OPSStyle.Colors.text
            ) {
                metaText(batch.batchNumber)
                if let count = stats?.count, count > 0 {
                    metaText("\(count) LINE\(count == 1 ? "" : "S")")
                }
                if flagged > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8))
                        Text("\(flagged)")
                            .font(.custom("JetBrainsMono-Medium", size: 9.5))
                    }
                    .foregroundColor(OPSStyle.Colors.tan)
                }
            } onTap: {
                onOpen(batch)
            }
        }
    }

    // MARK: - TO PAY

    @ViewBuilder
    private var payQueue: some View {
        if split.pay.isEmpty {
            emptyState(hero: "$0", label: "NOBODY OWED")
        } else {
            ForEach(ExpenseBuckets.payPersonGroups(split.pay)) { group in
                personHeader(
                    group,
                    subline: "\(group.batches.count) BATCH\(group.batches.count == 1 ? "" : "ES")",
                    actionLabel: "PAY \(group.batches.count)",
                    actionEnabled: canApprove,
                    action: { onPayGroup(group) }
                )
                ForEach(group.batches) { batch in
                    payRow(batch)
                }
            }
        }
    }

    private func payRow(_ batch: ExpenseBatchDTO) -> some View {
        let status = ExpenseBatchStatus(rawValue: batch.status)
        let owed = ExpenseBuckets.owedAmount(batch)
        return BooksSwipeRow(
            rowID: "batch-\(batch.id)",
            leading: canApprove ? [payAction(batch)] : [],
            openRowID: $openRowID
        ) {
            batchRow(
                primary: periodLabel(batch),
                amount: owed,
                amountColor: OPSStyle.Colors.text
            ) {
                metaText(batch.batchNumber)
                if status == .autoApproved {
                    BooksPillView(pill: BooksPill(text: "AUTO", color: OPSStyle.Colors.secondaryText))
                }
                if status == .partiallyApproved {
                    BooksPillView(pill: BooksPill(text: "PARTIAL", color: OPSStyle.Colors.tan))
                    metaText("OF \(BooksFormat.currency(batch.totalAmount ?? 0))")
                }
            } onTap: {
                onOpen(batch)
            }
        }
    }

    // MARK: - PAID

    @ViewBuilder
    private var paidLedger: some View {
        if split.paid.isEmpty {
            emptyState(hero: "—", label: "NO PAYOUTS RECORDED")
        } else {
            ForEach(ExpenseBuckets.paidSections(split.paid)) { section in
                monthHeader(section.monthKey)
                ForEach(section.batches) { batch in
                    paidRow(batch)
                }
            }
        }
    }

    private func paidRow(_ batch: ExpenseBatchDTO) -> some View {
        batchRow(
            primary: nameFor(batch.submittedBy).uppercased(),
            amount: ExpenseBuckets.owedAmount(batch),
            amountColor: OPSStyle.Colors.olive
        ) {
            metaText(batch.batchNumber)
            if let paidAt = ExpenseBuckets.parseDate(batch.paidAt) {
                metaText("PAID \(Self.shortDate.string(from: paidAt).uppercased())")
            }
        } onTap: {
            onOpen(batch)
        }
    }

    // MARK: - WITH CREW footer

    @ViewBuilder
    private var crewFooter: some View {
        if split.crewCount > 0 {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(reduceMotion ? nil : OPSStyle.Animation.fast) {
                    crewExpanded.toggle()
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text("//")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.textMute)
                    Text("WITH CREW")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .tracking(1.2)
                    Text(crewSummary)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Image(systemName: OPSStyle.Icons.chevronDown)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .rotationEffect(.degrees(crewExpanded ? 180 : 0))
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, OPSStyle.Layout.spacing2)

            if crewExpanded {
                ForEach(split.crewFilling) { batch in
                    crewFillingRow(batch)
                }
                ForEach(split.crewReturned) { batch in
                    crewReturnedRow(batch)
                }
            }
        }
    }

    private var crewSummary: String {
        var parts: [String] = []
        if !split.crewFilling.isEmpty { parts.append("\(split.crewFilling.count) FILLING") }
        if !split.crewReturned.isEmpty { parts.append("\(split.crewReturned.count) SENT BACK") }
        return parts.joined(separator: " · ")
    }

    private func crewFillingRow(_ batch: ExpenseBatchDTO) -> some View {
        batchRow(
            primary: nameFor(batch.submittedBy).uppercased(),
            amount: batch.totalAmount ?? 0,
            amountColor: OPSStyle.Colors.text3
        ) {
            metaText(periodLabel(batch))
            if let sendDate = ExpenseBuckets.autoSendDate(batch, graceDays: autoSubmitGraceDays) {
                metaText(
                    sendDate <= Date()
                        ? "SENDS TODAY"
                        : "AUTO-SENDS \(Self.shortDate.string(from: sendDate).uppercased())"
                )
            } else if batch.scopeProjectId != nil {
                metaText("SENDS AFTER THE JOB WRAPS")
            }
        } onTap: {
            onOpen(batch)
        }
    }

    private func crewReturnedRow(_ batch: ExpenseBatchDTO) -> some View {
        let linesLeft = lineStats[batch.id]?.count ?? 0
        return batchRow(
            primary: nameFor(batch.submittedBy).uppercased(),
            amount: batch.totalAmount ?? 0,
            amountColor: OPSStyle.Colors.text3
        ) {
            metaText(batch.batchNumber)
            Text("SENT BACK · \(linesLeft) LEFT")
                .font(.custom("JetBrainsMono-Regular", size: 9.5))
                .foregroundColor(OPSStyle.Colors.rose)
        } onTap: {
            onOpen(batch)
        }
    }

    // MARK: - Shared row chrome (Money-tab ledger family)

    /// Two-line hairline row: primary + mono amount up top, metadata below.
    private func batchRow(
        primary: String,
        amount: Double,
        amountColor: Color,
        @ViewBuilder metadata: () -> some View,
        onTap: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2_5) {
                Text(primary)
                    .font(.custom("Mohave-Medium", size: 15))
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(BooksFormat.currency(amount))
                    .font(.custom("JetBrainsMono-Medium", size: 15))
                    .foregroundColor(amountColor)
                    .monospacedDigit()
            }
            HStack(spacing: OPSStyle.Layout.spacing2) {
                metadata()
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OPSStyle.Colors.lineSoft)
                .frame(height: 1)
        }
    }

    private func metaText(_ text: String) -> some View {
        Text(text)
            .font(.custom("JetBrainsMono-Regular", size: 9.5))
            .foregroundColor(OPSStyle.Colors.text3)
            .lineLimit(1)
    }

    // MARK: - Person header

    private func personHeader(
        _ group: ExpensePersonGroup,
        subline: String,
        actionLabel: String,
        actionEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nameFor(group.userId == "unknown" ? nil : group.userId).uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(subline)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("·")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.textMute)
                    Text(BooksFormat.currency(group.total))
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .monospacedDigit()
                }
            }

            Spacer()

            if actionEnabled {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    action()
                } label: {
                    Text(actionLabel)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.chipRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing1)
    }

    /// Clean = no flagged lines; bulk approve never touches flagged batches.
    private func cleanBatches(in group: ExpensePersonGroup) -> [ExpenseBatchDTO] {
        group.batches.filter { (lineStats[$0.id]?.flagged ?? 0) == 0 }
    }

    private func sinceLabel(_ group: ExpensePersonGroup) -> String {
        let oldest = group.batches.compactMap(\.periodStart).min()
        guard let oldest, let date = ExpenseBuckets.parseDate(oldest) else {
            return "\(group.batches.count) BATCH\(group.batches.count == 1 ? "" : "ES")"
        }
        return "SINCE \(Self.shortDate.string(from: date).uppercased())"
    }

    // MARK: - Month header (PAID)

    private func monthHeader(_ monthKey: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("//")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.textMute)
            Text(monthLabel(monthKey))
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .tracking(1.2)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing1)
    }

    private func monthLabel(_ key: String) -> String {
        guard let date = Self.monthKeyParser.date(from: key) else { return key }
        return Self.monthDisplay.string(from: date).uppercased()
    }

    // MARK: - Swipe actions

    private func approveAction(_ batch: ExpenseBatchDTO) -> BooksRowAction {
        BooksRowAction(
            id: "approve",
            label: "APPROVE",
            menuTitle: "Approve Batch",
            icon: "checkmark.seal",
            tone: OPSStyle.Colors.olive
        ) { onApprove(batch) }
    }

    private func payAction(_ batch: ExpenseBatchDTO) -> BooksRowAction {
        BooksRowAction(
            id: "pay",
            label: "PAID",
            menuTitle: "Mark Paid",
            icon: "banknote",
            tone: OPSStyle.Colors.olive
        ) { onPay(batch) }
    }

    // MARK: - Empty state

    private func emptyState(hero: String, label: String) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text(hero)
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.text3)
                .monospacedDigit()
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text("//")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .tracking(1.6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }

    // MARK: - Period + date formatting

    /// "JUN 1–30" within a month, "JUN 28 – JUL 11" across months.
    private func periodLabel(_ batch: ExpenseBatchDTO) -> String {
        guard let start = ExpenseBuckets.parseDate(batch.periodStart),
              let end = ExpenseBuckets.parseDate(batch.periodEnd) else {
            return batch.batchNumber
        }
        let calendar = Calendar.current
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            let day = calendar.component(.day, from: end)
            return "\(Self.shortDate.string(from: start))–\(day)".uppercased()
        }
        return "\(Self.shortDate.string(from: start)) – \(Self.shortDate.string(from: end))".uppercased()
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let monthKeyParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let monthDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}
