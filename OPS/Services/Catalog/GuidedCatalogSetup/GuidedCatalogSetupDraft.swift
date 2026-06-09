//
//  GuidedCatalogSetupDraft.swift
//  OPS
//
//  Resume support for the Guided Catalog Setup flow. Mirrors
//  GuidedStockSetupDraftStore: a Codable snapshot persisted as JSON in the
//  Documents directory, keyed by CatalogSetupDraftContext with a dedicated
//  "catalog-guided" scope so it never collides with guided-stock drafts.
//

import Foundation

/// Which kind of standalone product line the product-line module is editing.
enum ProductLineKind: String, Codable, Equatable, CaseIterable, Identifiable {
    case service
    case good

    var id: String { rawValue }

    /// Maps to the 4-way product taxonomy used by ProductRepository.
    var productCategory: ProductCategory {
        switch self {
        case .service: return .service
        case .good:    return .material
        }
    }

    var displayLabel: String {
        switch self {
        case .service: return "SERVICE"
        case .good:    return "GOOD"
        }
    }
}

/// One in-progress service/good line in the product-line module.
struct ProductLineDraft: Codable, Equatable, Identifiable {
    var id: String
    var kind: ProductLineKind
    var name: String
    var sellText: String
    var costText: String
    var unitId: String?
    var categoryId: String?

    init(id: String = UUID().uuidString,
         kind: ProductLineKind,
         name: String = "",
         sellText: String = "",
         costText: String = "",
         unitId: String? = nil,
         categoryId: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.sellText = sellText
        self.costText = costText
        self.unitId = unitId
        self.categoryId = categoryId
    }
}

/// A product line committed to the catalog during this run (drives the done
/// summary and survives a quit-and-resume).
struct SavedProductLine: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var kind: ProductLineKind
    var sell: Double
}

/// An assembly (fixed-price package) committed this run.
struct SavedAssembly: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var sell: Double
    var marginPercent: Double?
}

/// Where the guide is. Codable so a quit mid-flow resumes at the same phase.
enum GuidedCatalogPhase: Codable, Equatable {
    case survey(questionIndex: Int)
    case plan
    case module(index: Int)
    case done
}

/// Persisted draft of an in-progress guided catalog setup.
struct GuidedCatalogSetupDraftSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var context: CatalogSetupDraftContext
    var updatedAt: Date
    var phase: GuidedCatalogPhase
    var profile: BusinessProfile?
    var productLines: [ProductLineDraft]
    var savedLines: [SavedProductLine]
    var savedAssemblies: [SavedAssembly]

    init(schemaVersion: Int = GuidedCatalogSetupDraftSnapshot.currentSchemaVersion,
         context: CatalogSetupDraftContext,
         updatedAt: Date = Date(),
         phase: GuidedCatalogPhase,
         profile: BusinessProfile?,
         productLines: [ProductLineDraft],
         savedLines: [SavedProductLine],
         savedAssemblies: [SavedAssembly] = []) {
        self.schemaVersion = schemaVersion
        self.context = context
        self.updatedAt = updatedAt
        self.phase = phase
        self.profile = profile
        self.productLines = productLines
        self.savedLines = savedLines
        self.savedAssemblies = savedAssemblies
    }
}

/// File-backed store for guided catalog setup drafts. Mirrors GuidedStockSetupDraftStore.
final class GuidedCatalogSetupDraftStore {
    static let shared = GuidedCatalogSetupDraftStore()

    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? fileManager
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("GuidedCatalogSetupDrafts", isDirectory: true)
    }

    func save(_ snapshot: GuidedCatalogSetupDraftSnapshot) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL(for: snapshot.context), options: .atomic)
    }

    func load(context: CatalogSetupDraftContext) throws -> GuidedCatalogSetupDraftSnapshot? {
        let url = fileURL(for: context)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(GuidedCatalogSetupDraftSnapshot.self, from: data)
        guard snapshot.schemaVersion == GuidedCatalogSetupDraftSnapshot.currentSchemaVersion,
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
