// OPS/OPS/DeckBuilder/Models/DeckDrawingState.swift

import Foundation
import SwiftUI

enum DrawingTool: String {
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
enum MarqueeShape: String, CaseIterable {
    case rect
    case lasso
}

enum SelectableElementType: String, CaseIterable {
    case vertex
    case edge
    case face
}

enum DrawingMode: Equatable {
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
}

struct SelectionState: Equatable {
    var selectedEdgeIds: Set<String> = []
    var selectedVertexIds: Set<String> = []
    /// Per-surface selection state — replaces the previous single-bool
    /// `selectedFootprint`. `selectedFootprint` is now a derived helper that
    /// returns true when ANY surface is selected (read-only). Callers that
    /// need to clear surface selection should mutate `selectedSurfaceIds`
    /// directly. DECK-NEW-1.
    var selectedSurfaceIds: Set<String> = []

    /// Legacy compat — true when at least one surface is selected.
    var selectedFootprint: Bool { !selectedSurfaceIds.isEmpty }

    var isEmpty: Bool {
        selectedEdgeIds.isEmpty && selectedVertexIds.isEmpty && selectedSurfaceIds.isEmpty
    }

    var hasEdges: Bool { !selectedEdgeIds.isEmpty }
    var hasVertices: Bool { !selectedVertexIds.isEmpty }
    var hasSurfaces: Bool { !selectedSurfaceIds.isEmpty }

    mutating func clear() {
        selectedEdgeIds.removeAll()
        selectedVertexIds.removeAll()
        selectedSurfaceIds.removeAll()
    }

    mutating func toggleEdge(_ id: String) {
        if selectedEdgeIds.contains(id) {
            selectedEdgeIds.remove(id)
        } else {
            selectedEdgeIds.insert(id)
        }
    }

    mutating func toggleVertex(_ id: String) {
        if selectedVertexIds.contains(id) {
            selectedVertexIds.remove(id)
        } else {
            selectedVertexIds.insert(id)
        }
    }

    mutating func toggleSurface(_ id: String) {
        if selectedSurfaceIds.contains(id) {
            selectedSurfaceIds.remove(id)
        } else {
            selectedSurfaceIds.insert(id)
        }
    }
}

/// Undo/redo history entry
struct DrawingSnapshot {
    let drawingData: DeckDrawingData
    let description: String // for debug/display
}
