//
//  DeckTab3DView.swift
//  OPS
//
//  Read-only 3D SceneKit viewer for deck designs in project details.
//  Delegates scene construction to DeckSceneBuilder so the viewer renders
//  the same geometry as the editor — including stairs, house walls,
//  railings, and ALL levels (not just the first). Falls back to a
//  geometry-from-canvas-coordinates pass when the design has no
//  scaleFactor set (uncalibrated drawings); the calibrated path is the
//  expected one for any deck saved from the builder.
//

import SwiftUI
import SceneKit

struct DeckTab3DView: View {
    let drawingData: DeckDrawingData

    var body: some View {
        GeometryReader { geo in
            if geo.size.height > 0 {
                DeckTab3DSceneView(drawingData: drawingData)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - SceneKit UIViewRepresentable

private struct DeckTab3DSceneView: UIViewRepresentable {
    let drawingData: DeckDrawingData
    private let feetToMeters: Float = 0.3048
    private let inchesToMeters: Float = 1.0 / 39.3701

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor(red: 10/255, green: 10/255, blue: 10/255, alpha: 1)
        scnView.preferredFramesPerSecond = 60

        let scene = buildScene()
        scnView.scene = scene
        if let cam = scene.rootNode.childNode(withName: "camera", recursively: true) {
            scnView.pointOfView = cam
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Rebuild when the drawing changes so edits in the editor flow through
        // to the project tab without a full screen tear-down.
        let scene = buildScene()
        uiView.scene = scene
        if let cam = scene.rootNode.childNode(withName: "camera", recursively: true) {
            uiView.pointOfView = cam
        }
    }

    /// Prefer the canonical builder when the design is calibrated. Falls back
    /// to a minimal canvas-space scene when no scaleFactor exists so the
    /// viewer still shows *something* for early-draft designs that haven't
    /// been calibrated yet.
    private func buildScene() -> SCNScene {
        if let scale = drawingData.scaleFactor, scale > 0 {
            return DeckSceneBuilder.buildScene(from: drawingData)
        }
        return buildFallbackScene()
    }

    // MARK: - Fallback Scene (no scaleFactor)

    /// Minimal SceneKit scene built from raw canvas coordinates. Used only
    /// when the design lacks a scaleFactor — DeckSceneBuilder requires real
    /// units, so this provides a usable preview for uncalibrated drawings.
    /// Renders surfaces + edges across ALL levels (not just the first).
    private func buildFallbackScene() -> SCNScene {
        let scene = SCNScene()

        // Aggregate positions across every level so the camera frames the
        // whole design — fixes the prior bug where only level 1 was visible.
        let allPositions: [CGPoint]
        if drawingData.isMultiLevel {
            allPositions = drawingData.levels.flatMap { $0.orderedPositions }
        } else {
            allPositions = drawingData.orderedPositions
        }
        guard allPositions.count >= 2 else { return scene }

        let xs = allPositions.map { Float($0.x) }
        let ys = allPositions.map { Float($0.y) }
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let spanX = maxX - minX
        let spanY = maxY - minY
        let maxSpan = max(spanX, spanY)
        guard maxSpan > 0.1 else { return scene }

        let targetSize: Float = 5.0
        let scale = targetSize / maxSpan

        func toScene(_ p: CGPoint) -> (x: Float, z: Float) {
            let x = (Float(p.x) - centerX) * scale
            let z = (Float(p.y) - centerY) * scale
            return (x, z)
        }

        // Render every level — surfaces + explicit edge features. Without this loop,
        // multi-level designs only ever showed level 1 in the viewer.
        let levelsToRender: [(positions: [CGPoint], edges: [DeckEdge], vertices: [DeckVertex], isClosed: Bool, deckHeight: Float, displayColor: LevelColor?, houseWallCapM: Float?)]
        if drawingData.isMultiLevel {
            levelsToRender = drawingData.levels.enumerated().map { idx, level in
                let deckHeight = Float(drawingData.renderElevationFeet(for: level, levelIndex: idx)) * feetToMeters
                let capM = drawingData.heightToNextLevelFeet(aboveLevelAt: idx).map { Float($0) * feetToMeters }
                return (level.orderedPositions, level.edges, level.vertices, level.isClosed, deckHeight, level.displayColor, capM)
            }
        } else {
            let deckHeight = Float(drawingData.renderElevationFeetSingleLevel) * feetToMeters
            levelsToRender = [(drawingData.orderedPositions, drawingData.edges, drawingData.vertices, drawingData.isClosed, deckHeight, nil, nil)]
        }

        for level in levelsToRender {
            renderFallbackLevel(
                positions: level.positions,
                edges: level.edges,
                vertices: level.vertices,
                isClosed: level.isClosed,
                levelDeckY: level.deckHeight,
                displayColor: level.displayColor,
                houseWallCapM: level.houseWallCapM,
                toScene: toScene,
                scene: scene
            )
        }

        addGroundPlane(scene: scene, targetSize: targetSize)
        addLighting(scene: scene)
        let cameraHeight = levelsToRender.map(\.deckHeight).max() ?? (2.5 * feetToMeters)
        addCamera(scene: scene, targetSize: targetSize, deckHeight: cameraHeight)

        return scene
    }

    private func renderFallbackLevel(
        positions: [CGPoint],
        edges: [DeckEdge],
        vertices: [DeckVertex],
        isClosed: Bool,
        levelDeckY: Float,
        displayColor: LevelColor?,
        houseWallCapM: Float?,
        toScene: (CGPoint) -> (x: Float, z: Float),
        scene: SCNScene
    ) {
        let beamHeight: Float = 0.08
        let beamWidth: Float = 0.06

        // Derive how many scene units one real-world inch spans on the
        // horizontal plane. The fallback has no scaleFactor, so stair runs and
        // widths (stored in inches) can't be converted to scene units directly.
        // But any edge carrying a measured `dimension` (real-world inches)
        // implies a canvas-points-per-inch ratio when compared to its drawn
        // canvas length; folding in the canvas→scene scale yields scene units
        // per inch — the same mixed convention the house/parapet walls already
        // use (real-world heights over a scaled canvas footprint). nil when no
        // edge is dimensioned, in which case stairs fall back to a proportional
        // representation. Mirrors how DeckSceneBuilder sizes stairs from inches.
        let sceneUnitsPerInch = fallbackSceneUnitsPerInch(
            edges: edges,
            vertices: vertices,
            toScene: toScene
        )

        // Surface
        if isClosed, positions.count >= 3 {
            let scenePoints = positions.map { p -> CGPoint in
                let s = toScene(p)
                return CGPoint(x: CGFloat(s.x), y: CGFloat(s.z))
            }
            if let surfaceGeo = DeckMeshGenerator.createPolygonGeometry(vertices: scenePoints, yHeight: levelDeckY) {
                let surfaceMat = SCNMaterial()
                // Multi-level designs color-code the surface by the level's
                // display color so levels stay visually distinct (bug 8f9c0280).
                if let displayColor {
                    let c = displayColor.fillColor
                    surfaceMat.diffuse.contents = UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
                } else {
                    surfaceMat.diffuse.contents = UIColor(red: 196/255, green: 149/255, blue: 106/255, alpha: 1)
                }
                surfaceMat.isDoubleSided = true
                surfaceGeo.materials = [surfaceMat]
                scene.rootNode.addChildNode(SCNNode(geometry: surfaceGeo))
            }
            if let undersideGeo = DeckMeshGenerator.createPolygonGeometry(vertices: scenePoints, yHeight: levelDeckY - 0.05) {
                let underMat = SCNMaterial()
                underMat.diffuse.contents = UIColor(red: 139/255, green: 108/255, blue: 74/255, alpha: 1)
                underMat.isDoubleSided = true
                undersideGeo.materials = [underMat]
                scene.rootNode.addChildNode(SCNNode(geometry: undersideGeo))
            }
        }

        // Edge beams
        for edge in edges {
            guard let startVert = vertices.first(where: { $0.id == edge.startVertexId }),
                  let endVert = vertices.first(where: { $0.id == edge.endVertexId }) else { continue }

            let s = toScene(startVert.position)
            let e = toScene(endVert.position)
            let dx = e.x - s.x
            let dz = e.z - s.z
            let length = sqrt(dx * dx + dz * dz)
            guard length > 0.01 else { continue }

            let midX = (s.x + e.x) / 2
            let midZ = (s.z + e.z) / 2
            let angle = atan2(dx, dz)

            let beamGeo = SCNBox(width: CGFloat(beamWidth), height: CGFloat(beamHeight), length: CGFloat(length), chamferRadius: 0)
            let beamMat = SCNMaterial()
            beamMat.diffuse.contents = edge.edgeType == .houseEdge
                ? UIColor(red: 136/255, green: 136/255, blue: 136/255, alpha: 0.8)
                : UIColor(red: 170/255, green: 130/255, blue: 90/255, alpha: 1)
            beamGeo.materials = [beamMat]
            let beamNode = SCNNode(geometry: beamGeo)
            // Seat the edge beam BENEATH the deck surface — top of the beam
            // flush with the surface — so it reads as a rim joist under the
            // deck boards rather than a curb standing proud of them (bug
            // 313aad41).
            beamNode.position = SCNVector3(midX, levelDeckY - beamHeight / 2, midZ)
            // SCNBox length runs along local +Z. Rotating eulerAngles.y by
            // atan2(dx, dz) aims +Z down the edge; negating it mirrors the box
            // across Z. That mirror is invisible on axis-aligned edges (a box
            // is symmetric) but points the beam the wrong way on any diagonal
            // edge — the source of the broken non-right-angle borders. Matches
            // DeckSceneBuilder.buildSpanningBox.
            beamNode.eulerAngles.y = angle
            scene.rootNode.addChildNode(beamNode)

            if edge.edgeType == .houseEdge {
                // 8' house wall, capped at the bottom of the next level up on
                // multi-level designs so it doesn't pierce the deck above
                // (bug fb007839 — supersedes a40556a7, which set it to 9').
                let houseWallHeight = houseWallCapM.map { min(8.0 * feetToMeters, $0) }
                    ?? (8.0 * feetToMeters)
                let wallColor = edge.houseEdgeMaterial.map { UIColor(hex: $0.fillHex) }
                    ?? UIColor(red: 136/255, green: 136/255, blue: 136/255, alpha: 0.8)
                if levelDeckY > 0.01 {
                    addWall(
                        scene: scene,
                        midX: midX,
                        midZ: midZ,
                        angle: angle,
                        length: length,
                        bottomY: 0,
                        height: levelDeckY,
                        thickness: 0.05,
                        color: wallColor.withAlphaComponent(0.35),
                        name: "houseWallToGrade"
                    )
                }
                addWall(
                    scene: scene,
                    midX: midX,
                    midZ: midZ,
                    angle: angle,
                    length: length,
                    bottomY: levelDeckY,
                    height: houseWallHeight,
                    thickness: 0.05,
                    color: wallColor,
                    name: "houseWall"
                )
            } else if let railing = edge.railingConfig, railing.railingType == .parapetWall {
                let wallHeight = Float(max(24.0, min(48.0, railing.postHeight))) * inchesToMeters
                addWall(
                    scene: scene,
                    midX: midX,
                    midZ: midZ,
                    angle: angle,
                    length: length,
                    bottomY: levelDeckY,
                    height: wallHeight,
                    thickness: 0.10,
                    color: UIColor(hex: railing.wallMaterial.fillHex)
                )
            }

            // Stairs — uncalibrated decks still need stairs in the project 3D
            // tab. The calibrated path builds these via DeckSceneBuilder.buildStairs;
            // this mirrors that geometry (tread boxes + stringers) in the
            // fallback's own scaled-canvas/real-height coordinate space so
            // stairs appear regardless of scaleFactor (bug 642a5e3c).
            if let stairConfig = edge.stairConfig {
                addFallbackStairs(
                    scene: scene,
                    startVert: startVert,
                    endVert: endVert,
                    stairConfig: stairConfig,
                    levelDeckY: levelDeckY,
                    sceneUnitsPerInch: sceneUnitsPerInch,
                    polygonPositions: positions,
                    isClosed: isClosed,
                    toScene: toScene
                )
            }
        }

    }

    // MARK: - Fallback Stairs

    /// Scene units spanned by one real-world inch on the horizontal plane, or
    /// nil when nothing in this level is dimensioned.
    ///
    /// `scaleFactor` is "canvas points per real-world inch" — absent here by
    /// definition. We recover an equivalent from any edge that carries a
    /// measured `dimension` (real-world inches): the ratio of that edge's drawn
    /// canvas length to its dimension is canvas-points-per-inch. Multiplying by
    /// the canvas→scene scale (recovered as the edge's scene length over its
    /// canvas length) gives scene-units-per-inch. Averaged across every
    /// dimensioned edge for stability. This keeps stair runs/widths sized in
    /// real proportions while their rise stays in real meters — the same mixed
    /// convention the house/parapet walls already use in the fallback.
    private func fallbackSceneUnitsPerInch(
        edges: [DeckEdge],
        vertices: [DeckVertex],
        toScene: (CGPoint) -> (x: Float, z: Float)
    ) -> Float? {
        var ratios: [Float] = []
        for edge in edges {
            guard let dimension = edge.dimension, dimension > 0,
                  let startVert = vertices.first(where: { $0.id == edge.startVertexId }),
                  let endVert = vertices.first(where: { $0.id == edge.endVertexId }) else { continue }

            let canvasDx = Float(endVert.position.x - startVert.position.x)
            let canvasDz = Float(endVert.position.y - startVert.position.y)
            let canvasLen = sqrt(canvasDx * canvasDx + canvasDz * canvasDz)
            guard canvasLen > 0.01 else { continue }

            let s = toScene(startVert.position)
            let e = toScene(endVert.position)
            let sceneDx = e.x - s.x
            let sceneDz = e.z - s.z
            let sceneLen = sqrt(sceneDx * sceneDx + sceneDz * sceneDz)
            guard sceneLen > 0.0001 else { continue }

            // sceneUnitsPerInch = (sceneLen / canvasLen) * (canvasLen / dimension)
            //                   =  sceneLen / dimension
            ratios.append(sceneLen / Float(dimension))
        }
        guard !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Float(ratios.count)
    }

    /// Build stair geometry (tread boxes + stringers) for the fallback scene,
    /// mirroring `DeckSceneBuilder.buildStairs`. Rise resolves from
    /// `stairConfig.totalRiseInches` (in real meters, matching the wall
    /// convention), falling back to the deck elevation. `treadCount` follows
    /// the stored override or the IRC-derived calculation. Runs and widths are
    /// expressed in scene units via `sceneUnitsPerInch`; when no edge is
    /// dimensioned that scale is unknown, so a proportional best-effort scale
    /// is derived from the edge's own scene length instead so stairs still
    /// render for uncalibrated drawings.
    private func addFallbackStairs(
        scene: SCNScene,
        startVert: DeckVertex,
        endVert: DeckVertex,
        stairConfig: StairConfig,
        levelDeckY: Float,
        sceneUnitsPerInch: Float?,
        polygonPositions: [CGPoint],
        isClosed: Bool,
        toScene: (CGPoint) -> (x: Float, z: Float)
    ) {
        // Rise: prefer the explicitly configured total rise (real meters), else
        // fall back to the deck elevation. Matches DeckSceneBuilder.buildStairs.
        let totalRiseM: Float
        if let stored = stairConfig.totalRiseInches, stored > 0 {
            totalRiseM = Float(stored) * inchesToMeters
        } else {
            totalRiseM = levelDeckY
        }
        guard totalRiseM > 0 else { return }

        let totalRiseInches = Double(totalRiseM) / Double(inchesToMeters)
        let treadCount = stairConfig.treadCount
            ?? StairConfig.calculateTreadCount(totalRise: totalRiseInches, risePerStep: stairConfig.risePerStep)
        guard treadCount > 0 else { return }

        // Edge endpoints in scene space.
        let s = toScene(startVert.position)
        let e = toScene(endVert.position)
        let edgeDx = e.x - s.x
        let edgeDz = e.z - s.z
        let edgeLen = sqrt(edgeDx * edgeDx + edgeDz * edgeDz)
        guard edgeLen > 0.0001 else { return }

        let tx = edgeDx / edgeLen
        let tz = edgeDz / edgeLen

        // Horizontal scale (scene units per inch). When the design is
        // dimensioned, use the derived value. Otherwise the inch→scene mapping
        // is genuinely unknowable, so approximate it so stairs still read at a
        // sensible size: assume the stair width roughly fills the edge.
        let unitsPerInch: Float = {
            if let derived = sceneUnitsPerInch, derived > 0 { return derived }
            let widthInches = Float(stairConfig.width)
            guard widthInches > 0 else { return edgeLen / 36.0 }
            return edgeLen / widthInches
        }()

        let risePerStepM = totalRiseM / Float(treadCount)
        let runPerTreadScene = Float(stairConfig.runPerTread) * unitsPerInch
        let stairWidthScene = Float(stairConfig.width) * unitsPerInch
        let stairWidthLimited = min(stairWidthScene, edgeLen)
        guard runPerTreadScene > 0, stairWidthLimited > 0 else { return }

        // Outward perpendicular — same polygon-aware logic as the 2D canvas and
        // DeckSceneBuilder so stairs land OPPOSITE the filled deck surface by
        // default. Computed in scene space (consistent with the edge endpoints).
        // Falls back to the CCW perpendicular when the polygon is open.
        let rawN: (x: Float, z: Float)
        if isClosed, polygonPositions.count >= 3 {
            let scenePolygon = polygonPositions.map { p -> CGPoint in
                let sp = toScene(p)
                return CGPoint(x: CGFloat(sp.x), y: CGFloat(sp.z))
            }
            let outward = PolygonMath.outwardPerpendicular(
                edgeStart: CGPoint(x: CGFloat(s.x), y: CGFloat(s.z)),
                edgeEnd: CGPoint(x: CGFloat(e.x), y: CGFloat(e.z)),
                polygonVertices: scenePolygon
            )
            rawN = (x: Float(outward.x), z: Float(outward.y))
        } else {
            rawN = (x: -edgeDz / edgeLen, z: edgeDx / edgeLen)
        }
        let nx = stairConfig.flipDirection ? -rawN.x : rawN.x
        let nz = stairConfig.flipDirection ? -rawN.z : rawN.z

        // Position the stair along the edge using alignment + offset, matching
        // the 2D canvas + DeckSceneBuilder logic.
        let gapTotal = edgeLen - stairWidthLimited
        let offsetScene = Float(stairConfig.offset) * unitsPerInch
        let stairStartT: Float
        switch stairConfig.alignment {
        case .left:
            stairStartT = offsetScene / edgeLen
        case .center:
            stairStartT = (gapTotal / 2 + offsetScene) / edgeLen
        case .right:
            stairStartT = (gapTotal - offsetScene) / edgeLen
        }
        let stairBaseX = s.x + tx * edgeLen * stairStartT
        let stairBaseZ = s.z + tz * edgeLen * stairStartT
        let midX = stairBaseX + tx * stairWidthLimited / 2
        let midZ = stairBaseZ + tz * stairWidthLimited / 2

        let stairGroup = SCNNode()
        stairGroup.name = "fallbackStairGroup"

        // Tread thickness scaled like every other horizontal dimension (1.5"),
        // matching DeckSceneBuilder's treadThicknessM concept in this space.
        let treadThicknessScene = max(1.5 * unitsPerInch, 0.01)
        let treadColor = UIColor(red: 196/255, green: 149/255, blue: 106/255, alpha: 1)   // #C4956A cedar
        let stringerColor = UIColor(red: 139/255, green: 108/255, blue: 74/255, alpha: 1) // #8B6C4A dark wood

        let edgeAngle = atan2(edgeDz, edgeDx)

        // Treads — step down (real meters) and outward (scene units).
        for i in 0..<treadCount {
            let stepOffset = Float(i + 1)
            let y = levelDeckY - stepOffset * risePerStepM
            let outward = stepOffset * runPerTreadScene
            let cx = midX + nx * outward
            let cz = midZ + nz * outward

            let treadGeo = SCNBox(
                width: CGFloat(stairWidthLimited),
                height: CGFloat(treadThicknessScene),
                length: CGFloat(runPerTreadScene),
                chamferRadius: 0
            )
            let treadMat = SCNMaterial()
            treadMat.diffuse.contents = treadColor
            treadGeo.materials = [treadMat]
            let treadNode = SCNNode(geometry: treadGeo)
            treadNode.position = SCNVector3(cx, y, cz)
            treadNode.eulerAngles.y = -edgeAngle
            treadNode.name = "fallbackTread_\(i)"
            stairGroup.addChildNode(treadNode)
        }

        // Stringers — angled side beams following the rise/run, one per side
        // (and intermediates for wide stairs), mirroring DeckSceneBuilder.
        let stringerCount = StairConfig.stringerCount(width: stairConfig.width)
        let totalRunScene = Float(treadCount) * runPerTreadScene
        let stringerLengthScene = sqrt(totalRiseM * totalRiseM + totalRunScene * totalRunScene)
        let stringerAngle = atan2(totalRiseM, totalRunScene)
        let stringerWidthScene = max(2.0 * unitsPerInch, 0.01)   // 2" wide
        let stringerDepthScene = max(10.0 * unitsPerInch, 0.02)  // 10" deep

        for stringerIndex in 0..<stringerCount {
            let t = Float(stringerIndex) / Float(max(stringerCount - 1, 1))
            let lateralOffset = stairWidthLimited * (t - 0.5)

            let centerOutward = totalRunScene / 2
            let centerY = levelDeckY - totalRiseM / 2
            let sx = midX + nx * centerOutward + tx * lateralOffset
            let sz = midZ + nz * centerOutward + tz * lateralOffset

            let stringerGeo = SCNBox(
                width: CGFloat(stringerWidthScene),
                height: CGFloat(stringerDepthScene),
                length: CGFloat(stringerLengthScene),
                chamferRadius: 0
            )
            let stringerMat = SCNMaterial()
            stringerMat.diffuse.contents = stringerColor
            stringerGeo.materials = [stringerMat]
            let stringerNode = SCNNode(geometry: stringerGeo)
            stringerNode.position = SCNVector3(sx, centerY, sz)
            stringerNode.eulerAngles.y = -edgeAngle
            stringerNode.eulerAngles.x = stringerAngle
            stringerNode.name = "fallbackStringer_\(stringerIndex)"
            stairGroup.addChildNode(stringerNode)
        }

        scene.rootNode.addChildNode(stairGroup)
    }

    private func addWall(
        scene: SCNScene,
        midX: Float,
        midZ: Float,
        angle: Float,
        length: Float,
        bottomY: Float,
        height: Float,
        thickness: Float,
        color: UIColor,
        name: String? = nil
    ) {
        guard height > 0, length > 0 else { return }
        let wallGeo = SCNBox(width: CGFloat(thickness), height: CGFloat(height), length: CGFloat(length), chamferRadius: 0)
        let wallMat = SCNMaterial()
        wallMat.diffuse.contents = color
        wallGeo.materials = [wallMat]
        let wallNode = SCNNode(geometry: wallGeo)
        wallNode.position = SCNVector3(midX, bottomY + height / 2, midZ)
        // +angle, not -angle: the box length axis must aim down the edge.
        // See the beam-orientation note in renderFallbackLevel.
        wallNode.eulerAngles.y = angle
        wallNode.name = name
        scene.rootNode.addChildNode(wallNode)
    }

    private func addGroundPlane(scene: SCNScene, targetSize: Float) {
        let groundGeo = SCNPlane(width: CGFloat(targetSize * 4), height: CGFloat(targetSize * 4))
        let groundMat = SCNMaterial()
        groundMat.diffuse.contents = UIColor(red: 74/255, green: 94/255, blue: 58/255, alpha: 0.3)
        groundMat.isDoubleSided = true
        groundGeo.materials = [groundMat]
        let groundNode = SCNNode(geometry: groundGeo)
        groundNode.eulerAngles.x = -.pi / 2
        groundNode.position = SCNVector3(0, -0.01, 0)
        scene.rootNode.addChildNode(groundNode)
    }

    private func addLighting(scene: SCNScene) {
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 400
        ambientLight.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.intensity = 800
        directionalLight.color = UIColor.white
        directionalLight.castsShadow = true
        directionalLight.shadowRadius = 3
        directionalLight.shadowMapSize = CGSize(width: 1024, height: 1024)
        let directionalNode = SCNNode()
        directionalNode.light = directionalLight
        directionalNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
        scene.rootNode.addChildNode(directionalNode)
    }

    private func addCamera(scene: SCNScene, targetSize: Float, deckHeight: Float) {
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.fieldOfView = 50

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"

        let distance: Float = targetSize * 1.6
        let azimuthRad: Float = 225.0 * .pi / 180.0
        let elevationRad: Float = 35.0 * .pi / 180.0

        cameraNode.position = SCNVector3(
            distance * cos(elevationRad) * sin(azimuthRad),
            deckHeight + distance * sin(elevationRad),
            distance * cos(elevationRad) * cos(azimuthRad)
        )
        cameraNode.look(at: SCNVector3(0, deckHeight / 2, 0))
        scene.rootNode.addChildNode(cameraNode)
    }
}
