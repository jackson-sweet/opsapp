//
//  StockQuickAdjustSheet.swift
//  OPS
//
//  Half-height stock adjustment surface opened from stock list/grid/table rows.
//  Full variant editing stays in VariantDetailView; this sheet handles the
//  field-speed quantity cases without forcing the operator into the full page.
//

import SwiftUI
import SwiftData

struct StockQuickAdjustSheet: View {
    let row: EnrichedVariantRow
    let onOpenFullDetail: () -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var permissionStore = PermissionStore.shared

    @State private var localQuantity: Double
    @State private var exactQuantityText: String
    @State private var customDeltaText: String = ""
    @State private var isAdjusting: Bool = false
    @State private var errorMessage: String? = nil

    init(row: EnrichedVariantRow, onOpenFullDetail: @escaping () -> Void) {
        self.row = row
        self.onOpenFullDetail = onOpenFullDetail
        _localQuantity = State(initialValue: row.variant.quantity)
        _exactQuantityText = State(initialValue: StockNumberFormatter.quantity(row.variant.quantity))
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var canAdjustStock: Bool {
        permissionStore.can("catalog.stock.adjust")
    }

    private var quantityText: String {
        StockNumberFormatter.quantity(localQuantity)
    }

    private var unitText: String {
        row.unit?.abbreviation ?? row.unit?.display ?? "UNITS"
    }

    private var status: ThresholdStatus {
        if let critical = row.effectiveCritical, localQuantity <= critical { return .critical }
        if let warning = row.effectiveWarning, localQuantity <= warning { return .warning }
        return .normal
    }

    private var statusLabel: String {
        switch status {
        case .normal: return "ON HAND"
        case .warning: return "BELOW WARNING"
        case .critical: return "BELOW CRITICAL"
        }
    }

    private var quickAdjustColumns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 4
        return Array(repeating: GridItem(.flexible(), spacing: OPSStyle.Layout.spacing1), count: count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        header
                        quantityReadout
                        presetGrid
                        exactQuantityControl
                        customDeltaControl
                        if let errorMessage {
                            errorCard(errorMessage)
                        }
                        Color.clear.frame(height: OPSStyle.Layout.spacing3)
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("CLOSE")
                            .font(OPSStyle.Typography.buttonLabel)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .accessibilityLabel("Close quick adjustment")
                }
                ToolbarItem(placement: .principal) {
                    Text("QUICK ADJUST")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onOpenFullDetail()
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .accessibilityLabel("Open full variant detail")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(row.family.name)
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !row.variantLabel.isEmpty {
                Text(row.variantLabel)
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let sku = row.variant.sku, !sku.isEmpty {
                Text(sku)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }

    private var quantityReadout: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .lastTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                Text(quantityText)
                    .font(OPSStyle.Typography.displayQuantity)
                    .foregroundColor(status.color)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unitText.uppercased())
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Circle()
                    .fill(status.color)
                    .frame(width: OPSStyle.Layout.Indicator.dotMD, height: OPSStyle.Layout.Indicator.dotMD)
                Text(statusLabel)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(status.color)
                Spacer()
                if isAdjusting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.tertiaryText))
                        .scaleEffect(0.75)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    private var presetGrid: some View {
        LazyVGrid(columns: quickAdjustColumns, spacing: OPSStyle.Layout.spacing1) {
            ForEach(StockQuantityAdjustment.presetDeltas, id: \.self) { delta in
                Button {
                    adjustQuantity(by: delta)
                } label: {
                    Text(delta > 0 ? "+\(StockNumberFormatter.quantity(delta))" : "-\(StockNumberFormatter.quantity(abs(delta)))")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                        .nestedCard(cornerRadius: OPSStyle.Layout.cornerRadius)
                }
                .disabled(isAdjusting || !canAdjustStock || StockQuantityAdjustment.targetQuantity(current: localQuantity, delta: delta) == nil)
                .opacity(canAdjustStock ? 1.0 : 0.4)
            }
        }
    }

    private var exactQuantityControl: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            CatalogFieldLabel("SET COUNT")
            HStack(spacing: OPSStyle.Layout.spacing2) {
                TextField(quantityText, text: $exactQuantityText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(CatalogTextFieldStyle())
                Button {
                    applyExactQuantity()
                } label: {
                    Text("SET")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(canApplyExactQuantity ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .frame(width: 64, height: OPSStyle.Layout.touchTargetMin)
                        .nestedCard(cornerRadius: OPSStyle.Layout.cornerRadius)
                }
                .disabled(!canApplyExactQuantity)
            }
        }
    }

    private var customDeltaControl: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            CatalogFieldLabel("CUSTOM")
            HStack(spacing: OPSStyle.Layout.spacing2) {
                TextField("37", text: $customDeltaText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(CatalogTextFieldStyle())
                Button { applyCustomDelta(sign: 1) } label: {
                    Text("ADD")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(canApplyCustomDelta(sign: 1) ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                        .frame(width: 64, height: OPSStyle.Layout.touchTargetMin)
                        .nestedCard(cornerRadius: OPSStyle.Layout.cornerRadius)
                }
                .disabled(!canApplyCustomDelta(sign: 1))

                Button { applyCustomDelta(sign: -1) } label: {
                    Text("SUB")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(canApplyCustomDelta(sign: -1) ? OPSStyle.Colors.errorText : OPSStyle.Colors.tertiaryText)
                        .frame(width: 64, height: OPSStyle.Layout.touchTargetMin)
                        .nestedCard(cornerRadius: OPSStyle.Layout.cornerRadius)
                }
                .disabled(!canApplyCustomDelta(sign: -1))
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.errorText)
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(
                cornerRadius: OPSStyle.Layout.cornerRadius,
                borderColor: OPSStyle.Colors.errorText.opacity(0.45)
            )
    }

    private func adjustQuantity(by delta: Double) {
        guard let next = StockQuantityAdjustment.targetQuantity(current: localQuantity, delta: delta) else { return }
        setQuantity(to: next)
    }

    private var canApplyExactQuantity: Bool {
        canAdjustStock &&
        !isAdjusting &&
        StockQuantityAdjustment.exactQuantity(from: exactQuantityText, current: localQuantity) != nil
    }

    private func applyExactQuantity() {
        guard canApplyExactQuantity,
              let next = StockQuantityAdjustment.exactQuantity(from: exactQuantityText, current: localQuantity)
        else { return }
        setQuantity(to: next)
    }

    private func canApplyCustomDelta(sign: Double) -> Bool {
        canAdjustStock &&
        !isAdjusting &&
        StockQuantityAdjustment.customTargetQuantity(from: customDeltaText, sign: sign, current: localQuantity) != nil
    }

    private func applyCustomDelta(sign: Double) {
        guard canApplyCustomDelta(sign: sign),
              let next = StockQuantityAdjustment.customTargetQuantity(from: customDeltaText, sign: sign, current: localQuantity)
        else { return }
        setQuantity(to: next)
        customDeltaText = ""
    }

    private func setQuantity(to next: Double) {
        let previous = localQuantity
        guard next != previous else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        localQuantity = next
        exactQuantityText = StockNumberFormatter.quantity(next)
        row.variant.quantity = next
        try? modelContext.save()
        isAdjusting = true
        errorMessage = nil

        Task { @MainActor in
            let repo = CatalogRepository(companyId: companyId)
            do {
                let dto = try await repo.adjustVariantQuantity(row.variant.id, newQuantity: next)
                localQuantity = dto.quantity
                exactQuantityText = StockNumberFormatter.quantity(dto.quantity)
                row.variant.quantity = dto.quantity
                row.variant.lastSyncedAt = Date()
                try? modelContext.save()

                try? await repo.recordVariantDeduction(
                    id: UUID().uuidString,
                    catalogVariantId: row.variant.id,
                    previousQuantity: previous,
                    newQuantity: next,
                    deductedBy: dataController.currentUser?.id,
                    reason: "manual_adjustment"
                )
            } catch {
                localQuantity = previous
                exactQuantityText = StockNumberFormatter.quantity(previous)
                row.variant.quantity = previous
                try? modelContext.save()
                errorMessage = error.localizedDescription
            }
            isAdjusting = false
        }
    }
}
