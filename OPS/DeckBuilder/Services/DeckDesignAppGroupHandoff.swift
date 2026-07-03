//
//  DeckDesignAppGroupHandoff.swift
//  OPS
//
//  Main OPS-side consumer for Deckset's local App Group deck handoff contract.
//  This keeps OPS on the light/view/import side of the boundary; the full
//  standalone designer remains in Deckset.
//

import Foundation
import SwiftData

enum DeckDesignHandoffSourceApp: String, Codable, Equatable {
    case deckset
    case ops
}

struct DeckDesignHandoffRecord: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let deckId: String
    let companyId: String
    let projectId: String?
    let title: String
    let drawingData: DeckDrawingData?
    let deckSchemaVersion: Int
    let sourceApp: DeckDesignHandoffSourceApp
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(
        formatVersion: Int = Self.currentFormatVersion,
        deckId: String,
        companyId: String,
        projectId: String?,
        title: String,
        drawingData: DeckDrawingData?,
        deckSchemaVersion: Int,
        sourceApp: DeckDesignHandoffSourceApp,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?
    ) {
        self.formatVersion = max(formatVersion, 1)
        self.deckId = deckId
        self.companyId = companyId
        self.projectId = projectId
        self.title = title
        self.drawingData = drawingData
        self.deckSchemaVersion = max(deckSchemaVersion, 1)
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    var effectiveUpdatedAt: Date {
        deletedAt ?? updatedAt
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case deckId = "deck_id"
        case companyId = "company_id"
        case projectId = "project_id"
        case title
        case drawingData = "drawing_data"
        case deckSchemaVersion = "deck_schema_version"
        case sourceApp = "source_app"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDrawingData = try container.decodeIfPresent(
            DeckDrawingData.self,
            forKey: .drawingData
        )
        self.init(
            formatVersion: try container.decodeIfPresent(Int.self, forKey: .formatVersion)
                ?? Self.currentFormatVersion,
            deckId: try container.decode(String.self, forKey: .deckId),
            companyId: try container.decode(String.self, forKey: .companyId),
            projectId: try container.decodeIfPresent(String.self, forKey: .projectId),
            title: try container.decode(String.self, forKey: .title),
            drawingData: decodedDrawingData,
            deckSchemaVersion: try container.decodeIfPresent(Int.self, forKey: .deckSchemaVersion)
                ?? 1,
            sourceApp: try container.decode(DeckDesignHandoffSourceApp.self, forKey: .sourceApp),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(deckId, forKey: .deckId)
        try container.encode(companyId, forKey: .companyId)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(drawingData, forKey: .drawingData)
        try container.encode(deckSchemaVersion, forKey: .deckSchemaVersion)
        try container.encode(sourceApp, forKey: .sourceApp)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

enum DeckDesignAppGroupHandoffStoreError: Error, Equatable {
    case appGroupContainerUnavailable(String)
    case recordNotFound(deckId: String, companyId: String)
}

final class DeckDesignAppGroupHandoffStore {
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        self.fileManager = fileManager
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    static func appGroup(
        identifier: String,
        fileManager: FileManager = .default
    ) throws -> DeckDesignAppGroupHandoffStore {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            throw DeckDesignAppGroupHandoffStoreError.appGroupContainerUnavailable(identifier)
        }
        return try DeckDesignAppGroupHandoffStore(
            directory: containerURL
                .appendingPathComponent("DeckDesignHandoff", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true),
            fileManager: fileManager
        )
    }

    func listDecks(includeDeleted: Bool = false) throws -> [DeckDesignHandoffRecord] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        var records: [DeckDesignHandoffRecord] = []
        for url in urls {
            guard let record = try? loadRecord(at: url) else { continue }
            if includeDeleted || !record.isDeleted {
                records.append(record)
            }
        }

        return records.sorted {
            if $0.effectiveUpdatedAt == $1.effectiveUpdatedAt {
                return $0.deckId < $1.deckId
            }
            return $0.effectiveUpdatedAt > $1.effectiveUpdatedAt
        }
    }

    func loadDeck(deckId: String, companyId: String) throws -> DeckDesignHandoffRecord {
        let url = fileURL(deckId: deckId, companyId: companyId)
        guard fileManager.fileExists(atPath: url.path) else {
            throw DeckDesignAppGroupHandoffStoreError.recordNotFound(
                deckId: deckId,
                companyId: companyId
            )
        }
        return try loadRecord(at: url)
    }

    func upsert(_ record: DeckDesignHandoffRecord) throws {
        let url = fileURL(deckId: record.deckId, companyId: record.companyId)
        if let existing = try? loadDeck(deckId: record.deckId, companyId: record.companyId),
           existing.effectiveUpdatedAt > record.effectiveUpdatedAt {
            return
        }
        let data = try DeckDesignHandoffRecord.encoder.encode(record)
        try data.write(to: url, options: .atomic)
    }

    private func loadRecord(at url: URL) throws -> DeckDesignHandoffRecord {
        let data = try Data(contentsOf: url)
        return try DeckDesignHandoffRecord.decoder.decode(
            DeckDesignHandoffRecord.self,
            from: data
        )
    }

    private func fileURL(deckId: String, companyId: String) -> URL {
        directory
            .appendingPathComponent(fileName(deckId: deckId, companyId: companyId))
            .appendingPathExtension("json")
    }

    private func fileName(deckId: String, companyId: String) -> String {
        let key = "\(companyId.utf8.count):\(companyId)|\(deckId.utf8.count):\(deckId)"
        return Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct DeckDesignAppGroupImportSummary: Equatable {
    var created = 0
    var updated = 0
    var deleted = 0
    var skippedCompanyMismatch = 0
    var skippedMissingDrawingData = 0
    var skippedOlderRecord = 0

    var changedCount: Int {
        created + updated + deleted
    }
}

struct DeckDesignAppGroupImporter {
    let store: DeckDesignAppGroupHandoffStore

    func importDecks(
        into context: ModelContext,
        companyId: String
    ) throws -> DeckDesignAppGroupImportSummary {
        let canonicalCompanyId = DeckDesign.canonicalUUIDString(companyId)
        var summary = DeckDesignAppGroupImportSummary()

        for record in try store.listDecks(includeDeleted: true) {
            guard DeckDesign.canonicalUUIDString(record.companyId) == canonicalCompanyId else {
                summary.skippedCompanyMismatch += 1
                continue
            }

            let canonicalDeckId = DeckDesign.canonicalUUIDString(record.deckId)
            let existing = try existingDeck(
                deckId: canonicalDeckId,
                companyId: canonicalCompanyId,
                context: context
            )

            if let existing,
               effectiveUpdatedAt(for: existing) > record.effectiveUpdatedAt {
                summary.skippedOlderRecord += 1
                continue
            }

            if record.isDeleted {
                guard let existing else { continue }
                existing.deletedAt = record.deletedAt
                existing.updatedAt = record.updatedAt
                existing.needsSync = record.sourceApp == .deckset
                summary.deleted += 1
                continue
            }

            guard let drawingData = record.drawingData else {
                summary.skippedMissingDrawingData += 1
                continue
            }

            if let existing {
                apply(record: record, drawingData: drawingData, to: existing)
                summary.updated += 1
            } else {
                context.insert(makeDeckDesign(from: record, drawingData: drawingData))
                summary.created += 1
            }
        }

        if summary.changedCount > 0 {
            try context.save()
        }
        return summary
    }

    private func existingDeck(
        deckId: String,
        companyId: String,
        context: ModelContext
    ) throws -> DeckDesign? {
        var descriptor = FetchDescriptor<DeckDesign>(
            predicate: #Predicate<DeckDesign> {
                $0.id == deckId && $0.companyId == companyId
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func makeDeckDesign(
        from record: DeckDesignHandoffRecord,
        drawingData: DeckDrawingData
    ) -> DeckDesign {
        let design = DeckDesign(
            id: record.deckId,
            companyId: record.companyId,
            projectId: record.projectId,
            title: record.title,
            drawingDataJSON: drawingData.toJSON()
        )
        design.createdAt = record.createdAt
        design.updatedAt = record.updatedAt
        design.deletedAt = nil
        design.needsSync = record.sourceApp == .deckset
        return design
    }

    private func apply(
        record: DeckDesignHandoffRecord,
        drawingData: DeckDrawingData,
        to design: DeckDesign
    ) {
        design.companyId = DeckDesign.canonicalUUIDString(record.companyId)
        design.projectId = record.projectId.map(DeckDesign.canonicalUUIDString)
        design.title = record.title
        design.drawingDataJSON = drawingData.toJSON()
        design.createdAt = min(design.createdAt, record.createdAt)
        design.updatedAt = record.updatedAt
        design.deletedAt = nil
        design.needsSync = record.sourceApp == .deckset
    }

    private func effectiveUpdatedAt(for design: DeckDesign) -> Date {
        design.deletedAt ?? design.updatedAt ?? design.createdAt
    }
}

@MainActor
extension DataController {
    @discardableResult
    func importDecksetHandoffIfPossible() async -> DeckDesignAppGroupImportSummary? {
        guard let modelContext,
              let companyId = currentUser?.companyId,
              !companyId.isEmpty else {
            return nil
        }

        do {
            let store = try DeckDesignAppGroupHandoffStore.appGroup(
                identifier: AppGroupConfig.identifier
            )
            let summary = try DeckDesignAppGroupImporter(store: store)
                .importDecks(into: modelContext, companyId: companyId)

            if summary.changedCount > 0, let syncEngine {
                await syncEngine.triggerSync()
            }
            return summary
        } catch DeckDesignAppGroupHandoffStoreError.appGroupContainerUnavailable {
            return nil
        } catch {
            print("[DECKSET_HANDOFF] Import failed: \(error)")
            return nil
        }
    }
}
