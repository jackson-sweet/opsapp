// OPS/OPS/DeckBuilder/AR/ARLineRenderer.swift

import Foundation
import RealityKit
import UIKit

/// Renders lines, vertex markers, dimension labels, and footprint fill in AR 3D space.
/// Visual style: tactical/military HUD — thin lines, monospace labels, clean geometry.
class ARLineRenderer {

    // MARK: - Root Entity

    let rootAnchor: AnchorEntity

    // MARK: - Entity Tracking

    private var vertexEntities: [String: Entity] = [:]
    private var edgeEntities: [String: Entity] = [:]
    private var labelEntities: [ModelEntity] = []
    private var liveLineEntity: Entity?
    private var liveLabelEntity: ModelEntity?
    private var footprintEntity: ModelEntity?

    // MARK: - Colors — white default, no arbitrary blue

    private let edgeDefaultColor: UIColor = UIColor.white
    private let edgeLiveColor: UIColor = UIColor.white.withAlphaComponent(0.4)
    private let houseEdgeColor: UIColor = UIColor(white: 0.6, alpha: 1.0)
    private let labelColor: UIColor = UIColor.white
    private let footprintFillColor: UIColor = UIColor.white.withAlphaComponent(0.06)

    // Vertex: tactical diamond/crosshair, not colored spheres
    private let vertexColor: UIColor = UIColor.white
    private let vertexFirstColor: UIColor = UIColor.white // same — no arbitrary blue for first vertex

    // MARK: - Geometry Constants

    private let vertexSize: Float = 0.025           // 2.5cm — small tactical marker
    private let edgeWidth: Float = 0.008            // 0.8cm — thinner lines
    private let edgeHeight: Float = 0.003           // 0.3cm
    private let labelTextSize: CGFloat = 0.035      // 3.5cm in world space
    private let materialLabelSize: CGFloat = 0.025  // smaller, below dimension

    // MARK: - Init

    init() {
        rootAnchor = AnchorEntity(world: .zero)
    }

    // MARK: - Vertex Operations

    /// Add a tactical vertex marker (diamond shape) at the given world position
    @discardableResult
    func addVertex(at position: SIMD3<Float>, isFirst: Bool) -> String {
        let name = "vertex_\(UUID().uuidString)"
        let group = Entity()
        group.name = name
        group.position = position

        // Diamond marker: rotated cube
        let mesh = MeshResource.generateBox(width: vertexSize, height: vertexSize * 0.3, depth: vertexSize)
        let material = SimpleMaterial(color: vertexColor, isMetallic: true)
        let diamond = ModelEntity(mesh: mesh, materials: [material])
        diamond.transform.rotation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        group.addChild(diamond)

        // Thin cross lines through the diamond (tactical crosshair at vertex)
        let armLength: Float = vertexSize * 1.2
        let armThickness: Float = 0.002
        let hMesh = MeshResource.generateBox(width: armLength, height: armThickness, depth: armThickness)
        let vMesh = MeshResource.generateBox(width: armThickness, height: armThickness, depth: armLength)
        let armMaterial = SimpleMaterial(color: UIColor.white.withAlphaComponent(0.5), isMetallic: false)
        let hArm = ModelEntity(mesh: hMesh, materials: [armMaterial])
        let vArm = ModelEntity(mesh: vMesh, materials: [armMaterial])
        group.addChild(hArm)
        group.addChild(vArm)

        rootAnchor.addChild(group)
        vertexEntities[name] = group
        return name
    }

    func removeVertex(named name: String) {
        if let entity = vertexEntities.removeValue(forKey: name) {
            entity.removeFromParent()
        }
    }

    // MARK: - Locked Edge Operations

    /// Add a locked edge with dimension label above and optional material label below.
    /// - Parameters:
    ///   - from/to: world positions
    ///   - dimensionLabel: text above the line (e.g., "~16' 4\"")
    ///   - materialLabel: text below the line (e.g., "GLASS RAILING"), nil if no assignment
    ///   - edgeColor: UIColor for the line — white default, task color if assigned
    @discardableResult
    func addLockedEdge(
        from: SIMD3<Float>,
        to: SIMD3<Float>,
        dimensionLabel: String,
        materialLabel: String? = nil,
        edgeColor: UIColor? = nil
    ) -> String {
        let name = "edge_\(UUID().uuidString)"
        let group = Entity()
        group.name = name

        let color = edgeColor ?? edgeDefaultColor
        let lineEntity = createLineEntity(from: from, to: to, color: color, alpha: 1.0)
        group.addChild(lineEntity)

        // Dimension label — ABOVE the line
        let dimLabel = createBillboardLabel(
            text: dimensionLabel,
            position: midpoint(from, to) + SIMD3<Float>(0, 0.07, 0),
            fontSize: labelTextSize
        )
        group.addChild(dimLabel)
        labelEntities.append(dimLabel)

        // Material label — BELOW the line (smaller, dimmer)
        if let matText = materialLabel {
            let matLabel = createBillboardLabel(
                text: matText,
                position: midpoint(from, to) + SIMD3<Float>(0, 0.03, 0),
                fontSize: materialLabelSize,
                color: UIColor.white.withAlphaComponent(0.5)
            )
            group.addChild(matLabel)
            labelEntities.append(matLabel)
        }

        rootAnchor.addChild(group)
        edgeEntities[name] = group
        return name
    }

    /// Legacy compatibility — single label
    @discardableResult
    func addLockedEdge(from: SIMD3<Float>, to: SIMD3<Float>, label: String) -> String {
        addLockedEdge(from: from, to: to, dimensionLabel: label)
    }

    func removeEdge(named name: String) {
        if let entity = edgeEntities.removeValue(forKey: name) {
            labelEntities.removeAll { label in
                label.parent === entity || entity.children.contains(where: { $0 === label })
            }
            entity.removeFromParent()
        }
    }

    // MARK: - Live Line Operations

    func updateLiveLine(from: SIMD3<Float>, to: SIMD3<Float>, label: String) {
        liveLineEntity?.removeFromParent()

        let group = Entity()
        group.name = "live_line"

        // Dashed line segments
        let distance = simd_distance(from, to)
        let segmentLength: Float = 0.12
        let gapLength: Float = 0.06
        let direction = distance > 0.001 ? simd_normalize(to - from) : SIMD3<Float>(0, 0, 1)

        var d: Float = 0
        while d < distance {
            let segEnd = min(d + segmentLength, distance)
            let segment = createLineEntity(
                from: from + direction * d,
                to: from + direction * segEnd,
                color: edgeLiveColor,
                alpha: 0.5
            )
            group.addChild(segment)
            d = segEnd + gapLength
        }

        // Dimension label above
        let liveLbl = createBillboardLabel(
            text: label,
            position: midpoint(from, to) + SIMD3<Float>(0, 0.07, 0),
            fontSize: labelTextSize
        )
        group.addChild(liveLbl)
        liveLabelEntity = liveLbl

        rootAnchor.addChild(group)
        liveLineEntity = group
    }

    func removeLiveLine() {
        liveLineEntity?.removeFromParent()
        liveLineEntity = nil
    }

    // MARK: - Footprint Fill

    func showFootprintFill(vertices: [SIMD3<Float>]) {
        guard vertices.count >= 3 else { return }
        footprintEntity?.removeFromParent()

        let avgY = vertices.map { $0.y }.reduce(0, +) / Float(vertices.count) - 0.001
        let centerX = vertices.map { $0.x }.reduce(0, +) / Float(vertices.count)
        let centerZ = vertices.map { $0.z }.reduce(0, +) / Float(vertices.count)

        var positions: [SIMD3<Float>] = [SIMD3<Float>(centerX, avgY, centerZ)]
        for v in vertices { positions.append(SIMD3<Float>(v.x, avgY, v.z)) }

        let n = vertices.count
        var indices: [UInt32] = []
        for i in 1...n {
            let next = (i % n) + 1
            indices.append(contentsOf: [0, UInt32(i), UInt32(next)])
            indices.append(contentsOf: [0, UInt32(next), UInt32(i)])
        }

        let normals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: positions.count)
        var descriptor = MeshDescriptor(name: "footprint")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)

        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return }
        let material = SimpleMaterial(color: footprintFillColor, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        rootAnchor.addChild(entity)
        footprintEntity = entity
    }

    // MARK: - Label Billboarding

    func updateLabelOrientations(cameraPosition: SIMD3<Float>) {
        for label in labelEntities {
            billboardToCamera(entity: label, cameraPosition: cameraPosition)
        }
        if let liveLabel = liveLabelEntity {
            billboardToCamera(entity: liveLabel, cameraPosition: cameraPosition)
        }
    }

    /// Billboard that faces camera but stays upright (no mirroring).
    /// The standard look(at:) produces mirrored text because RealityKit text
    /// faces +Z but look(at:) orients -Z toward the target.
    private func billboardToCamera(entity: ModelEntity, cameraPosition: SIMD3<Float>) {
        let toCamera = cameraPosition - entity.position
        let angle = atan2(toCamera.x, toCamera.z)
        // Rotate around Y axis to face camera, + PI to flip text forward
        entity.orientation = simd_quatf(angle: angle + .pi, axis: SIMD3<Float>(0, 1, 0))
    }

    // MARK: - Clear All

    func clearAll() {
        for (_, entity) in vertexEntities { entity.removeFromParent() }
        vertexEntities.removeAll()
        for (_, entity) in edgeEntities { entity.removeFromParent() }
        edgeEntities.removeAll()
        labelEntities.removeAll()
        liveLineEntity?.removeFromParent()
        liveLineEntity = nil
        liveLabelEntity = nil
        footprintEntity?.removeFromParent()
        footprintEntity = nil
    }

    // MARK: - Private Helpers

    private func createLineEntity(from: SIMD3<Float>, to: SIMD3<Float>, color: UIColor, alpha: Float) -> ModelEntity {
        let length = simd_distance(from, to)
        guard length > 0.001 else { return ModelEntity() }

        let mesh = MeshResource.generateBox(width: edgeWidth, height: edgeHeight, depth: length)
        var material = SimpleMaterial(color: color.withAlphaComponent(CGFloat(alpha)), isMetallic: false)
        material.roughness = .float(0.9)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = midpoint(from, to)

        let direction = simd_normalize(to - from)
        let forward = SIMD3<Float>(0, 0, 1)
        entity.orientation = simd_quatf(from: forward, to: direction)
        return entity
    }

    /// Create a billboard text label that won't mirror when facing the camera.
    private func createBillboardLabel(
        text: String,
        position: SIMD3<Float>,
        fontSize: CGFloat,
        color: UIColor = .white
    ) -> ModelEntity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.001,
            font: .monospacedSystemFont(ofSize: fontSize, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )
        let material = SimpleMaterial(color: color, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Center the text horizontally
        let bounds = entity.visualBounds(relativeTo: nil)
        let textWidth = bounds.extents.x
        entity.position = SIMD3<Float>(position.x - textWidth / 2, position.y, position.z)

        return entity
    }

    private func midpoint(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        (a + b) / 2
    }
}
