// OPS/OPS/DeckBuilder/Views/DeckFeetInchesWheels.swift

import SwiftUI

/// Compact feet + inches dial pair shared by the height and stair sheets.
/// Wheels instead of a decimal-pad text field: nothing to focus, nothing to
/// mistype, no keyboard shoving the sheet around — and the value is always
/// well-formed, which the free-text fields these replace could not guarantee.
struct DeckFeetInchesWheels: View {
    @Binding var feet: Int
    @Binding var inches: Int
    var feetRange: ClosedRange<Int> = 0...30

    var body: some View {
        HStack(spacing: 0) {
            wheel(label: "FT", range: feetRange, value: $feet)
            wheel(label: "IN", range: 0...11, value: $inches)
        }
        .frame(maxWidth: .infinity)
        .background(OPSStyle.Colors.background)
        .cornerRadius(OPSStyle.Layout.smallCornerRadius)
    }

    private func wheel(label: String, range: ClosedRange<Int>, value: Binding<Int>) -> some View {
        VStack(spacing: 0) {
            Picker(label, selection: value) {
                ForEach(Array(range), id: \.self) { rowValue in
                    Text("\(rowValue)")
                        .font(OPSStyle.Typography.monoValue)
                        .monospacedDigit()
                        .tag(rowValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            // Same dial height as the canvas measurement picker's wheels so
            // every length dial in the builder reads as one control family.
            .frame(height: DeckMeasurementPickerTokens.wheelHeight - 20)
            .compositingGroup()
            .clipped()

            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing1)
    }
}

extension DeckFeetInchesWheels {
    /// Splits decimal feet into whole feet + rounded inches for the dials.
    static func components(fromFeet value: Double, maxFeet: Int = 30) -> (feet: Int, inches: Int) {
        let clamped = max(0, value)
        let totalInches = Int((clamped * 12.0).rounded())
        let feet = min(maxFeet, totalInches / 12)
        return (feet: feet, inches: feet == maxFeet && totalInches / 12 > maxFeet ? 0 : totalInches % 12)
    }

    static func feetValue(feet: Int, inches: Int) -> Double {
        Double(feet) + Double(inches) / 12.0
    }
}
