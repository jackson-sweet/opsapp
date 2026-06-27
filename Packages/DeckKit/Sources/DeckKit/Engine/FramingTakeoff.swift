import CoreGraphics
import Foundation

public struct WasteSettings: Codable, Equatable {
    public var defaultWastePercent: Double
    public var perPatternWastePercent: [String: Double]

    public init(
        defaultWastePercent: Double = 10,
        perPatternWastePercent: [String: Double] = [:]
    ) {
        self.defaultWastePercent = defaultWastePercent
        self.perPatternWastePercent = perPatternWastePercent
    }
}

public enum FramingTakeoff {
    public struct LumberRow: Equatable {
        public let role: FramingRole
        public let nominalSize: LumberSize
        public let plyCount: Int
        public let totalLinearFeet: Double
        public let pieceCount: Int

        public init(
            role: FramingRole,
            nominalSize: LumberSize,
            plyCount: Int,
            totalLinearFeet: Double,
            pieceCount: Int
        ) {
            self.role = role
            self.nominalSize = nominalSize
            self.plyCount = plyCount
            self.totalLinearFeet = totalLinearFeet
            self.pieceCount = pieceCount
        }
    }

    public struct HardwareRow: Equatable {
        public let kind: String
        public let count: Int

        public init(kind: String, count: Int) {
            self.kind = kind
            self.count = count
        }
    }

    public struct Takeoff: Equatable {
        public let lumber: [LumberRow]
        public let hardware: [HardwareRow]
        public let footingCount: Int

        public init(lumber: [LumberRow], hardware: [HardwareRow], footingCount: Int) {
            self.lumber = lumber
            self.hardware = hardware
            self.footingCount = footingCount
        }
    }

    public static func takeoff(
        _ framing: FramingPlan,
        waste: WasteSettings,
        scaleFactor: Double
    ) -> Takeoff {
        struct LumberKey: Hashable {
            let role: FramingRole
            let nominalSize: LumberSize
            let plyCount: Int
        }

        var grouped: [LumberKey: (linearFeet: Double, pieceCount: Int)] = [:]
        var joistCount = 0
        var postCount = 0
        let safeScaleFactor = scaleFactor > 0 ? scaleFactor : 1

        for member in framing.members.flatMap(\.members) {
            guard let nominalSize = member.nominalSize else { continue }

            let plyCount = max(1, member.plyCount)
            let linearFeet = memberLinearFeet(member, scaleFactor: safeScaleFactor) * Double(plyCount)
            let key = LumberKey(role: member.role, nominalSize: nominalSize, plyCount: plyCount)
            let existing = grouped[key] ?? (linearFeet: 0, pieceCount: 0)
            grouped[key] = (
                linearFeet: existing.linearFeet + linearFeet,
                pieceCount: existing.pieceCount + 1
            )

            switch member.role {
            case .joist:
                joistCount += 1
            case .post:
                postCount += 1
            case .beam, .ledger, .rimBand, .blocking, .bridging, .cantilever:
                break
            }
        }

        let wasteMultiplier = 1 + max(0, waste.defaultWastePercent) / 100
        let lumber = grouped
            .map { key, value in
                LumberRow(
                    role: key.role,
                    nominalSize: key.nominalSize,
                    plyCount: key.plyCount,
                    totalLinearFeet: roundToTwo(value.linearFeet * wasteMultiplier),
                    pieceCount: value.pieceCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.role.sortIndex != rhs.role.sortIndex { return lhs.role.sortIndex < rhs.role.sortIndex }
                if lhs.nominalSize.rawValue != rhs.nominalSize.rawValue { return lhs.nominalSize.rawValue < rhs.nominalSize.rawValue }
                return lhs.plyCount < rhs.plyCount
            }

        var hardware: [HardwareRow] = []
        if joistCount > 0 {
            hardware.append(HardwareRow(kind: "joist_hanger", count: joistCount * 2))
        }
        if postCount > 0 {
            hardware.append(HardwareRow(kind: "post_base", count: postCount))
        }

        return Takeoff(lumber: lumber, hardware: hardware, footingCount: postCount)
    }

    private static func memberLinearFeet(_ member: FramingMember, scaleFactor: Double) -> Double {
        let dx = member.end.x - member.start.x
        let dy = member.end.y - member.start.y
        return Double(hypot(dx, dy)) / scaleFactor / 12
    }

    private static func roundToTwo(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

private extension FramingRole {
    var sortIndex: Int {
        switch self {
        case .joist: return 0
        case .beam: return 1
        case .post: return 2
        case .ledger: return 3
        case .rimBand: return 4
        case .blocking: return 5
        case .bridging: return 6
        case .cantilever: return 7
        }
    }
}
