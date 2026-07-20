import CoreGraphics
import SceneKit
import SwiftUI
import UIKit
import simd

/// SceneKit projection of the shared framing contract. This type renders only;
/// generation, sizing, and persistence remain outside the embedded OPS client.
enum FramingSceneBuilder {
    private static let inchesToMeters: Float = 1.0 / 39.3701
    private static let bearingTolerance: Double = 0.001
    private static let minimumRenderableLength: Float = 0.000_001
    private static let minimumSupportClearance: Float = 0.000_001

    static func buildFramingNode(
        framing: FramingPlan,
        levelId: String,
        scaleFactor: Double,
        center: CGPoint,
        deckElevationMeters: Float,
        vertices: [DeckVertex]
    ) -> SCNNode {
        let root = SCNNode()
        root.name = "framingRoot"

        let layers = Dictionary(uniqueKeysWithValues: FramingSceneLayer.allCases.map { layer in
            let node = SCNNode()
            node.name = layer.nodeName
            root.addChildNode(node)
            return (layer, node)
        })

        guard scaleFactor.isFinite,
              scaleFactor > 0,
              isFinite(center),
              deckElevationMeters.isFinite,
              let memberSet = framing.members.first(where: { $0.levelId == levelId }) else {
            return root
        }

        for member in memberSet.members {
            if member.role == .post {
                guard let beamBottom = supportBeamBottom(
                    for: member,
                    allMembers: memberSet.members,
                    deckElevationMeters: deckElevationMeters
                ),
                let footing = buildFooting(
                    for: member,
                    scaleFactor: scaleFactor,
                    center: center,
                    vertices: vertices
                ),
                beamBottom > footing.topMeters + minimumSupportClearance,
                let post = buildPost(
                    member,
                    scaleFactor: scaleFactor,
                    center: center,
                    bottomMeters: footing.topMeters,
                    topMeters: beamBottom
                ) else { continue }

                layers[.footings]?.addChildNode(footing.node)
                layers[.posts]?.addChildNode(post)
                continue
            }

            guard let node = buildLinearMember(
                member,
                allMembers: memberSet.members,
                scaleFactor: scaleFactor,
                center: center,
                deckElevationMeters: deckElevationMeters
            ) else { continue }
            layers[FramingSceneLayer.layer(for: member.role)]?.addChildNode(node)
        }

        return root
    }

    private static func buildLinearMember(
        _ member: FramingMember,
        allMembers: [FramingMember],
        scaleFactor: Double,
        center: CGPoint,
        deckElevationMeters: Float
    ) -> SCNNode? {
        guard let start = convertPoint(member.start, scaleFactor: scaleFactor, center: center),
              let end = convertPoint(member.end, scaleFactor: scaleFactor, center: center) else {
            return nil
        }
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length.isFinite, length > minimumRenderableLength else { return nil }

        let dimensions = LumberActualDimensions(
            member.nominalSize ?? fallbackSize(for: member.role),
            plyCount: member.plyCount
        )
        guard dimensions.isRenderable else { return nil }
        let yCenter: Float
        switch member.role {
        case .beam:
            guard let beamBottom = beamBottom(
                for: member,
                allMembers: allMembers,
                deckElevationMeters: deckElevationMeters
            ) else { return nil }
            yCenter = beamBottom + dimensions.depthMeters / 2
        case .joist, .ledger, .rimBand, .blocking, .bridging, .cantilever:
            yCenter = deckElevationMeters - dimensions.depthMeters / 2
        case .post:
            return nil
        }
        guard yCenter.isFinite else { return nil }

        guard let node = spanningBox(
            from: SCNVector3(start.x, yCenter, start.y),
            to: SCNVector3(end.x, yCenter, end.y),
            width: dimensions.widthMeters,
            height: dimensions.depthMeters,
            material: material(for: member.role)
        ) else { return nil }
        node.name = "framing.\(member.role.rawValue).\(member.id)"
        return node
    }

    private static func buildPost(
        _ member: FramingMember,
        scaleFactor: Double,
        center: CGPoint,
        bottomMeters: Float,
        topMeters: Float
    ) -> SCNNode? {
        guard let point = convertPoint(member.start, scaleFactor: scaleFactor, center: center),
              bottomMeters.isFinite,
              topMeters.isFinite,
              topMeters > bottomMeters + minimumSupportClearance else {
            return nil
        }
        let dimensions = LumberActualDimensions(
            member.nominalSize ?? .sixBySix,
            plyCount: 1
        )
        guard dimensions.isRenderable else { return nil }
        let height = topMeters - bottomMeters
        let box = SCNBox(
            width: CGFloat(dimensions.widthMeters),
            height: CGFloat(height),
            length: CGFloat(dimensions.depthMeters),
            chamferRadius: 0
        )
        box.firstMaterial = material(for: .post)
        let node = SCNNode(geometry: box)
        node.name = "framing.post.\(member.id)"
        node.position = SCNVector3(point.x, bottomMeters + height / 2, point.y)
        return node
    }

    private struct FootingBuildResult {
        let node: SCNNode
        let topMeters: Float
    }

    private static func buildFooting(
        for post: FramingMember,
        scaleFactor: Double,
        center: CGPoint,
        vertices: [DeckVertex]
    ) -> FootingBuildResult? {
        guard let point = convertPoint(post.start, scaleFactor: scaleFactor, center: center) else {
            return nil
        }
        let footingType = exactFootingType(at: post.start, vertices: vertices)
        let typeName = footingType?.rawValue ?? "schematic"

        let root = SCNNode()
        root.name = "framing.footing.\(post.id)"
        root.position = SCNVector3(point.x, 0, point.y)

        let shape: SCNNode
        let topMeters: Float
        switch footingType {
        case .helicalPile:
            let shaftHeight = 18.0 * inchesToMeters
            let shaft = SCNCylinder(
                radius: CGFloat(1.75 * inchesToMeters),
                height: CGFloat(shaftHeight)
            )
            shaft.firstMaterial = footingMaterial()
            shape = SCNNode(geometry: shaft)
            shape.position.y = -7.0 * inchesToMeters

            let plate = SCNCylinder(
                radius: CGFloat(5.0 * inchesToMeters),
                height: CGFloat(0.75 * inchesToMeters)
            )
            plate.firstMaterial = footingMaterial()
            let plateNode = SCNNode(geometry: plate)
            plateNode.name = "footingShape.helicalPlate"
            plateNode.position.y = -5.0 * inchesToMeters
            shape.addChildNode(plateNode)
            topMeters = 2.0 * inchesToMeters

        case .sonoTube:
            let height = 12.0 * inchesToMeters
            let cylinder = SCNCylinder(
                radius: CGFloat(6.0 * inchesToMeters),
                height: CGFloat(height)
            )
            cylinder.firstMaterial = footingMaterial()
            shape = SCNNode(geometry: cylinder)
            topMeters = height / 2

        case .concretePad, .none:
            let height = 5.0 * inchesToMeters
            let box = SCNBox(
                width: CGFloat(11.0 * inchesToMeters),
                height: CGFloat(height),
                length: CGFloat(11.0 * inchesToMeters),
                chamferRadius: 0
            )
            box.firstMaterial = footingMaterial()
            shape = SCNNode(geometry: box)
            shape.position.y = height / 2
            topMeters = height
        }
        shape.name = "footingShape.\(typeName)"
        root.addChildNode(shape)
        return FootingBuildResult(node: root, topMeters: topMeters)
    }

    private static func exactFootingType(
        at point: CGPoint,
        vertices: [DeckVertex]
    ) -> FootingType? {
        vertices.first(where: { $0.position == point })?.footingType
    }

    private static func supportBeamBottom(
        for post: FramingMember,
        allMembers: [FramingMember],
        deckElevationMeters: Float
    ) -> Float? {
        guard isFinite(post.start), isFinite(post.end) else { return nil }
        let bearingBeams = allMembers.filter { member in
            member.role == .beam && point(post.start, liesOn: member)
        }
        guard !bearingBeams.isEmpty else { return nil }

        return bearingBeams.compactMap {
            beamBottom(
                for: $0,
                allMembers: allMembers,
                deckElevationMeters: deckElevationMeters
            )
        }.min()
    }

    private static func beamBottom(
        for beam: FramingMember,
        allMembers: [FramingMember],
        deckElevationMeters: Float
    ) -> Float? {
        guard beam.role == .beam,
              isFinite(beam.start),
              isFinite(beam.end),
              segmentLength(of: beam) > bearingTolerance,
              deckElevationMeters.isFinite else { return nil }

        let dimensions = LumberActualDimensions(
            beam.nominalSize ?? .twoByTen,
            plyCount: beam.plyCount
        )
        guard dimensions.isRenderable else { return nil }

        let bearingDepth = allMembers
            .filter {
                ($0.role == .joist || $0.role == .cantilever) && segmentsBear($0, beam)
            }
            .map {
                LumberActualDimensions($0.nominalSize ?? .twoByEight, plyCount: 1).depthMeters
            }
            .filter(\.isFinite)
            .max() ?? LumberActualDimensions(.twoByEight, plyCount: 1).depthMeters
        let result = deckElevationMeters - bearingDepth - dimensions.depthMeters
        return result.isFinite ? result : nil
    }

    private static func fallbackSize(for role: FramingRole) -> LumberSize {
        switch role {
        case .beam: return .twoByTen
        case .post: return .sixBySix
        case .joist, .ledger, .rimBand, .blocking, .bridging, .cantilever: return .twoByEight
        }
    }

    private static func convertPoint(
        _ point: CGPoint,
        scaleFactor: Double,
        center: CGPoint
    ) -> (x: Float, y: Float)? {
        guard scaleFactor.isFinite,
              scaleFactor > 0,
              isFinite(point),
              isFinite(center) else { return nil }
        let metersPerPoint = 1.0 / scaleFactor / 39.3701
        let x = Float((Double(point.x) - Double(center.x)) * metersPerPoint)
        let y = Float((Double(point.y) - Double(center.y)) * metersPerPoint)
        return x.isFinite && y.isFinite ? (x, y) : nil
    }

    private static func spanningBox(
        from start: SCNVector3,
        to end: SCNVector3,
        width: Float,
        height: Float,
        material: SCNMaterial
    ) -> SCNNode? {
        guard isFinite(start),
              isFinite(end),
              width.isFinite,
              width > 0,
              height.isFinite,
              height > 0 else { return nil }
        let direction = SIMD3<Float>(end.x - start.x, end.y - start.y, end.z - start.z)
        let length = simd_length(direction)
        guard length.isFinite, length > minimumRenderableLength else { return nil }
        let box = SCNBox(
            width: CGFloat(width),
            height: CGFloat(height),
            length: CGFloat(length),
            chamferRadius: 0
        )
        box.firstMaterial = material

        let node = SCNNode(geometry: box)
        node.position = SCNVector3(
            (start.x + end.x) / 2,
            (start.y + end.y) / 2,
            (start.z + end.z) / 2
        )
        node.simdOrientation = spanningOrientation(direction: direction)
        return node
    }

    private static func point(_ point: CGPoint, liesOn member: FramingMember) -> Bool {
        guard isFinite(point),
              isFinite(member.start),
              isFinite(member.end),
              segmentLength(of: member) > bearingTolerance else { return false }
        let result = PolygonMath.closestPointOnSegment(
            point: point,
            segStart: member.start,
            segEnd: member.end
        )
        return result.distance.isFinite && result.distance <= bearingTolerance
    }

    private static func segmentsBear(_ first: FramingMember, _ second: FramingMember) -> Bool {
        guard isFinite(first.start),
              isFinite(first.end),
              isFinite(second.start),
              isFinite(second.end) else { return false }

        let p = first.start
        let q = second.start
        let r = CGPoint(x: first.end.x - p.x, y: first.end.y - p.y)
        let s = CGPoint(x: second.end.x - q.x, y: second.end.y - q.y)
        let rLength = hypot(Double(r.x), Double(r.y))
        let sLength = hypot(Double(s.x), Double(s.y))
        guard rLength.isFinite,
              sLength.isFinite,
              rLength > bearingTolerance,
              sLength > bearingTolerance else { return false }

        let denominator = cross(r, s)
        let qMinusP = CGPoint(x: q.x - p.x, y: q.y - p.y)
        if abs(denominator) > Double.ulpOfOne {
            let t = cross(qMinusP, s) / denominator
            let u = cross(qMinusP, r) / denominator
            let tTolerance = bearingTolerance / rLength
            let uTolerance = bearingTolerance / sLength
            if t >= -tTolerance,
               t <= 1 + tTolerance,
               u >= -uTolerance,
               u <= 1 + uTolerance {
                return true
            }
        }

        let endpointDistances = [
            PolygonMath.closestPointOnSegment(point: first.start, segStart: second.start, segEnd: second.end).distance,
            PolygonMath.closestPointOnSegment(point: first.end, segStart: second.start, segEnd: second.end).distance,
            PolygonMath.closestPointOnSegment(point: second.start, segStart: first.start, segEnd: first.end).distance,
            PolygonMath.closestPointOnSegment(point: second.end, segStart: first.start, segEnd: first.end).distance,
        ]
        return endpointDistances.contains { $0.isFinite && $0 <= bearingTolerance }
    }

    private static func cross(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        Double(lhs.x) * Double(rhs.y) - Double(lhs.y) * Double(rhs.x)
    }

    private static func segmentLength(of member: FramingMember) -> Double {
        hypot(
            Double(member.end.x) - Double(member.start.x),
            Double(member.end.y) - Double(member.start.y)
        )
    }

    private static func isFinite(_ point: CGPoint) -> Bool {
        Double(point.x).isFinite && Double(point.y).isFinite
    }

    private static func isFinite(_ vector: SCNVector3) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    private static func spanningOrientation(direction: SIMD3<Float>) -> simd_quatf {
        let zAxis = simd_normalize(direction)
        let horizontalPerpendicular = SIMD3<Float>(direction.z, 0, -direction.x)
        let xAxis = simd_length(horizontalPerpendicular) > 1e-6
            ? simd_normalize(horizontalPerpendicular)
            : SIMD3<Float>(1, 0, 0)
        let yAxis = simd_normalize(simd_cross(zAxis, xAxis))
        return simd_quatf(simd_float3x3(columns: (xAxis, yAxis, zAxis)))
    }

    private static func material(for role: FramingRole) -> SCNMaterial {
        switch role {
        case .beam, .post:
            return material(color: OPSStyle.Colors.text3)
        case .joist, .ledger, .rimBand, .blocking, .bridging, .cantilever:
            return material(color: OPSStyle.Colors.text2)
        }
    }

    private static func footingMaterial() -> SCNMaterial {
        material(color: OPSStyle.Colors.textMute)
    }

    private static func material(color: Color) -> SCNMaterial {
        let result = SCNMaterial()
        result.diffuse.contents = UIColor(color)
        result.roughness.contents = 0.85
        result.isDoubleSided = false
        return result
    }
}

private enum FramingSceneLayer: CaseIterable, Hashable {
    case joists
    case beams
    case posts
    case footings
    case rim
    case blocking

    var nodeName: String {
        switch self {
        case .joists: return "layer.joists"
        case .beams: return "layer.beams"
        case .posts: return "layer.posts"
        case .footings: return "layer.footings"
        case .rim: return "layer.rim"
        case .blocking: return "layer.blocking"
        }
    }

    static func layer(for role: FramingRole) -> FramingSceneLayer {
        switch role {
        case .joist, .cantilever: return .joists
        case .beam: return .beams
        case .post: return .posts
        case .ledger, .rimBand: return .rim
        case .blocking, .bridging: return .blocking
        }
    }
}

private struct LumberActualDimensions {
    let widthMeters: Float
    let depthMeters: Float

    var isRenderable: Bool {
        widthMeters.isFinite && widthMeters > 0 && depthMeters.isFinite && depthMeters > 0
    }

    init(_ nominalSize: LumberSize, plyCount: Int) {
        let dimensionsInches: (width: Float, depth: Float)
        switch nominalSize {
        case .twoBySix: dimensionsInches = (1.5, 5.5)
        case .twoByEight: dimensionsInches = (1.5, 7.25)
        case .twoByTen: dimensionsInches = (1.5, 9.25)
        case .twoByTwelve: dimensionsInches = (1.5, 11.25)
        case .fourByFour: dimensionsInches = (3.5, 3.5)
        case .fourBySix: dimensionsInches = (3.5, 5.5)
        case .sixBySix: dimensionsInches = (5.5, 5.5)
        }
        widthMeters = dimensionsInches.width * Float(max(plyCount, 1)) / 39.3701
        depthMeters = dimensionsInches.depth / 39.3701
    }
}
