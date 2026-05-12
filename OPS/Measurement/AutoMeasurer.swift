//
//  AutoMeasurer.swift
//  OPS
//
//  Given a `DetectedOpening` produced by `OpeningClassifier`, derive up to
//  four dimensions: width, height, sill height (distance from floor mesh to
//  the opening's bottom edge), and opening depth (recess distance from the
//  surrounding wall plane).
//
//  Honest limitation (spec §3.3): if no horizontal floor mesh exists within
//  0.5 m below the opening, the sill-height dimension is **skipped entirely**
//  — we do NOT fall back to ARKit's gravity-aligned plane, because that
//  produces a misleading "height-from-camera" reading. Three measurements are
//  returned in that case plus a `sillUnavailableReason` flag for the UI to
//  surface the inline hint `// SILL — NO FLOOR REFERENCE`.
//
//  Coordinates throughout are camera-frame metres (+X right, +Y down,
//  +Z forward).
//

import Foundation
import simd

public enum SillUnavailableReason: String, Equatable {
    case noFloorMeshNearby
    case openingNotVerticallyOriented
}

public struct AutoMeasurementResult {
    public let opening: DetectedOpening
    public let width: DimensionsData.Measurement
    public let height: DimensionsData.Measurement
    public let sillHeight: DimensionsData.Measurement?
    public let openingDepth: DimensionsData.Measurement?
    public let sillUnavailableReason: SillUnavailableReason?
    public let depthUnavailable: Bool

    /// Flat list of every successfully measured dimension, in canonical order:
    /// W, H, sill (if present), depth (if present).
    public var allMeasurements: [DimensionsData.Measurement] {
        var arr = [width, height]
        if let s = sillHeight { arr.append(s) }
        if let d = openingDepth { arr.append(d) }
        return arr
    }
}

public struct AutoMeasurer {

    /// Maximum vertical gap (camera-frame Y, metres) between the opening's
    /// bottom edge and a floor face's centroid for the floor to count as a
    /// valid sill reference. Per spec §3.3.
    public static let maxSillGapMetres: Float = 0.5

    /// Maximum horizontal/lateral distance from the opening's centre at which
    /// a wall face counts toward the surrounding-wall plane fit. Keeps the
    /// depth measurement local to the opening rather than averaging across
    /// the whole room.
    public static let wallSearchRadiusMetres: Float = 1.0

    public static func measure(
        opening: DetectedOpening,
        anchors: AnchorSnapshot,
        photoSize: CGSize
    ) -> AutoMeasurementResult {
        let corners = opening.cornersCameraFrame  // [TL, TR, BR, BL]

        let width  = makeLinear(label: "Width",
                                worldA: corners[0], worldB: corners[1],
                                imageA: opening.boundingPolygon[0],
                                imageB: opening.boundingPolygon[1])
        let height = makeLinear(label: "Height",
                                worldA: corners[0], worldB: corners[3],
                                imageA: opening.boundingPolygon[0],
                                imageB: opening.boundingPolygon[3])

        // Sill height
        let (sill, sillReason) = computeSillHeight(opening: opening, anchors: anchors)

        // Opening depth (recess from wall plane)
        let depth = computeOpeningDepth(opening: opening,
                                        anchors: anchors,
                                        photoSize: photoSize)

        return AutoMeasurementResult(
            opening: opening,
            width: width,
            height: height,
            sillHeight: sill,
            openingDepth: depth,
            sillUnavailableReason: sillReason,
            depthUnavailable: depth == nil
        )
    }

    // MARK: - Sill

    private static func computeSillHeight(
        opening: DetectedOpening,
        anchors: AnchorSnapshot
    ) -> (DimensionsData.Measurement?, SillUnavailableReason?) {
        // Opening bottom edge midpoint in camera frame: average of corners 2 (BR) and 3 (BL).
        let br = opening.cornersCameraFrame[2]
        let bl = opening.cornersCameraFrame[3]
        let openingBottomMid = (br + bl) * 0.5
        // The opening's plane normal should be roughly horizontal for a
        // window/door (looking forward), so its Y component should be small.
        // If the opening is mounted in a non-vertical surface (ceiling? bizarre)
        // sill height is meaningless.
        guard abs(opening.planeNormal.y) < 0.5 else {
            return (nil, .openingNotVerticallyOriented)
        }

        // Express floor faces in camera frame.
        let w2c = anchors.worldToCamera
        let floorCentroids: [SIMD3<Float>] = anchors.floorFaces.map { face in
            let cWorld = face.centroid
            let h = SIMD4<Float>(cWorld.x, cWorld.y, cWorld.z, 1)
            let cCam = w2c * h
            return SIMD3<Float>(cCam.x, cCam.y, cCam.z)
        }

        // Filter to floors directly below the opening: in camera frame, "below"
        // means greater Y (since +Y is down). Distance gate per spec §3.3.
        let openingY = Float(openingBottomMid.y)
        var bestGap: Float = .greatestFiniteMagnitude
        var bestCentroid: SIMD3<Float>?
        for c in floorCentroids {
            let dy = c.y - openingY
            guard dy > 0, dy <= maxSillGapMetres else { continue }
            if dy < bestGap {
                bestGap = dy
                bestCentroid = c
            }
        }
        guard let floor = bestCentroid else {
            return (nil, .noFloorMeshNearby)
        }

        // World points: opening bottom midpoint → floor point directly below it.
        let floorPoint = SIMD3<Double>(Double(floor.x), Double(floor.y), Double(floor.z))
        // Synthesise an image-pixel pair for the sill leader: the bottom-edge
        // midpoint pixel, and the point directly below it on screen.
        let bottomMidPixel = DimensionsData.Point2(
            x: 0.5 * (opening.boundingPolygon[2].x + opening.boundingPolygon[3].x),
            y: 0.5 * (opening.boundingPolygon[2].y + opening.boundingPolygon[3].y)
        )

        let dx = openingBottomMid.x - floorPoint.x
        let dy = openingBottomMid.y - floorPoint.y
        let dz = openingBottomMid.z - floorPoint.z
        let dist = (dx*dx + dy*dy + dz*dz).squareRoot()

        let m = DimensionsData.Measurement(
            type: .linear,
            label: "Sill Height",
            worldPoints: [
                DimensionsData.Point3(x: openingBottomMid.x, y: openingBottomMid.y, z: openingBottomMid.z),
                DimensionsData.Point3(x: floorPoint.x, y: floorPoint.y, z: floorPoint.z)
            ],
            imagePoints: [bottomMidPixel, bottomMidPixel],  // pixel for floor is below screen; UI will reposition
            valueMeters: dist,
            primaryDisplayUnit: .imperialFraction,
            labelPlacement: .init(side: .south, leaderLengthPx: 60),
            source: .auto
        )
        return (m, nil)
    }

    // MARK: - Depth

    private static func computeOpeningDepth(
        opening: DetectedOpening,
        anchors: AnchorSnapshot,
        photoSize: CGSize
    ) -> DimensionsData.Measurement? {
        // Find wall faces near the opening in camera frame.
        let w2c = anchors.worldToCamera
        let openingCentroidCam = opening.cornersCameraFrame.reduce(SIMD3<Double>.zero, +)
            / Double(opening.cornersCameraFrame.count)

        var wallNormalSum = SIMD3<Float>(repeating: 0)
        var wallCentroidSum = SIMD3<Float>(repeating: 0)
        var wallWeight: Float = 0
        for face in anchors.wallFaces {
            let cWorld = face.centroid
            let h = SIMD4<Float>(cWorld.x, cWorld.y, cWorld.z, 1)
            let cCam = w2c * h
            let cCamD = SIMD3<Double>(Double(cCam.x), Double(cCam.y), Double(cCam.z))
            let dist = simd_length(cCamD - openingCentroidCam)
            guard dist <= Double(wallSearchRadiusMetres) else { continue }
            // Express normal in camera frame: rotation-only application.
            let rotW2C = simd_float3x3(
                SIMD3<Float>(w2c.columns.0.x, w2c.columns.0.y, w2c.columns.0.z),
                SIMD3<Float>(w2c.columns.1.x, w2c.columns.1.y, w2c.columns.1.z),
                SIMD3<Float>(w2c.columns.2.x, w2c.columns.2.y, w2c.columns.2.z)
            )
            let nCam = simd_normalize(rotW2C * face.normal)
            wallNormalSum += face.area * nCam
            wallCentroidSum += face.area * SIMD3<Float>(cCam.x, cCam.y, cCam.z)
            wallWeight += face.area
        }
        guard wallWeight > 0, simd_length(wallNormalSum) > 1e-6 else {
            return nil
        }
        let wallNormal = simd_normalize(wallNormalSum)
        let wallCentroid = wallCentroidSum / wallWeight
        let wallOffset = -simd_dot(wallNormal, wallCentroid)

        // Distance from opening centroid to wall plane, signed along wall normal.
        let wallNormalD = SIMD3<Double>(Double(wallNormal.x), Double(wallNormal.y), Double(wallNormal.z))
        let signedDist = simd_dot(wallNormalD, openingCentroidCam) + Double(wallOffset)
        let depth = abs(signedDist)

        let centroidPixel = DimensionsData.Point2(
            x: opening.boundingPolygon.map(\.x).reduce(0, +) / Double(opening.boundingPolygon.count),
            y: opening.boundingPolygon.map(\.y).reduce(0, +) / Double(opening.boundingPolygon.count)
        )

        return DimensionsData.Measurement(
            type: .linear,
            label: "Opening Depth",
            worldPoints: [
                DimensionsData.Point3(x: openingCentroidCam.x,
                                      y: openingCentroidCam.y,
                                      z: openingCentroidCam.z),
                DimensionsData.Point3(x: openingCentroidCam.x - wallNormalD.x * signedDist,
                                      y: openingCentroidCam.y - wallNormalD.y * signedDist,
                                      z: openingCentroidCam.z - wallNormalD.z * signedDist)
            ],
            imagePoints: [centroidPixel, centroidPixel],
            valueMeters: depth,
            primaryDisplayUnit: .imperialFraction,
            labelPlacement: .init(side: .east, leaderLengthPx: 60),
            source: .auto
        )
    }

    // MARK: - Helpers

    private static func makeLinear(label: String,
                                   worldA: SIMD3<Double>, worldB: SIMD3<Double>,
                                   imageA: DimensionsData.Point2,
                                   imageB: DimensionsData.Point2) -> DimensionsData.Measurement {
        let dx = worldA.x - worldB.x
        let dy = worldA.y - worldB.y
        let dz = worldA.z - worldB.z
        let dist = (dx*dx + dy*dy + dz*dz).squareRoot()
        return DimensionsData.Measurement(
            type: .linear,
            label: label,
            worldPoints: [
                DimensionsData.Point3(x: worldA.x, y: worldA.y, z: worldA.z),
                DimensionsData.Point3(x: worldB.x, y: worldB.y, z: worldB.z)
            ],
            imagePoints: [imageA, imageB],
            valueMeters: dist,
            primaryDisplayUnit: .imperialFraction,
            labelPlacement: .init(side: .north, leaderLengthPx: 60),
            source: .auto
        )
    }
}
