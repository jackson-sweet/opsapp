//
//  DataActor.swift
//  OPS
//
//  Long-lived @ModelActor that owns all background SwiftData writes.
//  Part of the C-pragmatic ModelActor refactor (Phase 1).
//
//  Design invariants:
//   - One instance per app lifetime, created in DataController.setModelContext.
//   - Uses its own ModelContext (created by @ModelActor macro) — NOT mainContext.
//   - All external callers use async methods; internal work uses
//     ModelContext.transaction { } for atomicity.
//   - Accepts PersistentIdentifier across the actor boundary, never @Model.
//
//  Migration note: the methods on this actor replace the previous
//  @MainActor InboundProcessor, OutboundProcessor, and DataController cleanup
//  implementations. Legacy paths remain behind FeatureFlags.useDataActor
//  until verified and removed.
//

import Foundation
import SwiftData

@ModelActor
actor DataActor {
    // MARK: - Configuration

    /// Called once after init to apply per-context configuration.
    /// Must be called before any transaction is run.
    func configure() {
        modelContext.autosaveEnabled = false
    }

    // MARK: - Context Accessor

    /// Exposes the actor's ModelContext to the main-actor refresh bridge
    /// for didSave subscription. DO NOT use for direct reads/writes from
    /// outside the actor — that would re-introduce the thread-safety bug
    /// this entire refactor is designed to eliminate.
    func context() -> ModelContext {
        modelContext
    }
}
