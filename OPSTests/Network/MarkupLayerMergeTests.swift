//
//  MarkupLayerMergeTests.swift
//  OPSTests
//
//  Locks the inbound collaborative-markup merge: per-layer recency union (a
//  peer's newer server layer AND this device's un-pushed local layer both
//  survive; a stale echo can't revert), un-pushed detection (keeps needsSync),
//  and derive-annotation_url/deletedAt-from-merged-layers (matches the RPC).
//

import XCTest
@testable import OPS

final class MarkupLayerMergeTests: XCTestCase {

    private func layer(
        _ id: String,
        updated: TimeInterval,
        cleared: Bool = false,
        z: Int = 0,
        overlay: String? = nil
    ) -> MarkupLayer {
        MarkupLayer(
            layerId: id,
            authorId: id,
            authorName: id,
            overlayUrl: overlay ?? "\(id).png",
            strokeRef: "\(id).pk",
            visibleDefault: true,
            zIndex: z,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: updated),
            clearedAt: cleared ? Date(timeIntervalSince1970: updated) : nil
        )
    }

    // MARK: - union

    func test_union_keepsPeerServerLayer_andLocalUnpushedLayer() {
        let local = [layer("me", updated: 200)]                    // un-pushed own layer
        let server = [layer("peer", updated: 100)]                 // a peer's layer
        let merged = MarkupLayerMerge.union(local: local, server: server)
        XCTAssertEqual(Set(merged.map(\.layerId)), ["me", "peer"])
    }

    func test_union_staleServerEcho_doesNotRevertNewerLocal() {
        let local = [layer("me", updated: 300, overlay: "v2.png")]   // just saved locally
        let server = [layer("me", updated: 200, overlay: "v1.png")]  // replica-lagged echo
        let merged = MarkupLayerMerge.union(local: local, server: server)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.overlayUrl, "v2.png", "newer local layer must win over a stale echo")
    }

    func test_union_newerServerWins() {
        let local = [layer("me", updated: 200, overlay: "v1.png")]
        let server = [layer("me", updated: 300, overlay: "v2.png")]
        let merged = MarkupLayerMerge.union(local: local, server: server)
        XCTAssertEqual(merged.first?.overlayUrl, "v2.png")
    }

    func test_union_sortsByZThenId() {
        let merged = MarkupLayerMerge.union(
            local: [],
            server: [layer("b", updated: 100, z: 2), layer("a", updated: 100, z: 1)]
        )
        XCTAssertEqual(merged.map(\.layerId), ["a", "b"])
    }

    // MARK: - localHasUnpushed

    func test_localHasUnpushed() {
        // local-only id -> un-pushed
        XCTAssertTrue(MarkupLayerMerge.localHasUnpushed(local: [layer("me", updated: 100)], server: []))
        // local newer than server -> un-pushed
        XCTAssertTrue(MarkupLayerMerge.localHasUnpushed(local: [layer("me", updated: 200)], server: [layer("me", updated: 100)]))
        // equal -> pushed (RPC preserves the client's updatedAt)
        XCTAssertFalse(MarkupLayerMerge.localHasUnpushed(local: [layer("me", updated: 100)], server: [layer("me", updated: 100)]))
        // older local -> not ahead
        XCTAssertFalse(MarkupLayerMerge.localHasUnpushed(local: [layer("me", updated: 100)], server: [layer("me", updated: 200)]))
    }

    // MARK: - primaryOverlay / allCleared

    func test_primaryOverlay_newestActiveOverlay() {
        let layers = [
            layer("a", updated: 100, overlay: "a.png"),
            layer("b", updated: 300, overlay: "b.png"),
            layer("c", updated: 400, cleared: true, overlay: "c.png")  // cleared -> ignored
        ]
        XCTAssertEqual(MarkupLayerMerge.primaryOverlay(layers), "b.png")
    }

    func test_primaryOverlay_nilWhenAllCleared() {
        let layers = [layer("a", updated: 100, cleared: true), layer("b", updated: 200, cleared: true)]
        XCTAssertNil(MarkupLayerMerge.primaryOverlay(layers))
        XCTAssertTrue(MarkupLayerMerge.allCleared(layers))
    }

    func test_allCleared_falseWhenEmptyOrAnyActive() {
        XCTAssertFalse(MarkupLayerMerge.allCleared([]))
        XCTAssertFalse(MarkupLayerMerge.allCleared([layer("a", updated: 100)]))
    }

    // MARK: - change log union

    func test_changeLogUnion_serverWins_sortedByTime() {
        let local = [
            MarkupChangeEvent(eventId: "e1", authorId: "a", authorName: "A", action: .added, at: Date(timeIntervalSince1970: 100)),
            MarkupChangeEvent(eventId: "e2", authorId: "a", authorName: "A", action: .edited, at: Date(timeIntervalSince1970: 300))
        ]
        let server = [
            MarkupChangeEvent(eventId: "e1", authorId: "a", authorName: "A-server", action: .added, at: Date(timeIntervalSince1970: 100)),
            MarkupChangeEvent(eventId: "e3", authorId: "b", authorName: "B", action: .added, at: Date(timeIntervalSince1970: 200))
        ]
        let merged = MarkupChangeLogMerge.union(local: local, server: server)
        XCTAssertEqual(merged.map(\.eventId), ["e1", "e3", "e2"])               // sorted by at
        XCTAssertEqual(merged.first?.authorName, "A-server")                    // server wins e1
    }

    // MARK: - applyInboundMarkup (the shared 3-path helper)

    func test_apply_mergesPeerAndDerivesAnnotationURL() {
        let annotation = PhotoAnnotation(projectId: "p", companyId: "c", photoURL: "ph", authorId: "me")
        annotation.layers = [layer("me", updated: 200, overlay: "me.png")]
        let server = MarkupServerState(
            layers: [layer("peer", updated: 300, overlay: "peer.png")],
            changeLog: [], annotationURL: "peer.png", deletedAt: nil,
            beforeSnapshotURL: nil, afterSnapshotURL: nil
        )
        let unpushed = annotation.applyInboundMarkup(server, acceptLegacyAnnotationURL: true, acceptLegacyDeletedAt: true)
        XCTAssertTrue(unpushed, "local 'me' layer is not on the server yet")
        XCTAssertEqual(Set(annotation.layers.map(\.layerId)), ["me", "peer"])
        XCTAssertEqual(annotation.annotationURL, "peer.png", "derived from newest active overlay")
        XCTAssertNil(annotation.deletedAt)
    }

    func test_apply_softDeletesWhenAllCleared_noDimensions() {
        let annotation = PhotoAnnotation(projectId: "p", companyId: "c", photoURL: "ph", authorId: "me")
        let server = MarkupServerState(
            layers: [layer("me", updated: 300, cleared: true)],
            changeLog: [], annotationURL: nil, deletedAt: Date(timeIntervalSince1970: 999),
            beforeSnapshotURL: nil, afterSnapshotURL: nil
        )
        _ = annotation.applyInboundMarkup(server, acceptLegacyAnnotationURL: true, acceptLegacyDeletedAt: true)
        XCTAssertNotNil(annotation.deletedAt, "all layers cleared + no dimensions -> soft-delete")
        XCTAssertNil(annotation.annotationURL)
    }

    func test_apply_keepsRowAlive_whenLocalActiveLayer_beatsServerDeleted() {
        // Server thinks all cleared (deleted), but THIS device has an un-pushed active layer.
        let annotation = PhotoAnnotation(projectId: "p", companyId: "c", photoURL: "ph", authorId: "me")
        annotation.layers = [layer("me", updated: 500, overlay: "me.png")]   // active, newer, un-pushed
        let server = MarkupServerState(
            layers: [layer("me", updated: 300, cleared: true)],
            changeLog: [], annotationURL: nil, deletedAt: Date(timeIntervalSince1970: 999),
            beforeSnapshotURL: nil, afterSnapshotURL: nil
        )
        let unpushed = annotation.applyInboundMarkup(server, acceptLegacyAnnotationURL: true, acceptLegacyDeletedAt: true)
        XCTAssertTrue(unpushed)
        XCTAssertNil(annotation.deletedAt, "a newer local active layer must keep the row visible")
        XCTAssertEqual(annotation.annotationURL, "me.png")
    }

    func test_apply_dimensionedRowNeverDeleted_evenWhenAllCleared() {
        let annotation = PhotoAnnotation(projectId: "p", companyId: "c", photoURL: "ph", authorId: "me")
        annotation.dimensionsData = Data("{}".utf8)   // dimensioned capture present
        let server = MarkupServerState(
            layers: [layer("me", updated: 300, cleared: true)],
            changeLog: [], annotationURL: nil, deletedAt: Date(timeIntervalSince1970: 999),
            beforeSnapshotURL: nil, afterSnapshotURL: nil
        )
        _ = annotation.applyInboundMarkup(server, acceptLegacyAnnotationURL: true, acceptLegacyDeletedAt: true)
        XCTAssertNil(annotation.deletedAt, "dimensioned rows are preserved even when every markup layer is cleared")
    }

    func test_apply_legacyRow_usesFieldGuardedScalars() {
        // No layers on either side -> behaves like the legacy single-overlay path.
        let annotation = PhotoAnnotation(projectId: "p", companyId: "c", photoURL: "ph", authorId: "me")
        annotation.annotationURL = "old.png"
        let server = MarkupServerState(
            layers: [], changeLog: [], annotationURL: "new.png", deletedAt: nil,
            beforeSnapshotURL: nil, afterSnapshotURL: nil
        )
        // Guard says NO -> keep local
        _ = annotation.applyInboundMarkup(server, acceptLegacyAnnotationURL: false, acceptLegacyDeletedAt: false)
        XCTAssertEqual(annotation.annotationURL, "old.png")
        // Guard says YES -> accept server
        _ = annotation.applyInboundMarkup(server, acceptLegacyAnnotationURL: true, acceptLegacyDeletedAt: true)
        XCTAssertEqual(annotation.annotationURL, "new.png")
    }
}
