import CoreGraphics
import SceneKit
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias OPSPatternColor = UIColor
private typealias OPSPatternScalar = Float
#elseif canImport(AppKit)
import AppKit
private typealias OPSPatternColor = NSColor
private typealias OPSPatternScalar = CGFloat
#endif

public enum DeckPatternMeshBuilder {
    private enum RenderingToken {
        static let texturePixelSize = 256
        static let materialRoughness: CGFloat = 0.86
        static let minimumBoardWidthMeters: Double = 0.04
    }

    /// Builds one textured geometry for a surface pattern. `polygon` is in
    /// SceneKit X/Z units; board scale is real-world inches. The method never
    /// creates per-board nodes, preserving the mobile render budget.
    public static func surfaceMesh(
        polygon: [CGPoint],
        scaleFactor: Double,
        spec: SurfacePatternSpec,
        boardWidthInches: Double,
        yHeightMeters: Float = 0
    ) -> SCNGeometry? {
        let triangles = triangulate(vertices: polygon)
        guard !triangles.isEmpty else { return nil }

        let positions = polygon.map {
            SCNVector3(OPSPatternScalar($0.x), OPSPatternScalar(yHeightMeters), OPSPatternScalar($0.y))
        }
        let normals = Array(
            repeating: SCNVector3(OPSPatternScalar(0), OPSPatternScalar(1), OPSPatternScalar(0)),
            count: positions.count
        )
        let texCoords = textureCoordinates(
            for: polygon,
            boardWidthInches: boardWidthInches,
            scaleFactor: scaleFactor
        )
        var indexData: [UInt16] = []
        for (a, b, c) in triangles {
            indexData.append(contentsOf: [UInt16(a), UInt16(b), UInt16(c)])
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: texCoords),
            ],
            elements: [
                SCNGeometryElement(indices: indexData, primitiveType: .triangles),
            ]
        )
        geometry.name = "deck_pattern.\(spec.pattern.rawValue)"
        geometry.firstMaterial = material(for: spec)
        return geometry
    }

    public static func surfaceNode(
        polygon: [CGPoint],
        scaleFactor: Double,
        spec: SurfacePatternSpec,
        boardWidthInches: Double,
        yHeightMeters: Float = 0
    ) -> SCNNode? {
        guard let geometry = surfaceMesh(
            polygon: polygon,
            scaleFactor: scaleFactor,
            spec: spec,
            boardWidthInches: boardWidthInches,
            yHeightMeters: yHeightMeters
        ) else { return nil }

        let node = SCNNode(geometry: geometry)
        node.name = "deck_pattern.surface.\(spec.surfaceId)"
        return node
    }

    private static func material(for spec: SurfacePatternSpec) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "deck_pattern.\(spec.pattern.rawValue).texture"
        material.lightingModel = .physicallyBased
        material.diffuse.contents = makeTexture(for: spec) ?? sceneColor(OPSStyle.Colors.tan)
        material.roughness.contents = RenderingToken.materialRoughness
        material.metalness.contents = 0
        material.isDoubleSided = true
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.minificationFilter = .linear
        material.diffuse.magnificationFilter = .linear
        material.diffuse.mipFilter = .linear
        return material
    }

    private static func textureCoordinates(
        for polygon: [CGPoint],
        boardWidthInches: Double,
        scaleFactor: Double
    ) -> [CGPoint] {
        let bounds = boundingRect(for: polygon)
        let boardWidthMeters = max(
            RenderingToken.minimumBoardWidthMeters,
            boardWidthInches / 39.3701
        )
        let repeatScale = max(1, 1 / boardWidthMeters)
        let scaleAdjustment = max(scaleFactor, 0.0001)

        return polygon.map {
            CGPoint(
                x: ((Double($0.x) - Double(bounds.minX)) * repeatScale) / scaleAdjustment,
                y: ((Double($0.y) - Double(bounds.minY)) * repeatScale) / scaleAdjustment
            )
        }
    }

    private static func makeTexture(for spec: SurfacePatternSpec) -> CGImage? {
        let size = RenderingToken.texturePixelSize
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        fill(context, size: size, color: OPSStyle.Colors.tan)
        drawBoardLines(in: context, size: size, spec: spec)
        if spec.pattern == .pictureFrame || spec.pictureFrameCourses > 0 {
            drawPictureFrame(in: context, size: size, courses: max(1, spec.pictureFrameCourses))
        }

        return context.makeImage()
    }

    private static func drawBoardLines(
        in context: CGContext,
        size: Int,
        spec: SurfacePatternSpec
    ) {
        context.saveGState()
        context.translateBy(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        context.rotate(by: CGFloat(patternAngleDegrees(spec)) * .pi / 180)
        context.translateBy(x: -CGFloat(size) / 2, y: -CGFloat(size) / 2)
        context.setLineWidth(2)
        context.setStrokeColor(cgColor(OPSStyle.Colors.line))

        for x in stride(from: -size, through: size * 2, by: 14) {
            context.move(to: CGPoint(x: x, y: -size))
            context.addLine(to: CGPoint(x: x, y: size * 2))
        }
        context.strokePath()
        context.restoreGState()

        if spec.pattern == .herringbone || spec.pattern == .chevron {
            context.saveGState()
            context.translateBy(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
            context.rotate(by: -CGFloat(patternAngleDegrees(spec)) * .pi / 180)
            context.translateBy(x: -CGFloat(size) / 2, y: -CGFloat(size) / 2)
            context.setLineWidth(1)
            context.setStrokeColor(cgColor(OPSStyle.Colors.textMute))
            for x in stride(from: -size, through: size * 2, by: 28) {
                context.move(to: CGPoint(x: x, y: -size))
                context.addLine(to: CGPoint(x: x, y: size * 2))
            }
            context.strokePath()
            context.restoreGState()
        }
    }

    private static func drawPictureFrame(
        in context: CGContext,
        size: Int,
        courses: Int
    ) {
        context.setStrokeColor(cgColor(OPSStyle.Colors.text2))
        context.setLineWidth(4)
        for course in 0..<min(courses, 4) {
            let inset = CGFloat(8 + course * 10)
            context.stroke(CGRect(
                x: inset,
                y: inset,
                width: CGFloat(size) - inset * 2,
                height: CGFloat(size) - inset * 2
            ))
        }
    }

    private static func patternAngleDegrees(_ spec: SurfacePatternSpec) -> Double {
        switch spec.pattern {
        case .parallel, .pictureFrame:
            return spec.boardAngleDegrees
        case .diagonal:
            return spec.boardAngleDegrees == 0 ? 45 : spec.boardAngleDegrees
        case .herringbone, .chevron:
            return spec.boardAngleDegrees == 0 ? 45 : spec.boardAngleDegrees
        }
    }

    private static func triangulate(vertices: [CGPoint]) -> [(Int, Int, Int)] {
        guard vertices.count >= 3 else { return [] }
        if vertices.count == 3 { return [(0, 1, 2)] }

        var indices = Array(0..<vertices.count)
        var cleaned = true
        while cleaned {
            cleaned = false
            var index = 0
            while index < indices.count && indices.count > 3 {
                let previous = indices[(index - 1 + indices.count) % indices.count]
                let current = indices[index]
                let next = indices[(index + 1) % indices.count]
                if abs(crossProduct(vertices[previous], vertices[current], vertices[next])) < 1e-6 {
                    indices.remove(at: index)
                    cleaned = true
                } else {
                    index += 1
                }
            }
        }

        guard indices.count >= 3 else { return [] }
        if indices.count == 3 { return [(indices[0], indices[1], indices[2])] }

        let filtered = indices.map { vertices[$0] }
        let isCCW = isCounterClockwise(filtered)
        var triangles: [(Int, Int, Int)] = []
        var maxIterations = indices.count * indices.count

        while indices.count > 2 && maxIterations > 0 {
            maxIterations -= 1
            var earFound = false
            for index in 0..<indices.count {
                let previous = indices[(index - 1 + indices.count) % indices.count]
                let current = indices[index]
                let next = indices[(index + 1) % indices.count]
                let cross = crossProduct(vertices[previous], vertices[current], vertices[next])
                let convex = isCCW ? cross > 0 : cross < 0
                guard convex else { continue }

                let containsPoint = indices.contains { other in
                    guard other != previous, other != current, other != next else { return false }
                    return pointInTriangle(
                        vertices[other],
                        vertices[previous],
                        vertices[current],
                        vertices[next]
                    )
                }
                guard !containsPoint else { continue }

                triangles.append((previous, current, next))
                indices.remove(at: index)
                earFound = true
                break
            }
            if !earFound { break }
        }

        return triangles
    }

    private static func crossProduct(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        (Double(b.x) - Double(a.x)) * (Double(c.y) - Double(a.y)) -
            (Double(b.y) - Double(a.y)) * (Double(c.x) - Double(a.x))
    }

    private static func isCounterClockwise(_ vertices: [CGPoint]) -> Bool {
        var sum = 0.0
        for index in 0..<vertices.count {
            let next = (index + 1) % vertices.count
            sum += (Double(vertices[next].x) - Double(vertices[index].x)) *
                (Double(vertices[next].y) + Double(vertices[index].y))
        }
        return sum < 0
    }

    private static func pointInTriangle(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let d1 = crossProduct(a, b, p)
        let d2 = crossProduct(b, c, p)
        let d3 = crossProduct(c, a, p)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }

    private static func boundingRect(for vertices: [CGPoint]) -> CGRect {
        guard let first = vertices.first else { return .zero }
        return vertices.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partial, point in
            partial.union(CGRect(origin: point, size: .zero))
        }
    }

    private static func fill(_ context: CGContext, size: Int, color: Color) {
        context.setFillColor(cgColor(color))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }

    private static func sceneColor(_ color: Color) -> OPSPatternColor {
        OPSPatternColor(color)
    }

    private static func cgColor(_ color: Color) -> CGColor {
        let sceneColor = OPSPatternColor(color)
        #if canImport(AppKit)
        return sceneColor.usingColorSpace(.deviceRGB)?.cgColor ?? sceneColor.cgColor
        #else
        return sceneColor.cgColor
        #endif
    }
}
