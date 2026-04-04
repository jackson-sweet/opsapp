// OPS/OPS/DeckBuilder/3D/DeckMeshGenerator.swift

import Foundation
import SceneKit

struct DeckMeshGenerator {

    // MARK: - Polygon Triangulation (Ear Clipping)

    /// Triangulate a simple polygon into triangles
    /// - Parameter vertices: Ordered polygon vertices (2D, CCW or CW)
    /// - Returns: Array of triangle index triples (into the input array)
    static func triangulate(vertices: [CGPoint]) -> [(Int, Int, Int)] {
        guard vertices.count >= 3 else { return [] }
        if vertices.count == 3 { return [(0, 1, 2)] }

        var indices = Array(0..<vertices.count)

        // Pre-pass: remove collinear vertices to prevent infinite loop in ear-clipping.
        // Three consecutive points where cross product ≈ 0 means the middle one is redundant.
        let collinearThreshold = 1e-6
        var cleaned = true
        while cleaned {
            cleaned = false
            var i = 0
            while i < indices.count && indices.count > 3 {
                let prevIdx = indices[(i - 1 + indices.count) % indices.count]
                let currIdx = indices[i]
                let nextIdx = indices[(i + 1) % indices.count]
                let cross = crossProduct(vertices[prevIdx], vertices[currIdx], vertices[nextIdx])
                if abs(cross) < collinearThreshold {
                    print("[DeckBuilder] triangulate: removing collinear vertex at index \(currIdx)")
                    indices.remove(at: i)
                    cleaned = true
                } else {
                    i += 1
                }
            }
        }

        guard indices.count >= 3 else {
            print("[DeckBuilder] triangulate: all vertices collinear, cannot triangulate")
            return []
        }
        if indices.count == 3 { return [(indices[0], indices[1], indices[2])] }

        var triangles: [(Int, Int, Int)] = []

        // Ensure CCW winding
        let filteredVerts = indices.map { vertices[$0] }
        let ccw = isCounterClockwise(filteredVerts)

        var maxIterations = indices.count * indices.count // safety limit
        while indices.count > 2 && maxIterations > 0 {
            maxIterations -= 1
            var earFound = false

            for i in 0..<indices.count {
                let prev = indices[(i - 1 + indices.count) % indices.count]
                let curr = indices[i]
                let next = indices[(i + 1) % indices.count]

                let a = vertices[prev]
                let b = vertices[curr]
                let c = vertices[next]

                // Check if this is a convex vertex
                let cross = crossProduct(a, b, c)
                let isConvex = ccw ? cross > 0 : cross < 0

                if !isConvex { continue }

                // Check if any other vertex is inside this triangle
                var isEar = true
                for j in 0..<indices.count {
                    let idx = indices[j]
                    if idx == prev || idx == curr || idx == next { continue }
                    if pointInTriangle(vertices[idx], a, b, c) {
                        isEar = false
                        break
                    }
                }

                if isEar {
                    triangles.append((prev, curr, next))
                    indices.remove(at: i)
                    earFound = true
                    break
                }
            }

            if !earFound { break } // degenerate polygon
        }

        return triangles
    }

    // MARK: - SCNGeometry from Polygon

    /// Create a flat SCNGeometry from a polygon at a given Y height
    /// - Parameters:
    ///   - vertices: 2D polygon vertices (in meters, XZ plane)
    ///   - yHeight: Y coordinate (elevation in meters)
    /// - Returns: SCNGeometry for the polygon surface
    static func createPolygonGeometry(
        vertices: [CGPoint],
        yHeight: Float
    ) -> SCNGeometry? {
        let triangles = triangulate(vertices: vertices)
        guard !triangles.isEmpty else { return nil }

        // Create 3D positions (x, yHeight, z)
        let positions: [SCNVector3] = vertices.map {
            SCNVector3(Float($0.x), yHeight, Float($0.y))
        }

        // Create normals (all pointing up)
        let normals: [SCNVector3] = Array(repeating: SCNVector3(0, 1, 0), count: positions.count)

        // Create texture coordinates (normalized 0-1 based on bounding box)
        let bounds = boundingRect(for: vertices)
        let texCoords: [CGPoint] = vertices.map {
            CGPoint(
                x: (Double($0.x) - Double(bounds.origin.x)) / Double(bounds.width),
                y: (Double($0.y) - Double(bounds.origin.y)) / Double(bounds.height)
            )
        }

        // Flatten triangle indices
        var indexData: [UInt16] = []
        for (a, b, c) in triangles {
            indexData.append(contentsOf: [UInt16(a), UInt16(b), UInt16(c)])
        }

        let positionSource = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)
        let texSource = SCNGeometrySource(textureCoordinates: texCoords)
        let element = SCNGeometryElement(
            indices: indexData,
            primitiveType: .triangles
        )

        return SCNGeometry(sources: [positionSource, normalSource, texSource], elements: [element])
    }

    /// Create a box (post, rail, tread) at a position with size
    static func createBox(
        position: SCNVector3,
        width: Float,
        height: Float,
        depth: Float,
        material: SCNMaterial
    ) -> SCNNode {
        let box = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(depth), chamferRadius: 0)
        box.firstMaterial = material
        let node = SCNNode(geometry: box)
        node.position = position
        return node
    }

    // MARK: - Helpers

    private static func crossProduct(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        (Double(b.x) - Double(a.x)) * (Double(c.y) - Double(a.y)) -
        (Double(b.y) - Double(a.y)) * (Double(c.x) - Double(a.x))
    }

    static func isCounterClockwise(_ vertices: [CGPoint]) -> Bool {
        var sum = 0.0
        for i in 0..<vertices.count {
            let j = (i + 1) % vertices.count
            sum += (Double(vertices[j].x) - Double(vertices[i].x)) * (Double(vertices[j].y) + Double(vertices[i].y))
        }
        return sum < 0
    }

    private static func pointInTriangle(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let d1 = crossProduct(a, b, p)
        let d2 = crossProduct(b, c, p)
        let d3 = crossProduct(c, a, p)
        let hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0)
        let hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0)
        return !(hasNeg && hasPos)
    }

    static func boundingRect(for vertices: [CGPoint]) -> CGRect {
        guard let first = vertices.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in vertices.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let w = max(maxX - minX, 0.001) // avoid zero width
        let h = max(maxY - minY, 0.001)
        return CGRect(x: minX, y: minY, width: w, height: h)
    }
}
