import Foundation

public enum DeckSchemaMigration {
    public static let framingSchemaVersion = 2

    public static func stampFramingVersion(_ data: DeckDrawingData) -> DeckDrawingData {
        guard data.framing != nil else { return data }

        var copy = data
        let stampedVersion = max(copy.schemaVersion ?? 0, framingSchemaVersion)
        copy.schemaVersion = stampedVersion
        copy.framing?.generatedAtSchemaVersion = stampedVersion
        return copy
    }
}
