//
//  SiteVisitOwnCopyRepair.swift
//  OPS
//
//  A visit photo whose only pointer is a server address must still open on the
//  phone that took it. After an upload the artifact's local pointer becomes the
//  remote URL; if that address is unreadable (site-visits/ was never made
//  public-read — 2026-09-15) the tile goes blank even though the original
//  capture file is still on disk. This seeds the remote-URL cache from that
//  file, so the loader finds the bytes without the network.
//
//  `plan` is pure over two filesystem predicates so the rule is testable;
//  `seed` runs it against the real photo store and copies bytes off the main
//  thread.
//

import Foundation

enum SiteVisitOwnCopyRepair {
    struct Seed: Equatable {
        let localID: String
        let remoteURL: String
    }

    /// The remote-pointed artifacts whose own capture file is still on disk
    /// and whose remote-URL cache is empty, paired with the file to copy from.
    static func plan(
        artifacts: [SiteVisitCaptureArtifact],
        hasCache: (String) -> Bool,
        hasLocalFile: (String) -> Bool
    ) -> [Seed] {
        artifacts.compactMap { artifact in
            guard let remote = artifact.localAssetURL,
                  SiteVisitMediaSyncManager.isRemoteURL(remote),
                  !hasCache(remote),
                  let localID = ownCaptureCandidates(for: artifact.id).first(where: hasLocalFile)
            else { return nil }
            return Seed(localID: localID, remoteURL: remote)
        }
    }

    /// Every name this phone has ever used for an artifact's original bytes:
    /// the durable capture store (`capture_<id>.jpg`, lowercase id) and the
    /// older site-visit capture path (`site_visit_<id>.jpg`, id as stored).
    static func ownCaptureCandidates(for artifactId: String) -> [String] {
        var names: [String] = []
        for id in [artifactId.lowercased(), artifactId, artifactId.uppercased()] {
            for name in ["capture_\(id).jpg", "site_visit_\(id).jpg", "site_visit_\(id).heic"]
            where !names.contains(name) { names.append(name) }
        }
        return names.map { "local://project_images/\($0)" }
    }

    /// Repairs `artifacts` against the live photo store. File-existence checks
    /// run inline (a stat each); byte copies run in the background and the
    /// tiles refresh through `ImageFileManager`'s thumbnail-change notice.
    static func seed(_ artifacts: [SiteVisitCaptureArtifact]) {
        let store = ImageFileManager.shared
        let seeds = plan(
            artifacts: artifacts,
            hasCache: { store.imageExists(localID: $0) },
            hasLocalFile: { store.imageExists(localID: $0) }
        )
        guard !seeds.isEmpty else { return }
        Task.detached(priority: .utility) {
            for seed in seeds {
                guard let file = store.getFileURL(for: seed.localID),
                      let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { continue }
                _ = store.saveImage(data: data, localID: seed.remoteURL, allowEviction: false)
            }
        }
    }
}
