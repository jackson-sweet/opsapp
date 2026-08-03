// OPS/OPS/DeckBuilder/Views/StairConfigView.swift

import SwiftUI

/// The single stair authoring surface, built around how a stair is actually
/// specified in the field: a vertical drop and a rise/run pair, which together
/// determine the tread count.
///
/// The drop is known one of three ways — the deck's ELEVATION, a counted
/// number of TREADS, or the LEVEL the flight lands on. Each mode authors one
/// number and derives the rest through the same rise/run pair, which stays
/// visible and adjustable because it is the conversion between them (code
/// standard most days, a longer run or a taller/shallower rise when the job
/// calls for it).
///
/// ELEVATION / TREADS commit a fixed-rise stair on the edge; LEVEL commits a
/// `LevelConnection` whose rise keeps tracking the two levels' heights. An
/// edge carries one stair, never both kinds.
///
/// ELEVATION and TREADS are two readings of ONE drop, so they are held in one
/// `DeckStairRiseEntry` rather than as independent state: entering either moves
/// the other, deriving on entry and never on the switch, so flipping modes is
/// lossless and can never show a stale number (bug 46c2d6eb).
///
/// All three modes are always LISTED. LEVEL is muted and inert on a drawing
/// with nothing to descend to, with the one thing that unlocks it stated
/// underneath — a choice that vanishes reads as a missing feature.
///
/// Every geometry lookup goes through the view model's level-aware accessors
/// (`findEdge` / `activeLevel`) — the top-level vertex/edge arrays are empty
/// on multi-level drawings.
struct StairConfigView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    /// Overrides the data-derived starting mode (snapshot proofs; a future
    /// deep link could use it too). Nil means derive from the edge's state.
    var initialMode: RiseMode? = nil

    enum RiseMode: String, CaseIterable {
        case elevation
        case treads
        case level

        var label: String {
            switch self {
            case .elevation: return "ELEVATION"
            case .treads:    return "TREADS"
            case .level:     return "LEVEL"
            }
        }
    }

    /// Code reference points. Values stay adjustable — these mark where the
    /// entered pair sits relative to IRC R311.7, they don't constrain it.
    private enum Code {
        static let standardRise: Double = 7.5
        static let standardRun: Double = 10.0
        static let maxRise: Double = 7.75
        static let minRun: Double = 10.0
        static let riseRange: ClosedRange<Double> = 5.0...8.5
        static let runRange: ClosedRange<Double> = 9.0...18.0
    }

    @State private var mode: RiseMode = .elevation
    /// The drop, held in BOTH vocabularies at once. ELEVATION and TREADS are
    /// two readings of one dimension, so entering either moves the other and
    /// switching modes can never show a stale number (bug 46c2d6eb). Deriving
    /// happens on entry, never on the switch, so flipping back and forth is
    /// lossless — see `DeckStairRiseEntry`.
    @State private var riseEntry = DeckStairRiseEntry(
        totalRiseInches: 30,
        risePerStep: Code.standardRise
    )
    @State private var targetLevelId: String?
    /// Edge chosen inside the sheet when it was opened without a selection
    /// (the CONNECT entry point on the level bar).
    @State private var pickedEdgeId: String?
    @State private var widthInches: Double = 48
    @State private var runPerTread: Double = Code.standardRun
    @State private var addRailing: Bool = false
    @State private var alignment: StairAlignment = .center
    @State private var offsetInches: Double = 0
    @State private var flipDirection: Bool = false
    @State private var showingARHeight = false
    @State private var didLoad = false

    // MARK: - Context

    private var editingEdgeId: String? {
        viewModel.editingEdgeId ?? pickedEdgeId
    }

    /// Rise-per-step lives on the entry, so changing the code envelope
    /// re-derives whichever vocabulary the operator is NOT typing in.
    private var risePerStep: Double { riseEntry.risePerStep }

    /// Which vocabulary a rise/run change must leave alone. TREADS is the only
    /// mode that authors a step count; ELEVATION and LEVEL both author the drop
    /// directly, so the tread count is what follows.
    private var riseAuthority: DeckStairRiseEntry.Authority {
        mode == .treads ? .treads : .height
    }

    private var riseFeetBinding: Binding<Int> {
        Binding(
            get: { riseEntry.feet },
            set: { riseEntry.setHeight(feet: $0, inches: riseEntry.inches) }
        )
    }

    private var riseInchesBinding: Binding<Int> {
        Binding(
            get: { riseEntry.inches },
            set: { riseEntry.setHeight(feet: riseEntry.feet, inches: $0) }
        )
    }

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

    private var measurementSystem: MeasurementSystem {
        viewModel.drawingData.config.measurementSystem
    }

    /// Levels this flight could land on — every level except the active one.
    private var connectableLevels: [(index: Int, level: DeckLevel)] {
        guard viewModel.isMultiLevel else { return [] }
        return Array(viewModel.drawingData.levels.enumerated())
            .filter { $0.offset != viewModel.activeLevelIndex }
            .map { (index: $0.offset, level: $0.element) }
    }

    /// Whether a LEVEL flight is possible at all — there has to be another
    /// level below this one to land on.
    private var canConnectToLevel: Bool { !connectableLevels.isEmpty }

    /// Every vocabulary is always LISTED. LEVEL used to vanish on a
    /// single-level drawing, which reads as a missing feature rather than an
    /// unmet precondition — so it stays, muted and inert, with the one thing
    /// that unlocks it spelled out underneath (bug 46c2d6eb).
    private func isModeEnabled(_ candidate: RiseMode) -> Bool {
        candidate == .level ? canConnectToLevel : true
    }

    /// The drawing with THIS edge's fixed-rise stair removed — the world the
    /// commit creates, so a LEVEL preview can't be skewed by the stair it
    /// replaces (an existing stair can be what an implicit level height
    /// derives from).
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

    private func drop(toLevelAt index: Int) -> Double {
        activeLevelResolvedFeet - resolvedFeet(forLevelAt: index)
    }

    private var selectedTargetIndex: Int? {
        guard let targetLevelId else { return nil }
        return viewModel.drawingData.levels.firstIndex { $0.id == targetLevelId }
    }

    // MARK: - The stair

    /// Total rise in inches under the current mode. ELEVATION and LEVEL author
    /// the drop directly; TREADS authors the count and the drop follows from
    /// the rise-per-step.
    private var totalRise: Double {
        switch mode {
        case .elevation:
            return riseEntry.heightRiseInches
        case .treads:
            return riseEntry.treadRiseInches
        case .level:
            guard let index = selectedTargetIndex else { return 0 }
            return max(0, drop(toLevelAt: index) * 12.0)
        }
    }

    private var stairSpec: StairCalculator.StairSpec? {
        guard widthInches > 0, totalRise > 0 else { return nil }
        return StairCalculator.calculate(
            totalRise: totalRise,
            width: widthInches,
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

    private var railRunInches: Double? {
        guard let spec = stairSpec, spec.treadCount > 0 else { return nil }
        return StairConfig.stringerLength(
            totalRise: totalRise,
            treadCount: spec.treadCount,
            runPerTread: runPerTread
        )
    }

    // MARK: - Edge geometry

    /// Edge length in inches — the typed dimension when set, otherwise
    /// measured from the drawn geometry (stairs are usually attached before
    /// an edge is dimensioned).
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

    /// How far the stair can slide along its edge. Nil when it spans the edge.
    private var positionSlackInches: Double? {
        guard let edgeLen = edgeLengthInches else { return nil }
        let slack = edgeLen - widthInches
        return slack > 1 ? slack : nil   // 1" tolerance
    }

    private var gapMeasurements: (left: Double, right: Double)? {
        guard let edgeLen = edgeLengthInches, widthInches < edgeLen else { return nil }
        let gap = edgeLen - widthInches
        switch alignment {
        case .left:   return (left: offsetInches, right: gap - offsetInches)
        case .center: return (left: gap / 2 + offsetInches, right: gap / 2 - offsetInches)
        case .right:  return (left: gap - offsetInches, right: offsetInches)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
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
                        stepCard
                        stairCard
                        takeoffCard
                        railingCard
                        if hasExistingStair {
                            removeButton
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.background)
            .standardSheetToolbar(
                title: "Stairs",
                actionText: hasExistingStair ? "UPDATE" : "ADD",
                isActionEnabled: canApply,
                onCancel: { dismiss() },
                onAction: {
                    applyStairs()
                    dismiss()
                }
            )
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
            Text("—")
                .font(OPSStyle.Typography.emptyStateFigure)
                .foregroundColor(OPSStyle.Colors.text3)
            PanelSectionHeader(label: "No edge selected")
            Text("Select a deck edge, then add stairs from its toolbar.")
                .font(OPSStyle.Typography.smallBody)
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing4)
        .glassSurface()
    }

    // MARK: - Edge picker (CONNECT entry — opened without a selection)

    private var pickableEdges: [DeckEdge] {
        viewModel.activeLevel?.edges.filter { $0.edgeType != .houseEdge } ?? []
    }

    private func edgePickerCard(level: DeckLevel) -> some View {
        SectionCard(title: "Descends From") {
            VStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(pickableEdges, id: \.id) { edge in
                    let isSelected = pickedEdgeId == edge.id
                    Button {
                        pickedEdgeId = edge.id
                        prefill(forEdge: edge)
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                            Text(edgeLabel(edge, level: level))
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.text)
                            Spacer(minLength: 0)
                            if let dim = edge.dimension {
                                Text(DimensionEngine.format(dim, system: measurementSystem))
                                    .font(OPSStyle.Typography.dataValue)
                                    .foregroundColor(OPSStyle.Colors.text2)
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? OPSStyle.Colors.surfaceActive : Color.clear)
                        .nestedCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func edgeLabel(_ edge: DeckEdge, level: DeckLevel) -> String {
        let startIdx = level.vertices.firstIndex(where: { $0.id == edge.startVertexId }).map { $0 + 1 } ?? 0
        let endIdx = level.vertices.firstIndex(where: { $0.id == edge.endVertexId }).map { $0 + 1 } ?? 0
        return "Edge \(startIdx)\u{2013}\(endIdx)"
    }

    // MARK: - RISE — how far down

    private var riseCard: some View {
        SectionCard(title: "Rise") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                SegmentedControl(
                    selection: $mode,
                    options: RiseMode.allCases.map {
                        .text($0, $0.label, isEnabled: isModeEnabled($0))
                    }
                )

                if !canConnectToLevel {
                    Text("ADD A LEVEL TO CONNECT")
                        .font(OPSStyle.Typography.microLabel)
                        .kerning(1.4)
                        .foregroundColor(OPSStyle.Colors.textMute)
                }

                switch mode {
                case .elevation: elevationInput
                case .treads:    treadsInput
                case .level:     levelInput
                }

                derivedReadout
            }
        }
    }

    private var elevationInput: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            DeckFeetInchesWheels(feet: riseFeetBinding, inches: riseInchesBinding)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(risePresets, id: \.label) { preset in
                    StairChip(
                        label: preset.label,
                        isSelected: riseEntry.feet == preset.feet && riseEntry.inches == preset.inches
                    ) {
                        riseEntry.setHeight(feet: preset.feet, inches: preset.inches)
                    }
                }
                Spacer(minLength: 0)
                StairChip(label: "AR", systemImage: "camera.viewfinder", isSelected: false) {
                    showingARHeight = true
                }
            }
        }
    }

    private var risePresets: [(label: String, feet: Int, inches: Int)] {
        [("2'", 2, 0), ("2' 6\"", 2, 6), ("3'", 3, 0), ("4'", 4, 0)]
    }

    private var treadsInput: some View {
        StairCounterRow(
            label: "Treads",
            value: "\(riseEntry.treadCount)",
            canDecrement: riseEntry.treadCount > DeckStairRiseEntry.treadRange.lowerBound,
            canIncrement: riseEntry.treadCount < DeckStairRiseEntry.treadRange.upperBound,
            onDecrement: { riseEntry.setTreadCount(riseEntry.treadCount - 1) },
            onIncrement: { riseEntry.setTreadCount(riseEntry.treadCount + 1) }
        )
    }

    private var levelInput: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(connectableLevels, id: \.level.id) { candidate in
                levelRow(index: candidate.index, level: candidate.level)
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
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.text3)

                Circle()
                    .fill(level.displayColor.swiftUIColor)
                    .frame(width: OPSStyle.Layout.Indicator.dotSM, height: OPSStyle.Layout.Indicator.dotSM)

                Text(level.name)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(connectable ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)

                Spacer(minLength: 0)

                Text(connectable
                     ? "\u{2193} \(DimensionEngine.format(levelDrop * 12, system: measurementSystem))"
                     : (abs(levelDrop) <= 0.01 ? "SAME HEIGHT" : "HIGHER"))
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(connectable ? OPSStyle.Colors.text2 : OPSStyle.Colors.textMute)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? OPSStyle.Colors.surfaceActive : Color.clear)
            .nestedCard()
        }
        .buttonStyle(.plain)
        .disabled(!connectable)
    }

    /// The payoff line: whichever numbers this mode did NOT author, plus the
    /// evened rise per step a builder actually cuts to.
    private var derivedReadout: some View {
        HStack(spacing: 0) {
            StairReadout(
                label: "Total Rise",
                value: totalRise > 0 ? DimensionEngine.format(totalRise, system: measurementSystem) : "—",
                isAuthored: mode == .elevation
            )
            Divider().frame(height: OPSStyle.Layout.spacing4).overlay(OPSStyle.Colors.line)
            StairReadout(
                label: "Treads",
                value: stairSpec.map { "\($0.treadCount)" } ?? "—",
                isAuthored: mode == .treads
            )
            Divider().frame(height: OPSStyle.Layout.spacing4).overlay(OPSStyle.Colors.line)
            StairReadout(
                label: "Actual Rise",
                value: stairSpec.map { String(format: "%.2f\"", $0.risePerStep) } ?? "—",
                isAuthored: false
            )
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity)
        .nestedCard()
    }

    // MARK: - STEP — the rise/run pair that converts drop ⇄ treads

    private var stepCard: some View {
        SectionCard(title: "Step") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                // Changing the step re-derives the vocabulary the operator is
                // NOT typing in: in TREADS the count holds and the height
                // follows; in ELEVATION the height holds and the count follows.
                StairCounterRow(
                    label: "Rise / Step",
                    value: String(format: "%.2f\"", risePerStep),
                    canDecrement: risePerStep > Code.riseRange.lowerBound,
                    canIncrement: risePerStep < Code.riseRange.upperBound,
                    onDecrement: {
                        riseEntry.setRisePerStep(
                            max(Code.riseRange.lowerBound, risePerStep - 0.25),
                            authority: riseAuthority
                        )
                    },
                    onIncrement: {
                        riseEntry.setRisePerStep(
                            min(Code.riseRange.upperBound, risePerStep + 0.25),
                            authority: riseAuthority
                        )
                    }
                )

                StairCounterRow(
                    label: "Run / Tread",
                    value: String(format: "%.1f\"", runPerTread),
                    canDecrement: runPerTread > Code.runRange.lowerBound,
                    canIncrement: runPerTread < Code.runRange.upperBound,
                    onDecrement: { runPerTread = max(Code.runRange.lowerBound, runPerTread - 0.5) },
                    onIncrement: { runPerTread = min(Code.runRange.upperBound, runPerTread + 0.5) }
                )

                codeNote
            }
        }
    }

    /// Objective reference, never a verdict — states where the entered pair
    /// sits against IRC R311.7 without claiming the design passes or fails.
    private var codeNote: some View {
        let riseOver = risePerStep > Code.maxRise + 0.001
        let runUnder = runPerTread < Code.minRun - 0.001
        let outside = riseOver || runUnder
        let text: String = {
            guard outside else { return "IRC R311.7 · RISE \u{2264}7.75\" RUN \u{2265}10\"" }
            var parts: [String] = []
            if riseOver { parts.append("RISE OVER 7.75\"") }
            if runUnder { parts.append("RUN UNDER 10\"") }
            return parts.joined(separator: " · ")
        }()

        return HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("//")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text(text)
                .foregroundColor(outside ? OPSStyle.Colors.tanTextM : OPSStyle.Colors.textMute)
            Spacer(minLength: 0)
        }
        .font(OPSStyle.Typography.microLabel)
        .kerning(1.4)
        // One line always — a wrapped reference line orphans its tail and
        // reads as an error state.
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    // MARK: - STAIR — width, position, direction

    private var stairCard: some View {
        SectionCard(title: "Stair") {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                widthSection

                if positionSlackInches != nil {
                    Divider().overlay(OPSStyle.Colors.line)
                    positionSection
                }

                Divider().overlay(OPSStyle.Colors.line)

                Toggle(isOn: $flipDirection) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text("FLIP DIRECTION")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.text)
                        Text("Stairs run away from the deck. Flip to land them the other way.")
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.text3)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.text))
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
        }
    }

    private var widthSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("WIDTH")
                    .font(OPSStyle.Typography.metadata)
                    .kerning(1.4)
                    .foregroundColor(OPSStyle.Colors.text3)
                Spacer()
                Text(DimensionEngine.format(widthInches, system: measurementSystem))
                    .font(OPSStyle.Typography.dataValueLg)
                    .foregroundColor(OPSStyle.Colors.text)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let edgeLen = edgeLengthInches {
                    StairChip(label: "FULL", isSelected: abs(widthInches - edgeLen) < 1) {
                        widthInches = edgeLen
                        offsetInches = 0
                    }
                }
                ForEach(widthPresets, id: \.self) { preset in
                    StairChip(label: "\(Int(preset))\"", isSelected: abs(widthInches - preset) < 0.5) {
                        widthInches = preset
                        offsetInches = 0
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Presets narrower than the edge — a wider-than-the-edge stair is not a
    /// choice worth offering.
    private var widthPresets: [Double] {
        let all: [Double] = [36, 42, 48, 60]
        guard let edgeLen = edgeLengthInches else { return all }
        return all.filter { $0 < edgeLen - 1 }
    }

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("POSITION")
                .font(OPSStyle.Typography.metadata)
                .kerning(1.4)
                .foregroundColor(OPSStyle.Colors.text3)

            SegmentedControl(
                selection: $alignment,
                options: StairAlignment.allCases.map { ($0, $0.displayName.uppercased()) }
            )

            if let slack = positionSlackInches {
                let limit = alignment == .center ? slack / 2 : slack
                let lower = alignment == .center ? -limit : 0

                StairCounterRow(
                    label: "Nudge",
                    value: DimensionEngine.format(abs(offsetInches), system: measurementSystem),
                    canDecrement: offsetInches > lower,
                    canIncrement: offsetInches < limit,
                    onDecrement: { offsetInches = min(max(offsetInches - 2, lower), limit) },
                    onIncrement: { offsetInches = min(max(offsetInches + 2, lower), limit) }
                )

                if let gaps = gapMeasurements {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Text("//")
                            .foregroundColor(OPSStyle.Colors.textMute)
                        Text("\(DimensionEngine.format(max(0, gaps.left), system: measurementSystem)) LEFT · \(DimensionEngine.format(max(0, gaps.right), system: measurementSystem)) RIGHT")
                            .foregroundColor(OPSStyle.Colors.textMute)
                    }
                    .font(OPSStyle.Typography.microLabel)
                    .kerning(1.4)
                }
            }
        }
    }

    // MARK: - TAKEOFF — what it takes to build

    @ViewBuilder
    private var takeoffCard: some View {
        if let spec = stairSpec {
            SectionCard(title: "Takeoff") {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    takeoffRow("Total Run", DimensionEngine.format(spec.totalRun, system: measurementSystem))
                    takeoffRow("Rail Run", railRunInches.map { DimensionEngine.format($0, system: measurementSystem) } ?? "—")
                    takeoffRow("Stringers", "\(spec.stringerCount) @ \(DimensionEngine.format(spec.stringerLength, system: measurementSystem))")
                }
            }
        }
    }

    private func takeoffRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(OPSStyle.Typography.metadata)
                .kerning(1.4)
                .foregroundColor(OPSStyle.Colors.text3)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.text)
        }
        .frame(minHeight: OPSStyle.Layout.chipMinHeight)
    }

    // MARK: - RAILING

    private var railingCard: some View {
        SectionCard {
            Toggle(isOn: $addRailing) {
                Text("ADD RAILING")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text)
            }
            .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.text))
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
    }

    // MARK: - Remove

    private var removeButton: some View {
        Button {
            guard let edgeId = editingEdgeId else { return }
            viewModel.removeStairs(edgeId: edgeId)
            dismiss()
        } label: {
            Text("REMOVE STAIRS")
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.errorStatus)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.roseLineM, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(.plain)
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
            applyConfigDefaults(connection.stairConfig, edge: edge)
            return
        }

        if let existing = edge.stairConfig {
            mode = .elevation
            applyConfigDefaults(existing, edge: edge)
            // The stored drop is authoritative and both vocabularies follow it.
            setRise(fromInches: existing.totalRiseInches ?? activeLevelResolvedFeet * 12.0)
            // A stair that shipped an explicit tread count keeps it — the
            // height then re-derives from the count so the two stay one number.
            if let treads = existing.treadCount, treads > 0 {
                riseEntry.setTreadCount(treads)
            }
            return
        }

        // New stair: spans its edge (the common case — a stair is cut to the
        // opening), rise from the level's resolved height, code-standard step.
        mode = .elevation
        widthInches = edgeLengthInches ?? 48
        alignment = .center
        offsetInches = 0
        runPerTread = Code.standardRun
        riseEntry.setRisePerStep(Code.standardRise, authority: .height)
        setRise(fromInches: activeLevelResolvedFeet * 12.0)
    }

    private func applyConfigDefaults(_ config: StairConfig, edge: DeckEdge) {
        widthInches = config.width > 0 ? config.width : (edgeLengthInches ?? 48)
        riseEntry.setRisePerStep(config.risePerStep, authority: .height)
        runPerTread = config.runPerTread
        alignment = config.alignment
        offsetInches = config.offset
        flipDirection = config.flipDirection
        addRailing = config.railingConfig != nil
    }

    private func setRise(fromInches inches: Double) {
        riseEntry.setTotalRiseInches(inches)
    }

    private func applyStairs() {
        guard let edge = targetEdge, let spec = stairSpec else { return }

        var config = StairConfig(width: spec.width, risePerStep: risePerStep, runPerTread: runPerTread)
        config.flipDirection = flipDirection
        // Position rides on BOTH stair kinds — the planner honors alignment
        // and offset for connection stairs exactly like edge stairs.
        config.alignment = alignment
        config.offset = offsetInches
        if addRailing {
            config.railingConfig = RailingConfig(
                railingType: .parapetWall,
                maxPostSpacing: RailingType.parapetWall.defaultMaxPostSpacing
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

// MARK: - Stair sheet primitives

/// A −/+ counter row. The house pattern for a bounded numeric value: no
/// keyboard, 44pt targets, mono value, disabled ends instead of clamping
/// silently.
private struct StairCounterRow: View {
    let label: String
    let value: String
    let canDecrement: Bool
    let canIncrement: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.metadata)
                .kerning(1.4)
                .foregroundColor(OPSStyle.Colors.text3)

            Spacer(minLength: 0)

            Text(value)
                .font(OPSStyle.Typography.dataValueLg)
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()

            HStack(spacing: 0) {
                stepButton(systemImage: "minus", enabled: canDecrement, action: onDecrement)
                Divider()
                    .frame(height: OPSStyle.Layout.touchTargetMin / 2)
                    .overlay(OPSStyle.Colors.line)
                stepButton(systemImage: "plus", enabled: canIncrement, action: onIncrement)
            }
            .nestedCard()
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }

    private func stepButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: systemImage)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(enabled ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// One number in the derived readout strip. The authored value reads at full
/// strength; the numbers this mode computed sit one step back.
private struct StairReadout: View {
    let label: String
    let value: String
    let isAuthored: Bool

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.microLabel)
                .kerning(1.4)
                .foregroundColor(OPSStyle.Colors.textMute)
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(isAuthored ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Chip in the sanctioned 36pt form-picker grammar (MOBILE.md §4.3).
private struct StairChip: View {
    let label: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(OPSStyle.Typography.microLabel)
                }
                Text(label)
                    .font(OPSStyle.Typography.metadata)
                    .kerning(1.2)
            }
            .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.chipMinHeight)
            .background(isSelected ? OPSStyle.Colors.surfaceActive : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(
                        isSelected ? OPSStyle.Colors.fillNeutral : OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
