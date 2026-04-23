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
    private var liveLineEntity: Entity?
    private var liveLabelEntity: ModelEntity?
    private var footprintEntity: ModelEntity?

    private var textMeshCache: [String: MeshResource] = [:]
    private var lastLiveLabelText: String = ""
    private var lastLiveDashCount: Int = 0

    /// Pool of dash segment entities for the live line. Reused across frames:
    /// segments are repositioned every call, new ones allocated only when dash
    /// count increases, surplus segments are disabled.
    private var liveDashPool: [ModelEntity] = []

    /// Hash of the last rendered alignment guide set. Prevents rebuilding the
    /// entire dashed guide mesh tree every frame when guides haven't changed.
    private var lastGuidesHash: Int = 0

    // MARK: - Colors — white default, no arbitrary blue

    private let edgeDefaultColor: UIColor = UIColor.white
    private let edgeLiveColor: UIColor = UIColor.white.withAlphaComponent(0.4)
    private let houseEdgeColor: UIColor = UIColor(white: 0.6, alpha: 1.0)
    private let labelColor: UIColor = UIColor.white
    private let footprintFillColor: UIColor = UIColor.white.withAlphaComponent(0.06)

    // Vertex: tactical diamond/crosshair, not colored spheres
    private let vertexColor: UIColor = UIColor.white
    private let vertexFirstColor: UIColor = UIColor.white // same — no arbitrary blue for first vertex

    private func cachedTextMesh(_ text: String, fontSize: CGFloat) -> MeshResource {
        let key = "\(text)_\(fontSize)"
        if let cached = textMeshCache[key] { return cached }
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.001,
            font: .monospacedSystemFont(ofSize: fontSize, weight: .semibold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )
        textMeshCache[key] = mesh
        return mesh
    }

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

        // Labels lie flat on the ground along the edge direction — no billboard
        // tracking required. Dimension label sits centered on the edge, slightly
        // above it to avoid z-fighting with the edge strip and the ground plane.
        let edgeDirection = to - from
        let mid = midpoint(from, to)
        let perp = groundPerpendicular(direction: edgeDirection)
        let labelLift: Float = 0.005  // 5mm above edge surface

        let dimLabel = createGroundLabel(
            text: dimensionLabel,
            position: mid + SIMD3<Float>(0, labelLift, 0),
            direction: edgeDirection,
            fontSize: labelTextSize
        )
        group.addChild(dimLabel)

        // Material label — offset 5cm perpendicular to the edge, on the same ground
        // plane. Puts it beside the edge (not stacked on top of the dim label) so
        // both stay readable when viewed from above.
        if let matText = materialLabel {
            let matLabel = createGroundLabel(
                text: matText,
                position: mid + SIMD3<Float>(0, labelLift, 0) + perp * 0.05,
                direction: edgeDirection,
                fontSize: materialLabelSize,
                color: UIColor.white.withAlphaComponent(0.5)
            )
            group.addChild(matLabel)
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
            entity.removeFromParent()
        }
    }

    // MARK: - Live Line Operations

    /// Update the live (unplaced) line from the last vertex to the crosshair.
    ///
    /// Uses a dash-segment pool keyed to `liveDashPool`:
    ///   - The parent `Entity` is created once and reused.
    ///   - Dash segments are created lazily up to the current count, and reused
    ///     across frames. Surplus segments are disabled (not torn down) when the
    ///     count drops.
    ///   - Every call repositions all active segments (cheap — position + quat),
    ///     so dashes follow the crosshair smoothly as direction changes.
    ///   - Mesh/material is built once per segment. No per-frame `generateBox` /
    ///     `SimpleMaterial` allocations regardless of edge length or crosshair speed.
    ///   - The label is only reconstructed when the text changes; otherwise it's
    ///     just repositioned.
    ///
    /// Before: a 10m edge allocated 55 box meshes 30–60 times/sec as the
    /// dimension label ticked every 0.5". After: one-time allocation per dash
    /// count, ~O(N) reposition per frame. Scales cleanly regardless of edge length.
    func updateLiveLine(from: SIMD3<Float>, to: SIMD3<Float>, label: String) {
        let distance = simd_distance(from, to)
        let segmentLength: Float = 0.12
        let gapLength: Float = 0.06
        let stride = segmentLength + gapLength
        let newDashCount = max(1, Int(distance / stride))

        // Ensure the container exists.
        let group: Entity
        if let existing = liveLineEntity {
            group = existing
        } else {
            let created = Entity()
            created.name = "live_line"
            rootAnchor.addChild(created)
            liveLineEntity = created
            group = created
        }

        // Grow the pool lazily. Each segment is a fixed-length box; length
        // variation on the tail is handled by scaling Z.
        while liveDashPool.count < newDashCount {
            let mesh = MeshResource.generateBox(
                width: edgeWidth, height: edgeHeight, depth: segmentLength
            )
            var material = SimpleMaterial(
                color: edgeLiveColor.withAlphaComponent(0.5), isMetallic: false
            )
            material.roughness = .float(0.9)
            let entity = ModelEntity(mesh: mesh, materials: [material])
            group.addChild(entity)
            liveDashPool.append(entity)
        }

        // Orient all segments with +Z aligned to the edge direction.
        let direction = distance > 0.001 ? simd_normalize(to - from) : SIMD3<Float>(0, 0, 1)
        let forward = SIMD3<Float>(0, 0, 1)
        let segOrientation = simd_quatf(from: forward, to: direction)

        var d: Float = 0
        for i in 0..<newDashCount {
            let segStart = d
            let segEnd = min(d + segmentLength, distance)
            let actualLength = segEnd - segStart
            let dash = liveDashPool[i]
            dash.isEnabled = true
            dash.position = from + direction * ((segStart + segEnd) * 0.5)
            dash.orientation = segOrientation
            // Scale only the final (shorter) tail dash; full segments render at 1.0.
            let zScale = max(0.01, actualLength / segmentLength)
            dash.scale = SIMD3<Float>(1, 1, zScale)
            d = segEnd + gapLength
        }
        // Disable any surplus pool entries without tearing them down.
        if liveDashPool.count > newDashCount {
            for i in newDashCount..<liveDashPool.count {
                liveDashPool[i].isEnabled = false
            }
        }
        lastLiveDashCount = newDashCount

        // Label: rebuild only when text changes; otherwise just reposition.
        // Orientation is handled by BillboardComponent on the label pivot, so we only
        // need to update position when the text is unchanged.
        let labelPos = midpoint(from, to) + SIMD3<Float>(0, 0.005, 0)
        if label != lastLiveLabelText || liveLabelEntity == nil {
            liveLabelEntity?.removeFromParent()
            let liveLbl = createGroundLabel(
                text: label,
                position: labelPos,
                direction: direction,
                fontSize: labelTextSize
            )
            group.addChild(liveLbl)
            liveLabelEntity = liveLbl
            lastLiveLabelText = label
        } else if let existing = liveLabelEntity {
            existing.position = labelPos
        }
    }

    func removeLiveLine() {
        liveLineEntity?.removeFromParent()
        liveLineEntity = nil
        liveLabelEntity = nil
        liveDashPool.removeAll()  // pool children are gone with the parent
        lastLiveDashCount = 0
        lastLiveLabelText = ""
    }

    // MARK: - Alignment Guide Lines

    private var alignmentGuideEntity: Entity?

    /// Render dotted alignment guide lines in AR world space.
    /// Colors match the 2D canvas: cyan for axis, accent for parallel, green for perpendicular.
    ///
    /// Hash-gated: the full guide set's endpoints and types are hashed and
    /// compared to the last rendered state. Skips the entire rebuild when
    /// nothing has changed — prevents per-frame reallocation while the
    /// crosshair sits on a stable alignment.
    func updateAlignmentGuides(_ guides: [ARPerimeterViewModel.ARAlignmentGuide]) {
        let newHash = guidesHash(guides)
        if newHash == lastGuidesHash { return }
        lastGuidesHash = newHash

        alignmentGuideEntity?.removeFromParent()
        alignmentGuideEntity = nil
        guard !guides.isEmpty else { return }

        let group = Entity()
        group.name = "alignment_guides"

        for guide in guides {
            let color: UIColor
            switch guide.type {
            case .horizontal, .vertical:
                color = UIColor.cyan.withAlphaComponent(0.5)
            case .parallel:
                color = UIColor.systemOrange.withAlphaComponent(0.4)
            case .perpendicular:
                color = UIColor.systemGreen.withAlphaComponent(0.4)
            }

            // Dashed line
            let from = guide.from
            let to = guide.to
            let distance = simd_distance(from, to)
            let segmentLength: Float = 0.06
            let gapLength: Float = 0.04
            let direction = distance > 0.001 ? simd_normalize(to - from) : SIMD3<Float>(1, 0, 0)

            var d: Float = 0
            while d < distance {
                let segEnd = min(d + segmentLength, distance)
                let segment = createLineEntity(
                    from: from + direction * d,
                    to: from + direction * segEnd,
                    color: color,
                    alpha: 0.8
                )
                group.addChild(segment)
                d = segEnd + gapLength
            }
        }

        rootAnchor.addChild(group)
        alignmentGuideEntity = group
    }

    /// Quantized structural hash of the guide set. Endpoints are bucketed to
    /// 5mm so raycast jitter doesn't force rebuilds; any meaningful guide
    /// change still updates the hash.
    private func guidesHash(_ guides: [ARPerimeterViewModel.ARAlignmentGuide]) -> Int {
        var hasher = Hasher()
        hasher.combine(guides.count)
        for guide in guides {
            hasher.combine(quantize(guide.from.x))
            hasher.combine(quantize(guide.from.y))
            hasher.combine(quantize(guide.from.z))
            hasher.combine(quantize(guide.to.x))
            hasher.combine(quantize(guide.to.y))
            hasher.combine(quantize(guide.to.z))
            hasher.combine(guide.type)
        }
        return hasher.finalize()
    }

    private func quantize(_ v: Float) -> Int { Int((v * 200).rounded()) }  // 5mm bucket

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

    func removeFootprintFill() {
        footprintEntity?.removeFromParent()
        footprintEntity = nil
    }

    // MARK: - Reposition Preview

    private var repositionPreviewEntity: Entity?
    private var hiddenEdgeNames: Set<String> = []
    private var hiddenVertexName: String?

    /// Hide the static edges and vertex being repositioned so preview replaces them
    func beginRepositionPreview(hideEdgeNames: [String], hideVertexName: String) {
        for name in hideEdgeNames {
            edgeEntities[name]?.isEnabled = false
            hiddenEdgeNames.insert(name)
        }
        vertexEntities[hideVertexName]?.isEnabled = false
        hiddenVertexName = hideVertexName
    }

    /// Render dashed preview lines from connected vertices to the crosshair + a vertex marker.
    /// Preview labels lie flat on the ground along each preview edge — no billboarding required.
    func updateRepositionPreview(
        vertexPosition: SIMD3<Float>,
        connectedEndpoints: [(otherVertex: SIMD3<Float>, label: String)]
    ) {
        repositionPreviewEntity?.removeFromParent()

        let group = Entity()
        group.name = "reposition_preview"

        // Vertex marker at crosshair
        let vtxMesh = MeshResource.generateBox(width: vertexSize, height: vertexSize * 0.3, depth: vertexSize)
        let vtxMaterial = SimpleMaterial(color: UIColor.white, isMetallic: true)
        let diamond = ModelEntity(mesh: vtxMesh, materials: [vtxMaterial])
        diamond.position = vertexPosition
        diamond.transform.rotation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        group.addChild(diamond)

        for connection in connectedEndpoints {
            let from = connection.otherVertex
            let to = vertexPosition
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
                    alpha: 0.6
                )
                group.addChild(segment)
                d = segEnd + gapLength
            }

            let dimLabel = createGroundLabel(
                text: connection.label,
                position: midpoint(from, to) + SIMD3<Float>(0, 0.005, 0),
                direction: to - from,
                fontSize: labelTextSize
            )
            group.addChild(dimLabel)
        }

        rootAnchor.addChild(group)
        repositionPreviewEntity = group
    }

    /// End reposition preview — restore hidden entities and clean up
    func endRepositionPreview() {
        repositionPreviewEntity?.removeFromParent()
        repositionPreviewEntity = nil

        for name in hiddenEdgeNames {
            edgeEntities[name]?.isEnabled = true
        }
        hiddenEdgeNames.removeAll()

        if let name = hiddenVertexName {
            vertexEntities[name]?.isEnabled = true
        }
        hiddenVertexName = nil
    }

    // MARK: - Clear All

    func clearAll() {
        for (_, entity) in vertexEntities { entity.removeFromParent() }
        vertexEntities.removeAll()
        for (_, entity) in edgeEntities { entity.removeFromParent() }
        edgeEntities.removeAll()
        liveLineEntity?.removeFromParent()
        liveLineEntity = nil
        liveLabelEntity = nil
        liveDashPool.removeAll()
        lastLiveDashCount = 0
        lastLiveLabelText = ""
        footprintEntity?.removeFromParent()
        footprintEntity = nil
        alignmentGuideEntity?.removeFromParent()
        alignmentGuideEntity = nil
        lastGuidesHash = 0
        endRepositionPreview()
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

    // Former ground-plane orientation helper was removed when labels moved to
    // BillboardComponent. BillboardComponent rotates the pivot toward the camera
    // every frame, which makes any manual ground-aligned orientation wrong anyway.

    /// Ground-plane perpendicular of a direction vector (rotated +90° around +Y
    /// in the XZ plane). Used to offset material labels off to the side of an
    /// edge without stacking them on the dimension label.
    private func groundPerpendicular(direction: SIMD3<Float>) -> SIMD3<Float> {
        let horizontal = SIMD3<Float>(direction.x, 0, direction.z)
        let len = simd_length(horizontal)
        guard len > 0.001 else { return SIMD3<Float>(0, 0, 1) }
        let dir = horizontal / len
        // cross((0,1,0), dir) = (dir.z, 0, -dir.x)
        return SIMD3<Float>(dir.z, 0, -dir.x)
    }

    /// Create a text label with a dark badge background that always faces the user.
    ///
    /// Prior version laid labels flat on the ground aligned with the edge direction.
    /// On large decks where users walk all the way around a perimeter, labels on the
    /// far side read upside-down or sideways depending on approach angle. Fix: apply
    /// `BillboardComponent` so RealityKit keeps the pivot rotated toward the camera
    /// every frame. Text stays legible from any viewing position with no per-frame
    /// work on our side.
    ///
    /// `direction` is kept in the signature for source compatibility but is no longer
    /// used now that labels billboard — every call site already passed a direction,
    /// and future work may revive direction-based anchoring for specific label types.
    private func createGroundLabel(
        text: String,
        position: SIMD3<Float>,
        direction: SIMD3<Float>,
        fontSize: CGFloat,
        color: UIColor = .white,
        showBadge: Bool = true
    ) -> ModelEntity {
        _ = direction  // intentionally unused — BillboardComponent handles orientation
        let mesh = cachedTextMesh(text, fontSize: fontSize)
        let material = SimpleMaterial(color: color, isMetallic: false)
        let textEntity = ModelEntity(mesh: mesh, materials: [material])

        // Center the text mesh in its local space so BillboardComponent rotates
        // around the text's visual center (not its generated-text anchor point).
        let bounds = textEntity.visualBounds(relativeTo: nil)
        textEntity.position = SIMD3<Float>(-bounds.center.x, -bounds.center.y, 0)

        let pivot = ModelEntity()
        pivot.position = position
        pivot.components.set(BillboardComponent())
        pivot.addChild(textEntity)

        if showBadge {
            let padH: Float = 0.012
            let padV: Float = 0.006
            let bgWidth = bounds.extents.x * 2 + padH * 2
            let bgHeight = bounds.extents.y * 2 + padV * 2
            let bgMesh = MeshResource.generateBox(
                width: bgWidth, height: bgHeight, depth: 0.0004,
                cornerRadius: 0.004
            )
            var bgMaterial = SimpleMaterial(
                color: UIColor.black.withAlphaComponent(0.7), isMetallic: false
            )
            bgMaterial.roughness = .float(1.0)
            let bgEntity = ModelEntity(mesh: bgMesh, materials: [bgMaterial])
            // Badge sits just behind the text from the camera's POV — 2mm offset
            // along local -Z clears z-fighting. BillboardComponent keeps the whole
            // pivot facing the camera, so the badge stays behind the text.
            bgEntity.position = SIMD3<Float>(0, 0, -0.002)
            pivot.addChild(bgEntity)
        }

        return pivot
    }

    private func midpoint(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        (a + b) / 2
    }
}
