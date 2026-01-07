//
//  BulkQuantityAdjustmentSheet.swift
//  OPS
//
//  Bulk quantity adjustment sheet for multiple inventory items
//  Tactical minimalist design
//

import SwiftUI
import SwiftData

struct BulkQuantityAdjustmentSheet: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let items: [InventoryItem]
    let onComplete: () -> Void

    @State private var adjustmentAmount: Double = 0
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingPreview: Bool = false

    private var adjustmentSettings: AdjustmentSettings {
        AdjustmentSettings.load()
    }

    private var adjustmentValues: [Int] {
        adjustmentSettings.values
    }

    private var hasChanges: Bool {
        adjustmentAmount != 0
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Summary
                    summarySection
                        .padding(.top, OPSStyle.Layout.spacing3)

                    // Adjustment amount display
                    adjustmentDisplay
                        .padding(.top, OPSStyle.Layout.spacing4)

                    // Divider
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 1)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.top, OPSStyle.Layout.spacing4)

                    // Quick adjust buttons
                    adjustmentButtonsSection
                        .padding(.top, OPSStyle.Layout.spacing3)

                    // Error
                    if let error = errorMessage {
                        Text(error)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .padding(.top, OPSStyle.Layout.spacing2)
                    }

                    Spacer()

                    // Preview toggle
                    previewToggle
                        .padding(.bottom, OPSStyle.Layout.spacing2)

                    // Items preview (collapsible)
                    if showingPreview {
                        itemsPreviewList
                    }
                }
            }
            .standardSheetToolbar(
                title: "Bulk Adjust",
                actionText: "Apply",
                isActionEnabled: hasChanges,
                isSaving: isSaving,
                onCancel: { dismiss() },
                onAction: { saveChanges() }
            )
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("\(items.count) items selected")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Adjustment will be applied to all selected items")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Adjustment Display

    private let adjustmentFont = Font.custom("Mohave-Bold", size: 56)

    private var adjustmentDisplay: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if adjustmentAmount != 0 {
                    Text(adjustmentAmount > 0 ? "+" : "")
                        .font(adjustmentFont)
                        .foregroundColor(adjustmentColor)
                    +
                    Text(formatQuantity(adjustmentAmount))
                        .font(adjustmentFont)
                        .foregroundColor(adjustmentColor)
                } else {
                    Text("0")
                        .font(adjustmentFont)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Text("per item")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private var adjustmentColor: Color {
        if adjustmentAmount > 0 {
            return OPSStyle.Colors.successStatus
        } else if adjustmentAmount < 0 {
            return OPSStyle.Colors.errorStatus
        } else {
            return OPSStyle.Colors.tertiaryText
        }
    }

    // MARK: - Adjustment Buttons

    private var adjustmentButtonsSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Reset button
                    Button(action: {
                        adjustmentAmount = 0
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }) {
                        Text("Reset")
                            .font(Font.custom("Mohave-SemiBold", size: 18))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    ForEach(adjustmentValues, id: \.self) { value in
                        adjustmentPill(value: value)
                            .id(value)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
            .onAppear {
                let centerIndex = adjustmentValues.count / 2
                if centerIndex < adjustmentValues.count {
                    let centerValue = adjustmentValues[centerIndex]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(centerValue, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func adjustmentPill(value: Int) -> some View {
        let isPositive = value > 0
        let color = isPositive ? OPSStyle.Colors.successStatus : OPSStyle.Colors.errorStatus

        return Button(action: {
            adjustmentAmount += Double(value)
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(isPositive ? "+\(value)" : "\(value)")
                .font(Font.custom("Mohave-SemiBold", size: 22))
                .foregroundColor(color)
                .frame(minWidth: 72)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(color.opacity(0.15))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(color, lineWidth: 1.5)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Preview Toggle

    private var previewToggle: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingPreview.toggle()
            }
        }) {
            HStack {
                Text(showingPreview ? "Hide Items" : "Show Items")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                Image(systemName: showingPreview ? "chevron.up" : "chevron.down")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Items Preview List

    private var itemsPreviewList: some View {
        ScrollView {
            LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(items) { item in
                    itemPreviewRow(item)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing3)
        }
        .frame(maxHeight: 200)
    }

    private func itemPreviewRow(_ item: InventoryItem) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Current -> New quantity
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(formatQuantity(item.quantity))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                let newQuantity = max(0, item.quantity + adjustmentAmount)
                Text(formatQuantity(newQuantity))
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(newQuantityColor(current: item.quantity, new: newQuantity))
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }

    private func newQuantityColor(current: Double, new: Double) -> Color {
        if new > current {
            return OPSStyle.Colors.successStatus
        } else if new < current {
            return OPSStyle.Colors.errorStatus
        } else {
            return OPSStyle.Colors.primaryText
        }
    }

    // MARK: - Functions

    private func formatQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.1f", value)
        }
    }

    private func saveChanges() {
        guard hasChanges else { return }

        isSaving = true
        errorMessage = nil

        // Apply adjustment to all items locally first
        for item in items {
            item.quantity = max(0, item.quantity + adjustmentAmount)
            item.needsSync = true
        }

        Task {
            var failedCount = 0

            for item in items {
                do {
                    let updates: [String: Any] = [
                        BubbleFields.InventoryItem.quantity: item.quantity
                    ]

                    try await dataController.apiService.updateInventoryItem(id: item.id, updates: updates)

                    await MainActor.run {
                        item.needsSync = false
                        item.lastSyncedAt = Date()
                    }
                } catch {
                    failedCount += 1
                    print("[BULK ADJUST] Failed to update \(item.name): \(error)")
                }
            }

            await MainActor.run {
                try? modelContext.save()

                if failedCount > 0 {
                    errorMessage = "Failed to sync \(failedCount) items"
                    isSaving = false
                } else {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    onComplete()
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    BulkQuantityAdjustmentSheet(
        items: [
            InventoryItem(
                id: "preview1",
                name: "2x4 Lumber 8ft",
                quantity: 50,
                companyId: "company",
                unitId: nil,
                itemDescription: nil,
                tagsString: "",
                sku: nil,
                notes: nil,
                imageUrl: nil
            ),
            InventoryItem(
                id: "preview2",
                name: "Drywall 4x8",
                quantity: 25,
                companyId: "company",
                unitId: nil,
                itemDescription: nil,
                tagsString: "",
                sku: nil,
                notes: nil,
                imageUrl: nil
            )
        ],
        onComplete: { }
    )
    .environmentObject(DataController())
}
