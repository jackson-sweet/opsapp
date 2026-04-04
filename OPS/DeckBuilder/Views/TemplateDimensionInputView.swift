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

        // Get the vertex pattern in normalized [0..1] space
        let (verts, edgeLabels) = templateNormalizedShape()
        guard !verts.isEmpty else { return }

        // Scale + offset to fit
        let points = verts.map { v in
            CGPoint(
                x: v.x * available.width + padding,
                y: v.y * available.height + padding
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

    /// Returns normalized vertex positions (0..1 range) and edge labels for diagram rendering
    private func templateNormalizedShape() -> (vertices: [CGPoint], labels: [DimensionLabel]) {
        switch templateType {
        case .rectangle, .frontPorch, .freestanding:
            return (
                [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 0.6), CGPoint(x: 0, y: 0.6)],
                labels
            )

        case .lShape:
            return (
                [
                    CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                    CGPoint(x: 1, y: 0.3), CGPoint(x: 0.55, y: 0.3),
                    CGPoint(x: 0.55, y: 0.8), CGPoint(x: 0, y: 0.8),
                ],
                labels
            )

        case .wraparound:
            return (
                [
                    CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                    CGPoint(x: 1, y: 0.8), CGPoint(x: 0.4, y: 0.8),
                    CGPoint(x: 0.4, y: 0.3), CGPoint(x: 0, y: 0.3),
                ],
                labels
            )

        case .tShape:
            return (
                [
                    CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                    CGPoint(x: 1, y: 0.25), CGPoint(x: 0.7, y: 0.25),
                    CGPoint(x: 0.7, y: 0.85), CGPoint(x: 0.3, y: 0.85),
                    CGPoint(x: 0.3, y: 0.25), CGPoint(x: 0, y: 0.25),
                ],
                labels
            )

        case .multiLevel:
            // Show as rectangle (upper level) for diagram
            return (
                [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 0.6), CGPoint(x: 0, y: 0.6)],
                [labels[0], labels[1]] // Only A, B for the visible rectangle
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
            // Pulsing mic indicator
            Image(systemName: "mic.fill")
                .font(.system(size: 32))
                .foregroundColor(OPSStyle.Colors.warningStatus)
                .symbolEffect(.pulse, isActive: voiceInput.isListening)

            if !voiceInput.recognizedText.isEmpty {
                Text(voiceInput.recognizedText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                Text("Speak dimensions: \"A twenty-four feet, B fifteen feet\"")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if let error = voiceInput.error {
                Text(error)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(Color.red)
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
