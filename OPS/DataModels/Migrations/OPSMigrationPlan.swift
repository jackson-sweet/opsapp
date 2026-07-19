//
//  OPSMigrationPlan.swift
//  OPS
//
//  Declares the ordered sequence of SwiftData schema migrations that can
//  bring any previously-shipped OPS store forward to the current schema.
//
//  V1 → V2 stage: `WizardState` gains a mandatory `id` primary key used by
//  the Supabase sync layer. SwiftData's automatic schema transform refuses
//  to add a non-optional column to existing rows because there is no value
//  to populate — that's the NSCocoaErrorDomain 134110 the previous attempt
//  hit. `MigrationStage.custom` does NOT bypass this validation: `didMigrate`
//  only runs *after* the schema transform succeeds.
//
//  We fix it by clearing legacy WizardState rows in `willMigrate` (V1
//  context), so the schema transform runs against an empty table. Wizard
//  state is tutorial-progress only and is re-hydrated on next launch by
//  `InboundProcessor.syncWizardStates`, with `WizardStateManager` lazily
//  creating fresh `not_started` rows for any wizard the server has no record
//  of. The `didMigrate` UUID backfill is kept as defense-in-depth in case a
//  row somehow lands in V2 with an empty id.
//
//  V2 → V3 stage: drops the legacy `Inventory*` entities and registers the
//  new `catalog_*` / `product_*` extension entities. The schema diff itself
//  performs the destructive work (SwiftData removes records of entity types
//  absent from the new schema), so `willMigrate` has nothing to do. We set
//  `needs_full_catalog_sync` in `didMigrate` so InboundProcessor pulls a
//  fresh full catalog on next launch.
//
//  V3 → V4 stage: lightweight additive — TaskTypeReminder + TaskReminder.
//
//  V4 → V5 stage: lightweight additive — CalendarMirrorMap for the iPhone
//  Calendar Mirror feature. Originally landed as V3 on the calendar-mirror
//  branch; renumbered to V5 during the catalog-variant-model merge.
//
//  V5 → V6 stage: lightweight additive — PaymentMilestone (iOS parity for
//  the existing server table) and RecurringExpense (new) for the Cashflow
//  Forecast feature. Spec at docs/superpowers/specs/2026-05-11-cashflow-forecast-design.md.
//
//  V6 → V7 stage: lightweight additive — ProjectVinylOrderMarker, a local
//  projection of the project-level vinyl order marker fields.
//
//  V7 → V8 stage: lightweight additive — catalog stock units and
//  catalog-product option mappings for Phase 4 Catalog Setup.
//
//  V8 → V9 stage: lightweight additive — `ProjectPhoto`, the synced
//  `project_photos` gallery store, so every assigned teammate sees the full
//  gallery instead of only the uploader's optimistic local append.
//
//  V9 → V10 stage: lightweight additive — `CatalogStockUnitEvent`, the local
//  mirror of the append-only `catalog_stock_unit_events` ledger that records
//  offcut provenance for the vinyl deck-builder cut path.
//
//  V10 → V11 stage: lightweight additive — site-visit capture artifacts,
//  visit types, and checklist answer snapshots for rapid pre-project photos,
//  notes, measurements, LiDAR dimensioned captures, custom questions, and
//  CanPro deck-design references. This stage ALSO relaxes the existing
//  `SiteVisit.opportunityId` from a required `String` to an optional `String?`
//  so a visit can start before a lead is selected. Relaxing a required attribute
//  to optional is an inferable lightweight transform. V1–V10 keep the frozen
//  required shape (`OPSSchemaCommon.v1ToV10SiteVisitModel`); V11+ use the live
//  optional shape (`OPSSchemaCommon.v11SiteVisitModel`), so the change is
//  confined to this single boundary instead of silently rewriting every
//  historical schema's `SiteVisit` hash.
//
//  V11 → V12 stage: lightweight additive — site-visit identity draft rows for
//  client/lead contact capture inside the visit console.
//
//  V12 → V13 stage: lightweight additive — `ProjectNote` gains two optional
//  attributes (`eventKind`, `contentMetadataJSON`) mirroring the live
//  `project_notes.event_kind` / `content_metadata` columns so system entries
//  (status changes, site-visit packets) render as first-class feed cards. Like
//  SiteVisit at V10→V11 and Activity at V13→V14, `ProjectNote` is version-scoped
//  here: the frozen `OPSSchemaLegacyProjectNote.ProjectNote` (no system-event
//  columns) backs V1–V12, the live `ProjectNote` backs V13+. Adding the columns
//  in place would leave V12 and V13 byte-identical and abort plan construction
//  with "Duplicate version checksums across stages"; the frozen split gives the
//  stage a real fingerprint delta.
//
//  V13 → V14 stage: unified activity parents. Widens `Activity` so a timeline
//  activity can attach to a lead (opportunity), a client, OR a job (project),
//  and carry an author. `opportunityId` relaxes from required `String` to
//  optional `String?` and two nullable columns (`clientId`, `projectId`) are
//  added. Required→optional plus new optionals is an inferable lightweight
//  transform. Like SiteVisit at V10→V11, `Activity` is version-scoped: the
//  frozen `OPSSchemaLegacyActivity.Activity` (required opportunityId, no
//  client/project) backs V1–V13; the live `Activity` backs V14+. This confines
//  the change to this single boundary instead of silently rewriting every
//  historical schema's `Activity` hash (the hazard documented in OPSApp.swift).
//
//  V14 → V15 stage: site-visit → timeline auto-post idempotency. Adds a single
//  nullable `SiteVisit.loggedActivityId` so a completed visit that posts its
//  "Site visit" activity records the returned id and never double-posts on
//  re-completion. A new optional column is an inferable lightweight transform.
//  Like SiteVisit at V10→V11 and Activity at V13→V14, `SiteVisit` is
//  version-scoped: the frozen `OPSSchemaLegacySiteVisitV11.SiteVisit` (optional
//  opportunityId, no loggedActivityId) backs V11–V14; the live `SiteVisit`
//  (+ loggedActivityId) backs V15+. This confines the change to this single
//  boundary instead of rewriting every V11–V14 schema's `SiteVisit` hash.
//
//  V15 → V16 stage: app-update compatibility. Opportunity gains optional
//  coordinates plus its images array, and DeckDesign gains nullable
//  `opportunityId`. Both models are frozen through V15 and switch to their live
//  shapes at V16 so released fingerprints remain stable.
//
//  V16 → V17 stage: vinyl order marker gains nullable color + PO fields for
//  the VINYL ORDERS board.
//
//  V17 → V18 stage: guarded lead assignment concurrency + chase columns. Adds
//  the required, defaulted Int64 `Opportunity.assignmentVersion` snapshot and
//  three optional chase/summary fields (`handledAt`, `aiSummary`,
//  `aiSummaryUpdatedAt`). Opportunity is version-scoped at this boundary —
//  the frozen `OPSSchemaLegacyOpportunityV17.Opportunity` (images +
//  coordinates, no assignment/chase) backs V16–V17; the live model backs
//  V18+ — so only this boundary widens the fingerprint.
//

import Foundation
import SwiftData

enum OPSMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            OPSSchemaV1.self,
            OPSSchemaV2.self,
            OPSSchemaV3.self,
            OPSSchemaV4.self,
            OPSSchemaV5.self,
            OPSSchemaV6.self,
            OPSSchemaV7.self,
            OPSSchemaV8.self,
            OPSSchemaV9.self,
            OPSSchemaV10.self,
            OPSSchemaV11.self,
            OPSSchemaV12.self,
            OPSSchemaV13.self,
            OPSSchemaV14.self,
            OPSSchemaV15.self,
            OPSSchemaV16.self,
            OPSSchemaV17.self,
            OPSSchemaV18.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            migrateWizardStateIdV1toV2,
            migrateInventoryToCatalogV2toV3,
            migrateAddTaskRemindersV3toV4,
            addCalendarMirrorMapV4toV5,
            addForecastModelsV5toV6,
            addVinylOrderMarkerV6toV7,
            addCatalogSetupModelsV7toV8,
            addProjectPhotosV8toV9,
            addStockUnitEventsV9toV10,
            addSiteVisitCaptureArtifactsV10toV11,
            addSiteVisitIdentityDraftsV11toV12,
            addProjectNoteEventKindV12toV13,
            addUnifiedActivityParentsV13toV14,
            addSiteVisitActivityLinkV14toV15,
            addOpportunityMediaAndDeckLeadV15toV16,
            addVinylOrderColorPOV16toV17,
            addOpportunityAssignmentAndChaseV17toV18
        ]
    }

    /// V17 → V18: additive guarded-assignment snapshot + chase columns.
    /// Existing leads receive `assignmentVersion = 0` (required, defaulted);
    /// `handledAt` / `aiSummary` / `aiSummaryUpdatedAt` are new optionals
    /// defaulting to nil. Opportunity is version-scoped at this boundary
    /// (frozen `OPSSchemaLegacyOpportunityV17` for V16–V17, live for V18+)
    /// so released fingerprints stay exact.
    static let addOpportunityAssignmentAndChaseV17toV18 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV17.self,
        toVersion: OPSSchemaV18.self
    )

    /// V16 → V17: purely additive — `ProjectVinylOrderMarker` gains nullable
    /// `vinylColor` / `vinylPO`, projections of the additive
    /// `projects.vinyl_color` / `vinyl_po` columns (VINYL ORDERS board). The
    /// frozen V16 marker shape (`OPSSchemaLegacyVinylOrderV16`) preserves
    /// released fingerprints; lightweight migration defaults both columns to
    /// nil for historical rows.
    static let addVinylOrderColorPOV16toV17 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV16.self,
        toVersion: OPSSchemaV17.self
    )

    /// V15 → V16: fields that landed after V15 shipped. Opportunity adds an
    /// images array plus nullable latitude/longitude; DeckDesign adds nullable
    /// `opportunityId`. Frozen V15 model shapes preserve recognition of stores
    /// created by released binaries, while the additive/defaulted live shapes
    /// are inferable as a lightweight transform.
    static let addOpportunityMediaAndDeckLeadV15toV16 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV15.self,
        toVersion: OPSSchemaV16.self
    )

    /// V14 → V15: site-visit → timeline auto-post idempotency. Adds a single
    /// nullable `SiteVisit.loggedActivityId` so a completed visit that posts its
    /// "Site visit" activity can record the returned id and never double-post on
    /// re-completion. A new optional column is an inferable lightweight
    /// transform; the column defaults to nil for historical rows. `SiteVisit` is
    /// version-scoped at this boundary (frozen `OPSSchemaLegacySiteVisitV11`
    /// for V11–V14, live `SiteVisit` for V15+) so the widening does not rewrite
    /// every V11–V14 schema's `SiteVisit` fingerprint.
    ///
    /// This boundary ALSO introduces `PhotoAnnotation`'s two retry-hygiene columns
    /// (`syncFailureCount`, `syncParkedAt`), which were added to the live model
    /// in-place after V10 shipped. `PhotoAnnotation` is version-scoped here too
    /// (frozen `OPSSchemaLegacyPhotoAnnotation` for V1–V14, live for V15+) so V10's
    /// shipped fingerprint is preserved; both additions ride this single lightweight
    /// stage (new optional/defaulted columns, additive only).
    static let addSiteVisitActivityLinkV14toV15 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV14.self,
        toVersion: OPSSchemaV15.self
    )

    /// V13 → V14: unified activity parents. `Activity.opportunityId` relaxes
    /// from required `String` to optional `String?` and gains nullable
    /// `clientId` / `projectId` so an activity can attach to a lead, a client,
    /// OR a job. Required→optional plus new optionals is an inferable lightweight
    /// transform; existing non-null `opportunityId` values are preserved and the
    /// new columns default to nil for historical rows. `Activity` is
    /// version-scoped at this boundary (frozen `OPSSchemaLegacyActivity.Activity`
    /// for V1–V13, live `Activity` for V14+) so the widening does not rewrite
    /// every historical schema's `Activity` fingerprint.
    static let addUnifiedActivityParentsV13toV14 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV13.self,
        toVersion: OPSSchemaV14.self
    )

    /// V12 → V13: purely additive — `ProjectNote` gains optional `eventKind` +
    /// `contentMetadataJSON` attributes (live `project_notes` columns). Adding
    /// optional attributes is an inferable lightweight transform. `ProjectNote`
    /// is version-scoped at this boundary (frozen `OPSSchemaLegacyProjectNote`
    /// for V1–V12, live `ProjectNote` for V13+) so V12 and V13 have distinct
    /// fingerprints — an in-place widening leaves them identical and SwiftData
    /// aborts the plan with "Duplicate version checksums across stages".
    static let addProjectNoteEventKindV12toV13 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV12.self,
        toVersion: OPSSchemaV13.self
    )

    /// V11 → V12: purely additive — identity drafts are local-first rows keyed
    /// to a site visit. They preserve contact/client info before the lead is
    /// selected or created.
    static let addSiteVisitIdentityDraftsV11toV12 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV11.self,
        toVersion: OPSSchemaV12.self
    )

    /// V10 → V11: additive site-visit capture/checklist models (brand-new
    /// @Models, no pre-existing rows) PLUS one inferable relaxation: the frozen
    /// `SiteVisit.opportunityId` (required, V1–V10) becomes optional (V11+) so a
    /// visit can begin before a lead exists. Required→optional is a lightweight
    /// transform; existing non-null `opportunityId` values are preserved.
    static let addSiteVisitCaptureArtifactsV10toV11 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV10.self,
        toVersion: OPSSchemaV11.self
    )

    /// V9 → V10: purely additive — `CatalogStockUnitEvent` is a brand-new @Model
    /// backing the local mirror of `catalog_stock_unit_events`. No pre-existing
    /// rows to transform; SwiftData lightweight migration handles the V9 store.
    static let addStockUnitEventsV9toV10 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV9.self,
        toVersion: OPSSchemaV10.self
    )

    /// V8 → V9: purely additive — `ProjectPhoto` is a brand-new @Model backing
    /// the synced `project_photos` gallery store. No pre-existing rows to
    /// transform; SwiftData lightweight migration handles the V8 store.
    static let addProjectPhotosV8toV9 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV8.self,
        toVersion: OPSSchemaV9.self
    )

    /// V7 → V8: purely additive — stock units and product-option mappings are
    /// new local projections of existing live catalog setup tables.
    static let addCatalogSetupModelsV7toV8 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV7.self,
        toVersion: OPSSchemaV8.self
    )

    /// V6 → V7: purely additive — `ProjectVinylOrderMarker` is a local
    /// projection of server columns on `projects`, with no rows to transform
    /// before the next project sync hydrates it.
    static let addVinylOrderMarkerV6toV7 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV6.self,
        toVersion: OPSSchemaV7.self
    )

    /// V5 → V6: purely additive — `PaymentMilestone` and `RecurringExpense` are
    /// new models with no pre-existing rows to transform. SwiftData lightweight
    /// migration handles the schema diff transparently.
    static let addForecastModelsV5toV6 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV5.self,
        toVersion: OPSSchemaV6.self
    )

    /// V4 → V5: purely additive — `CalendarMirrorMap` is a brand-new model
    /// with no pre-existing rows to transform. SwiftData lightweight migration
    /// handles it.
    static let addCalendarMirrorMapV4toV5 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV4.self,
        toVersion: OPSSchemaV5.self
    )

    /// V3 → V4 adds the TaskTypeReminder and TaskReminder entities plus inverse
    /// `reminderTemplates` / `reminders` arrays on TaskType and ProjectTask.
    /// Purely additive — no destructive transforms — so SwiftData lightweight
    /// migration handles the schema diff transparently.
    static let migrateAddTaskRemindersV3toV4 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV3.self,
        toVersion: OPSSchemaV4.self
    )

    /// V2 → V3 drops the legacy Inventory* entities and registers the new
    /// catalog_* / product_* extension entities, then flags InboundProcessor
    /// to pull a fresh full catalog sync on next launch.
    static let migrateInventoryToCatalogV2toV3 = MigrationStage.custom(
        fromVersion: OPSSchemaV2.self,
        toVersion: OPSSchemaV3.self,
        willMigrate: { _ in
            // Intentionally empty. SwiftData drops entity types absent from the new
            // schema during the schema transform itself; nothing for us to do here.
            // The new catalog/product-extension entities will be empty until the
            // next inbound sync runs.
        },
        didMigrate: { _ in
            // Force a fresh full-sync flag so InboundProcessor pulls all
            // catalog data on next launch.
            UserDefaults.standard.set(true, forKey: "needs_full_catalog_sync")
        }
    )

    /// Bridges the pre-`id` WizardState shape into the V2 schema by dropping
    /// every legacy row before the schema transform runs, then defensively
    /// stamping any survivor that lands in V2 without an id.
    static let migrateWizardStateIdV1toV2 = MigrationStage.custom(
        fromVersion: OPSSchemaV1.self,
        toVersion: OPSSchemaV2.self,
        willMigrate: { context in
            // V1 context — fetch the nested legacy type, not the top-level
            // V2 `WizardState`. The legacy rows lack the mandatory `id`
            // column added in V2, so there is no value SwiftData can use to
            // satisfy the transform; deleting them is the only safe path.
            let descriptor = FetchDescriptor<OPSSchemaV1.WizardState>()
            let legacy = try context.fetch(descriptor)
            for state in legacy {
                context.delete(state)
            }
            try context.save()
        },
        didMigrate: { context in
            // Defensive: if any row reaches V2 with an empty id (shouldn't
            // happen given the willMigrate sweep), assign a fresh UUID and
            // mark the row for re-sync so the server learns about it.
            let descriptor = FetchDescriptor<WizardState>()
            let states = try context.fetch(descriptor)
            for state in states where state.id.isEmpty {
                state.id = UUID().uuidString
                state.needsSync = true
            }
            try context.save()
        }
    )
}
