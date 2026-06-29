// OPS/OPS/DeckBuilder/Views/DeckMeasurementPickerView.swift

import SwiftUI
import UIKit

struct DeckMeasurementPickerConfiguration {
    var imperialFeetRange: ClosedRange<Int> = 0...150
    var imperialInchesRange: ClosedRange<Int> = 0...144
    var imperialSixteenthsRange: ClosedRange<Int> = 0...15
    var metricMetersRange: ClosedRange<Int> = 0...50
    var metricCentimetersRange: ClosedRange<Int> = 0...999
    var metricMillimetersRange: ClosedRange<Int> = 0...99

    static let deckBuilder = DeckMeasurementPickerConfiguration()
}

enum DeckMeasurementPickerTokens {
    static let panelMaxWidth: CGFloat = 360
    static let wheelWidth: CGFloat = 78
    static let wheelHeight: CGFloat = 118
    static let waveformHeight: CGFloat = 24
    static let systemToggleWidth: CGFloat = 168
    static let compactButtonHeight: CGFloat = 44
    static let valuePillMinWidth: CGFloat = 136

    static var panelRadius: CGFloat { OPSStyle.Layout.panelRadius }
    static var controlRadius: CGFloat { OPSStyle.Layout.buttonRadius }
    static var nestedRadius: CGFloat { OPSStyle.Layout.cardRadius }
    static var panelPadding: CGFloat { OPSStyle.Layout.spacing2 }
    static var rowGap: CGFloat { OPSStyle.Layout.spacing1 }
    static var tightGap: CGFloat { OPSStyle.Layout.spacing1 }
    static var standardGap: CGFloat { OPSStyle.Layout.spacing2 }
    static var horizontalInset: CGFloat { OPSStyle.Layout.spacing2 }
    static var iconSize: CGFloat { OPSStyle.Layout.IconSize.md }
    static var smallIconSize: CGFloat { OPSStyle.Layout.IconSize.sm }
    static var minTouch: CGFloat { OPSStyle.Layout.touchTargetMin }
    static var standardTouch: CGFloat { OPSStyle.Layout.touchTargetStandard }
    static var borderWidth: CGFloat { OPSStyle.Layout.Border.standard }
}

enum DeckMeasurementWheelData {
    static func count(in range: ClosedRange<Int>) -> Int {
        range.upperBound - range.lowerBound + 1
    }

    static func clampedValue(_ value: Int, in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    static func row(for value: Int, in range: ClosedRange<Int>) -> Int {
        clampedValue(value, in: range) - range.lowerBound
    }

    static func value(forRow row: Int, in range: ClosedRange<Int>) -> Int {
        clampedValue(range.lowerBound + max(0, row), in: range)
    }
}

struct DeckMeasurementPickerView: View {
    let title: String
    @Binding var value: DeckMeasurementValue
    var leadingSystemImage: String?
    var message: String?
    var configuration: DeckMeasurementPickerConfiguration = .deckBuilder
    var canCommit: (DeckMeasurementValue) -> Bool = { $0.totalInches > 0 }
    var onBack: () -> Void
    var onCancel: (() -> Void)?
    var onCommit: (DeckMeasurementValue) -> Void

    @StateObject private var voiceInput = VoiceDimensionInput(expectedDimensionCount: 1)
    @State private var measurementSystem: MeasurementSystem = .imperial
    @State private var feet = 0
    @State private var inches = 0
    @State private var sixteenths = 0
    @State private var meters = 0
    @State private var centimeters = 0
    @State private var millimeters = 0
    @State private var didLoadInitialValue = false

    private var activeValue: DeckMeasurementValue {
        switch measurementSystem {
        case .imperial:
            return .imperial(feet: feet, inches: inches, sixteenths: sixteenths)
        case .metric:
            return .metric(meters: meters, centimeters: centimeters, millimeters: millimeters)
        }
    }

    var body: some View {
        VStack(spacing: DeckMeasurementPickerTokens.standardGap) {
            wheelRow
            actionRow
            voiceFeedbackRow
            messageRow
        }
        .frame(maxWidth: .infinity)
        // No card behind the whole strip — the controls float over the canvas.
        // An invisible content shape still consumes touches across the control
        // footprint, so a gloved thumb that lands in a gap can't fall through to
        // the canvas reorient drag; bare canvas above the strip still reorients.
        .contentShape(Rectangle())
        .onAppear(perform: loadInitialValue)
        .onChange(of: value) { _, newValue in
            syncFromExternalValue(newValue)
        }
        .onChange(of: voiceInput.parsedDimensions) { _, dimensions in
            guard let first = dimensions.first, let inches = first else { return }
            applyDictatedLength(inches)
        }
        .onDisappear {
            if voiceInput.isListening {
                voiceInput.stopListening()
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: DeckMeasurementPickerTokens.standardGap) {
            // Escape hatches at the leading edge — bail out of speed draw, or
            // step back to the direction wheel. Bare icons, no card.
            if let onCancel {
                bareIconButton(systemName: "xmark", tint: OPSStyle.Colors.text2,
                               label: "Exit speed draw", action: onCancel)
            }
            bareIconButton(systemName: "chevron.left", tint: OPSStyle.Colors.text,
                           label: "Back", action: onBack)

            Spacer(minLength: 0)
            systemToggle
            Spacer(minLength: 0)

            voiceButton

            // Continue — the one accent action, enabled only with a length. The
            // committed value reads live on the canvas, so there is no readout here.
            Button {
                onCommit(activeValue)
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: DeckMeasurementPickerTokens.iconSize, weight: .semibold))
                    .foregroundColor(canCommit(activeValue) ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                    .frame(
                        width: DeckMeasurementPickerTokens.minTouch,
                        height: DeckMeasurementPickerTokens.minTouch
                    )
                    .background(
                        Circle().fill(canCommit(activeValue)
                            ? OPSStyle.Colors.opsAccent.opacity(0.18) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCommit(activeValue))
            .accessibilityLabel("Continue")
        }
        .frame(maxWidth: .infinity)
    }

    private func bareIconButton(
        systemName: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: DeckMeasurementPickerTokens.iconSize, weight: .semibold))
                .foregroundColor(tint)
                .frame(
                    width: DeckMeasurementPickerTokens.minTouch,
                    height: DeckMeasurementPickerTokens.minTouch
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // Compact unit toggle — a small segmented control, not a full-width row.
    private var systemToggle: some View {
        HStack(spacing: 0) {
            measurementSystemButton(.imperial, label: "IMPERIAL")
            measurementSystemButton(.metric, label: "METRIC")
        }
        .background(
            RoundedRectangle(cornerRadius: DeckMeasurementPickerTokens.nestedRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DeckMeasurementPickerTokens.nestedRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.glassBorder, lineWidth: DeckMeasurementPickerTokens.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: DeckMeasurementPickerTokens.nestedRadius, style: .continuous))
    }

    private func measurementSystemButton(_ system: MeasurementSystem, label: String) -> some View {
        let isActive = measurementSystem == system
        return Button {
            measurementSystemBinding.wrappedValue = system
        } label: {
            Text(label == "IMPERIAL" ? "IMP" : "MET")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                .frame(width: DeckMeasurementPickerTokens.minTouch, height: DeckMeasurementPickerTokens.minTouch)
                // Single sliding indicator on the recessed track — no nested glass.
                .background(
                    RoundedRectangle(cornerRadius: DeckMeasurementPickerTokens.controlRadius, style: .continuous)
                        .fill(isActive ? OPSStyle.Colors.surfaceActive : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var wheelRow: some View {
        switch measurementSystem {
        case .imperial:
            HStack(spacing: DeckMeasurementPickerTokens.tightGap) {
                measurementWheel(label: "FT", range: configuration.imperialFeetRange, value: Binding(
                    get: { feet },
                    set: { feet = $0; publishImperialValue() }
                ))
                measurementWheel(label: "IN", range: configuration.imperialInchesRange, value: Binding(
                    get: { inches },
                    set: { inches = $0; publishImperialValue() }
                ))
                measurementWheel(label: "16TH", range: configuration.imperialSixteenthsRange, value: Binding(
                    get: { sixteenths },
                    set: { sixteenths = $0; publishImperialValue() }
                ))
            }
            .padding(DeckMeasurementPickerTokens.tightGap)
            .frame(maxWidth: .infinity)
            .measurementControlChrome(flat: true, cornerRadius: DeckMeasurementPickerTokens.nestedRadius)
        case .metric:
            HStack(spacing: DeckMeasurementPickerTokens.tightGap) {
                measurementWheel(label: "M", range: configuration.metricMetersRange, value: Binding(
                    get: { meters },
                    set: { meters = $0; publishMetricValue() }
                ))
                measurementWheel(label: "CM", range: configuration.metricCentimetersRange, value: Binding(
                    get: { centimeters },
                    set: { centimeters = $0; publishMetricValue() }
                ))
                measurementWheel(label: "MM", range: configuration.metricMillimetersRange, value: Binding(
                    get: { millimeters },
                    set: { millimeters = $0; publishMetricValue() }
                ))
            }
            .padding(DeckMeasurementPickerTokens.tightGap)
            .frame(maxWidth: .infinity)
            .measurementControlChrome(flat: true, cornerRadius: DeckMeasurementPickerTokens.nestedRadius)
        }
    }

    private var voiceButton: some View {
        Button {
            toggleDictation()
        } label: {
            Image(systemName: voiceInput.isListening ? "mic.fill" : "mic")
                .font(.system(size: DeckMeasurementPickerTokens.iconSize, weight: .semibold))
                .foregroundColor(voiceInput.isListening ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.text2)
                .frame(
                    width: DeckMeasurementPickerTokens.minTouch,
                    height: DeckMeasurementPickerTokens.minTouch
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voiceInput.isListening ? "Stop dictation" : "Dictate measurement")
    }

    @ViewBuilder
    private var voiceFeedbackRow: some View {
        if voiceInput.isListening || !voiceInput.recognizedText.isEmpty {
            HStack(spacing: DeckMeasurementPickerTokens.standardGap) {
                if voiceInput.isListening {
                    VoiceWaveformView(isListening: true)
                        .frame(height: DeckMeasurementPickerTokens.waveformHeight)
                        .transition(.opacity)
                } else if !voiceInput.recognizedText.isEmpty {
                    Text(voiceInput.recognizedText.uppercased())
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0)
            }
            .animation(OPSStyle.Animation.hover, value: voiceInput.isListening)
        }
    }

    @ViewBuilder
    private var messageRow: some View {
        if let message = message ?? voiceInput.error {
            Text(message.uppercased())
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tanTextM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var measurementSystemBinding: Binding<MeasurementSystem> {
        Binding(
            get: { measurementSystem },
            set: { convert(to: $0) }
        )
    }

    private func measurementWheel(label: String, range: ClosedRange<Int>, value: Binding<Int>) -> some View {
        VStack(spacing: 0) {
            Picker(label, selection: value) {
                ForEach(Array(range), id: \.self) { rowValue in
                    Text("\(rowValue)")
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .tag(rowValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(
                width: DeckMeasurementPickerTokens.wheelWidth,
                height: DeckMeasurementPickerTokens.wheelHeight - 20
            )
            .compositingGroup()
            .clipped()

            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        // No per-wheel chrome — the three wheels share one backing (wheelRow) so
        // they read as a single dial cluster. Each dial expands to an equal share
        // of the strip so the cluster uses the full available width.
        .frame(width: DeckMeasurementPickerTokens.wheelWidth, height: DeckMeasurementPickerTokens.wheelHeight)
        .frame(maxWidth: .infinity)
    }

    private func loadInitialValue() {
        guard !didLoadInitialValue else { return }
        didLoadInitialValue = true
        syncComponents(from: value)
        measurementSystem = value.measurementSystem
        voiceInput.setMeasurementSystem(value.measurementSystem)
    }

    private func syncFromExternalValue(_ newValue: DeckMeasurementValue) {
        let local = activeValue
        guard abs(local.totalInches - newValue.totalInches) > 0.0001
                || local.measurementSystem != newValue.measurementSystem else {
            return
        }
        measurementSystem = newValue.measurementSystem
        syncComponents(from: newValue)
        voiceInput.setMeasurementSystem(newValue.measurementSystem)
    }

    private func convert(to newSystem: MeasurementSystem) {
        guard newSystem != measurementSystem else { return }
        let converted = DeckMeasurementValue(measurementSystem: newSystem, totalInches: activeValue.totalInches)
        measurementSystem = newSystem
        syncComponents(from: converted)
        voiceInput.setMeasurementSystem(newSystem)
        value = converted
    }

    private func publishImperialValue() {
        measurementSystem = .imperial
        let nextValue = DeckMeasurementValue.imperial(feet: feet, inches: inches, sixteenths: sixteenths)
        voiceInput.setMeasurementSystem(.imperial)
        value = nextValue
    }

    private func publishMetricValue() {
        measurementSystem = .metric
        let nextValue = DeckMeasurementValue.metric(meters: meters, centimeters: centimeters, millimeters: millimeters)
        voiceInput.setMeasurementSystem(.metric)
        value = nextValue
    }

    private func applyDictatedLength(_ inches: Double) {
        let nextValue = DeckMeasurementValue(measurementSystem: measurementSystem, totalInches: inches)
        syncComponents(from: nextValue)
        value = nextValue
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func syncComponents(from value: DeckMeasurementValue) {
        let imperial = value.imperialComponents
        feet = imperial.feet
        inches = imperial.inches
        sixteenths = imperial.sixteenths

        let metric = value.metricComponents
        meters = metric.meters
        centimeters = metric.centimeters
        millimeters = metric.millimeters
    }

    private func toggleDictation() {
        if voiceInput.isListening {
            voiceInput.stopListening()
            return
        }

        guard voiceInput.isAuthorized else {
            if voiceInput.authorizationStatus == .notDetermined {
                voiceInput.requestAuthorization()
            } else {
                voiceInput.error = "SYS :: DICTATION LOCKED"
            }
            return
        }

        voiceInput.setMeasurementSystem(measurementSystem)
        voiceInput.startListening()
    }
}

extension View {
    /// Frosted chrome for the speed-draw overlay, in two elevations so the
    /// floating controls read as ONE instrument instead of a pile of glass tiles:
    /// - default (`flat: false`) — full L1 glass plate (ultraThinMaterial + tint +
    ///   hairline). Used by the overlay PANEL itself.
    /// - `flat: true` — a flat L2 well/key (solid `surfaceInput` fill + hairline,
    ///   NO material) for controls that sit ON the glass panel, so we never stack
    ///   one blurred material on another (the old glass-on-glass clutter).
    func measurementControlChrome(
        isProminent: Bool = false,
        isActive: Bool = false,
        flat: Bool = false,
        cornerRadius: CGFloat = DeckMeasurementPickerTokens.controlRadius
    ) -> some View {
        let isEmphasized = isProminent || isActive
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return background(
            ZStack {
                if flat {
                    // L2 control on the panel — solid recessed fill, no blur.
                    shape.fill(OPSStyle.Colors.surfaceInput)
                    if isProminent {
                        // The single accent element per panel (valid Continue).
                        shape.fill(OPSStyle.Colors.opsAccent.opacity(0.18))
                    } else if isActive {
                        shape.fill(OPSStyle.Colors.surfaceActive)
                    }
                } else {
                    // L1 glass plate.
                    shape.fill(.ultraThinMaterial)
                    shape.fill(OPSStyle.Colors.glassApprox)
                    if isEmphasized {
                        shape.fill(OPSStyle.Colors.surfaceActive)
                    }
                    LinearGradient(
                        colors: [OPSStyle.Colors.surfaceInput, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(shape)
                    .allowsHitTesting(false)
                }
            }
        )
        .overlay(
            shape.strokeBorder(
                isEmphasized ? OPSStyle.Colors.text2.opacity(0.42) : OPSStyle.Colors.glassBorder,
                lineWidth: DeckMeasurementPickerTokens.borderWidth
            )
        )
        .clipShape(shape)
    }
}
