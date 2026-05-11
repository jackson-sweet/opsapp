// OPS/OPS/DeckBuilder/Views/TemplateDimensionInputView.swift

import SwiftUI
import UIKit

struct TemplateDimensionInputView: View {
    let templateType: DeckTemplateType
    /// Now passes BOTH the parsed inches AND the unit mode the user typed in,
    /// so downstream callers can stamp `DrawingConfig.measurementSystem`
    /// correctly. Bug e7965781.
    let onCreateDeck: ([Double], MeasurementSystem) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var voiceInput: VoiceDimensionInput
    @State private var dimensionStrings: [String]
    @State private var showingVoiceOverlay = false
    /// Toggle between imperial (default) and metric input parsing. Persisted
    /// to UserDefaults so the user's preference survives app launches —
    /// imperial-only contractors see imperial each time, metric-only contractors
    /// don't have to flip the switch every job. Bug e7965781.
    @State private var measurementSystem: MeasurementSystem = TemplateDimensionInputView.loadStoredSystem()

    private let labels: [DimensionLabel]

    private static let storageKey = "deckBuilder.template.measurementSystem"

    private static func loadStoredSystem() -> MeasurementSystem {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let stored = MeasurementSystem(rawValue: raw) {
            return stored
        }
        return .imperial
    }

    init(templateType: DeckTemplateType, onCreateDeck: @escaping ([Double], MeasurementSystem) -> Void) {
        self.templateType = templateType
        self.onCreateDeck = onCreateDeck
        self.labels = templateType.dimensionLabels
        self._dimensionStrings = State(initialValue: Array(repeating: "", count: templateType.dimensionCount))
        self._voiceInput = StateObject(wrappedValue: VoiceDimensionInput(
            expectedDimensionCount: templateType.dimensionCount
        ))
    }

    /// Parsed inches for each input field. Always returns inches as the
    /// canonical internal unit regardless of the user's selected display
    /// system — `DimensionEngine.parseToInches(...)` converts cm/m/mm to
    /// inches transparently. Bug e7965781.
    private var parsedInches: [Double?] {
        dimensionStrings.map { str in
            guard !str.isEmpty else { return nil }
            return DimensionEngine.parseToInches(str, system: measurementSystem)
        }
    }

    /// All four (or N) fields must be non-empty AND > 0 AND must produce
    /// a geometrically valid shape per `DeckTemplateType.validationErrors`.
    /// Without the shape check the Create button used to enable on input that
    /// then silently degraded to a rectangle in the engine — the cause of
    /// bug 22577979's "L-shape → rectangle" import.
    private var allValid: Bool {
        guard parsedInches.allSatisfy({ $0 != nil && ($0 ?? 0) > 0 }) else { return false }
        return geometricErrors.isEmpty
    }

    /// Geometric constraint violations for the currently-parsed dimensions
    /// (empty fields are filtered out so the user doesn't see a wall of red
    /// errors before they finish typing).
    private var geometricErrors: [String] {
        let dims = parsedInches.compactMap { $0 }
        guard dims.count == templateType.dimensionCount else { return [] }
        return templateType.validationErrors(for: dims)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing4) {
                    // Shape diagram
                    shapeDiagram
                        .padding(.top, OPSStyle.Layout.spacing3)

                    // Imperial / metric toggle — sits above dimension fields
                    // so the user picks units BEFORE typing values. Saves the
                    // choice to UserDefaults so it persists across launches.
                    // Bug e7965781.
                    unitModeToggle

                    // Dimension fields
                    dimensionFields

                    // Constraint validation — surfaces "Extension width (C)
                    // must be less than long side (A)" etc. inline before
                    // the user taps Create. Bug 22577979.
                    if !geometricErrors.isEmpty {
                        validationBanner
                            .transition(.opacity)
                    }

                    // Voice overlay
                    if showingVoiceOverlay {
                        voiceOverlay
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Create button
                    createButton
                        .padding(.top, OPSStyle.Layout.spacing2)
                        .padding(.bottom, OPSStyle.Layout.spacing5)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
        .background(OPSStyle.Colors.background)
        .onAppear {
            voiceInput.requestAuthorization()
        }
        .onChange(of: voiceInput.parsedDimensions) { _, newDimensions in
            // Voice → fields sync. Format in the user's active unit mode so
            // the spoken value lands in the field as e.g. "2.5 m" rather than
            // a forced imperial "8' 2"" when the user is working in metric.
            // Bug e7965781.
            for (i, value) in newDimensions.enumerated() {
                if let inches = value, i < dimensionStrings.count, dimensionStrings[i].isEmpty {
                    dimensionStrings[i] = DimensionEngine.format(inches, system: measurementSystem)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }

            Spacer()

            Text(templateType.displayName)
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Spacer()

            // Mic button
            Button {
                // Dismiss keyboard before activating mic
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                withAnimation(OPSStyle.Animation.spring) {
                    if voiceInput.isListening {
                        voiceInput.stopListening()
                        showingVoiceOverlay = false
                    } else {
                        showingVoiceOverlay = true
                        voiceInput.startListening()
                    }
                }
            } label: {
                Image(systemName: voiceInput.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(voiceInput.isListening ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryAccent)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(!voiceInput.isAuthorized && voiceInput.authorizationStatus != .notDetermined)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
    }

    // MARK: - Shape Diagram

    private var shapeDiagram: some View {
        Canvas { context, size in
            drawTemplateDiagram(context: context, size: size)
        }
        .frame(height: 200)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    }

    /// Bug 22577979 — single source of truth for the diagram shape is now
    /// `DeckTemplateEngine.vertexPositions(...)`. Previously the input view
    /// kept its own normalized-coords switch statement that didn't match what
    /// the engine generated (L-shape preview said "wide top, leg down-left"
    /// but engine generated "thin wide top + main body below-left"). Routing
    /// both through the engine guarantees the preview IS the export.
    private func drawTemplateDiagram(context: GraphicsContext, size: CGSize) {
        let padding: CGFloat = 36
        let available = CGSize(width: size.width - padding * 2, height: size.height - padding * 2)

        let (verts, edgeBindings) = engineShape()
        guard !verts.isEmpty else { return }

        // Find bounding box and scale uniformly to fit.
        let xs = verts.map(\.x), ys = verts.map(\.y)
        let shapeW = max((xs.max() ?? 1) - (xs.min() ?? 0), 0.01)
        let shapeH = max((ys.max() ?? 1) - (ys.min() ?? 0), 0.01)
        let fitScale = min(available.width / shapeW, available.height / shapeH)
        let offsetX = padding + (available.width - shapeW * fitScale) / 2
        let offsetY = padding + (available.height - shapeH * fitScale) / 2

        let points = verts.map { v in
            CGPoint(
                x: (v.x - (xs.min() ?? 0)) * fitScale + offsetX,
                y: (v.y - (ys.min() ?? 0)) * fitScale + offsetY
            )
        }

        // Fill — uses opsAccent at low opacity (steel-blue tint) to keep the
        // shape visible without dominating the labels. Matches OPSStyle's
        // monochrome-canvas + accent rule.
        var shapePath = Path()
        shapePath.move(to: points[0])
        for i in 1..<points.count {
            shapePath.addLine(to: points[i])
        }
        shapePath.closeSubpath()
        context.fill(shapePath, with: .color(OPSStyle.Colors.opsAccent.opacity(0.08)))

        // Edges — colour each edge with its dimension label's colour so the
        // visual link between "B = Full Depth" and *that specific line* is
        // unambiguous. Unlabeled edges (e.g. the derived (b-d) step of an
        // L-shape) draw in a muted neutral so they don't steal focus.
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            let start = points[i]
            let end = points[j]

            var edgePath = Path()
            edgePath.move(to: start)
            edgePath.addLine(to: end)

            let binding = edgeBindings[i]
            let stroke: Color = binding?.label.color ?? OPSStyle.Colors.cardBorder
            let width: CGFloat = binding == nil ? 1.0 : 2.2
            context.stroke(edgePath, with: .color(stroke), lineWidth: width)
        }

        // Labels — pinned to each edge's outward normal, NOT the polygon
        // centroid. Old behaviour offset radially from centroid which
        // mis-positioned labels on non-convex shapes (e.g. the L-shape's
        // inner corner). Now every label sits perpendicular to its own
        // edge, with a leader dot anchoring the visual link.
        let centroid = polygonCentroid(points)
        for i in 0..<n {
            guard let binding = edgeBindings[i] else { continue }
            let j = (i + 1) % n
            let start = points[i]
            let end = points[j]
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

            // Outward normal: rotate edge direction 90°, pick the side that
            // points AWAY from the polygon centre so the label never falls
            // inside the shape.
            let dx = end.x - start.x
            let dy = end.y - start.y
            let len = max(sqrt(dx * dx + dy * dy), 1)
            var nx = -dy / len
            var ny =  dx / len
            let toCentroid = CGPoint(x: mid.x - centroid.x, y: mid.y - centroid.y)
            if (nx * toCentroid.x + ny * toCentroid.y) < 0 {
                nx = -nx; ny = -ny
            }

            let leaderDist: CGFloat = 8
            let labelDist: CGFloat = 22
            let leaderPos = CGPoint(x: mid.x + nx * leaderDist, y: mid.y + ny * leaderDist)
            let labelPos  = CGPoint(x: mid.x + nx * labelDist,  y: mid.y + ny * labelDist)

            // Tiny leader dot in label colour — makes the binding read at
            // a glance even when the label has to clear another edge.
            context.fill(
                Path(ellipseIn: CGRect(x: leaderPos.x - 2.5, y: leaderPos.y - 2.5, width: 5, height: 5)),
                with: .color(binding.label.color)
            )

            // Letter — bold, in the label's color.
            context.draw(
                Text(binding.label.letter)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(binding.label.color),
                at: labelPos
            )

            // Live numeric value below the letter — formatted in whatever
            // units the user has picked (imperial / metric). Empty if the
            // field is still blank. This is the live measurement display
            // bug 22577979 asked for.
            if let inches = parsedInches[safe: binding.labelIndex] ?? nil {
                let formatted = DimensionEngine.format(inches, system: measurementSystem)
                let textPos = CGPoint(x: labelPos.x + nx * 12, y: labelPos.y + ny * 12)
                context.draw(
                    Text(formatted)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(binding.label.color.opacity(0.85)),
                    at: textPos
                )
            }
        }

        // Vertices — small white dots, drawn last so they sit on top of edges.
        for point in points {
            let dotRect = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: dotRect), with: .color(OPSStyle.Colors.primaryText))
        }

        // Pool deck callout — pool diameter (label C) has no edge to live on,
        // so we render the pool itself as a centred circle with the C label
        // floating beside it. Bug 22577979 — pool deck previously inherited
        // the rectangle's preview with no pool indication at all.
        if templateType == .poolDeck,
           let pool = parsedInches[safe: 2] ?? nil,
           let length = parsedInches[safe: 0] ?? nil,
           let depth = parsedInches[safe: 1] ?? nil,
           pool > 0, length > 0, depth > 0 {
            let poolPxRadius = (pool / 2) * fitScale
            let center = CGPoint(
                x: offsetX + (length / 2) * fitScale,
                y: offsetY + (depth / 2) * fitScale
            )
            let circleRect = CGRect(
                x: center.x - poolPxRadius,
                y: center.y - poolPxRadius,
                width: poolPxRadius * 2,
                height: poolPxRadius * 2
            )
            let poolColor = templateType.dimensionLabels[2].color
            context.fill(Path(ellipseIn: circleRect), with: .color(poolColor.opacity(0.18)))
            context.stroke(Path(ellipseIn: circleRect), with: .color(poolColor), lineWidth: 2.2)
            context.draw(
                Text("C")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(poolColor),
                at: center
            )
        }
    }

    private func polygonCentroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sx = points.map(\.x).reduce(0, +)
        let sy = points.map(\.y).reduce(0, +)
        return CGPoint(x: sx / CGFloat(points.count), y: sy / CGFloat(points.count))
    }

    /// Pulls vertex positions from the engine when inputs are valid; otherwise
    /// falls back to a "best guess" preview built from fields that ARE filled
    /// so the user gets a live shape outline as they type rather than a
    /// rectangle placeholder. Returns the polygon vertices plus an array of
    /// per-edge label bindings (nil where the edge isn't user-named).
    private func engineShape() -> (vertices: [(x: Double, y: Double)], edgeBindings: [EdgeBinding?]) {
        // Fill in dummy values for unfilled fields so the preview still
        // animates as the user types one field at a time. Use slightly
        // asymmetric defaults so the L / T / wraparound shapes don't degenerate.
        let defaults: [Double] = [240, 144, 96, 48]  // 20', 12', 8', 4'
        let dims: [Double] = (0..<templateType.dimensionCount).map { i in
            if let v = parsedInches[safe: i] ?? nil, v > 0 { return v }
            return defaults[safe: i] ?? 120
        }

        // Try engine geometry first — only succeeds when inputs satisfy all
        // shape constraints. If they don't (and we used defaults for missing
        // fields), substitute defaults wholesale so the user sees the
        // canonical template until they fix the constraint violation.
        let verts: [(x: Double, y: Double)]
        if let engineVerts = DeckTemplateEngine.vertexPositions(template: templateType, dimensions: dims) {
            verts = engineVerts
        } else if let canonicalVerts = DeckTemplateEngine.vertexPositions(template: templateType, dimensions: defaults) {
            verts = canonicalVerts
        } else {
            verts = []
        }

        // Build edge bindings using the template's label→edge index map.
        let mapping = templateType.labelEdgeIndices
        var bindings = Array<EdgeBinding?>(repeating: nil, count: verts.count)
        for (labelIdx, edgeIdx) in mapping.enumerated() {
            guard edgeIdx >= 0, edgeIdx < bindings.count, labelIdx < labels.count else { continue }
            bindings[edgeIdx] = EdgeBinding(label: labels[labelIdx], labelIndex: labelIdx)
        }
        return (verts, bindings)
    }

    private struct EdgeBinding {
        let label: DimensionLabel
        let labelIndex: Int
    }

    // MARK: - Dimension Fields

    private var dimensionFields: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            ForEach(Array(labels.enumerated()), id: \.element.id) { index, label in
                dimensionField(index: index, label: label)
            }
        }
    }

    private func dimensionField(index: Int, label: DimensionLabel) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            // Letter badge
            Text(label.letter)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(label.color.opacity(0.8))
                .cornerRadius(OPSStyle.Layout.cornerRadius)

            // Field label
            Text(label.name)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 90, alignment: .leading)

            // Input — placeholder example matches the active unit mode so the
            // user immediately understands what input is expected.
            TextField(placeholderForActiveSystem, text: $dimensionStrings[index])
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.plain)
                .onChange(of: dimensionStrings[index]) { _, newValue in
                    // Swap iOS smart-quotes back to ASCII `'` / `"` so the visible
                    // text always matches what the parser expects. (Imperial-only
                    // concern but cheap to run in metric too.)
                    let sanitized = DimensionEngine.sanitizeQuotesForLiveInput(newValue)
                    if sanitized != newValue { dimensionStrings[index] = sanitized }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(fieldBorderColor(index: index), lineWidth: 1)
                )

            // Unit label — switches between "ft/in" and "m/cm" so the field
            // tells the user up-front which units the parser is expecting.
            Text(unitSuffixForActiveSystem)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: 36)
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }

    /// Field-validity border. Live-parses through DimensionEngine using the
    /// active unit mode so toggling imperial→metric instantly re-validates
    /// existing typed values. Invalid inputs paint a rose stroke (OPSStyle's
    /// negative tone) instead of the SwiftUI primitive `.red` we used to use.
    /// Bug e7965781.
    private func fieldBorderColor(index: Int) -> Color {
        let str = dimensionStrings[index]
        if str.isEmpty { return OPSStyle.Colors.cardBorder }
        if let inches = DimensionEngine.parseToInches(str, system: measurementSystem), inches > 0 {
            return labels[index].color.opacity(0.5)
        }
        return OPSStyle.Colors.rose.opacity(0.6)
    }

    /// Placeholder example for the input field that shows the user the
    /// canonical short-form for the active unit mode.
    private var placeholderForActiveSystem: String {
        switch measurementSystem {
        case .imperial: return "0' 0\""
        case .metric:   return "0 m"
        }
    }

    /// Tiny unit suffix shown to the right of every input field.
    private var unitSuffixForActiveSystem: String {
        switch measurementSystem {
        case .imperial: return "ft/in"
        case .metric:   return "m/cm"
        }
    }

    // MARK: - Validation Banner

    /// Inline error panel listing every constraint the current inputs violate.
    /// Rose-tinted, hairline-bordered — matches the OPSStyle "rose = negative"
    /// semantic. Copy is operator-voice: terse, no "please", no exclamation.
    private var validationBanner: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.rose)
                Text("CHECK DIMENSIONS")
                    .font(OPSStyle.Typography.smallCaption)
                    .tracking(1.2)
                    .foregroundColor(OPSStyle.Colors.rose)
            }
            ForEach(geometricErrors, id: \.self) { msg in
                Text(msg)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.roseSoft)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.roseLine, lineWidth: 1)
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Unit Toggle

    /// Imperial / metric unit-mode toggle. Drives both the parser and the
    /// `DrawingConfig.measurementSystem` stamped on the resulting deck design
    /// (so the deck builder formats every dimension back in the user's chosen
    /// units). Bug e7965781.
    private var unitModeToggle: some View {
        SegmentedControl(
            selection: Binding(
                get: { measurementSystem },
                set: { newValue in
                    measurementSystem = newValue
                    UserDefaults.standard.set(newValue.rawValue, forKey: Self.storageKey)
                }
            ),
            options: [(MeasurementSystem.imperial, "Imperial"), (MeasurementSystem.metric, "Metric")]
        )
    }

    // MARK: - Voice Overlay

    private var voiceOverlay: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            // Audio waveform visualization
            VoiceWaveformView(isListening: voiceInput.isListening)
                .frame(height: 40)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

            // Mic icon
            Image(systemName: "mic.fill")
                .font(.system(size: 28))
                .foregroundColor(OPSStyle.Colors.warningStatus)
                .symbolEffect(.pulse, isActive: voiceInput.isListening)

            if !voiceInput.recognizedText.isEmpty {
                Text(voiceInput.recognizedText)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                Text("Speak: \"A twenty-four feet, B fifteen feet\"")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if let error = voiceInput.error {
                Text(error)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
            }

            Button {
                voiceInput.stopListening()
                withAnimation(OPSStyle.Animation.spring) {
                    showingVoiceOverlay = false
                }
            } label: {
                Text("Done")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .frame(height: OPSStyle.Layout.touchTargetMin)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    }

    // MARK: - Create Button

    private var createButton: some View {
        Button {
            let inches = parsedInches.compactMap { $0 }
            guard inches.count == templateType.dimensionCount else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // Bug e7965781 — hand BOTH the parsed inches AND the active unit
            // mode back to the caller so the resulting deck design's
            // DrawingConfig stamps the right `measurementSystem` and formats
            // dimensions in the units the user typed.
            onCreateDeck(inches, measurementSystem)
        } label: {
            Text("Create Deck")
                .font(OPSStyle.Typography.button)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(allValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.3))
                .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        }
        .disabled(!allValid)
    }
}
