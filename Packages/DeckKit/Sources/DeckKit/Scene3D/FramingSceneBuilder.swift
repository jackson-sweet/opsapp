import CoreGraphics
import SceneKit
import SwiftUI
import simd

#if canImport(UIKit)
import UIKit
private typealias OPSSceneColor = UIColor
private typealias OPSSceneScalar = Float
#elseif canImport(AppKit)
import AppKit
private typealias OPSSceneColor = NSColor
private typealias OPSSceneScalar = CGFloat
#endif

public enum FramingSceneBuilder {
    private static let inchesToMeters: Float = 1.0 / 39.3701

    public static func buildFramingNode(
        framing: FramingPlan,
        levelId: String,
        scaleFactor: Double,
        center: CGPoint,
        deckElevationMeters: Float,
        postBottomMeters: Float = 0
    ) -> SCNNode {
        let root = SCNNode()
        root.name = "framingRoot"

        let layers = makeLayerNodes()
        for layer in FramingLayer.addressableLayers where layer != .decking {
            root.addChildNode(layers[layer, default: SCNNode()])
        }

        guard scaleFactor > 0,
              let memberSet = framing.members.first(where: { $0.levelId == levelId }) else {
            return root
        }

        let supportTop = supportTopMeters(
            for: memberSet.members,
            deckElevationMeters: deckElevationMeters,
            postBottomMeters: postBottomMeters
        )

        for member in memberSet.members {
            switch member.role {
            case .post:
                let postNodes = buildPostAndFooting(
                    member: member,
                    scaleFactor: scaleFactor,
                    center: center,
                    postBottomMeters: postBottomMeters,
                    postTopMeters: supportTop
                )
                layers[.posts]?.addChildNode(postNodes.post)
                layers[.footings]?.addChildNode(postNodes.footing)
            case .beam, .joist, .ledger, .rimBand, .blocking, .bridging, .cantilever:
                guard let node = buildLinearMember(
                    member: member,
                    allMembers: memberSet.members,
                    scaleFactor: scaleFactor,
                    center: center,
                    deckElevationMeters: deckElevationMeters
                ) else { continue }
                layers[layer(for: member.role)]?.addChildNode(node)
            }
        }

        return root
    }

    private static func makeLayerNodes() -> [FramingLayer: SCNNode] {
        Dictionary(uniqueKeysWithValues: FramingLayer.addressableLayers.map { layer in
            let node = SCNNode()
            node.name = layer.layerNodeName
            return (layer, node)
        })
    }

    private static func buildLinearMember(
        member: FramingMember,
        allMembers: [FramingMember],
        scaleFactor: Double,
        center: CGPoint,
        deckElevationMeters: Float
    ) -> SCNNode? {
        let start2D = convertPointToMeters(member.start, scaleFactor: scaleFactor, center: center)
        let end2D = convertPointToMeters(member.end, scaleFactor: scaleFactor, center: center)
        let start = (x: Float(start2D.x), z: Float(start2D.y))
        let end = (x: Float(end2D.x), z: Float(end2D.y))
        let dimensions = LumberActualDimensions(member.nominalSize, plyCount: member.plyCount)
        let joistDepth = maxDepthMeters(
            in: allMembers,
            roles: [.joist, .rimBand, .ledger, .blocking, .bridging, .cantilever],
            fallback: .twoByEight
        )

        let yCenter: Float
        switch member.role {
        case .beam:
            yCenter = deckElevationMeters - joistDepth - dimensions.depthMeters / 2
        case .joist, .ledger, .rimBand, .blocking, .bridging, .cantilever:
            yCenter = deckElevationMeters - dimensions.depthMeters / 2
        case .post:
            return nil
        }

        let node = buildSpanningBox(
            from: vector3(start.x, yCenter, start.z),
            to: vector3(end.x, yCenter, end.z),
            width: dimensions.widthMeters,
            height: dimensions.depthMeters,
            material: material(for: member.role)
        )
        node.name = "framing.\(member.role.rawValue).\(member.id)"
        return node
    }

    private static func buildPostAndFooting(
        member: FramingMember,
        scaleFactor: Double,
        center: CGPoint,
        postBottomMeters: Float,
        postTopMeters: Float
    ) -> (post: SCNNode, footing: SCNNode) {
        let point2D = convertPointToMeters(member.start, scaleFactor: scaleFactor, center: center)
        let dimensions = LumberActualDimensions(member.nominalSize, plyCount: member.plyCount)
        let postHeight = max(postTopMeters - postBottomMeters, 0.15)

        let postBox = SCNBox(
            width: CGFloat(dimensions.widthMeters),
            height: CGFloat(postHeight),
            length: CGFloat(dimensions.widthMeters),
            chamferRadius: 0
        )
        postBox.firstMaterial = material(for: .post)
        let post = SCNNode(geometry: postBox)
        post.name = "framing.post.\(member.id)"
        post.position = vector3(
            Float(point2D.x),
            postBottomMeters + postHeight / 2,
            Float(point2D.y)
        )

        let footing = SCNNode(geometry: SCNBox(
            width: CGFloat(11.0 * inchesToMeters),
            height: CGFloat(5.0 * inchesToMeters),
            length: CGFloat(11.0 * inchesToMeters),
            chamferRadius: 0
        ))
        footing.geometry?.firstMaterial = material(for: .footing)
        footing.name = "framing.footing.\(member.id)"
        footing.position = vector3(
            Float(point2D.x),
            postBottomMeters + 2.5 * inchesToMeters,
            Float(point2D.y)
        )

        return (post, footing)
    }

    private static func supportTopMeters(
        for members: [FramingMember],
        deckElevationMeters: Float,
        postBottomMeters: Float
    ) -> Float {
        let joistDepth = maxDepthMeters(
            in: members,
            roles: [.joist, .rimBand, .ledger, .blocking, .bridging, .cantilever],
            fallback: .twoByEight
        )
        let beamDepth = maxDepthMeters(in: members, roles: [.beam], fallback: .twoByTen)
        return max(deckElevationMeters - joistDepth - beamDepth, postBottomMeters + 0.15)
    }

    private static func maxDepthMeters(
        in members: [FramingMember],
        roles: Set<FramingRole>,
        fallback: LumberSize
    ) -> Float {
        let sizes = members
            .filter { roles.contains($0.role) }
            .compactMap(\.nominalSize)
        return sizes
            .map { LumberActualDimensions($0, plyCount: 1).depthMeters }
            .max() ?? LumberActualDimensions(fallback, plyCount: 1).depthMeters
    }

    private static func layer(for role: FramingRole) -> FramingLayer {
        switch role {
        case .joist, .cantilever:
            return .joists
        case .beam:
            return .beams
        case .post:
            return .posts
        case .ledger, .rimBand:
            return .rim
        case .blocking, .bridging:
            return .blocking
        }
    }

    private static func material(for role: FramingRole) -> SCNMaterial {
        switch role {
        case .beam:
            return material(color: OPSStyle.Colors.tan)
        case .post:
            return material(color: OPSStyle.Colors.tan)
        case .joist, .ledger, .rimBand, .blocking, .bridging, .cantilever:
            return material(color: OPSStyle.Colors.text2)
        }
    }

    private static func material(for footing: FramingFootingMaterial) -> SCNMaterial {
        switch footing {
        case .footing:
            return material(color: OPSStyle.Colors.text3)
        }
    }

    private static func material(color: Color) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = OPSSceneColor(color)
        material.roughness.contents = 0.85
        material.isDoubleSided = false
        return material
    }

    private static func convertPointToMeters(
        _ point: CGPoint,
        scaleFactor: Double,
        center: CGPoint
    ) -> CGPoint {
        let metersPerCanvasPoint = 1.0 / scaleFactor / Double(39.3701)
        return CGPoint(
            x: (Double(point.x) - Double(center.x)) * metersPerCanvasPoint,
            y: (Double(point.y) - Double(center.y)) * metersPerCanvasPoint
        )
    }

    private static func buildSpanningBox(
        from p1: SCNVector3,
        to p2: SCNVector3,
        width: Float,
        height: Float,
        material: SCNMaterial
    ) -> SCNNode {
        let delta = vector3(
            floatValue(p2.x) - floatValue(p1.x),
            floatValue(p2.y) - floatValue(p1.y),
            floatValue(p2.z) - floatValue(p1.z)
        )
        let deltaX = floatValue(delta.x)
        let deltaY = floatValue(delta.y)
        let deltaZ = floatValue(delta.z)
        let length = sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)

        let box = SCNBox(
            width: CGFloat(width),
            height: CGFloat(height),
            length: CGFloat(length),
            chamferRadius: 0
        )
        box.firstMaterial = material

        let node = SCNNode(geometry: box)
        node.position = vector3(
            (floatValue(p1.x) + floatValue(p2.x)) / 2,
            (floatValue(p1.y) + floatValue(p2.y)) / 2,
            (floatValue(p1.z) + floatValue(p2.z)) / 2
        )
        node.simdOrientation = spanningBoxOrientation(direction: delta)
        return node
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
        SCNVector3(OPSSceneScalar(x), OPSSceneScalar(y), OPSSceneScalar(z))
    }

    private static func floatValue(_ value: OPSSceneScalar) -> Float {
        Float(value)
    }
}

private enum FramingFootingMaterial {
    case footing
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
