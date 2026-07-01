import CoreGraphics
import Foundation

enum GeometryChecks {
    static func evaluate(
        _ data: DeckDrawingData,
        mode: ComplianceEngine.Mode,
        package: CodePackage
    ) -> [ComplianceFinding] {
        var findings: [ComplianceFinding] = []
        let invalidEdgeIds = invalidEdgeIds(data)

        findings.append(
            contentsOf: invalidEdgeIds.map {
                invalidEdgeFinding(edgeId: $0, package: package)
            }
        )

        if invalidEdgeIds.isEmpty {
            findings.append(contentsOf: footprintFindings(data, package: package))
        }

        if mode == .asBuilt,
           hasFootprintGeometry(data),
           explicitDeckHeightFeet(data) == nil {
            findings.append(missingElevationFinding(package: package))
        }

        findings.append(contentsOf: postSpacingFindings(data, package: package))
        return findings
    }

    private static func invalidEdgeIds(_ data: DeckDrawingData) -> [String] {
        let vertexIds = Set(data.allVertices.map(\.id))
        return data.allEdges
            .filter {
                !vertexIds.contains($0.startVertexId)
                    || !vertexIds.contains($0.endVertexId)
            }
            .map(\.id)
            .sorted()
    }

    private static func footprintFindings(
        _ data: DeckDrawingData,
        package: CodePackage
    ) -> [ComplianceFinding] {
        if data.isMultiLevel {
            return data.levels.flatMap { level in
                footprintFindings(
                    isClosed: level.isClosed,
                    hasSurface: !level.detectedSurfaces.isEmpty,
                    orderedPositions: level.orderedPositions,
                    idSuffix: level.id,
                    package: package
                )
            }
        }

        return footprintFindings(
            isClosed: data.isClosed,
            hasSurface: !data.detectedSurfaces.isEmpty,
            orderedPositions: data.orderedPositions,
            idSuffix: nil,
            package: package
        )
    }

    private static func footprintFindings(
        isClosed: Bool,
        hasSurface: Bool,
        orderedPositions: [CGPoint],
        idSuffix: String?,
        package: CodePackage
    ) -> [ComplianceFinding] {
        guard orderedPositions.count >= 3 else { return [] }

        if !isClosed && !hasSurface {
            return [
                ComplianceFinding(
                    id: suffixed("geometry:footprint:open", idSuffix),
                    item: "Deck footprint",
                    severity: .notAssessable,
                    currentValue: "open perimeter",
                    targetValue: "closed perimeter",
                    codeSection: packageCodeSection(package),
                    fix: "Close the deck footprint before permit review.",
                    confidence: .low,
                    evidence: nil,
                    source: .notAssessable
                )
            ]
        }

        if isClosed && PolygonMath.isSelfIntersecting(vertices: orderedPositions) {
            return [
                ComplianceFinding(
                    id: suffixed("geometry:footprint:self-intersecting", idSuffix),
                    item: "Deck footprint",
                    severity: .safetyHazard,
                    currentValue: "self-intersecting",
                    targetValue: "simple closed footprint",
                    codeSection: packageCodeSection(package),
                    fix: "Redraw the footprint as one simple closed perimeter.",
                    confidence: .high,
                    evidence: nil,
                    source: .measured
                )
            ]
        }

        return []
    }

    private static func postSpacingFindings(
        _ data: DeckDrawingData,
        package: CodePackage
    ) -> [ComplianceFinding] {
        guard let footings = data.footings?.footings,
              footings.count >= 2,
              let limit = postSpacingLimit(package) else {
            return []
        }

        let pairs = footingSpacingPairs(footings)
        return pairs.compactMap { first, second in
            let spacingInches = SnapEngine.distance(first.position, second.position)
                / data.effectiveScaleFactor
            guard spacingInches > limit.maxSpanFeet * 12 else { return nil }
            return ComplianceFinding(
                id: "geometry:post-spacing:\(first.id):\(second.id)",
                item: "Post spacing \(first.id) to \(second.id)",
                severity: .safetyHazard,
                currentValue: DimensionEngine.formatImperial(spacingInches),
                targetValue: "\(DimensionEngine.formatImperial(limit.maxSpanFeet * 12)) maximum",
                codeSection: limit.codeSection,
                fix: "Add a support or reduce spacing.",
                confidence: .high,
                evidence: nil,
                source: .measured
            )
        }
    }

    private static func footingSpacingPairs(_ footings: [Footing]) -> [(Footing, Footing)] {
        var pairs: [(Footing, Footing)] = []
        var seen: Set<String> = []

        appendConsecutivePairs(
            from: footings.sorted {
                if abs($0.position.y - $1.position.y) <= 0.5 {
                    return $0.position.x < $1.position.x
                }
                return $0.position.y < $1.position.y
            },
            axis: \.position.y,
            into: &pairs,
            seen: &seen
        )
        appendConsecutivePairs(
            from: footings.sorted {
                if abs($0.position.x - $1.position.x) <= 0.5 {
                    return $0.position.y < $1.position.y
                }
                return $0.position.x < $1.position.x
            },
            axis: \.position.x,
            into: &pairs,
            seen: &seen
        )

        return pairs
    }

    private static func appendConsecutivePairs(
        from footings: [Footing],
        axis: KeyPath<Footing, CGFloat>,
        into pairs: inout [(Footing, Footing)],
        seen: inout Set<String>
    ) {
        guard footings.count >= 2 else { return }

        for index in 0..<(footings.count - 1) {
            let first = footings[index]
            let second = footings[index + 1]
            guard abs(first[keyPath: axis] - second[keyPath: axis]) <= 0.5 else { continue }
            let key = first.id < second.id
                ? "\(first.id):\(second.id)"
                : "\(second.id):\(first.id)"
            guard seen.insert(key).inserted else { continue }
            pairs.append((first, second))
        }
    }

    private static func postSpacingLimit(_ package: CodePackage) -> PostSpacingLimit? {
        if let row = package.beamSpanTable
            .filter({ $0.role == .beam })
            .max(by: { $0.maxSpanFeet < $1.maxSpanFeet }) {
            return PostSpacingLimit(maxSpanFeet: row.maxSpanFeet, codeSection: row.codeSection)
        }

        guard let maxMemberSpanFeet = package.envelopeLimits.maxMemberSpanFeet else {
            return nil
        }
        return PostSpacingLimit(
            maxSpanFeet: maxMemberSpanFeet,
            codeSection: packageCodeSection(package)
        )
    }

    private static func invalidEdgeFinding(
        edgeId: String,
        package: CodePackage
    ) -> ComplianceFinding {
        ComplianceFinding(
            id: "geometry:edge:\(edgeId)",
            item: "Edge \(edgeId)",
            severity: .notAssessable,
            currentValue: "missing vertex",
            targetValue: "valid endpoints",
            codeSection: packageCodeSection(package),
            fix: "Reconnect or delete this edge.",
            confidence: .low,
            evidence: nil,
            source: .notAssessable
        )
    }

    private static func missingElevationFinding(package: CodePackage) -> ComplianceFinding {
        ComplianceFinding(
            id: "geometry:elevation:missing",
            item: "Deck height above grade",
            severity: .notAssessable,
            currentValue: nil,
            targetValue: nil,
            codeSection: packageCodeSection(package),
            fix: "Measure deck height above grade before audit.",
            confidence: .low,
            evidence: nil,
            source: .notAssessable
        )
    }

    private static func explicitDeckHeightFeet(_ data: DeckDrawingData) -> Double? {
        if let overallElevation = data.overallElevation {
            return overallElevation
        }

        let levelElevations = data.levels.compactMap(\.elevation)
        if let highestLevel = levelElevations.max() {
            return highestLevel
        }

        let vertexElevations = data.allVertices.compactMap(\.elevation)
        guard !vertexElevations.isEmpty else { return nil }
        return vertexElevations.max()
    }

    private static func hasFootprintGeometry(_ data: DeckDrawingData) -> Bool {
        if data.isMultiLevel {
            return data.levels.contains { $0.vertices.count >= 3 || !$0.detectedSurfaces.isEmpty }
        }
        return data.vertices.count >= 3 || !data.detectedSurfaces.isEmpty
    }

    private static func packageCodeSection(_ package: CodePackage) -> String {
        package.edition ?? package.jurisdictionId
    }

    private static func suffixed(_ id: String, _ suffix: String?) -> String {
        guard let suffix else { return id }
        return "\(id):\(suffix)"
    }
}

private struct PostSpacingLimit {
    var maxSpanFeet: Double
    var codeSection: String
}
