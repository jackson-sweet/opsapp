//
//  MarkupLayerMerge.swift
//  OPS
//
//  Pure, unit-testable union merge for collaborative markup layers + change log.
//  Kept free of SwiftData/network so the recency rules are testable in isolation.
//
//  The server (upsert_markup_layer RPC) is authoritative, but the inbound sync
//  must NOT wholesale-replace local layers: that would drop this device's own
//  un-pushed (offline) layer, AND a stale replica-lagged echo could revert a
//  just-saved layer. The guard is PER-LAYER recency by updatedAt — the same
//  principle that fixed the deck stale-overwrite revert — not whole-field LWW.
//

import Foundation

enum MarkupLayerMerge {
    /// Merge by layerId. For a shared layerId keep the newer `updatedAt`
    /// (strict — server wins ties, since the RPC is authoritative). Local-only
    /// ids (un-pushed own layer) and server-only ids (a peer's layer) both
    /// survive. Result is ordered by zIndex then layerId for stable rendering.
    static func union(local: [MarkupLayer], server: [MarkupLayer]) -> [MarkupLayer] {
        var byId: [String: MarkupLayer] = [:]
        for layer in server { byId[layer.layerId] = layer }
        for layer in local {
            if let serverLayer = byId[layer.layerId] {
                if layer.updatedAt > serverLayer.updatedAt { byId[layer.layerId] = layer }
            } else {
                byId[layer.layerId] = layer
            }
        }
        return byId.values.sorted { (lhs: MarkupLayer, rhs: MarkupLayer) -> Bool in
            if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
            return lhs.layerId < rhs.layerId
        }
    }

    /// True when some LOCAL layer is ahead of the server (newer updatedAt, or a
    /// layerId the server doesn't have yet) — i.e. there is un-pushed local markup
    /// that the offline sweep still owes the server. Used to keep `needsSync` set
    /// through an inbound merge so the un-pushed layer is not silently dropped.
    static func localHasUnpushed(local: [MarkupLayer], server: [MarkupLayer]) -> Bool {
        let serverById = Dictionary(server.map { ($0.layerId, $0) }, uniquingKeysWith: { a, _ in a })
        return local.contains { layer in
            guard let serverLayer = serverById[layer.layerId] else { return true }
            return layer.updatedAt > serverLayer.updatedAt
        }
    }

    /// The legacy `annotation_url` scalar derived from the merged layers: the
    /// newest ACTIVE (non-cleared) layer's overlay, or nil when no active overlay.
    /// Mirrors the RPC so the feed `hasMarkup` signal stays consistent on both
    /// the server-write and inbound-merge paths.
    static func primaryOverlay(_ layers: [MarkupLayer]) -> String? {
        layers
            .filter { $0.isActive }
            .compactMap { layer -> (Date, String)? in
                guard let url = layer.overlayUrl, !url.isEmpty else { return nil }
                return (layer.updatedAt, url)
            }
            .max { $0.0 < $1.0 }?
            .1
    }

    /// True when the merged layer set leaves the row with no value to display:
    /// every layer cleared (drives the whole-row soft-delete, gated on dimensions
    /// by the caller). Mirrors the RPC's all-cleared check.
    static func allCleared(_ layers: [MarkupLayer]) -> Bool {
        !layers.isEmpty && layers.allSatisfy { $0.isCleared }
    }
}

enum MarkupChangeLogMerge {
    /// Union by eventId (append-only). Server wins on a shared eventId; local-only
    /// (un-pushed) events survive. Ordered oldest→newest by `at`.
    static func union(local: [MarkupChangeEvent], server: [MarkupChangeEvent]) -> [MarkupChangeEvent] {
        var byId: [String: MarkupChangeEvent] = [:]
        for event in local { byId[event.eventId] = event }
        for event in server { byId[event.eventId] = event }
        return byId.values.sorted { $0.at < $1.at }
    }
}
