// OPS/OPS/DeckBuilder/Models/DeckMeasurementValue.swift

import Foundation

struct DeckMeasurementValue: Equatable {
    var measurementSystem: MeasurementSystem
    var totalInches: Double

    init(measurementSystem: MeasurementSystem, totalInches: Double) {
        self.measurementSystem = measurementSystem
        self.totalInches = max(0, totalInches)
    }

    static func zero(system: MeasurementSystem) -> DeckMeasurementValue {
        DeckMeasurementValue(measurementSystem: system, totalInches: 0)
    }

    static func imperial(feet: Int, inches: Int, sixteenths: Int) -> DeckMeasurementValue {
        let total = Double(max(0, feet) * 12 + max(0, inches)) + Double(max(0, sixteenths)) / 16.0
        return DeckMeasurementValue(measurementSystem: .imperial, totalInches: total)
    }

    static func metric(meters: Int, centimeters: Int, millimeters: Int) -> DeckMeasurementValue {
        let totalMillimeters = max(0, meters) * 1000 + max(0, centimeters) * 10 + max(0, millimeters)
        return DeckMeasurementValue(
            measurementSystem: .metric,
            totalInches: Double(totalMillimeters) / 25.4
        )
    }

    var imperialComponents: (feet: Int, inches: Int, sixteenths: Int) {
        let totalSixteenths = Int((totalInches * 16).rounded())
        let feet = totalSixteenths / (12 * 16)
        let remaining = totalSixteenths - feet * 12 * 16
        let inches = remaining / 16
        let sixteenths = remaining % 16
        return (feet, inches, sixteenths)
    }

    var metricComponents: (meters: Int, centimeters: Int, millimeters: Int) {
        let totalMillimeters = Int((totalInches * 25.4).rounded())
        let meters = totalMillimeters / 1000
        let remaining = totalMillimeters - meters * 1000
        let centimeters = remaining / 10
        let millimeters = remaining % 10
        return (meters, centimeters, millimeters)
    }

    func converted(to system: MeasurementSystem) -> DeckMeasurementValue {
        DeckMeasurementValue(measurementSystem: system, totalInches: totalInches)
    }

    func formatted() -> String {
        DimensionEngine.format(totalInches, system: measurementSystem)
    }
}

typealias PerimeterLengthDraft = DeckMeasurementValue
