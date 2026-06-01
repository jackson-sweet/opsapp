// OPS/OPS/DeckBuilder/3D/DeckSceneBuilder.swift

import Foundation
import SceneKit
import simd
import UIKit

struct DeckSceneBuilder {

    // MARK: - Constants

    private static let inchesToMeters: Float = 1.0 / 39.3701
    private static let feetToMeters: Float = 0.3048

    // Material colors (from spec)
    private static let deckSurfaceColor = UIColor(red: 196/255, green: 149/255, blue: 106/255, alpha: 1)  // #C4956A cedar
    private static let postColor = UIColor(red: 139/255, green: 108/255, blue: 74/255, alpha: 1)           // #8B6C4A dark wood
    private static let railPostColor = UIColor(red: 136/255, green: 136/255, blue: 136/255, alpha: 1)      // #888888 aluminum
    private static let glassPanelColor = UIColor(red: 160/255, green: 200/255, blue: 232/255, alpha: 0.2)  // #A0C8E8 at 20%
    private static let picketColor = UIColor.white                                                          // #FFFFFF
    private static let cableColor = UIColor(red: 102/255, green: 102/255, blue: 102/255, alpha: 1)         // #666666
    private static let topRailColor = UIColor(red: 136/255, green: 136/255, blue: 136/255, alpha: 1)       // #888888
    private static let stairTreadColor = UIColor(red: 196/255, green: 149/255, blue: 106/255, alpha: 1)    // #C4956A
    private static let stringerColor = UIColor(red: 139/255, green: 108/255, blue: 74/255, alpha: 1)       // #8B6C4A
    private static let groundColor = UIColor(red: 74/255, green: 94/255, blue: 58/255, alpha: 0.3)         // #4A5E3A at 30%
    private static let houseWallColor = UIColor(red: 136/255, green: 136/255, blue: 136/255, alpha: 0.5)   // #888888 at 50%

    // Dimensions in meters
    private static let railPostSizeM: Float = 3.5 * inchesToMeters   // 3.5" square rail post
    private static let railHeightM: Float = 36.0 * inchesToMeters    // 36" rail height
    private static let bottomRailOffsetM: Float = 4.0 * inchesToMeters // 4" above deck
    private static let topRailThicknessM: Float = 2.0 * inchesToMeters
    private static let treadThicknessM: Float = 1.5 * inchesToMeters  // 1.5" thick tread
    private static let houseWallHeightM: Float = 8.0 * feetToMeters   // 8' wall above deck

    // MARK: - Main Build

    static func buildScene(from drawingData: DeckDrawingData) -> SCNScene {
        let scene = SCNScene()

        guard let scaleFactor = drawingData.scaleFactor, scaleFactor > 0 else {
            // No scale — return empty scene with just ground and lights
            addGroundPlane(to: scene)
            addLighting(to: scene)
            return scene
        }

        // Calculate scene center for camera targeting
        var allPositions: [CGPoint] = []
        var cameraFrameCenter: CGPoint?

        if drawingData.isMultiLevel {
            // Bug ee787f29 / bc9109ef — the multi-level scene must share ONE
            // centroid across ALL levels. The previous per-level centroid
            // re-centered each level to its own bbox midpoint, so levels with
            // different canvas positions (e.g. an upper deck tucked into a
            // corner) collapsed onto the lower deck at the 3D origin. Build
            // the shared centroid from every position on every level — empty
            // levels contribute nothing, populated ones anchor the frame.
            var globalUnion: [CGPoint] = []
            for level in drawingData.levels {
                globalUnion.append(contentsOf: level.orderedPositions)
                globalUnion.append(contentsOf: level.detectedSurfaces.flatMap { $0.positions })
                globalUnion.append(contentsOf: level.vertices.map { $0.position })
                globalUnion.append(contentsOf: stairFramePositions(
                    edges: level.edges,
                    vertices: level.vertices,
                    polygonVertices: level.orderedPositions,
                    scaleFactor: scaleFactor,
                    measurementSystem: drawingData.config.measurementSystem
                ))
            }
            let sharedBounds = DeckMeshGenerator.boundingRect(for: globalUnion)
            let sharedCenter = CGPoint(x: sharedBounds.midX, y: sharedBounds.midY)
            cameraFrameCenter = sharedCenter

            for (levelIndex, level) in drawingData.levels.enumerated() {
                // DECK-NEW-1 — render every detected closed face on this level
                // (multiple surfaces, even sharing edges). Per-surface material
                // resolved against the level's persisted DeckSurface store.
                let detected = level.detectedSurfaces
                guard !detected.isEmpty || level.isClosed else { continue }

                let surfacesIn3D: [SurfaceMesh3D]? = detected.isEmpty ? nil : detected.map { face in
                    let metersPositions = convertToMeters(
                        vertices: face.positions,
                        scaleFactor: scaleFactor,
                        center: sharedCenter
                    )
                    let resolved = resolvedSurfacePresentation(for: face, in: level.surfaces)
                    return SurfaceMesh3D(
                        positionsInMeters: metersPositions,
                        vertexIds: face.vertexIds,
                        assignedItems: resolved.assignedItems,
                        color: resolved.color,
                        boardMaterial: resolved.boardMaterial
                    )
                }
                let primaryFallback = convertToMeters(
                    vertices: level.orderedPositions,
                    scaleFactor: scaleFactor,
                    center: sharedCenter
                )
                allPositions.append(contentsOf: detected.flatMap { $0.positions })
                if detected.isEmpty { allPositions.append(contentsOf: level.orderedPositions) }
                allPositions.append(contentsOf: stairFramePositions(
                    edges: level.edges,
                    vertices: level.vertices,
                    polygonVertices: level.orderedPositions,
                    scaleFactor: scaleFactor,
                    measurementSystem: drawingData.config.measurementSystem
                ))
                let elevationFeet = drawingData.renderElevationFeet(for: level, levelIndex: levelIndex)
                let elevationM = Float(elevationFeet) * feetToMeters
                let vertexPositions = vertexPositionMap(
                    vertices: level.vertices,
                    scaleFactor: scaleFactor,
                    center: sharedCenter
                )
                // Cap the house wall at the bottom of the next level up so a
                // wall on a lower level never punches through the deck above
                // it (bug fb007839). nil when no level sits higher.
                let houseWallCapM = drawingData.heightToNextLevelFeet(aboveLevelAt: levelIndex)
                    .map { Float($0) * feetToMeters }
                buildDeckLevel(
                    parent: scene.rootNode,
                    vertices2D: primaryFallback,
                    edges: level.edges,
                    vertexPositionsInMetersById: vertexPositions,
                    elevationM: elevationM,
                    scaleFactor: scaleFactor,
                    level: level,
                    houseWallCapM: houseWallCapM,
                    surfacesIn3D: surfacesIn3D
                )
            }
            // Level connections (stairs between levels)
            for connection in drawingData.levelConnections {
                buildLevelConnection(parent: scene.rootNode, connection: connection, drawingData: drawingData, scaleFactor: scaleFactor)
            }
        } else {
            // DECK-NEW-1 — same multi-surface treatment for single-level designs.
            let detected = drawingData.detectedSurfaces
            guard !detected.isEmpty || drawingData.isClosed else {
                addGroundPlane(to: scene)
                addLighting(to: scene)
                addCamera(to: scene, fitting: allPositions, scaleFactor: scaleFactor, drawingData: drawingData)
                return scene
            }
            // Bug bc9109ef — shared centroid across detected faces, ordered
            // fallback, and raw vertices so multiple closed shapes don't
            // overlap at the origin.
            var union: [CGPoint] = drawingData.orderedPositions
            union.append(contentsOf: detected.flatMap { $0.positions })
            union.append(contentsOf: drawingData.vertices.map { $0.position })
            union.append(contentsOf: stairFramePositions(
                edges: drawingData.edges,
                vertices: drawingData.vertices,
                polygonVertices: drawingData.orderedPositions,
                scaleFactor: scaleFactor,
                measurementSystem: drawingData.config.measurementSystem
            ))
            let bounds = DeckMeshGenerator.boundingRect(for: union)
            let sharedCenter = CGPoint(x: bounds.midX, y: bounds.midY)
            cameraFrameCenter = sharedCenter

            let surfacesIn3D: [SurfaceMesh3D]? = detected.isEmpty ? nil : detected.map { face in
                let metersPositions = convertToMeters(
                    vertices: face.positions,
                    scaleFactor: scaleFactor,
                    center: sharedCenter
                )
                let resolved = resolvedSurfacePresentation(for: face, in: drawingData.surfaces)
                return SurfaceMesh3D(
                    positionsInMeters: metersPositions,
                    vertexIds: face.vertexIds,
                    assignedItems: resolved.assignedItems,
                    color: resolved.color,
                    boardMaterial: resolved.boardMaterial
                )
            }
            let primaryFallback = convertToMeters(
                vertices: drawingData.orderedPositions,
                scaleFactor: scaleFactor,
                center: sharedCenter
            )
            allPositions = detected.isEmpty ? drawingData.orderedPositions : detected.flatMap { $0.positions }
            allPositions.append(contentsOf: stairFramePositions(
                edges: drawingData.edges,
                vertices: drawingData.vertices,
                polygonVertices: drawingData.orderedPositions,
                scaleFactor: scaleFactor,
                measurementSystem: drawingData.config.measurementSystem
            ))
            let elevationFeet = drawingData.renderElevationFeetSingleLevel
            let elevationM = Float(elevationFeet) * feetToMeters
            let vertexPositions = vertexPositionMap(
                vertices: drawingData.vertices,
                scaleFactor: scaleFactor,
                center: sharedCenter
            )
            buildDeckLevel(
                parent: scene.rootNode,
                vertices2D: primaryFallback,
                edges: drawingData.edges,
                vertexPositionsInMetersById: vertexPositions,
                elevationM: elevationM,
                scaleFactor: scaleFactor,
                level: nil,
                surfacesIn3D: surfacesIn3D
            )
        }

        addGroundPlane(to: scene)
        addLighting(to: scene)
        addCamera(
            to: scene,
            fitting: allPositions,
            scaleFactor: scaleFactor,
            drawingData: drawingData,
            center: cameraFrameCenter
        )

        return scene
    }

    // MARK: - AR Node Variant

    /// Build a deck node for AR placement — geometry only, no camera/lights/ground/wall.
    /// The AR environment provides its own camera, lighting, and ground.
    static func buildARNode(from drawingData: DeckDrawingData) -> SCNNode {
        let rootNode = SCNNode()
        rootNode.name = "deckARRoot"

        guard let scaleFactor = drawingData.scaleFactor, scaleFactor > 0 else {
            return rootNode
        }

        if drawingData.isMultiLevel {
            // Same shared-centroid fix as `buildScene` — multi-level AR view
            // also needs every level converted against ONE frame, otherwise
            // levels stack at the origin in the AR placement scene.
            var globalUnion: [CGPoint] = []
            for level in drawingData.levels where level.isClosed {
                globalUnion.append(contentsOf: level.orderedPositions)
            }
            let sharedBounds = DeckMeshGenerator.boundingRect(for: globalUnion)
            let sharedCenter = CGPoint(x: sharedBounds.midX, y: sharedBounds.midY)

            for (levelIndex, level) in drawingData.levels.enumerated() where level.isClosed {
                let metersVerts = convertToMeters(
                    vertices: level.orderedPositions,
                    scaleFactor: scaleFactor,
                    center: sharedCenter
                )
                let elevationFeet = drawingData.renderElevationFeet(for: level, levelIndex: levelIndex)
                let elevationM = Float(elevationFeet) * feetToMeters
                let vertexPositions = vertexPositionMap(
                    vertices: level.vertices,
                    scaleFactor: scaleFactor,
                    center: sharedCenter
                )
                buildDeckLevel(
                    parent: rootNode,
                    vertices2D: metersVerts,
                    edges: level.edges,
                    vertexPositionsInMetersById: vertexPositions,
                    elevationM: elevationM,
                    scaleFactor: scaleFactor,
                    level: level,
                    skipHouseWall: true
                )
            }
            for connection in drawingData.levelConnections {
                buildLevelConnection(parent: rootNode, connection: connection, drawingData: drawingData, scaleFactor: scaleFactor)
            }
        } else if drawingData.isClosed {
            let metersVerts = convertToMeters(vertices: drawingData.orderedPositions, scaleFactor: scaleFactor)
            let elevationFeet = drawingData.renderElevationFeetSingleLevel
            let elevationM = Float(elevationFeet) * feetToMeters
            let bounds = DeckMeshGenerator.boundingRect(for: drawingData.orderedPositions)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let vertexPositions = vertexPositionMap(
                vertices: drawingData.vertices,
                scaleFactor: scaleFactor,
                center: center
            )
            buildDeckLevel(
                parent: rootNode,
                vertices2D: metersVerts,
                edges: drawingData.edges,
                vertexPositionsInMetersById: vertexPositions,
                elevationM: elevationM,
                scaleFactor: scaleFactor,
                level: nil,
                skipHouseWall: true
            )
        }

        // Shadow-receiving floor — invisible but catches shadows from the deck
        let shadowFloor = SCNFloor()
        shadowFloor.reflectivity = 0
        let shadowMaterial = SCNMaterial()
        shadowMaterial.colorBufferWriteMask = []
        shadowMaterial.lightingModel = .constant
        shadowFloor.firstMaterial = shadowMaterial
        let floorNode = SCNNode(geometry: shadowFloor)
        floorNode.name = "shadowFloor"
        floorNode.position = SCNVector3(0, -0.001, 0)
        rootNode.addChildNode(floorNode)

        // Center the geometry so the anchor point is at the footprint midpoint.
        // convertToMeters already centers around (0,0), so the root is already
        // positioned with the deck centered at the origin. No additional offset needed.

        return rootNode
    }

    // MARK: - Deck Level

    /// Per-surface mesh + payload passed in when the caller wants
    /// each detected face to render with its own material/label rather
    /// than every face inheriting the legacy single-footprint material.
    /// DECK-NEW-1 follow-up.
    struct SurfaceMesh3D {
        let positionsInMeters: [CGPoint]
        let vertexIds: [String]   // ordered, matching positions
        let assignedItems: [AssignedItem]
        let color: String
        let boardMaterial: String
    }

    private static func buildDeckLevel(
        parent: SCNNode,
        vertices2D: [CGPoint],  // already in meters (XZ plane) — single-surface fallback
        edges: [DeckEdge],
        vertexPositionsInMetersById: [String: CGPoint],
        elevationM: Float,
        scaleFactor: Double,
        level: DeckLevel?,
        skipHouseWall: Bool = false,
        houseWallCapM: Float? = nil,  // bug fb007839 — wall cap on multi-level designs
        surfacesIn3D: [SurfaceMesh3D]? = nil  // DECK-NEW-1 — per-surface meshes + materials
    ) {
        let deckGroup = SCNNode()
        deckGroup.name = level.map { "deck_\($0.id)" } ?? "deck_main"

        // DECK-NEW-1 — build a surface mesh for EVERY detected face, each
        // with its own per-surface material/color. Falls back to the
        // all-vertices polygon when the caller didn't supply explicit
        // surfaces (single-loop legacy path).
        let surfaces = surfacesIn3D ?? [
            SurfaceMesh3D(
                positionsInMeters: vertices2D,
                vertexIds: [],
                assignedItems: [],
                color: "Brown",
                boardMaterial: "composite"
            )
        ]
        let visibleRimJoistEdgeIds = surfacesIn3D.map {
            DeckSurfaceEdgeResolver.visibleRimJoistEdgeIds(edges: edges, surfaces: $0)
        }
        // Multi-level designs tint each surface with its level's display
        // color so the levels read as visually distinct (bug 8f9c0280).
        let levelTint: UIColor? = level.map { lvl in
            let c = lvl.displayColor.fillColor
            return UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
        }
        for surf in surfaces {
            guard let surfaceGeo = DeckMeshGenerator.createPolygonGeometry(vertices: surf.positionsInMeters, yHeight: elevationM) else { continue }
            surfaceGeo.firstMaterial = surfaceMaterial(for: surf, levelColor: levelTint)
            let surfaceNode = SCNNode(geometry: surfaceGeo)
            surfaceNode.name = "deckSurface"
            deckGroup.addChildNode(surfaceNode)
        }

        // Railing and stairs per edge
        for edge in edges {
            guard let startPt = vertexPositionsInMetersById[edge.startVertexId],
                  let endPt = vertexPositionsInMetersById[edge.endVertexId] else { continue }
            let startPos3D = SCNVector3(Float(startPt.x), elevationM, Float(startPt.y))
            let endPos3D = SCNVector3(Float(endPt.x), elevationM, Float(endPt.y))

            // Rim joists belong on detected-surface boundaries only. Drawing
            // every graph edge made shared interior and stray construction
            // edges read as deck perimeter lines outside the surface.
            if visibleRimJoistEdgeIds?.contains(edge.id) ?? true ||
                DeckSurfaceEdgeResolver.carriesVisible3DFeature(edge) {
                buildRimJoist(parent: deckGroup, start: startPos3D, end: endPos3D, deckElevationM: elevationM)
            }

            // Edge length in inches for post count
            let edgeLengthInches = edge.dimension ?? {
                let dx = Double(endPt.x - startPt.x)
                let dz = Double(endPt.y - startPt.y)
                return sqrt(dx * dx + dz * dz) / Double(inchesToMeters)
            }()

            // Railing / parapet. House edges cannot carry railing config; if
            // legacy data still has one, the view model strips it on edit and
            // the renderer ignores it here.
            if let railConfig = edge.railingConfig, edge.edgeType == .deckEdge {
                buildRailing(
                    parent: deckGroup,
                    start: startPos3D,
                    end: endPos3D,
                    edgeLengthInches: edgeLengthInches,
                    config: railConfig,
                    deckElevationM: elevationM
                )
            }

            // Stairs
            if let stairConfig = edge.stairConfig {
                buildStairs(
                    parent: deckGroup,
                    start: startPos3D,
                    end: endPos3D,
                    stairConfig: stairConfig,
                    deckElevationM: elevationM,
                    scaleFactor: scaleFactor,
                    polygon2DMeters: vertices2D
                )
            }

            // House wall — driven by the edge's cladding material so house
            // edges render with the user-picked stucco/hardie/wood-vertical
            // tone instead of always-gray. Bug 3d72ce0b.
            if !skipHouseWall && edge.edgeType == .houseEdge {
                buildHouseWall(
                    parent: deckGroup,
                    start: startPos3D,
                    end: endPos3D,
                    deckElevationM: elevationM,
                    maxHeightM: houseWallCapM,
                    material: edge.houseEdgeMaterial
                )
            }
        }

        parent.addChildNode(deckGroup)
    }

    // MARK: - Railing

    private static func buildRailing(
        parent: SCNNode,
        start: SCNVector3,
        end: SCNVector3,
        edgeLengthInches: Double,
        config: RailingConfig,
        deckElevationM: Float
    ) {
        if config.railingType == .parapetWall {
            buildParapetWall(
                parent: parent,
                start: start,
                end: end,
                deckElevationM: deckElevationM,
                heightInches: config.postHeight,
                material: config.wallMaterial
            )
            return
        }

        let railGroup = SCNNode()
        railGroup.name = "railingGroup"

        let postCount = DimensionEngine.postCount(edgeLengthInches: edgeLengthInches, maxSpacing: config.maxPostSpacing)
        guard postCount >= 2 else { return }

        // Generate post positions along edge
        var postPositions: [SCNVector3] = []
        for i in 0..<postCount {
            let t = Float(i) / Float(postCount - 1)
            let x = start.x + (end.x - start.x) * t
            let z = start.z + (end.z - start.z) * t
            postPositions.append(SCNVector3(x, deckElevationM, z))
        }

        // Rail post uprights
        for (i, pos) in postPositions.enumerated() {
            let postNode = DeckMeshGenerator.createBox(
                position: SCNVector3(pos.x, pos.y + railHeightM / 2, pos.z),
                width: railPostSizeM,
                height: railHeightM,
                depth: railPostSizeM,
                material: makeMaterial(color: railPostColor, metalness: 0.3)
            )
            postNode.name = "railPost_\(i)"
            railGroup.addChildNode(postNode)
        }

        // Top rail spanning between posts
        for i in 0..<(postPositions.count - 1) {
            let p1 = postPositions[i]
            let p2 = postPositions[i + 1]
            let topRailNode = buildSpanningBox(
                from: p1, to: p2,
                yCenter: deckElevationM + railHeightM - topRailThicknessM / 2,
                width: railPostSizeM,
                height: topRailThicknessM,
                material: makeMaterial(color: topRailColor, metalness: 0.3)
            )
            topRailNode.name = "topRail_\(i)"
            railGroup.addChildNode(topRailNode)
        }

        // Bottom rail
        for i in 0..<(postPositions.count - 1) {
            let p1 = postPositions[i]
            let p2 = postPositions[i + 1]
            let bottomRailNode = buildSpanningBox(
                from: p1, to: p2,
                yCenter: deckElevationM + bottomRailOffsetM,
                width: railPostSizeM,
                height: topRailThicknessM,
                material: makeMaterial(color: topRailColor, metalness: 0.3)
            )
            bottomRailNode.name = "bottomRail_\(i)"
            railGroup.addChildNode(bottomRailNode)
        }

        // Railing panels (type-specific)
        for i in 0..<(postPositions.count - 1) {
            let p1 = postPositions[i]
            let p2 = postPositions[i + 1]
            buildRailingPanel(
                parent: railGroup,
                from: p1, to: p2,
                deckElevationM: deckElevationM,
                railingType: config.railingType,
                panelIndex: i
            )
        }

        parent.addChildNode(railGroup)
    }

    private static func buildParapetWall(
        parent: SCNNode,
        start: SCNVector3,
        end: SCNVector3,
        deckElevationM: Float,
        heightInches: Double,
        material: HouseEdgeMaterial
    ) {
        let heightM = Float(max(24.0, min(48.0, heightInches))) * inchesToMeters
        let wallNode = buildSpanningBox(
            from: start,
            to: end,
            yCenter: deckElevationM + heightM / 2,
            width: 0.10,
            height: heightM,
            material: makeMaterial(color: UIColor(hex: material.fillHex))
        )
        wallNode.name = "parapetWall"
        parent.addChildNode(wallNode)
    }

    private static func buildRailingPanel(
        parent: SCNNode,
        from p1: SCNVector3,
        to p2: SCNVector3,
        deckElevationM: Float,
        railingType: RailingType,
        panelIndex: Int
    ) {
        let dx = p2.x - p1.x
        let dz = p2.z - p1.z
        let spanLength = sqrt(dx * dx + dz * dz)
        let panelBottom = deckElevationM + bottomRailOffsetM + topRailThicknessM
        let panelTop = deckElevationM + railHeightM - topRailThicknessM
        let panelHeight = panelTop - panelBottom
        guard panelHeight > 0, spanLength > 0 else { return }

        switch railingType {
        case .parapetWall:
            return
        case .glass:
            // Transparent blue panel
            let panelNode = buildSpanningBox(
                from: p1, to: p2,
                yCenter: panelBottom + panelHeight / 2,
                width: 0.01, // thin glass
                height: panelHeight,
                material: makeMaterial(color: glassPanelColor, transparency: 0.2)
            )
            panelNode.name = "glassPanel_\(panelIndex)"
            parent.addChildNode(panelNode)

        case .picket:
            // Vertical pickets at 4" spacing
            let spacingM = 4.0 * Float(inchesToMeters)
            let picketWidthM: Float = 1.0 * Float(inchesToMeters) // 1" wide
            let count = Int(spanLength / spacingM)
            for j in 0...count {
                let t = Float(j) / Float(max(count, 1))
                let x = p1.x + dx * t
                let z = p1.z + dz * t
                let picket = DeckMeshGenerator.createBox(
                    position: SCNVector3(x, panelBottom + panelHeight / 2, z),
                    width: picketWidthM,
                    height: panelHeight,
                    depth: picketWidthM,
                    material: makeMaterial(color: picketColor)
                )
                picket.name = "picket_\(panelIndex)_\(j)"
                parent.addChildNode(picket)
            }

        case .cable:
            // Horizontal cables at 3" spacing
            let spacingM = 3.0 * Float(inchesToMeters)
            let cableRadius: Float = 0.003 // ~3mm cable
            let count = Int(panelHeight / spacingM)
            for j in 0...count {
                let y = panelBottom + Float(j) * spacingM
                if y > panelTop { break }
                let cableNode = buildSpanningBox(
                    from: p1, to: p2,
                    yCenter: y,
                    width: cableRadius * 2,
                    height: cableRadius * 2,
                    material: makeMaterial(color: cableColor)
                )
                cableNode.name = "cable_\(panelIndex)_\(j)"
                parent.addChildNode(cableNode)
            }

        case .horizontal:
            // Horizontal slats at 4" spacing
            let spacingM = 4.0 * Float(inchesToMeters)
            let slatHeightM: Float = 1.5 * Float(inchesToMeters) // 1.5" thick slat
            let count = Int(panelHeight / spacingM)
            for j in 0...count {
                let y = panelBottom + Float(j) * spacingM
                if y > panelTop { break }
                let slatNode = buildSpanningBox(
                    from: p1, to: p2,
                    yCenter: y,
                    width: slatHeightM,
                    height: slatHeightM,
                    material: makeMaterial(color: picketColor)
                )
                slatNode.name = "hSlat_\(panelIndex)_\(j)"
                parent.addChildNode(slatNode)
            }

        case .wood:
            // Thick pickets (2" wide) at 4" spacing
            let spacingM = 4.0 * Float(inchesToMeters)
            let picketWidthM: Float = 2.0 * Float(inchesToMeters)
            let count = Int(spanLength / spacingM)
            for j in 0...count {
                let t = Float(j) / Float(max(count, 1))
                let x = p1.x + dx * t
                let z = p1.z + dz * t
                let picket = DeckMeshGenerator.createBox(
                    position: SCNVector3(x, panelBottom + panelHeight / 2, z),
                    width: picketWidthM,
                    height: panelHeight,
                    depth: picketWidthM,
                    material: makeMaterial(color: postColor) // wood-colored thick pickets
                )
                picket.name = "woodPicket_\(panelIndex)_\(j)"
                parent.addChildNode(picket)
            }
        }
    }

    // MARK: - Stairs

    /// Orientation for a stair stringer modelled as an `SCNBox` (local axes:
    /// X = 2" width, Y = 10" depth, Z = slope length). Maps the box's length
    /// down the rise/run slope and its width along the stair edge, built from
    /// an explicit orthonormal basis so it is correct for ANY edge bearing and
    /// any `flipDirection`/polygon-aware outward normal. The previous approach
    /// set `eulerAngles.y` then `eulerAngles.x`, which pitched the slope about
    /// the world X axis and only lined up when the edge ran along world X —
    /// every rotated stair came out skewed.
    /// - Parameters:
    ///   - tangent: unit edge tangent (x, z) — where the box width lands.
    ///   - outwardNormal: unit outward direction (x, z) the stair runs toward.
    ///   - slopeAngle: stair pitch from horizontal, `atan2(totalRise, totalRun)`.
    static func stringerOrientation(
        tangent: SIMD2<Float>,
        outwardNormal: SIMD2<Float>,
        slopeAngle: Float
    ) -> simd_quatf {
        let c = cos(slopeAngle)
        let s = sin(slopeAngle)
        let xAxis = SIMD3<Float>(tangent.x, 0, tangent.y)                       // width → along edge
        let zAxis = SIMD3<Float>(outwardNormal.x * c, -s, outwardNormal.y * c)  // length → down the slope
        let yAxis = simd_normalize(simd_cross(zAxis, xAxis))                    // depth → slope-face normal
        return simd_quatf(simd_float3x3(columns: (xAxis, yAxis, zAxis)))
    }

    private static func buildStairs(
        parent: SCNNode,
        start: SCNVector3,
        end: SCNVector3,
        stairConfig: StairConfig,
        deckElevationM: Float,
        scaleFactor: Double,
        polygon2DMeters: [CGPoint] = []
    ) {
        let stairGroup = SCNNode()
        stairGroup.name = "stairGroup"

        // Use the stored total rise (set in StairConfigView) when available so
        // the 3D rise matches what the user explicitly configured. Fall back to
        // the deck elevation when the stair-specific value isn't stored. Bug 8.
        let totalRiseInches: Double
        if let stored = stairConfig.totalRiseInches, stored > 0 {
            totalRiseInches = stored
        } else {
            totalRiseInches = Double(deckElevationM) / Double(inchesToMeters)
        }
        let treadCount = stairConfig.treadCount ?? StairConfig.calculateTreadCount(totalRise: totalRiseInches, risePerStep: stairConfig.risePerStep)
        guard treadCount > 0 else { return }

        let totalRiseMFromConfig = Float(totalRiseInches) * inchesToMeters
        let risePerStepM = totalRiseMFromConfig / Float(treadCount)
        let runPerTreadM = Float(stairConfig.runPerTread) * inchesToMeters
        let stairWidthM = Float(stairConfig.width) * inchesToMeters

        // Direction vector perpendicular to edge (outward from deck)
        let edgeDx = end.x - start.x
        let edgeDz = end.z - start.z
        let edgeLen = sqrt(edgeDx * edgeDx + edgeDz * edgeDz)
        guard edgeLen > 0 else { return }

        // Edge tangent (for stair width)
        let tx = edgeDx / edgeLen
        let tz = edgeDz / edgeLen

        // Outward perpendicular — same polygon-aware logic as 2D so 3D stairs
        // also land OPPOSITE the filled deck surface by default. Falls back
        // to the historic CCW perpendicular when the polygon isn't supplied
        // (open sketches, AR builds with skipHouseWall). Bug a7429390.
        let rawN: (x: Float, z: Float)
        if polygon2DMeters.count >= 3 {
            let outward = PolygonMath.outwardPerpendicular(
                edgeStart: CGPoint(x: CGFloat(start.x), y: CGFloat(start.z)),
                edgeEnd: CGPoint(x: CGFloat(end.x), y: CGFloat(end.z)),
                polygonVertices: polygon2DMeters
            )
            rawN = (x: Float(outward.x), z: Float(outward.y))
        } else {
            rawN = (x: -edgeDz / edgeLen, z: edgeDx / edgeLen)
        }
        let nx = stairConfig.flipDirection ? -rawN.x : rawN.x
        let nz = stairConfig.flipDirection ? -rawN.z : rawN.z

        // Position the stair along the edge using alignment + offset, matching
        // the 2D canvas logic. Bug 8 — 3D previously always centred on the
        // edge midpoint, ignoring alignment and offset settings.
        let stairWidthLimited = min(stairWidthM, edgeLen)
        let gapTotal = edgeLen - stairWidthLimited
        let offsetM = Float(stairConfig.offset) * inchesToMeters
        let stairStartT: Float  // fraction along edge where stair begins
        switch stairConfig.alignment {
        case .left:
            stairStartT = offsetM / edgeLen
        case .center:
            stairStartT = (gapTotal / 2 + offsetM) / edgeLen
        case .right:
            stairStartT = (gapTotal - offsetM) / edgeLen
        }
        let stairBaseX = start.x + tx * edgeLen * stairStartT
        let stairBaseZ = start.z + tz * edgeLen * stairStartT
        let midX = stairBaseX + tx * stairWidthLimited / 2
        let midZ = stairBaseZ + tz * stairWidthLimited / 2

        // Treads
        for i in 0..<treadCount {
            let stepOffset = Float(i + 1)
            let y = deckElevationM - stepOffset * risePerStepM
            let outward = stepOffset * runPerTreadM
            let cx = midX + nx * outward
            let cz = midZ + nz * outward

            // Tread: box oriented along edge direction; width clamped to edge.
            let treadNode = SCNNode(geometry: SCNBox(
                width: CGFloat(stairWidthLimited),
                height: CGFloat(treadThicknessM),
                length: CGFloat(runPerTreadM),
                chamferRadius: 0
            ))
            treadNode.geometry?.firstMaterial = makeMaterial(color: stairTreadColor)
            treadNode.position = SCNVector3(cx, y, cz)

            // Rotate tread to align with edge
            let angle = atan2(edgeDz, edgeDx)
            treadNode.eulerAngles.y = -angle
            treadNode.name = "tread_\(i)"
            stairGroup.addChildNode(treadNode)
        }

        // Stringers (angled beams on each side)
        let stringerCount = StairConfig.stringerCount(width: stairConfig.width)
        let totalRunM = Float(treadCount) * runPerTreadM
        // Use the config rise (not just deckElevationM) so the stringer angle
        // matches the actual tread geometry. Bug 8.
        let stringerLengthM = sqrt(totalRiseMFromConfig * totalRiseMFromConfig + totalRunM * totalRunM)
        let stringerAngle = atan2(totalRiseMFromConfig, totalRunM)
        let stringerWidthM: Float = 2.0 * inchesToMeters  // 2" wide stringer
        let stringerDepthM: Float = 10.0 * inchesToMeters  // 10" deep stringer

        // One orientation for every stringer on this run: length follows the
        // rise/run slope, width lies along the stair edge — correct for any
        // edge bearing (see `stringerOrientation`).
        let stringerQ = stringerOrientation(
            tangent: SIMD2<Float>(tx, tz),
            outwardNormal: SIMD2<Float>(nx, nz),
            slopeAngle: stringerAngle
        )
        // Seat each board so its top face meets the tread nosing line instead
        // of straddling it: drop the center half a board-depth down the
        // slope-face normal (local +Y).
        let stringerUp = stringerQ.act(SIMD3<Float>(0, 1, 0))
        let seatOffset = -stringerDepthM / 2

        for s in 0..<stringerCount {
            let t = Float(s) / Float(max(stringerCount - 1, 1))
            let lateralOffset = stairWidthLimited * (t - 0.5)

            // Midway down the slope, offset to its side of the stair, seated
            // under the treads.
            let centerOutward = totalRunM / 2
            let centerY = deckElevationM - totalRiseMFromConfig / 2
            let sx = midX + nx * centerOutward + tx * lateralOffset + stringerUp.x * seatOffset
            let sy = centerY + stringerUp.y * seatOffset
            let sz = midZ + nz * centerOutward + tz * lateralOffset + stringerUp.z * seatOffset

            let stringerNode = SCNNode(geometry: SCNBox(
                width: CGFloat(stringerWidthM),
                height: CGFloat(stringerDepthM),
                length: CGFloat(stringerLengthM),
                chamferRadius: 0
            ))
            stringerNode.geometry?.firstMaterial = makeMaterial(color: stringerColor)
            stringerNode.position = SCNVector3(sx, sy, sz)
            stringerNode.simdOrientation = stringerQ
            stringerNode.name = "stringer_\(s)"
            stairGroup.addChildNode(stringerNode)
        }

        // Stair railing (if configured)
        if let railConfig = stairConfig.railingConfig {
            buildStairRailing(
                parent: stairGroup,
                midX: midX, midZ: midZ,
                nx: nx, nz: nz, tx: tx, tz: tz,
                stairWidthM: stairWidthM,
                deckElevationM: deckElevationM,
                treadCount: treadCount,
                risePerStepM: risePerStepM,
                runPerTreadM: runPerTreadM,
                config: railConfig
            )
        }

        parent.addChildNode(stairGroup)
    }

    // MARK: - Stair Railing

    private static func buildStairRailing(
        parent: SCNNode,
        midX: Float, midZ: Float,
        nx: Float, nz: Float,
        tx: Float, tz: Float,
        stairWidthM: Float,
        deckElevationM: Float,
        treadCount: Int,
        risePerStepM: Float,
        runPerTreadM: Float,
        config: RailingConfig
    ) {
        // Railing on both sides of the stairs, following the slope
        for side in [-1, 1] as [Float] {
            let lateralOffset = stairWidthM / 2 * side

            // Generate post positions at top, each tread, and bottom
            var postPositions: [SCNVector3] = []

            // Top post (at deck edge)
            postPositions.append(SCNVector3(
                midX + tx * lateralOffset,
                deckElevationM,
                midZ + tz * lateralOffset
            ))

            // Posts at selected tread intervals (every 2-3 treads)
            let postInterval = max(1, treadCount / 3)
            for i in stride(from: postInterval, through: treadCount, by: postInterval) {
                let stepOffset = Float(i)
                let y = deckElevationM - stepOffset * risePerStepM
                let outward = stepOffset * runPerTreadM
                postPositions.append(SCNVector3(
                    midX + nx * outward + tx * lateralOffset,
                    y,
                    midZ + nz * outward + tz * lateralOffset
                ))
            }

            // Bottom post (at ground)
            let bottomY = deckElevationM - Float(treadCount) * risePerStepM
            let bottomOutward = Float(treadCount) * runPerTreadM
            let lastPost = SCNVector3(
                midX + nx * bottomOutward + tx * lateralOffset,
                bottomY,
                midZ + nz * bottomOutward + tz * lateralOffset
            )
            if postPositions.last?.x != lastPost.x || postPositions.last?.z != lastPost.z {
                postPositions.append(lastPost)
            }

            // Rail post uprights at each position
            for (i, pos) in postPositions.enumerated() {
                let postNode = DeckMeshGenerator.createBox(
                    position: SCNVector3(pos.x, pos.y + railHeightM / 2, pos.z),
                    width: railPostSizeM,
                    height: railHeightM,
                    depth: railPostSizeM,
                    material: makeMaterial(color: railPostColor, metalness: 0.3)
                )
                postNode.name = "stairRailPost_\(side)_\(i)"
                parent.addChildNode(postNode)
            }

            // Top rail connecting posts along slope
            for i in 0..<(postPositions.count - 1) {
                let p1 = postPositions[i]
                let p2 = postPositions[i + 1]
                let topRailY1 = p1.y + railHeightM - topRailThicknessM / 2
                let topRailY2 = p2.y + railHeightM - topRailThicknessM / 2
                let railMidY = (topRailY1 + topRailY2) / 2
                let topRailNode = buildSpanningBox(
                    from: SCNVector3(p1.x, railMidY, p1.z),
                    to: SCNVector3(p2.x, railMidY, p2.z),
                    yCenter: railMidY,
                    width: railPostSizeM,
                    height: topRailThicknessM,
                    material: makeMaterial(color: topRailColor, metalness: 0.3)
                )
                topRailNode.name = "stairTopRail_\(side)_\(i)"
                parent.addChildNode(topRailNode)
            }
        }
    }

    // MARK: - Level Connections

    private static func buildLevelConnection(
        parent: SCNNode,
        connection: LevelConnection,
        drawingData: DeckDrawingData,
        scaleFactor: Double
    ) {
        // Resolve each level's height through the same ladder the surfaces use
        // (explicit → per-vertex → stair → staggered) rather than raw
        // `level.elevation`. Saved multi-level designs leave `elevation` nil on
        // every level, which previously made the connecting stairs vanish even
        // though the level surfaces still rendered at their resolved heights.
        guard let upperLevel = drawingData.level(byId: connection.upperLevelId),
              let upperElev = drawingData.resolvedElevationFeet(forLevelId: connection.upperLevelId),
              let lowerElev = drawingData.resolvedElevationFeet(forLevelId: connection.lowerLevelId) else { return }

        guard let upperEdge = upperLevel.edge(byId: connection.upperEdgeId) else { return }

        let upperVertices = convertToMeters(vertices: upperLevel.orderedPositions, scaleFactor: scaleFactor)
        guard let startIdx = upperLevel.vertices.firstIndex(where: { $0.id == upperEdge.startVertexId }),
              let endIdx = upperLevel.vertices.firstIndex(where: { $0.id == upperEdge.endVertexId }),
              startIdx < upperVertices.count, endIdx < upperVertices.count else { return }

        let upperElevM = Float(upperElev) * feetToMeters
        let lowerElevM = Float(lowerElev) * feetToMeters
        let riseDiffM = upperElevM - lowerElevM
        guard riseDiffM > 0 else { return }

        let startPt = upperVertices[startIdx]
        let endPt = upperVertices[endIdx]
        let start3D = SCNVector3(Float(startPt.x), upperElevM, Float(startPt.y))
        let end3D = SCNVector3(Float(endPt.x), upperElevM, Float(endPt.y))

        // Build stairs for this connection using the stair config
        let connectionGroup = SCNNode()
        connectionGroup.name = "levelConnection_\(connection.id)"

        let treadCount = connection.stairConfig.treadCount ?? StairConfig.calculateTreadCount(
            totalRise: Double(riseDiffM) / Double(inchesToMeters),
            risePerStep: connection.stairConfig.risePerStep
        )
        guard treadCount > 0 else { return }

        let risePerStepM = riseDiffM / Float(treadCount)
        let runPerTreadM = Float(connection.stairConfig.runPerTread) * inchesToMeters
        let stairWidthM = Float(connection.stairConfig.width) * inchesToMeters

        let edgeDx = end3D.x - start3D.x
        let edgeDz = end3D.z - start3D.z
        let edgeLen = sqrt(edgeDx * edgeDx + edgeDz * edgeDz)
        guard edgeLen > 0 else { return }

        let nx = -edgeDz / edgeLen
        let nz = edgeDx / edgeLen
        let tx = edgeDx / edgeLen
        let tz = edgeDz / edgeLen
        let midX = (start3D.x + end3D.x) / 2
        let midZ = (start3D.z + end3D.z) / 2

        // Treads
        for i in 0..<treadCount {
            let stepOffset = Float(i + 1)
            let y = upperElevM - stepOffset * risePerStepM
            let outward = stepOffset * runPerTreadM
            let cx = midX + nx * outward
            let cz = midZ + nz * outward

            let treadNode = SCNNode(geometry: SCNBox(
                width: CGFloat(stairWidthM),
                height: CGFloat(treadThicknessM),
                length: CGFloat(runPerTreadM),
                chamferRadius: 0
            ))
            treadNode.geometry?.firstMaterial = makeMaterial(color: stairTreadColor)
            treadNode.position = SCNVector3(cx, y, cz)
            let angle = atan2(edgeDz, edgeDx)
            treadNode.eulerAngles.y = -angle
            treadNode.name = "connTread_\(i)"
            connectionGroup.addChildNode(treadNode)
        }

        // Stringers
        let totalRunM = Float(treadCount) * runPerTreadM
        let stringerLengthM = sqrt(riseDiffM * riseDiffM + totalRunM * totalRunM)
        let stringerAngle = atan2(riseDiffM, totalRunM)
        let stringerWidthM: Float = 2.0 * inchesToMeters
        let stringerDepthM: Float = 10.0 * inchesToMeters
        let stringerCountVal = StairConfig.stringerCount(width: connection.stairConfig.width)

        // Same correct, edge-bearing-independent orientation + seating as
        // edge-attached stairs (see `buildStairs`).
        let stringerQ = stringerOrientation(
            tangent: SIMD2<Float>(tx, tz),
            outwardNormal: SIMD2<Float>(nx, nz),
            slopeAngle: stringerAngle
        )
        let stringerUp = stringerQ.act(SIMD3<Float>(0, 1, 0))
        let seatOffset = -stringerDepthM / 2

        for s in 0..<stringerCountVal {
            let t = Float(s) / Float(max(stringerCountVal - 1, 1))
            let lateralOffset = stairWidthM * (t - 0.5)

            let centerOutward = totalRunM / 2
            let centerY = upperElevM - riseDiffM / 2
            let sx = midX + nx * centerOutward + tx * lateralOffset + stringerUp.x * seatOffset
            let sy = centerY + stringerUp.y * seatOffset
            let sz = midZ + nz * centerOutward + tz * lateralOffset + stringerUp.z * seatOffset

            let stringerNode = SCNNode(geometry: SCNBox(
                width: CGFloat(stringerWidthM),
                height: CGFloat(stringerDepthM),
                length: CGFloat(stringerLengthM),
                chamferRadius: 0
            ))
            stringerNode.geometry?.firstMaterial = makeMaterial(color: stringerColor)
            stringerNode.position = SCNVector3(sx, sy, sz)
            stringerNode.simdOrientation = stringerQ
            stringerNode.name = "connStringer_\(s)"
            connectionGroup.addChildNode(stringerNode)
        }

        // Stair railing on level connection (if configured)
        if let railConfig = connection.stairConfig.railingConfig {
            buildStairRailing(
                parent: connectionGroup,
                midX: midX, midZ: midZ,
                nx: nx, nz: nz, tx: tx, tz: tz,
                stairWidthM: stairWidthM,
                deckElevationM: upperElevM,
                treadCount: treadCount,
                risePerStepM: risePerStepM,
                runPerTreadM: runPerTreadM,
                config: railConfig
            )
        }

        parent.addChildNode(connectionGroup)
    }

    // MARK: - House Wall

    private static func buildHouseWall(
        parent: SCNNode,
        start: SCNVector3,
        end: SCNVector3,
        deckElevationM: Float,
        maxHeightM: Float? = nil,
        material: HouseEdgeMaterial? = nil
    ) {
        // The wall rises from the deck surface upward (not from the ground)
        // so house edges read as a wall section the deck attaches to.
        //
        // Bug fb007839 — the wall is 8' tall by default, but on a
        // multi-level design `maxHeightM` carries the gap up to the next
        // level: the wall is capped there so it stops at the underside of
        // the deck above instead of spearing through it. This supersedes
        // bug a40556a7, which had fixed the wall height at 9'.
        let wallHeight = maxHeightM.map { min(houseWallHeightM, $0) } ?? houseWallHeightM
        guard wallHeight > 0 else { return }
        let wallBottom = deckElevationM
        let wallTop = deckElevationM + wallHeight

        // Bug 3d72ce0b — cladding material drives wall color. Stucco / hardie
        // / wood-vertical map to their `fillHex` tone (defined on the enum);
        // unset edges fall back to the neutral gray so legacy designs still
        // render.
        let wallColor: UIColor = {
            guard let mat = material else { return houseWallColor }
            return UIColor(hex: mat.fillHex)
        }()

        let wallNode = buildSpanningBox(
            from: start, to: end,
            yCenter: (wallBottom + wallTop) / 2,
            width: 0.05, // 2" thick wall representation
            height: wallHeight,
            material: makeMaterial(color: wallColor)
        )
        wallNode.name = "houseWall"
        parent.addChildNode(wallNode)
    }

    // MARK: - Rim Joist

    /// A rim joist runs the deck perimeter directly under the deck boards.
    /// The calibrated path previously drew no edge framing at all, so the
    /// deck surface read as a floating slab; this adds a proper joist beneath
    /// the surface for realism and to match the DeckTab3DView fallback, which
    /// now also seats its edge beam below the surface (bug 313aad41).
    private static func buildRimJoist(
        parent: SCNNode,
        start: SCNVector3,
        end: SCNVector3,
        deckElevationM: Float
    ) {
        let depthM: Float = 7.25 * inchesToMeters   // 2x8 rim joist
        let thicknessM: Float = 1.5 * inchesToMeters
        let joist = buildSpanningBox(
            from: start, to: end,
            yCenter: deckElevationM - depthM / 2,  // top of joist flush with the deck surface
            width: thicknessM,
            height: depthM,
            material: makeMaterial(color: stringerColor)
        )
        joist.name = "rimJoist"
        parent.addChildNode(joist)
    }

    // MARK: - Ground Plane

    private static func addGroundPlane(to scene: SCNScene) {
        let ground = SCNPlane(width: 30, height: 30)
        ground.firstMaterial = makeMaterial(color: groundColor)
        ground.firstMaterial?.isDoubleSided = true
        let groundNode = SCNNode(geometry: ground)
        groundNode.eulerAngles.x = -.pi / 2  // Lie flat
        groundNode.position = SCNVector3(0, -0.001, 0) // Slightly below zero to avoid z-fighting
        groundNode.name = "groundPlane"
        scene.rootNode.addChildNode(groundNode)
    }

    // MARK: - Lighting

    private static func addLighting(to scene: SCNScene) {
        // Ambient
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor.white
        ambientLight.intensity = 400
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        ambientNode.name = "ambientLight"
        scene.rootNode.addChildNode(ambientNode)

        // Directional (sun-like)
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.color = UIColor.white
        directionalLight.intensity = 800
        directionalLight.castsShadow = true
        directionalLight.shadowMode = .deferred
        directionalLight.shadowRadius = 3
        directionalLight.shadowMapSize = CGSize(width: 1024, height: 1024)
        let directionalNode = SCNNode()
        directionalNode.light = directionalLight
        directionalNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0) // From above-left
        directionalNode.name = "directionalLight"
        scene.rootNode.addChildNode(directionalNode)
    }

    // MARK: - Camera

    private static func addCamera(
        to scene: SCNScene,
        fitting positions: [CGPoint],
        scaleFactor: Double,
        drawingData: DeckDrawingData,
        center: CGPoint? = nil
    ) {
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.fieldOfView = 60

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"

        // Calculate bounding box center in meters
        let metersPositions: [CGPoint]
        if let center {
            metersPositions = convertToMeters(vertices: positions, scaleFactor: scaleFactor, center: center)
        } else {
            metersPositions = convertToMeters(vertices: positions, scaleFactor: scaleFactor)
        }
        let bounds = DeckMeshGenerator.boundingRect(for: metersPositions)
        let centerX = Float(bounds.midX)
        let centerZ = Float(bounds.midY)
        let avgElevation: Float = {
            if drawingData.isMultiLevel {
                let elevations = drawingData.levels.enumerated().map { index, level in
                    drawingData.renderElevationFeet(for: level, levelIndex: index)
                }
                guard !elevations.isEmpty else { return Float(2.5) * feetToMeters }
                return Float(elevations.reduce(0, +) / Double(elevations.count)) * feetToMeters
            }
            return Float(drawingData.renderElevationFeetSingleLevel) * feetToMeters
        }()

        // Distance to frame entire deck with 20% margin
        let maxSpan = max(Float(bounds.width), Float(bounds.height)) * 1.2
        let distance = max(maxSpan * 2.0, 3.0) // minimum 3m

        // Default: azimuth 225°, elevation 35°
        let azimuthRad = Float(225.0) * .pi / 180.0
        let elevationRad = Float(35.0) * .pi / 180.0

        let camX = centerX + distance * cos(elevationRad) * sin(azimuthRad)
        let camY = avgElevation + distance * sin(elevationRad)
        let camZ = centerZ + distance * cos(elevationRad) * cos(azimuthRad)

        cameraNode.position = SCNVector3(camX, camY, camZ)

        // Look at the deck center
        let lookAt = SCNVector3(centerX, avgElevation, centerZ)
        cameraNode.look(at: lookAt)

        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - Stair Camera Bounds

    private static func stairFramePositions(
        edges: [DeckEdge],
        vertices: [DeckVertex],
        polygonVertices: [CGPoint],
        scaleFactor: Double,
        measurementSystem: MeasurementSystem
    ) -> [CGPoint] {
        guard scaleFactor > 0 else { return [] }
        let verticesById = Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0.position) })

        return edges.flatMap { edge -> [CGPoint] in
            guard let config = edge.stairConfig,
                  let start = verticesById[edge.startVertexId],
                  let end = verticesById[edge.endVertexId] else {
                return []
            }
            let treadCount = config.treadCount ?? StairConfig.calculateTreadCount(
                totalRise: config.totalRiseInches ?? 30,
                risePerStep: config.risePerStep
            )
            guard treadCount > 0,
                  let plan = DeckStairRenderPlanner.plan(
                    edgeStart: start,
                    edgeEnd: end,
                    polygonVertices: polygonVertices,
                    config: config,
                    treadCount: treadCount,
                    scaleFactor: scaleFactor,
                    measurementSystem: measurementSystem
                  ) else {
                return []
            }
            return plan.framePoints
        }
    }

    // MARK: - Materials

    private static let boardTexture: UIImage = generateBoardTexture()

    private static func deckSurfaceMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = boardTexture
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.roughness.contents = 0.7
        material.isDoubleSided = true
        return material
    }

    /// Looks up the persisted `DeckSurface` presentation matching a detected
    /// face — by exact vertex set first, then by best-Jaccard fallback — so
    /// per-surface materials survive vertex edits the same way
    /// `SurfaceReconciler` matches them in the data layer.
    private static func resolvedSurfacePresentation(
        for detected: DetectedSurface,
        in persisted: [DeckSurface]
    ) -> (assignedItems: [AssignedItem], color: String, boardMaterial: String) {
        let dSet = Set(detected.vertexIds)
        if let exact = persisted.first(where: { $0.vertexIds == dSet }) {
            return (exact.assignedItems, exact.color, exact.boardMaterial)
        }
        var best: (surface: DeckSurface, jaccard: Double)? = nil
        for p in persisted {
            let intersection = dSet.intersection(p.vertexIds).count
            let union = dSet.union(p.vertexIds).count
            guard union > 0 else { continue }
            let jaccard = Double(intersection) / Double(union)
            if jaccard > (best?.jaccard ?? -1) {
                best = (p, jaccard)
            }
        }
        if let match = best, match.jaccard >= SurfaceReconciler.rebindThreshold {
            return (match.surface.assignedItems, match.surface.color, match.surface.boardMaterial)
        }
        return ([], "Brown", "composite")
    }

    /// Per-surface material. Board-like materials keep the deck board texture;
    /// slab/paver surfaces render flatter so the project details 3D view does
    /// not make every surface read as cedar boards.
    private static func surfaceMaterial(for surface: SurfaceMesh3D, levelColor: UIColor?) -> SCNMaterial {
        // Multi-level designs color-code each surface by its level's display
        // color so levels are visually distinguishable in the 3D scene
        // (bug 8f9c0280). Single-level designs (levelColor == nil) fall
        // through to the board-material texture + tint treatment below.
        if let levelColor {
            let material = SCNMaterial()
            material.diffuse.contents = levelColor
            material.roughness.contents = 0.7
            material.isDoubleSided = true
            return material
        }

        let key = surface.boardMaterial
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let material = SCNMaterial()
        let taskTint = surface.assignedItems.first?.taskTypeColor
            .flatMap { $0.hasPrefix("#") ? UIColor(hex: $0) : nil }

        if key.contains("concrete") {
            material.diffuse.contents = taskTint ?? UIColor(red: 126/255, green: 128/255, blue: 124/255, alpha: 1)
            material.roughness.contents = 0.95
            material.isDoubleSided = true
            return material
        }

        if key.contains("paver") {
            material.diffuse.contents = taskTint ?? UIColor(red: 142/255, green: 125/255, blue: 104/255, alpha: 1)
            material.roughness.contents = 0.9
            material.isDoubleSided = true
            return material
        }

        material.diffuse.contents = boardTexture
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.intensity = key.contains("pvc") ? 0.82 : 0.65
        let surfaceTint = surface.color.hasPrefix("#") ? UIColor(hex: surface.color) : nil
        material.multiply.contents = taskTint ?? surfaceTint ?? boardMaterialTint(for: key)
        material.multiply.intensity = 0.55
        material.roughness.contents = key.contains("pvc") ? 0.55 : 0.7
        material.isDoubleSided = true
        return material
    }

    private static func boardMaterialTint(for key: String) -> UIColor {
        if key.contains("pvc") { return UIColor(red: 212/255, green: 211/255, blue: 204/255, alpha: 1) }
        if key.contains("cedar") { return UIColor(red: 190/255, green: 128/255, blue: 74/255, alpha: 1) }
        if key.contains("treated") { return UIColor(red: 139/255, green: 150/255, blue: 112/255, alpha: 1) }
        if key.contains("hardwood") || key.contains("ipe") { return UIColor(red: 101/255, green: 61/255, blue: 40/255, alpha: 1) }
        return UIColor(red: 170/255, green: 130/255, blue: 90/255, alpha: 1)
    }

    static func generateBoardTexture(boardWidthMeters: Float = 0.14) -> UIImage {
        // 0.14m ~ 5.5" board width
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Fill with base cedar color
            UIColor(red: 196/255, green: 149/255, blue: 106/255, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // Draw board lines (darker, thinner)
            UIColor(red: 160/255, green: 120/255, blue: 80/255, alpha: 0.5).setStroke()
            let lineSpacing = size.width / 8 // 8 boards across the texture
            for i in 1..<8 {
                let x = CGFloat(i) * lineSpacing
                ctx.cgContext.move(to: CGPoint(x: x, y: 0))
                ctx.cgContext.addLine(to: CGPoint(x: x, y: size.height))
            }
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.strokePath()
        }
    }

    private static func makeMaterial(
        color: UIColor,
        metalness: Float = 0,
        transparency: Float = 1.0
    ) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        if metalness > 0 {
            mat.metalness.contents = metalness
        }
        if transparency < 1.0 {
            mat.transparency = CGFloat(transparency)
            mat.isDoubleSided = true
        }
        return mat
    }

    // MARK: - Coordinate Conversion

    /// Convert 2D canvas positions to meters in XZ plane, centered at origin.
    /// Self-centering convenience overload — derives the centroid from the
    /// input bounding box. **Do not use** when multiple polygons share a
    /// scene: every call re-centers to its OWN bbox, so two surfaces would
    /// stack at the same origin in 3D (bug bc9109ef). Use the explicit
    /// `center` overload instead and share one centroid across all polygons.
    static func convertToMeters(vertices: [CGPoint], scaleFactor: Double) -> [CGPoint] {
        guard !vertices.isEmpty else { return [] }
        let bounds = DeckMeshGenerator.boundingRect(for: vertices)
        return convertToMeters(
            vertices: vertices,
            scaleFactor: scaleFactor,
            center: CGPoint(x: bounds.midX, y: bounds.midY)
        )
    }

    /// Shared-frame conversion — every polygon in a multi-surface scene
    /// must pass the SAME `center` so faces, posts, and edges line up. Bug
    /// bc9109ef: the legacy self-centering form caused each detected
    /// surface to render around its own origin, so multi-shape designs
    /// drew every footprint stacked on top of each other.
    static func convertToMeters(
        vertices: [CGPoint],
        scaleFactor: Double,
        center: CGPoint
    ) -> [CGPoint] {
        guard !vertices.isEmpty else { return [] }
        let metersPerCanvasPoint = 1.0 / scaleFactor / Double(39.3701)
        let centerX = Double(center.x)
        let centerY = Double(center.y)
        return vertices.map { v in
            CGPoint(
                x: (Double(v.x) - centerX) * metersPerCanvasPoint,
                y: (Double(v.y) - centerY) * metersPerCanvasPoint
            )
        }
    }

    private static func vertexPositionMap(
        vertices: [DeckVertex],
        scaleFactor: Double,
        center: CGPoint
    ) -> [String: CGPoint] {
        Dictionary(
            uniqueKeysWithValues: vertices.map {
                ($0.id, convertPointToMeters($0.position, scaleFactor: scaleFactor, center: center))
            }
        )
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

    // MARK: - Spanning Box Helper

    /// Create a box that spans between two 3D points at a given Y center
    private static func buildSpanningBox(
        from p1: SCNVector3,
        to p2: SCNVector3,
        yCenter: Float,
        width: Float,
        height: Float,
        material: SCNMaterial
    ) -> SCNNode {
        let dx = p2.x - p1.x
        let dz = p2.z - p1.z
        let length = sqrt(dx * dx + dz * dz)

        let box = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0)
        box.firstMaterial = material

        let node = SCNNode(geometry: box)
        node.position = SCNVector3(
            (p1.x + p2.x) / 2,
            yCenter,
            (p1.z + p2.z) / 2
        )

        let angle = atan2(dx, dz)
        node.eulerAngles.y = angle

        return node
    }
}
