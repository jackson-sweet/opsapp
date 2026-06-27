// OPS/OPS/DeckBuilder/Views/PerimeterDirectionWheelView.swift

import SwiftUI

struct PerimeterDirectionWheelView: View {
    static let diameter: CGFloat = 224

    let anchor: PerimeterEntryAnchor
    let onSelect: (PerimeterDirection) -> Void

    @State private var highlightedDirection: PerimeterDirection?

    private let buttonDiameter: CGFloat = 50
    private let centerDiameter: CGFloat = 58
    private let radius: CGFloat = 82

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(OPSStyle.Colors.glassDenseApprox)
                )
                .overlay(
                    Circle()
                        .strokeBorder(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )

            ForEach(anchor.availableDirections) { direction in
                directionButton(direction)
                    .position(position(for: direction))
            }

            centerHub
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .contentShape(Circle())
        .gesture(directionDragGesture)
        .animation(OPSStyle.Animation.hover, value: highlightedDirection)
        .accessibilityElement(children: .contain)
    }

    private var centerHub: some View {
        VStack(spacing: 2) {
            Text("//")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.textMute)
            Text(anchor.usesRelativeDirections ? "TURN" : "DIR")
                .font(OPSStyle.Typography.badgeCake)
                .foregroundColor(OPSStyle.Colors.text)
        }
        .frame(width: centerDiameter, height: centerDiameter)
        .background(OPSStyle.Colors.surfaceActive)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func directionButton(_ direction: PerimeterDirection) -> some View {
        let isHighlighted = highlightedDirection == direction

        return Button {
            onSelect(direction)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: direction.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(compactLabel(for: direction))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .monospacedDigit()
            }
            .foregroundColor(isHighlighted ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
            .frame(width: buttonDiameter, height: buttonDiameter)
            .background(isHighlighted ? OPSStyle.Colors.opsAccent.opacity(0.28) : OPSStyle.Colors.surfaceInput)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(
                        isHighlighted ? OPSStyle.Colors.opsAccent.opacity(0.85) : OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction.label)
    }

    private var directionDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                highlightedDirection = nearestDirection(to: value.location)
            }
            .onEnded { value in
                let selected = highlightedDirection ?? nearestDirection(to: value.location)
                highlightedDirection = nil
                if let selected {
                    onSelect(selected)
                }
            }
    }

    private func position(for direction: PerimeterDirection) -> CGPoint {
        let angle = direction.angleDegrees(incomingAngleDegrees: anchor.incomingAngleDegrees) * .pi / 180
        return CGPoint(
            x: Self.diameter / 2 + CGFloat(cos(angle)) * radius,
            y: Self.diameter / 2 + CGFloat(sin(angle)) * radius
        )
    }

    private func nearestDirection(to location: CGPoint) -> PerimeterDirection? {
        let center = CGPoint(x: Self.diameter / 2, y: Self.diameter / 2)
        let vector = CGVector(dx: location.x - center.x, dy: location.y - center.y)
        guard hypot(vector.dx, vector.dy) > 12 else { return nil }

        let angle = PerimeterDirection.normalizedAngle(Double(atan2(vector.dy, vector.dx)) * 180 / Double.pi)
        return anchor.availableDirections.min { left, right in
            angleDistance(angle, left.angleDegrees(incomingAngleDegrees: anchor.incomingAngleDegrees))
                < angleDistance(angle, right.angleDegrees(incomingAngleDegrees: anchor.incomingAngleDegrees))
        }
    }

    private func angleDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }

    private func compactLabel(for direction: PerimeterDirection) -> String {
        switch direction {
        case .up:
            return "UP"
        case .right:
            return "RIGHT"
        case .down:
            return "DOWN"
        case .left:
            return "LEFT"
        case .upRight45:
            return "UR45"
        case .downRight45:
            return "DR45"
        case .downLeft45:
            return "DL45"
        case .upLeft45:
            return "UL45"
        case .straight:
            return "STR"
        case .left90:
            return "L90"
        case .right90:
            return "R90"
        case .back:
            return "BACK"
        case .left45:
            return "L45"
        case .right45:
            return "R45"
        }
    }
}
