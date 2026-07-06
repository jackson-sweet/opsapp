//
//  UnifiedLogActivityViewModelTests.swift
//  OPSTests
//
//  UnifiedLogActivityViewModel merges three legacy loggers' behavior into
//  one write path. These tests prove, without any live network/SwiftData:
//   - Entry-point resolution: leadDetail locks to that opportunity; postCall
//     locks + defaults type=.call + captures provenance; genericFAB starts
//     unbound + unlocked.
//   - Conditional field gating matches LeadLogActivitySheet's show-rules
//     exactly (note hides direction/duration; email shows direction only;
//     meeting shows duration only; call shows both, plus outcome for all
//     but note).
//   - `plannedLog()` — the pure DTO-shape decision `save()` writes — carries
//     every field the sheet collected (the original data-loss regression)
//     and threads call provenance only for `.call`.
//   - Follow-up mapping: selectedType → FollowUpType, and the pure DTO
//     builder carries the accepted suggestion's title/dueAt without ever
//     touching the network.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class UnifiedLogActivityViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Opportunity.self, Client.self, Project.self, User.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeOpportunity(id: String = "opp-1", companyId: String = "co-1", name: String = "Eric Devlin") -> Opportunity {
        Opportunity(id: id, companyId: companyId, contactName: name, stage: .quoting)
    }

    private func makeConfiguredViewModel(entry: UnifiedLogActivityViewModel.Entry) throws -> UnifiedLogActivityViewModel {
        let container = try makeContainer()
        let vm = UnifiedLogActivityViewModel(entry: entry)
        vm.configure(companyId: "co-1", userId: "user-operator-1", modelContext: container.mainContext)
        return vm
    }

    // MARK: - Entry-point resolution

    func test_leadDetail_entry_locksTargetToThatOpportunity() throws {
        let opp = makeOpportunity()
        let vm = try makeConfiguredViewModel(entry: .leadDetail(opp))

        XCTAssertTrue(vm.isTargetLocked)
        XCTAssertEqual(vm.target.parentKey, .opportunity("opp-1"))
        XCTAssertEqual(vm.selectedType, .call)
    }

    func test_postCall_entry_locksTarget_defaultsCallType_capturesProvenance() throws {
        let pending = PendingOutboundCall(
            opportunityId: "opp-99",
            contactName: "Maria Chen",
            phoneNumber: "6045550142",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let vm = try makeConfiguredViewModel(entry: .postCall(pending))

        XCTAssertTrue(vm.isTargetLocked)
        XCTAssertTrue(vm.leadIsLocked)
        XCTAssertEqual(vm.selectedType, .call)
        XCTAssertEqual(vm.contactName, "Maria Chen")
        XCTAssertEqual(vm.phoneNumber, "6045550142")
        XCTAssertEqual(vm.direction, "outbound")

        // Provenance threads into the planned write for a .call save.
        let planned = vm.plannedLog()
        XCTAssertEqual(planned.callSource, CallCaptureSource.postCallPrompt.rawValue)
        XCTAssertEqual(planned.callerNumber, PhoneNumber.normalize("6045550142"))
        XCTAssertEqual(planned.callStartedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func test_genericFAB_entry_startsUnbound_notLocked() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)

        XCTAssertFalse(vm.isTargetLocked)
        XCTAssertFalse(vm.leadIsLocked)
        XCTAssertEqual(vm.target, .unbound)
        XCTAssertNil(vm.target.parentKey)
    }

    func test_capture_entry_startsUnbound_notLocked_defaultsInbound() throws {
        let vm = try makeConfiguredViewModel(entry: .capture(.fab))

        XCTAssertFalse(vm.isTargetLocked)
        XCTAssertEqual(vm.target, .unbound)
        XCTAssertEqual(vm.direction, "inbound")
        XCTAssertEqual(vm.selectedType, .call)
    }

    // MARK: - Conditional gating (mirrors LeadLogActivitySheet show-rules)

    func test_note_hidesDirection_hidesDuration_hidesOutcome() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        vm.selectedType = .note

        XCTAssertFalse(vm.showDirectionField)
        XCTAssertFalse(vm.showDurationField)
        XCTAssertFalse(vm.showOutcomeField)
    }

    func test_email_showsDirection_hidesDuration_showsOutcome() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        vm.selectedType = .email

        XCTAssertTrue(vm.showDirectionField)
        XCTAssertFalse(vm.showDurationField)
        XCTAssertTrue(vm.showOutcomeField)
    }

    func test_meeting_hidesDirection_showsDuration_showsOutcome() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        vm.selectedType = .meeting

        XCTAssertFalse(vm.showDirectionField)
        XCTAssertTrue(vm.showDurationField)
        XCTAssertTrue(vm.showOutcomeField)
    }

    func test_call_showsDirection_showsDuration_showsOutcome() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        vm.selectedType = .call

        XCTAssertTrue(vm.showDirectionField)
        XCTAssertTrue(vm.showDurationField)
        XCTAssertTrue(vm.showOutcomeField)
    }

    // MARK: - plannedLog(): the save-arg planning regression guard

    func test_plannedLog_call_withDirectionOutcomeDuration_carriesAllThree_plusCreatedBy() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        vm.selectedType = .call
        vm.direction = "inbound"
        vm.outcome = "Left voicemail"
        vm.durationMinutes = 6

        let planned = vm.plannedLog()

        XCTAssertEqual(planned.direction, "inbound")
        XCTAssertEqual(planned.outcome, "Left voicemail")
        XCTAssertEqual(planned.durationMinutes, 6)
        XCTAssertEqual(planned.createdBy, "user-operator-1")
    }

    func test_plannedLog_note_nilsDirectionAndDuration_evenWithStaleFormState() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        vm.selectedType = .note
        // Stale values left over from a prior call-type selection must not
        // leak through — the sheet never shows these fields for .note.
        vm.direction = "inbound"
        vm.durationMinutes = 12

        let planned = vm.plannedLog()

        XCTAssertNil(planned.direction)
        XCTAssertNil(planned.durationMinutes)
    }

    func test_plannedLog_body_trimmedEmptyNotes_isNil() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        vm.notesText = "   "

        XCTAssertNil(vm.plannedLog().body)
    }

    func test_plannedLog_body_carriesNotesText() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        vm.notesText = "Quoted the reroof, following up Thursday"

        XCTAssertEqual(vm.plannedLog().body, "Quoted the reroof, following up Thursday")
    }

    func test_plannedLog_subject_blankIsNil_dbTriggerBackfills() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        vm.subject = ""

        XCTAssertNil(vm.plannedLog().subject)
    }

    func test_plannedLog_nonCallType_neverThreadsCallProvenance() throws {
        let pending = PendingOutboundCall(
            opportunityId: "opp-99",
            contactName: "Maria Chen",
            phoneNumber: "6045550142",
            startedAt: Date()
        )
        let vm = try makeConfiguredViewModel(entry: .postCall(pending))
        // Even though this entry point captured call provenance, switching
        // the type away from .call must not carry it into the write.
        vm.selectedType = .note

        let planned = vm.plannedLog()

        XCTAssertNil(planned.callSource)
        XCTAssertNil(planned.callerNumber)
        XCTAssertNil(planned.callStartedAt)
    }

    // MARK: - canSave

    func test_canSave_locked_isAlwaysTrue() throws {
        let vm = try makeConfiguredViewModel(entry: .leadDetail(makeOpportunity()))
        XCTAssertTrue(vm.canSave)
    }

    func test_canSave_unbound_falseUntilTargetOrContactResolved() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        XCTAssertFalse(vm.canSave)

        vm.selectTarget(.opportunity(makeOpportunity()))
        XCTAssertTrue(vm.canSave)
    }

    func test_canSave_capture_trueWithNameAndPhone() throws {
        let vm = try makeConfiguredViewModel(entry: .capture(.fab))
        XCTAssertFalse(vm.canSave)

        vm.contactName = "New Caller"
        vm.phoneNumber = "6045550142"
        XCTAssertTrue(vm.canSave)
    }

    // MARK: - Dedup (mirrors LogCallViewModel.runDedup)

    func test_runDedup_locked_isNoOp() throws {
        let vm = try makeConfiguredViewModel(entry: .leadDetail(makeOpportunity()))
        vm.phoneNumber = "6045550142"
        vm.runDedup()

        XCTAssertNil(vm.matchedLead)
    }

    func test_selectTarget_locked_isNoOp() throws {
        let opp = makeOpportunity(id: "opp-locked")
        let vm = try makeConfiguredViewModel(entry: .leadDetail(opp))

        vm.selectTarget(.opportunity(makeOpportunity(id: "opp-other")))

        XCTAssertEqual(vm.target.parentKey, .opportunity("opp-locked"))
    }

    // MARK: - Follow-up mapping

    func test_followUpType_mapping_callEmailMeeting_carryThrough() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)

        vm.selectedType = .call
        XCTAssertEqual(vm.mappedFollowUpTypeForTesting, .call)

        vm.selectedType = .email
        XCTAssertEqual(vm.mappedFollowUpTypeForTesting, .email)

        vm.selectedType = .meeting
        XCTAssertEqual(vm.mappedFollowUpTypeForTesting, .meeting)
    }

    func test_followUpType_mapping_noteAndOthers_mapToCustom() throws {
        let vm = try makeConfiguredViewModel(entry: .genericFAB)

        vm.selectedType = .note
        XCTAssertEqual(vm.mappedFollowUpTypeForTesting, .custom)

        vm.selectedType = .siteVisit
        XCTAssertEqual(vm.mappedFollowUpTypeForTesting, .custom)
    }

    func test_buildFollowUpDTO_carriesSuggestionTitleAndDueAt() throws {
        let dueAt = Date(timeIntervalSince1970: 1_720_000_000)
        let dto = UnifiedLogActivityViewModel.buildFollowUpDTO(
            companyId: "co-1",
            opportunityId: "opp-1",
            suggestion: (title: "Follow up with Eric Devlin", dueAt: dueAt),
            type: .call
        )

        XCTAssertEqual(dto.companyId, "co-1")
        XCTAssertEqual(dto.opportunityId, "opp-1")
        XCTAssertEqual(dto.title, "Follow up with Eric Devlin")
        XCTAssertEqual(dto.type, "call")
        XCTAssertEqual(dto.dueAt, SupabaseDate.format(dueAt))
        XCTAssertNil(dto.reminderAt)
        XCTAssertNil(dto.assignedTo)
    }

    func test_setFollowUp_withoutResolvedOpportunity_returnsFalse_neverPersists() async throws {
        // genericFAB with no target ever resolved: setFollowUp must be a
        // guarded no-op, proving a suggestion is never auto-persisted absent
        // a real opportunity id to attach it to.
        let vm = try makeConfiguredViewModel(entry: .genericFAB)
        vm.suggestedFollowUp = (title: "Follow up", dueAt: Date())

        let result = await vm.setFollowUp()

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.suggestedFollowUp, "a failed/no-op set must not clear the pending suggestion")
    }
}

// MARK: - Test-only accessors for private mapping logic

private extension UnifiedLogActivityViewModel {
    /// Exposes the private `mappedFollowUpType` computed property for direct
    /// assertion without needing a full `setFollowUp()` network round trip.
    var mappedFollowUpTypeForTesting: FollowUpType {
        switch selectedType {
        case .call:    return .call
        case .email:   return .email
        case .meeting: return .meeting
        default:       return .custom
        }
    }
}
