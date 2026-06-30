import Foundation

public enum DeckSchemaMigration {
    public static let currentSchemaVersion = 6
    public static let framingSchemaVersion = 2
    public static let houseSchemaVersion = 5
    public static let surfaceFeaturesSchemaVersion = 6

    public static func stampFramingVersion(_ data: DeckDrawingData) -> DeckDrawingData {
        var targetVersion = data.schemaVersion ?? 0
        if data.framing != nil {
            targetVersion = max(targetVersion, framingSchemaVersion)
        }
        if data.house != nil {
            targetVersion = max(targetVersion, houseSchemaVersion)
        }
        if data.surfaceFeatures != nil {
            targetVersion = max(targetVersion, surfaceFeaturesSchemaVersion)
        }
        guard targetVersion > (data.schemaVersion ?? 0) || data.framing != nil else { return data }

        var copy = data
        copy.schemaVersion = targetVersion
        copy.framing?.generatedAtSchemaVersion = targetVersion
        return copy
    }
}
