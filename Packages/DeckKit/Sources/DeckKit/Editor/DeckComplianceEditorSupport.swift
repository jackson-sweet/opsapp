import Foundation

enum DeckComplianceEditorEntryKind: Hashable {
    case complianceReport
    case asBuiltAudit
    case permitPlanSet
    case peStamp
    case opsDecksProUpsell
}

struct DeckComplianceEditorEntry: Equatable, Identifiable {
    let kind: DeckComplianceEditorEntryKind
    let title: String
    let subtitle: String
    let systemImage: String
    let isUpsell: Bool

    var id: DeckComplianceEditorEntryKind { kind }
}

enum DeckComplianceToolbarModel {
    static func entries(for capabilities: DeckCapabilities) -> [DeckComplianceEditorEntry] {
        var entries: [DeckComplianceEditorEntry] = []

        if capabilities.contains(.compliance) {
            entries.append(
                DeckComplianceEditorEntry(
                    kind: .complianceReport,
                    title: String(localized: "Code check"),
                    subtitle: String(localized: "Findings and citations"),
                    systemImage: "checklist",
                    isUpsell: false
                )
            )
            entries.append(
                DeckComplianceEditorEntry(
                    kind: .asBuiltAudit,
                    title: String(localized: "As-built"),
                    subtitle: String(localized: "Existing deck audit"),
                    systemImage: "scope",
                    isUpsell: false
                )
            )
        }

        if capabilities.contains(.permitPlanSet) {
            entries.append(
                DeckComplianceEditorEntry(
                    kind: .permitPlanSet,
                    title: String(localized: "Permit set"),
                    subtitle: String(localized: "Plan sheets and PDF"),
                    systemImage: "doc.richtext",
                    isUpsell: false
                )
            )
        }

        if capabilities.contains(.peStamp) {
            entries.append(
                DeckComplianceEditorEntry(
                    kind: .peStamp,
                    title: String(localized: "PE review"),
                    subtitle: String(localized: "Engineer request"),
                    systemImage: "signature",
                    isUpsell: false
                )
            )
        }

        guard entries.isEmpty else { return entries }
        return [
            DeckComplianceEditorEntry(
                kind: .opsDecksProUpsell,
                title: String(localized: "Available in OPS Decks Pro"),
                subtitle: String(localized: "Open the standalone app for permit tools"),
                systemImage: "lock",
                isUpsell: true
            ),
        ]
    }
}
