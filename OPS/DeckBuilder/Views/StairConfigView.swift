// OPS/OPS/DeckBuilder/Views/StairConfigView.swift

import SwiftUI

/// The single stair authoring surface. A stair's vertical drop is entered in
/// exactly one of three vocabularies — a tread count, a measured height, or
/// the level it connects down to — because those are the three ways a deck
/// builder actually knows the number. Treads/Height commit a fixed-rise stair
/// on the edge; Level commits a `LevelConnection` whose rise keeps tracking
/// the two levels' heights. An edge carries one stair, never both kinds.
///
/// Every geometry lookup goes through the view model's level-aware accessors
/// (`findEdge` / `activeLevel`) — the previous sheet read the top-level
/// vertex/edge arrays, which are empty on multi-level drawings, so its rise
/// silently collapsed to 0 and its inputs reset on every open.
struct StairConfigView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    /// Overrides the data-derived starting mode (snapshot proofs; a future
    /// deep link could use it too). Nil means derive from the edge's state.
    var initialMode: RiseMode? = nil

    enum RiseMode: String, CaseIterable {
        case treads
        case height
        case level

        var displayName: String {
            switch self {
            case .treads: return "Treads"
            case .height: return "Height"
            case .level:  return "Level"
            }
        }
    }

    @State private var mode: RiseMode = .height
    /// Treads and height are two readings of ONE drop, so they live in one
    /// value that keeps them in step — entering either moves the other, and
    /// switching modes can never show a stale number (bug 46c2d6eb).
    @State private var riseEntry = DeckStairRiseEntry(totalRiseInches: 30, risePerStep: 7.5)
    @State private var targetLevelId: String?
    /// Edge chosen inside the sheet when it opened without one.
    @State private var pickedEdgeId: String?
    @State private var widthText: String = "48"
    @State private var runPerTread: Double = 10.0
    @State private var addRailing: Bool = false
    @State private var railingType: RailingType = .parapetWall
    @State private var alignment: StairAlignment = .center
    @State private var offsetText: String = "0"
    @State private var flipDirection: Bool = false
    @State private var showingARHeight = false
    @State private var didLoad = false

    // MARK: - Context

    /// The single deck edge the operator has selected, if the selection is
    /// unambiguous. Selecting an edge by marquee (or toggling one off a
    /// multi-selection) leaves `editingEdgeId` nil while the selection still
    /// names exactly one edge — without this, opening Stairs from the toolbar
    /// in that state showed a sheet with nothing in it.
    private var soleSelectedDeckEdgeId: String? {
        let ids = viewModel.selection.selectedEdgeIds
        guard ids.count == 1, let id = ids.first,
              viewModel.findEdge(byId: id)?.edgeType != .houseEdge else { return nil }
        return id
    }

    private var editingEdgeId: String? {
        viewModel.editingEdgeId ?? pickedEdgeId ?? soleSelectedDeckEdgeId
    }

    /// The sheet has to ask which edge only when nothing else answered it.
    private var needsEdgeChoice: Bool {
        viewModel.editingEdgeId == nil && soleSelectedDeckEdgeId == nil
    }

    /// Rise-per-step lives on the entry so a code-envelope change re-derives
    /// whichever vocabulary the operator is NOT currently typing in.
    private var risePerStep: Double { riseEntry.risePerStep }

    /// Level-aware edge resolution — never the top-level array.
    private var targetEdge: DeckEdge? {
        guard let id = editingEdgeId,
              let edge = viewModel.findEdge(byId: id),
              edge.edgeType != .houseEdge else { return nil }
        return edge
    }

    private var existingConnection: LevelConnection? {
        guard let id = editingEdgeId else { return nil }
        return viewModel.connection(forEdgeId: id)
    }

    private var hasExistingStair: Bool {
        targetEdge?.stairConfig != nil || existingConnection != nil
    }

    /// Levels this edge's stair could descend to — every level except the
    /// active one. Rows above the active level render disabled: a connection
    /// descends from an upper-level edge (spec § 7.1), so connecting UP means
    /// switching to that level and tapping one of its edges.
    private var connectableLevels: [(index: Int, level: DeckLevel)] {
        guard viewModel.isMultiLevel else { return [] }
        return Array(viewModel.drawingData.levels.enumerated())
            .filter { $0.offset != viewModel.activeLevelIndex }
            .map { (index: $0.offset, level: $0.element) }
    }

    private var showsLevelMode: Bool { !connectableLevels.isEmpty }

    /// The drawing with THIS edge's fixed-rise stair removed — the world the
    /// commit creates. All resolved-height math reads from it so the drop the
    /// sheet previews equals the drop `connectLevels` commits: an existing
    /// stair being replaced can be the very thing an implicit level height
    /// derives from, and previewing against it would show a rise the commit
    /// itself invalidates.
    private var probeData: DeckDrawingData {
        guard let id = editingEdgeId else { return viewModel.drawingData }
        var probe = viewModel.drawingData
        for levelIndex in probe.levels.indices {
            if let edgeIndex = probe.levels[levelIndex].edges.firstIndex(where: { $0.id == id }) {
                probe.levels[levelIndex].edges[edgeIndex].stairConfig = nil
            }
        }
        if let edgeIndex = probe.edges.firstIndex(where: { $0.id == id }) {
            probe.edges[edgeIndex].stairConfig = nil
        }
        return probe
    }

    /// The active drawing context's own resolved height in feet — what this
    /// edge's stair descends FROM.
    private var activeLevelResolvedFeet: Double {
        let data = probeData
        if viewModel.isMultiLevel, viewModel.activeLevelIndex < data.levels.count {
            return data.renderElevationFeet(
                for: data.levels[viewModel.activeLevelIndex],
                levelIndex: viewModel.activeLevelIndex
            )
        }
        return data.renderElevationFeetSingleLevel
    }

    private func resolvedFeet(forLevelAt index: Int) -> Double {
        let data = probeData
        guard index < data.levels.count else { return 0 }
        return data.renderElevationFeet(for: data.levels[index], levelIndex: index)
    }

    /// Drop in feet from the active level down to a candidate target.
    private func drop(toLevelAt index: Int) -> Double {
        activeLevelResolvedFeet - resolvedFeet(forLevelAt: index)
    }

    private var selectedTargetIndex: Int? {
        guard let targetLevelId else { return nil }
        return viewModel.drawingData.levels.firstIndex { $0.id == targetLevelId }
    }

    // MARK: - Rise

    /// Total rise in inches under the current mode.
    private var totalRise: Double {
        switch mode {
        case .treads:
            return riseEntry.treadRiseInches
        case .height:
            return riseEntry.heightRiseInches
        case .level:
            guard let index = selectedTargetIndex else { return 0 }
            return max(0, drop(toLevelAt: index) * 12.0)
        }
    }

    private var stairSpec: StairCalculator.StairSpec? {
        guard let width = Double(widthText), width > 0, totalRise > 0 else { return nil }
        return StairCalculator.calculate(
            totalRise: totalRise,
            width: width,
            risePerStep: risePerStep,
            runPerTread: runPerTread,
            treadCountOverride: mode == .treads ? riseEntry.treadCount : nil
        )
    }

    private var canApply: Bool {
        guard targetEdge != nil, stairSpec != nil else { return false }
        if mode == .level { return selectedTargetIndex != nil }
        return true
    }

    // MARK: - Edge geometry

    private var edgeLengthInches: Double? {
        targetEdge?.dimension
    }

    private var needsAlignment: Bool {
        guard mode != .level,
              let edgeLen = edgeLengthInches,
              let width = Double(widthText) else { return false }
        return width < edgeLen - 1  // 1" tolerance
    }

    private var gapMeasurements: (left: Double, right: Double)? {
        guard let edgeLen = edgeLengthInches,
              let width = Double(widthText), width < edgeLen else { return nil }
        let offset = Double(offsetText) ?? 0
        let gap = edgeLen - width
        switch alignment {
        case .left:   return (left: offset, right: gap - offset)
        case .center: return (left: gap / 2 + offset, right: gap / 2 - offset)
        case .right:  return (left: gap - offset, right: offset)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3_5) {
                    if targetEdge == nil {
                        if !pickableEdges.isEmpty {
                            edgePickerCard
                        } else {
                            emptyState
                        }
                    } else {
                        if needsEdgeChoice {
                            edgePickerCard
                        }
                        riseCard
                        widthInput
                        if needsAlignment {
                            alignmentSection
                        }
                        directionSection
                        codeParameters
                        if let spec = stairSpec {
                            calculatedValues(spec: spec)
                        }
                        railingSection
                        if hasExistingStair {
                            removeSection
                        }
                    }

                    Spacer()
                }
                .padding(OPSStyle.Layout.spacing3_5)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("Stairs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyStairs()
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(!canApply)
                }
            }
        }
        // When the sheet has to ask which edge, it must not cover the canvas
        // it is asking about — the candidate edge highlights out there while
        // its row is selected. Opened on a known edge, it stays full height
        // for the whole configuration.
        .presentationDetents(needsEdgeChoice ? [.medium, .large] : [.large])
        .fullScreenCover(isPresented: $showingARHeight) {
            ARHeightMeasureView { heightInches, _ in
                riseEntry.setTotalRiseInches(heightInches)
                showingARHeight = false
            }
        }
        .onAppear(perform: loadExisting)
        .onDisappear {
            viewModel.highlightedEdgeId = nil
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("No edge selected")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Tap a deck edge on the canvas, then add stairs.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Edge picker (sheet opened without an edge)

    /// The level whose edges the picker offers. Multi-level drawings pick
    /// from the active level; single-level drawings from the root arrays.
    private var pickerLevel: DeckLevel? {
        if let active = viewModel.activeLevel { return active }
        var synthetic = DeckLevel(id: "root", name: "Deck")
        synthetic.vertices = viewModel.drawingData.vertices
        synthetic.edges = viewModel.drawingData.edges
        return synthetic
    }

    private var pickableEdges: [DeckEdge] {
        (pickerLevel?.edges ?? []).filter { $0.edgeType != .houseEdge }
    }

    private var edgePickerCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Stairs Descend From")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ForEach(pickableEdges, id: \.id) { edge in
                let isSelected = pickedEdgeId == edge.id
                Button {
                    pickedEdgeId = edge.id
                    viewModel.highlightedEdgeId = edge.id
                    prefill(forEdge: edge)
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.secondaryText)
                        Text(edgeLabel(edge))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer()
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(isSelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.background)
                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                }
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    /// The operator's own name for the edge, else the side it faces and how
    /// long it is. Vertex indices ("Edge 1–2") appear nowhere on the canvas,
    /// so they named nothing the operator could find. Bug 2f717747.
    private func edgeLabel(_ edge: DeckEdge) -> String {
        guard let level = pickerLevel else { return "Edge" }
        return DeckEdgeNaming.displayName(
            forEdgeId: edge.id,
            in: level,
            system: viewModel.drawingData.config.measurementSystem
        )
    }

    // MARK: - Rise card

    private var riseCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("Total Rise")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text(totalRise > 0 ? DimensionEngine.formatImperial(totalRise) : "\u{2014}")
                        .font(OPSStyle.Typography.headlineMono)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                Spacer()
                Text("IRC R311.7")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(OPSStyle.Colors.primaryAccent.opacity(0.15))
                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
            }

            modePicker

            switch mode {
            case .treads:
                treadsInput
            case .height:
                heightInput
            case .level:
                levelInput
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    /// All three vocabularies are always listed. Level used to VANISH on a
    /// single-level drawing, which reads as a missing feature rather than a
    /// precondition — so it stays, greyed, with the one thing that unlocks it
    /// spelled out underneath. Bug 46c2d6eb (A2).
    private var modePicker: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                ForEach(RiseMode.allCases, id: \.self) { candidate in
                    modeSegment(candidate)
                }
            }
            .padding(OPSStyle.Layout.spacing1 / 2)
            .background(OPSStyle.Colors.background)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: 1)
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)

            if !showsLevelMode {
                Text("ADD A LEVEL TO CONNECT")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }

    private func modeSegment(_ candidate: RiseMode) -> some View {
        let isEnabled = isModeEnabled(candidate)
        let isActive = mode == candidate
        return Button {
            mode = candidate
        } label: {
            Text(candidate.displayName)
                .font(OPSStyle.Typography.smallButton)
                .foregroundColor(
                    isActive
                        ? OPSStyle.Colors.primaryText
                        : (isEnabled ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.tertiaryText)
                )
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetMin - OPSStyle.Layout.spacing2)
                .background(isActive ? OPSStyle.Colors.surfaceActive : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                        .stroke(isActive ? OPSStyle.Colors.cardBorder : Color.clear, lineWidth: 1)
                )
                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
        }
        .disabled(!isEnabled)
    }

    private func isModeEnabled(_ candidate: RiseMode) -> Bool {
        candidate == .level ? showsLevelMode : true
    }

    // MARK: - Treads mode

    private var treadsInput: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                stepButton(
                    systemImage: "minus",
                    enabled: riseEntry.treadCount > DeckStairRiseEntry.treadRange.lowerBound
                ) {
                    riseEntry.setTreadCount(riseEntry.treadCount - 1)
                }

                VStack(spacing: 0) {
                    Text("\(riseEntry.treadCount)")
                        .font(OPSStyle.Typography.headlineMono)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                    Text(riseEntry.treadCount == 1 ? "tread" : "treads")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity)

                stepButton(
                    systemImage: "plus",
                    enabled: riseEntry.treadCount < DeckStairRiseEntry.treadRange.upperBound
                ) {
                    riseEntry.setTreadCount(riseEntry.treadCount + 1)
                }
            }

            // The height this count spans — the number the operator can't see
            // from the dial, and the one the stair is actually built to.
            Text("\(DimensionEngine.formatImperial(riseEntry.treadRiseInches)) total \u{00b7} \(String(format: "%.1f", risePerStep))\u{2033} per step")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .background(OPSStyle.Colors.background)
        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .semibold))
                .foregroundColor(enabled ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.smallCornerRadius)
        }
        .disabled(!enabled)
    }

    // MARK: - Height mode

    private var heightInput: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            DeckFeetInchesWheels(
                feet: Binding(
                    get: { riseEntry.feet },
                    set: { riseEntry.setHeight(feet: $0, inches: riseEntry.inches) }
                ),
                inches: Binding(
                    get: { riseEntry.inches },
                    set: { riseEntry.setHeight(feet: riseEntry.feet, inches: $0) }
                )
            )

            // The step count this height needs — what Treads mode will show,
            // surfaced here so the operator never has to switch to find out.
            Text("\(riseEntry.treadCount) \(riseEntry.treadCount == 1 ? "tread" : "treads") \u{00b7} \(String(format: "%.1f", actualRisePerStep))\u{2033} per step")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(heightPresets, id: \.label) { preset in
                    Button {
                        riseEntry.setHeight(feet: preset.feet, inches: preset.inches)
                    } label: {
                        Text(preset.label)
                            .font(OPSStyle.Typography.smallButton)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .background(OPSStyle.Colors.background)
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                    }
                }

                Spacer()

                Button {
                    showingARHeight = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: "camera.viewfinder")
                        Text("AR")
                    }
                    .font(OPSStyle.Typography.smallButton)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(OPSStyle.Colors.background)
                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                }
            }
        }
    }

    private var heightPresets: [(label: String, feet: Int, inches: Int)] {
        [("2'", 2, 0), ("2' 6\"", 2, 6), ("3'", 3, 0), ("4'", 4, 0)]
    }

    /// Rise per step once the drop is divided into whole treads — the built
    /// figure, always at or under the code maximum the stepper enforces.
    private var actualRisePerStep: Double {
        guard riseEntry.treadCount > 0 else { return risePerStep }
        return riseEntry.heightRiseInches / Double(riseEntry.treadCount)
    }

    // MARK: - Level mode

    private var levelInput: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            ForEach(connectableLevels, id: \.level.id) { candidate in
                levelRow(index: candidate.index, level: candidate.level)
            }

            if let index = selectedTargetIndex, let spec = stairSpec {
                Text("Drop \(DimensionEngine.formatImperial(drop(toLevelAt: index) * 12.0)) \u{00b7} \(spec.treadCount) treads")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
    }

    private func levelRow(index: Int, level: DeckLevel) -> some View {
        let levelDrop = drop(toLevelAt: index)
        let connectable = levelDrop > 0.01
        let isSelected = targetLevelId == level.id

        return Button {
            targetLevelId = level.id
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.secondaryText)

                Circle()
                    .fill(level.displayColor.swiftUIColor)
                    .frame(width: OPSStyle.Layout.Indicator.dotMD, height: OPSStyle.Layout.Indicator.dotMD)

                Text(level.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(connectable ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                Spacer()

                Text(heightBadge(forLevelAt: index, level: level))
                    .font(OPSStyle.Typography.monoValue)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(isSelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.background)
            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .disabled(!connectable)
        .overlay(alignment: .bottomLeading) {
            if !connectable {
                Text(abs(levelDrop) <= 0.01 ? "Same height" : "Higher \u{2014} connect from that level's edge")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.leading, OPSStyle.Layout.spacing2_5)
                    .padding(.bottom, OPSStyle.Layout.spacing1)
            }
        }
    }

    private func heightBadge(forLevelAt index: Int, level: DeckLevel) -> String {
        let resolved = resolvedFeet(forLevelAt: index)
        let formatted = formatFeet(resolved)
        return level.elevation != nil ? formatted : "\(formatted) \u{00b7} auto"
    }

    // MARK: - Width

    private var widthInput: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Stair Width")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack {
                TextField("48", text: $widthText)
                    .font(OPSStyle.Typography.titleMono)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.numberPad)

                Text("inches")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.background)
            .cornerRadius(OPSStyle.Layout.smallCornerRadius)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach([36, 42, 48, 60], id: \.self) { width in
                    Button {
                        widthText = "\(width)"
                    } label: {
                        Text("\(width)\"")
                            .font(OPSStyle.Typography.smallButton)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .background(OPSStyle.Colors.background)
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Alignment & Offset

    private var alignmentSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("Position Along Edge")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Picker("Alignment", selection: $alignment) {
                ForEach(StairAlignment.allCases, id: \.self) { align in
                    Text(align.displayName).tag(align)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Offset")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                TextField("0", text: $offsetText)
                    .font(OPSStyle.Typography.monoValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("inches")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            if let gaps = gapMeasurements {
                HStack {
                    Text("Left gap: \(DimensionEngine.formatImperial(gaps.left))")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Text("Right gap: \(DimensionEngine.formatImperial(gaps.right))")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.top, OPSStyle.Layout.spacing1)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Direction

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Toggle(isOn: $flipDirection) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flip Direction")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("Stairs run away from the deck. Flip if they should land the other way.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(2)
                }
            }
            .tint(OPSStyle.Colors.text)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Code Parameters

    private var codeParameters: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("Building Code (IRC R311.7)")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            HStack {
                Text("Rise per step")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text(String(format: "%.1f\"", risePerStep))
                    .font(OPSStyle.Typography.monoValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                // Changing the code envelope re-derives whichever vocabulary
                // the operator is NOT typing in, so the two never drift.
                Stepper(
                    "",
                    value: Binding(
                        get: { riseEntry.risePerStep },
                        set: { riseEntry.setRisePerStep($0, authority: mode == .treads ? .treads : .height) }
                    ),
                    in: 7.0...7.75,
                    step: 0.25
                )
                .labelsHidden()
                .frame(width: 100)
            }

            HStack {
                Text("Run per tread")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
                Text(String(format: "%.0f\"", runPerTread))
                    .font(OPSStyle.Typography.monoValue)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                Stepper("", value: $runPerTread, in: 10.0...12.0, step: 0.5)
                    .labelsHidden()
                    .frame(width: 100)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Calculated Values

    private func calculatedValues(spec: StairCalculator.StairSpec) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(mode == .treads ? "Manual Count" : "Auto-Calculated")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            calcRow("Treads", value: "\(spec.treadCount)")
            calcRow("Actual rise/step", value: String(format: "%.2f\"", spec.risePerStep))
            calcRow("Total run", value: DimensionEngine.formatImperial(spec.totalRun))
            calcRow("Stringer length", value: DimensionEngine.formatImperial(spec.stringerLength))
            calcRow("Stringers needed", value: "\(spec.stringerCount)")
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.primaryAccent.opacity(0.08))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    private func calcRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.monoValue)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    // MARK: - Railing

    private var railingSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Toggle(isOn: $addRailing) {
                Text("Add Railing")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .tint(OPSStyle.Colors.text)

            if addRailing {
                Picker("Railing Type", selection: $railingType) {
                    ForEach(RailingType.assignableDefaultTypes, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Remove

    private var removeSection: some View {
        Button {
            guard let edgeId = editingEdgeId else { return }
            viewModel.removeStairs(edgeId: edgeId)
            dismiss()
        } label: {
            Text("Remove Stairs")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.errorStatus)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.errorStatus.opacity(0.1))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Load / Apply

    private func loadExisting() {
        guard !didLoad else { return }
        didLoad = true
        if let edge = targetEdge {
            prefill(forEdge: edge)
        }
        if let initialMode, isModeEnabled(initialMode) {
            mode = initialMode
        }
    }

    private func prefill(forEdge edge: DeckEdge) {
        if let connection = viewModel.connection(forEdgeId: edge.id) {
            mode = .level
            targetLevelId = connection.lowerLevelId
            let config = connection.stairConfig
            widthText = String(format: "%.0f", config.width)
            riseEntry.setRisePerStep(config.risePerStep, authority: .height)
            runPerTread = config.runPerTread
            flipDirection = config.flipDirection
            if let railing = config.railingConfig {
                addRailing = true
                railingType = railing.railingType
            }
            return
        }

        if let existing = edge.stairConfig {
            mode = .height
            widthText = String(format: "%.0f", existing.width)
            riseEntry.setRisePerStep(existing.risePerStep, authority: .height)
            runPerTread = existing.runPerTread
            alignment = existing.alignment
            offsetText = String(format: "%.0f", existing.offset)
            flipDirection = existing.flipDirection
            if let railing = existing.railingConfig {
                addRailing = true
                railingType = railing.railingType
            }
            // The stored drop is authoritative; the tread count follows it,
            // exactly as it did before this state was unified.
            riseEntry.setTotalRiseInches(existing.totalRiseInches ?? activeLevelResolvedFeet * 12.0)
            return
        }

        // New stair: width defaults to the edge, rise to the level's resolved
        // height — a stair to grade spans exactly that, so most commits are
        // a straight Apply.
        mode = .height
        if let edgeLen = edge.dimension {
            widthText = String(format: "%.0f", edgeLen)
        }
        riseEntry.setTotalRiseInches(activeLevelResolvedFeet * 12.0)
    }

    private func formatFeet(_ feet: Double) -> String {
        DimensionEngine.formatImperial(feet * 12.0)
    }

    private func applyStairs() {
        guard let edge = targetEdge, let spec = stairSpec else { return }

        var config = StairConfig(width: spec.width, risePerStep: risePerStep, runPerTread: runPerTread)
        config.flipDirection = flipDirection
        if addRailing {
            config.railingConfig = RailingConfig(
                railingType: railingType,
                maxPostSpacing: railingType.defaultMaxPostSpacing
            )
        }

        if mode == .level {
            guard let targetLevelId,
                  let upperLevel = viewModel.activeLevel else { return }
            viewModel.connectLevels(
                upperLevelId: upperLevel.id,
                lowerLevelId: targetLevelId,
                upperEdgeId: edge.id,
                stairConfig: config
            )
            return
        }

        config.treadCount = spec.treadCount
        config.totalRiseInches = totalRise
        config.alignment = alignment
        config.offset = Double(offsetText) ?? 0
        viewModel.setStairs(edge.id, config: config)
    }
}
