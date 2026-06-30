import Foundation

public enum StructuralSizingEngine {
    public static func stringerSizing(
        base: StairCalculator.StairSpec,
        spacingInchesOC: Double,
        species: WoodSpecies,
        grade: LumberGrade,
        package: CodePackage,
        stringerType: StairStringerType = .notchedWoodOpen
    ) -> MemberSizingResult {
        let matchingRows = package.stairRules.notchedStringerSizing.filter {
            $0.species == species && $0.grade == grade && $0.stringerType == stringerType
        }
        let fallbackCitation = citation(
            row: matchingRows.first,
            package: package
        )

        guard !matchingRows.isEmpty else {
            return MemberSizingResult(
                outcome: .outOfEnvelope(
                    reason: "No \(label(for: stringerType)) table for this code package.",
                    citation: fallbackCitation
                )
            )
        }

        let coveringRows = matchingRows
            .filter {
                spacingInchesOC <= $0.maxSpacingInchesOC
                    && base.stringerLength <= $0.maxStringerLengthInches
            }
            .sorted {
                if $0.maxStringerLengthInches == $1.maxStringerLengthInches {
                    return $0.maxSpacingInchesOC < $1.maxSpacingInchesOC
                }
                return $0.maxStringerLengthInches < $1.maxStringerLengthInches
            }

        guard let row = coveringRows.first else {
            return MemberSizingResult(
                outcome: .outOfEnvelope(
                    reason: "The \(label(for: stringerType)) run is outside the code package.",
                    citation: fallbackCitation
                )
            )
        }

        let actualSpanFeet = base.stringerLength / 12
        let allowableSpanFeet = row.maxStringerLengthInches / 12
        let utilization = row.maxStringerLengthInches > 0
            ? base.stringerLength / row.maxStringerLengthInches
            : 0

        return MemberSizingResult(
            outcome: .ok(
                value: SizedMember(
                    size: row.size,
                    plyCount: 1,
                    allowableSpanFeet: allowableSpanFeet,
                    actualSpanFeet: actualSpanFeet,
                    utilization: utilization
                ),
                citation: citation(row: row, package: package),
                assumptions: EngineAssumptions(
                    liveLoadPSF: 40,
                    deadLoadPSF: 10,
                    snowLoadPSF: nil,
                    species: species,
                    grade: grade,
                    soilBearingPSF: nil,
                    packageEdition: package.edition ?? ""
                )
            )
        )
    }

    private static func citation(row: StairStringerSizingRow?, package: CodePackage) -> EngineCitation {
        EngineCitation(
            limitingCheck: "notched stringer table",
            codeSection: row?.codeSection ?? "IRC R311.7 / AWC DCA6",
            packageEdition: package.edition ?? ""
        )
    }

    private static func label(for stringerType: StairStringerType) -> String {
        switch stringerType {
        case .notchedWoodOpen:
            return "notched-stringer"
        case .closedWood:
            return "closed wood stringer"
        case .steel:
            return "steel stringer"
        }
    }
}
