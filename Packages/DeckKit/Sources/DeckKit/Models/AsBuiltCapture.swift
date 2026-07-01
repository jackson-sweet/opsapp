import Foundation

public struct AsBuiltAuditOverlay: Codable, Equatable {
    public var fastenerHint: Evidence?
    public var lateralConnectorsPresent: Bool?
    public var flashingPresent: Bool?

    public init(
        fastenerHint: Evidence? = nil,
        lateralConnectorsPresent: Bool? = nil,
        flashingPresent: Bool? = nil
    ) {
        self.fastenerHint = fastenerHint
        self.lateralConnectorsPresent = lateralConnectorsPresent
        self.flashingPresent = flashingPresent
    }
}

public struct AsBuiltCapture: Codable, Equatable {
    public var measuredGeometry: DeckDrawingData
    public var enteredJoist: FramingMember?
    public var enteredBeam: FramingMember?
    public var fastenerHint: Evidence?
    public var lateralConnectorsPresent: Bool?
    public var flashingPresent: Bool?

    public init(
        measuredGeometry: DeckDrawingData = DeckDrawingData(),
        enteredJoist: FramingMember? = nil,
        enteredBeam: FramingMember? = nil,
        fastenerHint: Evidence? = nil,
        lateralConnectorsPresent: Bool? = nil,
        flashingPresent: Bool? = nil
    ) {
        self.measuredGeometry = measuredGeometry
        self.enteredJoist = enteredJoist
        self.enteredBeam = enteredBeam
        self.fastenerHint = fastenerHint
        self.lateralConnectorsPresent = lateralConnectorsPresent
        self.flashingPresent = flashingPresent
    }

    public func asEvaluableDesign() -> DeckDrawingData {
        var data = measuredGeometry
        if let auditOverlay = asBuiltAuditOverlay() {
            data.asBuiltAudit = auditOverlay
        }

        let hiddenMembers = enteredHiddenMembers()
        guard !hiddenMembers.isEmpty else { return data }

        var framing = data.framing ?? FramingPlan(
            members: [],
            generationSource: .manual
        )
        let levelId = primaryFramingLevelId(in: data, framing: framing)

        if let index = framing.members.firstIndex(where: { $0.levelId == levelId }) {
            framing.members[index].members = Self.merging(
                existing: framing.members[index].members,
                entered: hiddenMembers
            )
        } else {
            framing.members.append(
                FramingMemberSet(levelId: levelId, members: hiddenMembers)
            )
        }

        if data.framing == nil {
            framing.generationSource = .manual
        } else if framing.generationSource == .auto {
            framing.generationSource = .autoThenEdited
        }
        data.framing = framing
        return data
    }

    private func asBuiltAuditOverlay() -> AsBuiltAuditOverlay? {
        guard fastenerHint != nil
                || lateralConnectorsPresent != nil
                || flashingPresent != nil else {
            return nil
        }
        return AsBuiltAuditOverlay(
            fastenerHint: fastenerHint,
            lateralConnectorsPresent: lateralConnectorsPresent,
            flashingPresent: flashingPresent
        )
    }

    private func enteredHiddenMembers() -> [FramingMember] {
        var members: [FramingMember] = []
        if let enteredJoist {
            members.append(enteredJoist)
        }
        if let enteredBeam {
            members.append(enteredBeam)
        }
        return members
    }

    private func primaryFramingLevelId(
        in data: DeckDrawingData,
        framing: FramingPlan
    ) -> String {
        if let existingLevelId = framing.members.first?.levelId,
           !existingLevelId.isEmpty {
            return existingLevelId
        }
        if let levelId = data.levels.first?.id,
           !levelId.isEmpty {
            return levelId
        }
        return "level-main"
    }

    private static func merging(
        existing: [FramingMember],
        entered: [FramingMember]
    ) -> [FramingMember] {
        var merged = existing
        for member in entered {
            if let index = merged.firstIndex(where: { $0.id == member.id }) {
                merged[index] = member
            } else {
                merged.append(member)
            }
        }
        return merged
    }
}
