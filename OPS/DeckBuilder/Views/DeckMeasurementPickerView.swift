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
    static let panelMaxWidth: CGFloat = 348
    static let wheelWidth: CGFloat = 92
    static let wheelHeight: CGFloat = 118
    static let waveformHeight: CGFloat = 34

    static var panelRadius: CGFloat { OPSStyle.Layout.panelRadius }
    static var controlRadius: CGFloat { OPSStyle.Layout.buttonRadius }
    static var nestedRadius: CGFloat { OPSStyle.Layout.cardRadius }
    static var panelPadding: CGFloat { OPSStyle.Layout.spacing3 }
    static var rowGap: CGFloat { OPSStyle.Layout.spacing2_5 }
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
        VStack(spacing: DeckMeasurementPickerTokens.rowGap) {
            headerRow
            systemToggle
            wheelRow
            voiceRow
            messageRow
        }
        .padding(.horizontal, DeckMeasurementPickerTokens.panelPadding)
        .padding(.vertical, DeckMeasurementPickerTokens.standardGap)
        .frame(maxWidth: DeckMeasurementPickerTokens.panelMaxWidth)
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

    private var headerRow: some View {
        HStack(spacing: DeckMeasurementPickerTokens.standardGap) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: DeckMeasurementPickerTokens.iconSize, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text)
                    .frame(
                        width: DeckMeasurementPickerTokens.minTouch,
                        height: DeckMeasurementPickerTokens.minTouch
                    )
                    .measurementControlChrome()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text("// \(title.uppercased())")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)

                HStack(spacing: DeckMeasurementPickerTokens.tightGap) {
                    if let leadingSystemImage {
                        Image(systemName: leadingSystemImage)
                            .font(.system(size: DeckMeasurementPickerTokens.smallIconSize, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.opsAccent)
                    }
                    Text(activeValue.formatted())
                        .font(OPSStyle.Typography.dataValueLg)
                        .foregroundColor(OPSStyle.Colors.text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 0)

            Button {
                onCommit(activeValue)
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: DeckMeasurementPickerTokens.iconSize, weight: .semibold))
                    .foregroundColor(canCommit(activeValue) ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                    .frame(
                        width: DeckMeasurementPickerTokens.standardTouch,
                        height: DeckMeasurementPickerTokens.minTouch
                    )
                    .measurementControlChrome(isProminent: canCommit(activeValue))
            }
            .buttonStyle(.plain)
            .disabled(!canCommit(activeValue))
            .accessibilityLabel("Continue")
        }
    }

    private var systemToggle: some View {
        HStack(spacing: DeckMeasurementPickerTokens.tightGap) {
            measurementSystemButton(.imperial, label: "IMPERIAL")
            measurementSystemButton(.metric, label: "METRIC")
        }
        .padding(DeckMeasurementPickerTokens.tightGap)
        .measurementControlChrome()
    }

    private func measurementSystemButton(_ system: MeasurementSystem, label: String) -> some View {
        let isActive = measurementSystem == system
        return Button {
            measurementSystemBinding.wrappedValue = system
        } label: {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                .frame(maxWidth: .infinity)
                .frame(height: DeckMeasurementPickerTokens.minTouch)
                .measurementControlChrome(isActive: isActive)
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
        }
    }

    private var voiceRow: some View {
        HStack(spacing: DeckMeasurementPickerTokens.standardGap) {
            Button {
                toggleDictation()
            } label: {
                HStack(spacing: DeckMeasurementPickerTokens.tightGap) {
                    Image(systemName: voiceInput.isListening ? "mic.fill" : "mic")
                        .font(.system(size: DeckMeasurementPickerTokens.smallIconSize, weight: .semibold))
                    Text(voiceInput.isListening ? "LISTENING" : "DICTATE")
                        .font(OPSStyle.Typography.badgeCake)
                        .lineLimit(1)
                }
                .foregroundColor(voiceInput.isListening ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.text2)
                .frame(height: DeckMeasurementPickerTokens.minTouch)
                .padding(.horizontal, DeckMeasurementPickerTokens.horizontalInset)
                .measurementControlChrome()
            }
            .buttonStyle(.plain)

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
        VStack(spacing: DeckMeasurementPickerTokens.tightGap) {
            RealtimeMeasurementWheel(range: range, value: value)
            .frame(
                width: DeckMeasurementPickerTokens.wheelWidth,
                height: DeckMeasurementPickerTokens.wheelHeight
            )
            .clipped()

            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .padding(.vertical, DeckMeasurementPickerTokens.tightGap)
        .frame(maxWidth: .infinity)
        .measurementControlChrome(cornerRadius: DeckMeasurementPickerTokens.nestedRadius)
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

private struct RealtimeMeasurementWheel: UIViewRepresentable {
    let range: ClosedRange<Int>
    @Binding var value: Int

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.backgroundColor = .clear
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.selectRow(DeckMeasurementWheelData.row(for: value, in: range), inComponent: 0, animated: false)
        context.coordinator.attach(to: picker)
        return picker
    }

    func updateUIView(_ uiView: UIPickerView, context: Context) {
        let previousRange = context.coordinator.range
        context.coordinator.value = $value
        context.coordinator.range = range
        context.coordinator.attach(to: uiView)

        if previousRange != range {
            uiView.reloadAllComponents()
        }

        let targetRow = DeckMeasurementWheelData.row(for: value, in: range)
        if uiView.selectedRow(inComponent: 0) != targetRow {
            uiView.selectRow(targetRow, inComponent: 0, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, range: range)
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var value: Binding<Int>
        var range: ClosedRange<Int>

        private weak var pickerView: UIPickerView?
        private weak var observedScrollView: UIScrollView?
        private var displayLink: CADisplayLink?
        private var baselineRow = 0
        private var baselineOffsetY: CGFloat = 0

        init(value: Binding<Int>, range: ClosedRange<Int>) {
            self.value = value
            self.range = range
        }

        deinit {
            observedScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
            stopTracking()
        }

        func attach(to pickerView: UIPickerView) {
            self.pickerView = pickerView
            guard let scrollView = pickerView.firstDescendant(of: UIScrollView.self) else { return }
            guard observedScrollView !== scrollView else { return }

            observedScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
            observedScrollView = scrollView
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
            calibrate(from: scrollView)
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int {
            1
        }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            DeckMeasurementWheelData.count(in: range)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            Self.rowHeight
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            DeckMeasurementPickerTokens.wheelWidth
        }

        func pickerView(
            _ pickerView: UIPickerView,
            viewForRow row: Int,
            forComponent component: Int,
            reusing view: UIView?
        ) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.textAlignment = .center
            label.backgroundColor = .clear
            label.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
            label.textColor = UIColor(OPSStyle.Colors.text)
            label.text = "\(DeckMeasurementWheelData.value(forRow: row, in: range))"
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            publishSelectedRow(from: pickerView)
            if let scrollView = observedScrollView {
                calibrate(from: scrollView)
            }
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                if let scrollView = observedScrollView {
                    calibrate(from: scrollView)
                }
                startTracking()
                publishEstimatedRow()
            case .changed:
                startTracking()
                publishEstimatedRow()
            case .ended, .cancelled, .failed:
                startTracking()
            default:
                break
            }
        }

        @objc private func tick() {
            publishEstimatedRow()
            guard let scrollView = observedScrollView else {
                stopTracking()
                return
            }
            if !scrollView.isDragging && !scrollView.isDecelerating && !scrollView.isTracking {
                stopTracking()
            }
        }

        private func startTracking() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopTracking() {
            displayLink?.invalidate()
            displayLink = nil
        }

        private static let rowHeight: CGFloat = 36

        private func calibrate(from scrollView: UIScrollView) {
            baselineRow = pickerView?.selectedRow(inComponent: 0) ?? 0
            baselineOffsetY = scrollView.contentOffset.y
        }

        private func publishEstimatedRow() {
            guard let scrollView = observedScrollView else {
                publishSelectedRow(from: pickerView)
                return
            }

            let rowDelta = Int(((scrollView.contentOffset.y - baselineOffsetY) / Self.rowHeight).rounded())
            let estimatedRow = baselineRow + rowDelta
            publish(row: estimatedRow)
        }

        private func publishSelectedRow(from pickerView: UIPickerView?) {
            guard let pickerView else { return }
            publish(row: pickerView.selectedRow(inComponent: 0))
        }

        private func publish(row: Int) {
            let selected = DeckMeasurementWheelData.value(forRow: row, in: range)
            guard value.wrappedValue != selected else { return }
            value.wrappedValue = selected
        }
    }
}

private extension UIView {
    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}

private extension View {
    func measurementControlChrome(
        isProminent: Bool = false,
        isActive: Bool = false,
        cornerRadius: CGFloat = DeckMeasurementPickerTokens.controlRadius
    ) -> some View {
        let isEmphasized = isProminent || isActive
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return background(
            ZStack {
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
