// OPS/OPS/DeckBuilder/Models/DeckGeometry.swift

import Foundation
import SwiftUI

extension KeyedDecodingContainer {
    public func decodeLegacyBoolIfPresent(forKey key: Key) throws -> Bool? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return nil }
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) {
            switch value {
            case 0: return false
            case 1: return true
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Expected legacy numeric Bool to be 0 or 1."
                )
            }
        }
        if let value = try? decode(Double.self, forKey: key) {
            switch value {
            case 0: return false
            case 1: return true
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Expected legacy numeric Bool to be 0 or 1."
                )
            }
        }
        if let value = try? decode(String.self, forKey: key) {
            switch value.lowercased() {
            case "false", "0": return false
            case "true", "1": return true
            default: break
            }
        }

        throw DecodingError.typeMismatch(
            Bool.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected Bool-compatible value."
            )
        )
    }
}

// MARK: - Units & Configuration

public enum MeasurementSystem: String, Codable {
    case imperial
    case metric
}

public struct DrawingConfig: Codable {
    public var measurementSystem: MeasurementSystem = .imperial
    public var angleSnapIncrement: Double = 15.0      // degrees
    public var lengthSnapIncrement: Double = 6.0      // inches (or cm if metric)
    public var snappingEnabled: Bool = true
    public var endpointSnapRadius: Double = 20.0      // points (screen distance for magnetic snap)
    public var gridVisible: Bool = true
    public var vinylCatalogItemId: String?

    public enum CodingKeys: String, CodingKey {
        case measurementSystem
        case angleSnapIncrement
        case lengthSnapIncrement
        case snappingEnabled
        case endpointSnapRadius
        case gridVisible
        case vinylCatalogItemId
    }

    public init(
        measurementSystem: MeasurementSystem = .imperial,
        angleSnapIncrement: Double = 15.0,
        lengthSnapIncrement: Double = 6.0,
        snappingEnabled: Bool = true,
        endpointSnapRadius: Double = 20.0,
        gridVisible: Bool = true,
        vinylCatalogItemId: String? = nil
    ) {
        self.measurementSystem = measurementSystem
        self.angleSnapIncrement = angleSnapIncrement
        self.lengthSnapIncrement = lengthSnapIncrement
        self.snappingEnabled = snappingEnabled
        self.endpointSnapRadius = endpointSnapRadius
        self.gridVisible = gridVisible
        self.vinylCatalogItemId = vinylCatalogItemId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.measurementSystem = try c.decodeIfPresent(MeasurementSystem.self, forKey: .measurementSystem) ?? .imperial
        self.angleSnapIncrement = try c.decodeIfPresent(Double.self, forKey: .angleSnapIncrement) ?? 15.0
        self.lengthSnapIncrement = try c.decodeIfPresent(Double.self, forKey: .lengthSnapIncrement) ?? 6.0
        self.snappingEnabled = try c.decodeLegacyBoolIfPresent(forKey: .snappingEnabled) ?? true
        self.endpointSnapRadius = try c.decodeIfPresent(Double.self, forKey: .endpointSnapRadius) ?? 20.0
        self.gridVisible = try c.decodeLegacyBoolIfPresent(forKey: .gridVisible) ?? true
        self.vinylCatalogItemId = try c.decodeIfPresent(String.self, forKey: .vinylCatalogItemId)
    }
}

// MARK: - Core Geometry

public struct DeckVertex: Identifiable, Codable, Equatable {
    public let id: String
    public var position: CGPoint           // canvas coordinates
    public var elevation: Double?          // feet (or meters) off ground, nil = not set
    public var elevationSource: ElevationSource = .manual
    public var footingType: FootingType?
    public var postType: String?           // product reference

    public enum CodingKeys: String, CodingKey {
        case id
        case position
        case elevation
        case elevationSource
        case footingType
        case postType
    }

    public init(
        id: String = UUID().uuidString,
        position: CGPoint,
        elevation: Double? = nil,
        elevationSource: ElevationSource = .manual,
        footingType: FootingType? = nil,
        postType: String? = nil
    ) {
        self.id = id
        self.position = position
        self.elevation = elevation
        self.elevationSource = elevationSource
        self.footingType = footingType
        self.postType = postType
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.position = try c.decode(CGPoint.self, forKey: .position)
        self.elevation = try c.decodeIfPresent(Double.self, forKey: .elevation)
        self.elevationSource = try c.decodeIfPresent(ElevationSource.self, forKey: .elevationSource) ?? .manual
        self.footingType = try c.decodeIfPresent(FootingType.self, forKey: .footingType)
        self.postType = try c.decodeIfPresent(String.self, forKey: .postType)
    }
}

public enum ElevationSource: String, Codable {
    case manual
    case ar          // captured via AR — carries ±accuracy
}

public enum FootingType: String, Codable, CaseIterable {
    case helicalPile = "helical_pile"
    case sonoTube = "sono_tube"
    case concretePad = "concrete_pad"
}

public struct DeckEdge: Identifiable, Codable, Equatable {
    public let id: String
    public var startVertexId: String
    public var endVertexId: String
    public var edgeType: EdgeType = .deckEdge
    public var dimension: Double?          // real-world length in inches (or cm)
    public var dimensionSource: DimensionSource = .manual
    public var railingConfig: RailingConfig?
    public var stairConfig: StairConfig?
    public var assignedItems: [AssignedItem] = []
    public var accuracyPercent: Double?    // e.g., 3.0 means ±3%. nil = manually verified / no AR
    /// Set to true when a vertex drag changed the canvas length of this edge
    /// but its stored `dimension` was preserved because the source was manual /
    /// laser / AR (user-authoritative). The renderer surfaces a warning glyph
    /// so the user knows the typed value and the drawn length disagree. Cleared
    /// when the user retypes / re-measures the dimension.
    public var dimensionStale: Bool = false
    /// Optional user-supplied label that floats over this edge on the canvas
    /// (e.g. "Hot tub side", "BBQ wall"). Trimmed to nil when blank so absent
    /// labels never render an empty pill. Bug 4a03f507.
    public var label: String?
    /// Optional house-edge cladding material (stucco, hardie, wood vertical, etc.)
    /// — separate from the `assignedItems` list because a house edge isn't billed
    /// as deck framing/decking, but its visible cladding still informs renders.
    /// Bug 3d72ce0b.
    public var houseEdgeMaterial: HouseEdgeMaterial?

    public enum CodingKeys: String, CodingKey {
        case id
        case startVertexId
        case endVertexId
        case edgeType
        case dimension
        case dimensionSource
        case railingConfig
        case stairConfig
        case assignedItems
        case accuracyPercent
        case dimensionStale
        case label
        case houseEdgeMaterial
    }

    public init(
        id: String = UUID().uuidString,
        startVertexId: String,
        endVertexId: String,
        edgeType: EdgeType = .deckEdge,
        dimension: Double? = nil,
        dimensionSource: DimensionSource = .manual,
        railingConfig: RailingConfig? = nil,
        stairConfig: StairConfig? = nil,
        assignedItems: [AssignedItem] = [],
        accuracyPercent: Double? = nil,
        dimensionStale: Bool = false,
        label: String? = nil,
        houseEdgeMaterial: HouseEdgeMaterial? = nil
    ) {
        self.id = id
        self.startVertexId = startVertexId
        self.endVertexId = endVertexId
        self.edgeType = edgeType
        self.dimension = dimension
        self.dimensionSource = dimensionSource
        self.railingConfig = railingConfig
        self.stairConfig = stairConfig
        self.assignedItems = assignedItems
        self.accuracyPercent = accuracyPercent
        self.dimensionStale = dimensionStale
        self.label = label
        self.houseEdgeMaterial = houseEdgeMaterial
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.startVertexId = try c.decode(String.self, forKey: .startVertexId)
        self.endVertexId = try c.decode(String.self, forKey: .endVertexId)
        self.edgeType = try c.decodeIfPresent(EdgeType.self, forKey: .edgeType) ?? .deckEdge
        self.dimension = try c.decodeIfPresent(Double.self, forKey: .dimension)
        self.dimensionSource = try c.decodeIfPresent(DimensionSource.self, forKey: .dimensionSource) ?? .manual
        self.railingConfig = try c.decodeIfPresent(RailingConfig.self, forKey: .railingConfig)
        self.stairConfig = try c.decodeIfPresent(StairConfig.self, forKey: .stairConfig)
        self.assignedItems = try c.decodeIfPresent([AssignedItem].self, forKey: .assignedItems) ?? []
        self.accuracyPercent = try c.decodeIfPresent(Double.self, forKey: .accuracyPercent)
        self.dimensionStale = try c.decodeLegacyBoolIfPresent(forKey: .dimensionStale) ?? false
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.houseEdgeMaterial = try c.decodeIfPresent(HouseEdgeMaterial.self, forKey: .houseEdgeMaterial)
        if edgeType == .houseEdge {
            self.railingConfig = nil
        } else {
            self.houseEdgeMaterial = nil
        }
    }
}

public enum EdgeType: String, Codable, CaseIterable {
    case houseEdge = "house_edge"
    case deckEdge = "deck_edge"
}

/// Cladding material for a `houseEdge`. Drives the rendered house-side wall
/// texture and shows up in materials/estimates output. Bug 3d72ce0b — house
/// edges should rise visibly above the deck surface in the 3D scene; the
/// material picks the right hatch/tone in the 2D renderers and the right
/// fill/normal in the 3D scene.
public enum HouseEdgeMaterial: String, Codable, CaseIterable {
    case stucco
    case hardie             // Hardie board / fiber cement plank
    case woodVertical       // Vertical board-and-batten / shiplap
    case brick              // Brick veneer / clay masonry
    case stone              // Stone veneer / natural stone cladding
    case vinyl              // Vinyl siding
    case parapet            // Low capped wall — half-height masonry, used on
                            // rooftop decks and modern flat-faced builds.
                            // Bug ee787f29 — explicitly requested as a
                            // cladding option for high-end residential.

    public var displayName: String {
        switch self {
        case .stucco:       return "Stucco"
        case .hardie:       return "Hardie Plank"
        case .woodVertical: return "Wood Vertical"
        case .brick:        return "Brick"
        case .stone:        return "Stone Veneer"
        case .vinyl:        return "Vinyl Siding"
        case .parapet:      return "Parapet Wall"
        }
    }

    /// Material/catalog color data used by renderers for wall surface tint.
    /// This is not UI chrome styling; callers decide how to render it.
    public var fillHex: String {
        "#\(fillHexCode)"
    }

    public var fillHexCode: String {
        switch self {
        case .stucco:       return "D6CFC2"   // warm off-white
        case .hardie:       return "A6A8A3"   // light gray-green
        case .woodVertical: return "8B6F4F"   // walnut brown
        case .brick:        return "8C5A4F"   // muted brick red
        case .stone:        return "7A7466"   // weathered limestone
        case .vinyl:        return "C2C5C0"   // cool gray-beige
        case .parapet:      return "9A8F7E"   // sand-toned masonry cap
        }
    }
}

public enum DimensionSource: String, Codable {
    case manual         // typed by user
    case scale          // derived from scale calculation
    case ar             // from AR walk — carries ±accuracy
    case laser          // from Bluetooth laser meter — high accuracy
}

// MARK: - Railing

public struct RailingConfig: Codable, Equatable {
    public var railingType: RailingType
    public var maxPostSpacing: Double      // inches between posts (e.g., 60" for glass, 84" for picket)
    public var assignedItems: [AssignedItem] = []

    // Catalog metadata vocabulary (deck-catalog integration spec § 3.4).
    // Free-text strings — companies author option values per Product, so
    // the deck side stays decoupled from any one company's vocabulary.
    // The assignment sheet renders a picker over the assigned Product's
    // option values when one exists; otherwise free-text against these
    // defaults.
    public var color: String = "Black"
    public var mountType: String = "Topmount"      // Topmount | Sidemount | Surface
    public var mountSurface: String = "Surface"    // Surface | Concrete | other
    public var postHeight: Double = 36.0           // inches; drives post_set.height (IRC R312 minimum)
    public var wallMaterial: HouseEdgeMaterial = .parapet

    public enum CodingKeys: String, CodingKey {
        case railingType, maxPostSpacing, assignedItems
        case color, mountType, mountSurface, postHeight, wallMaterial
    }

    public init(
        railingType: RailingType,
        maxPostSpacing: Double,
        assignedItems: [AssignedItem] = [],
        color: String = "Black",
        mountType: String = "Topmount",
        mountSurface: String = "Surface",
        postHeight: Double = 36.0,
        wallMaterial: HouseEdgeMaterial = .parapet
    ) {
        self.railingType = railingType
        self.maxPostSpacing = maxPostSpacing
        self.assignedItems = assignedItems
        self.color = color
        self.mountType = mountType
        self.mountSurface = mountSurface
        self.postHeight = postHeight
        self.wallMaterial = wallMaterial
    }

    public init(from decoder: Decoder) throws {
        // Custom decoder so legacy JSON (saved before the catalog vocabulary
        // landed) round-trips with sensible defaults instead of throwing on
        // missing keys. Swift's synthesized init(from:) calls `decode` for
        // every property regardless of the property's inline default.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.railingType = try c.decode(RailingType.self, forKey: .railingType)
        self.maxPostSpacing = try c.decode(Double.self, forKey: .maxPostSpacing)
        self.assignedItems = try c.decodeIfPresent([AssignedItem].self, forKey: .assignedItems) ?? []
        self.color = try c.decodeIfPresent(String.self, forKey: .color) ?? "Black"
        self.mountType = try c.decodeIfPresent(String.self, forKey: .mountType) ?? "Topmount"
        self.mountSurface = try c.decodeIfPresent(String.self, forKey: .mountSurface) ?? "Surface"
        self.postHeight = try c.decodeIfPresent(Double.self, forKey: .postHeight) ?? 36.0
        self.wallMaterial = try c.decodeIfPresent(HouseEdgeMaterial.self, forKey: .wallMaterial) ?? .parapet
    }
}

public enum RailingType: String, Codable, CaseIterable {
    case parapetWall = "parapet_wall"
    case glass
    case picket
    case cable
    case horizontal
    case wood

    public static var assignableDefaultTypes: [RailingType] {
        [.parapetWall]
    }

    public var defaultMaxPostSpacing: Double {
        switch self {
        case .parapetWall: return 96.0
        case .glass:      return 60.0   // 5 feet
        case .picket:     return 84.0   // 7 feet
        case .cable:      return 48.0   // 4 feet
        case .horizontal: return 72.0   // 6 feet
        case .wood:       return 72.0   // 6 feet
        }
    }

    public var displayName: String {
        switch self {
        case .parapetWall: return "Parapet Wall"
        case .glass:      return "Glass"
        case .picket:     return "Picket"
        case .cable:      return "Cable"
        case .horizontal: return "Horizontal"
        case .wood:       return "Wood"
        }
    }
}

// MARK: - Stairs

public enum StairAlignment: String, Codable, CaseIterable {
    case left
    case center
    case right

    public var displayName: String {
        switch self {
        case .left:   return "Left"
        case .center: return "Center"
        case .right:  return "Right"
        }
    }
}

public struct StairConfig: Codable, Equatable {
    public var width: Double               // inches
    public var risePerStep: Double = 7.5   // inches (IRC R311.7: max 7.75")
    public var runPerTread: Double = 10.0  // inches (IRC R311.7: min 10")
    public var treadCount: Int?            // auto-calculated or user override
    public var alignment: StairAlignment = .center  // position along edge when width < edge length
    public var offset: Double = 0          // inches from alignment side
    public var railingConfig: RailingConfig?
    public var assignedItems: [AssignedItem] = []
    /// Stair total rise in INCHES — captured in StairConfigView (which stores
    /// the user's feet entry × 12) when no per-vertex or overall elevation is
    /// set. Once stored, the user can edit this on subsequent passes through
    /// the stair editor (instead of being trapped by the read-only "Total
    /// Rise" card). Bug bfbc4068. Also the value the deck adopts as its render
    /// elevation when none was entered explicitly — see
    /// `DeckDrawingData.stairDerivedElevationFeet`.
    public var totalRiseInches: Double?
    /// When true, render stairs on the OPPOSITE perpendicular from the deck
    /// fill. Default `false` means stairs run AWAY from the deck surface, which
    /// is the natural case (bug a7429390). The toggle in StairConfigView
    /// flips this for edges where the user wants the stairs to land on the
    /// other side (e.g. against a fence the renderer can't infer).
    public var flipDirection: Bool = false

    // Catalog metadata vocabulary (deck-catalog integration spec § 3.4).
    // `mountType` uses a different vocabulary than railing (Surface | Top | Side)
    // because stairs land on grade, on top of an existing landing, or against
    // the side of a deck — each maps to a distinct stair-product variant.
    public var color: String = "Black"
    public var mountType: String = "Surface"   // Surface | Top | Side

    public enum CodingKeys: String, CodingKey {
        case width, risePerStep, runPerTread, treadCount, alignment, offset
        case railingConfig, assignedItems, totalRiseInches, flipDirection
        case color, mountType
    }

    public init(
        width: Double,
        risePerStep: Double = 7.5,
        runPerTread: Double = 10.0,
        treadCount: Int? = nil,
        alignment: StairAlignment = .center,
        offset: Double = 0,
        railingConfig: RailingConfig? = nil,
        assignedItems: [AssignedItem] = [],
        totalRiseInches: Double? = nil,
        flipDirection: Bool = false,
        color: String = "Black",
        mountType: String = "Surface"
    ) {
        self.width = width
        self.risePerStep = risePerStep
        self.runPerTread = runPerTread
        self.treadCount = treadCount
        self.alignment = alignment
        self.offset = offset
        self.railingConfig = railingConfig
        self.assignedItems = assignedItems
        self.totalRiseInches = totalRiseInches
        self.flipDirection = flipDirection
        self.color = color
        self.mountType = mountType
    }

    public init(from decoder: Decoder) throws {
        // Custom decoder so legacy JSON round-trips with sensible defaults
        // instead of throwing on missing keys. See RailingConfig for the
        // rationale.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.width = try c.decode(Double.self, forKey: .width)
        self.risePerStep = try c.decodeIfPresent(Double.self, forKey: .risePerStep) ?? 7.5
        self.runPerTread = try c.decodeIfPresent(Double.self, forKey: .runPerTread) ?? 10.0
        self.treadCount = try c.decodeIfPresent(Int.self, forKey: .treadCount)
        self.alignment = try c.decodeIfPresent(StairAlignment.self, forKey: .alignment) ?? .center
        self.offset = try c.decodeIfPresent(Double.self, forKey: .offset) ?? 0
        self.railingConfig = try c.decodeIfPresent(RailingConfig.self, forKey: .railingConfig)
        self.assignedItems = try c.decodeIfPresent([AssignedItem].self, forKey: .assignedItems) ?? []
        self.totalRiseInches = try c.decodeIfPresent(Double.self, forKey: .totalRiseInches)
        self.flipDirection = try c.decodeLegacyBoolIfPresent(forKey: .flipDirection) ?? false
        self.color = try c.decodeIfPresent(String.self, forKey: .color) ?? "Black"
        self.mountType = try c.decodeIfPresent(String.self, forKey: .mountType) ?? "Surface"
    }

    /// Calculate tread count from total rise (elevation difference at edge endpoints)
    public static func calculateTreadCount(totalRise: Double, risePerStep: Double = 7.5) -> Int {
        guard totalRise > 0 else { return 0 }
        return Int(ceil(totalRise / risePerStep))
    }

    /// Calculate stringer length from total rise and run
    public static func stringerLength(totalRise: Double, treadCount: Int, runPerTread: Double = 10.0) -> Double {
        let totalRun = Double(treadCount) * runPerTread
        return sqrt(totalRise * totalRise + totalRun * totalRun)
    }

    /// Number of stringers based on stair width
    public static func stringerCount(width: Double) -> Int {
        // Two outer stringers plus intermediates so spacing never exceeds 24"
        // on center: a 36" stair gets 3 (18" o.c.), 48" gets 3 (24"), 60" gets
        // 4 (20"). Minimum 2 (one per side).
        return max(2, Int(ceil(width / 24.0)) + 1)
    }
}

// MARK: - Item Assignment

public struct AssignedItem: Identifiable, Codable, Equatable {
    public let id: String
    public var productId: String?          // reference to company's Products table
    public var name: String                // display name
    public var unitType: UnitType          // determines what this item measures
    public var unitPrice: Double?          // price per unit (optional — may come from product)
    public var taskTypeId: String?         // task type this material belongs to
    public var taskTypeColor: String?      // hex color cached from assigned task metadata
    /// Flags this assignment as a gate (drives `gate` component emission per
    /// the deck-catalog integration spec § 3.5). Auto-defaulted on by the
    /// assignment sheet when the picked Product's `category` (or tag)
    /// contains "gate" (case-insensitive); the user can override either way.
    public var isGate: Bool = false

    public enum CodingKeys: String, CodingKey {
        case id, productId, name, unitType, unitPrice, taskTypeId, taskTypeColor, isGate
    }

    public init(
        id: String = UUID().uuidString,
        productId: String? = nil,
        name: String,
        unitType: UnitType,
        unitPrice: Double? = nil,
        taskTypeId: String? = nil,
        taskTypeColor: String? = nil,
        isGate: Bool = false
    ) {
        self.id = id
        self.productId = productId
        self.name = name
        self.unitType = unitType
        self.unitPrice = unitPrice
        self.taskTypeId = taskTypeId
        self.taskTypeColor = taskTypeColor
        self.isGate = isGate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.productId = try c.decodeIfPresent(String.self, forKey: .productId)
        self.name = try c.decode(String.self, forKey: .name)
        self.unitType = try c.decode(UnitType.self, forKey: .unitType)
        self.unitPrice = try c.decodeIfPresent(Double.self, forKey: .unitPrice)
        self.taskTypeId = try c.decodeIfPresent(String.self, forKey: .taskTypeId)
        self.taskTypeColor = try c.decodeIfPresent(String.self, forKey: .taskTypeColor)
        self.isGate = try c.decodeLegacyBoolIfPresent(forKey: .isGate) ?? false
    }
}

public enum UnitType: String, Codable, CaseIterable {
    case linearFoot = "linear_foot"
    case linearMeter = "linear_meter"
    case squareFoot = "square_foot"
    case squareMeter = "square_meter"
    case each
    case set
}

// MARK: - Footprint (Closed Polygon) — legacy single-surface model

/// Legacy single-surface assignment store. Retained for back-compat with
/// previously-saved drawings; new per-surface assignments live in
/// `DeckDrawingData.surfaces` / `DeckLevel.surfaces` (`DeckSurface`).
/// On first reconciliation after migration, any populated `assignedItems`
/// or `label` here is moved to the largest detected surface and the legacy
/// fields are cleared.
public struct DeckFootprint: Codable, Equatable {
    public var assignedItems: [AssignedItem] = []   // area-based items (surfacing, etc.)
    public var isClosed: Bool = false
    /// Optional user-supplied label that floats over the deck surface
    /// (e.g. "BBQ Area", "Hot Tub Pad"). Trimmed to nil when blank.
    /// Bug 4a03f507.
    public var label: String?

    public enum CodingKeys: String, CodingKey {
        case assignedItems
        case isClosed
        case label
    }

    public init(
        assignedItems: [AssignedItem] = [],
        isClosed: Bool = false,
        label: String? = nil
    ) {
        self.assignedItems = assignedItems
        self.isClosed = isClosed
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.assignedItems = try c.decodeIfPresent([AssignedItem].self, forKey: .assignedItems) ?? []
        self.isClosed = try c.decodeLegacyBoolIfPresent(forKey: .isClosed) ?? false
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
    }
}

// MARK: - Surfaces (Multi-Polygon)

/// A persisted closed face in the deck-edge graph. Distinct from the legacy
/// `DeckFootprint` (which assumed exactly one polygon per drawing). Every
/// closed face detected by `SurfaceDetector` is mapped — through
/// `SurfaceReconciler` — to one of these so per-surface material and label
/// assignments survive across geometry edits. DECK-NEW-1.
public struct DeckSurface: Identifiable, Codable, Equatable {
    /// Stable UUID; survives geometry edits via vertex-set Jaccard matching.
    public let id: String
    /// Unordered membership — matched against `DetectedSurface.vertexIds`.
    /// Updated in place when a small edit shifts the surface's boundary.
    public var vertexIds: Set<String>
    /// Per-surface area-based items (decking material, finishes, etc.).
    public var assignedItems: [AssignedItem] = []
    /// Optional user-supplied label that floats over the surface in the
    /// renderers (e.g. "BBQ Area", "Hot Tub Pad").
    public var label: String?

    // Catalog metadata vocabulary (deck-catalog integration spec § 3.4).
    // Defaults pick the most common new-construction values so partially-
    // configured surfaces still emit meaningful `deck_board` components.
    public var color: String = "Brown"
    public var boardMaterial: String = "composite"  // composite | pvc | cedar | treated | other

    public enum CodingKeys: String, CodingKey {
        case id, vertexIds, assignedItems, label, color, boardMaterial
    }

    public init(
        id: String = UUID().uuidString,
        vertexIds: Set<String> = [],
        assignedItems: [AssignedItem] = [],
        label: String? = nil,
        color: String = "Brown",
        boardMaterial: String = "composite"
    ) {
        self.id = id
        self.vertexIds = vertexIds
        self.assignedItems = assignedItems
        self.label = label
        self.color = color
        self.boardMaterial = boardMaterial
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.vertexIds = try c.decode(Set<String>.self, forKey: .vertexIds)
        self.assignedItems = try c.decodeIfPresent([AssignedItem].self, forKey: .assignedItems) ?? []
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.color = try c.decodeIfPresent(String.self, forKey: .color) ?? "Brown"
        self.boardMaterial = try c.decodeIfPresent(String.self, forKey: .boardMaterial) ?? "composite"
    }
}

// MARK: - Complete Drawing Data

public struct DeckDrawingData: Codable {
    public var vertices: [DeckVertex] = []
    public var edges: [DeckEdge] = []
    public var footprint: DeckFootprint = DeckFootprint()
    /// Per-surface material/label store (DECK-NEW-1 follow-up). One entry
    /// per detected closed face; reconciled via `SurfaceReconciler` after
    /// any geometry edit. Empty until the first surface is detected and
    /// reconciled. Single-level drawings populate this; multi-level
    /// drawings populate the equivalent on each `DeckLevel`.
    public var surfaces: [DeckSurface] = []
    public var config: DrawingConfig = DrawingConfig()
    public var overallElevation: Double?          // simple mode: uniform height
    public var scaleFactor: Double?               // canvas points per real-world inch
    public var poolDiameter: Double?              // pool deck: diameter in inches (visual overlay only)
    public var photoOverlay: PhotoOverlayState?   // saved overlay positioning for re-editing

    // MARK: - Multi-Level

    public var levels: [DeckLevel] = []
    public var levelConnections: [LevelConnection] = []

    // MARK: - Catalog projection

    /// Catalog-facing projection of the drawing — one row per visible
    /// component (railing, deck_board, stair_set, gate, post_set) with
    /// metadata keys the `DesignToEstimateAdapter` consumes.
    /// Recomputed from geometry on every `toJSON()` (Phase 2); never read
    /// for rendering. Absent on legacy JSON; backfilled on first load
    /// (deck-catalog integration spec § 3.2 + § 4.2).
    public var components: [DesignComponentRow]? = nil
    /// Opaque top-level `drawing_data` blocks that newer deck runtimes may
    /// write before this app understands them. `fromJSON(_:)` parses these
    /// blocks outside `JSONDecoder` so raw JSON number tokens survive exact
    /// round-trips through older builds.
    public var futureBlocks: [String: DeckJSONValue] = [:]

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case vertices
        case edges
        case footprint
        case surfaces
        case config
        case overallElevation
        case scaleFactor
        case poolDiameter
        case photoOverlay
        case levels
        case levelConnections
        case components
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.vertices = try c.decodeIfPresent([DeckVertex].self, forKey: .vertices) ?? []
        self.edges = try c.decodeIfPresent([DeckEdge].self, forKey: .edges) ?? []
        self.footprint = try c.decodeIfPresent(DeckFootprint.self, forKey: .footprint) ?? DeckFootprint()
        self.surfaces = try c.decodeIfPresent([DeckSurface].self, forKey: .surfaces) ?? []
        self.config = try c.decodeIfPresent(DrawingConfig.self, forKey: .config) ?? DrawingConfig()
        self.overallElevation = try c.decodeIfPresent(Double.self, forKey: .overallElevation)
        self.scaleFactor = try c.decodeIfPresent(Double.self, forKey: .scaleFactor)
        self.poolDiameter = try c.decodeIfPresent(Double.self, forKey: .poolDiameter)
        self.photoOverlay = try c.decodeIfPresent(PhotoOverlayState.self, forKey: .photoOverlay)
        self.levels = try c.decodeIfPresent([DeckLevel].self, forKey: .levels) ?? []
        self.levelConnections = try c.decodeIfPresent([LevelConnection].self, forKey: .levelConnections) ?? []
        self.components = try c.decodeIfPresent([DesignComponentRow].self, forKey: .components)
        self.futureBlocks = [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vertices, forKey: .vertices)
        try c.encode(edges, forKey: .edges)
        try c.encode(footprint, forKey: .footprint)
        try c.encode(surfaces, forKey: .surfaces)
        try c.encode(config, forKey: .config)
        try c.encodeIfPresent(overallElevation, forKey: .overallElevation)
        try c.encodeIfPresent(scaleFactor, forKey: .scaleFactor)
        try c.encodeIfPresent(poolDiameter, forKey: .poolDiameter)
        try c.encodeIfPresent(photoOverlay, forKey: .photoOverlay)
        try c.encode(levels, forKey: .levels)
        try c.encode(levelConnections, forKey: .levelConnections)
        try c.encodeIfPresent(components, forKey: .components)
    }

    // MARK: - Vertex Helpers

    public func vertex(byId id: String) -> DeckVertex? {
        vertices.first { $0.id == id }
    }

    public mutating func updateVertex(_ vertex: DeckVertex) {
        if let index = vertices.firstIndex(where: { $0.id == vertex.id }) {
            vertices[index] = vertex
        }
    }

    // MARK: - Edge Helpers

    public func edge(byId id: String) -> DeckEdge? {
        edges.first { $0.id == id }
    }

    public func edges(connectedTo vertexId: String) -> [DeckEdge] {
        edges.filter { $0.startVertexId == vertexId || $0.endVertexId == vertexId }
    }

    public mutating func updateEdge(_ edge: DeckEdge) {
        if let index = edges.firstIndex(where: { $0.id == edge.id }) {
            edges[index] = edge
        }
    }

    // MARK: - Polygon State

    /// Count of vertices whose edge-degree ≠ 2 — i.e. loose/open ends that
    /// keep the perimeter from forming a closed face. 0 ⇒ topologically closed.
    /// Drives the actionable "incomplete design" message in the 3D tab: a deck
    /// that won't render almost always has a small, nameable number of unjoined
    /// ends, and telling the user exactly how many turns a dead-end into a fix.
    public var openEndpointCount: Int {
        // Use allVertices/allEdges so the count is correct in BOTH single-level
        // (top-level vertices/edges) and multi-level designs (geometry lives in
        // `levels`, top-level arrays empty). Reading only the top-level arrays
        // made multi-level always report 0, so the actionable 3D-tab message
        // could never name the open ends there.
        let countVertices = allVertices
        let countEdges = allEdges
        guard !countVertices.isEmpty else { return 0 }
        var degree: [String: Int] = [:]
        for edge in countEdges {
            degree[edge.startVertexId, default: 0] += 1
            degree[edge.endVertexId, default: 0] += 1
        }
        return countVertices.reduce(0) { $0 + ((degree[$1.id] ?? 0) == 2 ? 0 : 1) }
    }

    public var isClosed: Bool {
        guard vertices.count >= 3, edges.count >= 3 else { return false }

        // Build adjacency: vertex → [connected vertex ids]
        var adjacency: [String: Set<String>] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].insert(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].insert(edge.startVertexId)
        }

        // Every vertex must have exactly 2 connections for a simple polygon
        for vertex in vertices {
            let connections = adjacency[vertex.id]?.count ?? 0
            if connections != 2 { return false }
        }

        // Walk the graph from the first vertex — must visit all vertices and return to start
        guard let startId = vertices.first?.id else { return false }
        var visited: Set<String> = [startId]
        var currentId = startId

        for _ in 0..<vertices.count {
            guard let neighbors = adjacency[currentId] else { return false }
            let unvisited = neighbors.subtracting(visited)

            if unvisited.isEmpty {
                // Only valid if we've visited all vertices and can return to start
                return visited.count == vertices.count && neighbors.contains(startId)
            }

            guard let nextId = unvisited.first else { return false }
            visited.insert(nextId)
            currentId = nextId
        }

        return false
    }

    /// Ordered vertex positions for rendering — walks the edge graph in geometric order
    /// so polygon fill traces the visible boundary. Each vertex in a simple closed polygon
    /// has exactly two neighbors, so "next" is always "the one I didn't come from".
    ///
    /// Field bug: picking the alphabetically-smaller neighbor (our previous implementation)
    /// occasionally reversed direction mid-walk on concave/construction-mole shapes,
    /// producing a path that looped back through the interior. CGContext.fillPath then
    /// filled the enclosed region of that broken path — bleeding fill outside the real
    /// edges. Previous-vertex-aware traversal guarantees the walk follows edges only.
    public var orderedPositions: [CGPoint] {
        guard vertices.count >= 3, edges.count >= 3 else {
            return vertices.map { $0.position }
        }

        var adjacency: [String: [String]] = [:]
        for edge in edges {
            adjacency[edge.startVertexId, default: []].append(edge.endVertexId)
            adjacency[edge.endVertexId, default: []].append(edge.startVertexId)
        }

        for vertex in vertices {
            let connections = adjacency[vertex.id]?.count ?? 0
            if connections != 2 { return vertices.map { $0.position } }
        }

        guard let startId = vertices.first?.id else { return vertices.map { $0.position } }
        var ordered: [CGPoint] = []
        var visited: Set<String> = [startId]
        var previousId: String? = nil
        var currentId = startId

        if let startVertex = vertex(byId: startId) {
            ordered.append(startVertex.position)
        }

        for _ in 0..<vertices.count - 1 {
            guard let neighbors = adjacency[currentId] else { break }
            // Pick the neighbor we didn't arrive from. On the first step previousId is
            // nil, so we fall back to a deterministic pick (sorted) — this is the only
            // place winding direction is chosen.
            let nextId: String?
            if let prev = previousId {
                nextId = neighbors.first(where: { $0 != prev })
            } else {
                nextId = neighbors.sorted().first
            }
            guard let next = nextId, !visited.contains(next) else { break }
            visited.insert(next)
            previousId = currentId
            currentId = next
            if let v = vertex(byId: next) {
                ordered.append(v.position)
            }
        }

        guard ordered.count == vertices.count else {
            return vertices.map { $0.position }
        }

        // Normalize winding so the walk always returns vertices in the same
        // visual direction (CCW in SwiftUI canvas coordinates → negative
        // shoelace). The first-step pick is otherwise arbitrary and depends
        // on UUID sort, which would silently flip direction for any future
        // consumer that cares (3D normals, fill rules, etc.).
        if PolygonMath.signedArea(vertices: ordered) > 0 {
            ordered.reverse()
        }

        return ordered
    }

    /// Every closed face in this drawing's edge graph. Replaces the
    /// all-or-nothing `orderedPositions` polygon when the user draws multiple
    /// loops, shares an edge between two surfaces, or adds detail lines
    /// beyond the perimeter (DECK-NEW-1). Returns empty when no loop is
    /// closed yet. For multi-level drawings, callers should ask each level
    /// for its own surfaces — this top-level array only inspects the
    /// single-level fields.
    public var detectedSurfaces: [DetectedSurface] {
        SurfaceDetector.detect(vertices: vertices, edges: edges)
    }

    /// True when the drawing has at least one closed surface — anywhere.
    /// More permissive than `isClosed`, which requires every vertex to be
    /// on the perimeter of one Hamiltonian cycle (so two disjoint deck
    /// footprints, or two separate levels each with their own footprint,
    /// both register as "not closed" via the single-loop walk). Use this
    /// to gate UI that should appear as soon as ANY closed shape exists —
    /// 3D preview, area/perimeter badges, estimate eligibility.
    /// Multi-level aware: in multi-level mode the top-level vertices/edges
    /// arrays are empty (all geometry lives on the levels), so we ask each
    /// level for its own detected surfaces. Bug ee787f29 follow-up — the
    /// DeckTabView 3D viewer was gating on `isClosed`, which always
    /// returned false in multi-level mode and falsely shows the "close the
    /// polygon" empty state.
    public var hasAnyClosedSurface: Bool {
        if isMultiLevel {
            return levels.contains(where: { !$0.detectedSurfaces.isEmpty })
        }
        return !detectedSurfaces.isEmpty
    }

    // MARK: - Multi-Level Helpers

    /// Whether this drawing uses multi-level mode
    public var isMultiLevel: Bool {
        !levels.isEmpty
    }

    /// The active geometry source — levels if multi-level, top-level fields if single
    public var allVertices: [DeckVertex] {
        isMultiLevel ? levels.flatMap { $0.vertices } : vertices
    }

    public var allEdges: [DeckEdge] {
        isMultiLevel ? levels.flatMap { $0.edges } : edges
    }

    /// The scale every real-world measurement on this drawing should use:
    /// the calibrated `scaleFactor` once the user has confirmed a dimension
    /// (or AR / sketch scan / template set it), otherwise the prescale
    /// fallback the canvas already draws, snaps and dimensions every edge at.
    /// A freehand-drawn deck has `scaleFactor == nil` yet is still at a
    /// sound, internally-consistent scale — every edge already carries a
    /// real `dimension` derived from this same fallback. Gating measurement
    /// on `scaleFactor != nil` wrongly treated every un-recalibrated deck as
    /// unmeasurable. Always > 0.
    public var effectiveScaleFactor: Double {
        if let scaleFactor, scaleFactor > 0 { return scaleFactor }
        return Self.prescaleFallbackScale
    }

    public static let prescaleFallbackScale: Double = 2.0

    /// Total area across all levels in square inches
    public func totalRealWorldArea(scaleFactor: Double) -> Double {
        if isMultiLevel {
            return levels.reduce(0) { total, level in
                let surfaces = level.detectedSurfaces
                if surfaces.isEmpty {
                    guard level.isClosed,
                          !PolygonMath.isSelfIntersecting(vertices: level.orderedPositions) else { return total }
                    return total + PolygonMath.realWorldArea(vertices: level.orderedPositions, scaleFactor: scaleFactor)
                }
                return total + surfaces.reduce(0) { surfaceTotal, surface in
                    guard !PolygonMath.isSelfIntersecting(vertices: surface.positions) else { return surfaceTotal }
                    return surfaceTotal + PolygonMath.realWorldArea(vertices: surface.positions, scaleFactor: scaleFactor)
                }
            }
        }
        let surfaces = detectedSurfaces
        if surfaces.isEmpty {
            guard isClosed,
                  !PolygonMath.isSelfIntersecting(vertices: orderedPositions) else { return 0 }
            return PolygonMath.realWorldArea(vertices: orderedPositions, scaleFactor: scaleFactor)
        }
        return surfaces.reduce(0) { total, surface in
            guard !PolygonMath.isSelfIntersecting(vertices: surface.positions) else { return total }
            return total + PolygonMath.realWorldArea(vertices: surface.positions, scaleFactor: scaleFactor)
        }
    }

    /// Get a level by ID
    public func level(byId id: String) -> DeckLevel? {
        levels.first { $0.id == id }
    }

    /// Update a level in place
    public mutating func updateLevel(_ level: DeckLevel) {
        if let index = levels.firstIndex(where: { $0.id == level.id }) {
            levels[index] = level
        }
    }

    /// Elevation difference between two levels in inches
    public func elevationDifference(upperLevelId: String, lowerLevelId: String) -> Double? {
        guard let upper = level(byId: upperLevelId)?.elevation,
              let lower = level(byId: lowerLevelId)?.elevation else { return nil }
        return (upper - lower) * 12.0  // feet to inches
    }

    // MARK: - Render Elevation Resolution

    /// Uniform render elevation (in feet) for one level of a multi-level
    /// design. The 3D scene draws each level's surface as a single flat
    /// polygon, so it needs ONE representative height per level — and the
    /// deck builder stores that height in more than one place depending on
    /// how the user entered it. Reading `level.elevation` alone is the bug:
    /// it is only ever written by `migrateToMultiLevel` (level 0) and
    /// `LevelConnectionSheet` (stair wiring), so any level the user never
    /// connected stays nil and the renderer collapses it onto a flat 2.5'.
    /// Live data confirms this — every saved multi-level design has
    /// `elevation: null` on every level.
    ///
    /// Resolution order:
    /// 1. `level.elevation` — the explicit uniform per-level height.
    /// 2. The average of the level's per-vertex `elevation` values — the
    ///    "sloped" elevation mode and single-vertex height edits write here.
    /// 3. An attached stair's total rise — a stair spans grade up to the deck
    ///    surface, so its rise IS this level's elevation when the user never
    ///    entered one. Adopt it before the arbitrary staggered default.
    /// 4. A staggered height — `base + levelIndex × 2.5'` — so levels never
    ///    collapse onto one another when no per-level height was recorded.
    ///    `base` is `overallElevation` when set: in multi-level mode the
    ///    elevation editor only exposes a single overall-height field, so
    ///    the user's typed height lands there rather than on any level.
    ///    Staggering off that base — instead of using it flat for every
    ///    level — is what both honors the user's input AND keeps the levels
    ///    visually separated.
    public func renderElevationFeet(for level: DeckLevel, levelIndex: Int) -> Double {
        if let elevation = level.elevation { return elevation }
        let vertexElevations = level.vertices.compactMap { $0.elevation }
        if !vertexElevations.isEmpty {
            return vertexElevations.reduce(0, +) / Double(vertexElevations.count)
        }
        if let stairFeet = stairDerivedElevationFeet(edges: level.edges) {
            return stairFeet
        }
        let baseFeet = overallElevation ?? 2.5
        return baseFeet + Double(levelIndex) * 2.5
    }

    /// Resolved uniform render elevation (feet) for the level with the given
    /// id, or nil when no such level exists. Wraps `renderElevationFeet` so
    /// callers that only hold a level id — e.g. level-connection stairs —
    /// resolve height through the same explicit → per-vertex → stair →
    /// staggered ladder the level surfaces use, instead of reading raw
    /// `level.elevation` and disappearing when it is nil.
    public func resolvedElevationFeet(forLevelId id: String) -> Double? {
        guard let index = levels.firstIndex(where: { $0.id == id }) else { return nil }
        return renderElevationFeet(for: levels[index], levelIndex: index)
    }

    /// Uniform render elevation (in feet) for a single-level design.
    /// Priority: `overallElevation` → average of per-vertex elevations →
    /// an attached stair's total rise → the 2.5' default — so single-level
    /// designs resolve height with the same fallbacks as
    /// `renderElevationFeet(for:levelIndex:)`.
    public var renderElevationFeetSingleLevel: Double {
        if let overall = overallElevation { return overall }
        let vertexElevations = vertices.compactMap { $0.elevation }
        if !vertexElevations.isEmpty {
            return vertexElevations.reduce(0, +) / Double(vertexElevations.count)
        }
        if let stairFeet = stairDerivedElevationFeet(edges: edges) {
            return stairFeet
        }
        return 2.5
    }

    /// Highest stair total rise (in feet) among the given edges that carry a
    /// configured stair, or nil when none do. A stair's `totalRiseInches` is
    /// the vertical span it covers — grade up to the deck surface — so it
    /// equals the deck's elevation when no elevation was entered explicitly.
    /// `totalRiseInches` is inches; convert to feet. When several stairs carry
    /// a rise the tallest wins — a deck can't sit lower than its highest stair.
    private func stairDerivedElevationFeet(edges: [DeckEdge]) -> Double? {
        edges
            .compactMap { edge -> Double? in
                guard let inches = edge.stairConfig?.totalRiseInches, inches > 0 else { return nil }
                return inches / 12.0
            }
            .max()
    }

    /// Vertical gap (in feet) from a level's surface up to the bottom of the
    /// next level above it, or nil when no level sits higher. A house wall on
    /// a level must stop at the deck above rather than spear through it, so
    /// the 3D renderers cap the wall at this gap (bug fb007839). Uses the
    /// same resolved heights as `renderElevationFeet(for:levelIndex:)`.
    public func heightToNextLevelFeet(aboveLevelAt levelIndex: Int) -> Double? {
        guard levelIndex >= 0, levelIndex < levels.count else { return nil }
        let thisElevation = renderElevationFeet(for: levels[levelIndex], levelIndex: levelIndex)
        let higherElevations = levels.enumerated()
            .map { renderElevationFeet(for: $0.element, levelIndex: $0.offset) }
            .filter { $0 > thisElevation }
        guard let nextElevation = higherElevations.min() else { return nil }
        return nextElevation - thisElevation
    }

    /// Migrate single-level data to multi-level (called when adding a second level)
    public mutating func migrateToMultiLevel() {
        guard !isMultiLevel, vertices.count >= 3 else { return }
        var firstLevel = DeckLevel(
            name: "Level 1",
            displayColor: .blue,
            sortOrder: 0
        )
        firstLevel.vertices = vertices
        firstLevel.edges = edges
        firstLevel.footprint = footprint
        firstLevel.elevation = overallElevation
        levels = [firstLevel]
        // Clear the top-level shape state — the data lives in `levels[0]` now.
        // Without this, deleting every level later flips `isMultiLevel` back
        // to false, and the original single-level vertices/edges silently
        // resurface (the user dragged a deck into existence twice).
        vertices = []
        edges = []
        footprint = DeckFootprint()
        overallElevation = nil
    }

    // MARK: - Serialization

    public func toJSON() -> String {
        // Recompute the catalog-facing components projection on every encode.
        // The projection is derived from geometry — never authored directly —
        // so refreshing it here guarantees the on-disk JSON always carries an
        // up-to-date components array for `DesignToEstimateAdapter`.
        var copy = self
        copy.components = ComponentEmitter.emit(self)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(copy),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        guard !copy.futureBlocks.isEmpty else { return json }

        guard var merged = try? DeckJSONValue.parseObject(from: json) else {
            return json
        }

        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        for (key, value) in copy.futureBlocks.sorted(by: { $0.key < $1.key }) {
            guard !knownKeys.contains(key), value.isValidJSONObject else { continue }
            merged[key] = value
        }

        return (try? DeckJSONValue.object(merged).renderedJSONString()) ?? json
    }

    public static func fromJSON(_ json: String) -> DeckDrawingData? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard var decoded = try? JSONDecoder().decode(DeckDrawingData.self, from: data) else { return nil }

        if let root = try? DeckJSONValue.parseObject(from: json) {
            let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
            decoded.futureBlocks = root.reduce(into: [:]) { result, entry in
                guard !knownKeys.contains(entry.key) else { return }
                result[entry.key] = entry.value
            }
        }

        // Referential integrity, single-level: drop edges that reference
        // missing vertices, then drop vertices that no surviving edge
        // references. Without the second pass an orphan vertex makes the
        // adjacency walk fail (`connections != 2`) and `isClosed` returns
        // false forever, so the polygon never opens as a valid shape again.
        let vertexIds = Set(decoded.vertices.map { $0.id })
        let beforeEdgeCount = decoded.edges.count
        decoded.edges.removeAll { edge in
            let startMissing = !vertexIds.contains(edge.startVertexId)
            let endMissing = !vertexIds.contains(edge.endVertexId)
            if startMissing || endMissing {
                print("[DeckBuilder] fromJSON: removing orphaned edge \(edge.id) (start: \(startMissing), end: \(endMissing))")
                return true
            }
            return false
        }
        if decoded.edges.count != beforeEdgeCount {
            print("[DeckBuilder] fromJSON: removed \(beforeEdgeCount - decoded.edges.count) orphaned edges")
        }

        let connectedVertexIds = Set(decoded.edges.flatMap { [$0.startVertexId, $0.endVertexId] })
        let beforeVertexCount = decoded.vertices.count
        decoded.vertices.removeAll { !connectedVertexIds.contains($0.id) }
        if decoded.vertices.count != beforeVertexCount {
            print("[DeckBuilder] fromJSON: removed \(beforeVertexCount - decoded.vertices.count) orphaned vertices")
        }

        // Same two-pass check per level.
        for i in decoded.levels.indices {
            let levelVertexIds = Set(decoded.levels[i].vertices.map { $0.id })
            decoded.levels[i].edges.removeAll { edge in
                !levelVertexIds.contains(edge.startVertexId) || !levelVertexIds.contains(edge.endVertexId)
            }
            let connected = Set(decoded.levels[i].edges.flatMap { [$0.startVertexId, $0.endVertexId] })
            decoded.levels[i].vertices.removeAll { !connected.contains($0.id) }
        }

        // Drop any LevelConnection whose referenced edges no longer exist
        // after the integrity pass — otherwise the connection becomes a
        // phantom (renderer silently early-returns) but still ships into
        // estimates. Same rule as runtime delete paths.
        // Snapshot the levels into a local because Swift forbids reading
        // `decoded.levels` from inside a predicate that also mutates
        // `decoded.levelConnections` (overlapping access).
        let levelsSnapshot = decoded.levels
        decoded.levelConnections.removeAll { conn in
            guard let upper = levelsSnapshot.first(where: { $0.id == conn.upperLevelId }),
                  upper.edge(byId: conn.upperEdgeId) != nil else { return true }
            if let lowerEdgeId = conn.lowerEdgeId {
                guard let lower = levelsSnapshot.first(where: { $0.id == conn.lowerLevelId }),
                      lower.edge(byId: lowerEdgeId) != nil else { return true }
            }
            return false
        }

        // Clamp negative scale factor to nil
        if let scale = decoded.scaleFactor, scale <= 0 {
            print("[DeckBuilder] fromJSON: clamping invalid scale factor \(scale) to nil")
            decoded.scaleFactor = nil
        }

        return decoded
    }
}

// MARK: - CGPoint Codable

extension CGPoint: @retroactive Codable {
    public enum CodingKeys: String, CodingKey {
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
