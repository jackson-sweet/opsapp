// OPS/OPS/DeckBuilder/Views/PerimeterDirectionWheelView.swift

import SwiftUI

enum PerimeterDirectionWheelGeometry {
    static let diameter: CGFloat = 268
    static let radius: CGFloat = 92
    static let deadZone: CGFloat = 20

    static func position(for direction: PerimeterDirection, anchor: PerimeterEntryAnchor) -> CGPoint {
        let angle = direction.angleDegrees(incomingAngleDegrees: anchor.incomingAngleDegrees) * .pi / 180
        return CGPoint(
            x: diameter / 2 + CGFloat(cos(angle)) * radius,
            y: diameter / 2 + CGFloat(sin(angle)) * radius
        )
    }

    static func localLocation(from screenLocation: CGPoint, wheelCenter: CGPoint) -> CGPoint {
        CGPoint(
            x: screenLocation.x - wheelCenter.x + diameter / 2,
            y: screenLocation.y - wheelCenter.y + diameter / 2
        )
    }

    static func overlayCenter(anchorScreenPoint: CGPoint, activePressPoint: CGPoint?) -> CGPoint {
        activePressPoint ?? anchorScreenPoint
    }

    static func nearestDirection(to location: CGPoint, anchor: PerimeterEntryAnchor) -> PerimeterDirection? {
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let vector = CGVector(dx: location.x - center.x, dy: location.y - center.y)
        guard hypot(vector.dx, vector.dy) > deadZone else { return nil }

        let angle = PerimeterDirection.normalizedAngle(Double(atan2(vector.dy, vector.dx)) * 180 / Double.pi)
        return anchor.availableDirections.min { left, right in
            angleDistance(angle, left.angleDegrees(incomingAngleDegrees: anchor.incomingAngleDegrees))
                < angleDistance(angle, right.angleDegrees(incomingAngleDegrees: anchor.incomingAngleDegrees))
        }
    }

    private static func angleDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }
}

struct PerimeterDirectionWheelView: View {
    static let diameter: CGFloat = PerimeterDirectionWheelGeometry.diameter

    let anchor: PerimeterEntryAnchor
    let highlightedDirection: PerimeterDirection?
    let onHighlight: (PerimeterDirection?) -> Void
    let onSelect: (PerimeterDirection) -> Void

    private let nodeWidth: CGFloat = 78
    private let nodeHeight: CGFloat = 50

    init(
        anchor: PerimeterEntryAnchor,
        highlightedDirection: PerimeterDirection? = nil,
        onHighlight: @escaping (PerimeterDirection?) -> Void = { _ in },
        onSelect: @escaping (PerimeterDirection) -> Void
    ) {
        self.anchor = anchor
        self.highlightedDirection = highlightedDirection
        self.onHighlight = onHighlight
        self.onSelect = onSelect
    }

    var body: some View {
        ZStack {
            ForEach(anchor.availableDirections) { direction in
                directionButton(direction)
                    .position(PerimeterDirectionWheelGeometry.position(for: direction, anchor: anchor))
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .contentShape(Rectangle())
        .gesture(directionDragGesture)
        .animation(OPSStyle.Animation.hover, value: highlightedDirection)
        .accessibilityElement(children: .contain)
    }

    private func directionButton(_ direction: PerimeterDirection) -> some View {
        let isHighlighted = highlightedDirection == direction

        return Button {
            onSelect(direction)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .rotationEffect(.degrees(direction.angleDegrees(incomingAngleDegrees: anchor.incomingAngleDegrees) + 90))

                Text(direction.wheelLabel)
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .monospacedDigit()
            }
            .foregroundColor(isHighlighted ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
            .frame(width: nodeWidth, height: nodeHeight)
            .background(highlightBackground(isHighlighted: isHighlighted))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction.wheelLabel)
    }

    private var directionDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onHighlight(PerimeterDirectionWheelGeometry.nearestDirection(to: value.location, anchor: anchor))
            }
            .onEnded { value in
                let selected = PerimeterDirectionWheelGeometry.nearestDirection(to: value.location, anchor: anchor)
                    ?? highlightedDirection
                onHighlight(nil)
                if let selected {
                    onSelect(selected)
                }
            }
    }

    @ViewBuilder
    private func highlightBackground(isHighlighted: Bool) -> some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .fill(OPSStyle.Colors.surfaceActive)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                )
        } else {
            Color.clear
        }
    }
}
