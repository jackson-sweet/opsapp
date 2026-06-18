//
//  ExpenseCard.swift
//  OPS
//
//  Card for an expense line — merchant, amount, category, and a quiet line that
//  reads the line's state + its envelope phase ("filling" / "with the office" /
//  "approved" / "paid"). Swipe left to delete. No submit gesture — the server
//  files an added expense automatically.
//

import SwiftUI

struct ExpenseCard: View {
    let expense: ExpenseDTO
    let categoryName: String?
    let categoryIcon: String?
    /// The expense's envelope phase (nil when the line is a draft / unbatched or
    /// its batch isn't loaded on this surface). Drives the "filling" vs
    /// "with the office" distinction for a submitted line.
    var batchStatus: ExpenseBatchStatus?
    /// Resolved display name of whoever added the expense. Surfaced on shared
    /// surfaces (e.g. a project's expense list) where the line may belong to a
    /// teammate. Nil hides the attribution — used where the viewer is always the
    /// owner (My Expenses) or the name can't be resolved.
    var submittedByName: String?
    /// Whether the current user may delete this line (submitter or admin).
    /// Gates the swipe-to-delete affordance so we never reveal an action the
    /// server would reject. Defaults true for surfaces that only list a user's
    /// own expenses (e.g. My Expenses).
    var canDelete: Bool = true
    let onTap: () -> Void
    let onSwipeLeft: () -> Void

    @State private var dragOffset: CGFloat = 0

    init(
        expense: ExpenseDTO,
        categoryName: String?,
        categoryIcon: String?,
        batchStatus: ExpenseBatchStatus? = nil,
        submittedByName: String? = nil,
        canDelete: Bool = true,
        onTap: @escaping () -> Void,
        onSwipeLeft: @escaping () -> Void
    ) {
        self.expense = expense
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.batchStatus = batchStatus
        self.submittedByName = submittedByName
        self.canDelete = canDelete
        self.onTap = onTap
        self.onSwipeLeft = onSwipeLeft
    }

    private var swipeThreshold: CGFloat { 80 }

    private var expenseStatus: ExpenseStatus {
        ExpenseStatus(rawValue: expense.status) ?? .draft
    }

    /// Approved / reimbursed lines are locked — no delete. Also gated by the
    /// caller's `canDelete` (submitter or admin).
    private var canSwipeLeft: Bool {
        canDelete && expenseStatus != .approved && expenseStatus != .reimbursed
    }

    private var formattedDate: String {
        guard let dateString = expense.expenseDate ?? Optional(expense.createdAt) else {
            return ""
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: dateString) {
            let display = DateFormatter()
            display.dateFormat = "MMM d"
            return display.string(from: date)
        }
        // Fallback: try the full createdAt string
        let fallback = ISO8601DateFormatter()
        if let date = fallback.date(from: expense.createdAt) {
            let display = DateFormatter()
            display.dateFormat = "MMM d"
            return display.string(from: date)
        }
        return ""
    }

    var body: some View {
        ZStack {
            // Swipe-left reveal (DELETE) — the only swipe action.
            HStack {
                Spacer()
                Label("DELETE", systemImage: "trash.fill")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.trailing, OPSStyle.Layout.spacing3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.errorStatus)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .opacity(dragOffset < 0 ? Double(min(-dragOffset / swipeThreshold, 1)) : 0)

            // Card content
            cardContent
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Delete-only — ignore right swipes (no submit gesture).
                            // No reveal at all when the user can't delete this line.
                            dragOffset = canSwipeLeft ? min(0, value.translation.width) : 0
                        }
                        .onEnded { value in
                            if value.translation.width < -swipeThreshold && canSwipeLeft {
                                withAnimation(OPSStyle.Animation.faster) { dragOffset = 0 }
                                onSwipeLeft()
                            } else {
                                withAnimation(OPSStyle.Animation.faster) { dragOffset = 0 }
                            }
                        }
                )
        }
    }

    private var cardContent: some View {
        Button(action: { onTap() }) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                // Row 1: merchant name + amount
                HStack {
                    Text(expense.merchantName ?? "UNKNOWN MERCHANT")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(expense.amount, format: .currency(code: expense.currency ?? "USD").precision(.fractionLength(2)))
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                // Row 2: category icon + name, with the adder on the trailing edge
                // where a name is supplied (shared surfaces like a project list).
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    if let icon = categoryIcon, !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Text(categoryName ?? "UNCATEGORIZED")
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)

                    if let submittedByName, !submittedByName.isEmpty {
                        Spacer(minLength: OPSStyle.Layout.spacing2)
                        Image(systemName: OPSStyle.Icons.teamMember)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text(submittedByName)
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                // Row 3: quiet state + envelope phase, with the date.
                HStack {
                    phaseLine
                    Spacer()
                    Text(formattedDate)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface()
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var phaseLine: some View {
        let p = phase
        return HStack(spacing: OPSStyle.Layout.spacing1) {
            Circle()
                .fill(p.color)
                .frame(width: OPSStyle.Layout.Indicator.dotMD, height: OPSStyle.Layout.Indicator.dotMD)
            Text(p.text)
                .font(OPSStyle.Typography.smallCaption)
                .fontWeight(.medium)
                .foregroundColor(p.color)
        }
    }

    /// Quiet, sentence-case descriptor of where this line is in its journey.
    /// The line's own status carries most of it; the envelope phase distinguishes
    /// a filling envelope from one already handed to the office.
    private var phase: (text: String, color: Color) {
        switch expenseStatus {
        case .draft:      return ("unfinished", OPSStyle.Colors.tertiaryText)
        case .rejected:   return ("needs fix",  OPSStyle.Colors.errorStatus)
        case .approved:   return ("approved",   OPSStyle.Colors.successStatus)
        case .reimbursed: return ("paid",       OPSStyle.Colors.successStatus)
        case .submitted:
            switch batchStatus {
            case .some(.open):
                return ("filling", OPSStyle.Colors.tertiaryText)
            case .some(.pendingReview):
                return ("with the office", OPSStyle.Colors.primaryAccent)
            case .some(.approved), .some(.autoApproved), .some(.partiallyApproved):
                return ("approved", OPSStyle.Colors.successStatus)
            default:
                return ("pending", OPSStyle.Colors.primaryAccent)
            }
        }
    }
}
