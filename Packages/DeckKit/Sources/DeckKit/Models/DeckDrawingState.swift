// OPS/OPS/DeckBuilder/Models/DeckDrawingState.swift

import Foundation
import SwiftUI

public enum DrawingTool: String {
    case draw           // tap-hold-drag to draw lines
    case select         // legacy rectangular marquee — kept for back-compat
    case lasso          // legacy freeform — kept for back-compat
    /// Combined select tool (DECK-NEW-4). Tap toggles individual elements;
    /// drag from empty space draws a marquee or lasso based on
    /// `marqueeShape`. Replaces the previous separate Select / Lasso /
    /// Multi tools.
    case tapSelect
    case none           // long-press always works regardless
}

/// Drag-shape sub-mode for `.tapSelect`. Toggleable from the selection
/// sub-toolbar so the user picks a rectangular marquee or freehand lasso
/// without leaving select mode. DECK-NEW-4.
public enum MarqueeShape: String, CaseIterable {
    case rect
    case lasso
}

public enum SelectableElementType: String, CaseIterable {
    case vertex
    case edge
    case face
}

public enum DrawingMode: Equatable {
    case idle                                      // no active gesture
    /// Actively dragging a line.
    /// `fromVertexId` is nil when the drag started in empty space — the start
    /// vertex is created on commit (endLine), not when the drag begins, so
    /// cancelled drags don't leak orphan vertices into the data.
    /// `startPosition` is the canvas-coordinate anchor of the line.
    case drawing(fromVertexId: String?, startPosition: CGPoint, currentEnd: CGPoint)
    case selecting(rect: CGRect)                   // dragging a selection rectangle
    case lassoing(points: [CGPoint])               // drawing a freeform lasso
    case draggingVertex(vertexId: String)           // repositioning a vertex in 2D
    case movingSelection                            // repositioning selected geometry as one XY group
    case movingPendingPaste                         // repositioning staged pasted geometry before commit
}

public struct SelectionState: Equatable {
    public var selectedEdgeIds: Set<String> = []
    public var selectedVertexIds: Set<String> = []
    /// Per-surface selection state — replaces the previous single-bool
    /// `selectedFootprint`. `selectedFootprint` is now a derived helper that
    /// returns true when ANY surface is selected (read-only). Callers that
    /// need to clear surface selection should mutate `selectedSurfaceIds`
    /// directly. DECK-NEW-1.
    public var selectedSurfaceIds: Set<String> = []

    /// Legacy compat — true when at least one surface is selected.
    public var selectedFootprint: Bool { !selectedSurfaceIds.isEmpty }

    public var isEmpty: Bool {
        selectedEdgeIds.isEmpty && selectedVertexIds.isEmpty && selectedSurfaceIds.isEmpty
    }

    public var hasEdges: Bool { !selectedEdgeIds.isEmpty }
    public var hasVertices: Bool { !selectedVertexIds.isEmpty }
    public var hasSurfaces: Bool { !selectedSurfaceIds.isEmpty }

    public init(
        selectedEdgeIds: Set<String> = [],
        selectedVertexIds: Set<String> = [],
        selectedSurfaceIds: Set<String> = []
    ) {
        self.selectedEdgeIds = selectedEdgeIds
        self.selectedVertexIds = selectedVertexIds
        self.selectedSurfaceIds = selectedSurfaceIds
    }

    public mutating func clear() {
        selectedEdgeIds.removeAll()
        selectedVertexIds.removeAll()
        selectedSurfaceIds.removeAll()
    }

    public mutating func toggleEdge(_ id: String) {
        if selectedEdgeIds.contains(id) {
            selectedEdgeIds.remove(id)
        } else {
            selectedEdgeIds.insert(id)
        }
    }

    public mutating func toggleVertex(_ id: String) {
        if selectedVertexIds.contains(id) {
            selectedVertexIds.remove(id)
        } else {
            selectedVertexIds.insert(id)
        }
    }

    public mutating func toggleSurface(_ id: String) {
        if selectedSurfaceIds.contains(id) {
            selectedSurfaceIds.remove(id)
        } else {
            selectedSurfaceIds.insert(id)
        }
    }
}

/// Undo/redo history entry
public struct DrawingSnapshot {
    public let drawingData: DeckDrawingData
    public let description: String // for debug/display

    public init(drawingData: DeckDrawingData, description: String) {
        self.drawingData = drawingData
        self.description = description
    }
}

// MARK: - Copy / Paste Staging

public struct DeckSelectionClipboard: Equatable {
    public let vertices: [DeckVertex]
    public let edges: [DeckEdge]
    public let surfaces: [DeckSurface]
    public let bounds: CGRect

    public init(
        vertices: [DeckVertex],
        edges: [DeckEdge],
        surfaces: [DeckSurface],
        bounds: CGRect
    ) {
        self.vertices = vertices
        self.edges = edges
        self.surfaces = surfaces
        self.bounds = bounds
    }

    public var center: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    public var isEmpty: Bool {
        vertices.isEmpty && edges.isEmpty && surfaces.isEmpty
    }

    public func preview(centeredAt targetCenter: CGPoint) -> DeckPastePreview {
        let delta = CGSize(
            width: targetCenter.x - center.x,
            height: targetCenter.y - center.y
        )
        return preview(offsetBy: delta)
    }

    private func preview(offsetBy delta: CGSize) -> DeckPastePreview {
        var vertexIdMap: [String: String] = [:]
        let clonedVertices = vertices.map { vertex -> DeckVertex in
            let newId = UUID().uuidString
            vertexIdMap[vertex.id] = newId
            return DeckVertex(
                id: newId,
                position: CGPoint(
                    x: vertex.position.x + delta.width,
                    y: vertex.position.y + delta.height
                ),
                elevation: vertex.elevation,
                elevationSource: vertex.elevationSource,
                footingType: vertex.footingType,
                postType: vertex.postType
            )
        }

        let clonedEdges = edges.compactMap { edge -> DeckEdge? in
            guard let startId = vertexIdMap[edge.startVertexId],
                  let endId = vertexIdMap[edge.endVertexId] else { return nil }
            return DeckEdge(
                id: UUID().uuidString,
                startVertexId: startId,
                endVertexId: endId,
                edgeType: edge.edgeType,
                dimension: edge.dimension,
                dimensionSource: edge.dimensionSource,
                railingConfig: edge.railingConfig,
                stairConfig: edge.stairConfig,
                assignedItems: edge.assignedItems.map(Self.cloneAssignedItem),
                accuracyPercent: edge.accuracyPercent,
                dimensionStale: edge.dimensionStale,
                label: edge.label,
                houseEdgeMaterial: edge.houseEdgeMaterial
            )
        }

        let clonedSurfaces = surfaces.compactMap { surface -> DeckSurface? in
            let mappedIds = surface.vertexIds.compactMap { vertexIdMap[$0] }
            guard mappedIds.count == surface.vertexIds.count else { return nil }
            return DeckSurface(
                id: UUID().uuidString,
                vertexIds: Set(mappedIds),
                assignedItems: surface.assignedItems.map(Self.cloneAssignedItem),
                label: surface.label,
                color: surface.color,
                boardMaterial: surface.boardMaterial
            )
        }

        let movedBounds = CGRect(
            x: bounds.minX + delta.width,
            y: bounds.minY + delta.height,
            width: bounds.width,
            height: bounds.height
        )

        return DeckPastePreview(
            vertices: clonedVertices,
            edges: clonedEdges,
            surfaces: clonedSurfaces,
            sourceBounds: bounds,
            bounds: movedBounds
        )
    }

    private static func cloneAssignedItem(_ item: AssignedItem) -> AssignedItem {
        AssignedItem(
            productId: item.productId,
            name: item.name,
            unitType: item.unitType,
            unitPrice: item.unitPrice,
            taskTypeId: item.taskTypeId,
            taskTypeColor: item.taskTypeColor,
            isGate: item.isGate
        )
    }
}

public struct DeckPastePreview: Equatable {
    public var vertices: [DeckVertex]
    public var edges: [DeckEdge]
    public var surfaces: [DeckSurface]
    public let sourceBounds: CGRect
    public var bounds: CGRect

    public var isEmpty: Bool {
        vertices.isEmpty && edges.isEmpty && surfaces.isEmpty
    }

    public mutating func translate(by delta: CGSize) {
        for i in vertices.indices {
            vertices[i].position = CGPoint(
                x: vertices[i].position.x + delta.width,
                y: vertices[i].position.y + delta.height
            )
        }
        bounds = CGRect(
            x: bounds.minX + delta.width,
            y: bounds.minY + delta.height,
            width: bounds.width,
            height: bounds.height
        )
    }
}
