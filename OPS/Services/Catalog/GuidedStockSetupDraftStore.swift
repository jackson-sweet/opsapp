import Foundation

struct GuidedStockSetupDraftSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var context: CatalogSetupDraftContext
    var updatedAt: Date
    var stage: Int
    var capturedItems: [GuidedCapturedItem]
    var groups: [GuidedStructuredGroup]
    var committedGroupIds: [String]

    init(schemaVersion: Int = GuidedStockSetupDraftSnapshot.currentSchemaVersion,
         context: CatalogSetupDraftContext,
         updatedAt: Date = Date(),
         stage: Int,
         capturedItems: [GuidedCapturedItem],
         groups: [GuidedStructuredGroup],
         committedGroupIds: [String]) {
        self.schemaVersion = schemaVersion
        self.context = context
        self.updatedAt = updatedAt
        self.stage = stage
        self.capturedItems = capturedItems
        self.groups = groups
        self.committedGroupIds = committedGroupIds
    }
}

final class GuidedStockSetupDraftStore {
    static let shared = GuidedStockSetupDraftStore()

    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("GuidedStockSetupDrafts", isDirectory: true)
    }

    func save(_ snapshot: GuidedStockSetupDraftSnapshot) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL(for: snapshot.context), options: .atomic)
    }

    func load(context: CatalogSetupDraftContext) throws -> GuidedStockSetupDraftSnapshot? {
        let url = fileURL(for: context)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(GuidedStockSetupDraftSnapshot.self, from: data)
        guard snapshot.schemaVersion == GuidedStockSetupDraftSnapshot.currentSchemaVersion,
              snapshot.context == context else { return nil }
        return snapshot
    }

    func clear(context: CatalogSetupDraftContext) throws {
        let url = fileURL(for: context)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func fileURL(for context: CatalogSetupDraftContext) -> URL {
        var path = "\(safePathComponent(context.companyId))__\(safePathComponent(context.userId))"
        if let scope = context.scope?.trimmingCharacters(in: .whitespacesAndNewlines), !scope.isEmpty {
            path += "__\(safePathComponent(scope))"
        }
        return rootURL.appendingPathComponent("\(path).json", isDirectory: false)
    }

    private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let components = value.unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "_"
        }
        return components.joined()
    }
}
