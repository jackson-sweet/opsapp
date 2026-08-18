//
//  DeckMaterialsSection.swift
//  OPS
//
//  The `// MATERIALS` section on the project Deck tab. Renders the auto-calculated
//  vinyl materials list — cut list, drip edge / clip / 90° flash totals + stick
//  counts, and glue buckets — with crew-editable stick/coverage presets. Once
//  MARK ORDERED freezes a snapshot, it renders the ordered values, locks the
//  presets, and flags DESIGN CHANGED SINCE ORDER on drift.
//
//  Non-vinyl projects render nothing (the tab stays byte-identical). All
//  computation is memoized in @State and refreshed only on drawing-JSON change +
//  initial task — never in `body` (this tab is @Query-driven and perf-sensitive).
//

import SwiftData
import SwiftUI

struct DeckMaterialsSection: View {
    let design: DeckDesign
    let project: Project

    @Environment(\.modelContext) private var modelContext

    /// Memoized resolved materials. Recomputed only on drawing-JSON change +
    /// initial task; the compute pipeline (detection + engine + SwiftData
    /// fetches) never runs in `body`.
    @State private var resolved: DeckMaterialsResolver.Resolved?
    /// True when a live recompute (using the snapshot's own settings) no longer
    /// matches the frozen snapshot. Only meaningful while a snapshot exists.
    @State private var driftFlagged = false
    /// Test seam: when true, `recompute()` is skipped so injected state stands.
    @State private var isInjected = false
    /// Presents the order-confirm sheet for EDIT ORDER (correct an ordered record
    /// without CLEAR + re-order).
    @State private var showingEditOrder = false

    init(design: DeckDesign, project: Project) {
        self.design = design
        self.project = project
    }

    var body: some View {
        // A real container, not Group — Group forwards modifiers to its
        // children, so while nothing has resolved yet there are no children
        // and `.task` would never fire. First render is intentionally empty
        // (resolved == nil), so the recompute task MUST hang off a view that
        // exists regardless of content or the section deadlocks blank.
        VStack(spacing: 0) {
            if let snapshot = design.drawingData.orderedMaterials {
                materialsCard { orderedContent(snapshot) }
            } else if let resolved {
                if let materials = resolved.materials {
                    if let blocker = materials.vinylPlan.blockingMessage {
                        materialsCard {
                            banner(text: blocker, color: OPSStyle.Colors.errorStatus)
                        }
                    } else {
                        materialsCard { liveContent(materials) }
                    }
                } else {
                    // No vinyl on the design. This section IS the MATERIALS
                    // tab now, so an empty tab must say why and name the path
                    // forward — never render blank.
                    noVinylState
                }
            }
        }
        .task { if !isInjected { recompute() } }
        .onChange(of: design.drawingDataJSON) { _, _ in if !isInjected { recompute() } }
        .sheet(isPresented: $showingEditOrder) { editOrderSheet }
    }

    /// Quiet empty state for non-vinyl designs — the materials engine is
    /// vinyl-driven, so the honest message is what unlocks it.
    private var noVinylState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("NO VINYL ON THIS DESIGN")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .tracking(1)
            Text("Assign vinyl in the builder and the materials list builds itself.")
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
        .padding(.horizontal, OPSStyle.Layout.spacing4)
    }

    /// EDIT ORDER re-opens the confirm sheet pre-filled with the CURRENT snapshot
    /// values (RESET still targets the calculator). Confirming rewrites the order
    /// via the service — geometry/drift preserved — then refreshes the drift flag.
    @ViewBuilder
    private var editOrderSheet: some View {
        if let snapshot = design.drawingData.orderedMaterials {
            VinylOrderConfirmSheet(
                projectTitle: project.title,
                deckTitle: design.title,
                rollWidthInches: snapshot.vinylSettings.rollWidthInches,
                calculated: DeckMaterialsOrderConfirmation.calculated(fromSnapshot: snapshot),
                initial: DeckMaterialsOrderConfirmation.stored(fromSnapshot: snapshot),
                onConfirm: { confirmed in
                    DeckMaterialsOrderService.editOrder(design: design, confirmed: confirmed)
                    if !isInjected { recompute() }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Card shell

    @ViewBuilder
    private func materialsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        // No `// MATERIALS` header and no top inset — this card is the body of
        // the MATERIALS tab (a peer of 3D/2D), so the segment already names it
        // and the control bar already spaces it.
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            content()
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Live content (state 3)

    @ViewBuilder
    private func liveContent(_ materials: DeckMaterialsList) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            vinylBlock(
                color: materials.vinylPlan.settings.color,
                headline: vinylHeadline(
                    orderMode: currentSettings.orderMode,
                    orderedSqFt: materials.vinylPlan.totalOrderedSqFt,
                    rollCount: materials.rollCount,
                    rollLengthFeet: currentSettings.fullRollLengthFeet,
                    rollWidthInches: materials.vinylPlan.settings.rollWidthInches
                ),
                cuts: liveCutLines(materials)
            )
            if materials.overlengthStripCount > 0 {
                banner(text: "CUT LONGER THAN ROLL", color: OPSStyle.Colors.warningStatus)
            }
            metricList([
                MaterialRow(label: "DRIP EDGE", value: flashingValue(exactFeet: materials.dripEdge.exactFeet, sticks: materials.dripEdge.sticks, stickFeet: materials.dripEdge.stickFeet)),
                MaterialRow(label: "CLIP", value: flashingValue(exactFeet: materials.clip.exactFeet, sticks: materials.clip.sticks, stickFeet: materials.clip.stickFeet)),
                MaterialRow(label: "90 FLASH", value: flashingValue(exactFeet: materials.ninetyFlash.exactFeet, sticks: materials.ninetyFlash.sticks, stickFeet: materials.ninetyFlash.stickFeet)),
                MaterialRow(label: "GLUE", value: glueValue(buckets: materials.glueBuckets, coverage: currentSettings.glueCoverageSqFt))
            ])
            steppers()
        }
    }

    // MARK: - Ordered content (state 4)

    @ViewBuilder
    private func orderedContent(_ snapshot: DeckMaterialsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            vinylBlock(
                color: snapshot.vinylColor,
                headline: vinylHeadline(
                    orderMode: snapshot.orderMode,
                    orderedSqFt: snapshot.vinylOrderedSqFt,
                    rollCount: snapshot.orderedRollCount ?? 0,
                    rollLengthFeet: snapshot.fullRollLengthFeet,
                    rollWidthInches: snapshot.vinylSettings.rollWidthInches
                ),
                cuts: snapshotCutLines(snapshot)
            )
            metricList([
                MaterialRow(label: "DRIP EDGE", value: flashingValue(exactFeet: snapshot.dripEdgeFeet, sticks: snapshot.dripSticks, stickFeet: snapshot.settings.dripStickFeet)),
                MaterialRow(label: "CLIP", value: flashingValue(exactFeet: snapshot.clipFeet, sticks: snapshot.clipSticks, stickFeet: snapshot.settings.clipStickFeet)),
                MaterialRow(label: "90 FLASH", value: flashingValue(exactFeet: snapshot.ninetyFeet, sticks: snapshot.ninetySticks, stickFeet: snapshot.settings.ninetyStickFeet)),
                MaterialRow(label: "GLUE", value: glueValue(buckets: snapshot.glueBuckets, coverage: snapshot.settings.glueCoverageSqFt))
            ])

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("ORDERED \(DateHelper.simpleDateString(from: snapshot.orderedAt).uppercased())")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.successStatus)
                if snapshot.isOrderedEdited {
                    Text("ADJUSTED")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .tracking(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, OPSStyle.Layout.spacing1)

            if driftFlagged {
                banner(text: "DESIGN CHANGED SINCE ORDER", color: OPSStyle.Colors.warningStatus)
            }

            editOrderButton
        }
    }

    /// Re-open the confirm sheet to correct an ordered record without CLEAR +
    /// re-order. Subtle bordered action — the ordered card stays a scan surface.
    private var editOrderButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingEditOrder = true
        } label: {
            Text("EDIT ORDER")
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
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
        .padding(.top, OPSStyle.Layout.spacing1)
    }

    // MARK: - Rows

    /// The vinyl block. `headline` is the order line — `ORDER 260 SQ FT` in
    /// cut-list mode, `3 ROLLS @ 75' × 72"` in full-roll mode. The itemized cut
    /// lines always stay below as the on-site cutting guide.
    private func vinylBlock(color: String, headline: String, cuts: [String]) -> some View {
        let trimmedColor = color.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("VINYL")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer(minLength: 0)
                Text(headline)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            Text(trimmedColor.isEmpty ? "FIELD CONFIRM" : trimmedColor.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(trimmedColor.isEmpty ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryText)
            if cuts.isEmpty {
                Text("—")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            } else {
                ForEach(Array(cuts.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    /// Order headline for a given mode. Roll mode reads `N ROLLS @ L' × W"`.
    private func vinylHeadline(orderMode: VinylOrderMode, orderedSqFt: Int, rollCount: Int, rollLengthFeet: Double, rollWidthInches: Double) -> String {
        guard orderMode == .fullRolls else { return "ORDER \(orderedSqFt) SQ FT" }
        return "\(rollCount) ROLL\(rollCount == 1 ? "" : "S") @ \(Int(rollLengthFeet))' × \(Int(rollWidthInches.rounded()))\""
    }

    /// One label/value line in the materials list. `label` is unique per list,
    /// so it doubles as the stable identity.
    private struct MaterialRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// The flashing + glue lines, each given a little vertical room and parted by
    /// a single hairline so every item reads as its own scannable line
    /// (glass + hairlines — DESIGN.md). Hairlines sit BETWEEN rows only, never
    /// leading or trailing.
    private func metricList(_ rows: [MaterialRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                metricRow(row.label, row.value)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(OPSStyle.Colors.line)
                        .frame(height: OPSStyle.Layout.Border.standard)
                }
            }
        }
    }

    private func flashingValue(exactFeet: Double, sticks: Int, stickFeet: Double) -> String {
        guard exactFeet > 0 else { return "—" }
        return "\(Int(ceil(exactFeet))) FT · \(sticks) STICK\(sticks == 1 ? "" : "S") @ \(Int(stickFeet))'"
    }

    private func glueValue(buckets: Int, coverage: Double) -> String {
        buckets <= 0 ? "—" : "\(buckets) BUCKET\(buckets == 1 ? "" : "S") · 1 PER \(Int(coverage)) SQ FT"
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
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
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

    // MARK: - Steppers (live only)

    private func steppers() -> some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            orderModeControl()
            if currentSettings.orderMode == .fullRolls {
                stepperRow(label: "ROLL LENGTH", value: presetBinding(\.fullRollLengthFeet), range: 25...300, step: 5) { "\(Int($0))'" }
            }
            stepperRow(label: "DRIP STICK", value: presetBinding(\.dripStickFeet), range: 4...20, step: 1) { "\(Int($0))'" }
            stepperRow(label: "90 STICK", value: presetBinding(\.ninetyStickFeet), range: 4...20, step: 1) { "\(Int($0))'" }
            stepperRow(label: "CLIP STICK", value: presetBinding(\.clipStickFeet), range: 4...20, step: 1) { "\(Int($0))'" }
            stepperRow(label: "COVERAGE", value: presetBinding(\.glueCoverageSqFt), range: 100...1000, step: 25) { "\(Int($0)) SQ FT" }
        }
        .padding(.top, OPSStyle.Layout.spacing1)
    }

    /// `CUT LIST | FULL ROLLS` segmented control — the vinyl purchasing mode.
    /// Writes `materialsSettings.orderMode` (syncs company-wide), light haptic.
    private func orderModeControl() -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("ORDER")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: Self.presetLabelWidth, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(VinylOrderMode.allCases, id: \.self) { mode in
                    Button {
                        setOrderMode(mode)
                    } label: {
                        Text(mode.presetLabel)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(currentSettings.orderMode == mode ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: OPSStyle.Layout.touchTargetMin)
                            .background(currentSettings.orderMode == mode ? OPSStyle.Colors.surfaceActive : Color.clear)
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

    private func setOrderMode(_ mode: VinylOrderMode) {
        guard currentSettings.orderMode != mode else { return }
        var settings = currentSettings
        settings.orderMode = mode
        var data = design.drawingData
        data.materialsSettings = settings
        design.drawingData = data
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func stepperRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: @escaping (Double) -> String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(label)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(width: Self.presetLabelWidth, alignment: .leading)
                Text(display(value.wrappedValue))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
        }
        .tint(OPSStyle.Colors.secondaryText)
    }

    private static let presetLabelWidth = CGFloat(OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing5)

    // MARK: - Cut lines

    private func liveCutLines(_ materials: DeckMaterialsList) -> [String] {
        VinylCutGroup
            .groups(from: materials.vinylPlan.surfaces.flatMap(\.purchasedCuts))
            .map(\.orderFragment)
    }

    private func snapshotCutLines(_ snapshot: DeckMaterialsSnapshot) -> [String] {
        snapshot.cutGroups.map { group in
            "\(group.count) CUT\(group.count == 1 ? "" : "S") @ \(vinylFormatFeetAndInches(group.lengthInches))"
        }
    }

    // MARK: - Presets

    private var currentSettings: DeckMaterialsSettings {
        design.drawingData.materialsSettings ?? DeckMaterialsSettings()
    }

    /// Read/write a single preset field. Writing mutates the design's drawing JSON
    /// (accessor marks needsSync + updatedAt → syncs company-wide) and fires a
    /// light haptic. The drawing-JSON change drives the memoized recompute.
    private func presetBinding(_ keyPath: WritableKeyPath<DeckMaterialsSettings, Double>) -> Binding<Double> {
        Binding(
            get: { currentSettings[keyPath: keyPath] },
            set: { newValue in
                var settings = currentSettings
                settings[keyPath: keyPath] = newValue
                var data = design.drawingData
                data.materialsSettings = settings
                design.drawingData = data
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        )
    }

    // MARK: - Compute

    private func recompute() {
        let data = design.drawingData
        let taskDisplays = fetchTaskTypeDisplays()
        let vinylHints = fetchVinylHintByProductId()

        resolved = DeckMaterialsResolver.resolve(
            data: data,
            settings: data.materialsSettings ?? DeckMaterialsSettings(),
            vinylSettings: defaultSeededVinylSettings(data),
            taskTypeDisplays: taskDisplays,
            vinylHintByProductId: vinylHints
        )

        if let snapshot = data.orderedMaterials {
            let recompute = DeckMaterialsResolver.resolve(
                data: data,
                settings: snapshot.settings,
                vinylSettings: snapshot.vinylSettings,
                taskTypeDisplays: taskDisplays,
                vinylHintByProductId: vinylHints
            )
            if let materials = recompute.materials {
                driftFlagged = materials.driftKey != DeckMaterialsDriftKey(snapshot: snapshot)
            } else {
                // Snapshot exists but the design no longer resolves any materials.
                driftFlagged = true
            }
        } else {
            driftFlagged = false
        }
    }

    private func fetchTaskTypeDisplays() -> [String] {
        let pid = project.id
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.projectId == pid && $0.deletedAt == nil }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).compactMap { $0.taskType?.display }
    }

    /// `productId → vinyl-hint` blob for detection rule 3. Keyed by `Product.id`
    /// (what an `AssignedItem.productId` references), with each product's linked
    /// catalog item folded in — see `DeckVinylHintBuilder`.
    private func fetchVinylHintByProductId() -> [String: String] {
        let cid = project.companyId
        let productDescriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.companyId == cid }
        )
        let catalogDescriptor = FetchDescriptor<CatalogItem>(
            predicate: #Predicate { $0.companyId == cid && $0.deletedAt == nil }
        )
        let products = (try? modelContext.fetch(productDescriptor)) ?? []
        let catalogItems = (try? modelContext.fetch(catalogDescriptor)) ?? []
        return DeckVinylHintBuilder.build(products: products, catalogItems: catalogItems)
    }

    private func defaultSeededVinylSettings(_ data: DeckDrawingData) -> VinylOrderSettings {
        var settings = data.vinylOrderSettings ?? .default
        if let id = data.config.vinylCatalogItemId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            settings.catalogItemId = id
        }
        return settings
    }
}

#if DEBUG
extension DeckMaterialsSection {
    /// Test seam: inject precomputed state so the snapshot harness renders each
    /// UI state without any SwiftData fetches.
    init(
        design: DeckDesign,
        project: Project,
        injectedResolved: DeckMaterialsResolver.Resolved?,
        driftFlagged: Bool
    ) {
        self.design = design
        self.project = project
        self._resolved = State(initialValue: injectedResolved)
        self._driftFlagged = State(initialValue: driftFlagged)
        self._isInjected = State(initialValue: true)
    }
}
#endif
