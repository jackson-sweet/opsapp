//
//  VoiceActivityParserFollowUpTests.swift
//  OPSTests
//
//  Follow-up detection tests for VoiceActivityParser.
//  Uses an injected reference date for deterministic, timezone-stable assertions.
//

import XCTest
@testable import OPS

final class VoiceActivityParserFollowUpTests: XCTestCase {

    /// Fixed reference "now": Tuesday 2026-07-07, 10:00 local.
    private var referenceNow: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 7
        components.hour = 10
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    // MARK: - Helpers

    private func day(_ date: Date) -> Int {
        Calendar.current.component(.weekday, from: date)
    }

    // MARK: - Tests

    func test_callback_tuesday_sets_next_future_tuesday_at_9am() {
        let ref = referenceNow
        let draft = VoiceActivityParser.parse(
            transcription: "called with John, callback Tuesday",
            opportunities: [],
            now: ref
        )

        guard let dueAt = draft.suggestedFollowUpDueAt else {
            XCTFail("Expected a suggested follow-up date")
            return
        }

        // Must be strictly in the future relative to `ref` (roll-forward, not same-day).
        XCTAssertGreaterThan(dueAt, ref)

        // Must land on a Tuesday.
        XCTAssertEqual(Calendar.current.component(.weekday, from: dueAt), 3, "Expected Tuesday (weekday=3)")

        // Must default to 09:00 local (date-only match, no time spoken).
        let comps = Calendar.current.dateComponents([.hour, .minute], from: dueAt)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 0)

        XCTAssertEqual(draft.suggestedFollowUpTitle, "Follow up with John")
    }

    func test_bare_weekday_spoken_on_that_weekday_rolls_to_next_week() {
        // referenceNow itself IS a Tuesday. Speaking "Tuesday" with a cue word
        // on a Tuesday must roll to next week's Tuesday, not today.
        let ref = referenceNow
        let draft = VoiceActivityParser.parse(
            transcription: "follow up Tuesday with the client",
            opportunities: [],
            now: ref
        )

        guard let dueAt = draft.suggestedFollowUpDueAt else {
            XCTFail("Expected a suggested follow-up date")
            return
        }

        XCTAssertGreaterThan(dueAt, ref)
        XCTAssertEqual(Calendar.current.component(.weekday, from: dueAt), 3, "Expected Tuesday (weekday=3)")

        // Confirm it advanced by roughly a week (not merely a few hours forward).
        let daysBetween = Calendar.current.dateComponents([.day], from: ref, to: dueAt).day ?? 0
        XCTAssertGreaterThanOrEqual(daysBetween, 6, "Bare weekday spoken on that same weekday must roll to NEXT week")
    }

    func test_incidental_date_without_cue_makes_no_followup() {
        let draft = VoiceActivityParser.parse(
            transcription: "met him Monday about the deck",
            opportunities: [],
            now: referenceNow
        )

        XCTAssertNil(draft.suggestedFollowUpDueAt)
        XCTAssertNil(draft.suggestedFollowUpTitle)
    }

    func test_follow_up_next_week_produces_future_date_with_generic_title() {
        let ref = referenceNow
        let draft = VoiceActivityParser.parse(
            transcription: "follow up next week",
            opportunities: [],
            now: ref
        )

        guard let dueAt = draft.suggestedFollowUpDueAt else {
            XCTFail("Expected a suggested follow-up date")
            return
        }

        XCTAssertGreaterThan(dueAt, ref)
        // No contact name was parsed, so the title must be the generic fallback.
        XCTAssertEqual(draft.suggestedFollowUpTitle, "Follow up")
    }

    func test_no_date_and_no_cue_leaves_both_fields_nil() {
        let draft = VoiceActivityParser.parse(
            transcription: "site visit went well, roof looks good",
            opportunities: [],
            now: referenceNow
        )

        XCTAssertNil(draft.suggestedFollowUpDueAt)
        XCTAssertNil(draft.suggestedFollowUpTitle)
    }

    /// Confirms adding follow-up detection did not alter pre-existing parse behavior
    /// (type / notes / confidence) for a normal transcript with no follow-up cues.
    func test_existing_parse_behavior_unchanged_for_normal_transcript() {
        let draft = VoiceActivityParser.parse(
            transcription: "called with John, discussed the estimate",
            opportunities: [],
            now: referenceNow
        )

        XCTAssertEqual(draft.type, .call)
        XCTAssertEqual(draft.notes, "The estimate")
        XCTAssertEqual(draft.confidence, .noMatch)
        XCTAssertEqual(draft.parsedContactName, "John")
        XCTAssertNil(draft.suggestedFollowUpDueAt)
        XCTAssertNil(draft.suggestedFollowUpTitle)
    }
}
