//
//  DeckSaveTelemetry.swift
//  OPS
//
//  Reports a failed deck-design write instead of printing it.
//
//  Bug 9f4aeaf8. Before this, the only trace a deck save ever left when it
//  failed was `print("[DeckBuilder] Save failed: \(error)")` — which meant the
//  whole save-loss class was invisible in production and had to be diagnosed
//  from source rather than from data. A deck design is the input to estimates,
//  vinyl orders, materials lists and the client portal: a lost one is a
//  re-measured site visit, and we should not learn about it from a bug report
//  filed days later.
//
//  This is a thin adapter over `AutoBugReporter`, deliberately: that type
//  already owns the RPC, the server-side dedupe seed, the client-side TTL and
//  the "never throws, never blocks the caller" contract. The only thing added
//  here is a per-design, per-session gate, because `AutoBugReporter`'s dedupe
//  hash covers screen + file + error code but not which drawing was lost — and
//  one report per affected design is exactly the signal we want.
//

import Foundation

/// Failures the deck save path raises itself, as opposed to ones the store
/// hands back.
enum DeckSaveError: LocalizedError {
    /// The view model has no `ModelContext`, so there is nowhere to write.
    /// Unreachable from today's UI — every presentation site guards on the
    /// context — but the code path used to be an optional chain that reported
    /// success, so it is asserted in debug and reported in release rather than
    /// trusted to stay unreachable.
    case noModelContext

    var errorDescription: String? {
        switch self {
        case .noModelContext:
            return "The deck editor has no local store to write to."
        }
    }
}

@MainActor
enum DeckSaveTelemetry {

    private static let screen = "DeckBuilder.save"
    private static let suspectedFile = "DeckBuilderViewModel.swift"

    /// One report per design per app session. A save that fails usually keeps
    /// failing — the autosave tick alone would retry every two minutes — and a
    /// single row per affected drawing is the whole signal.
    private static var reportedDesignIds: Set<String> = []

    /// Files a deduped bug report for a deck write that did not land.
    ///
    /// Fire-and-forget by design: the reporting must never delay, block or
    /// change the outcome of the save path it observes.
    static func recordFailure(designId: String, error: Error, isPersisted: Bool) {
        // A test process must never write a production bug_reports row. Same
        // guard DataController uses to keep its auth probe out of XCTest.
        guard NSClassFromString("XCTestCase") == nil else { return }
        guard reportedDesignIds.insert(designId).inserted else { return }

        let code = Self.errorCode(for: error)
        let metadata: [String: Any] = [
            "design_id": designId,
            "error": String(describing: error),
            "free_disk_mb": Self.freeDiskMb(),
            "design_is_persisted": isPersisted
        ]

        Task {
            await AutoBugReporter.shared.report(
                screen: screen,
                suspectedFile: suspectedFile,
                errorCode: code,
                summary: "Deck design save failed — the drawing did not reach the local store.",
                metadata: metadata
            )
        }
    }

    /// Stable per-cause code so distinct failure shapes produce distinct rows
    /// while repeats of one shape collapse. NSError's domain + code is the
    /// stable identity for anything SwiftData or Core Data hands back.
    private static func errorCode(for error: Error) -> String {
        if let deckError = error as? DeckSaveError {
            switch deckError {
            case .noModelContext:
                return "DECK_SAVE_NO_STORE"
            }
        }
        let nsError = error as NSError
        return "DECK_SAVE_\(nsError.domain)_\(nsError.code)"
    }

    /// Free space in MB, or -1 when the volume cannot be read. A full disk is a
    /// leading explanation for a store write that throws, so it is worth
    /// carrying even though it is usually uninteresting.
    private static func freeDiskMb() -> Int {
        guard
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
            let freeBytes = attributes[.systemFreeSize] as? Int64
        else { return -1 }
        return Int(freeBytes / (1024 * 1024))
    }
}
