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
    private var liveControllers: [DataController] = []

    override func tearDown() async throws {
        // Invalidate timer/notification work while the fixture stores still
        // exist. P1-4 separately guards production in-flight row lifetimes.
        for controller in liveControllers { controller.syncEngine.stopForLogoutSync() }
        for controller in liveControllers { await controller.syncEngine.stopForLogoutAsync() }
        liveControllers.removeAll()
        liveContainers.removeAll()
        try await super.tearDown()
    }

    func test_createLead_commitsClientContactsAndDraftAtomicallyWithoutSavingCallerWork() async throws {
        for failFirst in [false, true] {
            var fail = false
            let harness = try makeLeadCreateHarness(validateCommit: {
                if fail { throw URLError(.cannotWriteToFile) }
            })
            let vm = harness.viewModel
            vm.updateIdentityDraft(searchText: "", clientName: "Synthetic company",
                contactName: "Site person", preferredEmail: "primary@example.com",
                additionalEmailsText: "crew@example.com, CREW@example.com, second@example.com, primary@example.com",
                phoneNumber: "250-555-0100", address: "Synthetic address", notes: "Site notes")
            var probes = 0
            vm.probeClientVisibility = { _, _ in probes += 1; throw URLError(.notConnectedToInternet) }
            vm.createOpportunityRemotely = { _, _ in throw TestServerError.guardedCreateRejected }
            let caller = harness.context
            caller.autosaveEnabled = false
            let other = Client(id: UUID().uuidString.lowercased(), name: "Stored B", companyId: Self.companyId)
            caller.insert(other)
            try caller.save()
            other.name = "Pending B"
            let pendingDraft = SiteVisitIdentityDraft(siteVisitId: UUID().uuidString.lowercased(),
                companyId: Self.companyId, notes: "Uncommitted B draft")
            caller.insert(pendingDraft)
            let otherId = other.id
            let pendingDraftId = pendingDraft.id
            let visitId = try XCTUnwrap(vm.siteVisit?.id)
            fail = failFirst
            let outcome = await vm.createLeadFromIdentityDraft(dataController: harness.dataController)
            if failFirst {
                guard case .failed = outcome else { return XCTFail("Failed transaction must not hand off a client") }
                XCTAssertNil(vm.identityDraft?.clientId)
                XCTAssertNil(harness.queue.enqueuedClientId)
                XCTAssertEqual(probes, 0)
                let failedReadback = ModelContext(caller.container)
                XCTAssertEqual(try failedReadback.fetch(FetchDescriptor<Client>()).count, 1)
                XCTAssertTrue(try failedReadback.fetch(FetchDescriptor<SubClient>()).isEmpty)
                XCTAssertFalse(try failedReadback.fetch(FetchDescriptor<SyncOperation>()).contains {
                    $0.entityType == SyncEntityType.client.rawValue || $0.entityType == SyncEntityType.subClient.rawValue
                })
                fail = false
                let retry = await vm.createLeadFromIdentityDraft(dataController: harness.dataController)
                guard case .queued = retry else { return XCTFail("Retry must save the whole packet") }
            } else {
                guard case .queued = outcome else { return XCTFail("Offline packet must be queued") }
            }
            let clientId = try XCTUnwrap(vm.identityDraft?.clientId)
            let fresh = ModelContext(caller.container)
            let savedClients = try fresh.fetch(FetchDescriptor<Client>())
            let client = try XCTUnwrap(savedClients.first { $0.id == clientId })
            XCTAssertEqual(savedClients.count, 2)
            XCTAssertEqual(client.name, "Synthetic company")
            XCTAssertEqual(client.notes, "Site notes")
            XCTAssertEqual(client.subClients.count, 2)
            XCTAssertTrue(client.subClients.allSatisfy { $0.client?.id == clientId && $0.needsSync })
            let operations = try fresh.fetch(FetchDescriptor<SyncOperation>())
            let clientOperation = try XCTUnwrap(operations.first { $0.entityType == SyncEntityType.client.rawValue })
            XCTAssertEqual(clientOperation.entityId, clientId)
            XCTAssertEqual(clientOperation.operationType, "create")
            XCTAssertTrue(SyncFieldGuard.protectedFields(from: [clientOperation], now: Date()).contains("phoneNumber"))
            XCTAssertEqual(operations.filter { $0.entityType == SyncEntityType.subClient.rawValue }.count, 2)
            XCTAssertEqual(try fresh.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).first { $0.siteVisitId == visitId }?.clientId, clientId)
            XCTAssertEqual(savedClients.first { $0.id == otherId }?.name, "Stored B")
            XCTAssertFalse(try fresh.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).contains { $0.id == pendingDraftId })
            XCTAssertEqual(other.name, "Pending B")
            XCTAssertEqual(pendingDraft.notes, "Uncommitted B draft")
            XCTAssertTrue(caller.hasChanges)
            // Tapping again while the client create is pending must reuse it,
            // recheck visibility and deduplicate both extra contacts and outbox.
            let retry = await vm.createLeadFromIdentityDraft(dataController: harness.dataController)
            guard case .queued = retry else { return XCTFail("Pending parent still needs delivery") }
            XCTAssertEqual(vm.identityDraft?.clientId, clientId)
            XCTAssertEqual(probes, 2)
            let retried = ModelContext(caller.container)
            XCTAssertEqual(try retried.fetch(FetchDescriptor<Client>()).count, 2)
            XCTAssertEqual(try retried.fetch(FetchDescriptor<SubClient>()).count, 2)
            let sends = try retried.fetch(FetchDescriptor<SyncOperation>())
            XCTAssertEqual(sends.filter { $0.entityType == SyncEntityType.client.rawValue }.count, 1)
            XCTAssertEqual(sends.filter { $0.entityType == SyncEntityType.subClient.rawValue }.count, 2)
        }
    }

    func test_createLead_updatesExistingClientAndClearsContactFieldsWhilePreservingBlankNotes() async throws {
        var fail = false
        let harness = try makeLeadCreateHarness(validateCommit: {
            if fail { throw URLError(.cannotWriteToFile) }
        })
        let client = Client(id: UUID().uuidString.lowercased(), name: "Original", email: "old@example.com",
            phoneNumber: "250-555-0101", address: "Old address", companyId: Self.companyId, notes: "Old notes")
        harness.context.insert(client)
        try harness.context.save()
        let clientId = client.id
        harness.viewModel.bindClient(client)
        harness.viewModel.updateIdentityDraft(searchText: "", clientName: "Updated", contactName: "Person",
            preferredEmail: "", additionalEmailsText: "extra@example.com", phoneNumber: "250-555-0199",
            address: "", notes: "")
        client.name = "Pending elsewhere"
        harness.viewModel.probeClientVisibility = { _, _ in XCTFail("An already landed parent needs no wait") }
        harness.viewModel.createOpportunityRemotely = { _, _ in throw URLError(.notConnectedToInternet) }
        fail = true
        let failed = await harness.viewModel.createLeadFromIdentityDraft(dataController: harness.dataController)
        guard case .failed = failed else { return XCTFail("Existing-client edits must fail atomically") }
        let failedReadback = ModelContext(harness.context.container)
        let unchanged = try XCTUnwrap(try failedReadback.fetch(FetchDescriptor<Client>()).first)
        XCTAssertEqual(unchanged.name, "Original")
        XCTAssertEqual(unchanged.notes, "Old notes")
        XCTAssertEqual(unchanged.phoneNumber, "250-555-0101")
        XCTAssertTrue(try failedReadback.fetch(FetchDescriptor<SubClient>()).isEmpty)
        XCTAssertFalse(try failedReadback.fetch(FetchDescriptor<SyncOperation>()).contains {
            $0.entityType == SyncEntityType.client.rawValue || $0.entityType == SyncEntityType.subClient.rawValue
        })
        XCTAssertEqual(client.name, "Pending elsewhere")
        XCTAssertEqual(harness.viewModel.identityDraft?.clientId, clientId)
        fail = false
        let outcome = await harness.viewModel.createLeadFromIdentityDraft(dataController: harness.dataController)
        guard case .queued = outcome else { return XCTFail("Lead delivery should be queued") }
        let readback = ModelContext(harness.context.container)
        let updated = try XCTUnwrap(try readback.fetch(FetchDescriptor<Client>()).first)
        XCTAssertEqual(updated.id, clientId)
        XCTAssertEqual(updated.name, "Updated")
        XCTAssertEqual(updated.phoneNumber, "250-555-0199")
        XCTAssertNil(updated.email)
        XCTAssertNil(updated.address)
        XCTAssertEqual(updated.notes, "Old notes")
        XCTAssertEqual(client.name, "Pending elsewhere")
        XCTAssertTrue(harness.context.hasChanges)
        let operation = try XCTUnwrap(try readback.fetch(FetchDescriptor<SyncOperation>()).first {
            $0.entityType == SyncEntityType.client.rawValue
        })
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any])
        XCTAssertTrue(payload["email"] is NSNull)
        XCTAssertTrue(payload["address"] is NSNull)
        XCTAssertNil(payload["notes"], "Blank capture notes must not encode a client-note clear")
        XCTAssertEqual(payload["phone_number"] as? String, "250-555-0199")
        XCTAssertTrue(operation.getChangedFields().contains("phoneNumber"))

        harness.viewModel.updateIdentityDraft(searchText: "", clientName: "Updated", contactName: "Person",
            preferredEmail: "", additionalEmailsText: "extra@example.com", phoneNumber: "250-555-0199",
            address: "", notes: "New captured notes")
        let noteUpdate = await harness.viewModel.createLeadFromIdentityDraft(dataController: harness.dataController)
        guard case .queued = noteUpdate else { return XCTFail("Nonblank note update should be queued") }
        let noteReadback = ModelContext(harness.context.container)
        XCTAssertEqual(try noteReadback.fetch(FetchDescriptor<Client>()).first?.notes, "New captured notes")
        let noteOperation = try XCTUnwrap(try noteReadback.fetch(FetchDescriptor<SyncOperation>()).first {
            $0.entityType == SyncEntityType.client.rawValue
        })
        let notePayload = try XCTUnwrap(try JSONSerialization.jsonObject(with: noteOperation.payload) as? [String: Any])
        XCTAssertEqual(notePayload["notes"] as? String, "New captured notes")
        XCTAssertTrue(notePayload["email"] is NSNull)
        XCTAssertTrue(notePayload["address"] is NSNull)
        XCTAssertEqual(client.name, "Pending elsewhere")
        XCTAssertTrue(harness.context.hasChanges)
    }

    func test_createLead_resumedClientBoundBlankDraftPreservesExistingClientNotes() async throws {
        let harness = try makeLeadCreateHarness()
        let client = Client(id: UUID().uuidString.lowercased(), name: "Original",
            email: "legacy@example.com", companyId: Self.companyId, notes: "Existing client notes")
        harness.context.insert(client)
        let visit = insertVisit(id: UUID().uuidString.lowercased(), into: harness.context)
        let draft = SiteVisitIdentityDraft(siteVisitId: visit.id, companyId: Self.companyId,
            clientId: client.id, clientName: "Updated legacy client", contactName: "Site person",
            preferredEmail: "legacy@example.com", notes: "", createdBy: "user-operator-1")
        harness.context.insert(draft)
        try harness.context.save()
        let clientId = client.id
        let visitId = visit.id
        let draftId = draft.id
        client.notes = "Uncommitted caller notes"

        // Load the already-bound stored draft directly; do not call bindClient
        // or updateIdentityDraft, which would bypass the legacy resume path.
        let resumed = SiteVisitCaptureViewModel(opportunity: nil, companyId: Self.companyId,
            userId: "user-operator-1", modelContext: harness.context, entryIntent: .resume(visitId: visitId))
        resumed.leadAutocreateQueue = harness.queue
        resumed.probeClientVisibility = { _, _ in XCTFail("Existing parent needs no visibility wait") }
        resumed.createOpportunityRemotely = { _, _ in throw URLError(.notConnectedToInternet) }
        resumed.loadOrCreateVisit()
        XCTAssertEqual(resumed.siteVisit?.id, visitId)
        XCTAssertEqual(resumed.identityDraft?.id, draftId)
        XCTAssertEqual(resumed.identityDraft?.clientId, clientId)
        XCTAssertEqual(resumed.identityDraft?.notes, "")
        let outcome = await resumed.createLeadFromIdentityDraft(dataController: harness.dataController)
        guard case .queued = outcome else { return XCTFail("Resumed draft must retain durable lead delivery") }
        let fresh = ModelContext(harness.context.container)
        let saved = try XCTUnwrap(try fresh.fetch(FetchDescriptor<Client>()).first { $0.id == clientId })
        XCTAssertEqual(saved.notes, "Existing client notes")
        XCTAssertEqual(saved.name, "Updated legacy client")
        XCTAssertEqual(client.notes, "Uncommitted caller notes")
        XCTAssertTrue(harness.context.hasChanges)
        let operation = try XCTUnwrap(try fresh.fetch(FetchDescriptor<SyncOperation>()).first {
            $0.entityType == SyncEntityType.client.rawValue && $0.entityId == clientId
        })
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any])
        XCTAssertNil(payload["notes"])
        XCTAssertFalse(operation.getChangedFields().contains("notes"))
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).first { $0.id == draftId }?.notes, "")
    }

    func test_createLead_doesNotReviveOrBypassAStoppedClientCreate() async throws {
        let harness = try makeLeadCreateHarness()
        let client = Client(id: UUID().uuidString.lowercased(), name: "Original", email: "one@example.com", companyId: Self.companyId)
        harness.context.insert(client)
        let payload = try JSONSerialization.data(withJSONObject: ["id": client.id, "company_id": Self.companyId, "name": "Original"])
        let stopped = SyncOperation(entityType: SyncEntityType.client.rawValue, entityId: client.id,
            operationType: "create", payload: payload, changedFields: ["name"])
        stopped.status = "parked"
        harness.context.insert(stopped)
        try harness.context.save()
        let stoppedId = stopped.id
        harness.viewModel.bindClient(client)
        harness.viewModel.probeClientVisibility = { _, _ in XCTFail("Stopped parent must be handed to durable review") }
        harness.viewModel.createOpportunityRemotely = { _, _ in
            XCTFail("A stopped client create must not be bypassed by direct lead delivery")
            throw TestServerError.guardedCreateRejected
        }
        let outcome = await harness.viewModel.createLeadFromIdentityDraft(dataController: harness.dataController)
        guard case .queued = outcome else { return XCTFail("Stopped parent must remain in durable delivery") }
        let fresh = ModelContext(harness.context.container)
        let saved = try XCTUnwrap(try fresh.fetch(FetchDescriptor<SyncOperation>()).first { $0.id == stoppedId })
        XCTAssertEqual(saved.status, "parked")
        XCTAssertEqual(saved.payload, payload)
        let followOn = try XCTUnwrap(try fresh.fetch(FetchDescriptor<SyncOperation>()).first {
            $0.entityType == SyncEntityType.client.rawValue && $0.id != stoppedId
        })
        XCTAssertEqual(followOn.dependsOnId, stoppedId.uuidString.lowercased())
    }

    // MARK: - Bug 5d5df5b0 · non-destructive re-entry

    func test_reentry_resumesExactInterruptedVisitIdentity() throws {
        let context = try makeContext()
        let prior = insertVisit(id: "visit-prior", into: context)
        insertDraft(
            forVisitId: prior.id,
            contactName: "Corinne Robertson",
            address: "972 Lyall St, Esquimalt",
            updatedAt: Date(),
            into: context
        )

        let viewModel = SiteVisitCaptureViewModel(opportunity: nil, companyId: Self.companyId,
            userId: "user-operator-1", modelContext: context, entryIntent: .resume(visitId: prior.id))
        viewModel.loadOrCreateVisit()

        XCTAssertEqual(
            viewModel.siteVisit?.id,
            prior.id,
            "explicit resume continues the same visit regardless of age"
        )
        XCTAssertEqual(viewModel.identityDraft?.contactName, "Corinne Robertson")
        XCTAssertEqual(viewModel.identityDraft?.address, "972 Lyall St, Esquimalt")
        XCTAssertNil(
            viewModel.resumableVisit,
            "an explicitly resumed visit must not also show the resume banner"
        )
    }

    func test_newVisitNeverReusesRecentIdentityButOffersResume() throws {
        let context = try makeContext()
        let prior = insertVisit(id: "recent-visit", into: context)
        insertDraft(forVisitId: prior.id, contactName: "Synthetic customer", updatedAt: Date(), into: context)
        let viewModel = makeViewModel(context: context)
        viewModel.loadOrCreateVisit()
        XCTAssertNotEqual(viewModel.siteVisit?.id, prior.id)
        XCTAssertEqual(viewModel.resumableVisit?.id, prior.id)
    }

    func test_checklistOnlyAndIdentityNotesOnlyRemainResumable() throws {
        let context = try makeContext()
        let prior = insertVisit(id: "checklist-only", into: context)
        let answer = SiteVisitChecklistAnswer(siteVisitId: prior.id, companyId: Self.companyId,
            opportunityId: nil, siteVisitTypeId: nil, fieldId: "gate", label: "Gate",
            kind: .shortText, required: false, sortOrder: 1, answerValue: .text("1234"))
        context.insert(answer)
        try context.save()
        let first = makeViewModel(context: context)
        first.loadOrCreateVisit()
        XCTAssertEqual(first.resumableVisit?.id, prior.id)
        first.resumeResumableVisit()
        XCTAssertTrue(first.hasCapturedAnything)
        XCTAssertEqual(first.checklistAnswers.first?.answerValue.text, "1234")
        let noteVisit = insertVisit(id: "identity-notes-only", into: context)
        let draft = SiteVisitIdentityDraft(siteVisitId: noteVisit.id, companyId: Self.companyId,
            searchText: "partial lookup", notes: "Call before arrival")
        context.insert(draft)
        try context.save()
        let next = makeViewModel(context: context)
        next.loadOrCreateVisit()
        XCTAssertEqual(next.resumableVisit?.id, noteVisit.id)
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

    func test_reentry_preservesEmptyVisitBecauseCameraJournalCustodyIsUnknown() throws {
        let context = try makeContext()
        let empty = insertVisit(id: "visit-empty", into: context)

        let viewModel = makeViewModel(context: context)
        viewModel.loadOrCreateVisit()

        XCTAssertNotEqual(viewModel.siteVisit?.id, empty.id)
        XCTAssertNil(viewModel.resumableVisit, "an empty visit is nothing to resume")
        let survivors = try context.fetch(FetchDescriptor<SiteVisit>()).map(\.id)
        XCTAssertTrue(survivors.contains(empty.id), "absence of attached artifacts cannot prove camera custody empty")
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
        let deliveryContext = ModelContext(harness.context.container)
        deliveryContext.insert(delivered)
        let draft = try XCTUnwrap(deliveryContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate { $0.siteVisitId == visitId }
        )).first)
        draft.opportunityId = delivered.id
        draft.lastCommittedAt = Date()
        draft.touch()
        let visit = try XCTUnwrap(deliveryContext.fetch(FetchDescriptor<SiteVisit>(
            predicate: #Predicate { $0.id == visitId }
        )).first)
        visit.opportunityId = delivered.id
        try deliveryContext.save()

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
        address: String = "972 Lyall St, Esquimalt",
        validateCommit: @escaping () throws -> Void = {}
    ) throws -> LeadCreateHarness {
        let context = try makeContext()
        context.autosaveEnabled = false
        let dataController = DataController()
        liveControllers.append(dataController)
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: SiteVisitFixtureOfflineConnectivity()
        )

        let coordinator = SiteVisitPersistenceCoordinator(modelContext: context,
            companyId: Self.companyId, validateCommit: validateCommit)
        let viewModel = SiteVisitCaptureViewModel(opportunity: nil, companyId: Self.companyId,
            userId: "user-operator-1", modelContext: context, persistenceCoordinator: coordinator)
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
            createdBy: "user-operator-1",
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

/// The visibility/lead transports above are injected independently. Background
/// client/outbox work must stay offline regardless of the Mac's real network.
@MainActor
private final class SiteVisitFixtureOfflineConnectivity: ConnectivityManager {
    override var shouldAttemptSync: Bool { false }
    override var shouldPullData: Bool { false }
    override var shouldUploadPhotos: Bool { false }
}
