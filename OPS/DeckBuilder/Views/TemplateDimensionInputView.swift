// OPS/OPS/DeckBuilder/Views/TemplateDimensionInputView.swift

import SwiftUI
import UIKit

struct TemplateDimensionInputView: View {
    let templateType: DeckTemplateType
    let onCreateDeck: ([Double]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var voiceInput: VoiceDimensionInput
    @State private var dimensionStrings: [String]
    @State private var showingVoiceOverlay = false

    private let labels: [DimensionLabel]

    init(templateType: DeckTemplateType, onCreateDeck: @escaping ([Double]) -> Void) {
        self.templateType = templateType
        self.onCreateDeck = onCreateDeck
        self.labels = templateType.dimensionLabels
        self._dimensionStrings = State(initialValue: Array(repeating: "", count: templateType.dimensionCount))
        self._voiceInput = StateObject(wrappedValue: VoiceDimensionInput(
            expectedDimensionCount: templateType.dimensionCount
        ))
    }

    private var parsedInches: [Double?] {
        dimensionStrings.map { str in
            guard !str.isEmpty else { return nil }
            return DimensionEngine.parseToInches(str, system: .imperial)
        }
    }

    private var allValid: Bool {
        parsedInches.allSatisfy { $0 != nil && ($0 ?? 0) > 0 }
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

                    // Dimension fields
                    dimensionFields

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
            // Voice → fields sync
            for (i, value) in newDimensions.enumerated() {
                if let inches = value, i < dimensionStrings.count, dimensionStrings[i].isEmpty {
                    dimensionStrings[i] = DimensionEngine.format(inches, system: .imperial)
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

    private func drawTemplateDiagram(context: GraphicsContext, size: CGSize) {
        let padding: CGFloat = 30
        let available = CGSize(width: size.width - padding * 2, height: size.height - padding * 2)

        // Get the vertex pattern — may have varying aspect ratio based on typed dimensions
        let (verts, edgeLabels) = templateNormalizedShape()
        guard !verts.isEmpty else { return }

        // Find bounding box of the normalized shape and scale to fit uniformly
        let xs = verts.map(\.x), ys = verts.map(\.y)
        let shapeW = max((xs.max() ?? 1) - (xs.min() ?? 0), 0.01)
        let shapeH = max((ys.max() ?? 1) - (ys.min() ?? 0), 0.01)
        let fitScale = min(available.width / shapeW, available.height / shapeH)
        let offsetX = padding + (available.width - shapeW * fitScale) / 2
        let offsetY = padding + (available.height - shapeH * fitScale) / 2

        let points = verts.map { v in
            CGPoint(
                x: v.x * fitScale + offsetX,
                y: v.y * fitScale + offsetY
            )
        }

        // Draw filled shape
        var shapePath = Path()
        shapePath.move(to: points[0])
        for i in 1..<points.count {
            shapePath.addLine(to: points[i])
        }
        shapePath.closeSubpath()
        context.fill(shapePath, with: .color(OPSStyle.Colors.primaryAccent.opacity(0.1)))

        // Draw edges with dimension labels
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            let start = points[i]
            let end = points[j]

            // Edge line
            var edgePath = Path()
            edgePath.move(to: start)
            edgePath.addLine(to: end)
            context.stroke(edgePath, with: .color(Color.white.opacity(0.6)), lineWidth: 1.5)

            // Label at midpoint
            if i < edgeLabels.count {
                let label = edgeLabels[i]
                let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

                // Offset label away from center of shape
                let centerX = points.map(\.x).reduce(0, +) / CGFloat(n)
                let centerY = points.map(\.y).reduce(0, +) / CGFloat(n)
                let dx = mid.x - centerX
                let dy = mid.y - centerY
                let dist = max(sqrt(dx * dx + dy * dy), 1)
                let offsetAmt: CGFloat = 18
                let labelPos = CGPoint(x: mid.x + dx / dist * offsetAmt, y: mid.y + dy / dist * offsetAmt)

                context.draw(
                    Text(label.letter)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(label.color),
                    at: labelPos
                )
            }
        }

        // Draw vertices
        for point in points {
            let dotRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dotRect), with: .color(Color.white))
        }
    }

    /// Returns normalized vertex positions (0..1 range) and edge labels for diagram rendering.
    /// Positions scale proportionally based on entered dimensions for live feedback.
    private func templateNormalizedShape() -> (vertices: [CGPoint], labels: [DimensionLabel]) {
        let dims = parsedInches.map { $0 ?? 1.0 } // fall back to 1.0 for empty fields

        switch templateType {
        case .rectangle, .frontPorch, .freestanding:
            let a = max(dims[safe: 0] ?? 1, 0.1)  // length
            let b = max(dims[safe: 1] ?? 1, 0.1)  // depth
            let r = b / a  // aspect ratio
            return (
                [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: r), CGPoint(x: 0, y: r)],
                labels
            )

        case .lShape:
            let a = max(dims[safe: 0] ?? 1, 0.1)
            let b = max(dims[safe: 1] ?? 1, 0.1)
            let c = max(dims[safe: 2] ?? 1, 0.1)
            let d = max(dims[safe: 3] ?? 1, 0.1)
            let rB = b / a, rC = c / a, rD = d / a
            return (
                [
                    CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                    CGPoint(x: 1, y: rB), CGPoint(x: rC, y: rB),
                    CGPoint(x: rC, y: rB + rD), CGPoint(x: 0, y: rB + rD),
                ],
                labels
            )

        case .wraparound:
            let a = max(dims[safe: 0] ?? 1, 0.1)
            let b = max(dims[safe: 1] ?? 1, 0.1)
            let c = max(dims[safe: 2] ?? 1, 0.1)
            let d = max(dims[safe: 3] ?? 1, 0.1)
            let rB = b / a, rC = c / a, rD = d / a
            return (
                [
                    CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                    CGPoint(x: 1, y: rB + rD), CGPoint(x: rC, y: rB + rD),
                    CGPoint(x: rC, y: rB), CGPoint(x: 0, y: rB),
                ],
                labels
            )

        case .tShape:
            let a = max(dims[safe: 0] ?? 1, 0.1)
            let b = max(dims[safe: 1] ?? 1, 0.1)
            let c = max(dims[safe: 2] ?? 1, 0.1)
            let d = max(dims[safe: 3] ?? 1, 0.1)
            let rB = b / a, rC = c / a, rD = d / a
            let inset = (1.0 - rC) / 2  // center the stem
            return (
                [
                    CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                    CGPoint(x: 1, y: rB), CGPoint(x: inset + rC, y: rB),
                    CGPoint(x: inset + rC, y: rB + rD), CGPoint(x: inset, y: rB + rD),
                    CGPoint(x: inset, y: rB), CGPoint(x: 0, y: rB),
                ],
                labels
            )

        case .multiLevel:
            let a = max(dims[safe: 0] ?? 1, 0.1)
            let b = max(dims[safe: 1] ?? 1, 0.1)
            let r = b / a
            return (
                [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: r), CGPoint(x: 0, y: r)],
                [labels[0], labels[1]]
            )

        case .poolDeck:
            return (
                [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 0.7), CGPoint(x: 0, y: 0.7)],
                labels
            )
        }
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

            // Input
            TextField("0' 0\"", text: $dimensionStrings[index])
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.plain)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(fieldBorderColor(index: index), lineWidth: 1)
                )

            // Unit label
            Text("ft/in")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: 36)
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }

    private func fieldBorderColor(index: Int) -> Color {
        let str = dimensionStrings[index]
        if str.isEmpty { return OPSStyle.Colors.cardBorder }
        if let inches = DimensionEngine.parseToInches(str, system: .imperial), inches > 0 {
            return labels[index].color.opacity(0.5)
        }
        return Color.red.opacity(0.6)
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
            onCreateDeck(inches)
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
