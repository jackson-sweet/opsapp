//
//  LogActivityViewModelTests.swift
//  OPSTests
//
//  Regression: `LogActivityViewModel.save()` used to hardcode
//  subject/direction/outcome/duration to nil in its CreateActivityDTO,
//  silently discarding whatever the operator typed into the Log Activity
//  sheet, and stamped no `created_by` at all. `plannedLog()` is the pure
//  extraction of that decision — these tests prove it now carries every
//  field the sheet collected, without touching the network or SwiftData.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class LogActivityViewModelTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Opportunity.self, User.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeViewModel() throws -> LogActivityViewModel {
        let container = try makeContainer()
        let vm = LogActivityViewModel()
        vm.setup(companyId: "co-1", userId: "user-operator-1", modelContext: container.mainContext)
        return vm
    }

    // MARK: - The regression: call with direction/outcome/duration set

    func test_plannedLog_callWithDirectionOutcomeDuration_carriesAllThree_notNil() throws {
        let vm = try makeViewModel()
        vm.selectedType = .call
        vm.direction = "inbound"
        vm.outcome = "Left voicemail"
        vm.durationMinutes = 6

        let planned = vm.plannedLog()

        XCTAssertEqual(planned.direction, "inbound")
        XCTAssertEqual(planned.outcome, "Left voicemail")
        XCTAssertEqual(planned.durationMinutes, 6)
    }

    // MARK: - createdBy is stamped from the operator's users.id

    func test_plannedLog_createdBy_isOperatorUsersId() throws {
        let vm = try makeViewModel()
        vm.selectedType = .call

        let planned = vm.plannedLog()

        XCTAssertEqual(planned.createdBy, "user-operator-1")
    }

    // MARK: - subject always nil (DB trigger backfills)

    func test_plannedLog_subject_alwaysNil() throws {
        let vm = try makeViewModel()
        vm.selectedType = .call
        vm.direction = "outbound"
        vm.outcome = "Booked estimate"
        vm.durationMinutes = 12

        XCTAssertNil(vm.plannedLog().subject)
    }

    // MARK: - body carries the notes field (trimmed-empty → nil)

    func test_plannedLog_body_carriesNotesText() throws {
        let vm = try makeViewModel()
        vm.notesText = "Quoted the reroof, following up Thursday"

        XCTAssertEqual(vm.plannedLog().body, "Quoted the reroof, following up Thursday")
    }

    func test_plannedLog_body_emptyNotes_isNil() throws {
        let vm = try makeViewModel()
        vm.notesText = ""

        XCTAssertNil(vm.plannedLog().body)
    }

    // MARK: - direction/duration are gated on the type's visible fields

    func test_plannedLog_note_hidesDirectionAndDuration() throws {
        let vm = try makeViewModel()
        vm.selectedType = .note
        // Even if stale form state carries a leftover value from a prior
        // call-type selection, a note must not report direction/duration —
        // the sheet never showed those fields for `.note`.
        vm.direction = "inbound"
        vm.durationMinutes = 6

        let planned = vm.plannedLog()

        XCTAssertNil(planned.direction)
        XCTAssertNil(planned.durationMinutes)
    }

    func test_plannedLog_email_showsDirection_hidesDuration() throws {
        let vm = try makeViewModel()
        vm.selectedType = .email
        vm.direction = "outbound"
        vm.durationMinutes = 6

        let planned = vm.plannedLog()

        XCTAssertEqual(planned.direction, "outbound")
        XCTAssertNil(planned.durationMinutes)
    }

    func test_plannedLog_meeting_hidesDirection_showsDuration() throws {
        let vm = try makeViewModel()
        vm.selectedType = .meeting
        vm.direction = "inbound"
        vm.durationMinutes = 30

        let planned = vm.plannedLog()

        XCTAssertNil(planned.direction)
        XCTAssertEqual(planned.durationMinutes, 30)
    }

    // MARK: - type is carried through unchanged

    func test_plannedLog_type_matchesSelectedType() throws {
        let vm = try makeViewModel()
        vm.selectedType = .meeting

        XCTAssertEqual(vm.plannedLog().type, .meeting)
    }
}
