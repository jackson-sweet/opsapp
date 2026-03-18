//
//  StarburstView.swift
//  OPS
//
//  3D rotating radial burst animation using SwiftUI Canvas.
//  Lines radiate from center using Fibonacci sphere distribution,
//  rotating around the Y-axis with a fixed X-axis tilt.
//  Front-hemisphere elements render in accent color, back in grey.
//
//  Ported from try-ops/components/animations/StarburstCanvas.tsx
//

import SwiftUI

// MARK: - Public View

/// Interactive 3D starburst animation. Renders 220 lines radiating from
/// center in all 3D directions, rotating continuously.
struct StarburstView: View {
    /// Optional size override. Defaults to fill available space.
    var size: CGFloat? = nil

    @State private var scene = StarburstScene.generate()
    @State private var yaw: Double = 0
    @State private var startDate = Date()

    // Constants matching the web implementation
    private static let tiltAngle: Double = 0.30 // ~17 degrees
    private static let rotationPeriodS: Double = 90
    private static let focalLength: Double = 2000

    private static let accent = SIMD3<Double>(89, 119, 148)  // #597794
    private static let grey = SIMD3<Double>(100, 100, 100)    // #646464

    var body: some View {
        SwiftUI.TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let currentYaw = elapsed * (2 * .pi / Self.rotationPeriodS)

            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2
                let radius = min(canvasSize.width, canvasSize.height) * 0.45

                drawStarburst(
                    context: &context,
                    cx: cx, cy: cy,
                    radius: radius,
                    yaw: currentYaw,
                    tilt: Self.tiltAngle
                )
            }
            .frame(width: size, height: size)
        }
    }

    // MARK: - Drawing

    private func drawStarburst(
        context: inout GraphicsContext,
        cx: Double, cy: Double,
        radius: Double,
        yaw: Double, tilt: Double
    ) {
        // Phase 1: Compute all 3D positions and project
        struct ComputedLine {
            let startX: Double, startY: Double
            let endX: Double, endY: Double
            let depth: Double
            let depthNorm: Double
            let opacity: Double
            let lineWidth: Double
            let color: SIMD3<Double>
            let hasNode: Bool
            let nodeX: Double, nodeY: Double
            let nodeSize: Double
            let nodeColor: SIMD3<Double>
            let nodeOpacity: Double
        }

        var computed: [ComputedLine] = []
        var maxZ: Double = 1

        // First pass: find maxZ for normalization
        for line in scene.lines {
            let ex = line.dx * radius * line.endDistance
            let ey = line.dy * radius * line.endDistance
            let ez = line.dz * radius * line.endDistance
            let r = Self.rotate(px: ex, py: ey, pz: ez, yaw: yaw, tilt: tilt)
            maxZ = max(maxZ, abs(r.z))

            for node in line.nodes {
                let nx = node.dx * radius * node.distance
                let ny = node.dy * radius * node.distance
                let nz = node.dz * radius * node.distance
                let nr = Self.rotate(px: nx, py: ny, pz: nz, yaw: yaw, tilt: tilt)
                maxZ = max(maxZ, abs(nr.z))
            }
        }

        // Second pass: project and compute styling
        for line in scene.lines {
            let ex = line.dx * radius * line.endDistance
            let ey = line.dy * radius * line.endDistance
            let ez = line.dz * radius * line.endDistance
            let r = Self.rotate(px: ex, py: ey, pz: ez, yaw: yaw, tilt: tilt)
            let p = Self.project(x: r.x, y: r.y, z: r.z, cx: cx, cy: cy)
            let depthNorm = (r.z / maxZ + 1) / 2

            let lineColor = Self.lerpColor(Self.grey, Self.accent, t: depthNorm)
            let lineOpacity = line.baseOpacity * (0.5 + depthNorm * 0.5)
            let lineWidth = line.hasNode
                ? (0.5 + depthNorm * 0.8)
                : (0.3 + depthNorm * 0.4)

            var nodeX: Double = 0, nodeY: Double = 0
            var nodeSize: Double = 0
            var nodeColor = Self.grey
            var nodeOpacity: Double = 0

            if let node = line.nodes.first {
                let nx = node.dx * radius * node.distance
                let ny = node.dy * radius * node.distance
                let nz = node.dz * radius * node.distance
                let nr = Self.rotate(px: nx, py: ny, pz: nz, yaw: yaw, tilt: tilt)
                let np = Self.project(x: nr.x, y: nr.y, z: nr.z, cx: cx, cy: cy)
                let nDepth = (nr.z / maxZ + 1) / 2
                let isFront = nr.z > 0

                nodeX = np.sx
                nodeY = np.sy
                nodeSize = node.size * np.scale
                nodeColor = node.interactive
                    ? Self.lerpColor(Self.grey, Self.accent, t: nDepth)
                    : Self.grey
                nodeOpacity = node.interactive
                    ? (isFront ? Self.lerp(0.25, 0.65, t: nDepth) : Self.lerp(0.10, 0.25, t: nDepth))
                    : Self.lerp(0.08, 0.20, t: nDepth)
            }

            computed.append(ComputedLine(
                startX: cx, startY: cy,
                endX: p.sx, endY: p.sy,
                depth: r.z,
                depthNorm: depthNorm,
                opacity: lineOpacity,
                lineWidth: lineWidth,
                color: lineColor,
                hasNode: line.hasNode,
                nodeX: nodeX, nodeY: nodeY,
                nodeSize: nodeSize,
                nodeColor: nodeColor,
                nodeOpacity: nodeOpacity
            ))
        }

        // Sort back-to-front
        computed.sort { $0.depth < $1.depth }

        // Draw
        for c in computed {
            // Draw line
            var linePath = Path()
            linePath.move(to: CGPoint(x: c.startX, y: c.startY))
            linePath.addLine(to: CGPoint(x: c.endX, y: c.endY))

            context.stroke(
                linePath,
                with: .color(Color(
                    red: c.color.x / 255,
                    green: c.color.y / 255,
                    blue: c.color.z / 255
                ).opacity(c.opacity)),
                lineWidth: c.lineWidth
            )

            // Draw node (small square)
            if c.hasNode && c.nodeSize > 0 {
                let half = c.nodeSize / 2
                let nodeRect = CGRect(
                    x: c.nodeX - half,
                    y: c.nodeY - half,
                    width: c.nodeSize,
                    height: c.nodeSize
                )
                context.fill(
                    Path(nodeRect),
                    with: .color(Color(
                        red: c.nodeColor.x / 255,
                        green: c.nodeColor.y / 255,
                        blue: c.nodeColor.z / 255
                    ).opacity(c.nodeOpacity))
                )
            }
        }
    }

    // MARK: - 3D Math

    /// Rotate point by yaw (Y-axis) then tilt (X-axis).
    private static func rotate(
        px: Double, py: Double, pz: Double,
        yaw: Double, tilt: Double
    ) -> (x: Double, y: Double, z: Double) {
        // Y-axis rotation
        let x1 = px * cos(yaw) + pz * sin(yaw)
        let z1 = -px * sin(yaw) + pz * cos(yaw)
        let y1 = py
        // X-axis tilt
        return (
            x: x1,
            y: y1 * cos(tilt) - z1 * sin(tilt),
            z: y1 * sin(tilt) + z1 * cos(tilt)
        )
    }

    /// Perspective projection. z > 0 = front (closer to viewer).
    private static func project(
        x: Double, y: Double, z: Double,
        cx: Double, cy: Double
    ) -> (sx: Double, sy: Double, scale: Double) {
        let scale = focalLength / (focalLength - z)
        return (sx: cx + x * scale, sy: cy + y * scale, scale: scale)
    }

    private static func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        a + (b - a) * t
    }

    private static func lerpColor(
        _ back: SIMD3<Double>,
        _ front: SIMD3<Double>,
        t: Double
    ) -> SIMD3<Double> {
        SIMD3(
            (lerp(back.x, front.x, t: t)).rounded(),
            (lerp(back.y, front.y, t: t)).rounded(),
            (lerp(back.z, front.z, t: t)).rounded()
        )
    }
}

// MARK: - Scene Data

private struct StarburstNode {
    let dx: Double, dy: Double, dz: Double
    let distance: Double
    let size: Double
    let interactive: Bool
}

private struct StarburstLine {
    let dx: Double, dy: Double, dz: Double
    let baseOpacity: Double
    let hasNode: Bool
    let endDistance: Double
    let nodes: [StarburstNode]
}

private struct StarburstScene {
    let lines: [StarburstLine]

    static func generate() -> StarburstScene {
        let lineCount = 220
        let goldenAngle = Double.pi * (1 + sqrt(5))
        var lines: [StarburstLine] = []

        for i in 0..<lineCount {
            let phi = acos(1 - 2 * (Double(i) + 0.5) / Double(lineCount))
            let theta = goldenAngle * Double(i)

            let dx = sin(phi) * cos(theta)
            let dy = sin(phi) * sin(theta)
            let dz = cos(phi)

            let baseOpacity = 0.18 + Double.random(in: 0..<0.16)
            let hasNode = Double.random(in: 0..<1) < 0.35
            var nodes: [StarburstNode] = []
            var endDistance: Double

            if hasNode {
                endDistance = 0.4 + Double.random(in: 0..<0.5)
                nodes.append(StarburstNode(
                    dx: dx, dy: dy, dz: dz,
                    distance: endDistance,
                    size: 4 + Double.random(in: 0..<3),
                    interactive: Double.random(in: 0..<1) < 0.5
                ))
            } else {
                endDistance = 0.3 + Double.random(in: 0..<0.2)
            }

            lines.append(StarburstLine(
                dx: dx, dy: dy, dz: dz,
                baseOpacity: baseOpacity,
                hasNode: hasNode,
                endDistance: endDistance,
                nodes: nodes
            ))
        }

        return StarburstScene(lines: lines)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        StarburstView(size: 300)
    }
}
