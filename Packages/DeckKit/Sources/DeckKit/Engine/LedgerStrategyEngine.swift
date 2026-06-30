import CoreGraphics
import Foundation

public enum LedgerStrategyEngine {
    public enum Strategy: Equatable {
        /// Ledger attachment is a code-recognized condition for this cladding.
        case attach(detail: LedgerDetail)
        /// Cladding is not a recognized ledger-attachment substrate; fall back
        /// to a freestanding house-side beam line. Geometry only.
        case freestanding(detail: LedgerDetail, fallback: FreestandingFallback)
    }

    public struct FreestandingFallback: Equatable {
        public var beamMembers: [FramingMember]
        public var footingAnchors: [Footing]
        public var rationale: String

        public init(
            beamMembers: [FramingMember],
            footingAnchors: [Footing],
            rationale: String
        ) {
            self.beamMembers = beamMembers
            self.footingAnchors = footingAnchors
            self.rationale = rationale
        }
    }

    public static func strategy(
        for edge: DeckEdge,
        houseSideBeamSpanInches: Double,
        package: CodePackage?
    ) -> Strategy {
        let start = CGPoint.zero
        let end = CGPoint(x: max(0, houseSideBeamSpanInches), y: 0)
        return strategy(
            for: edge,
            start: start,
            end: end,
            spanInches: max(0, houseSideBeamSpanInches),
            package: package
        )
    }

    public static func strategy(
        for edge: DeckEdge,
        in data: DeckDrawingData,
        package: CodePackage?
    ) -> Strategy {
        guard let start = vertexPosition(edge.startVertexId, in: data),
              let end = vertexPosition(edge.endVertexId, in: data) else {
            return strategy(
                for: edge,
                houseSideBeamSpanInches: WallOpeningGeometry.wallLengthInches(edge: edge, in: data),
                package: package
            )
        }

        return strategy(
            for: edge,
            start: start,
            end: end,
            spanInches: WallOpeningGeometry.wallLengthInches(edge: edge, in: data),
            package: package
        )
    }

    public static func resolvedDetail(_ strategy: Strategy) -> LedgerDetail {
        switch strategy {
        case let .attach(detail):
            return detail
        case let .freestanding(detail, _):
            return detail
        }
    }

    private static func strategy(
        for edge: DeckEdge,
        start: CGPoint,
        end: CGPoint,
        spanInches: Double,
        package: CodePackage?
    ) -> Strategy {
        let cladding = edge.houseEdgeMaterial ?? .stucco
        let detail = LedgerDetail(
            cladding: cladding,
            attachmentAllowed: attachmentAllowed(for: cladding)
        )

        guard !detail.attachmentAllowed else {
            return .attach(detail: detail)
        }

        return .freestanding(
            detail: detail,
            fallback: FreestandingFallback(
                beamMembers: [
                    FramingMember(
                        id: "ledger-fallback-beam-\(edge.id)",
                        role: .beam,
                        start: start,
                        end: end
                    )
                ],
                footingAnchors: footingAnchors(
                    edgeId: edge.id,
                    start: start,
                    end: end,
                    spanInches: spanInches
                ),
                rationale: rationale(for: cladding, package: package)
            )
        )
    }

    private static func attachmentAllowed(for cladding: HouseEdgeMaterial) -> Bool {
        switch cladding {
        case .stucco, .hardie, .woodVertical, .vinyl:
            return true
        case .brick, .stone, .parapet:
            return false
        }
    }

    private static func footingAnchors(
        edgeId: String,
        start: CGPoint,
        end: CGPoint,
        spanInches: Double
    ) -> [Footing] {
        let segmentCount = max(1, Int(ceil(max(0, spanInches) / 96)))
        return (0...segmentCount).map { index in
            let t = CGFloat(Double(index) / Double(segmentCount))
            return Footing(
                id: "ledger-fallback-footing-\(edgeId)-\(index)",
                vertexId: nil,
                position: interpolate(start: start, end: end, t: t),
                type: .sonoTube
            )
        }
    }

    private static func interpolate(start: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + ((end.x - start.x) * t),
            y: start.y + ((end.y - start.y) * t)
        )
    }

    private static func rationale(for cladding: HouseEdgeMaterial, package: CodePackage?) -> String {
        let base = "\(rationaleCladdingName(cladding)) cladding is not a code-recognized ledger substrate. OPS switches this edge to a freestanding house-side beam."
        if package == nil {
            return "\(base) Select a jurisdiction before using this in a permit set."
        }
        return base
    }

    private static func rationaleCladdingName(_ cladding: HouseEdgeMaterial) -> String {
        switch cladding {
        case .stucco:
            return "Stucco"
        case .hardie:
            return "Hardie"
        case .woodVertical:
            return "Wood"
        case .brick:
            return "Brick"
        case .stone:
            return "Stone"
        case .vinyl:
            return "Vinyl"
        case .parapet:
            return "Parapet"
        }
    }

    private static func vertexPosition(_ vertexId: String, in data: DeckDrawingData) -> CGPoint? {
        data.allVertices.first { $0.id == vertexId }?.position
    }
}
