// OPS/OPS/DeckBuilder/Models/DeckGeometry.swift

import Foundation
import SwiftUI

// MARK: - Units & Configuration

enum MeasurementSystem: String, Codable {
    case imperial
    case metric
}

struct DrawingConfig: Codable {
    var measurementSystem: MeasurementSystem = .imperial
    var angleSnapIncrement: Double = 15.0      // degrees
    var lengthSnapIncrement: Double = 6.0      // inches (or cm if metric)
    var snappingEnabled: Bool = true
    var endpointSnapRadius: Double = 20.0      // points (screen distance for magnetic snap)
}

// MARK: - Core Geometry

struct DeckVertex: Identifiable, Codable, Equatable {
    let id: String
    var position: CGPoint           // canvas coordinates
    var elevation: Double?          // feet (or meters) off ground, nil = not set
    var elevationSource: ElevationSource = .manual
    var footingType: FootingType?
    var postType: String?           // product reference

    init(id: String = UUID().uuidString, position: CGPoint, elevation: Double? = nil) {
        self.id = id
        self.position = position
        self.elevation = elevation
    }
}

enum ElevationSource: String, Codable {
    case manual
    case ar          // captured via AR — carries ±accuracy
}

enum FootingType: String, Codable, CaseIterable {
    case helicalPile = "helical_pile"
    case sonoTube = "sono_tube"
    case concretePad = "concrete_pad"
}

struct DeckEdge: Identifiable, Codable, Equatable {
    let id: String
    var startVertexId: String
    var endVertexId: String
    var edgeType: EdgeType = .deckEdge
    var dimension: Double?          // real-world length in inches (or cm)
    var dimensionSource: DimensionSource = .manual
    var railingConfig: RailingConfig?
    var stairConfig: StairConfig?
    var assignedItems: [AssignedItem] = []

    init(
        id: String = UUID().uuidString,
        startVertexId: String,
        endVertexId: String
    ) {
        self.id = id
        self.startVertexId = startVertexId
        self.endVertexId = endVertexId
    }
}

enum EdgeType: String, Codable, CaseIterable {
    case houseEdge = "house_edge"
    case deckEdge = "deck_edge"
}

enum DimensionSource: String, Codable {
    case manual         // typed by user
    case scale          // derived from scale calculation
    case ar             // from AR walk — carries ±accuracy
    case laser          // from Bluetooth laser meter — high accuracy
}

// MARK: - Railing

struct RailingConfig: Codable, Equatable {
    var railingType: RailingType
    var maxPostSpacing: Double      // inches between posts (e.g., 60" for glass, 84" for picket)
    var assignedItems: [AssignedItem] = []
}

enum RailingType: String, Codable, CaseIterable {
    case glass
    case picket
    case cable
    case horizontal
    case wood

    var defaultMaxPostSpacing: Double {
        switch self {
        case .glass:      return 60.0   // 5 feet
        case .picket:     return 84.0   // 7 feet
        case .cable:      return 48.0   // 4 feet
        case .horizontal: return 72.0   // 6 feet
        case .wood:       return 72.0   // 6 feet
        }
    }

    var displayName: String {
        switch self {
        case .glass:      return "Glass"
        case .picket:     return "Picket"
        case .cable:      return "Cable"
        case .horizontal: return "Horizontal"
        case .wood:       return "Wood"
        }
    }
}

// MARK: - Stairs

struct StairConfig: Codable, Equatable {
    var width: Double               // inches
    var risePerStep: Double = 7.5   // inches (IRC R311.7: max 7.75")
    var runPerTread: Double = 10.0  // inches (IRC R311.7: min 10")
    var treadCount: Int?            // auto-calculated or user override
    var railingConfig: RailingConfig?
    var assignedItems: [AssignedItem] = []

    /// Calculate tread count from total rise (elevation difference at edge endpoints)
    static func calculateTreadCount(totalRise: Double, risePerStep: Double = 7.5) -> Int {
        guard totalRise > 0 else { return 0 }
        return Int(ceil(totalRise / risePerStep))
    }

    /// Calculate stringer length from total rise and run
    static func stringerLength(totalRise: Double, treadCount: Int, runPerTread: Double = 10.0) -> Double {
        let totalRun = Double(treadCount) * runPerTread
        return sqrt(totalRise * totalRise + totalRun * totalRun)
    }

    /// Number of stringers based on stair width
    static func stringerCount(width: Double) -> Int {
        // One stringer every 16" on center, minimum 2
        return max(2, Int(ceil(width / 16.0)) + 1)
    }
}

// MARK: - Item Assignment

struct AssignedItem: Identifiable, Codable, Equatable {
    let id: String
    var productId: String?          // reference to company's Products table
    var name: String                // display name
    var unitType: UnitType          // determines what this item measures
    var unitPrice: Double?          // price per unit (optional — may come from product)

    init(
        id: String = UUID().uuidString,
        productId: String? = nil,
        name: String,
        unitType: UnitType,
        unitPrice: Double? = nil
    ) {
        self.id = id
        self.productId = productId
        self.name = name
        self.unitType = unitType
        self.unitPrice = unitPrice
    }
}

enum UnitType: String, Codable, CaseIterable {
    case linearFoot = "linear_foot"
    case linearMeter = "linear_meter"
    case squareFoot = "square_foot"
    case squareMeter = "square_meter"
    case each
    case set
}

// MARK: - Footprint (Closed Polygon)

struct DeckFootprint: Codable, Equatable {
    var assignedItems: [AssignedItem] = []   // area-based items (surfacing, etc.)
    var isClosed: Bool = false
}

// MARK: - Complete Drawing Data

struct DeckDrawingData: Codable {
    var vertices: [DeckVertex] = []
    var edges: [DeckEdge] = []
    var footprint: DeckFootprint = DeckFootprint()
    var config: DrawingConfig = DrawingConfig()
    var overallElevation: Double?          // simple mode: uniform height
    var scaleFactor: Double?               // canvas points per real-world inch

    // MARK: - Vertex Helpers

    func vertex(byId id: String) -> DeckVertex? {
        vertices.first { $0.id == id }
    }

    mutating func updateVertex(_ vertex: DeckVertex) {
        if let index = vertices.firstIndex(where: { $0.id == vertex.id }) {
            vertices[index] = vertex
        }
    }

    // MARK: - Edge Helpers

    func edge(byId id: String) -> DeckEdge? {
        edges.first { $0.id == id }
    }

    func edges(connectedTo vertexId: String) -> [DeckEdge] {
        edges.filter { $0.startVertexId == vertexId || $0.endVertexId == vertexId }
    }

    mutating func updateEdge(_ edge: DeckEdge) {
        if let index = edges.firstIndex(where: { $0.id == edge.id }) {
            edges[index] = edge
        }
    }

    // MARK: - Polygon State

    var isClosed: Bool {
        guard vertices.count >= 3, edges.count >= 3 else { return false }
        // Check if edges form a cycle
        let firstVertexId = vertices.first?.id
        let lastEdge = edges.last
        return lastEdge?.endVertexId == firstVertexId
    }

    /// Ordered vertex positions for rendering
    var orderedPositions: [CGPoint] {
        vertices.map { $0.position }
    }

    // MARK: - Serialization

    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func fromJSON(_ json: String) -> DeckDrawingData? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DeckDrawingData.self, from: data)
    }
}

// MARK: - CGPoint Codable

extension CGPoint: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case x, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        self.init(x: x, y: y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Double(x), forKey: .x)
        try container.encode(Double(y), forKey: .y)
    }
}
