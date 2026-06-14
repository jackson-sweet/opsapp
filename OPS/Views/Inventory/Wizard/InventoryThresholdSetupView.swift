//
//  InventoryThresholdSetupView.swift
//  OPS
//
//  Batch threshold editor for the inventory setup wizard (Step 3).
//  Also reused from the insights fallback CTA (presented as a sheet).
//
//  Shows all inventory items with auto-suggested warning/critical thresholds.
//  User picks WARNING or CRITICAL via tabs and adjusts each item's value
//  using either tap-the-button steppers or a swipe-up/down gesture on the
//  number itself (drag = fast change with haptic + visual feedback).
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var dataController: DataController

    // MARK: - State

    /// Per-item threshold values keyed by item ID
    @State private var warningValues: [String: Double] = [:]
    @State private var criticalValues: [String: Double] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Which threshold the user is currently editing (WARNING or CRITICAL).
    /// Bug f69e82e8: tabs let the user focus on one threshold type at a
    /// time so each row gets the full width — much easier to read with
    /// gloves and large numbers.
    @State private var activeTab: ThresholdTab = .warning

    // MARK: - Tab Definition

    /// The two threshold types the user can edit. Order maps to the tab
    /// order on screen.
    private enum ThresholdTab: Int, CaseIterable, Identifiable {
        case warning
        case critical

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .warning:  return "WARNING"
            case .critical: return "CRITICAL"
            }
        }

        var color: Color {
            switch self {
            case .warning:  return OPSStyle.Colors.warningStatus
            case .critical: return OPSStyle.Colors.errorStatus
            }
        }
    }

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
                tabBar
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

            Text("We've suggested thresholds based on your current quantities. Drag a number up or down to change it fast, or tap the buttons.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing4)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    // MARK: - Tab Bar

    /// Two-tab segmented control for switching between WARNING and CRITICAL
    /// thresholds. Mirrors the dot+label pattern used in the form sheet so
    /// the visual language is consistent across the inventory module.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ThresholdTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    private func tabButton(for tab: ThresholdTab) -> some View {
        let isActive = activeTab == tab

        return Button {
            guard activeTab != tab else { return }
            TutorialHaptics.lightTap()
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : OPSStyle.Animation.standard) {
                activeTab = tab
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                // Color dot — same visual hint used in the per-item form
                Circle()
                    .fill(tab.color)
                    .frame(
                        width: OPSStyle.Layout.Indicator.dotSM,
                        height: OPSStyle.Layout.Indicator.dotSM
                    )

                Text(tab.label)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(isActive ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                    .tracking(1.1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetMin)
            .background(
                isActive
                    ? OPSStyle.Colors.cardBackgroundDark
                    : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        isActive ? tab.color : OPSStyle.Colors.cardBorderSubtle,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, OPSStyle.Layout.spacing1)
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

    /// One row per inventory item. Shows the item name on the left and a
    /// single full-width stepper on the right for whichever tab is active.
    private func thresholdRow(for item: InventoryItem) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            // Item name + current quantity
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

            // Single stepper for the active threshold — full-width, easy to
            // read with gloves. Switches based on the active tab.
            ThresholdStepperRow(
                value: binding(for: activeTab, itemId: item.id),
                color: activeTab.color
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }

    /// Get the @Binding for the active tab's value on this item. The setter
    /// also enforces the relationship between warning and critical so the
    /// user never ends up with critical > warning (which would never trigger
    /// a critical alert before a warning).
    private func binding(for tab: ThresholdTab, itemId: String) -> Binding<Double> {
        switch tab {
        case .warning:
            return Binding(
                get: { warningValues[itemId] ?? 0 },
                set: { newValue in
                    let clamped = max(0, newValue)
                    warningValues[itemId] = clamped
                    // Keep critical <= warning (warning warns earlier).
                    if let critical = criticalValues[itemId], clamped < critical {
                        criticalValues[itemId] = clamped
                    }
                }
            )
        case .critical:
            return Binding(
                get: { criticalValues[itemId] ?? 0 },
                set: { newValue in
                    let clamped = max(0, newValue)
                    criticalValues[itemId] = clamped
                    // Keep warning >= critical.
                    if let warning = warningValues[itemId], clamped > warning {
                        warningValues[itemId] = clamped
                    }
                }
            )
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

    /// Populate suggested thresholds based on current quantities. Existing
    /// item-level thresholds (already saved on the model) take precedence
    /// over the auto-suggestion so previously-set values aren't clobbered.
    private func initializeSuggestedThresholds() {
        for item in sortedItems {
            let qty = item.quantity

            // Use already-saved values when present; otherwise auto-suggest.
            if let existing = item.warningThreshold {
                warningValues[item.id] = existing
            } else if qty <= 0 {
                warningValues[item.id] = 0
            } else {
                // warning = ceil(qty * 0.25), min 2
                warningValues[item.id] = max(2, ceil(qty * 0.25))
            }

            if let existing = item.criticalThreshold {
                criticalValues[item.id] = existing
            } else if qty <= 0 {
                criticalValues[item.id] = 0
            } else {
                // critical = ceil(qty * 0.10), min 1
                criticalValues[item.id] = max(1, ceil(qty * 0.10))
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

// MARK: - ThresholdStepperRow

/// Full-width threshold control: minus button, draggable number, plus button.
///
/// The number in the middle is the headline interaction — drag up to
/// increment, drag down to decrement, with continuous haptic feedback per
/// integer step and a subtle scale + glow while dragging. Tap the +/-
/// buttons for one-at-a-time changes.
///
/// Drag sensitivity: 1 integer step per ~14pt of vertical movement. Tuned
/// so a thumb-flick adjusts by 5-10 (good for "from 8 to 3") without
/// overshooting on small adjustments. Negative values are clamped at zero.
private struct ThresholdStepperRow: View {
    @Binding var value: Double
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The value at the moment the drag began. We rebase from this so the
    /// math stays correct across multiple .onChanged events.
    @State private var dragStartValue: Double = 0

    /// True while the user is actively dragging the number. Drives the
    /// scale + glow feedback.
    @State private var isDragging: Bool = false

    /// Last committed integer step during the active drag. Used to gate
    /// per-step haptics so we don't fire on every pixel.
    @State private var lastDragStep: Int = 0

    /// Pre-warmed haptic generator. Prepared on drag start so the Taptic
    /// Engine has zero spin-up latency for the per-step ticks.
    private let stepHaptic = UIImpactFeedbackGenerator(style: .rigid)

    /// Vertical pixels of drag per integer step. Smaller = more sensitive
    /// (faster but easier to overshoot). 14pt is the sweet spot — fast
    /// thumb-flicks adjust by ~10, careful nudges adjust by 1.
    private static let pointsPerStep: CGFloat = 14.0

    var body: some View {
        HStack(spacing: 6) {
            // Color indicator dot — matches the active tab's color
            Circle()
                .fill(color)
                .frame(
                    width: OPSStyle.Layout.Indicator.dotSM,
                    height: OPSStyle.Layout.Indicator.dotSM
                )

            // Minus button — tap-to-decrement
            Button {
                TutorialHaptics.lightTap()
                if value > 0 {
                    value -= 1
                }
            } label: {
                Image(systemName: OPSStyle.Icons.minus)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(value > 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    .frame(width: 28, height: 28)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .disabled(value <= 0)

            // Draggable value display — drag up/down to change quickly
            draggableNumber

            // Plus button — tap-to-increment
            Button {
                TutorialHaptics.lightTap()
                value += 1
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

    /// The headline draggable number. Visual feedback while dragging:
    /// — slight scale (1.0 → 1.15)
    /// — accent-colored glow ring
    /// — text adopts the threshold color (warning gold or critical red)
    /// Haptics fire once per integer step crossed during the drag.
    private var draggableNumber: some View {
        Text("\(Int(value))")
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(isDragging ? color : OPSStyle.Colors.primaryText)
            .monospacedDigit()
            .frame(minWidth: 36, minHeight: 32)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(isDragging ? color.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        isDragging ? color : Color.clear,
                        // Border thickens to communicate "you're holding it"
                        lineWidth: isDragging ? 1.5 : 0
                    )
            )
            // Scale-up while dragging communicates "this is grabbed".
            // 1.15 = visible but not gimmicky; reduceMotion users see no scale.
            .scaleEffect(reduceMotion ? 1.0 : (isDragging ? 1.15 : 1.0))
            // Spring lands without bounce — controlled feel, matches OPS
            // tactical-minimalist motion language (no playful overshoot).
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2) : OPSStyle.Animation.quick,
                value: isDragging
            )
            .contentShape(Rectangle())
            // .gesture (NOT .simultaneousGesture) — competes with the
            // outer ScrollView. SwiftUI uses minimumDistance to figure out
            // intent: touches that move <8pt before becoming directional
            // bias toward the scroll view (so users can still scroll the
            // list). Once the user has moved >8pt vertically on the
            // number, this gesture wins and the scroll is preempted.
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { gesture in
                        handleDragChanged(translation: gesture.translation.height)
                    }
                    .onEnded { _ in
                        handleDragEnded()
                    }
            )
            .accessibilityLabel(Text("Threshold value \(Int(value)). Drag up to increase, drag down to decrease."))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    value += 1
                case .decrement:
                    if value > 0 { value -= 1 }
                @unknown default:
                    break
                }
                TutorialHaptics.lightTap()
            }
    }

    // MARK: - Drag Handlers

    private func handleDragChanged(translation: CGFloat) {
        // First .onChanged in this drag — capture the starting state and
        // pre-warm the haptic engine so per-step ticks fire instantly.
        if !isDragging {
            isDragging = true
            dragStartValue = value
            lastDragStep = 0
            stepHaptic.prepare()
        }

        // SwiftUI translation: positive Y = downward. Inventory users expect
        // "drag up to increase" (more in stock) so we flip the sign here.
        let stepsRaw = -translation / Self.pointsPerStep
        let stepsRounded = Int(stepsRaw.rounded())

        // Compute proposed value, clamp at zero (no negative thresholds).
        let proposed = max(0, dragStartValue + Double(stepsRounded))

        // If the integer value changed since the last frame, apply it and
        // fire a haptic tick. Per-step haptic = each integer feels like a
        // notch on a physical dial. Critical for use with gloves where
        // visual feedback alone is unreliable.
        if proposed != value {
            value = proposed
        }

        if stepsRounded != lastDragStep {
            // Intensity scales with how far we've moved this frame so a
            // fast flick feels weightier than a slow nudge.
            let intensity = min(0.9, 0.5 + abs(Double(stepsRounded - lastDragStep)) * 0.1)
            stepHaptic.impactOccurred(intensity: intensity)
            lastDragStep = stepsRounded
        }
    }

    private func handleDragEnded() {
        // Light commit haptic to bookend the interaction — tells the user
        // "release accepted, value locked in".
        TutorialHaptics.lightTap()
        isDragging = false
        lastDragStep = 0
    }
}
