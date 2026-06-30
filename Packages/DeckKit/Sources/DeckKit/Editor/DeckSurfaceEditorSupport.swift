import Foundation

enum DeckSurfaceEditorEntryKind: Hashable {
    case surfacePattern
    case stairDetail
    case surfaceFeatures
    case overheadStructure
    case opsDecksProUpsell
}

struct DeckSurfaceEditorEntry: Equatable, Identifiable {
    let kind: DeckSurfaceEditorEntryKind
    let title: String
    let subtitle: String
    let systemImage: String
    let isUpsell: Bool

    var id: DeckSurfaceEditorEntryKind { kind }
}

enum DeckSurfaceEditorToolbarModel {
    static func entries(for capabilities: DeckCapabilities) -> [DeckSurfaceEditorEntry] {
        var entries: [DeckSurfaceEditorEntry] = []

        if capabilities.contains(.surfacePatterns) {
            entries.append(
                DeckSurfaceEditorEntry(
                    kind: .surfacePattern,
                    title: String(localized: "Pattern"),
                    subtitle: String(localized: "Board direction and frame"),
                    systemImage: "rectangle.split.3x1",
                    isUpsell: false
                )
            )
        }

        if capabilities.contains(.stairDetails) {
            entries.append(
                DeckSurfaceEditorEntry(
                    kind: .stairDetail,
                    title: String(localized: "Stairs"),
                    subtitle: String(localized: "Stringers and treads"),
                    systemImage: "stairs",
                    isUpsell: false
                )
            )
        }

        if capabilities.contains(.surfaceFeatures) {
            entries.append(
                DeckSurfaceEditorEntry(
                    kind: .surfaceFeatures,
                    title: String(localized: "Features"),
                    subtitle: String(localized: "Fascia, skirting, lighting"),
                    systemImage: "square.stack.3d.down.forward",
                    isUpsell: false
                )
            )
        }

        if capabilities.contains(.overheadStructures) {
            entries.append(
                DeckSurfaceEditorEntry(
                    kind: .overheadStructure,
                    title: String(localized: "Overhead"),
                    subtitle: String(localized: "Pergola and roof blocks"),
                    systemImage: "rectangle.tophalf.inset.filled",
                    isUpsell: false
                )
            )
        }

        guard entries.isEmpty else { return entries }
        return [
            DeckSurfaceEditorEntry(
                kind: .opsDecksProUpsell,
                title: String(localized: "Available in OPS Decks Pro"),
                subtitle: String(localized: "Open the standalone app to edit surfaces"),
                systemImage: "lock",
                isUpsell: true
            ),
        ]
    }
}

struct DeckSurfaceEditorEngineRunner {
    var overheadSize: (OverheadStructure, LoadPreset, CodePackage) -> OverheadSizingOutcome
    var stairDetail: (
        StairCalculator.StairSpec,
        TreadType,
        String,
        Double,
        WoodSpecies,
        LumberGrade,
        CodePackage,
        StairStringerType
    ) -> StairDetailResult

    static let live = DeckSurfaceEditorEngineRunner(
        overheadSize: { structure, load, package in
            OverheadSizingCoordinator.size(structure, load: load, package: package)
        },
        stairDetail: { base, treadType, treadMaterial, spacing, species, grade, package, stringerType in
            StairDetailEngine.detail(
                base: base,
                treadType: treadType,
                treadMaterial: treadMaterial,
                stringerSpacingInchesOC: spacing,
                species: species,
                grade: grade,
                package: package,
                stringerType: stringerType
            )
        }
    )
}

extension DeckingPattern {
    var editorTitle: String {
        switch self {
        case .parallel: return String(localized: "Straight")
        case .diagonal: return String(localized: "Diagonal")
        case .pictureFrame: return String(localized: "Picture frame")
        case .herringbone: return String(localized: "Herringbone")
        case .chevron: return String(localized: "Chevron")
        }
    }

    var editorSubtitle: String {
        switch self {
        case .parallel: return String(localized: "Fast install. Clean field runs.")
        case .diagonal: return String(localized: "Angled field boards. Higher waste.")
        case .pictureFrame: return String(localized: "Border courses define the edge.")
        case .herringbone: return String(localized: "Premium field layout.")
        case .chevron: return String(localized: "Directional premium layout.")
        }
    }

    var defaultBoardAngleDegrees: Double {
        switch self {
        case .parallel, .pictureFrame:
            return 0
        case .diagonal:
            return 45
        case .herringbone, .chevron:
            return 45
        }
    }

    var defaultPictureFrameCourses: Int {
        self == .pictureFrame ? 1 : 0
    }
}

extension FastenerSystem {
    var editorTitle: String {
        switch self {
        case .hiddenClip: return String(localized: "Hidden clip")
        case .faceScrew: return String(localized: "Face screw")
        }
    }
}

extension BuiltInKind {
    var editorTitle: String {
        switch self {
        case .bench: return String(localized: "Bench")
        case .planter: return String(localized: "Planter")
        case .privacyWall: return String(localized: "Privacy wall")
        }
    }

    var defaultHeightInches: Double {
        switch self {
        case .bench: return 18
        case .planter: return 24
        case .privacyWall: return 72
        }
    }
}

extension StairStringerStyle {
    var editorTitle: String {
        switch self {
        case .open: return String(localized: "Open")
        case .closed: return String(localized: "Closed")
        case .mono: return String(localized: "Mono")
        }
    }
}

extension StairStringerMaterial {
    var editorTitle: String {
        switch self {
        case .pressureTreatedWood: return String(localized: "PT wood")
        case .cedar: return String(localized: "Cedar")
        case .steel: return String(localized: "Steel")
        case .aluminum: return String(localized: "Aluminum")
        }
    }
}

extension StairTreadMaterial {
    var editorTitle: String {
        switch self {
        case .composite: return String(localized: "Composite")
        case .pressureTreatedWood: return String(localized: "PT wood")
        case .cedar: return String(localized: "Cedar")
        case .twoBySix: return String(localized: "2x6")
        case .fiveQuarterDecking: return String(localized: "5/4 decking")
        }
    }
}

extension OverheadKind {
    var editorTitle: String {
        switch self {
        case .pergola: return String(localized: "Pergola")
        case .louveredRoof: return String(localized: "Louvered roof")
        case .solidRoof: return String(localized: "Solid roof")
        }
    }
}

extension RoofShape {
    var editorTitle: String {
        switch self {
        case .shed: return String(localized: "Shed")
        case .gable: return String(localized: "Gable")
        case .hip: return String(localized: "Hip")
        }
    }
}

extension StairConfig {
    var editorTreadType: TreadType {
        stringerStyle == .closed ? .closedRiser : .openRiser
    }

    var editorStringerType: StairStringerType {
        if stringerMaterial == .steel || stringerStyle == .mono {
            return .steel
        }
        return stringerStyle == .closed ? .closedWood : .notchedWoodOpen
    }

    var editorStringerSpacingInchesOC: Double {
        let count = StairConfig.stringerCount(width: width)
        guard count > 1 else { return width }
        return width / Double(count - 1)
    }
}
