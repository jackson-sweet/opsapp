//
//  MarkupLayerTests.swift
//  OPSTests
//
//  Locks the wire contract for collaborative photo-markup layers: camelCase
//  jsonb keys (the upsert_markup_layer RPC reads `->> 'layerId'`), ISO-8601
//  dates, clearedAt OMITTED when nil (so the RPC's active check is correct),
//  resilient array decode (one bad element never nukes the row), and the
//  PhotoAnnotation typed accessors / peer-visibility helpers.
//

import XCTest
@testable import OPS

final class MarkupLayerTests: XCTestCase {

    private func makeLayer(
        id: String = "user-a",
        cleared: Bool = false,
        zIndex: Int = 0,
        overlay: String? = "https://s3/a.png"
    ) -> MarkupLayer {
        MarkupLayer(
            layerId: id,
            authorId: id,
            authorName: "Author \(id)",
            overlayUrl: overlay,
            strokeRef: "https://s3/a.pkdrawing",
            visibleDefault: true,
            zIndex: zIndex,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_500),
            clearedAt: cleared ? Date(timeIntervalSince1970: 1_750_001_000) : nil
        )
    }

    // MARK: - Wire contract

    func test_encode_usesCamelCaseKeys() throws {
        let data = try MarkupCoding.encoder.encode(makeLayer())
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"layerId\""))
        XCTAssertTrue(json.contains("\"overlayUrl\""))
        XCTAssertTrue(json.contains("\"visibleDefault\""))
        XCTAssertTrue(json.contains("\"zIndex\""))
        // snake_case must NOT appear — the RPC reads camelCase.
        XCTAssertFalse(json.contains("layer_id"))
        XCTAssertFalse(json.contains("overlay_url"))
    }

    func test_encode_omitsClearedAt_whenActive() throws {
        let active = try MarkupCoding.encoder.encode(makeLayer(cleared: false))
        XCTAssertFalse(String(data: active, encoding: .utf8)!.contains("clearedAt"),
                       "active layer must omit clearedAt so the RPC reads it as NULL")

        let cleared = try MarkupCoding.encoder.encode(makeLayer(cleared: true))
        XCTAssertTrue(String(data: cleared, encoding: .utf8)!.contains("clearedAt"))
    }

    func test_codable_roundTrips() throws {
        let original = makeLayer(cleared: true)
        let data = try MarkupCoding.encoder.encode(original)
        let restored = try MarkupCoding.decoder.decode(MarkupLayer.self, from: data)
        XCTAssertEqual(restored, original)
        XCTAssertTrue(restored.isCleared)
        XCTAssertFalse(restored.isActive)
    }

    func test_changeEvent_roundTrips() throws {
        let event = MarkupChangeEvent(
            eventId: "evt-1",
            authorId: "user-a",
            authorName: "Nick",
            action: .added,
            strokeDelta: 3,
            at: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let data = try MarkupCoding.encoder.encode(event)
        let restored = try MarkupCoding.decoder.decode(MarkupChangeEvent.self, from: data)
        XCTAssertEqual(restored, event)
        XCTAssertEqual(restored.action, .added)
    }

    // MARK: - Resilient decode

    func test_decodeArray_skipsMalformedElement() {
        // First element valid, second missing the required layerId.
        let json = """
        [
          {"layerId":"user-a","authorId":"user-a","authorName":"A","overlayUrl":"a.png","visibleDefault":true,"zIndex":0,"createdAt":"2025-06-15T12:00:00.000Z","updatedAt":"2025-06-15T12:00:00.000Z"},
          {"garbage":true}
        ]
        """
        let layers: [MarkupLayer] = MarkupCoding.decodeArray(Data(json.utf8))
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers.first?.layerId, "user-a")
    }

    func test_decodeArray_nilOrEmpty_returnsEmpty() {
        XCTAssertTrue((MarkupCoding.decodeArray(nil) as [MarkupLayer]).isEmpty)
        XCTAssertTrue((MarkupCoding.decodeArray(Data()) as [MarkupLayer]).isEmpty)
    }

    // MARK: - PhotoAnnotation accessors

    func test_layersAccessor_roundTrips() {
        let annotation = PhotoAnnotation(projectId: "p", companyId: "c", photoURL: "ph", authorId: "user-a")
        XCTAssertTrue(annotation.layers.isEmpty)
        annotation.layers = [makeLayer(id: "user-a"), makeLayer(id: "user-b", zIndex: 1)]
        XCTAssertEqual(annotation.layers.count, 2)
        XCTAssertNotNil(annotation.layersData)
        // Setting empty clears the backing data.
        annotation.layers = []
        XCTAssertNil(annotation.layersData)
    }

    func test_hiddenAuthorIds_isLocalRoundTrip() {
        let annotation = PhotoAnnotation(projectId: "p", companyId: "c", photoURL: "ph", authorId: "user-a")
        XCTAssertTrue(annotation.hiddenAuthorIds.isEmpty)
        annotation.hiddenAuthorIds = ["user-b"]
        XCTAssertEqual(annotation.hiddenAuthorIds, ["user-b"])
        annotation.hiddenAuthorIds = []
        XCTAssertNil(annotation.hiddenAuthorIdsData)
    }

    func test_visiblePeerLayers_excludesSelfClearedAndHidden_sortedByZ() {
        let annotation = PhotoAnnotation(projectId: "p", companyId: "c", photoURL: "ph", authorId: "me")
        annotation.layers = [
            makeLayer(id: "me", zIndex: 0),                         // self -> excluded
            makeLayer(id: "peerB", cleared: true, zIndex: 1),       // cleared -> excluded
            makeLayer(id: "peerC", zIndex: 3),                      // hidden -> excluded
            makeLayer(id: "peerA", zIndex: 2)                       // visible peer
        ]
        annotation.hiddenAuthorIds = ["peerC"]

        let peers = annotation.visiblePeerLayers(userId: "me")
        XCTAssertEqual(peers.map(\.layerId), ["peerA"])

        XCTAssertEqual(annotation.ownLayer(userId: "me")?.layerId, "me")
        // active authors = me + peerA + peerC (peerB cleared), regardless of hidden.
        XCTAssertEqual(Set(annotation.activeAuthorLayers().map(\.layerId)), ["me", "peerA", "peerC"])
    }

    // MARK: - DTO surfaces the new columns

    func test_dto_decodesLayers_intoModel() throws {
        let json = """
        {
          "id":"11111111-1111-1111-1111-111111111111",
          "project_id":"p","company_id":"c","photo_url":"ph",
          "rendered_photo_url":null,"annotation_url":"a.png","note":null,
          "author_id":"user-a","created_at":"2025-06-15T12:00:00Z","updated_at":null,"deleted_at":null,
          "dimensions":null,
          "layers":[{"layerId":"user-a","authorId":"user-a","authorName":"A","overlayUrl":"a.png","visibleDefault":true,"zIndex":0,"createdAt":"2025-06-15T12:00:00.000Z","updatedAt":"2025-06-15T12:00:00.000Z"}],
          "change_log":[{"eventId":"e1","authorId":"user-a","authorName":"A","action":"added","at":"2025-06-15T12:00:00.000Z"}],
          "before_snapshot_url":null,"after_snapshot_url":null
        }
        """
        let dto = try JSONDecoder().decode(PhotoAnnotationDTO.self, from: Data(json.utf8))
        let model = dto.toModel()
        XCTAssertEqual(model.layers.count, 1)
        XCTAssertEqual(model.layers.first?.authorName, "A")
        XCTAssertEqual(model.changeLog.count, 1)
        XCTAssertEqual(model.changeLog.first?.action, .added)
        XCTAssertNil(model.beforeSnapshotURL)
    }
}
