// OPS/OPS/DeckBuilder/AR/ARPerimeterViewModel.swift

import Foundation
import SwiftUI
import Combine
import UIKit
import CoreLocation
import simd

@MainActor
class ARPerimeterViewModel: ObservableObject {

    // MARK: - Vertex & Edge State

    @Published var arVertices: [ARCoordinateConverter.ARVertex] = []
    @Published var arEdges: [ARCoordinateConverter.AREdge] = []

    // MARK: - AR Session State

    @Published var isPlaneDetected: Bool = false
    @Published var isClosed: Bool = false
    @Published var isNearFirstVertex: Bool = false
    @Published var currentCrosshairPosition: SIMD3<Float>?
    @Published var showPlaneTimeoutAlert: Bool = false
    private var planeDetectionTask: Task<Void, Never>?

    // MARK: - Alignment Guides (AR Space)

    struct ARAlignmentGuide {
        let from: SIMD3<Float>
        let to: SIMD3<Float>
        let type: AlignmentGuideType  // reuse the canvas enum
    }

    @Published var activeAlignmentGuides: [ARAlignmentGuide] = []

    // MARK: - UI State

    @Published var liveDimensionLabel: String = ""
    @Published var angleSnappingEnabled: Bool = false   // Off for first line, auto-enabled after
    @Published var lengthSnappingEnabled: Bool = true
    @Published var isEditingVertex: Bool = false
    @Published var editingVertexIndex: Int?
    @Published var showVertexPopover: Bool = false
    @Published var popoverVertexIndex: Int?
    @Published var isSplittingEdge: Bool = false
    @Published var splittingEdgeIndex: Int?

    // MARK: - Assignment Wheel

    @Published var activeAssignment: AssignedItem?
    @Published var activeEdgeType: EdgeType = .deckEdge
    @Published var activeRailingConfig: RailingConfig?

    var currentAssignmentLabel: String? {
        if activeEdgeType == .houseEdge { return "House Edge" }
        if let railing = activeRailingConfig { return railing.railingType.displayName }
        if let item = activeAssignment { return item.name }
        return nil
    }

    // MARK: - AR Address Detection

    @Published var detectedAddress: String?
    @Published var showAddressPrompt: Bool = false

    // MARK: - 3D Entity Names (for renderer cleanup)

    var vertexEntityNames: [String] = []
    var edgeEntityNames: [String] = []

    // MARK: - Render Versioning

    /// Incremented on any vertex/edge mutation (reposition, delete, split) to trigger 3D re-render.
    /// Count-based detection misses same-count mutations like vertex repositioning.
    @Published var renderVersion: Int = 0

    // MARK: - Constants

    private let closeLoopRadius: Float = 0.1           // meters ≈ 4" — tight snap, deliberate close only
    private let metersToInches: Double = 39.3701
    private let angleSnapIncrement: Double = 15.0     // degrees
    private let angleSnapTolerance: Double = 7.5      // degrees within which to snap
    private let lengthSnapIncrementMeters: Double = 0.1524  // 6 inches

    // MARK: - Haptic Generators

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let successNotification = UINotificationFeedbackGenerator()

    // MARK: - Init

    init() {
        lightImpact.prepare()
        mediumImpact.prepare()
        successNotification.prepare()
        startPlaneDetectionTimeout()
    }

    // MARK: - Plane Detection Timeout

    func startPlaneDetectionTimeout() {
        planeDetectionTask?.cancel()
        showPlaneTimeoutAlert = false
        planeDetectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            guard !Task.isCancelled else { return }
            guard let self, !self.isPlaneDetected else { return }
            self.showPlaneTimeoutAlert = true
        }
    }

    func cancelPlaneDetectionTimeout() {
        planeDetectionTask?.cancel()
        planeDetectionTask = nil
    }

    // MARK: - Record Vertex

    /// Place a vertex at the current crosshair world position
    /// - Parameter worldPosition: The raycast hit position in AR world space
    func recordVertex(worldPosition: SIMD3<Float>) {
        guard !isClosed else { return }

        var finalPosition = worldPosition
        var didSnap = false

        // Angle snapping — only for 3rd+ vertices (second line onward).
        // First line has no previous edge to reference, so angle snap is disabled.
        if angleSnappingEnabled && arVertices.count >= 2 {
            let snappedResult = snapAngleInWorldSpace(
                newPosition: finalPosition,
                previousPosition: simd3(arVertices[arVertices.count - 1]),
                priorPosition: simd3(arVertices[arVertices.count - 2])
            )
            finalPosition = snappedResult.position
            didSnap = didSnap || snappedResult.didSnap
        }

        // Length snapping — available for all lines (2nd vertex onward)
        if lengthSnappingEnabled, let lastVertex = arVertices.last {
            let snappedResult = snapLength(position: finalPosition, fromPosition: simd3(lastVertex))
            finalPosition = snappedResult.position
            didSnap = didSnap || snappedResult.didSnap
        }

        if didSnap {
            lightImpact.impactOccurred()
        }

        let vertexId = UUID().uuidString
        let vertex = ARCoordinateConverter.ARVertex(
            id: vertexId,
            x: Double(finalPosition.x),
            z: Double(finalPosition.z),
            y: Double(finalPosition.y)
        )
        arVertices.append(vertex)
        renderVersion += 1

        // Auto-enable angle snapping after first line is placed (2nd vertex down)
        if arVertices.count == 2 && !angleSnappingEnabled {
            angleSnappingEnabled = true
        }

        // Create edge from previous vertex
        if arVertices.count >= 2 {
            let prev = arVertices[arVertices.count - 2]
            let dx = vertex.x - prev.x
            let dz = vertex.z - prev.z
            let distanceMeters = sqrt(dx * dx + dz * dz)
            let accuracyPercent = AccuracyModel.estimateAccuracy(distanceMeters: distanceMeters)

            var edge = ARCoordinateConverter.AREdge(
                id: UUID().uuidString,
                startVertexId: prev.id,
                endVertexId: vertex.id,
                distanceMeters: distanceMeters,
                accuracyPercent: accuracyPercent,
                edgeType: activeEdgeType,
                railingConfig: activeRailingConfig
            )

            // Apply active linear assignment
            if let assignment = activeAssignment,
               assignment.unitType == .linearFoot || assignment.unitType == .linearMeter {
                edge.assignedItems.append(assignment)
            }

            arEdges.append(edge)
        }

        activeAlignmentGuides = []
        mediumImpact.impactOccurred()
    }

    // MARK: - Close Loop

    /// Close the polygon by connecting the last vertex to the first
    func closeLoop() {
        guard arVertices.count >= 3, !isClosed else { return }

        let first = arVertices[0]
        let last = arVertices[arVertices.count - 1]
        let dx = first.x - last.x
        let dz = first.z - last.z
        let distanceMeters = sqrt(dx * dx + dz * dz)
        let accuracyPercent = AccuracyModel.estimateAccuracy(distanceMeters: distanceMeters)

        var edge = ARCoordinateConverter.AREdge(
            id: UUID().uuidString,
            startVertexId: last.id,
            endVertexId: first.id,
            distanceMeters: distanceMeters,
            accuracyPercent: accuracyPercent,
            edgeType: activeEdgeType,
            railingConfig: activeRailingConfig
        )

        if let assignment = activeAssignment,
           assignment.unitType == .linearFoot || assignment.unitType == .linearMeter {
            edge.assignedItems.append(assignment)
        }

        arEdges.append(edge)
        isClosed = true
        isNearFirstVertex = false
        renderVersion += 1

        successNotification.notificationOccurred(.success)
    }

    // MARK: - Crosshair Update (Called Every Frame)

    /// Update the current crosshair position from the AR raycast result
    /// - Parameter position: World-space position of the raycast hit
    func updateCrosshairPosition(_ position: SIMD3<Float>) {
        guard !isClosed else {
            currentCrosshairPosition = position
            liveDimensionLabel = ""
            return
        }

        // Apply real-time snapping so the crosshair shows the snapped position
        var snappedPosition = position
        if let lastVertex = arVertices.last {
            let lastPos = simd3(lastVertex)

            // Angle snapping — only for 3rd+ vertices (second line onward)
            if angleSnappingEnabled && arVertices.count >= 2 {
                let priorPos = simd3(arVertices[arVertices.count - 2])
                let result = snapAngleInWorldSpace(
                    newPosition: snappedPosition, previousPosition: lastPos, priorPosition: priorPos)
                snappedPosition = result.position
            }

            // Length snapping — available for all lines
            if lengthSnappingEnabled {
                let result = snapLength(position: snappedPosition, fromPosition: lastPos)
                snappedPosition = result.position
            }

            // Alignment guides — detect and apply axis/parallel/perpendicular snaps
            if arVertices.count >= 2 {
                let (alignedPos, guides) = detectARAlignmentGuides(from: lastPos, currentEnd: snappedPosition)
                if guides.contains(where: { $0.type == .vertical || $0.type == .horizontal }) {
                    snappedPosition = alignedPos
                }
                activeAlignmentGuides = guides
            } else {
                activeAlignmentGuides = []
            }
        } else {
            activeAlignmentGuides = []
        }

        currentCrosshairPosition = snappedPosition

        // Live dimension label from the snapped position
        if let lastVertex = arVertices.last {
            let lastPos = simd3(lastVertex)
            let dx = Double(snappedPosition.x - lastPos.x)
            let dz = Double(snappedPosition.z - lastPos.z)
            let distanceMeters = sqrt(dx * dx + dz * dz)
            let distanceInches = distanceMeters * metersToInches
            let accuracy = AccuracyModel.estimateAccuracy(distanceMeters: distanceMeters)
            let dimLabel = "~" + DimensionEngine.formatImperial(distanceInches)
            let accLabel = AccuracyModel.formatAccuracy(dimensionInches: distanceInches, accuracyPercent: accuracy)
            liveDimensionLabel = "\(dimLabel) \(accLabel)"
        } else {
            liveDimensionLabel = ""
        }

        // Check proximity to first vertex for close-loop
        if arVertices.count >= 3, let first = arVertices.first {
            let firstPos = simd3(first)
            let distance = simd_distance(snappedPosition, firstPos)
            isNearFirstVertex = distance < closeLoopRadius
        } else {
            isNearFirstVertex = false
        }
    }

    // MARK: - Undo Last Vertex

    func undoLastVertex() {
        guard !arVertices.isEmpty, !isClosed else { return }

        arVertices.removeLast()
        if !arEdges.isEmpty {
            arEdges.removeLast()
        }

        // Disable angle snapping if back to first-line territory
        if arVertices.count < 2 {
            angleSnappingEnabled = false
        }

        // Reset close-loop state
        isNearFirstVertex = false
        liveDimensionLabel = ""
        renderVersion += 1

        lightImpact.impactOccurred()
    }

    // MARK: - Line Split (Missed Corner)

    /// Split an existing edge by inserting a new vertex at the crosshair position
    /// - Parameters:
    ///   - edgeIndex: Index of the edge to split
    ///   - newPosition: World-space position of the new vertex
    func splitEdge(edgeIndex: Int, at newPosition: SIMD3<Float>) {
        guard edgeIndex >= 0, edgeIndex < arEdges.count else { return }

        let oldEdge = arEdges[edgeIndex]

        // Create new vertex
        let newVertexId = UUID().uuidString
        let newVertex = ARCoordinateConverter.ARVertex(
            id: newVertexId,
            x: Double(newPosition.x),
            z: Double(newPosition.z),
            y: Double(newPosition.y)
        )

        // Find the start and end vertices of the split edge
        guard let startVertex = arVertices.first(where: { $0.id == oldEdge.startVertexId }),
              let endVertex = arVertices.first(where: { $0.id == oldEdge.endVertexId }) else { return }

        // Calculate distances for the two new edges
        let dx1 = newVertex.x - startVertex.x
        let dz1 = newVertex.z - startVertex.z
        let dist1 = sqrt(dx1 * dx1 + dz1 * dz1)

        let dx2 = endVertex.x - newVertex.x
        let dz2 = endVertex.z - newVertex.z
        let dist2 = sqrt(dx2 * dx2 + dz2 * dz2)

        // Create two new edges
        let edge1 = ARCoordinateConverter.AREdge(
            id: UUID().uuidString,
            startVertexId: oldEdge.startVertexId,
            endVertexId: newVertexId,
            distanceMeters: dist1,
            accuracyPercent: AccuracyModel.estimateAccuracy(distanceMeters: dist1),
            edgeType: oldEdge.edgeType,
            railingConfig: oldEdge.railingConfig,
            assignedItems: oldEdge.assignedItems
        )

        let edge2 = ARCoordinateConverter.AREdge(
            id: UUID().uuidString,
            startVertexId: newVertexId,
            endVertexId: oldEdge.endVertexId,
            distanceMeters: dist2,
            accuracyPercent: AccuracyModel.estimateAccuracy(distanceMeters: dist2),
            edgeType: oldEdge.edgeType,
            railingConfig: oldEdge.railingConfig,
            assignedItems: oldEdge.assignedItems
        )

        // Insert vertex after the start vertex
        if let insertIndex = arVertices.firstIndex(where: { $0.id == oldEdge.endVertexId }) {
            arVertices.insert(newVertex, at: insertIndex)
        } else {
            arVertices.append(newVertex)
        }

        // Replace old edge with two new edges
        arEdges.remove(at: edgeIndex)
        arEdges.insert(edge2, at: edgeIndex)
        arEdges.insert(edge1, at: edgeIndex)

        isSplittingEdge = false
        splittingEdgeIndex = nil
        renderVersion += 1

        lightImpact.impactOccurred()
    }

    // MARK: - Vertex Reposition

    /// Reposition an existing vertex to the current crosshair position
    /// - Parameters:
    ///   - index: Index of the vertex to reposition
    ///   - newPosition: New world-space position
    func repositionVertex(index: Int, to newPosition: SIMD3<Float>) {
        guard index >= 0, index < arVertices.count else { return }

        let oldVertex = arVertices[index]
        let newVertex = ARCoordinateConverter.ARVertex(
            id: oldVertex.id,
            x: Double(newPosition.x),
            z: Double(newPosition.z),
            y: Double(newPosition.y)
        )
        arVertices[index] = newVertex

        // Recalculate connected edges
        for i in 0..<arEdges.count {
            let edge = arEdges[i]
            if edge.startVertexId == oldVertex.id || edge.endVertexId == oldVertex.id {
                guard let startV = arVertices.first(where: { $0.id == edge.startVertexId }),
                      let endV = arVertices.first(where: { $0.id == edge.endVertexId }) else { continue }
                let dx = endV.x - startV.x
                let dz = endV.z - startV.z
                let dist = sqrt(dx * dx + dz * dz)
                arEdges[i] = ARCoordinateConverter.AREdge(
                    id: edge.id,
                    startVertexId: edge.startVertexId,
                    endVertexId: edge.endVertexId,
                    distanceMeters: dist,
                    accuracyPercent: AccuracyModel.estimateAccuracy(distanceMeters: dist),
                    edgeType: edge.edgeType,
                    railingConfig: edge.railingConfig,
                    assignedItems: edge.assignedItems
                )
            }
        }

        isEditingVertex = false
        editingVertexIndex = nil
        renderVersion += 1
        mediumImpact.impactOccurred()
    }

    // MARK: - Delete Vertex

    /// Delete a vertex and merge its adjacent edges
    /// - Parameter index: Index of the vertex to delete
    func deleteVertex(index: Int) {
        guard index >= 0, index < arVertices.count, arVertices.count > 2 else { return }

        let vertex = arVertices[index]

        // Find edges connected to this vertex
        let connectedEdgeIndices = arEdges.enumerated().compactMap { idx, edge -> Int? in
            (edge.startVertexId == vertex.id || edge.endVertexId == vertex.id) ? idx : nil
        }

        // If exactly two edges connect (normal case), merge them
        if connectedEdgeIndices.count == 2 {
            let edge1 = arEdges[connectedEdgeIndices[0]]
            let edge2 = arEdges[connectedEdgeIndices[1]]

            // Find the two other vertices (not the one being deleted)
            let otherStart = edge1.startVertexId == vertex.id ? edge1.endVertexId : edge1.startVertexId
            let otherEnd = edge2.startVertexId == vertex.id ? edge2.endVertexId : edge2.startVertexId

            // Create merged edge
            guard let startV = arVertices.first(where: { $0.id == otherStart }),
                  let endV = arVertices.first(where: { $0.id == otherEnd }) else { return }
            let dx = endV.x - startV.x
            let dz = endV.z - startV.z
            let dist = sqrt(dx * dx + dz * dz)

            let mergedEdge = ARCoordinateConverter.AREdge(
                id: UUID().uuidString,
                startVertexId: otherStart,
                endVertexId: otherEnd,
                distanceMeters: dist,
                accuracyPercent: AccuracyModel.estimateAccuracy(distanceMeters: dist)
            )

            // Remove old edges (in reverse index order to avoid shifting)
            for idx in connectedEdgeIndices.sorted().reversed() {
                arEdges.remove(at: idx)
            }

            // Insert merged edge at the position of the first removed edge
            let insertIdx = min(connectedEdgeIndices[0], arEdges.count)
            arEdges.insert(mergedEdge, at: insertIdx)
        } else {
            // Edge case: remove all connected edges
            for idx in connectedEdgeIndices.sorted().reversed() {
                arEdges.remove(at: idx)
            }
        }

        // Remove vertex
        arVertices.remove(at: index)

        // Reset closed state — polygon is no longer closed after vertex removal
        if isClosed {
            isClosed = false
            isNearFirstVertex = false
        }

        isEditingVertex = false
        editingVertexIndex = nil
        renderVersion += 1
        lightImpact.impactOccurred()
    }

    // MARK: - Convert to DeckDrawingData

    /// Convert the AR walk result to a DeckDrawingData for the 2D canvas
    func toDrawingData(canvasWidth: CGFloat = 4800, canvasHeight: CGFloat = 4800) -> DeckDrawingData {
        ARCoordinateConverter.convert(
            arVertices: arVertices,
            arEdges: arEdges,
            isClosed: isClosed,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )
    }

    // MARK: - Angle Snapping Helpers

    private struct SnapResult {
        let position: SIMD3<Float>
        let didSnap: Bool
    }

    /// Snap the new vertex angle relative to the previous edge direction
    private func snapAngleInWorldSpace(
        newPosition: SIMD3<Float>,
        previousPosition: SIMD3<Float>,
        priorPosition: SIMD3<Float>
    ) -> SnapResult {
        // Calculate the angle of the previous edge (prior → previous)
        let prevDx = Double(previousPosition.x - priorPosition.x)
        let prevDz = Double(previousPosition.z - priorPosition.z)
        let prevAngle = atan2(prevDz, prevDx) * 180.0 / .pi

        // Calculate the angle of the new edge (previous → new)
        let newDx = Double(newPosition.x - previousPosition.x)
        let newDz = Double(newPosition.z - previousPosition.z)
        let newAngle = atan2(newDz, newDx) * 180.0 / .pi

        // Calculate the turn angle
        var turnAngle = newAngle - prevAngle
        if turnAngle > 180 { turnAngle -= 360 }
        if turnAngle < -180 { turnAngle += 360 }

        // Snap the turn angle directly — round to nearest increment preserving sign
        let snappedTurn = (turnAngle / angleSnapIncrement).rounded() * angleSnapIncrement
        let angleDiff = abs(turnAngle - snappedTurn)

        if angleDiff < angleSnapTolerance && angleDiff > 0.1 {
            // Apply snap: adjust the new position to match the snapped angle
            let snappedAbsoluteAngle = (prevAngle + snappedTurn) * .pi / 180.0
            let distance = sqrt(newDx * newDx + newDz * newDz)
            let snappedX = Double(previousPosition.x) + distance * cos(snappedAbsoluteAngle)
            let snappedZ = Double(previousPosition.z) + distance * sin(snappedAbsoluteAngle)
            return SnapResult(
                position: SIMD3<Float>(Float(snappedX), newPosition.y, Float(snappedZ)),
                didSnap: true
            )
        }

        return SnapResult(position: newPosition, didSnap: false)
    }

    /// Snap the second vertex to cardinal angles relative to world axes
    private func snapAngleToCardinal(newPosition: SIMD3<Float>, fromPosition: SIMD3<Float>) -> SnapResult {
        let dx = Double(newPosition.x - fromPosition.x)
        let dz = Double(newPosition.z - fromPosition.z)
        let angle = atan2(dz, dx) * 180.0 / .pi
        let normalizedAngle = angle < 0 ? angle + 360 : angle

        let snappedAngle = SnapEngine.snapAngle(normalizedAngle, increment: angleSnapIncrement)
        let diff = abs(normalizedAngle - snappedAngle)

        if diff < angleSnapTolerance && diff > 0.1 {
            let distance = sqrt(dx * dx + dz * dz)
            let radians = snappedAngle * .pi / 180.0
            let snappedX = Double(fromPosition.x) + distance * cos(radians)
            let snappedZ = Double(fromPosition.z) + distance * sin(radians)
            return SnapResult(
                position: SIMD3<Float>(Float(snappedX), newPosition.y, Float(snappedZ)),
                didSnap: true
            )
        }

        return SnapResult(position: newPosition, didSnap: false)
    }

    /// Snap the distance from a reference point to the nearest length increment (6 inches)
    private func snapLength(position: SIMD3<Float>, fromPosition: SIMD3<Float>) -> SnapResult {
        let dx = Double(position.x - fromPosition.x)
        let dz = Double(position.z - fromPosition.z)
        let distance = sqrt(dx * dx + dz * dz)

        guard distance > 0 else {
            return SnapResult(position: position, didSnap: false)
        }

        let snappedDistance = (distance / lengthSnapIncrementMeters).rounded() * lengthSnapIncrementMeters
        let diff = abs(distance - snappedDistance)

        if diff > 0.001 {
            let scale = snappedDistance / distance
            let snappedX = Double(fromPosition.x) + dx * scale
            let snappedZ = Double(fromPosition.z) + dz * scale
            return SnapResult(
                position: SIMD3<Float>(Float(snappedX), position.y, Float(snappedZ)),
                didSnap: true
            )
        }

        return SnapResult(position: position, didSnap: false)
    }

    /// Convert ARVertex to SIMD3<Float> for distance checks
    private func simd3(_ vertex: ARCoordinateConverter.ARVertex) -> SIMD3<Float> {
        SIMD3<Float>(Float(vertex.x), Float(vertex.y), Float(vertex.z))
    }

    // MARK: - Alignment Guide Detection (AR World Space)

    /// Detect axis alignment, parallel, and perpendicular guides in AR world space.
    /// Works on the ground plane (X/Z). Returns a snapped position and active guides.
    private func detectARAlignmentGuides(
        from start: SIMD3<Float>,
        currentEnd: SIMD3<Float>
    ) -> (snapped: SIMD3<Float>, guides: [ARAlignmentGuide]) {
        let threshold: Float = 0.08  // ~3 inches in world meters
        let angleThreshold: Double = 2.0  // degrees
        var guides: [ARAlignmentGuide] = []
        var snappedX = currentEnd.x
        var snappedZ = currentEnd.z
        var bestDx: Float = threshold + 1
        var bestDz: Float = threshold + 1

        // Exclude the start vertex from detection
        let startVertexId = arVertices.last?.id

        // --- Axis alignment with existing vertices ---
        for vertex in arVertices {
            if vertex.id == startVertexId { continue }
            let vx = Float(vertex.x)
            let vz = Float(vertex.z)

            // X alignment (vertical guide in plan view)
            let dx = abs(currentEnd.x - vx)
            if dx < threshold && dx < bestDx {
                bestDx = dx
                snappedX = vx
                guides.removeAll { $0.type == .vertical }
                let minZ = min(vz, currentEnd.z) - 0.3
                let maxZ = max(vz, currentEnd.z) + 0.3
                guides.append(ARAlignmentGuide(
                    from: SIMD3<Float>(vx, currentEnd.y, minZ),
                    to: SIMD3<Float>(vx, currentEnd.y, maxZ),
                    type: .vertical
                ))
            }

            // Z alignment (horizontal guide in plan view)
            let dz = abs(currentEnd.z - vz)
            if dz < threshold && dz < bestDz {
                bestDz = dz
                snappedZ = vz
                guides.removeAll { $0.type == .horizontal }
                let minX = min(vx, currentEnd.x) - 0.3
                let maxX = max(vx, currentEnd.x) + 0.3
                guides.append(ARAlignmentGuide(
                    from: SIMD3<Float>(minX, currentEnd.y, vz),
                    to: SIMD3<Float>(maxX, currentEnd.y, vz),
                    type: .horizontal
                ))
            }
        }

        // --- Parallel / Perpendicular to existing edges ---
        // Build id→vertex map once so inner edge lookup is O(1) instead of O(V).
        // This drops detectARAlignmentGuides from O(V*E) to O(V+E) per frame.
        var vertexMap: [String: ARCoordinateConverter.ARVertex] = [:]
        vertexMap.reserveCapacity(arVertices.count)
        for v in arVertices { vertexMap[v.id] = v }

        let snappedEnd = SIMD3<Float>(snappedX, currentEnd.y, snappedZ)
        let currentAngle = atan2(Double(snappedEnd.z - start.z), Double(snappedEnd.x - start.x)) * 180.0 / .pi

        for edge in arEdges {
            guard let sv = vertexMap[edge.startVertexId],
                  let ev = vertexMap[edge.endVertexId] else { continue }
            if edge.startVertexId == startVertexId || edge.endVertexId == startVertexId { continue }

            let edgeAngle = atan2(ev.z - sv.z, ev.x - sv.x) * 180.0 / .pi
            var angleDiff = abs(currentAngle - edgeAngle)
            if angleDiff > 180 { angleDiff = 360 - angleDiff }

            if angleDiff < angleThreshold || abs(angleDiff - 180) < angleThreshold {
                if !guides.contains(where: { $0.type == .parallel }) {
                    guides.append(ARAlignmentGuide(
                        from: SIMD3<Float>(Float(sv.x), Float(sv.y), Float(sv.z)),
                        to: SIMD3<Float>(Float(ev.x), Float(ev.y), Float(ev.z)),
                        type: .parallel
                    ))
                }
            }

            if abs(angleDiff - 90) < angleThreshold || abs(angleDiff - 270) < angleThreshold {
                if !guides.contains(where: { $0.type == .perpendicular }) {
                    guides.append(ARAlignmentGuide(
                        from: SIMD3<Float>(Float(sv.x), Float(sv.y), Float(sv.z)),
                        to: SIMD3<Float>(Float(ev.x), Float(ev.y), Float(ev.z)),
                        type: .perpendicular
                    ))
                }
            }
        }

        return (SIMD3<Float>(snappedX, currentEnd.y, snappedZ), guides)
    }

    // MARK: - Address Detection (Reverse Geocoding)

    /// Call once when the AR session detects a plane and has a valid device location.
    /// Uses CLGeocoder to reverse-geocode the device's GPS position.
    func detectAddress(latitude: Double, longitude: Double) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self, let placemark = placemarks?.first else {
                if let error = error {
                    print("[DeckBuilder] Reverse geocode failed: \(error.localizedDescription)")
                }
                return
            }
            let parts = [placemark.subThoroughfare, placemark.thoroughfare, placemark.locality, placemark.administrativeArea]
            let address = parts.compactMap { $0 }.joined(separator: " ")
            Task { @MainActor in
                self.detectedAddress = address
            }
        }
    }
}
