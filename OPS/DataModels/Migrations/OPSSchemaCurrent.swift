//
//  OPSSchemaCurrent.swift
//  OPS
//
//  The single declaration of the schema head. Every surface that means "the
//  current schema" — the app container, DEBUG QA hosts, and current-schema
//  tests — resolves it through this alias instead of naming a version literal.
//
//  When a new VersionedSchema lands, repoint this alias in the same commit
//  that appends the version to `OPSMigrationPlan`, then run
//  `AppUpdateMigrationTests` and `SiteVisitMigrationTests`. Call sites that
//  name an explicit `OPSSchemaV<N>` mean that historical version deliberately
//  (frozen-store fixtures, stage-isolation migration tests) and must NOT use
//  this alias.
//
//  Why this exists: a call site that hard-codes the head keeps compiling when
//  the head moves, but the frozen/live model registrations behind it shift —
//  inserting or fetching a live `@Model` against a stale "current" container
//  traps with an uncatchable EXC_BREAKPOINT (the V23 SiteVisit freeze made
//  V19/V22-pinned harnesses do exactly that).
//

typealias OPSSchemaCurrent = OPSSchemaV25
