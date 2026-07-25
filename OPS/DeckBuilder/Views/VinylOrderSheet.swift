// OPS/OPS/DeckBuilder/Views/VinylOrderSheet.swift

import MessageUI
import Supabase
import SwiftData
import SwiftUI
import UIKit

struct VinylOrderSheet: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    let projectId: String?
    let companyId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @Query private var projects: [Project]
    @Query private var vinylOrderMarkers: [ProjectVinylOrderMarker]
    @Query private var catalogItems: [CatalogItem]
    @Query private var catalogVariants: [CatalogVariant]
    @Query private var catalogOptionValues: [CatalogOptionValue]
    @Query private var catalogVariantOptionValues: [CatalogVariantOptionValue]
    @Query private var stockUnits: [CatalogStockUnit]

    @State private var settings = VinylOrderSettings.default
    @State private var didSeedVinylOrderSettings = false
    /// UI mirror of the design's persisted `materialsSettings.orderMode` — the
    /// single source of truth shared with the deck-tab materials card. Seeded on
    /// appear, written straight back to the design on change (so MARK ORDERED and
    /// the card always agree).
    @State private var orderMode: VinylOrderMode = .cutList
    @State private var fullRollLengthFeet: Double = 75
    @State private var didSeedOrderMode = false
    @State private var isCreating = false
    @State private var isUpdatingProjectMarker = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var showingMessageComposer = false
    @State private var surfaceInputs: [VinylOrderSurfaceInput] = []
    @State private var didLoadSurfaceInputs = false
    @State private var showingTemplateEditor = false
    /// One-shot latch for restoring a persisted free-text colour — catalog
    /// reloads re-run the restore path and must not clobber in-session typing.
    @State private var didRestoreFreeTextColor = false
    /// Resolved once on appear: company runs tracked inventory AND the
    /// catalog_stock_units schema is live. Gates every stock-inventory surface.
    @State private var stockTrackingActive = false
    /// Set after a successful order draft (tracked companies only) to prompt the
    /// roll-receipt confirmation.
    @State private var pendingRollReceipt: VinylRollReceiptContext?
    /// Set when MARK ORDERED resolves a materials list — presents the order-confirm
    /// sheet so the operator confirms the actual quantities before the freeze.
    @State private var pendingOrderConfirm: PendingVinylOrderConfirm?
    @State private var bankingOffcutIds: Set<String> = []
    @State private var bankedOffcutIds: Set<String> = []
    @AppStorage(VinylCutListTextTemplate.messageStorageKey) private var messageTemplate = VinylCutListTextTemplate.defaultMessageTemplate
    @AppStorage(VinylCutListTextTemplate.cutStorageKey) private var cutTemplate = VinylCutListTextTemplate.defaultCutTemplate
    @AppStorage(VinylCutListTextTemplate.separatorStorageKey) private var cutSeparatorRawValue = VinylCutListSeparator.lines.rawValue

    /// Memoized vinyl cut plan. Recomputed only when `settings` or `surfaceInputs`
    /// actually change — never per body pass. "MARK ORDERED" fans a single tap out
    /// into a burst of context saves + push/realtime echoes, each of which
    /// invalidates this sheet's @Query-driven body; recomputing the full cut-list
    /// geometry on every one of those passes is what made the sheet lag on tap.
    @State private var plan: VinylCutPlan = VinylCutListEngine.makePlan(surfaces: [], settings: .default)

    /// Memoized catalog product/variant tree. Same rationale as `plan`: rebuilt
    /// only when the underlying catalog @Query results change, not per body pass.
    @State private var catalogProductChoices: [VinylCatalogProductChoice] = []

    private var cutSeparator: VinylCutListSeparator {
        VinylCutListSeparator(rawValue: cutSeparatorRawValue) ?? .lines
    }

    private var project: Project? {
        guard let projectId else { return nil }
        return projects.first { $0.id == projectId }
    }

    private var projectVinylOrderMarker: ProjectVinylOrderMarker? {
        guard let projectId else { return nil }
        return vinylOrderMarkers.first { $0.projectId == projectId }
    }

    private var projectVinylOrderStatus: ProjectVinylOrderStatus {
        projectVinylOrderMarker?.status ?? .notOrdered
    }

    private var projectTitle: String {
        let trimmed = project?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.flatMap { $0.isEmpty ? nil : $0 } ?? "PROJECT"
    }

    private var deckTitle: String {
        let trimmed = viewModel.deckDesign.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "DECK DESIGN" : trimmed
    }

    private var noteText: String {
        plan.orderNotes(projectTitle: projectTitle, deckTitle: deckTitle, rolls: isRollMode ? rollSummaryLine : nil)
    }

    private var messageText: String {
        plan.textMessageBody(
            messageTemplate: messageTemplate,
            cutTemplate: cutTemplate,
            cutSeparator: cutSeparator,
            projectTitle: projectTitle,
            rolls: isRollMode ? rollSummaryLine : ""
        )
    }

    // MARK: - Full-roll ordering

    private var isRollMode: Bool { orderMode == .fullRolls }

    /// The plan's purchased strips packed into whole rolls of `fullRollLengthFeet`.
    private var rollPackingPlan: VinylRollPackingPlan {
        VinylRollPacker.packingPlan(
            stripLengthsFeet: plan.surfaces.flatMap(\.purchasedCuts).map { $0.lengthInches / 12.0 },
            rollLengthFeet: fullRollLengthFeet
        )
    }

    private var rollPack: RollPackResult {
        rollPackingPlan.summary
    }

    /// e.g. "3 ROLLS @ 75'" — the roll-mode order line for the summary + notes.
    private var rollSummaryLine: String {
        "\(rollPack.rollCount) ROLL\(rollPack.rollCount == 1 ? "" : "S") @ \(Int(fullRollLengthFeet))'"
    }

    /// Seed the order-mode mirror from the design's persisted materials settings
    /// on first appear (idempotent — user edits thereafter own the state).
    private func seedOrderModeIfNeeded() {
        guard !didSeedOrderMode else { return }
        didSeedOrderMode = true
        let ms = viewModel.drawingData.materialsSettings ?? DeckMaterialsSettings()
        orderMode = ms.orderMode
        fullRollLengthFeet = ms.fullRollLengthFeet
    }

    private func seedVinylOrderSettingsIfNeeded() {
        guard !didSeedVinylOrderSettings else { return }
        didSeedVinylOrderSettings = true
        settings = viewModel.drawingData.vinylOrderSettings ?? .default
    }

    private func handlePlanInputChange() {
        guard didSeedVinylOrderSettings else { return }
        var data = viewModel.drawingData
        if data.vinylOrderSettings != settings {
            data.vinylOrderSettings = settings
            viewModel.drawingData = data
        }
        recomputePlan()
    }

    /// Persist an order-mode change straight to the design's `materialsSettings`
    /// so the deck-tab card and MARK ORDERED read the same value.
    private func writeMaterialsOrderMode(_ mode: VinylOrderMode) {
        guard orderMode != mode else { return }
        orderMode = mode
        var ms = viewModel.drawingData.materialsSettings ?? DeckMaterialsSettings()
        ms.orderMode = mode
        var data = viewModel.drawingData
        data.materialsSettings = ms
        viewModel.drawingData = data
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func writeFullRollLength(_ feet: Double) {
        fullRollLengthFeet = feet
        var ms = viewModel.drawingData.materialsSettings ?? DeckMaterialsSettings()
        ms.fullRollLengthFeet = feet
        var data = viewModel.drawingData
        data.materialsSettings = ms
        viewModel.drawingData = data
    }

    /// The signed-in operator's `users.id` (a lowercase Postgres uuid). This
    /// must NEVER be the Firebase UID: `catalog_orders.created_by_id` and
    /// `catalog_stock_unit_events.created_by` are uuid columns, and a Firebase UID
    /// (28-char alphanumeric) makes Postgres reject the whole write with 22P02 —
    /// the "CREATE ORDER throws an error" in bug 0f86b9b0. `SupabaseService.currentUserId`
    /// and the UserDefaults "currentUserId" key both can carry the Firebase UID,
    /// so neither is a safe source here. Nil until the user record loads — the
    /// action buttons stay disabled rather than sending garbage.
    private var currentUserId: String? {
        dataController.currentUser?.id.lowercased()
    }

    /// The selected catalog variant id, or nil when ordering by free-text color
    /// (no stock identity, so no inventory surfaces).
    private var resolvedVariantId: String? {
        guard let id = settings.catalogVariantId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else { return nil }
        return id
    }

    private var resolvedVariantLabel: String {
        if let variant = selectedVariant { return variantDisplayName(variant) }
        return settings.color.isEmpty ? "VINYL" : settings.color
    }

    /// Available rolls of the selected variant, most-full first (the bank source).
    private var onHandRolls: [CatalogStockUnit] {
        guard let vid = resolvedVariantId else { return [] }
        return stockUnits
            .filter {
                $0.companyId == companyId
                    && $0.catalogVariantId == vid
                    && $0.unitKind == .roll
                    && $0.deletedAt == nil
                    && $0.status.countsAsAvailable
                    && ($0.remainingLengthValue ?? 0) > 0
            }
            .sorted { ($0.remainingLengthValue ?? 0) > ($1.remainingLengthValue ?? 0) }
    }

    private var onHandOffcuts: [CatalogStockUnit] {
        guard let vid = resolvedVariantId else { return [] }
        return stockUnits.filter {
            $0.companyId == companyId
                && $0.catalogVariantId == vid
                && $0.unitKind == .offcut
                && $0.deletedAt == nil
                && $0.status.countsAsAvailable
        }
    }

    /// Banked offcuts fed back into the planner so reuse spans jobs. Stored in
    /// feet; the engine works in inches. Empty unless tracking is live.
    private var availableOffcutSeeds: [VinylOnHandOffcut] {
        guard stockTrackingActive else { return [] }
        return onHandOffcuts.map {
            VinylOnHandOffcut(
                id: $0.id,
                label: $0.label ?? "BANKED OFFCUT",
                widthInches: ($0.widthValue ?? 0) * 12,
                lengthInches: ($0.remainingLengthValue ?? 0) * 12
            )
        }
    }

    private var offcutInventoryService: VinylOffcutInventoryService {
        VinylOffcutInventoryService(
            companyId: companyId,
            userId: currentUserId ?? "",
            modelContext: modelContext
        )
    }

    private var canCreateOrder: Bool {
        projectId != nil
            && currentUserId != nil
            && !plan.surfaces.isEmpty
            && plan.isOrderable
            && hasResolvedCatalogColor
            && !isCreating
    }

    private var canExportCutPlan: Bool {
        !plan.surfaces.isEmpty && plan.isOrderable
    }

    private var canToggleProjectMarker: Bool {
        guard let project, let userId = currentUserId else { return false }
        return !ProjectAccessHelper.isMentionOnly(project, userId: userId)
            && PermissionStore.shared.isFeatureEnabled("deck_builder")
            && PermissionStore.shared.can("deck_builder.view", requiredScope: "assigned")
            && PermissionStore.shared.can("projects.edit")
            && !isUpdatingProjectMarker
            && (projectVinylOrderStatus == .ordered || plan.isOrderable)
    }

    private func computeCatalogProductChoices() -> [VinylCatalogProductChoice] {
        VinylCatalogSelection.productChoices(
            companyId: companyId,
            items: catalogItems,
            variants: catalogVariants,
            optionValues: catalogOptionValues,
            variantOptionValues: catalogVariantOptionValues
        )
    }

    private var selectedProductChoice: VinylCatalogProductChoice? {
        guard let itemId = settings.catalogItemId else { return nil }
        return catalogProductChoices.first { $0.id == itemId }
    }

    private var selectedVariant: CatalogVariant? {
        guard let variantId = settings.catalogVariantId else { return nil }
        return selectedProductChoice?.variants.first { $0.id == variantId }
    }

    private var hasResolvedCatalogColor: Bool {
        settings.catalogItemId == nil || selectedVariant != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            validationBanner
                            if plan.isOrderable {
                                VinylOrderLayoutWindow(
                                    plan: plan,
                                    projectTitle: projectTitle,
                                    subtitle: deckTitle
                                )
                            }

                            controlsSection
                            if plan.isOrderable {
                                summarySection
                                cutListSection
                                textTemplateSection
                                reuseSection
                                catalogSection
                                stockSection
                            }
                            projectMarkerSection
                            statusSection

                            Color.clear.frame(height: VinylOrderLayout.actionBarReserveHeight)
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }
                }

                VStack {
                    Spacer()
                    actionBar
                }
            }
            .navigationTitle("// VINYL ORDER")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CLOSE") { dismiss() }
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .sheet(isPresented: $showingMessageComposer) {
                VinylOrderMessageComposeView(
                    body: messageText,
                    onCompletion: { _ in
                        showingMessageComposer = false
                    }
                )
            }
            .task {
                seedVinylOrderSettingsIfNeeded()
                seedOrderModeIfNeeded()
                await loadSurfaceInputsIfNeeded()
            }
            .task {
                await resolveStockTracking()
            }
            .onDisappear {
                persistFreeTextColorIfNeeded()
            }
            .sheet(item: $pendingRollReceipt) { context in
                VinylRollReceiptSheet(context: context) { count, lengthFeet, widthInches in
                    await receiveRolls(context: context, count: count, lengthFeet: lengthFeet, widthInches: widthInches)
                }
            }
            .sheet(item: $pendingOrderConfirm) { ctx in
                VinylOrderConfirmSheet(
                    projectTitle: ctx.projectTitle,
                    deckTitle: ctx.deckTitle,
                    rollWidthInches: ctx.rollWidthInches,
                    calculated: ctx.calculated,
                    onConfirm: { confirmed in confirmProjectVinylOrder(ctx, confirmed) }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            // Memoization hooks live in a ViewModifier so the (already large) body
            // expression stays inside the Swift type-checker's budget. They keep
            // `plan` / `catalogProductChoices` fresh without recomputing per pass.
            .modifier(VinylOrderMemoHooks(
                settings: settings,
                catalogItems: catalogItems,
                catalogVariants: catalogVariants,
                catalogOptionValues: catalogOptionValues,
                catalogVariantOptionValues: catalogVariantOptionValues,
                onPlanInputChange: { handlePlanInputChange() },
                onCatalogChange: { rebuildCatalogChoices() }
            ))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(alignment: .leading, spacing: 3) {
                Text("// VINYL ORDER")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .tracking(1.1)
                Text(plan.isOrderable
                     ? (isRollMode
                        ? "\(plan.surfaces.count) SURFACE\(plan.surfaces.count == 1 ? "" : "S") / \(rollPack.rollCount) ROLL\(rollPack.rollCount == 1 ? "" : "S")"
                        : "\(plan.surfaces.count) SURFACE\(plan.surfaces.count == 1 ? "" : "S") / \(plan.totalOrderedSqFt) SQ FT")
                     : "BLOCKED")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
    }

    @ViewBuilder
    private var validationBanner: some View {
        if projectId == nil {
            banner(text: "PROJECT LINK MISSING", color: OPSStyle.Colors.errorStatus)
        } else if viewModel.vinylOrderSurfaceScope == .selectedSurfaces && viewModel.selection.selectedSurfaceIds.isEmpty {
            banner(text: "SELECT A SURFACE", color: OPSStyle.Colors.warningStatus)
        } else if viewModel.vinylOrderEffectiveScale == nil {
            banner(text: "CONFIRM ONE EDGE LENGTH", color: OPSStyle.Colors.warningStatus)
        } else if let blocker = plan.blockingMessage {
            banner(text: blocker, color: OPSStyle.Colors.errorStatus)
        } else if settings.catalogItemId != nil && selectedVariant == nil {
            banner(text: "SELECT VINYL COLOR", color: OPSStyle.Colors.warningStatus)
        } else if plan.surfaces.isEmpty {
            banner(text: "NO ORDERABLE SURFACE FOUND", color: OPSStyle.Colors.warningStatus)
        }
    }

    private func banner(text: String, color: Color) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
            Text(text)
                .font(OPSStyle.Typography.captionBold)
                .tracking(0.8)
            Spacer(minLength: 0)
        }
        .foregroundColor(color)
        .padding(OPSStyle.Layout.spacing2)
        .background(color.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(color.opacity(0.45), lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    private var controlsSection: some View {
        section(title: "SETTINGS") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                if selectedProductChoice != nil {
                    catalogVariantPicker
                } else {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text("COLOR")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)
                        TextField("FIELD CONFIRM", text: $settings.color)
                            .font(OPSStyle.Typography.body)
                            .textInputAutocapitalization(.words)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(OPSStyle.Colors.subtleBackground)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    }
                }

                directionControl
                patternControl
                if settings.patternMode == .solid {
                    runLockControl
                }

                settingStepper(
                    label: "ROLL",
                    value: $settings.rollWidthInches,
                    range: 24...144,
                    step: 6
                )
                settingStepper(
                    label: "SEAM",
                    value: $settings.seamOverlapInches,
                    range: 0...12,
                    step: 0.25
                )
                settingStepper(
                    label: "WRAP",
                    value: $settings.edgeWrapInches,
                    range: 0...18,
                    step: 0.5
                )

                orderModeControl
                if isRollMode {
                    rollLengthStepper
                }
            }
        }
    }

    /// `CUT LIST | FULL ROLLS` segmented control — reads/writes the design's
    /// `materialsSettings.orderMode` (single source of truth with the deck-tab card).
    private var orderModeControl: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("ORDER")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(VinylOrderMode.allCases, id: \.self) { mode in
                    Button {
                        writeMaterialsOrderMode(mode)
                    } label: {
                        Text(mode.presetLabel)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(orderMode == mode ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(orderMode == mode ? OPSStyle.Colors.surfaceActive : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(OPSStyle.Colors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private var rollLengthStepper: some View {
        Stepper(
            value: Binding(get: { fullRollLengthFeet }, set: { writeFullRollLength($0) }),
            in: 25...300,
            step: 5
        ) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("ROLL LENGTH")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)
                Text("\(Int(fullRollLengthFeet))'")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer(minLength: 0)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
    }

    private var catalogVariantPicker: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("VARIANT")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)

            Picker("VARIANT", selection: Binding(
                get: { settings.catalogVariantId ?? "" },
                set: { selectCatalogVariant($0) }
            )) {
                Text("SELECT")
                    .tag("")
                ForEach(selectedProductChoice?.variants ?? []) { variant in
                    Text(variantDisplayName(variant).uppercased())
                        .tag(variant.id)
                }
            }
            .pickerStyle(.menu)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        }
    }

    private var patternControl: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("PATTERN")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(VinylPatternMode.allCases) { patternMode in
                    Button {
                        settings.patternMode = patternMode
                        if patternMode == .linear {
                            settings.allowsDirectionalChanges = false
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(patternMode.label)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(settings.patternMode == patternMode ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(settings.patternMode == patternMode ? OPSStyle.Colors.surfaceActive : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(OPSStyle.Colors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private var runLockControl: some View {
        Toggle(isOn: Binding(
            get: { !settings.allowsDirectionalChanges },
            set: { settings.allowsDirectionalChanges = !$0 }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOCK RUN")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text(settings.allowsDirectionalChanges ? "SOLID COLOR ONLY" : "ONE DIRECTION")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
    }

    private var directionControl: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("RUN")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(VinylLayoutDirection.allCases) { direction in
                    Button {
                        settings.direction = direction
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(direction.label)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(settings.direction == direction ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(settings.direction == direction ? OPSStyle.Colors.surfaceActive : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(OPSStyle.Colors.subtleBackground)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private func settingStepper(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: VinylOrderLayout.labelWidth, alignment: .leading)
                Text(formatInchesForSheet(value.wrappedValue))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Spacer(minLength: 0)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
    }

    private var summarySection: some View {
        section(title: "SUMMARY") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                if isRollMode {
                    // Full-roll mode leads with whole rolls; the cut list below
                    // stays the on-site cutting guide.
                    metricRow("ROLLS", "\(rollPack.rollCount) @ \(Int(fullRollLengthFeet))'")
                    VinylRollUtilizationView(plan: rollPackingPlan)
                    if rollPack.overlengthStripCount > 0 {
                        metricRow("OVER ROLL", "\(rollPack.overlengthStripCount) CUT\(rollPack.overlengthStripCount == 1 ? "" : "S")")
                    }
                }
                metricRow("ORDER AREA", "\(plan.totalOrderedSqFt) SQ FT")
                metricRow("RUN", plan.runDirectionSummary)
                metricRow("SURFACE AREA", "\(formatSqFtForSheet(plan.totalSurfaceAreaSqFt)) SQ FT")
                if plan.totalReusedCutAreaSqFt > 0 {
                    metricRow("REUSED AREA", "\(formatSqFtForSheet(plan.totalReusedCutAreaSqFt)) SQ FT")
                }
                metricRow("CUT WASTE", "\(formatSqFtForSheet(plan.totalWasteSqFt)) SQ FT")
                metricRow("CUTS", "\(plan.totalStripCount)")
            }
        }
    }

    private var cutListSection: some View {
        section(title: "CUT LIST") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                if plan.surfaces.isEmpty {
                    emptyLine("—")
                } else {
                    ForEach(plan.surfaces) { surface in
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                            Text(surface.displayLabel.uppercased())
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            ForEach(VinylCutGroup.groups(from: surface.cuts)) { group in
                                Text(group.displayLine)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(group.isPurchased ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.tan)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.subtleBackground)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    }
                }
            }
        }
    }

    private var textTemplateSection: some View {
        section(title: "TEXT TEMPLATE") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Button {
                    showingTemplateEditor.toggle()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        Text(showingTemplateEditor ? "HIDE TEMPLATE" : "EDIT TEMPLATE")
                            .font(OPSStyle.Typography.buttonLabel)
                        Spacer(minLength: 0)
                        Image(systemName: showingTemplateEditor ? "chevron.up" : "chevron.down")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                }
                .buttonStyle(.plain)

                if showingTemplateEditor {
                    templateEditor(label: "MESSAGE", text: $messageTemplate, minHeight: VinylOrderLayout.templateEditorHeight)

                    templateEditor(label: "CUT ROW", text: $cutTemplate, minHeight: VinylOrderLayout.cutTemplateEditorHeight)

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text("JOIN")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            ForEach(VinylCutListSeparator.allCases) { separator in
                                Button {
                                    cutSeparatorRawValue = separator.rawValue
                                } label: {
                                    Text(separator.label)
                                        .font(OPSStyle.Typography.buttonLabel)
                                        .foregroundColor(cutSeparator == separator ? OPSStyle.Colors.text : OPSStyle.Colors.secondaryText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, OPSStyle.Layout.spacing2)
                                        .background(cutSeparator == separator ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.subtleBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                .stroke(
                                                    cutSeparator == separator ? OPSStyle.Colors.text : OPSStyle.Colors.cardBorder,
                                                    lineWidth: OPSStyle.Layout.Border.standard
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MESSAGE: [project] [color] [cuts] [cut_count]")
                            Text("CUT: [quantity] [length] [surface]")
                        }
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("RESET") {
                            messageTemplate = VinylCutListTextTemplate.defaultMessageTemplate
                            cutTemplate = VinylCutListTextTemplate.defaultCutTemplate
                            cutSeparatorRawValue = VinylCutListSeparator.lines.rawValue
                        }
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func templateEditor(label: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            TextEditor(text: text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .padding(OPSStyle.Layout.spacing2)
                .frame(minHeight: minHeight)
                .background(OPSStyle.Colors.subtleBackground)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    private var reuseSection: some View {
        section(title: "OFFCUT REUSE") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                if plan.reuseNotes.isEmpty {
                    emptyLine("NO FULL-SURFACE REUSE FOUND. KEEP LONG OFFCUTS.")
                } else {
                    ForEach(Array(plan.reuseNotes.enumerated()), id: \.offset) { _, note in
                        Text(note.line)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.tanSoft)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    }
                }
            }
        }
    }

    private var catalogSection: some View {
        section(title: "CATALOG") {
            if let choice = selectedProductChoice {
                metricRow("PRODUCT", choice.item.name.uppercased())
                if let variant = selectedVariant {
                    metricRow("VARIANT", variantDisplayName(variant).uppercased())
                    if let sku = variant.sku, !sku.isEmpty {
                        metricRow("SKU", sku.uppercased())
                    }
                } else {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text("VARIANT NOT SELECTED")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                        Text("SELECT A VARIANT TO WRITE A CATALOG ITEM.")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("NO PRODUCT SELECTED")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("COLOR STAYS FIELD TEXT. NO CATALOG ITEM IS WRITTEN.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var stockSection: some View {
        if stockTrackingActive,
           resolvedVariantId != nil,
           !plan.producedOffcuts.isEmpty || !onHandRolls.isEmpty || !onHandOffcuts.isEmpty {
            section(title: "STOCK") {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    metricRow("ON HAND", onHandSummary)

                    if !plan.producedOffcuts.isEmpty {
                        Text("// BANK OFFCUTS")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .tracking(0.8)
                            .padding(.top, OPSStyle.Layout.spacing1)

                        if onHandRolls.isEmpty {
                            emptyLine("RECEIVE ROLLS TO BANK OFFCUTS.")
                        }

                        ForEach(plan.producedOffcuts) { offcut in
                            offcutBankRow(offcut)
                        }
                    }
                }
            }
        }
    }

    private var onHandSummary: String {
        let rolls = onHandRolls.count
        let offcuts = onHandOffcuts.count
        guard rolls > 0 || offcuts > 0 else { return "—" }
        return "\(rolls) ROLL\(rolls == 1 ? "" : "S") · \(offcuts) OFFCUT\(offcuts == 1 ? "" : "S")"
    }

    private func offcutBankRow(_ offcut: VinylProducedOffcut) -> some View {
        let isBanked = bankedOffcutIds.contains(offcut.id)
        let isBanking = bankingOffcutIds.contains(offcut.id)
        // Enabled only when a roll can cover this offcut's full length and no
        // other bank is in flight (banks are serialized so concurrent debits of
        // the same auto-picked roll cannot over-credit it).
        let canBank = coveringRoll(for: offcut) != nil && !isBanked && bankingOffcutIds.isEmpty
        return HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatInchesForSheet(offcut.widthInches)) × \(vinylFormatFeetAndInches(offcut.lengthInches))")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Text("FROM \(offcut.sourceSurfaceLabel.uppercased())")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            Spacer(minLength: 0)
            Button {
                bankOffcut(offcut)
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    if isBanking {
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryText)
                    }
                    Text(isBanked ? "BANKED" : (isBanking ? "BANKING…" : "BANK"))
                        .font(OPSStyle.Typography.buttonLabel)
                }
                .foregroundColor(isBanked ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryText)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .background(isBanked ? Color.clear : OPSStyle.Colors.surfaceHover)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(
                            isBanked ? OPSStyle.Colors.successStatus.opacity(0.5) : OPSStyle.Colors.line,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(!canBank)
            .opacity(canBank || isBanked || isBanking ? 1 : 0.45)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    @ViewBuilder
    private var projectMarkerSection: some View {
        if PermissionStore.shared.isFeatureEnabled("deck_builder")
            && PermissionStore.shared.can("deck_builder.view", requiredScope: "assigned") {
            section(title: "PROJECT MARKER") {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("VINYL")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text(projectVinylOrderStatus.displayLabel)
                                .font(OPSStyle.Typography.dataValue)
                                .foregroundColor(projectVinylOrderStatus == .ordered ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryText)
                        }

                        Spacer(minLength: 0)

                        Button {
                            setProjectVinylOrdered(projectVinylOrderStatus != .ordered)
                        } label: {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                if isUpdatingProjectMarker {
                                    ProgressView()
                                        .tint(OPSStyle.Colors.primaryText)
                                }
                                Text(projectVinylOrderStatus == .ordered ? "CLEAR ORDERED" : "MARK ORDERED")
                                    .font(OPSStyle.Typography.buttonLabel)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .background(OPSStyle.Colors.surfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canToggleProjectMarker)
                        .opacity(canToggleProjectMarker ? 1 : 0.45)
                    }

                    if let orderedAt = projectVinylOrderMarker?.orderedAt, projectVinylOrderStatus == .ordered {
                        Text("ORDERED \(DateHelper.simpleDateString(from: orderedAt).uppercased())")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let statusMessage {
            banner(text: statusMessage, color: OPSStyle.Colors.successStatus)
        } else if let errorMessage {
            banner(text: errorMessage, color: OPSStyle.Colors.errorStatus)
        }
    }

    private var actionBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                handleTextAction()
            } label: {
                Label(MFMessageComposeViewController.canSendText() ? "TEXT CUTS" : "COPY CUTS", systemImage: "message.fill")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canExportCutPlan)
            .opacity(canExportCutPlan ? 1 : 0.45)

            Button {
                beginCreateOrderAndNote()
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    if isCreating {
                        ProgressView()
                            .tint(OPSStyle.Colors.background)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    Text("CREATE ORDER + NOTE")
                }
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.background)
                .frame(maxWidth: .infinity)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .background(canCreateOrder ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(!canCreateOrder)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.background.opacity(0.96))
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// \(title)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.1)
            content()
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer(minLength: 0)
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectCatalogVariant(_ rawVariantId: String) {
        let variantId = rawVariantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !variantId.isEmpty,
              let variant = selectedProductChoice?.variants.first(where: { $0.id == variantId }) else {
            settings.catalogVariantId = nil
            settings.color = ""
            viewModel.setVinylCatalogSelection(variantId: nil, color: nil)
            return
        }
        settings.catalogVariantId = variant.id
        settings.color = variantDisplayName(variant)
        // Persist onto the deck design so reopening the sheet restores the
        // colour instead of resetting it (bug 0f86b9b0).
        viewModel.setVinylCatalogSelection(variantId: variant.id, color: variantDisplayName(variant))
    }

    /// Persists a free-text colour (no catalog product configured) once, when
    /// the sheet closes — never per keystroke.
    private func persistFreeTextColorIfNeeded() {
        guard settings.catalogItemId == nil else { return }
        let trimmed = settings.color.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (viewModel.drawingData.config.vinylColor ?? "") else { return }
        viewModel.setVinylCatalogSelection(variantId: nil, color: trimmed)
    }

    private func variantDisplayName(_ variant: CatalogVariant) -> String {
        VinylCatalogSelection.variantDisplayName(
            variant,
            optionValues: catalogOptionValues,
            variantOptionValues: catalogVariantOptionValues
        )
    }

    private var vinylCatalogSelection: (item: CatalogItem, variant: CatalogVariant)? {
        guard let itemId = settings.catalogItemId,
              let variantId = settings.catalogVariantId,
              let item = catalogItems.first(where: {
                  $0.id == itemId
                      && $0.companyId == companyId
                      && $0.isActive
                      && $0.deletedAt == nil
              }),
              let variant = catalogVariants.first(where: {
                  $0.id == variantId
                      && $0.catalogItemId == item.id
                      && $0.companyId == companyId
                      && $0.isActive
                      && $0.deletedAt == nil
              }) else {
            return nil
        }
        return (item, variant)
    }

    private func handleTextAction() {
        guard canExportCutPlan else {
            errorMessage = plan.blockingMessage
            return
        }
        guard refreshPlanForOutbound() != nil else { return }
        if MFMessageComposeViewController.canSendText() {
            showingMessageComposer = true
        } else {
            UIPasteboard.general.string = messageText
            statusMessage = "CUTS COPIED"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func setProjectVinylOrdered(_ ordered: Bool) {
        guard canToggleProjectMarker, let projectId, let userId = currentUserId else { return }
        statusMessage = nil
        errorMessage = nil

        guard ordered else {
            clearProjectVinylOrdered(projectId: projectId, userId: userId)
            return
        }

        guard refreshPlanForOutbound() != nil else { return }

        // Resolve the full materials list over the whole drawing (same detection
        // the deck tab uses) so the frozen snapshot's vinyl set matches the tab's
        // live recompute and never false-flags drift.
        let current = resolveCurrentProjectOrder(projectId: projectId)

        if let materials = current.materials {
            guard materials.vinylPlan.isOrderable else {
                errorMessage = materials.vinylPlan.blockingMessage ?? VinylCutPlan.wallAlignedTransitionBlocker
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            // A materials list resolved → confirm the actual order first. The
            // mark happens in `confirmProjectVinylOrder` on CONFIRM ORDERED.
            pendingOrderConfirm = PendingVinylOrderConfirm(
                design: viewModel.deckDesign,
                materials: materials,
                settings: current.settings,
                vinylSettings: current.vinylSettings,
                projectId: projectId,
                projectTitle: projectTitle,
                deckTitle: deckTitle
            )
        } else {
            // No vinyl set / unresolved scale — plain marker toggle, no snapshot.
            markProjectVinylOrderedPlain(projectId: projectId)
        }
    }

    /// Freeze the confirmed order (from the confirm sheet) and mark the project.
    private func confirmProjectVinylOrder(_ ctx: PendingVinylOrderConfirm, _ confirmed: DeckMaterialsOrderConfirmation) {
        guard let userId = currentUserId else { return }
        isUpdatingProjectMarker = true
        statusMessage = nil
        errorMessage = nil
        let service = DeckMaterialsOrderService(userId: userId) { pid, fields in
            try await dataController.updateProjectFields(projectId: pid, fields: fields)
        }
        Task { @MainActor in
            do {
                // Re-resolve inside the task immediately before the local-first
                // snapshot write; no queued UI/realtime event can slip between
                // validation and the service boundary.
                let current = resolveCurrentProjectOrder(projectId: ctx.projectId)
                try DeckMaterialsOrderService.validateCurrentOrder(
                    currentMaterials: current.materials,
                    currentSettings: current.settings,
                    currentVinylSettings: current.vinylSettings,
                    pendingMaterials: ctx.materials,
                    pendingSettings: ctx.settings,
                    pendingVinylSettings: ctx.vinylSettings
                )
                guard let currentMaterials = current.materials else {
                    throw DeckMaterialsOrderError.vinylPlanChanged
                }
                try await service.markOrdered(
                    projectId: ctx.projectId,
                    design: viewModel.deckDesign,
                    materials: currentMaterials,
                    settings: current.settings,
                    vinylSettings: current.vinylSettings,
                    confirmed: confirmed
                )
                // The designer owns an active drawing-data copy. Keep the newly
                // frozen snapshot in that copy so its next save cannot erase the
                // service's local-first write on the model object.
                var activeData = viewModel.drawingData
                DeckMaterialsOrderService.mergeOrderedSnapshot(
                    from: viewModel.deckDesign,
                    into: &activeData
                )
                viewModel.drawingData = activeData
                isUpdatingProjectMarker = false
                statusMessage = "VINYL MARKED ORDERED"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                print("[VinylOrderSheet] Vinyl marker update failed: \(error)")
                isUpdatingProjectMarker = false
                errorMessage = (error as? DeckMaterialsOrderError)?.errorDescription ?? "VINYL STATUS FAILED"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    /// No materials list resolved — mark the project ordered without a snapshot.
    private func markProjectVinylOrderedPlain(projectId: String) {
        isUpdatingProjectMarker = true
        Task { @MainActor in
            do {
                if let materials = resolveCurrentProjectOrder(projectId: projectId).materials {
                    guard materials.vinylPlan.isOrderable else {
                        throw DeckMaterialsOrderError.vinylPlanBlocked(
                            materials.vinylPlan.blockingMessage
                                ?? VinylCutPlan.wallAlignedTransitionBlocker
                        )
                    }
                    // A plan appeared after the plain-marker decision. It now
                    // requires the normal review + frozen snapshot flow.
                    throw DeckMaterialsOrderError.vinylPlanChanged
                }
                try await dataController.updateProjectFields(
                    projectId: projectId,
                    fields: [
                        ProjectVinylOrderFields.status: .string(ProjectVinylOrderStatus.ordered.rawValue),
                        ProjectVinylOrderFields.orderedAt: .string(SupabaseDate.format(Date())),
                        // `projects.vinyl_ordered_by` FKs to auth.users(id), not public.users(id).
                        // The app does not surface this attribution, so keep the marker write valid.
                        ProjectVinylOrderFields.orderedBy: .null
                    ]
                )
                isUpdatingProjectMarker = false
                statusMessage = "VINYL MARKED ORDERED"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                print("[VinylOrderSheet] Vinyl marker update failed: \(error)")
                isUpdatingProjectMarker = false
                errorMessage = (error as? DeckMaterialsOrderError)?.errorDescription
                    ?? "VINYL STATUS FAILED"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func clearProjectVinylOrdered(projectId: String, userId: String) {
        isUpdatingProjectMarker = true
        let service = DeckMaterialsOrderService(userId: userId) { pid, fields in
            try await dataController.updateProjectFields(projectId: pid, fields: fields)
        }
        let design = viewModel.deckDesign
        Task { @MainActor in
            do {
                try await service.clearOrdered(projectId: projectId, design: design)
                var activeData = viewModel.drawingData
                DeckMaterialsOrderService.mergeOrderedSnapshot(
                    from: viewModel.deckDesign,
                    into: &activeData
                )
                viewModel.drawingData = activeData
                isUpdatingProjectMarker = false
                statusMessage = "VINYL MARK CLEARED"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                print("[VinylOrderSheet] Vinyl marker update failed: \(error)")
                isUpdatingProjectMarker = false
                errorMessage = "VINYL STATUS FAILED"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    /// Non-deleted task-type display names for this project — the vinyl job
    /// signal source (§ 5). On-demand fetch (not a @Query) so it costs nothing
    /// until MARK ORDERED is tapped.
    private func projectTaskTypeDisplays(projectId: String) -> [String] {
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.projectId == projectId && $0.deletedAt == nil }
        )
        let tasks = (try? modelContext.fetch(descriptor)) ?? []
        return tasks.compactMap { $0.taskType?.display }
    }

    /// `productId → vinyl-hint` blob for detection rule 3 — keyed by `Product.id`
    /// (what an `AssignedItem.productId` references), each product's linked
    /// catalog item folded in (see `DeckVinylHintBuilder`). Products fetched
    /// on-demand; the catalog side reuses this sheet's live `@Query`.
    private func vinylHintByProductId() -> [String: String] {
        let cid = companyId
        let productDescriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.companyId == cid }
        )
        let products = (try? modelContext.fetch(productDescriptor)) ?? []
        let scopedCatalog = catalogItems.filter { $0.companyId == companyId && $0.deletedAt == nil }
        return DeckVinylHintBuilder.build(products: products, catalogItems: scopedCatalog)
    }

    private func resolveCurrentProjectOrder(
        projectId: String
    ) -> (
        materials: DeckMaterialsList?,
        settings: DeckMaterialsSettings,
        vinylSettings: VinylOrderSettings
    ) {
        let data = viewModel.drawingData
        let materialsSettings = data.materialsSettings ?? DeckMaterialsSettings()
        let vinylSettings = data.vinylOrderSettings ?? settings
        let resolved = DeckMaterialsResolver.resolve(
            data: data,
            settings: materialsSettings,
            vinylSettings: vinylSettings,
            taskTypeDisplays: projectTaskTypeDisplays(projectId: projectId),
            vinylHintByProductId: vinylHintByProductId()
        )
        return (resolved.materials, materialsSettings, vinylSettings)
    }

    private func beginCreateOrderAndNote() {
        guard canCreateOrder else { return }
        isCreating = true
        Task { await createOrderAndNote() }
    }

    @MainActor
    private func loadSurfaceInputsIfNeeded() async {
        guard !didLoadSurfaceInputs else { return }
        didLoadSurfaceInputs = true
        // This reconciles @Published deck state; keep it out of SwiftUI's body pass.
        await Task.yield()
        rebuildCatalogChoices()
        surfaceInputs = viewModel.vinylOrderSurfaceInputs(scope: viewModel.vinylOrderSurfaceScope)
        recomputePlan()
    }

    /// Rebuild the memoized catalog tree from the current @Query results, then
    /// re-apply the deck's configured product (which can only resolve once the
    /// choices exist). Driven by the catalog `.onChange` hooks and initial load —
    /// never the per-body-pass path.
    private func rebuildCatalogChoices() {
        let choices = computeCatalogProductChoices()
        catalogProductChoices = choices
        applyConfiguredCatalogProduct(in: choices)
    }

    private func recomputePlan() {
        plan = VinylCutListEngine.makePlan(
            surfaces: surfaceInputs,
            settings: settings,
            availableOffcuts: availableOffcutSeeds
        )
    }

    /// Every outbound action gets one fresh plan from the active drawing. If the
    /// design changed since the preview was rendered, update the preview and
    /// require a second deliberate tap before copying, ordering, marking, or
    /// banking anything.
    @discardableResult
    private func refreshPlanForOutbound() -> VinylCutPlan? {
        let currentInputs = viewModel.vinylOrderSurfaceInputs(
            scope: viewModel.vinylOrderSurfaceScope
        )
        let currentPlan = VinylCutListEngine.makePlan(
            surfaces: currentInputs,
            settings: settings,
            availableOffcuts: availableOffcutSeeds
        )
        guard currentPlan.isOrderable else {
            surfaceInputs = currentInputs
            plan = currentPlan
            errorMessage = currentPlan.blockingMessage
                ?? VinylCutPlan.wallAlignedTransitionBlocker
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return nil
        }
        guard currentPlan == plan else {
            surfaceInputs = currentInputs
            plan = currentPlan
            errorMessage = DeckMaterialsOrderError.vinylPlanChanged.errorDescription
                ?? "DESIGN CHANGED · REVIEW ORDER"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return nil
        }
        return currentPlan
    }

    private func applyConfiguredCatalogProduct(in choices: [VinylCatalogProductChoice]) {
        guard settings.catalogItemId == nil else { return }

        let restored = VinylCatalogSelection.restoredSelection(
            configItemId: viewModel.drawingData.config.vinylCatalogItemId?.trimmingCharacters(in: .whitespacesAndNewlines),
            configVariantId: viewModel.drawingData.config.vinylCatalogVariantId,
            configColor: viewModel.drawingData.config.vinylColor,
            availableItemIds: Set(choices.map(\.id)),
            variantIdsByItem: Dictionary(uniqueKeysWithValues: choices.map { ($0.id, Set($0.variants.map(\.id))) })
        )

        if let itemId = restored.itemId {
            settings.catalogItemId = itemId
            settings.catalogVariantId = restored.variantId
            settings.color = restored.color ?? ""
        } else if !didRestoreFreeTextColor {
            // Free-text mode (or the configured product vanished): restore the
            // persisted colour exactly once so later catalog reloads never
            // clobber what the operator is typing.
            didRestoreFreeTextColor = true
            if settings.color.isEmpty, let color = restored.color {
                settings.color = color
            }
        }
    }

    @MainActor
    private func createOrderAndNote() async {
        defer { isCreating = false }

        guard let projectId else {
            errorMessage = "PROJECT LINK MISSING"
            return
        }
        guard let userId = currentUserId else {
            errorMessage = "USER MISSING"
            return
        }

        guard let draftPlan = refreshPlanForOutbound() else { return }
        let draftSettings = settings.normalized
        // Reflect roll-mode quantity in the drafted note (catalog line-item
        // quantity stays sq ft — the catalog unit — per scope).
        let draftRolls: String? = isRollMode ? rollSummaryLine : nil
        let draftNoteText = draftPlan.orderNotes(projectTitle: projectTitle, deckTitle: deckTitle, rolls: draftRolls)
        let draftProjectTitle = projectTitle
        let draftCatalogSelection = vinylCatalogSelection

        guard !draftPlan.surfaces.isEmpty else {
            errorMessage = "NO CUT LIST"
            return
        }
        guard draftPlan.isOrderable else {
            errorMessage = draftPlan.blockingMessage ?? VinylCutPlan.wallAlignedTransitionBlocker
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        // The colour is committing to a real order — persist it on the deck
        // design now, not just at sheet close.
        persistFreeTextColorIfNeeded()

        statusMessage = nil
        errorMessage = nil

        let orderRepo = CatalogOrderRepository(companyId: companyId)
        var createdOrderDTO: CatalogOrderDTO?
        var createdItemDTO: CatalogOrderItemDTO?
        let createdNoteDTO: ProjectNoteDTO

        do {
            let orderDTO = try await orderRepo.createOrder(CreateCatalogOrderDTO(
                companyId: companyId,
                status: CatalogOrderStatus.draft.rawValue,
                title: "VINYL ORDER - \(draftProjectTitle)",
                supplierName: nil,
                supplierContact: nil,
                expectedDeliveryDate: nil,
                notes: draftNoteText,
                createdById: userId
            ))
            createdOrderDTO = orderDTO

            if let match = draftCatalogSelection {
                let quantity = Double(draftPlan.totalOrderedSqFt)
                createdItemDTO = try await orderRepo.addItem(
                    orderId: orderDTO.id,
                    dto: CreateCatalogOrderItemDTO(
                        orderId: orderDTO.id,
                        catalogVariantId: match.variant.id,
                        quantityRequested: quantity,
                        costPerUnit: match.variant.unitCostOverride ?? match.item.defaultUnitCost,
                        notes: "VINYL CUT LIST - \(draftSettings.color.isEmpty ? "FIELD CONFIRM" : draftSettings.color)"
                    )
                )
            }

            createdNoteDTO = try await ProjectNoteRepository(companyId: companyId).create(CreateProjectNoteDTO(
                projectId: projectId,
                companyId: companyId,
                authorId: userId,
                content: "\(draftNoteText)\n\nORDER DRAFT: \(orderDTO.id)",
                mentionedUserIds: []
            ))
        } catch {
            if let itemId = createdItemDTO?.id {
                try? await orderRepo.removeItem(itemId)
            }
            if let orderId = createdOrderDTO?.id {
                try? await orderRepo.softDeleteOrder(orderId)
            }
            print("[VinylOrderSheet] Order create failed: \(error)")
            errorMessage = "ORDER FAILED"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        var localSaveFailed = false
        do {
            if let createdOrderDTO {
                modelContext.insert(createdOrderDTO.toModel())
            }
            if let createdItemDTO {
                modelContext.insert(createdItemDTO.toModel())
            }
            modelContext.insert(createdNoteDTO.toModel())
            try modelContext.save()
        } catch {
            localSaveFailed = true
            print("[VinylOrderSheet] Local save failed after remote order create: \(error)")
        }

        var railFailed = false
        do {
            try await NotificationRepository.shared.createNotification(
                NotificationRepository.CreateNotificationDTO(
                    userId: userId,
                    companyId: companyId,
                    type: "catalog_order_drafted",
                    title: "// VINYL ORDER DRAFTED",
                    body: "\(draftProjectTitle.uppercased()) · \(draftPlan.totalOrderedSqFt) SQ FT READY",
                    projectId: projectId,
                    noteId: createdNoteDTO.id,
                    deepLinkType: "catalogOrders",
                    persistent: false,
                    actionUrl: "ops://catalog/orders?tab=draft",
                    actionLabel: "REVIEW"
                )
            )
        } catch {
            railFailed = true
            print("[VinylOrderSheet] Notification insert failed: \(error)")
        }

        if localSaveFailed {
            statusMessage = "ORDER DRAFTED / LOCAL SYNC PENDING"
        } else if railFailed {
            statusMessage = "ORDER DRAFTED / RAIL FAILED"
        } else {
            statusMessage = "ORDER DRAFTED"
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Tracked inventory: offer to receive the physical rolls into stock,
        // linked to the drafted order line. Silent for untracked companies.
        if stockTrackingActive,
           let createdItemDTO,
           let selection = draftCatalogSelection {
            pendingRollReceipt = VinylRollReceiptContext(
                orderItemId: createdItemDTO.id,
                variantId: selection.variant.id,
                variantLabel: variantDisplayName(selection.variant),
                defaultRollCount: 1,
                defaultRollLengthFeet: 150,
                defaultRollWidthInches: draftSettings.rollWidthInches
            )
        }
    }

    @MainActor
    private func resolveStockTracking() async {
        let active = await offcutInventoryService.isTrackingActive()
        guard active != stockTrackingActive else { return }
        stockTrackingActive = active
        // Re-plan so banked offcuts seed reuse now that tracking is known live.
        recomputePlan()
    }

    @MainActor
    private func receiveRolls(
        context: VinylRollReceiptContext,
        count: Int,
        lengthFeet: Double,
        widthInches: Double
    ) async -> Bool {
        do {
            let created = try await offcutInventoryService.receiveRolls(
                orderItemId: context.orderItemId,
                variantId: context.variantId,
                rollCount: count,
                rollLengthFeet: lengthFeet,
                rollWidthInches: widthInches
            )
            guard !created.isEmpty else { return false }
            recomputePlan()
            statusMessage = created.count == 1 ? "ROLL ON HAND" : "\(created.count) ROLLS ON HAND"
            return true
        } catch {
            print("[VinylOrderSheet] receiveRolls failed: \(error)")
            return false
        }
    }

    /// The most-full on-hand roll that can physically cover this offcut's full
    /// length, or nil when none can (banking is then disabled rather than
    /// truncating the cut).
    private func coveringRoll(for offcut: VinylProducedOffcut) -> CatalogStockUnit? {
        let needFeet = offcut.lengthInches / 12.0
        return onHandRolls.first { ($0.remainingLengthValue ?? 0) + 0.001 >= needFeet }
    }

    private func bankOffcut(_ offcut: VinylProducedOffcut) {
        // Serialize: never start a bank while another is in flight, so two banks
        // cannot read the same roll's remaining length before either debits it.
        guard bankingOffcutIds.isEmpty, !bankedOffcutIds.contains(offcut.id) else { return }
        bankingOffcutIds.insert(offcut.id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            defer { bankingOffcutIds.remove(offcut.id) }
            guard let currentPlan = refreshPlanForOutbound() else { return }
            guard let currentOffcut = VinylOffcutBankingCandidateResolver.resolve(
                offcut,
                in: currentPlan.producedOffcuts
            ) else {
                errorMessage = DeckMaterialsOrderError.vinylPlanChanged.errorDescription
                    ?? "DESIGN CHANGED · REVIEW ORDER"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            guard let variantId = resolvedVariantId,
                  let roll = coveringRoll(for: currentOffcut) else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            do {
                let banked = try await offcutInventoryService.bankOffcut(
                    variantId: variantId,
                    sourceRollId: roll.id,
                    offcut: currentOffcut,
                    projectId: projectId
                )
                if banked != nil {
                    bankedOffcutIds.insert(currentOffcut.id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    // Intentionally NOT recomputing the plan here: re-seeding the
                    // on-screen plan with the just-banked offcut would make this
                    // row vanish mid-confirmation. The on-hand summary updates via
                    // the @Query; cross-job reuse seeds on the next sheet open.
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            } catch {
                print("[VinylOrderSheet] bankOffcut failed: \(error)")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func formatInchesForSheet(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))\""
        }
        return String(format: "%.1f\"", rounded)
    }

    private func formatSqFtForSheet(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// Resolves a tapped remnant against the freshly rebuilt plan immediately before
/// inventory is mutated. Labels may change without changing material, but the
/// stable remnant identity and both physical dimensions must still match.
enum VinylOffcutBankingCandidateResolver {
    static func resolve(
        _ requested: VinylProducedOffcut,
        in currentOffcuts: [VinylProducedOffcut]
    ) -> VinylProducedOffcut? {
        currentOffcuts.first {
            $0.id == requested.id
                && $0.widthInches == requested.widthInches
                && $0.lengthInches == requested.lengthInches
        }
    }
}

/// Lifecycle hooks for VinylOrderSheet's memoized derivations. Kept in a
/// ViewModifier so the main `body` expression stays within the Swift
/// type-checker's budget. `onChange(of:)` on the catalog @Query arrays fires only
/// when their contents actually change (by persistent id), so the catalog tree is
/// rebuilt on real catalog edits — not on the burst of body passes a "MARK
/// ORDERED" write triggers.
private struct VinylOrderMemoHooks: ViewModifier {
    let settings: VinylOrderSettings
    let catalogItems: [CatalogItem]
    let catalogVariants: [CatalogVariant]
    let catalogOptionValues: [CatalogOptionValue]
    let catalogVariantOptionValues: [CatalogVariantOptionValue]
    let onPlanInputChange: () -> Void
    let onCatalogChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: settings) { _, _ in onPlanInputChange() }
            .onChange(of: catalogItems) { _, _ in onCatalogChange() }
            .onChange(of: catalogVariants) { _, _ in onCatalogChange() }
            .onChange(of: catalogOptionValues) { _, _ in onCatalogChange() }
            .onChange(of: catalogVariantOptionValues) { _, _ in onCatalogChange() }
    }
}


enum VinylOrderLayout {
    static let previewHeight = CGFloat(OPSStyle.Layout.touchTargetLarge * 3)
    static let actionBarReserveHeight = CGFloat(OPSStyle.Layout.touchTargetStandard * 2)
    static let labelWidth = CGFloat(OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing5)
    static let previewInset = CGFloat(OPSStyle.Layout.spacing3)
    static let templateEditorHeight = CGFloat(OPSStyle.Layout.touchTargetLarge * 2)
    static let cutTemplateEditorHeight = CGFloat(OPSStyle.Layout.touchTargetLarge)
}
