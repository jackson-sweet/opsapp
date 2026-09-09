//
//  SiteVisitOpenVisitsTests.swift
//  OPSTests
//
//  Regression cover for the site-visit console's "which open visit is mine?"
//  lookup. The lookup used to ask SwiftData to search the stored `assigneeIds`
//  array inside a `#Predicate`; CoreData compiles that into
//  `_NSCoreDataStringSearch`, which dereferences a null CFString and takes the
//  process down with SIGSEGV. Not a thrown error — the app is simply gone.
//
//  It stayed hidden because SQLite short-circuits `OR`: `createdBy == user`
//  matched first for visits the operator made themselves, so the array term
//  never ran. The two shapes below are the ones that reached it — an operator
//  opening the console with no signed-in id (every snapshot test), and a visit
//  someone else created and assigned onward (a manager assigning a crew
//  member). Assignment is resolved in Swift now; these pin that it stays there
//  AND that the scoping it replaced still holds.
//

#if DEBUG
import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitOpenVisitsTests: XCTestCase {

    private let company = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let operatorId = "11111111-2222-3333-4444-555555555555"
    private let colleagueId = "99999999-8888-7777-6666-555555555555"

    private var containers: [ModelContainer] = []

    /// A context whose container outlives the test — a bare
    /// `try makeContainer().mainContext` deallocates the store mid-expression
    /// and the next insert traps inside SwiftData.
    private func freshContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: OPSSchemaCurrent.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        containers.append(container)
        return ModelContext(container)
    }

    override func tearDown() {
        containers.removeAll()
        super.tearDown()
    }

    private func lead() -> Opportunity {
        Opportunity(
            id: UUID().uuidString.lowercased(),
            companyId: company,
            contactName: "Dale Harmon",
            stage: .newLead
        )
    }

    private func viewModel(
        for lead: Opportunity,
        userId: String?,
        context: ModelContext
    ) -> SiteVisitCaptureViewModel {
        SiteVisitCaptureViewModel(
            opportunity: lead,
            companyId: company,
            userId: userId,
            modelContext: context
        )
    }

    /// The shape that killed the site-visit form snapshot test: the console
    /// opens twice against one store with no operator id, so the second open
    /// evaluates the lookup over the row the first one wrote. It must survive,
    /// and it must adopt that row rather than mint a second visit for the
    /// same lead.
    func testConsoleOpensTwiceWithoutAnOperatorIdAndAdoptsItsOwnVisit() throws {
        let context = try freshContext()
        let lead = lead()

        let first = viewModel(for: lead, userId: nil, context: context)
        first.loadOrCreateVisit()
        let created = try XCTUnwrap(first.siteVisit?.id, "first open must create a visit")

        let second = viewModel(for: lead, userId: nil, context: context)
        second.loadOrCreateVisit()

        XCTAssertEqual(
            second.siteVisit?.id, created,
            "the second open must adopt the visit the first one created, not duplicate it"
        )
    }

    /// The shape that killed the app in the field: a colleague created the
    /// visit and assigned it onward, so `createdBy` and `assignedTo` both miss
    /// and only the assignee list matches. This is the row the old predicate
    /// segfaulted on.
    func testVisitAssignedOnlyThroughTheAssigneeListIsAdopted() throws {
        let context = try freshContext()
        let lead = lead()

        let handedOver = SiteVisit(
            opportunityId: lead.id,
            companyId: company,
            status: .scheduled,
            assigneeIds: [operatorId],
            createdBy: colleagueId
        )
        handedOver.assignedTo = colleagueId
        context.insert(handedOver)
        try context.save()

        let console = viewModel(for: lead, userId: operatorId, context: context)
        console.loadOrCreateVisit()

        XCTAssertEqual(
            console.siteVisit?.id, handedOver.id,
            "a visit assigned through the assignee list belongs to this operator"
        )
    }

    /// The scoping the in-memory filter replaced: someone else's open visit
    /// for the same lead is not adopted, so the operator gets their own.
    func testVisitBelongingToAnotherOperatorIsNotAdopted() throws {
        let context = try freshContext()
        let lead = lead()

        let theirs = SiteVisit(
            opportunityId: lead.id,
            companyId: company,
            status: .scheduled,
            assigneeIds: [colleagueId],
            createdBy: colleagueId
        )
        theirs.assignedTo = colleagueId
        context.insert(theirs)
        try context.save()

        let console = viewModel(for: lead, userId: operatorId, context: context)
        console.loadOrCreateVisit()

        let mine = try XCTUnwrap(console.siteVisit?.id, "the operator must get a visit of their own")
        XCTAssertNotEqual(mine, theirs.id, "another operator's visit must not be adopted")
    }
}
#endif
