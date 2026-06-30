import Foundation

public struct CodePackage: Codable, Equatable {
    public var jurisdictionId: String
    public var edition: String?

    private enum CodingKeys: String, CodingKey {
        case jurisdictionId
        case edition
    }

    public init(
        jurisdictionId: String = "",
        edition: String? = nil
    ) {
        self.jurisdictionId = jurisdictionId
        self.edition = edition
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.jurisdictionId = try c.decodeIfPresent(String.self, forKey: .jurisdictionId) ?? ""
        self.edition = try c.decodeIfPresent(String.self, forKey: .edition)
    }
}
