// OPS/OPS/DeckBuilder/Models/DeckDrawingState.swift

import Foundation
import SwiftUI

enum DrawingTool: String {
    case draw           // tap-hold-drag to draw lines
    case select         // rectangular marquee
    case lasso          // freeform selection
    case none           // long-press always works regardless
}

enum DrawingMode {
    case idle                                      // no active gesture
    case drawing(fromVertexId: String, currentEnd: CGPoint) // actively dragging a line
    case selecting(rect: CGRect)                   // dragging a selection rectangle
    case lassoing(points: [CGPoint])               // drawing a freeform lasso
    case draggingVertex(vertexId: String)           // repositioning a vertex in 2D
}

struct SelectionState: Equatable {
    var selectedEdgeIds: Set<String> = []
    var selectedVertexIds: Set<String> = []
    var selectedFootprint: Bool = false            // whether the area is selected

    var isEmpty: Bool {
        selectedEdgeIds.isEmpty && selectedVertexIds.isEmpty && !selectedFootprint
    }

    var hasEdges: Bool { !selectedEdgeIds.isEmpty }
    var hasVertices: Bool { !selectedVertexIds.isEmpty }

    mutating func clear() {
        selectedEdgeIds.removeAll()
        selectedVertexIds.removeAll()
        selectedFootprint = false
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
}

/// Undo/redo history entry
struct DrawingSnapshot {
    let drawingData: DeckDrawingData
    let description: String // for debug/display
}
