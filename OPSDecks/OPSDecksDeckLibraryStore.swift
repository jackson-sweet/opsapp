import DeckKit
import Foundation

enum OPSDecksDeckLibraryStoreError: Error, Equatable {
    case documentNotFound(String)
    case documentBelongsToDifferentCompany(String)
    case invalidStorageDirectory
}

struct OPSDecksDeckDesignRow: Codable, Identifiable {
    let id: String
    let companyId: String
    let projectId: String?
    let title: String
    let drawingData: DeckDrawingData
    let version: Int
    let createdBy: String?
    let createdAt: Date
    let updatedAt: Date?
    var deletedAt: Date?

    init(
        id: String,
        companyId: String,
        projectId: String?,
        title: String,
        drawingData: DeckDrawingData,
        version: Int,
        createdBy: String?,
        createdAt: Date,
        updatedAt: Date?,
        deletedAt: Date?
    ) {
        self.id = id
        self.companyId = companyId
        self.projectId = projectId
        self.title = title
        self.drawingData = DeckSchemaMigration.stampFramingVersion(drawingData)
        self.version = max(version, 1)
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(document: OPSDecksDeckDocument, createdBy: String? = nil, deletedAt: Date? = nil) {
        let drawingData = DeckSchemaMigration.stampFramingVersion(document.drawingData)
        self.init(
            id: document.id,
            companyId: document.companyId,
            projectId: document.projectId,
            title: document.title,
            drawingData: drawingData,
            version: max(drawingData.schemaVersion ?? 1, 1),
            createdBy: createdBy,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            deletedAt: deletedAt
        )
    }

    var document: OPSDecksDeckDocument {
        OPSDecksDeckDocument(
            id: id,
            companyId: companyId,
            projectId: projectId,
            title: title,
            drawingData: drawingData,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case projectId = "project_id"
        case title
        case drawingData = "drawing_data"
        case version
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            companyId: try container.decode(String.self, forKey: .companyId),
            projectId: try container.decodeIfPresent(String.self, forKey: .projectId),
            title: try container.decode(String.self, forKey: .title),
            drawingData: try container.decode(DeckDrawingData.self, forKey: .drawingData),
            version: try container.decodeIfPresent(Int.self, forKey: .version) ?? 1,
            createdBy: try container.decodeIfPresent(String.self, forKey: .createdBy),
            createdAt: try Self.decodeDate(from: container, forKey: .createdAt),
            updatedAt: try Self.decodeOptionalDate(from: container, forKey: .updatedAt),
            deletedAt: try Self.decodeOptionalDate(from: container, forKey: .deletedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(companyId, forKey: .companyId)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encode(title, forKey: .title)
        try container.encode(drawingData, forKey: .drawingData)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
        try container.encode(Self.encodeDate(createdAt), forKey: .createdAt)
        try container.encodeIfPresent(updatedAt.map(Self.encodeDate), forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt.map(Self.encodeDate), forKey: .deletedAt)
    }

    private static func decodeDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date {
        if let value = try? container.decode(String.self, forKey: key) {
            guard let date = parseDate(value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "Expected ISO8601 timestamp."
                )
            }
            return date
        }
        return try container.decode(Date.self, forKey: key)
    }

    private static func decodeOptionalDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            guard let date = parseDate(value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: container,
                    debugDescription: "Expected ISO8601 timestamp."
                )
            }
            return date
        }
        return try container.decodeIfPresent(Date.self, forKey: key)
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = isoDateFormatter.date(from: value) {
            return date
        }
        return fractionalISODateFormatter.date(from: value)
    }

    private static func encodeDate(_ date: Date) -> String {
        isoDateFormatter.string(from: date)
    }
}

protocol OPSDecksRemoteDeckLibraryClient: AnyObject {
    func listDecks(companyId: String) async throws -> [OPSDecksDeckDesignRow]
    func upsertDeck(_ row: OPSDecksDeckDesignRow) async throws
    func softDeleteDeck(id: String, companyId: String, deletedAt: Date) async throws
}

protocol OPSDecksDeckLibraryStore: AnyObject {
    func listDecks() throws -> [OPSDecksDeckDocument]
    func loadDeck(id: String) throws -> OPSDecksDeckDocument
    func save(_ document: OPSDecksDeckDocument) throws
    func deleteDeck(id: String) throws
}

protocol OPSDecksRemoteSyncingDeckLibraryStore: OPSDecksDeckLibraryStore {
    func refreshFromRemote() async throws
    func saveAndSync(_ document: OPSDecksDeckDocument) async throws
    func deleteAndSync(id: String) async throws
}

final class OPSDecksInMemoryDeckLibraryStore: OPSDecksDeckLibraryStore {
    private(set) var documents: [OPSDecksDeckDocument]

    init(documents: [OPSDecksDeckDocument] = []) {
        self.documents = documents
    }

    convenience init(seedCount: Int, companyId: String) {
        let documents = (0..<max(seedCount, 0)).map { index in
            OPSDecksDeckDocument(
                id: "seed-deck-\(index)",
                companyId: companyId,
                title: OPSDecksCopy.defaultDeckTitle
            )
        }
        self.init(documents: documents)
    }

    func listDecks() throws -> [OPSDecksDeckDocument] {
        sorted(documents)
    }

    func loadDeck(id: String) throws -> OPSDecksDeckDocument {
        guard let document = documents.first(where: { $0.id == id }) else {
            throw OPSDecksDeckLibraryStoreError.documentNotFound(id)
        }
        return document
    }

    func save(_ document: OPSDecksDeckDocument) throws {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        } else {
            documents.append(document)
        }
    }

    func deleteDeck(id: String) throws {
        guard let index = documents.firstIndex(where: { $0.id == id }) else {
            throw OPSDecksDeckLibraryStoreError.documentNotFound(id)
        }
        documents.remove(at: index)
    }
}

final class OPSDecksUnavailableDeckLibraryStore: OPSDecksDeckLibraryStore {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func listDecks() throws -> [OPSDecksDeckDocument] {
        throw error
    }

    func loadDeck(id: String) throws -> OPSDecksDeckDocument {
        throw error
    }

    func save(_ document: OPSDecksDeckDocument) throws {
        throw error
    }

    func deleteDeck(id: String) throws {
        throw error
    }
}

final class OPSDecksFileDeckLibraryStore: OPSDecksDeckLibraryStore {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func appStore(fileManager: FileManager = .default) throws -> OPSDecksFileDeckLibraryStore {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw OPSDecksDeckLibraryStoreError.invalidStorageDirectory
        }
        return try OPSDecksFileDeckLibraryStore(
            directory: applicationSupport
                .appendingPathComponent("OPSDecks", isDirectory: true)
                .appendingPathComponent("Decks", isDirectory: true),
            fileManager: fileManager
        )
    }

    func listDecks() throws -> [OPSDecksDeckDocument] {
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        let documents = try fileURLs.map(loadDocument(at:))
        return sorted(documents)
    }

    func loadDeck(id: String) throws -> OPSDecksDeckDocument {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw OPSDecksDeckLibraryStoreError.documentNotFound(id)
        }
        return try loadDocument(at: url)
    }

    func save(_ document: OPSDecksDeckDocument) throws {
        let record = OPSDecksDeckRecord(document: document)
        let data = try encoder.encode(record)
        try data.write(to: fileURL(for: document.id), options: .atomic)
    }

    func deleteDeck(id: String) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw OPSDecksDeckLibraryStoreError.documentNotFound(id)
        }
        try fileManager.removeItem(at: url)
    }

    private func loadDocument(at url: URL) throws -> OPSDecksDeckDocument {
        let data = try Data(contentsOf: url)
        let record = try decoder.decode(OPSDecksDeckRecord.self, from: data)
        return record.document
    }

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent(sanitizedFileName(for: id)).appendingPathExtension("json")
    }

    private func sanitizedFileName(for id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = id.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let candidate = String(scalars)
        return candidate.isEmpty ? UUID().uuidString : candidate
    }
}

final class OPSDecksSyncingDeckLibraryStore: OPSDecksRemoteSyncingDeckLibraryStore {
    private let companyId: String
    private let cache: OPSDecksDeckLibraryStore
    private let remoteClient: OPSDecksRemoteDeckLibraryClient

    init(
        companyId: String,
        cache: OPSDecksDeckLibraryStore,
        remoteClient: OPSDecksRemoteDeckLibraryClient
    ) {
        self.companyId = companyId
        self.cache = cache
        self.remoteClient = remoteClient
    }

    func listDecks() throws -> [OPSDecksDeckDocument] {
        try cache.listDecks().filter { $0.companyId == companyId }
    }

    func loadDeck(id: String) throws -> OPSDecksDeckDocument {
        let document = try cache.loadDeck(id: id)
        guard document.companyId == companyId else {
            throw OPSDecksDeckLibraryStoreError.documentBelongsToDifferentCompany(id)
        }
        return document
    }

    func save(_ document: OPSDecksDeckDocument) throws {
        guard document.companyId == companyId else {
            throw OPSDecksDeckLibraryStoreError.documentBelongsToDifferentCompany(document.id)
        }
        try cache.save(document)
    }

    func deleteDeck(id: String) throws {
        let document = try loadDeck(id: id)
        try cache.deleteDeck(id: document.id)
    }

    func refreshFromRemote() async throws {
        let rows = try await remoteClient.listDecks(companyId: companyId)
        for row in rows where row.companyId == companyId && row.deletedAt == nil {
            try cache.save(row.document)
        }
    }

    func saveAndSync(_ document: OPSDecksDeckDocument) async throws {
        try save(document)
        try await remoteClient.upsertDeck(OPSDecksDeckDesignRow(document: document))
    }

    func deleteAndSync(id: String) async throws {
        let document = try loadDeck(id: id)
        try deleteDeck(id: id)
        try await remoteClient.softDeleteDeck(
            id: document.id,
            companyId: companyId,
            deletedAt: Date()
        )
    }
}

@MainActor
final class OPSDecksActiveDeckStore: DeckStore {
    private let documentId: String
    private let libraryStore: OPSDecksDeckLibraryStore

    init(documentId: String, libraryStore: OPSDecksDeckLibraryStore) {
        self.documentId = documentId
        self.libraryStore = libraryStore
    }

    func save(drawingData: DeckDrawingData) throws {
        var document = try libraryStore.loadDeck(id: documentId)
        document.updateDrawingData(drawingData)
        try libraryStore.save(document)
    }

    func delete() throws {
        try libraryStore.deleteDeck(id: documentId)
    }
}

private struct OPSDecksDeckRecord: Codable {
    let id: String
    let companyId: String
    let projectId: String?
    let title: String
    let drawingData: DeckDrawingData
    let createdAt: Date
    let updatedAt: Date

    init(document: OPSDecksDeckDocument) {
        self.id = document.id
        self.companyId = document.companyId
        self.projectId = document.projectId
        self.title = document.title
        self.drawingData = document.drawingData
        self.createdAt = document.createdAt
        self.updatedAt = document.updatedAt
    }

    var document: OPSDecksDeckDocument {
        OPSDecksDeckDocument(
            id: id,
            companyId: companyId,
            projectId: projectId,
            title: title,
            drawingData: drawingData,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private func sorted(_ documents: [OPSDecksDeckDocument]) -> [OPSDecksDeckDocument] {
    documents.sorted {
        if $0.updatedAt == $1.updatedAt {
            return $0.createdAt > $1.createdAt
        }
        return $0.updatedAt > $1.updatedAt
    }
}

private let isoDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private let fractionalISODateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
