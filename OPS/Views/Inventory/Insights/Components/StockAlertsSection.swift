//
//  StockAlertsSection.swift
//  OPS
//
//  Stock alerts section showing critical and low-stock items.
//  Two sub-cards with left border stripes and inline threshold editing.
//

import SwiftUI

struct StockAlertsSection: View {
    let criticalAlerts: [StockAlert]
    let warningAlerts: [StockAlert]
    let onUpdateThreshold: (String, Double?, Double?) -> Void
    let onItemTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Section header
            sectionHeader

            // Critical sub-card
            alertGroupCard(
                title: "CRITICAL",
                alerts: criticalAlerts,
                accentColor: OPSStyle.Colors.errorStatus,
                emptyIcon: "checkmark.circle",
                emptyText: "No critical items"
            )

            // Low stock sub-card
            alertGroupCard(
                title: "LOW",
                alerts: warningAlerts,
                accentColor: OPSStyle.Colors.warningStatus,
                emptyIcon: "checkmark.circle",
                emptyText: "No low stock items"
            )
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Text("STOCK ALERTS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    // MARK: - Alert Group Card

    private func alertGroupCard(
        title: String,
        alerts: [StockAlert],
        accentColor: Color,
        emptyIcon: String,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group title
            Text(title)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(accentColor)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, OPSStyle.Layout.spacing2_5)
                .padding(.bottom, alerts.isEmpty ? 0 : 8)

            if alerts.isEmpty {
                // Empty state
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: emptyIcon)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.successStatus)

                    Text(emptyText)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, OPSStyle.Layout.spacing3)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                // Alert rows
                ForEach(Array(alerts.enumerated()), id: \.element.id) { index, alert in
                    StockAlertRow(
                        alert: alert,
                        accentColor: accentColor,
                        onUpdateThreshold: onUpdateThreshold,
                        onItemTap: onItemTap
                    )

                    if index < alerts.count - 1 {
                        Divider()
                            .background(OPSStyle.Colors.separator)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }
                }
            }
        }
        .padding(.bottom, OPSStyle.Layout.spacing2_5)
        .glassSurface()
        // Left border stripe
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
    }
}

// MARK: - Stock Alert Row

private struct StockAlertRow: View {
    let alert: StockAlert
    let accentColor: Color
    let onUpdateThreshold: (String, Double?, Double?) -> Void
    let onItemTap: (String) -> Void

    @State private var showThresholdEditor = false

    var body: some View {
        Button {
            onItemTap(alert.id)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                // Item name
                Text(alert.name)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Spacer()

                // Quantity vs threshold display
                thresholdDisplay
                    .onTapGesture {
                        showThresholdEditor = true
                    }

                // Unit label
                Text(alert.unitDisplay)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showThresholdEditor) {
            ThresholdEditorPopover(
                alert: alert,
                onSave: { newWarning, newCritical in
                    onUpdateThreshold(alert.id, newWarning, newCritical)
                    showThresholdEditor = false
                },
                onCancel: {
                    showThresholdEditor = false
                }
            )
        }
    }

    private var thresholdDisplay: some View {
        let threshold: Double = {
            switch alert.severity {
            case .critical: return alert.criticalThreshold ?? 0
            case .warning: return alert.warningThreshold ?? 0
            }
        }()

        return HStack(spacing: 3) {
            Text(formatQuantity(alert.currentQty))
                .font(OPSStyle.Typography.body)
                .foregroundColor(accentColor)

            Text("/")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text(formatQuantity(threshold))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    private func formatQuantity(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Threshold Editor Popover

private struct ThresholdEditorPopover: View {
    let alert: StockAlert
    let onSave: (Double?, Double?) -> Void
    let onCancel: () -> Void

    @State private var warningValue: Double
    @State private var criticalValue: Double

    init(alert: StockAlert, onSave: @escaping (Double?, Double?) -> Void, onCancel: @escaping () -> Void) {
        self.alert = alert
        self.onSave = onSave
        self.onCancel = onCancel
        _warningValue = State(initialValue: alert.warningThreshold ?? 0)
        _criticalValue = State(initialValue: alert.criticalThreshold ?? 0)
    }

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            // Title
            Text("Adjust Thresholds")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(alert.name)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Warning threshold stepper
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(OPSStyle.Colors.warningStatus)
                        .frame(width: 8, height: 8)

                    Text("WARNING")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }

                Stepper(
                    value: $warningValue,
                    in: 0...9999,
                    step: 1
                ) {
                    Text(formatQuantity(warningValue) + " " + alert.unitDisplay)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .tint(OPSStyle.Colors.primaryAccent)
            }

            // Critical threshold stepper
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(OPSStyle.Colors.errorStatus)
                        .frame(width: 8, height: 8)

                    Text("CRITICAL")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                }

                Stepper(
                    value: $criticalValue,
                    in: 0...9999,
                    step: 1
                ) {
                    Text(formatQuantity(criticalValue) + " " + alert.unitDisplay)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .tint(OPSStyle.Colors.primaryAccent)
            }

            // Action buttons
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(OPSStyle.Colors.surfaceInput)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }

                Button {
                    let w = warningValue > 0 ? warningValue : nil
                    let c = criticalValue > 0 ? criticalValue : nil
                    onSave(w, c)
                } label: {
                    Text("Save")
                        .font(OPSStyle.Typography.button)
                        .foregroundColor(OPSStyle.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassDense()
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
    }

    private func formatQuantity(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()

        ScrollView {
            StockAlertsSection(
                criticalAlerts: [
                    StockAlert(
                        id: "1", name: "Wire Connectors",
                        currentQty: 3, warningThreshold: 10, criticalThreshold: 5,
                        unitDisplay: "ea"
                    ),
                    StockAlert(
                        id: "2", name: "PVC Cement",
                        currentQty: 0, warningThreshold: 5, criticalThreshold: 2,
                        unitDisplay: "cans"
                    ),
                ],
                warningAlerts: [
                    StockAlert(
                        id: "3", name: "Copper Elbows",
                        currentQty: 8, warningThreshold: 10, criticalThreshold: 3,
                        unitDisplay: "ea"
                    ),
                ],
                onUpdateThreshold: { _, _, _ in },
                onItemTap: { _ in }
            )
            .padding()
        }
    }
}

#Preview("Empty State") {
    ZStack {
        OPSStyle.Colors.background.ignoresSafeArea()

        ScrollView {
            StockAlertsSection(
                criticalAlerts: [],
                warningAlerts: [],
                onUpdateThreshold: { _, _, _ in },
                onItemTap: { _ in }
            )
            .padding()
        }
    }
}
