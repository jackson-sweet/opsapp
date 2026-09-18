//
//  SiteVisitCaptureAuthorityTests.swift
//  OPSTests
//
//  CREW SITE VISITS · P1 — the capture console as an assignee without lead
//  authority. The server freezes a visit's links and deleted_at for an
//  assignee-only save and refuses a stage move without lead edit, so the
//  console must never queue those writes. Invented people and ids only.
//

import XCTest
import SwiftData
@testable import OPS

@MainActor
final class SiteVisitCaptureAuthorityTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private let company = "7a7a7a7a-1111-4111-8111-7a7a7a7a7a7a"
    private let crewId = "7b7b7b7b-2222-4222-8222-7b7b7b7b7b7b"
    private let officeId = "7c7c7c7c-3333-4333-8333-7c7c7c7c7c7c"
    private let leadId = "7d7d7d7d-4444-4444-8444-7d7d7d7d7d7d"
    private let otherLeadId = "7e7e7e7e-5555-4555-8555-7e7e7e7e7e7e"

    override func tearDown() { containers.removeAll(); super.tearDown() }

    // MARK: - Harness

    private var crewPolicy: LeadAccessPolicy {
        LeadAccessPolicy(currentUserId: crewId, permissions: [:],
                         explicitPermissionKeys: LeadAccessPolicy.granularPermissionKeys)
    }

    private var officePolicy: LeadAccessPolicy {
        LeadAccessPolicy(
            currentUserId: officeId,
            permissions: ["pipeline.create": "all", "pipeline.view": "all",
                          "pipeline.edit": "all", "pipeline.convert": "all"],
            explicitPermissionKeys: LeadAccessPolicy.granularPermissionKeys
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([SiteVisit.self, SiteVisitType.self, SiteVisitCaptureArtifact.self,
            SiteVisitChecklistAnswer.self, SiteVisitIdentityDraft.self, SyncOperation.self,
            Opportunity.self, Client.self, SubClient.self, DeckDesign.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        containers.append(container)
        return container.mainContext
    }

    /// A booked, lead-linked visit an office user created and assigned to crew.
    @discardableResult
    private func insertAssignedVisit(into context: ModelContext, id: String = "7f7f7f7f-6666-4666-8666-7f7f7f7f7f7f") throws -> SiteVisit {
        let visit = SiteVisit(id: id, opportunityId: leadId, companyId: company, status: .scheduled,
                              assigneeIds: [crewId], createdBy: officeId)
        visit.assignedTo = officeId
        visit.address = "14 Invented Way"
        context.insert(visit)
        try context.save()
        return visit
    }

    /// What the root capture host builds from a lead brief: display fields,
    /// no `assigned_to`.
    private func briefSnapshot() -> Opportunity {
        let snapshot = Opportunity(id: leadId, companyId: company, contactName: "Rowan Example")
        snapshot.address = "14 Invented Way"
        return snapshot
    }

    private func console(
        context: ModelContext,
        opportunity: Opportunity?,
        userId: String,
        policy: LeadAccessPolicy?,
        walkUp: Bool = false,
        resume visitId: String?
    ) -> SiteVisitCaptureViewModel {
        let vm = SiteVisitCaptureViewModel(
            opportunity: opportunity, companyId: company, userId: userId, modelContext: context,
            entryIntent: visitId.map { .resume(visitId: $0) } ?? .newVisit
        )
        if let policy {
            vm.leadPolicyProvider = { policy }
            vm.walkUpAuthorityProvider = { walkUp }
        }
        vm.loadOrCreateVisit()
        return vm
    }

    private func stageOperations(in context: ModelContext) throws -> [SyncOperation] {
        try ModelContext(context.container).fetch(FetchDescriptor<SyncOperation>())
            .filter { $0.operationType == SiteVisitSyncOperation.stageOperationType }
    }

    private func captureEvidence(_ vm: SiteVisitCaptureViewModel) {
        for answer in vm.missingRequiredChecklistAnswers {
            vm.updateChecklistAnswer(answer, value: .text("Scope"))
        }
        vm.noteDraft = "Gate on the north side"
        vm.commitNote()
    }

    // MARK: - Assignee without lead authority

    func test_assigneeResumesTheExactAssignedVisitAndItsLead() throws {
        let context = try makeContext()
        let visit = try insertAssignedVisit(into: context)

        let vm = console(context: context, opportunity: nil, userId: crewId, policy: crewPolicy, resume: visit.id)

        XCTAssertEqual(vm.siteVisit?.id, visit.id)
        XCTAssertTrue(vm.hasBoundOpportunity, "the visit's own lead link binds the console")
        XCTAssertEqual(vm.identityDraft?.opportunityId, leadId,
                       "a fresh identity draft carries the visit's lead, never an unlinked identity")
        XCTAssertEqual(vm.captureGates, SiteVisitCaptureGates(
            canChangeBinding: false, canSearchLeads: false, canCreateLead: false,
            canCreateProject: false, canMoveLeadStage: false,
            canPersistAddressToLead: false, canDiscardVisit: false
        ))
    }

    func test_assigneeCompletesTheVisitWithoutEverQueuingAStageCommand() async throws {
        let context = try makeContext()
        let visit = try insertAssignedVisit(into: context)
        let vm = console(context: context, opportunity: briefSnapshot(), userId: crewId,
                         policy: crewPolicy, resume: visit.id)
        vm.readStageSnapshot = { _ in
            XCTFail("an assignee without lead edit never reads the stage contract")
            throw URLError(.userAuthenticationRequired)
        }
        await vm.prepareStageSnapshot()
        captureEvidence(vm)

        XCTAssertNil(vm.makeStageDecision(), "no stage card, no stage decision")
        let result = await vm.saveVisit(movingLeadTo: .qualifying)

        XCTAssertEqual(result, .committed, "the visit completes; nothing asks to review a lead stage")
        XCTAssertEqual(vm.siteVisit?.status, .completed)
        XCTAssertTrue(try stageOperations(in: context).isEmpty)
    }

    func test_anExplicitStageDecisionIsIgnoredWithoutLeadEdit() async throws {
        let context = try makeContext()
        let visit = try insertAssignedVisit(into: context)
        let vm = console(context: context, opportunity: briefSnapshot(), userId: crewId,
                         policy: crewPolicy, resume: visit.id)
        captureEvidence(vm)
        let forged = SiteVisitStageDecision(opportunityId: leadId, currentStage: .newLead,
                                            snapshot: nil, targetStage: .qualifying)

        let result = await vm.saveVisit(stageDecision: forged)

        XCTAssertEqual(result, .committed)
        XCTAssertTrue(try stageOperations(in: context).isEmpty)
    }

    func test_assigneeCannotRelinkClearBindOrDiscardTheVisit() throws {
        let context = try makeContext()
        let visit = try insertAssignedVisit(into: context)
        let other = Opportunity(id: otherLeadId, companyId: company, contactName: "Someone Else")
        let client = Client(id: "70707070-7777-4777-8777-707070707070", name: "Invented Client",
                            email: "client@example.com", companyId: company)
        context.insert(other); context.insert(client); try context.save()
        let vm = console(context: context, opportunity: briefSnapshot(), userId: crewId,
                         policy: crewPolicy, resume: visit.id)
        let draftClient = vm.identityDraft?.clientId

        vm.reassignVisit(to: other)
        XCTAssertEqual(vm.siteVisit?.opportunityId, leadId)
        XCTAssertEqual(vm.currentOpportunity?.id, leadId)

        vm.clearIdentitySelection()
        XCTAssertEqual(vm.siteVisit?.opportunityId, leadId)
        XCTAssertEqual(vm.identityDraft?.opportunityId, leadId)

        vm.bindClient(client)
        XCTAssertEqual(vm.identityDraft?.clientId, draftClient)

        vm.discardVisit()
        XCTAssertNil(vm.siteVisit?.deletedAt)

        let stored = try XCTUnwrap(ModelContext(context.container)
            .fetch(FetchDescriptor<SiteVisit>()).first { $0.id == visit.id })
        XCTAssertEqual(stored.opportunityId, leadId)
        XCTAssertNil(stored.deletedAt)
        XCTAssertNil(stored.projectId)
        XCTAssertNil(stored.clientId)
    }

    func test_assigneeCannotCreateALeadFromTheVisit() async throws {
        let context = try makeContext()
        let visit = try insertAssignedVisit(into: context)
        let vm = console(context: context, opportunity: nil, userId: crewId, policy: crewPolicy, resume: visit.id)
        vm.createOpportunityRemotely = { _, _ in
            XCTFail("an assignee never creates a lead")
            throw URLError(.userAuthenticationRequired)
        }

        let outcome = await vm.createLeadFromIdentityDraft(dataController: DataController())

        guard case .failed = outcome else { return XCTFail("CREATE LEAD is closed without pipeline create") }
        XCTAssertEqual(vm.siteVisit?.opportunityId, leadId)
    }

    func test_addressEditsStayOnTheVisitWithoutLeadEdit() async throws {
        let context = try makeContext()
        let visit = try insertAssignedVisit(into: context)
        let vm = console(context: context, opportunity: briefSnapshot(), userId: crewId,
                         policy: crewPolicy, resume: visit.id)

        await vm.updateVisitAddress("22 Sample Street, Testville", persistToLead: true)

        XCTAssertEqual(vm.siteVisit?.address, "22 Sample Street, Testville")
        XCTAssertEqual(vm.currentOpportunity?.address, "14 Invented Way",
                       "the lead's address is lead authority — never patched, never faked locally")
        XCTAssertNil(vm.errorMessage, "no lead write was attempted, so none failed")
    }

    func test_aClosedResumeTargetIsNeverReplacedByAVisitTheAssigneeCannotCreate() throws {
        let context = try makeContext()
        let visit = try insertAssignedVisit(into: context)
        visit.status = .completed
        visit.completedAt = Date()
        try context.save()

        let vm = console(context: context, opportunity: briefSnapshot(), userId: crewId,
                         policy: crewPolicy, walkUp: true, resume: visit.id)

        XCTAssertNil(vm.siteVisit)
        XCTAssertEqual(vm.errorMessage, "SITE VISIT UNAVAILABLE")
        XCTAssertEqual(try ModelContext(context.container).fetch(FetchDescriptor<SiteVisit>()).count, 1,
                       "no lead-bound replacement visit was minted")
    }

    // MARK: - Walk-up capture

    func test_walkUpWithoutLeadGrantsKeepsCaptureButNoLeadActions() throws {
        let context = try makeContext()
        let vm = console(context: context, opportunity: nil, userId: crewId,
                         policy: crewPolicy, walkUp: true, resume: nil)

        XCTAssertNotNil(vm.siteVisit, "walk-up capture starts a leadless visit")
        XCTAssertNil(vm.siteVisit?.opportunityId)
        XCTAssertFalse(vm.captureGates.canSearchLeads)
        XCTAssertFalse(vm.captureGates.canCreateLead)
        XCTAssertTrue(vm.captureGates.canDiscardVisit, "their own walk-up stays discardable")
    }

    // MARK: - Lead authority keeps today's console

    func test_leadEditorKeepsStageMovesAndDiscard() async throws {
        let context = try makeContext()
        let visit = try insertAssignedVisit(into: context)
        let lead = Opportunity(id: leadId, companyId: company, contactName: "Rowan Example", stage: .newLead)
        context.insert(lead); try context.save()
        let vm = console(context: context, opportunity: lead, userId: officeId,
                         policy: officePolicy, resume: visit.id)

        XCTAssertEqual(vm.siteVisit?.id, visit.id)
        XCTAssertTrue(vm.captureGates.canMoveLeadStage)
        XCTAssertTrue(vm.captureGates.canDiscardVisit)
        XCTAssertNotNil(vm.makeStageDecision())
    }

    func test_consoleBuiltOutsideTheCaptureViewIsUnrestricted() throws {
        let context = try makeContext()
        let visit = try insertAssignedVisit(into: context)
        let vm = console(context: context, opportunity: nil, userId: crewId, policy: nil, resume: visit.id)

        XCTAssertEqual(vm.captureGates, .unrestricted)
    }
}
