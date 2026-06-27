// OPS/OPS/DeckBuilder/Models/PerimeterEntryState.swift

import CoreGraphics
import Foundation

enum PerimeterDirection: String, CaseIterable, Identifiable, Equatable {
    case up
    case right
    case down
    case left
    case upRight45
    case downRight45
    case downLeft45
    case upLeft45
    case straight
    case left90
    case right90
    case back
    case left45
    case right45
    case left135
    case right135

    var id: String { rawValue }

    static let absoluteDirections: [PerimeterDirection] = [
        .up, .upRight45, .right, .downRight45, .down, .downLeft45, .left, .upLeft45
    ]

    static let relativeDirections: [PerimeterDirection] = [
        .straight, .right45, .right90, .right135, .back, .left135, .left90, .left45
    ]

    var label: String {
        wheelLabel
    }

    var wheelLabel: String {
        switch self {
        case .up: return "NORTH"
        case .right: return "EAST"
        case .down: return "SOUTH"
        case .left: return "WEST"
        case .upRight45: return "NORTHEAST"
        case .downRight45: return "SOUTHEAST"
        case .downLeft45: return "SOUTHWEST"
        case .upLeft45: return "NORTHWEST"
        case .straight: return "0°"
        case .left45: return "-45°"
        case .left90: return "-90°"
        case .left135: return "-135°"
        case .back: return "180°"
        case .right135: return "+135°"
        case .right90: return "+90°"
        case .right45: return "+45°"
        }
    }

    var systemImage: String {
        switch self {
        case .up: return "arrow.up"
        case .right: return "arrow.right"
        case .down: return "arrow.down"
        case .left: return "arrow.left"
        case .upRight45: return "arrow.up.right"
        case .downRight45: return "arrow.down.right"
        case .downLeft45: return "arrow.down.left"
        case .upLeft45: return "arrow.up.left"
        case .straight: return "arrow.up"
        case .left90: return "arrow.turn.up.left"
        case .right90: return "arrow.turn.up.right"
        case .back: return "arrow.uturn.backward"
        case .left45: return "arrow.up.left"
        case .right45: return "arrow.up.right"
        case .left135: return "arrow.down.left"
        case .right135: return "arrow.down.right"
        }
    }

    func angleDegrees(incomingAngleDegrees: Double?) -> Double {
        let angle: Double
        switch self {
        case .right:
            angle = 0
        case .downRight45:
            angle = 45
        case .down:
            angle = 90
        case .downLeft45:
            angle = 135
        case .left:
            angle = 180
        case .upLeft45:
            angle = 225
        case .up:
            angle = 270
        case .upRight45:
            angle = 315
        case .straight:
            angle = incomingAngleDegrees ?? 0
        case .right45:
            angle = (incomingAngleDegrees ?? 0) + 45
        case .right90:
            angle = (incomingAngleDegrees ?? 0) + 90
        case .right135:
            angle = (incomingAngleDegrees ?? 0) + 135
        case .back:
            angle = (incomingAngleDegrees ?? 0) + 180
        case .left135:
            angle = (incomingAngleDegrees ?? 0) - 135
        case .left90:
            angle = (incomingAngleDegrees ?? 0) - 90
        case .left45:
            angle = (incomingAngleDegrees ?? 0) - 45
        }
        return Self.normalizedAngle(angle)
    }

    static func normalizedAngle(_ angle: Double) -> Double {
        let wrapped = angle.truncatingRemainder(dividingBy: 360)
        return wrapped >= 0 ? wrapped : wrapped + 360
    }
}

enum PerimeterEntryGeometry {
    static func endpoint(
        from start: CGPoint,
        direction: PerimeterDirection,
        lengthInches: Double,
        scaleFactor: Double?,
        incomingAngleDegrees: Double?,
        fallbackScale: Double
    ) -> CGPoint {
        let scale: Double
        if let scaleFactor, scaleFactor > 0 {
            scale = scaleFactor
        } else {
            scale = fallbackScale
        }
        let lengthPoints = lengthInches * scale
        let radians = direction.angleDegrees(incomingAngleDegrees: incomingAngleDegrees) * .pi / 180
        return CGPoint(
            x: start.x + cos(radians) * lengthPoints,
            y: start.y + sin(radians) * lengthPoints
        )
    }
}

struct PerimeterEntryAnchor: Equatable {
    let vertexId: String
    let position: CGPoint
    let incomingAngleDegrees: Double?
    let rootVertexId: String

    var usesRelativeDirections: Bool { incomingAngleDegrees != nil }

    var availableDirections: [PerimeterDirection] {
        usesRelativeDirections ? PerimeterDirection.relativeDirections : PerimeterDirection.absoluteDirections
    }
}

struct PerimeterEntryCommit: Equatable {
    let edgeId: String
    let startVertexId: String
    let endVertexId: String
    let createdEndVertex: Bool
    let previousAnchor: PerimeterEntryAnchor
}

struct PerimeterDraftPreview: Equatable {
    let anchor: PerimeterEntryAnchor
    let direction: PerimeterDirection
    let start: CGPoint
    let end: CGPoint
    let dimensionInches: Double
}

enum PerimeterEntryMode: Equatable {
    case idle
    case choosingDirection(anchor: PerimeterEntryAnchor)
    case enteringLength(anchor: PerimeterEntryAnchor, direction: PerimeterDirection, draft: PerimeterLengthDraft)

    var activeAnchor: PerimeterEntryAnchor? {
        switch self {
        case .idle:
            return nil
        case .choosingDirection(let anchor):
            return anchor
        case .enteringLength(let anchor, _, _):
            return anchor
        }
    }

    var selectedDirection: PerimeterDirection? {
        guard case .enteringLength(_, let direction, _) = self else { return nil }
        return direction
    }

    var lengthDraft: PerimeterLengthDraft? {
        guard case .enteringLength(_, _, let draft) = self else { return nil }
        return draft
    }
}
