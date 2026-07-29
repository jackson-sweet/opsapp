//
//  SiteVisitLeadCaptureTests.swift
//  OPSTests
//
//  Site-visit lead capture — the two field failures this suite locks down:
//
//  Bug 13c66762 — CREATE LEAD during a visit showed a red error even though the
//  lead was delivered seconds later. Clients are created LOCAL-FIRST, so the
//  guarded opportunity RPC hit `client_not_found_in_company` and rolled back;
//  the durable queue then delivered the lead. The direct path must wait for the
//  client to be visible server-side before writing its child, and a handoff to
//  that queue must read as "saved, syncing" — never as a failure.
//
//  Bug 5d5df5b0 — importing a contact killed the visit and left an empty intake
//  form. The form-wipe half is guarded here: an un-hydrated panel's empty mirror
//  can never overwrite a saved draft, and abandoned-visit re-entry inside a
//  short window resumes the visit's content instead of building a blank one.
//

import Contacts
import SwiftData
import XCTest
@testable import OPS

@MainActor
final class SiteVisitLeadCaptureTests: XCTestCase {

    /// Containers stay alive for the test's duration — handing out only
    /// `mainContext` would let the store deallocate under the context.
    private var liveContainers: [ModelContainer] = []

    override func tearDown() {
        liveContainers.removeAll()
        super.tearDown()
    }

    // MARK: - Bug 5d5df5b0 · non-destructive re-entry

    func test_reentry_autoResumesRecentUnlinkedVisitThatHoldsContent() throws {
        let context = try makeContext()
        let prior = insertVisit(id: "visit-prior", into: context)
        insertDraft(
            forVisitId: prior.id,
            contactName: "Corinne Robertson",
            address: "972 Lyall St, Esquimalt",
            updatedAt: Date(),
            into: context
        )

        let viewModel = makeViewModel(context: context)
        viewModel.loadOrCreateVisit()

        XCTAssertEqual(
            viewModel.siteVisit?.id,
            prior.id,
            "re-entering within the window continues the SAME visit — a blank one loses the capture"
        )
        XCTAssertEqual(viewModel.identityDraft?.contactName, "Corinne Robertson")
        XCTAssertEqual(viewModel.identityDraft?.address, "972 Lyall St, Esquimalt")
        XCTAssertNil(
            viewModel.resumableVisit,
            "an auto-resumed visit must not also nag through the resume banner"
        )
    }

    func test_reentry_startsFreshWhenPriorUnlinkedVisitIsStale() throws {
        let context = try makeContext()
        let stale = Date().addingTimeInterval(-60 * 60)
        let prior = insertVisit(id: "visit-prior", createdAt: stale, into: context)
        insertDraft(
            forVisitId: prior.id,
            contactName: "Corinne Robertson",
            address: "972 Lyall St, Esquimalt",
            updatedAt: stale,
            into: context
        )

        let viewModel = makeViewModel(context: context)
        viewModel.loadOrCreateVisit()

        XCTAssertNotEqual(
            viewModel.siteVisit?.id,
            prior.id,
            "an hour-old visit is a different site — never silently reopened"
        )
        XCTAssertEqual(
            viewModel.resumableVisit?.id,
            prior.id,
            "the stale visit stays offered through the resume banner"
        )
    }

    func test_reentry_sweepsEmptyAbandonedVisits() throws {
        let context = try makeContext()
        let empty = insertVisit(id: "visit-empty", into: context)

        let viewModel = makeViewModel(context: context)
        viewModel.loadOrCreateVisit()

        XCTAssertNotEqual(viewModel.siteVisit?.id, empty.id)
        XCTAssertNil(viewModel.resumableVisit, "an empty visit is nothing to resume")
        let survivors = try context.fetch(FetchDescriptor<SiteVisit>()).map(\.id)
        XCTAssertFalse(survivors.contains(empty.id), "empty abandoned visits are swept")
    }

    func test_reentry_linkedStartIgnoresUnlinkedVisitsEntirely() throws {
        let context = try makeContext()
        let prior = insertVisit(id: "visit-prior", into: context)
        insertDraft(
            forVisitId: prior.id,
            contactName: "Corinne Robertson",
            address: "972 Lyall St, Esquimalt",
            updatedAt: Date(),
            into: context
        )

        let lead = Opportunity(
            id: "opp-1",
            companyId: Self.companyId,
            contactName: "Eric Devlin",
            stage: .quoting
        )
        context.insert(lead)
        let viewModel = makeViewModel(opportunity: lead, context: context)
        viewModel.loadOrCreateVisit()

        XCTAssertNotEqual(
            viewModel.siteVisit?.id,
            prior.id,
            "a lead-linked start never adopts an unrelated unlinked visit"
        )
        XCTAssertEqual(viewModel.siteVisit?.opportunityId, "opp-1")
    }

    // MARK: - Bug 13c66762 · the direct lead-create path

    func test_createLead_waitsForClientVisibilityBeforeWritingTheLead() async throws {
        let harness = try makeLeadCreateHarness()
        var order: [String] = []
        var probes = 0

        harness.viewModel.probeClientVisibility = { _, _ in
            probes += 1
            order.append("probe-\(probes)")
            if probes < 3 { throw TestServerError.clientNotFoundInCompany }
        }
        harness.viewModel.clientVisibilityBackoff = { _ in }
        harness.viewModel.createOpportunityRemotely = { dto, _ in
            order.append("create")
            return try Self.makeOpportunityDTO(
                id: "opp-created",
                companyId: Self.companyId,
                clientId: dto.clientId,
                title: dto.title
            )
        }

        let outcome = await harness.viewModel.createLeadFromIdentityDraft(
            dataController: harness.dataController
        )

        guard case .created(let opportunity) = outcome else {
            return XCTFail("expected the lead to be created once the client was visible, got \(outcome)")
        }
        XCTAssertEqual(
            order,
            ["probe-1", "probe-2", "probe-3", "create"],
            "the guarded RPC is only called once the server can see the client"
        )
        XCTAssertEqual(opportunity.id, "opp-created")
        XCTAssertEqual(harness.viewModel.identityDraft?.opportunityId, "opp-created")
        XCTAssertEqual(harness.viewModel.siteVisit?.opportunityId, "opp-created", "the visit rebinds to its new lead")
        XCTAssertTrue(harness.viewModel.hasBoundOpportunity)
        XCTAssertNil(harness.viewModel.errorMessage)
        XCTAssertNil(harness.queue.enqueuedClientId, "a delivered lead needs no durable retry")
    }

    func test_createLead_handsDeliveryToTheQueueWhenTheClientNeverBecomesVisible() async throws {
        let harness = try makeLeadCreateHarness()
        var createAttempts = 0

        harness.viewModel.clientVisibilityAttempts = 3
        harness.viewModel.probeClientVisibility = { _, _ in throw TestServerError.clientNotFoundInCompany }
        harness.viewModel.clientVisibilityBackoff = { _ in }
        harness.viewModel.createOpportunityRemotely = { _, _ in
            createAttempts += 1
            throw TestServerError.clientNotFoundInCompany
        }

        let outcome = await harness.viewModel.createLeadFromIdentityDraft(
            dataController: harness.dataController
        )

        guard case .queued(let offline) = outcome else {
            return XCTFail("an undelivered lead is queued, never failed — got \(outcome)")
        }
        XCTAssertFalse(offline)
        XCTAssertEqual(createAttempts, 0, "never fire a create the server is guaranteed to roll back")
        XCTAssertNotNil(harness.queue.enqueuedClientId, "delivery is handed to the durable queue")
        XCTAssertEqual(harness.queue.enqueuedCompanyId, Self.companyId)
        XCTAssertNil(
            harness.viewModel.errorMessage,
            "bug 13c66762 — the lead IS coming; a red error here is a lie"
        )
        XCTAssertEqual(
            harness.viewModel.identityDraft?.clientId,
            harness.queue.enqueuedClientId,
            "the draft keeps the client so the queue's delivery can bind back to it"
        )
    }

    func test_createLead_queuesImmediatelyWhenOfflineInsteadOfBurningTheWait() async throws {
        let harness = try makeLeadCreateHarness()
        var probes = 0

        harness.viewModel.probeClientVisibility = { _, _ in
            probes += 1
            throw URLError(.notConnectedToInternet)
        }
        harness.viewModel.clientVisibilityBackoff = { _ in
            XCTFail("no signal means no point waiting")
        }

        let outcome = await harness.viewModel.createLeadFromIdentityDraft(
            dataController: harness.dataController
        )

        guard case .queued(let offline) = outcome else {
            return XCTFail("expected an offline queue handoff, got \(outcome)")
        }
        XCTAssertTrue(offline)
        XCTAssertEqual(probes, 1)
        XCTAssertNotNil(harness.queue.enqueuedClientId)
        XCTAssertNil(harness.viewModel.errorMessage)
    }

    func test_createLead_serverRejectionAfterVisibilityStillQueues() async throws {
        let harness = try makeLeadCreateHarness()

        harness.viewModel.probeClientVisibility = { _, _ in }
        harness.viewModel.createOpportunityRemotely = { _, _ in
            throw TestServerError.guardedCreateRejected
        }

        let outcome = await harness.viewModel.createLeadFromIdentityDraft(
            dataController: harness.dataController
        )

        guard case .queued = outcome else {
            return XCTFail("a saved client plus a failed insert is a handoff, not a failure — got \(outcome)")
        }
        XCTAssertNotNil(harness.queue.enqueuedClientId)
        XCTAssertNil(harness.viewModel.errorMessage)
    }

    func test_createLead_requiresAContactMethodBeforeTouchingTheServer() async throws {
        let harness = try makeLeadCreateHarness(preferredEmail: "", phoneNumber: "")
        harness.viewModel.probeClientVisibility = { _, _ in XCTFail("validation runs first") }

        let outcome = await harness.viewModel.createLeadFromIdentityDraft(
            dataController: harness.dataController
        )

        guard case .failed = outcome else {
            return XCTFail("a lead with no way to reach anyone is a real failure — got \(outcome)")
        }
        XCTAssertEqual(harness.viewModel.errorMessage, "CONTACT REQUIRED")
        XCTAssertNil(harness.queue.enqueuedClientId)
    }

    // MARK: - Bug 13c66762 · the queue's delivery reaches an open console

    func test_queueDeliveredLeadBindsTheOpenVisit() async throws {
        let harness = try makeLeadCreateHarness()
        let visitId = try XCTUnwrap(harness.viewModel.siteVisit?.id)

        // Exactly what ClientLeadAutocreateQueue does on a successful delivery:
        // cache the opportunity, bind the waiting draft, then signal the visit.
        let delivered = try Self.makeOpportunityDTO(
            id: "opp-delivered",
            companyId: Self.companyId,
            clientId: "client-x",
            title: "Corinne Robertson — lead"
        ).toModel()
        harness.context.insert(delivered)
        harness.viewModel.identityDraft?.opportunityId = "opp-delivered"
        try harness.context.save()

        NotificationCenter.default.post(
            name: Notification.Name("SiteVisitLeadBound"),
            object: nil,
            userInfo: ["siteVisitId": visitId]
        )

        let bound = await settled { harness.viewModel.currentOpportunity != nil }
        XCTAssertTrue(bound, "the open console must pick up the queue's delivery")
        XCTAssertEqual(harness.viewModel.currentOpportunity?.id, "opp-delivered")
        XCTAssertEqual(harness.viewModel.siteVisit?.opportunityId, "opp-delivered")
        XCTAssertTrue(harness.viewModel.hasBoundOpportunity)
    }

    func test_queueDeliveryForAnotherVisitIsIgnored() throws {
        let harness = try makeLeadCreateHarness()
        harness.viewModel.identityDraft?.opportunityId = "opp-delivered"

        harness.viewModel.adoptQueueDeliveredLead(forVisitId: "some-other-visit")

        XCTAssertNil(
            harness.viewModel.currentOpportunity,
            "a delivery for a different visit never binds this one"
        )
    }

    // MARK: - Bug 5d5df5b0 · the draft survives an un-hydrated panel

    func test_updateIdentityDraft_ignoresACommitFromAnUnhydratedPanel() throws {
        let harness = try makeLeadCreateHarness()

        harness.viewModel.updateIdentityDraft(
            searchText: "",
            clientName: "",
            contactName: "",
            preferredEmail: "",
            additionalEmailsText: "",
            phoneNumber: "",
            address: "",
            notes: "",
            isHydrated: false
        )

        XCTAssertEqual(
            harness.viewModel.identityDraft?.contactName,
            "Corinne Robertson",
            "an un-hydrated panel holds an empty mirror, not an edit — it must never erase the draft"
        )
        XCTAssertEqual(harness.viewModel.identityDraft?.address, "972 Lyall St, Esquimalt")
    }

    func test_updateIdentityDraft_appliesAHydratedCommit() throws {
        let harness = try makeLeadCreateHarness()

        harness.viewModel.updateIdentityDraft(
            searchText: "",
            clientName: "",
            contactName: "Corinne Robertson",
            preferredEmail: "corinne@example.com",
            additionalEmailsText: "",
            phoneNumber: "250-555-0142",
            address: "1100 Maple Ave, Victoria",
            notes: "Gate code 4412",
            isHydrated: true
        )

        XCTAssertEqual(harness.viewModel.identityDraft?.address, "1100 Maple Ave, Victoria")
        XCTAssertEqual(harness.viewModel.identityDraft?.notes, "Gate code 4412")
    }

    // MARK: - Bug 5d5df5b0 · contact import writes the draft, not view state

    func test_applyImportedContact_fillsTheDraftAndSignalsThePanel() throws {
        let harness = try makeLeadCreateHarness(contactName: "", preferredEmail: "", phoneNumber: "", address: "")
        let generationBefore = harness.viewModel.contactImportGeneration

        let contact = CNMutableContact()
        contact.givenName = "Corinne"
        contact.familyName = "Robertson"
        contact.organizationName = "West Shore Decks"
        contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: "corinne@example.com" as NSString)]
        contact.phoneNumbers = [
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "250-555-0142"))
        ]
        let postal = CNMutablePostalAddress()
        postal.street = "972 Lyall St"
        postal.city = "Esquimalt"
        postal.state = "BC"
        postal.postalCode = "V9A 5G8"
        contact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: postal as CNPostalAddress)]

        harness.viewModel.applyImportedContact(contact)

        let draft = try XCTUnwrap(harness.viewModel.identityDraft)
        XCTAssertEqual(draft.contactName, "Corinne Robertson")
        XCTAssertEqual(draft.clientName, "West Shore Decks")
        XCTAssertEqual(draft.preferredEmail, "corinne@example.com")
        XCTAssertEqual(draft.phoneNumber, "250-555-0142")
        XCTAssertTrue(draft.address.hasPrefix("972 Lyall St"), "got \(draft.address)")
        XCTAssertTrue(draft.address.contains("Esquimalt"), "got \(draft.address)")
        XCTAssertEqual(harness.viewModel.siteVisit?.address, draft.address, "the visit carries the picked address")
        XCTAssertEqual(
            harness.viewModel.contactImportGeneration,
            generationBefore + 1,
            "the panel re-mirrors the draft off this signal alone"
        )
    }

    func test_applyImportedContact_keepsTypedValuesTheContactDoesNotCarry() throws {
        let harness = try makeLeadCreateHarness()

        let contact = CNMutableContact()
        contact.phoneNumbers = [
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "250-555-9000"))
        ]

        harness.viewModel.applyImportedContact(contact)

        let draft = try XCTUnwrap(harness.viewModel.identityDraft)
        XCTAssertEqual(draft.phoneNumber, "250-555-9000", "the contact's phone wins")
        XCTAssertEqual(draft.contactName, "Corinne Robertson", "a nameless contact never blanks a typed name")
        XCTAssertEqual(draft.address, "972 Lyall St, Esquimalt", "no postal address means the typed one stands")
    }

    // MARK: - Fixtures

    private static let companyId = "company-1"

    private enum TestServerError: Error {
        /// The real 22023 the guarded RPC raises when the client row has not
        /// reached the server yet. Worded so the offline classifier can NOT
        /// mistake it for a connectivity failure.
        case clientNotFoundInCompany
        case guardedCreateRejected
    }

    private struct LeadCreateHarness {
        let viewModel: SiteVisitCaptureViewModel
        let dataController: DataController
        let queue: RecordingLeadQueue
        let context: ModelContext
    }

    /// A loaded console on an unlinked visit whose identity draft is filled in —
    /// the exact state an operator is in when they tap CREATE LEAD.
    private func makeLeadCreateHarness(
        contactName: String = "Corinne Robertson",
        preferredEmail: String = "corinne@example.com",
        phoneNumber: String = "250-555-0142",
        address: String = "972 Lyall St, Esquimalt"
    ) throws -> LeadCreateHarness {
        let context = try makeContext()
        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )

        let viewModel = makeViewModel(context: context)
        viewModel.loadOrCreateVisit()
        viewModel.updateIdentityDraft(
            searchText: "",
            clientName: "",
            contactName: contactName,
            preferredEmail: preferredEmail,
            additionalEmailsText: "",
            phoneNumber: phoneNumber,
            address: address,
            notes: ""
        )

        let queue = RecordingLeadQueue()
        viewModel.leadAutocreateQueue = queue
        viewModel.clientVisibilityBackoff = { _ in }

        return LeadCreateHarness(
            viewModel: viewModel,
            dataController: dataController,
            queue: queue,
            context: context
        )
    }

    /// Polls a condition on the main actor instead of sleeping a fixed interval.
    private func settled(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private static func makeOpportunityDTO(
        id: String,
        companyId: String,
        clientId: String?,
        title: String?
    ) throws -> OpportunityDTO {
        var json: [String: Any] = [
            "id": id,
            "company_id": companyId,
            "title": title ?? "Site visit",
            "contact_name": "Corinne Robertson",
            "stage": "new_lead",
            "stage_entered_at": "2026-07-28T12:00:00Z",
            "assignment_version": 0,
            "created_at": "2026-07-28T12:00:00Z",
            "updated_at": "2026-07-28T12:00:00Z"
        ]
        if let clientId { json["client_id"] = clientId }
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(OpportunityDTO.self, from: data)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Opportunity.self,
            Client.self,
            SubClient.self,
            SiteVisit.self,
            SiteVisitCaptureArtifact.self,
            SiteVisitType.self,
            SiteVisitChecklistAnswer.self,
            SiteVisitIdentityDraft.self,
            SyncOperation.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        liveContainers.append(container)
        return container.mainContext
    }

    private func makeViewModel(
        opportunity: Opportunity? = nil,
        context: ModelContext
    ) -> SiteVisitCaptureViewModel {
        SiteVisitCaptureViewModel(
            opportunity: opportunity,
            companyId: Self.companyId,
            userId: "user-operator-1",
            modelContext: context
        )
    }

    @discardableResult
    private func insertVisit(
        id: String,
        createdAt: Date = Date(),
        into context: ModelContext
    ) -> SiteVisit {
        let visit = SiteVisit(
            id: id,
            opportunityId: nil,
            companyId: Self.companyId,
            status: .scheduled,
            createdAt: createdAt
        )
        context.insert(visit)
        try? context.save()
        return visit
    }

    @discardableResult
    private func insertDraft(
        forVisitId visitId: String,
        contactName: String = "",
        preferredEmail: String = "",
        phoneNumber: String = "",
        address: String = "",
        clientId: String? = nil,
        updatedAt: Date = Date(),
        into context: ModelContext
    ) -> SiteVisitIdentityDraft {
        let draft = SiteVisitIdentityDraft(
            siteVisitId: visitId,
            companyId: Self.companyId,
            clientId: clientId,
            contactName: contactName,
            preferredEmail: preferredEmail,
            phoneNumber: phoneNumber,
            address: address
        )
        draft.updatedAt = updatedAt
        context.insert(draft)
        try? context.save()
        return draft
    }
}

/// Stands in for `ClientLeadAutocreateQueue` so a test can prove the handoff
/// happened without running the real durable queue.
@MainActor
private final class RecordingLeadQueue: ClientLeadAutocreateQueueing {
    private(set) var enqueuedClientId: String?
    private(set) var enqueuedCompanyId: String?

    func enqueueAndDrainInBackground(_ client: Client, companyId: String) {
        enqueuedClientId = client.id
        enqueuedCompanyId = companyId
    }
}
