import Foundation

struct OPSDecksAccountContext: Codable, Equatable {
    let firebaseUID: String
    let email: String
    let displayName: String?
    let companyId: String
    let userId: String
    let role: String
    let subscriptionPlan: String

    init(
        firebaseUID: String,
        email: String,
        displayName: String?,
        companyId: String,
        userId: String,
        role: String,
        subscriptionPlan: String
    ) {
        self.firebaseUID = firebaseUID
        self.email = email
        self.displayName = displayName
        self.companyId = companyId
        self.userId = userId
        self.role = role
        self.subscriptionPlan = subscriptionPlan
    }

    init(
        firebaseUID: String,
        email: String,
        displayName: String?,
        provisioningResponse: DecksCompanyProvisioningResponse
    ) {
        self.init(
            firebaseUID: firebaseUID,
            email: email,
            displayName: displayName,
            companyId: provisioningResponse.companyId,
            userId: provisioningResponse.userId,
            role: provisioningResponse.role,
            subscriptionPlan: provisioningResponse.subscriptionPlan
        )
    }

    enum CodingKeys: String, CodingKey {
        case firebaseUID = "firebase_uid"
        case email
        case displayName = "display_name"
        case companyId = "company_id"
        case userId = "user_id"
        case role
        case subscriptionPlan = "subscription_plan"
    }
}

protocol OPSDecksAccountContextStore: AnyObject {
    func loadAccountContext() throws -> OPSDecksAccountContext?
    func saveAccountContext(_ context: OPSDecksAccountContext) throws
    func clearAccountContext() throws
}

enum OPSDecksAccountContextStoreError: Error, Equatable {
    case invalidStorageDirectory
}

final class OPSDecksFileAccountContextStore: OPSDecksAccountContextStore {
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

    static func appStore(fileManager: FileManager = .default) throws -> OPSDecksFileAccountContextStore {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw OPSDecksAccountContextStoreError.invalidStorageDirectory
        }
        return try OPSDecksFileAccountContextStore(
            directory: applicationSupport
                .appendingPathComponent("OPSDecks", isDirectory: true)
                .appendingPathComponent("Account", isDirectory: true),
            fileManager: fileManager
        )
    }

    func loadAccountContext() throws -> OPSDecksAccountContext? {
        let url = accountContextURL
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(OPSDecksAccountContext.self, from: data)
    }

    func saveAccountContext(_ context: OPSDecksAccountContext) throws {
        let data = try encoder.encode(context)
        try data.write(to: accountContextURL, options: .atomic)
    }

    func clearAccountContext() throws {
        let url = accountContextURL
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private var accountContextURL: URL {
        directory.appendingPathComponent("account-context").appendingPathExtension("json")
    }
}

struct OPSDecksLibraryBootstrap {
    static let localCompanyId = "ops-decks-local-company"

    let companyId: String
    let libraryStore: OPSDecksDeckLibraryStore

    static func make(
        accountContext: OPSDecksAccountContext?,
        savedDeckCount: Int? = nil,
        localCompanyId: String = Self.localCompanyId,
        remoteClient: OPSDecksRemoteDeckLibraryClient? = nil,
        accessTokenProvider: (@Sendable () async throws -> String)? = nil,
        cacheStore: OPSDecksDeckLibraryStore? = nil,
        fileManager: FileManager = .default
    ) -> OPSDecksLibraryBootstrap {
        if let accountContext {
            let cache = cacheStore ?? fileDeckLibraryStore(fileManager: fileManager)
            guard let remoteClient = remoteClient ?? accessTokenProvider.map({
                OPSDecksSupabaseDeckLibraryClient(accessTokenProvider: $0)
            }) else {
                return OPSDecksLibraryBootstrap(
                    companyId: accountContext.companyId,
                    libraryStore: cache
                )
            }
            return OPSDecksLibraryBootstrap(
                companyId: accountContext.companyId,
                libraryStore: OPSDecksSyncingDeckLibraryStore(
                    companyId: accountContext.companyId,
                    cache: cache,
                    remoteClient: remoteClient
                )
            )
        }

        if let savedDeckCount {
            return OPSDecksLibraryBootstrap(
                companyId: localCompanyId,
                libraryStore: OPSDecksInMemoryDeckLibraryStore(
                    seedCount: savedDeckCount,
                    companyId: localCompanyId
                )
            )
        }

        return OPSDecksLibraryBootstrap(
            companyId: localCompanyId,
            libraryStore: fileDeckLibraryStore(fileManager: fileManager)
        )
    }

    private static func fileDeckLibraryStore(
        fileManager: FileManager
    ) -> OPSDecksDeckLibraryStore {
        do {
            return try OPSDecksFileDeckLibraryStore.appStore(fileManager: fileManager)
        } catch {
            return OPSDecksUnavailableDeckLibraryStore(error: error)
        }
    }
}
