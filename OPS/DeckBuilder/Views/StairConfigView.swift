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

    /// Standard stair width in inches — matches the first width preset and
    /// the code-typical 4' residential run.
    private enum StairDefaults {
        static let width: Double = 48
    }

    @State private var mode: RiseMode = .height
    @State private var treadCount: Int = 4
    @State private var riseFeet: Int = 2
    @State private var riseInches: Int = 6
    @State private var targetLevelId: String?
    /// Edge chosen inside the sheet when it was opened without a selection
    /// (the Connect entry point on the level bar).
    @State private var pickedEdgeId: String?
    @State private var widthText: String = "48"
    @State private var risePerStep: Double = 7.5
    @State private var runPerTread: Double = 10.0
    @State private var addRailing: Bool = false
    @State private var railingType: RailingType = .parapetWall
    @State private var alignment: StairAlignment = .center
    @State private var offsetText: String = "0"
    @State private var flipDirection: Bool = false
    @State private var showingARHeight = false
    @State private var didLoad = false

    // MARK: - Context

    private var editingEdgeId: String? {
        viewModel.editingEdgeId ?? pickedEdgeId
    }

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
            return Double(treadCount) * risePerStep
        case .height:
            return Double(riseFeet * 12 + riseInches)
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
            treadCountOverride: mode == .treads ? treadCount : nil
        )
    }

    private var canApply: Bool {
        guard targetEdge != nil, stairSpec != nil else { return false }
        if mode == .level { return selectedTargetIndex != nil }
        return true
    }

    // MARK: - Edge geometry

    /// Edge length in inches — the typed dimension when the user set one,
    /// otherwise measured from the drawn geometry through the effective
    /// scale. Reading `dimension` alone left this nil on every undimensioned
    /// edge, which silently hid the position control (an edge almost never
    /// carries a typed dimension when stairs are first attached).
    private var edgeLengthInches: Double? {
        if let dimension = targetEdge?.dimension, dimension > 0 { return dimension }
        guard let edge = targetEdge,
              let start = viewModel.findVertex(byId: edge.startVertexId),
              let end = viewModel.findVertex(byId: edge.endVertexId) else { return nil }
        let canvasLength = hypot(end.position.x - start.position.x, end.position.y - start.position.y)
        let scale = viewModel.drawingData.effectiveScaleFactor
        guard canvasLength > 0, scale > 0 else { return nil }
        return Double(canvasLength) / scale
    }

    private var offsetValue: Double { Double(offsetText) ?? 0 }

    /// Clamp the nudge to the slack so a stair can never be pushed past the
    /// end of its own edge.
    private func setOffset(_ value: Double, limit: Double) {
        let lower = alignment == .center ? -limit : 0
        offsetText = String(format: "%.0f", min(max(value, lower), limit))
        // stepButton already fires the light impact — no double tap.
    }

    /// Slack between the stair and its edge — how far the stair can slide.
    private var positionSlackInches: Double? {
        guard let edgeLen = edgeLengthInches, let width = Double(widthText) else { return nil }
        let slack = edgeLen - width
        return slack > 1 ? slack : nil   // 1" tolerance
    }

    /// Position controls appear whenever the stair is narrower than its edge —
    /// including connection stairs, whose alignment the planner honors too.
    private var needsAlignment: Bool { positionSlackInches != nil }

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
                        if viewModel.isMultiLevel, let level = viewModel.activeLevel, !pickableEdges.isEmpty {
                            edgePickerCard(level: level)
                        } else {
                            emptyState
                        }
                    } else {
                        if viewModel.editingEdgeId == nil, let level = viewModel.activeLevel {
                            edgePickerCard(level: level)
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
        .presentationDetents([.large])
        .fullScreenCover(isPresented: $showingARHeight) {
            ARHeightMeasureView { heightInches, _ in
                setRise(fromInches: heightInches)
                showingARHeight = false
            }
        }
        .onAppear(perform: loadExisting)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("No edge selected")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Select a deck edge, then add stairs from its toolbar.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Edge picker (Connect entry — sheet opened without a selection)

    private var pickableEdges: [DeckEdge] {
        viewModel.activeLevel?.edges.filter { $0.edgeType != .houseEdge } ?? []
    }

    private func edgePickerCard(level: DeckLevel) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Stairs Descend From")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ForEach(pickableEdges, id: \.id) { edge in
                let isSelected = pickedEdgeId == edge.id
                Button {
                    pickedEdgeId = edge.id
                    prefill(forEdge: edge)
                } label: {
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.secondaryText)
                        Text(edgeLabel(edge, level: level))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        Spacer()
                        if let dim = edge.dimension {
                            Text(DimensionEngine.formatImperial(dim))
                                .font(OPSStyle.Typography.monoValue)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
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

    private func edgeLabel(_ edge: DeckEdge, level: DeckLevel) -> String {
        let startIdx = level.vertices.firstIndex(where: { $0.id == edge.startVertexId }).map { $0 + 1 } ?? 0
        let endIdx = level.vertices.firstIndex(where: { $0.id == edge.endVertexId }).map { $0 + 1 } ?? 0
        return "Edge \(startIdx)\u{2013}\(endIdx)"
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

            Picker("Rise input", selection: $mode) {
                ForEach(availableModes, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

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

    private var availableModes: [RiseMode] {
        showsLevelMode ? RiseMode.allCases : [.treads, .height]
    }

    // MARK: - Treads mode

    private var treadsInput: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                stepButton(systemImage: "minus", enabled: treadCount > 1) {
                    treadCount = max(1, treadCount - 1)
                }

                VStack(spacing: 0) {
                    Text("\(treadCount)")
                        .font(OPSStyle.Typography.headlineMono)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .monospacedDigit()
                    Text(treadCount == 1 ? "tread" : "treads")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity)

                stepButton(systemImage: "plus", enabled: treadCount < 30) {
                    treadCount = min(30, treadCount + 1)
                }
            }

            Text("\(String(format: "%.1f", risePerStep))\u{2033} per step")
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
            DeckFeetInchesWheels(feet: $riseFeet, inches: $riseInches)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(heightPresets, id: \.label) { preset in
                    Button {
                        riseFeet = preset.feet
                        riseInches = preset.inches
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

            // Nudge the stair along the edge from its alignment. Stepper
            // rather than a keypad: it can't exceed the slack, and it works
            // one-handed. CENTER nudges both ways, so it takes the full slack
            // split either side.
            if let slack = positionSlackInches {
                let offsetLimit = alignment == .center ? slack / 2 : slack
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    Text("Nudge")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Spacer()

                    stepButton(systemImage: "minus", enabled: offsetValue > (alignment == .center ? -offsetLimit : 0)) {
                        setOffset(offsetValue - 2, limit: offsetLimit)
                    }

                    Text(DimensionEngine.formatImperial(abs(offsetValue)))
                        .font(OPSStyle.Typography.monoValue)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(minWidth: 64)

                    stepButton(systemImage: "plus", enabled: offsetValue < offsetLimit) {
                        setOffset(offsetValue + 2, limit: offsetLimit)
                    }
                }

                HStack {
                    Text("Slides \(DimensionEngine.formatImperial(slack))")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer()
                    if let gaps = gapMeasurements {
                        Text("\(DimensionEngine.formatImperial(max(0, gaps.left))) | \(DimensionEngine.formatImperial(max(0, gaps.right)))")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
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
                Stepper("", value: $risePerStep, in: 7.0...7.75, step: 0.25)
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
        if let initialMode, availableModes.contains(initialMode) {
            mode = initialMode
        }
    }

    private func prefill(forEdge edge: DeckEdge) {
        if let connection = viewModel.connection(forEdgeId: edge.id) {
            mode = .level
            targetLevelId = connection.lowerLevelId
            let config = connection.stairConfig
            widthText = String(format: "%.0f", config.width)
            risePerStep = config.risePerStep
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
            risePerStep = existing.risePerStep
            runPerTread = existing.runPerTread
            alignment = existing.alignment
            offsetText = String(format: "%.0f", existing.offset)
            flipDirection = existing.flipDirection
            if let treads = existing.treadCount, treads > 0 {
                treadCount = treads
            }
            if let railing = existing.railingConfig {
                addRailing = true
                railingType = railing.railingType
            }
            setRise(fromInches: existing.totalRiseInches ?? activeLevelResolvedFeet * 12.0)
            return
        }

        // New stair: a real stair width (48" — the code-standard default and
        // the first width preset), never the whole edge. Defaulting to the
        // full edge made every new stair span the deck AND hid the position
        // control, since a full-width stair has nowhere to slide. Narrower
        // edges just take the edge.
        mode = .height
        let defaultWidth = min(StairDefaults.width, edgeLengthInches ?? StairDefaults.width)
        widthText = String(format: "%.0f", defaultWidth)
        setRise(fromInches: activeLevelResolvedFeet * 12.0)
    }

    private func setRise(fromInches inches: Double) {
        let clamped = max(0, inches)
        let components = DeckFeetInchesWheels.components(fromFeet: clamped / 12.0)
        riseFeet = components.feet
        riseInches = components.inches
        treadCount = max(1, StairConfig.calculateTreadCount(totalRise: clamped, risePerStep: risePerStep))
    }

    private func formatFeet(_ feet: Double) -> String {
        DimensionEngine.formatImperial(feet * 12.0)
    }

    private func applyStairs() {
        guard let edge = targetEdge, let spec = stairSpec else { return }

        var config = StairConfig(width: spec.width, risePerStep: risePerStep, runPerTread: runPerTread)
        config.flipDirection = flipDirection
        // Position rides on BOTH stair kinds — the planner honors alignment
        // and offset for connection stairs exactly like edge stairs.
        config.alignment = alignment
        config.offset = offsetValue
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
        viewModel.setStairs(edge.id, config: config)
    }
}
