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

    init(design: DeckDesign, project: Project) {
        self.design = design
        self.project = project
    }

    var body: some View {
        Group {
            if let snapshot = design.drawingData.orderedMaterials {
                materialsCard { orderedContent(snapshot) }
            } else if let resolved {
                if let materials = resolved.materials {
                    materialsCard { liveContent(materials) }
                } else if !resolved.vinylInputs.isEmpty {
                    // Vinyl set present but scale unconfirmed.
                    materialsCard { banner(text: "CONFIRM ONE EDGE LENGTH", color: OPSStyle.Colors.warningStatus) }
                }
                // else: no vinyl set → render nothing (tab identical for non-vinyl).
            }
        }
        .task { if !isInjected { recompute() } }
        .onChange(of: design.drawingDataJSON) { _, _ in if !isInjected { recompute() } }
    }

    // MARK: - Card shell

    @ViewBuilder
    private func materialsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// MATERIALS")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.1)
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
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    // MARK: - Live content (state 3)

    @ViewBuilder
    private func liveContent(_ materials: DeckMaterialsList) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            vinylBlock(
                color: materials.vinylPlan.settings.color,
                cuts: liveCutLines(materials),
                orderedSqFt: materials.vinylPlan.totalOrderedSqFt
            )
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
                cuts: snapshotCutLines(snapshot),
                orderedSqFt: snapshot.vinylOrderedSqFt
            )
            metricList([
                MaterialRow(label: "DRIP EDGE", value: flashingValue(exactFeet: snapshot.dripEdgeFeet, sticks: snapshot.dripSticks, stickFeet: snapshot.settings.dripStickFeet)),
                MaterialRow(label: "CLIP", value: flashingValue(exactFeet: snapshot.clipFeet, sticks: snapshot.clipSticks, stickFeet: snapshot.settings.clipStickFeet)),
                MaterialRow(label: "90 FLASH", value: flashingValue(exactFeet: snapshot.ninetyFeet, sticks: snapshot.ninetySticks, stickFeet: snapshot.settings.ninetyStickFeet)),
                MaterialRow(label: "GLUE", value: glueValue(buckets: snapshot.glueBuckets, coverage: snapshot.settings.glueCoverageSqFt))
            ])

            Text("ORDERED \(DateHelper.simpleDateString(from: snapshot.orderedAt).uppercased())")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.successStatus)
                .padding(.top, OPSStyle.Layout.spacing1)

            if driftFlagged {
                banner(text: "DESIGN CHANGED SINCE ORDER", color: OPSStyle.Colors.warningStatus)
            }
        }
    }

    // MARK: - Rows

    private func vinylBlock(color: String, cuts: [String], orderedSqFt: Int) -> some View {
        let trimmedColor = color.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("VINYL")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer(minLength: 0)
                Text("ORDER \(orderedSqFt) SQ FT")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .monospacedDigit()
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
            stepperRow(label: "DRIP STICK", value: presetBinding(\.dripStickFeet), range: 4...20, step: 1) { "\(Int($0))'" }
            stepperRow(label: "90 STICK", value: presetBinding(\.ninetyStickFeet), range: 4...20, step: 1) { "\(Int($0))'" }
            stepperRow(label: "CLIP STICK", value: presetBinding(\.clipStickFeet), range: 4...20, step: 1) { "\(Int($0))'" }
            stepperRow(label: "COVERAGE", value: presetBinding(\.glueCoverageSqFt), range: 100...1000, step: 25) { "\(Int($0)) SQ FT" }
        }
        .padding(.top, OPSStyle.Layout.spacing1)
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
        var settings = VinylOrderSettings.default
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
