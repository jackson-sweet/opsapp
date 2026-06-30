import Foundation

public enum RailingComponentBreakdown {
    public static func parts(
        railing: RailingConfig,
        edgeLengthInches: Double,
        family: RailingMaterialFamily
    ) -> [RailingPart] {
        let linearFeet = max(0, edgeLengthInches) / 12
        let postCount = Double(DimensionEngine.postCount(
            edgeLengthInches: max(0, edgeLengthInches),
            maxSpacing: railing.maxPostSpacing
        ))
        let framedRailFeet = railing.frameStyle == .frameless ? 0 : linearFeet * 2
        let framedPostCount = railing.frameStyle == .frameless ? 0 : postCount

        return [
            RailingPart(part: "rail", quantity: roundToTwo(framedRailFeet), unit: "linear ft", family: family),
            RailingPart(part: "infill", quantity: roundToTwo(linearFeet), unit: "linear ft", family: family),
            RailingPart(part: "post", quantity: framedPostCount, unit: "each", family: family),
            RailingPart(part: "sleeve", quantity: framedPostCount, unit: "each", family: family),
            RailingPart(part: "cap", quantity: framedPostCount, unit: "each", family: family),
        ]
    }

    private static func roundToTwo(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

public enum RailingMaterialFamily: String, Codable, CaseIterable {
    case aluminum
    case composite
    case pvc
    case wood
    case cable
    case glass
}

public struct RailingPart: Codable, Equatable {
    public var part: String
    public var quantity: Double
    public var unit: String
    public var family: RailingMaterialFamily

    public init(
        part: String,
        quantity: Double,
        unit: String,
        family: RailingMaterialFamily
    ) {
        self.part = part
        self.quantity = quantity
        self.unit = unit
        self.family = family
    }
}
