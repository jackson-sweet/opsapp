import Foundation
import CoreGraphics

public struct TerrainModel: Codable, Equatable {
    public var gradePoints: [GradePoint]
    public var groundCover: [GroundZone]
    public var slopeSource: ElevationSource

    private enum CodingKeys: String, CodingKey {
        case gradePoints
        case groundCover
        case slopeSource
    }

    public init(
        gradePoints: [GradePoint] = [],
        groundCover: [GroundZone] = [],
        slopeSource: ElevationSource = .manual
    ) {
        self.gradePoints = gradePoints
        self.groundCover = groundCover
        self.slopeSource = slopeSource
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.gradePoints = try c.decodeIfPresent([GradePoint].self, forKey: .gradePoints) ?? []
        self.groundCover = try c.decodeIfPresent([GroundZone].self, forKey: .groundCover) ?? []
        self.slopeSource = try c.decodeIfPresent(ElevationSource.self, forKey: .slopeSource) ?? .manual
    }
}

public struct GroundZone: Codable, Equatable, Identifiable {
    public let id: String
    public var polygon: [CGPoint]
    public var cover: GroundCover

    private enum CodingKeys: String, CodingKey {
        case id
        case polygon
        case cover
    }

    public init(id: String = UUID().uuidString, polygon: [CGPoint], cover: GroundCover) {
        self.id = id
        self.polygon = polygon
        self.cover = cover
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.polygon = try c.decodeIfPresent([CGPoint].self, forKey: .polygon) ?? []
        self.cover = try c.decodeIfPresent(GroundCover.self, forKey: .cover) ?? .grass
    }
}

public enum GroundCover: String, Codable, CaseIterable {
    case grass
    case dirt
    case gravel
    case rock
    case concrete
    case pavers
}

public struct GradePoint: Codable, Equatable {
    public var position: CGPoint
    public var dropFeet: Double

    public init(position: CGPoint, dropFeet: Double) {
        self.position = position
        self.dropFeet = dropFeet
    }
}
