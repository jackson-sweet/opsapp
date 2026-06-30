# Site Visit Types And Checklists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add company-scoped site visit types with custom checklist fields that extend the base site visit capture packet without slowing field capture.

**Architecture:** Keep the feature additive by storing `SiteVisitType` and `SiteVisitChecklistAnswer` rows beside the existing local-first `SiteVisitCaptureArtifact` packet. Do not mutate the base `SiteVisit` schema. The capture view model seeds built-in templates, selects a type for the active visit, creates answer snapshots from the type fields, and includes completed answers in project handoff.

**Tech Stack:** SwiftData, SwiftUI, XCTest, existing OPSStyle tokens, existing site-visit capture packet models.

## Global Constraints

- Field UI must stay rapid: photos, notes, measurements, and deck design remain one-tap action-bar actions.
- Site visit types are company-scoped; built-in templates are seeded locally and can be copied/edited later.
- Custom fields are additive to the base visit packet, not replacements for notes/photos/measurements.
- Deck-design fields are feature-gated to `deck_builder`.
- All copy stays terse and tactical; no emoji, no marketing language, no exclamation points.
- All styling uses existing OPSStyle tokens.

---

### Task 1: Add Type And Checklist Models

**Files:**
- Create: `OPS/DataModels/SiteVisits/SiteVisitType.swift`
- Modify: `OPS/DataModels/Migrations/OPSSchemaCommon.swift`
- Test: `OPSTests/SiteVisits/SiteVisitCapturePacketTests.swift`

**Interfaces:**
- Produces: `SiteVisitType`, `SiteVisitTypeFieldDefinition`, `SiteVisitChecklistAnswer`, `SiteVisitFieldKind`, `SiteVisitChecklistValue`.
- Produces: `SiteVisitType.builtInTemplates(companyId:deckBuilderEnabled:)`.
- Produces: `SiteVisitChecklistAnswer.makeAnswers(for:siteVisitId:companyId:opportunityId:createdBy:)`.

- [ ] Write a failing XCTest proving built-in templates seed required fields and answer snapshots.
- [ ] Run the focused test and confirm it fails because the new types do not exist.
- [ ] Add the new SwiftData models and Codable helpers.
- [ ] Register the models in `v11SiteVisitCaptureModels`.
- [ ] Re-run the focused test and confirm it passes.

### Task 2: View Model Type Selection And Answers

**Files:**
- Modify: `OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift`
- Test: `OPSTests/SiteVisits/SiteVisitCapturePacketTests.swift`

**Interfaces:**
- Consumes: `SiteVisitType`, `SiteVisitChecklistAnswer`.
- Produces: `siteVisitTypes`, `selectedSiteVisitType`, `checklistAnswers`, `selectSiteVisitType(_:)`, `updateChecklistAnswer(_:value:)`, `addAdHocChecklistQuestion(label:kind:)`, `missingRequiredChecklistAnswers`.

- [ ] Write a failing XCTest proving a selected type creates checklist answer rows for the active visit.
- [ ] Run the focused test and confirm it fails.
- [ ] Implement default type seeding, selected type loading, answer snapshot creation, updates, and reassignment propagation.
- [ ] Re-run the focused test and confirm it passes.

### Task 3: Start And Capture UI

**Files:**
- Modify: `OPS/Views/SiteVisits/SiteVisitStartSheet.swift`
- Modify: `OPS/Views/SiteVisits/SiteVisitCaptureView.swift`
- Modify: `OPS/Views/Components/FloatingActionMenu.swift`
- Modify: `OPS/Views/Leads/LeadsTabView.swift`
- Modify: `OPS/Views/Leads/LeadDetailView.swift`

**Interfaces:**
- Consumes: `SiteVisitType`.
- Produces: `SiteVisitCaptureView(opportunity:initialSiteVisitType:onCreateProject:)`.

- [ ] Pass an optional initial visit type from the FAB start sheet into capture.
- [ ] Add a compact visit type selector to `SiteVisitStartSheet`.
- [ ] Add a `CHECKLIST` panel to capture with checkbox, yes/no/N/A, text, measurement, photo, photo+markup, and deck-design answer states.
- [ ] Add an ad hoc question row action inside the checklist panel.
- [ ] Keep all existing action-bar capture controls intact.
- [ ] Build the app target and fix compiler issues before continuing.

### Task 4: Review, Project Handoff, And Docs

**Files:**
- Modify: `OPS/DataModels/SiteVisits/SiteVisitCaptureArtifact.swift`
- Modify: `OPS/Views/SiteVisits/SiteVisitProjectHandoff.swift`
- Modify: `OPS/Views/SiteVisits/SiteVisitCaptureView.swift`
- Modify: `ops-software-bible/03_DATA_ARCHITECTURE.md`
- Modify: `ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`

**Interfaces:**
- Consumes: `SiteVisitChecklistAnswer`.
- Produces: checklist answer text in the staged project payload and project note.

- [ ] Add checklist answer ids or answer snapshots to `SiteVisitProjectPayload`.
- [ ] Include checklist answers in review summary and project note handoff.
- [ ] Show missing required checklist answers in the review sheet before project creation.
- [ ] Update the software bible data architecture and lifecycle docs.
- [ ] Run focused tests and full app build.

### Task 5: Verification

**Files:**
- Test: `OPSTests/SiteVisits/SiteVisitCapturePacketTests.swift`

- [ ] Run the site-visit focused model tests.
- [ ] Run `xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -skipPackageUpdates -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build -quiet`.
- [ ] Run `git diff --check` in `ops-ios`.
- [ ] Run `git diff --check` in `ops-software-bible`.
