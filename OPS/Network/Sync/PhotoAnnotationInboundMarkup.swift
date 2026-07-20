//
//  PhotoAnnotationInboundMarkup.swift
//  OPS
//
//  ONE shared inbound merge for collaborative markup, called by EVERY inbound
//  path — InboundProcessor (legacy), DataActor (active), RealtimeProcessor —
//  so the three cannot drift (the recurring dual/triple-path sync hazard). The
//  merge is per-layer recency union: a peer's newer server layer AND this
//  device's un-pushed local layer both survive, and a stale echo can't revert.
//

import Foundation

/// The collaborative-markup slice of a server annotation row, normalised so the
/// merge helper is agnostic to whether the source was a DTO or a converted model.
struct MarkupServerState {
    var layers: [MarkupLayer]
    var changeLog: [MarkupChangeEvent]
    var annotationURL: String?
    var deletedAt: Date?
    var beforeSnapshotURL: String?
    var afterSnapshotURL: String?
}

extension PhotoAnnotationDTO {
    var markupServerState: MarkupServerState {
        MarkupServerState(
            layers: layersModel,
            changeLog: changeLogModel,
            annotationURL: annotationUrl,
            deletedAt: deletedAt.flatMap { SupabaseDate.parse($0) },
            beforeSnapshotURL: beforeSnapshotUrl,
            afterSnapshotURL: afterSnapshotUrl
        )
    }
}

extension PhotoAnnotation {
    /// This row's markup slice (used when the inbound source is already a model,
    /// e.g. the RealtimeProcessor's `dto.toModel()`).
    var markupServerState: MarkupServerState {
        MarkupServerState(
            layers: layers,
            changeLog: changeLog,
            annotationURL: annotationURL,
            deletedAt: deletedAt,
            beforeSnapshotURL: beforeSnapshotURL,
            afterSnapshotURL: afterSnapshotURL
        )
    }

    /// Merge inbound markup state onto THIS local row.
    ///
    /// - Rows WITH layers derive `annotationURL` + `deletedAt` from the MERGED
    ///   layers (matching the upsert_markup_layer RPC), so display stays consistent
    ///   no matter which side won a given layer.
    /// - Layer-less (legacy/dimensioned) rows keep the field-guarded scalar paths.
    /// - `hiddenAuthorIds` is local-only and never touched here.
    ///
    /// - Returns: true when a LOCAL layer is still un-pushed (newer than the
    ///   server, or absent server-side) — the caller must keep `needsSync` set so
    ///   the offline sweep still owes the server that layer.
    ///
    /// `preserveLocalTombstone` carries the callers' PhotoAnnotationMergePolicy
    /// verdict (prod 2026-06-24, bugs 452bab04/0415504f): a not-yet-pushed local
    /// whole-row delete must never be resurrected by a live-row echo — neither
    /// via the legacy scalar path nor via the layer-derived deletedAt.
    @discardableResult
    func applyInboundMarkup(
        _ server: MarkupServerState,
        acceptLegacyAnnotationURL: Bool,
        acceptLegacyDeletedAt: Bool,
        preserveLocalTombstone: Bool = false
    ) -> Bool {
        let localLayers = layers
        let merged = MarkupLayerMerge.union(local: localLayers, server: server.layers)
        let unpushed = MarkupLayerMerge.localHasUnpushed(local: localLayers, server: server.layers)

        if merged.isEmpty {
            if acceptLegacyAnnotationURL { annotationURL = server.annotationURL }
            if acceptLegacyDeletedAt, !preserveLocalTombstone { deletedAt = server.deletedAt }
        } else {
            layers = merged
            changeLog = MarkupChangeLogMerge.union(local: changeLog, server: server.changeLog)
            annotationURL = MarkupLayerMerge.primaryOverlay(merged)
            if !preserveLocalTombstone {
                let anyActive = merged.contains { $0.isActive }
                deletedAt = (anyActive || dimensionsData != nil) ? nil : (server.deletedAt ?? Date())
            }
        }

        // Snapshot URLs are server-authoritative (written atomically by the RPC).
        beforeSnapshotURL = server.beforeSnapshotURL
        afterSnapshotURL = server.afterSnapshotURL
        return unpushed
    }
}
