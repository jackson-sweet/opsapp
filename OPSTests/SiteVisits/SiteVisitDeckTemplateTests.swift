//
//  SiteVisitDeckTemplateTests.swift
//  OPSTests
//
//  The built-in DECK checklist no longer carries a "Field measurements" item.
//  Measuring is what the visit's capture tools are FOR — the LiDAR / scaled /
//  dimensioned capture stores — so a checklist row demanding the same thing
//  was a second, redundant gate that blocked completion after the operator had
//  already measured.
//
//  Removing a field from a built-in template has to be safe in three ways, and
//  each is pinned here:
//   1. the shipped template no longer offers the item;
//   2. reconciliation rewrites an ALREADY-SEEDED company's system template
//      (built-ins are seeded once per company — without the rewrite, every
//      existing company would keep the retired row forever);
//   3. a historical visit that already answered the retired item keeps its
//      answer snapshot and still completes — per-visit answers are snapshots,
//      independent of the template they were minted from.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitDeckTemplateTests: XCTestCase {

    private var liveContainers: [ModelContainer] = []

    /// `PermissionStore.shared` is a process-wide singleton the test host may
    /// already have hydrated from its keychain cache. Seeding reads
    /// `isFeatureEnabled("deck_builder")` off it, so these tests pin the flag
    /// and hand back whatever was there — otherwise they depend on host state
    /// and they pollute every suite that runs after them.
    private var savedDisabledFlags: Set<String> = []

    override func setUp() {
        super.setUp()
        savedDisabledFlags = PermissionStore.shared.disabledFlags
        PermissionStore.shared.disabledFlags = []
    }

    override func tearDown() {
        PermissionStore.shared.disabledFlags = savedDisabledFlags
        liveContainers.removeAll()
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SiteVisit.self, SiteVisitType.self, SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self, SiteVisitCaptureArtifact.self,
            Opportunity.self, Client.self, Project.self, User.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        liveContainers.append(container)
        return container.mainContext
    }

    private func deckTemplate(companyId: String = "company-1") -> SiteVisitType {
        let templates = SiteVisitType.builtInTemplates(companyId: companyId, deckBuilderEnabled: true)
        return templates.first { $0.slug == "deck_estimate" }!
    }

    // MARK: - 1. The shipped template

    func test_deckTemplate_noLongerOffersAFieldMeasurementsItem() {
        let fieldIds = deckTemplate().fields.map(\.id)
        XCTAssertFalse(fieldIds.contains("field-measurements"),
                       "The deck checklist must not ask for measurements — the capture tools own that.")
    }

    func test_deckTemplate_keepsTheRestOfItsChecklistIntact() {
        let fieldIds = deckTemplate().fields.map(\.id)
        XCTAssertEqual(fieldIds, ["client-goals", "existing-structure", "deck-design"],
                       "Only the measurement row goes — goals, structure photos, and the design stay.")
    }

    func test_deckDesign_remainsTheRequiredItem() {
        let design = deckTemplate().fields.first { $0.id == "deck-design" }
        XCTAssertEqual(design?.required, true,
                       "A deck estimate still requires a design.")
    }

    // MARK: - 2. Reconciliation rewrites an already-seeded company

    func test_reconciliation_dropsTheRetiredItemFromAnExistingCompanyTemplate() throws {
        let context = try makeContext()

        // A company seeded before the change — its stored system template still
        // carries the retired measurement row.
        let stale = SiteVisitType(
            id: "system-company-1-deck-estimate",
            companyId: "company-1",
            slug: "deck_estimate",
            name: "Deck",
            descriptionText: "Deck scope, photos, measurements, and design.",
            isSystemTemplate: true,
            sortOrder: 30,
            fields: [
                .init(id: "client-goals", label: "What the client wants", kind: .longText, sortOrder: 10),
                .init(id: "existing-structure", label: "Existing structure", kind: .photoMarkup, sortOrder: 20),
                .init(id: "field-measurements", label: "Field measurements", kind: .measurement, required: true, sortOrder: 30),
                .init(id: "deck-design", label: "Deck design", kind: .deckDesign, required: true, sortOrder: 40)
            ]
        )
        context.insert(stale)
        try context.save()

        let viewModel = SiteVisitCaptureViewModel(
            opportunity: nil,
            companyId: "company-1",
            userId: "user-1",
            modelContext: context
        )
        viewModel.loadOrCreateVisit()

        let reconciled = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SiteVisitType>())
                .first { $0.slug == "deck_estimate" && $0.deletedAt == nil }
        )
        XCTAssertFalse(reconciled.fields.map(\.id).contains("field-measurements"),
                       "Reconciliation must rewrite the stored fields, or existing companies keep the retired row forever.")
    }

    func test_reconciliation_leavesUserCreatedTypesAlone() throws {
        let context = try makeContext()

        let custom = SiteVisitType(
            id: "custom-1",
            companyId: "company-1",
            slug: "my_own_walkthrough",
            name: "My walkthrough",
            isSystemTemplate: false,
            sortOrder: 90,
            fields: [
                .init(id: "field-measurements", label: "Field measurements", kind: .measurement, required: true, sortOrder: 10)
            ]
        )
        context.insert(custom)
        try context.save()

        let viewModel = SiteVisitCaptureViewModel(
            opportunity: nil,
            companyId: "company-1",
            userId: "user-1",
            modelContext: context
        )
        viewModel.loadOrCreateVisit()

        let reloaded = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SiteVisitType>()).first { $0.id == "custom-1" }
        )
        XCTAssertEqual(reloaded.fields.map(\.id), ["field-measurements"],
                       "A company that built its own measurement question keeps it — we only retire OUR defaults.")
        XCTAssertNil(reloaded.deletedAt, "User-created types are never retired by reconciliation.")
    }

    // MARK: - 3. Historical answers survive

    func test_historicalAnswerForTheRetiredItemSurvivesAndStillReads() throws {
        let context = try makeContext()

        let visit = SiteVisit(id: "visit-historical", opportunityId: nil, companyId: "company-1")
        context.insert(visit)

        // The answer snapshot a shipped build wrote when the item still existed.
        let answer = SiteVisitChecklistAnswer(
            siteVisitId: visit.id,
            companyId: "company-1",
            opportunityId: nil,
            siteVisitTypeId: "system-company-1-deck-estimate",
            fieldId: "field-measurements",
            label: "Field measurements",
            kind: .measurement,
            required: true,
            sortOrder: 30,
            createdBy: "user-1"
        )
        answer.answerValue = .text("12' x 16' deck, 30\" above grade")
        context.insert(answer)
        try context.save()

        let stored = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>())
                .first { $0.fieldId == "field-measurements" }
        )
        XCTAssertTrue(stored.isAnswered,
                      "A historical answer stays readable — answers are per-visit snapshots, not template pointers.")
        XCTAssertEqual(stored.label, "Field measurements",
                       "The snapshot carries its own label, so it renders even though the template dropped the item.")
    }
}
