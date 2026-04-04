// OPS/OPS/DeckBuilder/3D/DeckSceneBuilder.swift

import Foundation
import SceneKit
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
    private static let postSizeM: Float = 4.0 * inchesToMeters       // 4" square post
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

        if drawingData.isMultiLevel {
            for level in drawingData.levels where level.isClosed {
                let metersVerts = convertToMeters(vertices: level.orderedPositions, scaleFactor: scaleFactor)
                allPositions.append(contentsOf: level.orderedPositions)
                let elevationFeet = level.elevation ?? 2.5
                let elevationM = Float(elevationFeet) * feetToMeters
                buildDeckLevel(
                    scene: scene,
                    vertices2D: metersVerts,
                    edges: level.edges,
                    allVertices: level.vertices,
                    elevationM: elevationM,
                    scaleFactor: scaleFactor,
                    perVertexElevation: level.perVertexElevation,
                    level: level
                )
            }
            // Level connections (stairs between levels)
            for connection in drawingData.levelConnections {
                buildLevelConnection(scene: scene, connection: connection, drawingData: drawingData, scaleFactor: scaleFactor)
            }
        } else if drawingData.isClosed {
            let metersVerts = convertToMeters(vertices: drawingData.orderedPositions, scaleFactor: scaleFactor)
            allPositions = drawingData.orderedPositions
            let elevationFeet = drawingData.overallElevation ?? 2.5
            let elevationM = Float(elevationFeet) * feetToMeters
            buildDeckLevel(
                scene: scene,
                vertices2D: metersVerts,
                edges: drawingData.edges,
                allVertices: drawingData.vertices,
                elevationM: elevationM,
                scaleFactor: scaleFactor,
                perVertexElevation: false,
                level: nil
            )
        }

        addGroundPlane(to: scene)
        addLighting(to: scene)
        addCamera(to: scene, fitting: allPositions, scaleFactor: scaleFactor, drawingData: drawingData)

        return scene
    }

    // MARK: - Deck Level

    private static func buildDeckLevel(
        scene: SCNScene,
        vertices2D: [CGPoint],  // already in meters (XZ plane)
        edges: [DeckEdge],
        allVertices: [DeckVertex],
        elevationM: Float,
        scaleFactor: Double,
        perVertexElevation: Bool,
        level: DeckLevel?
    ) {
        let deckGroup = SCNNode()
        deckGroup.name = level.map { "deck_\($0.id)" } ?? "deck_main"

        // Deck surface
        if let surfaceGeo = DeckMeshGenerator.createPolygonGeometry(vertices: vertices2D, yHeight: elevationM) {
            let material = deckSurfaceMaterial()
            surfaceGeo.firstMaterial = material
            let surfaceNode = SCNNode(geometry: surfaceGeo)
            surfaceNode.name = "deckSurface"
            deckGroup.addChildNode(surfaceNode)
        }

        // Posts at each vertex
        for (i, vert2D) in vertices2D.enumerated() {
            let vertexElevationM: Float
            if perVertexElevation, i < allVertices.count, let vElev = allVertices[i].elevation {
                vertexElevationM = Float(vElev) * feetToMeters
            } else {
                vertexElevationM = elevationM
            }
            let postHeight = vertexElevationM
            guard postHeight > 0 else { continue }
            let postNode = DeckMeshGenerator.createBox(
                position: SCNVector3(Float(vert2D.x), postHeight / 2, Float(vert2D.y)),
                width: postSizeM,
                height: postHeight,
                depth: postSizeM,
                material: makeMaterial(color: postColor)
            )
            postNode.name = "post_\(i)"
            deckGroup.addChildNode(postNode)
        }

        // Railing and stairs per edge
        for edge in edges {
            guard let startIdx = allVertices.firstIndex(where: { $0.id == edge.startVertexId }),
                  let endIdx = allVertices.firstIndex(where: { $0.id == edge.endVertexId }),
                  startIdx < vertices2D.count, endIdx < vertices2D.count else { continue }

            let startPt = vertices2D[startIdx]
            let endPt = vertices2D[endIdx]
            let startPos3D = SCNVector3(Float(startPt.x), elevationM, Float(startPt.y))
            let endPos3D = SCNVector3(Float(endPt.x), elevationM, Float(endPt.y))

            // Edge length in inches for post count
            let edgeLengthInches = edge.dimension ?? {
                let dx = Double(endPt.x - startPt.x)
                let dz = Double(endPt.y - startPt.y)
                return sqrt(dx * dx + dz * dz) / Double(inchesToMeters)
            }()

            // Railing
            if let railConfig = edge.railingConfig {
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
                    scaleFactor: scaleFactor
                )
            }

            // House wall
            if edge.edgeType == .houseEdge {
                buildHouseWall(
                    parent: deckGroup,
                    start: startPos3D,
                    end: endPos3D,
                    deckElevationM: elevationM
                )
            }
        }

        scene.rootNode.addChildNode(deckGroup)
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

    private static func buildStairs(
        parent: SCNNode,
        start: SCNVector3,
        end: SCNVector3,
        stairConfig: StairConfig,
        deckElevationM: Float,
        scaleFactor: Double
    ) {
        let stairGroup = SCNNode()
        stairGroup.name = "stairGroup"

        let totalRiseInches = Double(deckElevationM) / Double(inchesToMeters)
        let treadCount = stairConfig.treadCount ?? StairConfig.calculateTreadCount(totalRise: totalRiseInches, risePerStep: stairConfig.risePerStep)
        guard treadCount > 0 else { return }

        let risePerStepM = Float(stairConfig.risePerStep) * inchesToMeters
        let runPerTreadM = Float(stairConfig.runPerTread) * inchesToMeters
        let stairWidthM = Float(stairConfig.width) * inchesToMeters

        // Direction vector perpendicular to edge (outward from deck)
        let edgeDx = end.x - start.x
        let edgeDz = end.z - start.z
        let edgeLen = sqrt(edgeDx * edgeDx + edgeDz * edgeDz)
        guard edgeLen > 0 else { return }

        // Normal direction (perpendicular, pointing outward)
        let nx = -edgeDz / edgeLen
        let nz = edgeDx / edgeLen

        // Stair center along edge
        let midX = (start.x + end.x) / 2
        let midZ = (start.z + end.z) / 2

        // Edge tangent (for stair width)
        let tx = edgeDx / edgeLen
        let tz = edgeDz / edgeLen

        // Treads
        for i in 0..<treadCount {
            let stepOffset = Float(i + 1)
            let y = deckElevationM - stepOffset * risePerStepM
            let outward = stepOffset * runPerTreadM
            let cx = midX + nx * outward
            let cz = midZ + nz * outward

            // Tread: box oriented along edge direction
            let treadNode = SCNNode(geometry: SCNBox(
                width: CGFloat(stairWidthM),
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
        let stringerLengthM = sqrt(deckElevationM * deckElevationM + totalRunM * totalRunM)
        let stringerAngle = atan2(deckElevationM, totalRunM)
        let stringerWidthM: Float = 2.0 * inchesToMeters  // 2" wide stringer
        let stringerDepthM: Float = 10.0 * inchesToMeters  // 10" deep stringer

        for s in 0..<stringerCount {
            let t = Float(s) / Float(max(stringerCount - 1, 1))
            let lateralOffset = stairWidthM * (t - 0.5)

            // Stringer center point
            let centerOutward = totalRunM / 2
            let centerY = deckElevationM / 2
            let sx = midX + nx * centerOutward + tx * lateralOffset
            let sz = midZ + nz * centerOutward + tz * lateralOffset

            let stringerNode = SCNNode(geometry: SCNBox(
                width: CGFloat(stringerWidthM),
                height: CGFloat(stringerDepthM),
                length: CGFloat(stringerLengthM),
                chamferRadius: 0
            ))
            stringerNode.geometry?.firstMaterial = makeMaterial(color: stringerColor)
            stringerNode.position = SCNVector3(sx, centerY, sz)

            // Rotate to follow stair angle + edge direction
            let edgeAngle = atan2(edgeDz, edgeDx)
            stringerNode.eulerAngles.y = -edgeAngle
            stringerNode.eulerAngles.x = stringerAngle
            stringerNode.name = "stringer_\(s)"
            stairGroup.addChildNode(stringerNode)
        }

        parent.addChildNode(stairGroup)
    }

    // MARK: - Level Connections

    private static func buildLevelConnection(
        scene: SCNScene,
        connection: LevelConnection,
        drawingData: DeckDrawingData,
        scaleFactor: Double
    ) {
        guard let upperLevel = drawingData.level(byId: connection.upperLevelId),
              let lowerLevel = drawingData.level(byId: connection.lowerLevelId),
              let upperElev = upperLevel.elevation,
              let lowerElev = lowerLevel.elevation else { return }

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
        let midX = (start3D.x + end3D.x) / 2
        let midZ = (start3D.z + end3D.z) / 2

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

        scene.rootNode.addChildNode(connectionGroup)
    }

    // MARK: - House Wall

    private static func buildHouseWall(
        parent: SCNNode,
        start: SCNVector3,
        end: SCNVector3,
        deckElevationM: Float
    ) {
        let wallHeight = deckElevationM + houseWallHeightM
        let wallNode = buildSpanningBox(
            from: start, to: end,
            yCenter: wallHeight / 2,
            width: 0.05, // 2" thick wall representation
            height: wallHeight,
            material: makeMaterial(color: houseWallColor)
        )
        wallNode.name = "houseWall"
        parent.addChildNode(wallNode)
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
        drawingData: DeckDrawingData
    ) {
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.fieldOfView = 60

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"

        // Calculate bounding box center in meters
        let metersPositions = convertToMeters(vertices: positions, scaleFactor: scaleFactor)
        let bounds = DeckMeshGenerator.boundingRect(for: metersPositions)
        let centerX = Float(bounds.midX)
        let centerZ = Float(bounds.midY)
        let avgElevation: Float = {
            if drawingData.isMultiLevel {
                let elevations = drawingData.levels.compactMap { $0.elevation }
                guard !elevations.isEmpty else { return 0.76 } // ~2.5' default
                return Float(elevations.reduce(0, +) / Double(elevations.count)) * feetToMeters
            }
            return Float(drawingData.overallElevation ?? 2.5) * feetToMeters
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

    // MARK: - Materials

    private static func deckSurfaceMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = generateBoardTexture()
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.roughness.contents = 0.7
        material.isDoubleSided = true
        return material
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

    /// Convert 2D canvas positions to meters in XZ plane, centered at origin
    static func convertToMeters(vertices: [CGPoint], scaleFactor: Double) -> [CGPoint] {
        guard !vertices.isEmpty else { return [] }

        // Convert canvas points → inches → meters
        let metersPerCanvasPoint = 1.0 / scaleFactor / Double(39.3701)

        // Find center to place deck at origin
        let bounds = DeckMeshGenerator.boundingRect(for: vertices)
        let centerX = Double(bounds.midX)
        let centerY = Double(bounds.midY)

        return vertices.map { v in
            CGPoint(
                x: (Double(v.x) - centerX) * metersPerCanvasPoint,
                y: (Double(v.y) - centerY) * metersPerCanvasPoint
            )
        }
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
