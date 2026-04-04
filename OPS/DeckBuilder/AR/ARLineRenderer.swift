// OPS/OPS/DeckBuilder/AR/ARLineRenderer.swift

import Foundation
import RealityKit
import UIKit

/// Renders lines, vertex dots, dimension labels, and footprint fill in AR 3D space using RealityKit entities.
class ARLineRenderer {

    // MARK: - Root Entity

    let rootAnchor: AnchorEntity

    // MARK: - Entity Tracking

    private var vertexEntities: [String: ModelEntity] = [:]
    private var edgeEntities: [String: Entity] = [:]         // contains line + label
    private var liveLineEntity: Entity?
    private var footprintEntity: ModelEntity?

    // MARK: - Colors (from OPSStyle tokens, converted for RealityKit)

    private let vertexPlacedColor: UIColor = UIColor(red: 0.65, green: 0.78, blue: 0.46, alpha: 1.0)   // successStatus green
    private let vertexFirstColor: UIColor = UIColor(red: 0.349, green: 0.471, blue: 0.58, alpha: 1.0)   // primaryAccent blue-gray
    private let edgeLockedColor: UIColor = UIColor.white
    private let edgeLiveColor: UIColor = UIColor(red: 0.349, green: 0.471, blue: 0.58, alpha: 0.5)      // primaryAccent 50%
    private let footprintFillColor: UIColor = UIColor(red: 0.349, green: 0.471, blue: 0.58, alpha: 0.15) // primaryAccent 15%
    private let labelColor: UIColor = UIColor.white

    // MARK: - Geometry Constants

    private let vertexRadius: Float = 0.03       // 3cm — fist-sized from standing distance
    private let edgeWidth: Float = 0.01          // 1cm wide
    private let edgeHeight: Float = 0.005        // 0.5cm tall
    private let labelTextSize: CGFloat = 0.04    // 4cm text height in world space

    // MARK: - Init

    init() {
        rootAnchor = AnchorEntity(world: .zero)
    }

    // MARK: - Vertex Operations

    /// Add a vertex sphere at the given world position
    /// - Parameters:
    ///   - position: World-space position (SIMD3<Float>)
    ///   - isFirst: Whether this is the first vertex (close-loop target — colored blue)
    /// - Returns: A unique name for the vertex entity
    @discardableResult
    func addVertex(at position: SIMD3<Float>, isFirst: Bool) -> String {
        let name = "vertex_\(UUID().uuidString)"
        let mesh = MeshResource.generateSphere(radius: vertexRadius)
        let color = isFirst ? vertexFirstColor : vertexPlacedColor
        let material = SimpleMaterial(color: color, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        entity.position = position
        rootAnchor.addChild(entity)
        vertexEntities[name] = entity
        return name
    }

    /// Remove a vertex sphere by name
    func removeVertex(named name: String) {
        if let entity = vertexEntities.removeValue(forKey: name) {
            entity.removeFromParent()
        }
    }

    // MARK: - Locked Edge Operations

    /// Add a solid locked edge between two world positions with a dimension label
    /// - Parameters:
    ///   - from: Start position in world space
    ///   - to: End position in world space
    ///   - label: Dimension label text (e.g., "~16' 4\" ±6\"")
    /// - Returns: A unique name for the edge entity group
    @discardableResult
    func addLockedEdge(from: SIMD3<Float>, to: SIMD3<Float>, label: String) -> String {
        let name = "edge_\(UUID().uuidString)"
        let group = Entity()
        group.name = name

        // Line box between the two points
        let lineEntity = createLineEntity(from: from, to: to, color: edgeLockedColor, alpha: 1.0)
        group.addChild(lineEntity)

        // Dimension label at midpoint
        let labelEntity = createLabelEntity(
            text: label,
            position: midpoint(from, to),
            from: from,
            to: to
        )
        group.addChild(labelEntity)

        rootAnchor.addChild(group)
        edgeEntities[name] = group
        return name
    }

    /// Remove an edge (line + label) by name
    func removeEdge(named name: String) {
        if let entity = edgeEntities.removeValue(forKey: name) {
            entity.removeFromParent()
        }
    }

    // MARK: - Live Line Operations

    /// Update or create the live preview line from the last vertex to the crosshair position
    func updateLiveLine(from: SIMD3<Float>, to: SIMD3<Float>, label: String) {
        // Remove existing live line
        liveLineEntity?.removeFromParent()

        let group = Entity()
        group.name = "live_line"

        // Semi-transparent dashed line (approximated with two short segments with gaps)
        let distance = simd_distance(from, to)
        let segmentLength: Float = 0.15  // 15cm segments
        let gapLength: Float = 0.08      // 8cm gaps
        let direction = simd_normalize(to - from)

        var currentDistance: Float = 0
        while currentDistance < distance {
            let segEnd = min(currentDistance + segmentLength, distance)
            let segFrom = from + direction * currentDistance
            let segTo = from + direction * segEnd
            let segment = createLineEntity(from: segFrom, to: segTo, color: edgeLiveColor, alpha: 0.6)
            group.addChild(segment)
            currentDistance = segEnd + gapLength
        }

        // Dimension label
        let labelEntity = createLabelEntity(
            text: label,
            position: midpoint(from, to),
            from: from,
            to: to
        )
        group.addChild(labelEntity)

        rootAnchor.addChild(group)
        liveLineEntity = group
    }

    /// Remove the live preview line
    func removeLiveLine() {
        liveLineEntity?.removeFromParent()
        liveLineEntity = nil
    }

    // MARK: - Footprint Fill

    /// Render a flat filled plane covering the closed polygon
    func showFootprintFill(vertices: [SIMD3<Float>]) {
        guard vertices.count >= 3 else { return }

        // Remove existing footprint
        footprintEntity?.removeFromParent()

        // Calculate bounding box for the plane
        let xs = vertices.map { $0.x }
        let zs = vertices.map { $0.z }
        let minX = xs.min()!, maxX = xs.max()!
        let minZ = zs.min()!, maxZ = zs.max()!
        let avgY = vertices.map { $0.y }.reduce(0, +) / Float(vertices.count)

        let width = maxX - minX
        let depth = maxZ - minZ

        let mesh = MeshResource.generatePlane(width: width, depth: depth)
        let material = SimpleMaterial(color: footprintFillColor, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Position at center of bounding box, at average Y
        entity.position = SIMD3<Float>(
            (minX + maxX) / 2,
            avgY - 0.001,  // slightly below vertices to avoid z-fighting
            (minZ + maxZ) / 2
        )

        rootAnchor.addChild(entity)
        footprintEntity = entity
    }

    // MARK: - Clear All

    /// Remove all rendered entities
    func clearAll() {
        for (_, entity) in vertexEntities {
            entity.removeFromParent()
        }
        vertexEntities.removeAll()

        for (_, entity) in edgeEntities {
            entity.removeFromParent()
        }
        edgeEntities.removeAll()

        liveLineEntity?.removeFromParent()
        liveLineEntity = nil

        footprintEntity?.removeFromParent()
        footprintEntity = nil
    }

    // MARK: - Private Helpers

    /// Create a thin box entity representing a line segment between two points
    private func createLineEntity(from: SIMD3<Float>, to: SIMD3<Float>, color: UIColor, alpha: Float) -> ModelEntity {
        let length = simd_distance(from, to)
        guard length > 0.001 else {
            return ModelEntity()
        }

        let mesh = MeshResource.generateBox(width: edgeWidth, height: edgeHeight, depth: length)
        var material = SimpleMaterial(color: color.withAlphaComponent(CGFloat(alpha)), isMetallic: false)
        material.roughness = .float(0.8)
        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Position at midpoint
        entity.position = midpoint(from, to)

        // Rotate to point from → to
        let direction = simd_normalize(to - from)
        // Default box extends along Z axis, so we orient from Z-forward to our direction
        let forward = SIMD3<Float>(0, 0, 1)
        let rotation = simd_quatf(from: forward, to: direction)
        entity.orientation = rotation

        return entity
    }

    /// Create a text entity for a dimension label
    private func createLabelEntity(text: String, position: SIMD3<Float>, from: SIMD3<Float>, to: SIMD3<Float>) -> ModelEntity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: labelTextSize, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let material = SimpleMaterial(color: labelColor, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Position above the line midpoint
        entity.position = SIMD3<Float>(position.x, position.y + 0.08, position.z)

        // Compute text width from bounds so we can center it
        let bounds = entity.visualBounds(relativeTo: nil)
        let textWidth = bounds.extents.x
        entity.position.x -= textWidth / 2

        return entity
    }

    /// Midpoint between two SIMD3 positions
    private func midpoint(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        (a + b) / 2
    }
}
