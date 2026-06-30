import CoreGraphics
import SceneKit
import SwiftUI
import simd

#if canImport(UIKit)
import UIKit
private typealias OPSOverheadColor = UIColor
private typealias OPSOverheadScalar = Float
#elseif canImport(AppKit)
import AppKit
private typealias OPSOverheadColor = NSColor
private typealias OPSOverheadScalar = CGFloat
#endif

public enum OverheadSceneNodes {
    private static let inchesToMeters: Float = 1.0 / 39.3701
    private static let defaultClearanceMeters: Float = 96.0 * inchesToMeters

    public static func nodes(
        for structure: OverheadStructure,
        scaleFactor: Double,
        center: CGPoint = .zero,
        deckElevationMeters: Float = 0
    ) -> SCNNode {
        let root = SCNNode()
        root.name = DeckSceneLayerToggle.overheadLayerNodeName

        guard scaleFactor > 0 else { return root }

        var geometryCache: [GeometryKey: SCNGeometry] = [:]
        for member in structure.framing {
            guard let node = memberNode(
                member,
                scaleFactor: scaleFactor,
                center: center,
                deckElevationMeters: deckElevationMeters,
                geometryCache: &geometryCache
            ) else { continue }
            root.addChildNode(node)
        }

        return root
    }

    private static func memberNode(
        _ member: FramingMember,
        scaleFactor: Double,
        center: CGPoint,
        deckElevationMeters: Float,
        geometryCache: inout [GeometryKey: SCNGeometry]
    ) -> SCNNode? {
        if member.role == .post {
            return postNode(
                member,
                scaleFactor: scaleFactor,
                center: center,
                deckElevationMeters: deckElevationMeters,
                geometryCache: &geometryCache
            )
        }

        let startPoint = convertPointToMeters(member.start, scaleFactor: scaleFactor, center: center)
        let endPoint = convertPointToMeters(member.end, scaleFactor: scaleFactor, center: center)
        let start = vector3(Float(startPoint.x), deckElevationMeters + defaultClearanceMeters, Float(startPoint.y))
        let end = vector3(Float(endPoint.x), deckElevationMeters + defaultClearanceMeters, Float(endPoint.y))
        let delta = vector3(
            floatValue(end.x) - floatValue(start.x),
            floatValue(end.y) - floatValue(start.y),
            floatValue(end.z) - floatValue(start.z)
        )
        let length = vectorLength(delta)
        guard length > 0 else { return nil }

        let dimensions = LumberActualDimensions(member.nominalSize, plyCount: member.plyCount)
        let key = GeometryKey(
            role: member.role,
            nominalSize: member.nominalSize?.rawValue ?? "6x6",
            plyCount: max(member.plyCount, 1),
            lengthMillimeters: Int((length * 1000).rounded())
        )
        let geometry = geometryCache[key] ?? {
            let box = SCNBox(
                width: CGFloat(dimensions.widthMeters),
                height: CGFloat(dimensions.depthMeters),
                length: CGFloat(length),
                chamferRadius: 0
            )
            box.firstMaterial = material(for: member.role)
            geometryCache[key] = box
            return box
        }()

        let node = SCNNode(geometry: geometry)
        node.name = "overhead.member.\(member.role.rawValue).\(member.id)"
        node.position = vector3(
            (floatValue(start.x) + floatValue(end.x)) / 2,
            (floatValue(start.y) + floatValue(end.y)) / 2,
            (floatValue(start.z) + floatValue(end.z)) / 2
        )
        node.simdOrientation = spanningBoxOrientation(direction: delta)
        return node
    }

    private static func postNode(
        _ member: FramingMember,
        scaleFactor: Double,
        center: CGPoint,
        deckElevationMeters: Float,
        geometryCache: inout [GeometryKey: SCNGeometry]
    ) -> SCNNode? {
        let point = convertPointToMeters(member.start, scaleFactor: scaleFactor, center: center)
        let dimensions = LumberActualDimensions(member.nominalSize, plyCount: member.plyCount)
        let height = defaultClearanceMeters
        let key = GeometryKey(
            role: .post,
            nominalSize: member.nominalSize?.rawValue ?? "6x6",
            plyCount: max(member.plyCount, 1),
            lengthMillimeters: Int((height * 1000).rounded())
        )
        let geometry = geometryCache[key] ?? {
            let box = SCNBox(
                width: CGFloat(dimensions.widthMeters),
                height: CGFloat(height),
                length: CGFloat(dimensions.widthMeters),
                chamferRadius: 0
            )
            box.firstMaterial = material(for: .post)
            geometryCache[key] = box
            return box
        }()

        let node = SCNNode(geometry: geometry)
        node.name = "overhead.member.post.\(member.id)"
        node.position = vector3(
            Float(point.x),
            deckElevationMeters + height / 2,
            Float(point.y)
        )
        return node
    }

    private static func material(for role: FramingRole) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "overhead.\(role.rawValue).material"
        material.lightingModel = .physicallyBased
        switch role {
        case .post, .beam:
            material.diffuse.contents = OPSOverheadColor(OPSStyle.Colors.tan)
        case .joist, .ledger, .rimBand, .blocking, .bridging, .cantilever:
            material.diffuse.contents = OPSOverheadColor(OPSStyle.Colors.text2)
        }
        material.roughness.contents = 0.84
        material.metalness.contents = 0
        return material
    }

    private static func convertPointToMeters(
        _ point: CGPoint,
        scaleFactor: Double,
        center: CGPoint
    ) -> CGPoint {
        let metersPerCanvasPoint = 1.0 / scaleFactor / 39.3701
        return CGPoint(
            x: (Double(point.x) - Double(center.x)) * metersPerCanvasPoint,
            y: (Double(point.y) - Double(center.y)) * metersPerCanvasPoint
        )
    }

    private static func vectorLength(_ vector: SCNVector3) -> Float {
        let dx = floatValue(vector.x)
        let dy = floatValue(vector.y)
        let dz = floatValue(vector.z)
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private static func spanningBoxOrientation(direction: SCNVector3) -> simd_quatf {
        let dx = floatValue(direction.x)
        let dy = floatValue(direction.y)
        let dz = floatValue(direction.z)
        let zAxis = simd_normalize(SIMD3<Float>(dx, dy, dz))
        let horizontalPerpendicular = SIMD3<Float>(dz, 0, -dx)
        let xAxis = simd_length(horizontalPerpendicular) > 1e-6
            ? simd_normalize(horizontalPerpendicular)
            : SIMD3<Float>(1, 0, 0)
        let yAxis = simd_normalize(simd_cross(zAxis, xAxis))
        return simd_quatf(simd_float3x3(columns: (xAxis, yAxis, zAxis)))
    }

    private static func vector3(_ x: Float, _ y: Float, _ z: Float) -> SCNVector3 {
        SCNVector3(OPSOverheadScalar(x), OPSOverheadScalar(y), OPSOverheadScalar(z))
    }

    private static func floatValue(_ value: OPSOverheadScalar) -> Float {
        Float(value)
    }
}

private struct GeometryKey: Hashable {
    var role: FramingRole
    var nominalSize: String
    var plyCount: Int
    var lengthMillimeters: Int
}

private struct LumberActualDimensions {
    let widthMeters: Float
    let depthMeters: Float

    init(_ nominalSize: LumberSize?, plyCount: Int) {
        let inches: (width: Float, depth: Float)
        switch nominalSize {
        case .twoBySix:
            inches = (1.5, 5.5)
        case .twoByEight:
            inches = (1.5, 7.25)
        case .twoByTen:
            inches = (1.5, 9.25)
        case .twoByTwelve:
            inches = (1.5, 11.25)
        case .fourByFour:
            inches = (3.5, 3.5)
        case .fourBySix:
            inches = (3.5, 5.5)
        case .sixBySix, .none:
            inches = (5.5, 5.5)
        }
        self.widthMeters = inches.width * Float(max(plyCount, 1)) / 39.3701
        self.depthMeters = inches.depth / 39.3701
    }
}
