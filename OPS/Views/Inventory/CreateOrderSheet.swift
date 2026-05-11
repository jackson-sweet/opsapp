//
//  CreateOrderSheet.swift
//  OPS
//
//  Suggested-order sheet (feature e08c63a2). Lists every inventory item
//  currently below its warning/critical threshold and proposes a quantity
//  to order (enough to restore each item to its warning level, rounded
//  up). The operator can adjust per-row, then export the order as plain
//  text (system share sheet) or copy it to the clipboard for a supplier.
//
//  Why "share" rather than a true purchase flow: OPS doesn't broker
//  supplier transactions. The lowest-friction path is a clean order
//  list the operator can paste into an email, text, or supplier portal.
//  The list lives here so the operator never has to hunt for low items
//  before placing an order — the suggestion is built from thresholds.
//

import SwiftUI
import SwiftData

struct CreateOrderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let items: [InventoryItem]

    /// Per-row order quantity edits, keyed by item id. Seeded on first
    /// render via `defaultOrderQty(for:)`; the user can override any value.
    @State private var orderQty: [String: Double] = [:]
    @State private var includeItem: [String: Bool] = [:]
    @State private var didShareOrCopy = false

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    summaryHeader

                    if items.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                                ForEach(sortedItems) { item in
                                    orderRow(item)
                                }
                                Color.clear.frame(height: 100)
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.top, OPSStyle.Layout.spacing2)
                        }
                    }
                }

                if !items.isEmpty {
                    VStack {
                        Spacer()
                        actionBar
                    }
                }
            }
            .navigationTitle("Create Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .onAppear {
                seedDefaults()
            }
        }
    }

    // MARK: - Sub-views

    private var sortedItems: [InventoryItem] {
        items.sorted { lhs, rhs in
            let lhsStatus = lhs.effectiveThresholdStatus()
            let rhsStatus = rhs.effectiveThresholdStatus()
            if lhsStatus != rhsStatus { return lhsStatus > rhsStatus }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var summaryHeader: some View {
        let included = items.filter { includeItem[$0.id] ?? true }
        let totalUnits = included.reduce(0.0) { $0 + (orderQty[$1.id] ?? defaultOrderQty(for: $1)) }
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "cart.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text("ORDER SUMMARY")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(1.1)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing3) {
                summaryStat(label: "ITEMS", value: "\(included.count)")
                summaryStat(label: "UNITS", value: formatQuantity(totalUnits))
                summaryStat(label: "CRITICAL", value: "\(items.filter { $0.effectiveThresholdStatus() == .critical }.count)")
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .tracking(0.8)
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 32))
                .foregroundColor(OPSStyle.Colors.successStatus)
            Text("All items above threshold")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("No order needed right now.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func orderRow(_ item: InventoryItem) -> some View {
        let status = item.effectiveThresholdStatus()
        let included = includeItem[item.id] ?? true
        let qty = orderQty[item.id] ?? defaultOrderQty(for: item)
        let unit = item.unit?.display ?? ""

        HStack(spacing: OPSStyle.Layout.spacing3) {
            Button {
                includeItem[item.id] = !included
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: included ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundColor(included ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(included ? "Exclude \(item.name)" : "Include \(item.name)")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    if let badge = status.label {
                        Text(badge)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(status.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(status.color, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                    }
                    Text(item.name.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(included ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
                Text("On hand: \(formatQuantity(item.quantity))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            HStack(spacing: OPSStyle.Layout.spacing1) {
                Button {
                    let newValue = max(0, qty - 1)
                    orderQty[item.id] = newValue
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .background(OPSStyle.Colors.subtleBackground)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease order quantity")

                Text(formatQuantity(qty))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(included ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    .frame(minWidth: 40)

                Button {
                    orderQty[item.id] = qty + 1
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .background(OPSStyle.Colors.subtleBackground)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase order quantity")
            }
            .opacity(included ? 1.0 : 0.5)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var actionBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                UIPasteboard.general.string = orderText
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                didShareOrCopy = true
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .buttonStyle(.plain)

            ShareLink(item: orderText, subject: Text("Stock Order")) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    // MARK: - Order math

    /// Suggest enough quantity to restore the item to its warning level
    /// (or 1× the critical level if no warning is configured). Rounded up
    /// to the next whole unit so the result is always orderable in
    /// whole-unit packs.
    private func defaultOrderQty(for item: InventoryItem) -> Double {
        let effective = item.effectiveThresholds()
        let target: Double
        if let warning = effective.warning {
            target = warning
        } else if let critical = effective.critical {
            target = critical * 2
        } else {
            target = max(1, item.quantity * 2)
        }
        let needed = max(0, target - item.quantity)
        // Round up to next whole unit so the operator never under-orders.
        return ceil(needed)
    }

    private func seedDefaults() {
        for item in items {
            if orderQty[item.id] == nil {
                orderQty[item.id] = defaultOrderQty(for: item)
            }
            if includeItem[item.id] == nil {
                includeItem[item.id] = true
            }
        }
    }

    private var orderText: String {
        var lines: [String] = ["OPS — STOCK ORDER", ""]
        for item in sortedItems where (includeItem[item.id] ?? true) {
            let qty = orderQty[item.id] ?? defaultOrderQty(for: item)
            guard qty > 0 else { continue }
            let unit = item.unit?.display ?? ""
            let sku = item.sku.flatMap { $0.isEmpty ? nil : "  (SKU \($0))" } ?? ""
            lines.append("• \(formatQuantity(qty))\(unit.isEmpty ? "" : " \(unit)") — \(item.name)\(sku)")
        }
        lines.append("")
        lines.append("Generated by OPS")
        return lines.joined(separator: "\n")
    }

    private func formatQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }
}
