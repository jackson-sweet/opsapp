//
//  DeckTabView.swift
//  OPS
//
//  Deck tab for project details. Shows 3D/2D interactive model of the
//  project's deck design, or an empty state with CTA to create one.
//

import SwiftUI
import SwiftData

enum DeckTabViewMode: String {
    case threeD = "3D"
    case twoD = "2D"
}

struct DeckTabView: View {
    let project: Project
    let onCreateDeckDesign: () -> Void
    let onEditDeckDesign: (DeckDesign) -> Void

    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewMode: DeckTabViewMode = .threeD
    @State private var remoteFetchAttemptedProjectId: String?
    /// `true` while the user is panning or pinching the 3D scene. Drives the
    /// badge fade — badges hide during camera movement so they don't obstruct
    /// the geometry the user is trying to inspect. Reset to `false` whenever
    /// the view mode leaves `.threeD` so badges can't get stuck hidden.
    @State private var is3DInteracting = false

    // Bug 4 fix: use @Query so SwiftData automatically invalidates this view
    // when a DeckDesign is inserted/updated for this project — no manual
    // loadDesign() or onAppear dance needed. The previous @State + loadDesign()
    // pattern missed the case where DeckBuilderView saves and dismisses while
    // ProjectDetailsView stays alive, leaving the deck tab stale until the
    // user navigated away and back.
    @Query private var allDesigns: [DeckDesign]

    /// Most-recently-updated non-deleted design for this project.
    private var deckDesign: DeckDesign? {
        DeckDesign.displayCandidate(in: allDesigns, forProjectId: project.id)
    }

    var body: some View {
        Group {
            if let design = deckDesign, design.hasRenderableGeometry {
                designViewer(design: design)
            } else {
                emptyState
            }
        }
        .task(id: project.id) {
            await fetchRemoteDeckDesignIfNeeded()
        }
    }

    // MARK: - Design Viewer

    private func designViewer(design: DeckDesign) -> some View {
        VStack(spacing: 0) {
            controlBar(design: design)

            // Bug 9327599a — rendering area sits inside ProjectDetailsView's
            // ScrollView/LazyVStack, where maxHeight: .infinity collapses to
            // the children's intrinsic size (GeometryReader and SCNView both
            // expose ~0 intrinsic height). Result: the 2D/3D viewport got a
            // few-point-tall sliver and the drawing rendered "tiny" even
            // after the centerViewport math zoomed it correctly.
            //
            // Fix: lock the rendering area to a 1:1 aspect ratio against the
            // available width — produces a substantial square viewport that
            // scales to fill the screen width and gives both 2D blueprint and
            // 3D scene enough room to read clearly. Horizontal padding gives
            // the requested breathing room from the screen edges.
            Group {
                switch viewMode {
                case .threeD:
                    // `hasAnyClosedSurface` rather than `isClosed` — the latter
                    // requires a single Hamiltonian cycle (false for two
                    // disjoint deck footprints, false for any multi-level
                    // design where the top-level vertices/edges arrays are
                    // empty). `hasAnyClosedSurface` returns true as soon as
                    // any face is closed on any level. Bug ee787f29 follow-up.
                    if design.drawingData.hasAnyClosedSurface {
                        DeckTab3DView(drawingData: design.drawingData,
                                      onInteractingChange: { is3DInteracting = $0 })
                    } else {
                        incompleteDesignMessage
                    }
                case .twoD:
                    DeckTab2DView(drawingData: design.drawingData)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            // Floating overlay — title pinned top-left of the rendering
            // viewport with surface metadata below it. Replaces the previous
            // bottom infoBar so the viewport owns its identifying chrome.
            .overlay(alignment: .topLeading) {
                floatingDesignInfo(design: design)
                    .padding(.leading, OPSStyle.Layout.spacing2_5)
                    .padding(.top, OPSStyle.Layout.spacing2_5)
                    .allowsHitTesting(false)
                    // Fade badges out while the user pans/zooms the 3D camera
                    // so they don't obscure structural members being inspected.
                    // Only active in 3D mode — 2D pans don't interact with these
                    // recognizers, so `is3DInteracting` stays false there.
                    // Reduce Motion: nil animation = instant snap (no fade at all),
                    // which is correct — the opacity change itself still happens,
                    // but without any motion that might cause vestibular discomfort.
                    .opacity(is3DInteracting && viewMode == .threeD ? 0 : 1)
                    .animation(reduceMotion ? nil : OPSStyle.Animation.standard,
                               value: is3DInteracting)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .animation(OPSStyle.Animation.fast, value: viewMode)
        }
    }

    // MARK: - Floating Design Info (overlay top-left of viewport)

    /// Design title plus a per-level chip set, anchored to the top-leading
    /// corner of the rendering viewport. Each level reports its own height,
    /// area, railing, siding and stair detail — bug 258378ac. Supersedes the
    /// whole-design aggregate line (bug 38c8c58c) and the original loose
    /// sqft / linear-foot / material badges (bug 8dbecc70).
    private func floatingDesignInfo(design: DeckDesign) -> some View {
        let chips = levelChips(for: design)
        return VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            titlePill(project.title)

            ForEach(chips) { chip in
                levelChipView(chip)
            }
        }
    }

    /// Single-line design-name pill — ellipsis on overflow so long names
    /// never push the chips off the viewport.
    private func titlePill(_ title: String) -> some View {
        Text(title)
            .font(OPSStyle.Typography.cardBody)
            .fontWeight(.semibold)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .frame(maxWidth: Self.chipWidth, alignment: .leading)
            .glassDense(cornerRadius: OPSStyle.Layout.chipRadius)
    }

    /// One chip per deck level — or a single "DECK" chip for a single-level
    /// design. The header carries level identity + height (the attribute
    /// that defines a level); the flow below carries area, railing, siding
    /// and stairs — only the metrics that resolve for that level.
    ///
    /// Static by design: this is ambient reference chrome, so it carries no
    /// entry animation. Per the OPSStyle motion budget, movement is reserved
    /// for transitions that communicate change — these chips communicate
    /// state, so they simply render.
    private func levelChipView(_ chip: DeckLevelChipData) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                if let accent = chip.accentColor {
                    Circle()
                        .fill(accent)
                        .frame(
                            width: OPSStyle.Layout.Indicator.dotSM,
                            height: OPSStyle.Layout.Indicator.dotSM
                        )
                }

                Text(chip.name)
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Spacer(minLength: OPSStyle.Layout.spacing2)

                Text(chip.heightText ?? "—")
                    .font(OPSStyle.Typography.category)
                    .monospacedDigit()
                    .foregroundColor(
                        chip.heightText == nil
                            ? OPSStyle.Colors.tertiaryText
                            : OPSStyle.Colors.primaryText
                    )
            }

            if !chip.metrics.isEmpty {
                FlowLayout(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(chip.metrics) { metric in
                        metricToken(label: metric.label, value: metric.value)
                    }
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .frame(width: Self.chipWidth, alignment: .leading)
        .glassDense(cornerRadius: OPSStyle.Layout.chipRadius)
    }

    /// A single metric: a dim uppercase micro-label butted against its mono
    /// value (e.g. `RAILING 64 FT GLASS`). Concatenated into one `Text` so
    /// `FlowLayout` treats the label + value as one atomic, non-wrapping unit.
    private func metricToken(label: String, value: String) -> some View {
        (
            Text(label + " ")
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            + Text(value)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.primaryText)
        )
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: - Control Bar

    private func controlBar(design: DeckDesign) -> some View {
        HStack {
            SegmentedControl(
                selection: $viewMode,
                options: [
                    (DeckTabViewMode.threeD, "3D"),
                    (DeckTabViewMode.twoD, "2D")
                ]
            )
            .frame(width: 120)
            .onChange(of: viewMode) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Clear the interaction flag when leaving 3D so badges can't
                // get stuck hidden after a mode switch mid-gesture.
                is3DInteracting = false
            }

            Spacer()

            if permissionStore.can("deck_builder.edit", requiredScope: "assigned") {
                Button {
                    onEditDeckDesign(design)
                } label: {
                    Text("EDIT DESIGN")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.wizardAccent)

                    Text("DECK DESIGN")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.bottom, OPSStyle.Layout.spacing3)

                Text("Create a deck design to visualize your build, generate estimates, and share with clients.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(4)
                    .padding(.bottom, OPSStyle.Layout.spacing4)

                if permissionStore.can("deck_builder.create", requiredScope: "assigned") {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onCreateDeckDesign()
                    } label: {
                        HStack {
                            Text("CREATE DECK DESIGN")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.buttonText)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.buttonText)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.wizardAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            }
            .padding(28)
            .glassSurface()
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            Spacer()
        }
    }

    // MARK: - Incomplete Design Message

    private var incompleteDesignMessage: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            Spacer()
            Image(systemName: "square.dashed")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("CLOSE THE POLYGON TO SEE THE 3D MODEL")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .tracking(1)
            Text("Switch to 2D to see the current design")
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// Fixed width for the floating title pill and level chips. Bounds the
    /// overlay so it never spans the viewport, and gives `FlowLayout` a
    /// definite width to wrap metric tokens against.
    private static let chipWidth: CGFloat = 200

    /// Build one chip per level. Multi-level designs report each `DeckLevel`
    /// in draw order; a single-level design collapses to one "DECK" chip
    /// covering the top-level geometry.
    private func levelChips(for design: DeckDesign) -> [DeckLevelChipData] {
        let data = design.drawingData
        let scale = data.effectiveScaleFactor

        if data.isMultiLevel {
            return data.levels
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { level in
                    buildChip(
                        id: level.id,
                        name: level.name.uppercased(),
                        accentColor: level.displayColor.swiftUIColor,
                        elevation: level.elevation,
                        vertices: level.vertices,
                        edges: level.edges,
                        detectedSurfaces: level.detectedSurfaces,
                        orderedPositions: level.orderedPositions,
                        isClosed: level.isClosed,
                        scale: scale
                    )
                }
        }

        return [
            buildChip(
                id: design.id,
                name: "DECK",
                accentColor: nil,
                elevation: data.overallElevation,
                vertices: data.vertices,
                edges: data.edges,
                detectedSurfaces: data.detectedSurfaces,
                orderedPositions: data.orderedPositions,
                isClosed: data.isClosed,
                scale: scale
            )
        ]
    }

    /// Assemble the height + metric set for one level's geometry. Only the
    /// metrics that resolve for the level are emitted, so an uncalibrated or
    /// feature-light level still produces a clean, sparse chip.
    private func buildChip(
        id: String,
        name: String,
        accentColor: Color?,
        elevation: Double?,
        vertices: [DeckVertex],
        edges: [DeckEdge],
        detectedSurfaces: [DetectedSurface],
        orderedPositions: [CGPoint],
        isClosed: Bool,
        scale: Double
    ) -> DeckLevelChipData {
        var metrics: [ChipMetric] = []

        // Square footage — the same per-surface logic as
        // `DeckDrawingData.totalRealWorldArea`, scoped to this level.
        // Absent only when the level encloses no measurable surface.
        if let area = levelAreaSquareFeet(
            detectedSurfaces: detectedSurfaces,
            orderedPositions: orderedPositions,
            isClosed: isClosed,
            scale: scale
        ) {
            metrics.append(
                ChipMetric(label: "AREA", value: "\(Int(area.rounded()).formatted()) FT²")
            )
        }

        // Railing — linear feet across every edge carrying a railing
        // config, plus the railing type(s).
        let railingEdges = edges.filter { $0.railingConfig != nil }
        if !railingEdges.isEmpty {
            metrics.append(
                ChipMetric(
                    label: "RAILING",
                    value: railingValue(railingEdges, vertices: vertices, scale: scale)
                )
            )
        }

        // House siding — cladding material on house edges, when set.
        let sidings = edges
            .filter { $0.edgeType == .houseEdge }
            .compactMap { $0.houseEdgeMaterial }
        if !sidings.isEmpty {
            metrics.append(ChipMetric(label: "SIDING", value: materialValue(sidings)))
        }

        // Stairs — count of edges on this level carrying a stair config.
        let stairCount = edges.filter { $0.stairConfig != nil }.count
        if stairCount > 0 {
            metrics.append(ChipMetric(label: "STAIRS", value: "\(stairCount)"))
        }

        return DeckLevelChipData(
            id: id,
            name: name,
            accentColor: accentColor,
            heightText: elevation.map(feetText),
            metrics: metrics
        )
    }

    /// Real-world floor area for one level in square feet — mirrors the
    /// per-surface branch of `DeckDrawingData.totalRealWorldArea`, using the
    /// drawing's effective scale. Returns nil only when the level encloses
    /// nothing measurable (open shape, or every surface self-intersecting).
    private func levelAreaSquareFeet(
        detectedSurfaces: [DetectedSurface],
        orderedPositions: [CGPoint],
        isClosed: Bool,
        scale: Double
    ) -> Double? {
        let areaSquareInches: Double
        if detectedSurfaces.isEmpty {
            guard isClosed,
                  !PolygonMath.isSelfIntersecting(vertices: orderedPositions) else { return nil }
            areaSquareInches = PolygonMath.realWorldArea(
                vertices: orderedPositions,
                scaleFactor: scale
            )
        } else {
            areaSquareInches = detectedSurfaces.reduce(0) { partial, surface in
                guard !PolygonMath.isSelfIntersecting(vertices: surface.positions) else { return partial }
                return partial + PolygonMath.realWorldArea(
                    vertices: surface.positions,
                    scaleFactor: scale
                )
            }
        }

        let squareFeet = areaSquareInches / 144.0
        return squareFeet >= 0.5 ? squareFeet : nil
    }

    /// Railing linear feet plus the railing type — e.g. `64 FT GLASS`.
    /// Falls back to the type alone when no edge length resolves, and to
    /// `MIXED` when a level carries more than one type.
    private func railingValue(
        _ edges: [DeckEdge],
        vertices: [DeckVertex],
        scale: Double
    ) -> String {
        let types = edges.compactMap { $0.railingConfig?.railingType }
        let distinct = RailingType.allCases.filter { types.contains($0) }
        let typeText = distinct.count == 1
            ? distinct[0].displayName.uppercased()
            : "MIXED"

        let totalInches = edges
            .compactMap { edgeLengthInches($0, vertices: vertices, scale: scale) }
            .reduce(0, +)
        let linearFeet = totalInches / 12.0

        guard linearFeet >= 0.5 else { return typeText }
        return "\(Int(linearFeet.rounded()).formatted()) FT \(typeText)"
    }

    /// House-edge cladding — a single material name, or `MIXED` when a
    /// level's house edges carry more than one.
    private func materialValue(_ materials: [HouseEdgeMaterial]) -> String {
        let distinct = HouseEdgeMaterial.allCases.filter { materials.contains($0) }
        return distinct.count == 1 ? distinct[0].displayName.uppercased() : "MIXED"
    }

    /// Real-world length of an edge in inches — the stored dimension when
    /// the edge carries one, otherwise derived from canvas length and the
    /// drawing's effective scale. Nil only when the edge references a
    /// missing vertex.
    private func edgeLengthInches(
        _ edge: DeckEdge,
        vertices: [DeckVertex],
        scale: Double
    ) -> Double? {
        if let dimension = edge.dimension, dimension > 0 { return dimension }

        guard let start = vertices.first(where: { $0.id == edge.startVertexId })?.position,
              let end = vertices.first(where: { $0.id == edge.endVertexId })?.position
        else { return nil }

        return SnapEngine.distance(start, end) / scale
    }

    /// Format a height in feet — whole numbers drop the decimal (`9 FT`),
    /// fractional heights keep one place (`8.5 FT`).
    private func feetText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) FT"
        }
        return String(format: "%.1f FT", rounded)
    }

    @MainActor
    private func fetchRemoteDeckDesignIfNeeded() async {
        guard deckDesign?.hasRenderableGeometry != true else { return }
        guard remoteFetchAttemptedProjectId != project.id else { return }
        guard let companyId = effectiveCompanyId else {
            print("[DeckTabView] Skipping deck design repair fetch — no company id")
            return
        }

        remoteFetchAttemptedProjectId = project.id

        do {
            let dtos = try await DeckDesignRepository(companyId: companyId)
                .fetchForProject(DeckDesign.canonicalUUIDString(project.id))
            guard !dtos.isEmpty else { return }

            try mergeRemoteDeckDesigns(dtos)
            print("[DeckTabView] Repaired \(dtos.count) deck design(s) for project \(project.id)")
        } catch {
            print("[DeckTabView] Deck design repair fetch failed for project \(project.id): \(error)")
        }
    }

    private var effectiveCompanyId: String? {
        [
            project.companyId,
            dataController.currentUser?.companyId,
            UserDefaults.standard.string(forKey: "currentUserCompanyId"),
            UserDefaults.standard.string(forKey: "company_id")
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    @MainActor
    private func mergeRemoteDeckDesigns(_ dtos: [SupabaseDeckDesignDTO]) throws {
        for dto in dtos {
            let pendingFields = pendingDeckFields(for: dto.id)
            let acceptedFields = Set(DeckDesign.serverMergeFields).subtracting(pendingFields)

            if let existing = try localDeckDesign(matching: dto.id) {
                existing.applyServerSnapshot(dto, accepting: acceptedFields)
                existing.lastSyncedAt = Date()
                existing.needsSync = !pendingFields.isEmpty
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                modelContext.insert(model)
            }
        }

        try modelContext.save()
    }

    @MainActor
    private func localDeckDesign(matching id: String) throws -> DeckDesign? {
        let canonicalId = DeckDesign.canonicalUUIDString(id)
        let lowercasedId = canonicalId.lowercased()
        let uppercasedId = canonicalId.uppercased()
        let exactDescriptor = FetchDescriptor<DeckDesign>(
            predicate: #Predicate {
                $0.id == canonicalId || $0.id == lowercasedId || $0.id == uppercasedId
            }
        )

        if let exactMatch = try modelContext.fetch(exactDescriptor).first {
            return exactMatch
        }

        let allDescriptor = FetchDescriptor<DeckDesign>()
        return try modelContext.fetch(allDescriptor).first {
            DeckDesign.canonicalUUIDString($0.id) == canonicalId
        }
    }

    @MainActor
    private func pendingDeckFields(for id: String) -> Set<String> {
        let entityType = SyncEntityType.deckDesign.rawValue
        let canonicalId = DeckDesign.canonicalUUIDString(id)
        let lowercasedId = canonicalId.lowercased()
        let uppercasedId = canonicalId.uppercased()
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate {
                $0.entityType == entityType &&
                ($0.entityId == canonicalId || $0.entityId == lowercasedId || $0.entityId == uppercasedId) &&
                $0.status == "pending"
            }
        )

        guard let operations = try? modelContext.fetch(descriptor) else { return [] }

        var fields = Set<String>()
        for operation in operations {
            fields.formUnion(operation.getChangedFields())
        }
        return fields
    }
}

// MARK: - Level Chip Model

/// View-model for one floating level chip in `DeckTabView`, built by
/// `levelChips(for:)` from a `DeckDesign`'s geometry.
private struct DeckLevelChipData: Identifiable {
    /// `DeckLevel.id` for a multi-level design, or `DeckDesign.id` for the
    /// single-level fallback chip.
    let id: String
    /// Uppercased level name (`LEVEL 1`), or `DECK` for a single-level design.
    let name: String
    /// Level render colour, surfaced as a key dot so the chip ties back to
    /// the 2D/3D scene. Nil for single-level designs — nothing to key.
    let accentColor: Color?
    /// Formatted level height (`9 FT`), or nil when no elevation is set.
    let heightText: String?
    /// Resolved per-level metrics — area, railing, siding, stairs. Only the
    /// metrics that apply to the level are present.
    let metrics: [ChipMetric]
}

/// A single labelled metric inside a level chip.
private struct ChipMetric: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}
