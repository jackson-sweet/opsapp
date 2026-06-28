import Foundation
import Supabase

struct OPSDecksSupabaseConfiguration: Equatable {
    let supabaseURL: URL
    let supabaseKey: String

    static let production = OPSDecksSupabaseConfiguration(
        supabaseURL: URL(string: "https://ijeekuhbatykdomumfjx.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlqZWVrdWhiYXR5a2RvbXVtZmp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyNzM2MTgsImV4cCI6MjA4Njg0OTYxOH0.pXYn9WRpVkWSJg2vHw2fjw8RsAmytnRGwEjb2Jwrn-c"
    )
}

protocol OPSDecksDeckDesignRemoteTransport: AnyObject {
    func listDeckRows(companyId: String) async throws -> Data
    func upsertDeckRow(_ row: OPSDecksDeckDesignRow) async throws
    func softDeleteDeckRow(id: String, companyId: String, deletedAt: Date) async throws
}

final class OPSDecksSupabaseDeckLibraryClient: OPSDecksRemoteDeckLibraryClient {
    private let transport: OPSDecksDeckDesignRemoteTransport

    init(transport: OPSDecksDeckDesignRemoteTransport) {
        self.transport = transport
    }

    init(
        configuration: OPSDecksSupabaseConfiguration = .production,
        accessTokenProvider: @escaping @Sendable () async throws -> String
    ) {
        self.transport = OPSDecksSupabaseDeckDesignRemoteTransport(
            configuration: configuration,
            accessTokenProvider: accessTokenProvider
        )
    }

    func listDecks(companyId: String) async throws -> [OPSDecksDeckDesignRow] {
        let data = try await transport.listDeckRows(companyId: companyId)
        return Self.decodeResilient(data).filter {
            $0.companyId == companyId && $0.deletedAt == nil
        }
    }

    func upsertDeck(_ row: OPSDecksDeckDesignRow) async throws {
        try await transport.upsertDeckRow(row)
    }

    func softDeleteDeck(id: String, companyId: String, deletedAt: Date) async throws {
        try await transport.softDeleteDeckRow(
            id: id,
            companyId: companyId,
            deletedAt: deletedAt
        )
    }

    static func decodeResilient(_ data: Data) -> [OPSDecksDeckDesignRow] {
        let decoder = JSONDecoder()
        guard let elements = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            return (try? decoder.decode([OPSDecksDeckDesignRow].self, from: data)) ?? []
        }

        var decoded: [OPSDecksDeckDesignRow] = []
        decoded.reserveCapacity(elements.count)
        for element in elements {
            guard let rowData = try? JSONSerialization.data(withJSONObject: element) else {
                continue
            }
            guard let row = try? decoder.decode(OPSDecksDeckDesignRow.self, from: rowData) else {
                continue
            }
            decoded.append(row)
        }
        return decoded
    }
}

final class OPSDecksSupabaseDeckDesignRemoteTransport: OPSDecksDeckDesignRemoteTransport {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    convenience init(
        configuration: OPSDecksSupabaseConfiguration,
        accessTokenProvider: @escaping @Sendable () async throws -> String
    ) {
        self.init(
            client: SupabaseClient(
                supabaseURL: configuration.supabaseURL,
                supabaseKey: configuration.supabaseKey,
                options: SupabaseClientOptions(
                    auth: .init(accessToken: accessTokenProvider)
                )
            )
        )
    }

    func listDeckRows(companyId: String) async throws -> Data {
        try await client
            .from("deck_designs")
            .select()
            .eq("company_id", value: companyId)
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .data
    }

    func upsertDeckRow(_ row: OPSDecksDeckDesignRow) async throws {
        try await client
            .from("deck_designs")
            .upsert(row)
            .execute()
    }

    func softDeleteDeckRow(id: String, companyId: String, deletedAt: Date) async throws {
        let patch = OPSDecksDeckDesignSoftDeletePatch(
            deletedAt: deletedAt,
            updatedAt: deletedAt
        )
        try await client
            .from("deck_designs")
            .update(patch)
            .eq("id", value: id)
            .eq("company_id", value: companyId)
            .execute()
    }
}

struct OPSDecksDeckDesignSoftDeletePatch: Encodable, Equatable {
    let deletedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.encodeDate(deletedAt), forKey: .deletedAt)
        try container.encode(Self.encodeDate(updatedAt), forKey: .updatedAt)
    }

    private static func encodeDate(_ date: Date) -> String {
        opsDecksSupabaseISODateFormatter.string(from: date)
    }
}

private let opsDecksSupabaseISODateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
