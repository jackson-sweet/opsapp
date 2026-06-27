import DeckKit
import Foundation

enum OPSDecksDeckLibraryStoreError: Error, Equatable {
    case documentNotFound(String)
    case documentBelongsToDifferentCompany(String)
    case invalidStorageDirectory
}

protocol OPSDecksDeckLibraryStore: AnyObject {
    func listDecks() throws -> [OPSDecksDeckDocument]
    func loadDeck(id: String) throws -> OPSDecksDeckDocument
    func save(_ document: OPSDecksDeckDocument) throws
    func deleteDeck(id: String) throws
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
