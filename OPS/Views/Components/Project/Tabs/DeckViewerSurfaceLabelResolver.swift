import Foundation

/// Resolves the read-only name drawn over one deck surface.
///
/// Persisted operator labels remain authoritative, followed by the first named
/// assigned material. Expanded viewers may supply a stable face ordinal for an
/// identity fallback; inline previews omit that ordinal and stay uncluttered.
enum DeckViewerSurfaceLabelResolver {

    static func resolve(
        userLabel: String?,
        assignedItems: [AssignedItem],
        fallbackOrdinal: Int?
    ) -> String? {
        if let userLabel = normalized(userLabel) {
            return userLabel
        }

        if let materialName = assignedItems.lazy.compactMap({ normalized($0.name) }).first {
            return materialName
        }

        guard let fallbackOrdinal, fallbackOrdinal > 0 else {
            return nil
        }
        return "Surface \(fallbackOrdinal)"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
