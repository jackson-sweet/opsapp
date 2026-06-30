import Foundation

public enum StructuralSizingEngine {
    public static func beamSizing(
        member: FramingMember,
        load: LoadPreset,
        package: CodePackage
    ) -> MemberSizingResult {
        let actualSpanFeet = memberLengthFeet(member)
        let species = member.species ?? load.species
        let grade = member.grade ?? load.grade
        let requestedPlyCount = max(member.plyCount, 1)
        let role = spanRole(for: member.role)
        let matchingRows = package.beamSpanTable.filter {
            $0.role == role
                && $0.species == species
                && $0.grade == grade
                && $0.plyCount == requestedPlyCount
                && (member.nominalSize == nil || $0.size == member.nominalSize)
        }
        let fallbackCitation = beamCitation(
            row: matchingRows.first,
            role: role,
            package: package
        )

        guard actualSpanFeet > 0 else {
            return MemberSizingResult(
                outcome: .outOfEnvelope(
                    reason: "\(role.rawValue) span is missing; no sizing emitted.",
                    citation: fallbackCitation
                )
            )
        }

        guard !matchingRows.isEmpty else {
            return MemberSizingResult(
                outcome: .outOfEnvelope(
                    reason: "No beam span table for \(role.rawValue) in this code package.",
                    citation: fallbackCitation
                )
            )
        }

        if let maxMemberSpanFeet = package.envelopeLimits.maxMemberSpanFeet,
           actualSpanFeet > maxMemberSpanFeet {
            return MemberSizingResult(
                outcome: .outOfEnvelope(
                    reason: "\(role.rawValue) span exceeds the code package envelope.",
                    citation: fallbackCitation
                )
            )
        }

        let coveringRows = matchingRows
            .filter {
                actualSpanFeet <= $0.maxSpanFeet
                    && covers(load: load, row: $0)
            }
            .sorted {
                if $0.maxSpanFeet == $1.maxSpanFeet {
                    return $0.size.rawValue < $1.size.rawValue
                }
                return $0.maxSpanFeet < $1.maxSpanFeet
            }

        guard let row = coveringRows.first else {
            return MemberSizingResult(
                outcome: .outOfEnvelope(
                    reason: "The \(role.rawValue) span is outside the code package.",
                    citation: fallbackCitation
                )
            )
        }

        return MemberSizingResult(
            outcome: .ok(
                value: SizedMember(
                    size: row.size,
                    plyCount: row.plyCount,
                    allowableSpanFeet: row.maxSpanFeet,
                    actualSpanFeet: actualSpanFeet,
                    utilization: actualSpanFeet / row.maxSpanFeet
                ),
                citation: beamCitation(row: row, role: role, package: package),
                assumptions: assumptions(load: load, species: species, grade: grade, package: package)
            )
        )
    }

    public static func postSizing(
        member: FramingMember,
        load: LoadPreset,
        package: CodePackage
    ) -> MemberSizingResult {
        let actualHeightFeet = memberLengthFeet(member)
        let species = member.species ?? load.species
        let grade = member.grade ?? load.grade
        let matchingRows = package.postHeightTable.filter {
            $0.species == species
                && $0.grade == grade
                && (member.nominalSize == nil || $0.size == member.nominalSize)
        }
        let fallbackCitation = postCitation(row: matchingRows.first, package: package)

        guard actualHeightFeet > 0 else {
            return MemberSizingResult(
                outcome: .outOfEnvelope(
                    reason: "Post height is missing; no sizing emitted.",
                    citation: postCitation(row: nil, package: package)
                )
            )
        }

        guard !matchingRows.isEmpty else {
            return MemberSizingResult(
                outcome: .outOfEnvelope(
                    reason: "No post height table for this code package.",
                    citation: fallbackCitation
                )
            )
        }

        if let maxPostHeightFeet = package.envelopeLimits.maxPostHeightFeet,
           actualHeightFeet > maxPostHeightFeet {
            return MemberSizingResult(
                outcome: .outOfEnvelope(
                    reason: "Post height exceeds the code package envelope.",
                    citation: fallbackCitation
                )
            )
        }

        let coveringRows = matchingRows
            .filter { actualHeightFeet <= $0.maxHeightFeet }
            .sorted {
                if $0.maxHeightFeet == $1.maxHeightFeet {
                    return $0.size.rawValue < $1.size.rawValue
                }
                return $0.maxHeightFeet < $1.maxHeightFeet
            }

        guard let row = coveringRows.first else {
            return MemberSizingResult(
                outcome: .outOfEnvelope(
                    reason: "The post height is outside the code package.",
                    citation: fallbackCitation
                )
            )
        }

        return MemberSizingResult(
            outcome: .ok(
                value: SizedMember(
                    size: row.size,
                    plyCount: 1,
                    allowableSpanFeet: row.maxHeightFeet,
                    actualSpanFeet: actualHeightFeet,
                    utilization: actualHeightFeet / row.maxHeightFeet
                ),
                citation: postCitation(row: row, package: package),
                assumptions: assumptions(load: load, species: species, grade: grade, package: package)
            )
        )
    }

    public static func sizeAll(
        members: [FramingMember],
        load: LoadPreset,
        package: CodePackage
    ) -> [FramingMember] {
        members.map { member in
            var sizedMember = member
            switch member.role {
            case .beam, .joist:
                sizedMember.sizing = beamSizing(member: member, load: load, package: package)
            case .post:
                sizedMember.sizing = postSizing(member: member, load: load, package: package)
            case .ledger, .rimBand, .blocking, .bridging, .cantilever:
                sizedMember.sizing = nil
            }
            return sizedMember
        }
    }

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

    private static func memberLengthFeet(_ member: FramingMember) -> Double {
        SnapEngine.distance(member.start, member.end) / 12
    }

    private static func spanRole(for role: FramingRole) -> FramingRole {
        role == .joist ? .joist : .beam
    }

    private static func covers(load: LoadPreset, row: BeamSpanSizingRow) -> Bool {
        let snowCovered: Bool
        if let snowLoad = load.snowLoadPSF {
            snowCovered = covers(snowLoad, max: row.maxSnowLoadPSF)
        } else {
            snowCovered = true
        }

        return covers(load.liveLoadPSF, max: row.maxLiveLoadPSF)
            && covers(load.deadLoadPSF, max: row.maxDeadLoadPSF)
            && snowCovered
    }

    private static func covers(_ load: Double, max: Double?) -> Bool {
        guard let max else { return true }
        return load <= max
    }

    private static func assumptions(
        load: LoadPreset,
        species: WoodSpecies,
        grade: LumberGrade,
        package: CodePackage
    ) -> EngineAssumptions {
        EngineAssumptions(
            liveLoadPSF: load.liveLoadPSF,
            deadLoadPSF: load.deadLoadPSF,
            snowLoadPSF: load.snowLoadPSF,
            species: species,
            grade: grade,
            soilBearingPSF: nil,
            packageEdition: package.edition ?? ""
        )
    }

    private static func beamCitation(
        row: BeamSpanSizingRow?,
        role: FramingRole,
        package: CodePackage
    ) -> EngineCitation {
        EngineCitation(
            limitingCheck: row?.limitingCheck ?? "\(role.rawValue) span table",
            codeSection: row?.codeSection ?? "AWC DCA6 / package beam span table",
            packageEdition: package.edition ?? ""
        )
    }

    private static func postCitation(row: PostHeightSizingRow?, package: CodePackage) -> EngineCitation {
        EngineCitation(
            limitingCheck: row?.limitingCheck ?? "post height table",
            codeSection: row?.codeSection ?? "IRC R507.4 / package post table",
            packageEdition: package.edition ?? ""
        )
    }
}
