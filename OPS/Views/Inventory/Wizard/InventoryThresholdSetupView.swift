//
//  InventoryThresholdSetupView.swift
//  OPS
//
//  Batch threshold editor for the inventory setup wizard (Step 3).
//  Also reused from the insights fallback CTA (presented as a sheet).
//
//  Shows all inventory items with auto-suggested warning/critical thresholds.
//  User can adjust per-item values via steppers, then apply all at once.
//

import SwiftUI
import SwiftData

struct InventoryThresholdSetupView: View {
    // MARK: - Inputs

    let items: [InventoryItem]
    let onApply: () -> Void
    let onSkip: () -> Void

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    // MARK: - State

    /// Per-item threshold values keyed by item ID
    @State private var warningValues: [String: Double] = [:]
    @State private var criticalValues: [String: Double] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: - Computed

    /// Items sorted alphabetically, excluding soft-deleted
    private var sortedItems: [InventoryItem] {
        items
            .filter { $0.deletedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                scrollableItemList
                bottomButtons
            }

            if isSaving {
                savingOverlay
            }
        }
        .onAppear {
            initializeSuggestedThresholds()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("SET STOCK ALERTS")
                .font(OPSStyle.Typography.headingBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("We've suggested thresholds based on your current quantities. Adjust as needed.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing4)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    // MARK: - Item List

    private var scrollableItemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                    thresholdRow(for: item)

                    if index < sortedItems.count - 1 {
                        Rectangle()
                            .fill(OPSStyle.Colors.cardBorderSubtle)
                            .frame(height: 1)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .padding(.bottom, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Threshold Row

    private func thresholdRow(for item: InventoryItem) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Item name
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Text("Qty: \(item.quantityDisplay)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Warning stepper
            thresholdStepper(
                value: Binding(
                    get: { warningValues[item.id] ?? 0 },
                    set: { newValue in
                        warningValues[item.id] = max(0, newValue)
                        // Ensure warning >= critical
                        if let critical = criticalValues[item.id], newValue < critical {
                            criticalValues[item.id] = newValue
                        }
                    }
                ),
                color: OPSStyle.Colors.warningStatus
            )

            // Critical stepper
            thresholdStepper(
                value: Binding(
                    get: { criticalValues[item.id] ?? 0 },
                    set: { newValue in
                        criticalValues[item.id] = max(0, newValue)
                        // Ensure critical <= warning
                        if let warning = warningValues[item.id], newValue > warning {
                            warningValues[item.id] = newValue
                        }
                    }
                ),
                color: OPSStyle.Colors.errorStatus
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }

    // MARK: - Stepper Component

    private func thresholdStepper(value: Binding<Double>, color: Color) -> some View {
        HStack(spacing: 6) {
            // Color indicator dot
            Circle()
                .fill(color)
                .frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)

            // Minus button
            Button {
                TutorialHaptics.lightTap()
                if value.wrappedValue > 0 {
                    value.wrappedValue -= 1
                }
            } label: {
                Image(systemName: OPSStyle.Icons.minus)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(value.wrappedValue > 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    .frame(width: 28, height: 28)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .disabled(value.wrappedValue <= 0)

            // Value display
            Text("\(Int(value.wrappedValue))")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: 28, alignment: .center)
                .monospacedDigit()

            // Plus button
            Button {
                TutorialHaptics.lightTap()
                value.wrappedValue += 1
            } label: {
                Image(systemName: OPSStyle.Icons.plus)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: 28, height: 28)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            }

            // APPLY ALL button
            Button {
                TutorialHaptics.lightTap()
                applyAllThresholds()
            } label: {
                Text("APPLY ALL")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.wizardAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .disabled(isSaving)
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            // SKIP button
            Button {
                TutorialHaptics.lightTap()
                onSkip()
            } label: {
                Text("SKIP")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(isSaving)
        }
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    // MARK: - Saving Overlay

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: OPSStyle.Layout.spacing3) {
                ProgressView()
                    .tint(OPSStyle.Colors.loadingSpinner)
                    .scaleEffect(1.2)

                Text("SAVING THRESHOLDS...")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing4)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorderSubtle, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    // MARK: - Logic

    /// Populate suggested thresholds based on current quantities
    private func initializeSuggestedThresholds() {
        for item in sortedItems {
            let qty = item.quantity

            if qty <= 0 {
                // Items with 0 quantity get no suggestion
                warningValues[item.id] = 0
                criticalValues[item.id] = 0
            } else {
                // warning = ceil(qty * 0.25), min 2
                let suggestedWarning = max(2, ceil(qty * 0.25))
                // critical = ceil(qty * 0.10), min 1
                let suggestedCritical = max(1, ceil(qty * 0.10))

                warningValues[item.id] = suggestedWarning
                criticalValues[item.id] = suggestedCritical
            }
        }
    }

    /// Batch-update all items with their threshold values
    private func applyAllThresholds() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                guard let repo = dataController.inventoryRepository else {
                    throw NSError(domain: "OPS", code: -1, userInfo: [NSLocalizedDescriptionKey: "No inventory repository available"])
                }

                // Batch update each item
                for item in sortedItems {
                    let warning = warningValues[item.id] ?? 0
                    let critical = criticalValues[item.id] ?? 0

                    // Only set non-zero thresholds (0 means no threshold)
                    let warningValue: Double? = warning > 0 ? warning : nil
                    let criticalValue: Double? = critical > 0 ? critical : nil

                    let dto = UpdateInventoryItemDTO(
                        warningThreshold: warningValue,
                        criticalThreshold: criticalValue
                    )

                    _ = try await repo.updateItem(item.id, fields: dto)

                    // Update local SwiftData model
                    await MainActor.run {
                        item.warningThreshold = warningValue
                        item.criticalThreshold = criticalValue
                        item.needsSync = false
                    }
                }

                await MainActor.run {
                    isSaving = false
                    TutorialHaptics.success()
                    onApply()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save thresholds. Please try again."
                    TutorialHaptics.error()
                    print("[THRESHOLD_SETUP] Error saving thresholds: \(error)")
                }
            }
        }
    }
}
