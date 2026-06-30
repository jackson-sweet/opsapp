import Foundation

public enum OverheadSizingCoordinator {
    public static func size(
        _ structure: OverheadStructure,
        load: LoadPreset,
        package: CodePackage
    ) -> OverheadSizingOutcome {
        let assumptions = EngineAssumptions(
            liveLoadPSF: load.liveLoadPSF,
            deadLoadPSF: load.deadLoadPSF,
            snowLoadPSF: load.snowLoadPSF,
            species: load.species,
            grade: load.grade,
            soilBearingPSF: nil,
            packageEdition: package.edition ?? ""
        )

        if let blocked = blockingCitation(for: structure, package: package) {
            return OverheadSizingOutcome(
                structure: clearingSizing(from: structure),
                blocked: blocked,
                assumptions: assumptions
            )
        }

        var sizedStructure = structure
        sizedStructure.framing = StructuralSizingEngine.sizeAll(
            members: structure.framing,
            load: load,
            package: package
        )

        return OverheadSizingOutcome(
            structure: sizedStructure,
            blocked: nil,
            assumptions: assumptions
        )
    }

    private static func blockingCitation(
        for structure: OverheadStructure,
        package: CodePackage
    ) -> EngineCitation? {
        switch structure.kind {
        case .pergola:
            return nil
        case .solidRoof:
            return EngineCitation(
                limitingCheck: "roof-cover load path requires licensed engineer review",
                codeSection: "IRC Appendix H unverified for this package",
                packageEdition: package.edition ?? ""
            )
        case .louveredRoof:
            return EngineCitation(
                limitingCheck: "manufacturer stamped tables required",
                codeSection: "Manufacturer-engineered overhead roof product",
                packageEdition: package.edition ?? ""
            )
        }
    }

    private static func clearingSizing(from structure: OverheadStructure) -> OverheadStructure {
        var copy = structure
        copy.framing = structure.framing.map { member in
            var cleared = member
            cleared.sizing = nil
            return cleared
        }
        return copy
    }
}

public struct OverheadSizingOutcome: Codable, Equatable {
    public var structure: OverheadStructure
    public var blocked: EngineCitation?
    public var assumptions: EngineAssumptions

    public init(
        structure: OverheadStructure,
        blocked: EngineCitation?,
        assumptions: EngineAssumptions
    ) {
        self.structure = structure
        self.blocked = blocked
        self.assumptions = assumptions
    }
}
