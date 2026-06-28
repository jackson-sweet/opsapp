import Foundation
import DeckKit
import XCTest
@testable import OPSDecks

@MainActor
final class OPSDecksSupabaseDeckLibraryClientTests: XCTestCase {
    func testProductionConfigurationUsesOPSProject() throws {
        let configuration = OPSDecksSupabaseConfiguration.production

        XCTAssertEqual(
            configuration.supabaseURL.absoluteString,
            "https://ijeekuhbatykdomumfjx.supabase.co"
        )
        XCTAssertFalse(configuration.supabaseKey.isEmpty)
    }

    func testListDecksDecodesRowsResilientlyAndFiltersCompanyScopeAndDeletes() async throws {
        let transport = RecordingDeckDesignRemoteTransport(
            listData: Data("""
            [
                {
                    "id": "deck-a",
                    "company_id": "company-a",
                    "project_id": null,
                    "title": "FIELD DECK",
                    "drawing_data": {},
                    "version": 1,
                    "created_by": null,
                    "created_at": "2026-06-27T20:00:00Z",
                    "updated_at": null,
                    "deleted_at": null
                },
                {
                    "id": "bad-row",
                    "company_id": "company-a",
                    "project_id": null,
                    "title": "BAD ROW",
                    "drawing_data": "not-jsonb",
                    "version": 1,
                    "created_by": null,
                    "created_at": "2026-06-27T20:00:00Z",
                    "updated_at": null,
                    "deleted_at": null
                },
                {
                    "id": "other-company",
                    "company_id": "company-b",
                    "project_id": null,
                    "title": "OTHER",
                    "drawing_data": {},
                    "version": 1,
                    "created_by": null,
                    "created_at": "2026-06-27T20:00:00Z",
                    "updated_at": null,
                    "deleted_at": null
                },
                {
                    "id": "deleted-deck",
                    "company_id": "company-a",
                    "project_id": null,
                    "title": "DELETED",
                    "drawing_data": {},
                    "version": 1,
                    "created_by": null,
                    "created_at": "2026-06-27T20:00:00Z",
                    "updated_at": null,
                    "deleted_at": "2026-06-27T21:00:00Z"
                }
            ]
            """.utf8)
        )
        let client = OPSDecksSupabaseDeckLibraryClient(transport: transport)

        let rows = try await client.listDecks(companyId: "company-a")

        XCTAssertEqual(transport.listedCompanyIds, ["company-a"])
        XCTAssertEqual(rows.map(\.id), ["deck-a"])
    }

    func testUpsertAndSoftDeleteDelegateToTransport() async throws {
        let transport = RecordingDeckDesignRemoteTransport()
        let client = OPSDecksSupabaseDeckLibraryClient(transport: transport)
        let row = OPSDecksDeckDesignRow(
            id: "deck-a",
            companyId: "company-a",
            projectId: nil,
            title: "FIELD DECK",
            drawingData: DeckDrawingData(),
            version: 1,
            createdBy: "user-a",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            deletedAt: nil
        )
        let deletedAt = Date(timeIntervalSince1970: 300)

        try await client.upsertDeck(row)
        try await client.softDeleteDeck(
            id: "deck-a",
            companyId: "company-a",
            deletedAt: deletedAt
        )

        XCTAssertEqual(transport.upsertedRows.map(\.id), ["deck-a"])
        XCTAssertEqual(transport.softDeletes.map(\.id), ["deck-a"])
        XCTAssertEqual(transport.softDeletes.first?.companyId, "company-a")
        XCTAssertEqual(transport.softDeletes.first?.deletedAt, deletedAt)
    }
}

private final class RecordingDeckDesignRemoteTransport: OPSDecksDeckDesignRemoteTransport {
    private let listData: Data
    private(set) var listedCompanyIds: [String] = []
    private(set) var upsertedRows: [OPSDecksDeckDesignRow] = []
    private(set) var softDeletes: [(id: String, companyId: String, deletedAt: Date)] = []

    init(listData: Data = Data("[]".utf8)) {
        self.listData = listData
    }

    func listDeckRows(companyId: String) async throws -> Data {
        listedCompanyIds.append(companyId)
        return listData
    }

    func upsertDeckRow(_ row: OPSDecksDeckDesignRow) async throws {
        upsertedRows.append(row)
    }

    func softDeleteDeckRow(id: String, companyId: String, deletedAt: Date) async throws {
        softDeletes.append((id: id, companyId: companyId, deletedAt: deletedAt))
    }
}
