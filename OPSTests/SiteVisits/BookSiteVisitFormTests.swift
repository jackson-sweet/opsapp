import XCTest
@testable import OPS

/// The booking sheet's decision core, kept pure so every rule is provable
/// without rendering: validation, the untouched-heads-up = no-override rule,
/// reschedule's send-only-what-changed contract, and the chip option sets.
final class BookSiteVisitFormTests: XCTestCase {
    private let bookerId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    private let mateId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    private let calendar = Calendar(identifier: .gregorian)

    private var now: Date { Date(timeIntervalSince1970: 1_790_000_000) } // fixed clock

    // MARK: - Create mode

    func testCreateDefaultsToBookerSixtyMinutesAndSettingsLead() {
        let form = BookSiteVisitForm.create(
            bookerId: bookerId,
            defaultHeadsUpMinutes: 45,
            startingAt: futureDate(hour: 10)
        )

        XCTAssertEqual(form.durationMinutes, 60)
        XCTAssertEqual(form.assigneeIds, [bookerId])
        XCTAssertEqual(form.headsUpMinutes, 45)
        XCTAssertFalse(form.headsUpTouched)
    }

    func testCreateParamsOmitAssigneesWhenOnlyBookerGoes() {
        let when = futureDate(hour: 10)
        let form = BookSiteVisitForm.create(
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30,
            startingAt: when
        )

        let params = form.createIntent()

        XCTAssertEqual(params.scheduledAt, when)
        XCTAssertEqual(params.durationMinutes, 60)
        XCTAssertNil(params.assigneeIds, "booker-only defaults stay server-side")
        XCTAssertNil(params.reminderLeadMinutes, "untouched heads-up follows each assignee's own default")
    }

    func testCreateParamsCarryExplicitCrewAndTouchedHeadsUp() {
        var form = BookSiteVisitForm.create(
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30,
            startingAt: futureDate(hour: 10)
        )
        form.setAssignees([bookerId, mateId])
        form.selectHeadsUp(60)

        let params = form.createIntent()

        XCTAssertEqual(params.assigneeIds, [bookerId, mateId].sorted())
        XCTAssertEqual(params.reminderLeadMinutes, 60)
    }

    func testDeselectingEveryoneFallsBackToBooker() {
        var form = BookSiteVisitForm.create(
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30,
            startingAt: futureDate(hour: 10)
        )
        form.setAssignees([])

        XCTAssertEqual(form.assigneeIds, [bookerId], "WHO'S GOING can never be empty")
    }

    func testPastTimeIsInvalidInCreateMode() {
        var form = BookSiteVisitForm.create(
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30,
            startingAt: futureDate(hour: 10)
        )
        XCTAssertTrue(form.isValid(now: now))

        form.setDateAndTime(mergedDate(daysFromNow: -1, hour: 10))
        XCTAssertFalse(form.isValid(now: now))
    }

    // MARK: - Reschedule mode

    private func existingSnapshot(
        hour: Int = 9,
        duration: Int = 60,
        assignees: [String]? = nil,
        reminder: Int? = nil
    ) -> BookSiteVisitForm.BookingSnapshot {
        BookSiteVisitForm.BookingSnapshot(
            siteVisitId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            scheduledAt: mergedDate(daysFromNow: 2, hour: hour),
            durationMinutes: duration,
            assigneeIds: assignees ?? [bookerId],
            reminderLeadMinutes: reminder
        )
    }

    func testReschedulePrefillsFromExistingBooking() {
        let existing = existingSnapshot(hour: 9, duration: 120, assignees: [bookerId, mateId], reminder: 15)
        let form = BookSiteVisitForm.reschedule(
            existing: existing,
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30
        )

        XCTAssertEqual(form.mergedDate(), existing.scheduledAt)
        XCTAssertEqual(form.durationMinutes, 120)
        XCTAssertEqual(form.assigneeIds, Set([bookerId, mateId]))
        XCTAssertEqual(form.headsUpMinutes, 15)
    }

    func testUntouchedRescheduleSendsNothing() {
        let form = BookSiteVisitForm.reschedule(
            existing: existingSnapshot(),
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30
        )

        let intent = form.rescheduleIntent()

        XCTAssertNil(intent.scheduledAt)
        XCTAssertNil(intent.durationMinutes)
        XCTAssertNil(intent.assigneeIds)
        XCTAssertEqual(intent.reminderOverride, .keep)
        XCTAssertFalse(intent.hasChanges)
    }

    func testRescheduleSendsOnlyTheChangedFields() {
        var form = BookSiteVisitForm.reschedule(
            existing: existingSnapshot(hour: 9, duration: 60),
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30
        )
        let newTime = mergedDate(daysFromNow: 3, hour: 14)
        form.setDateAndTime(newTime)

        let intent = form.rescheduleIntent()

        XCTAssertEqual(intent.scheduledAt, newTime)
        XCTAssertNil(intent.durationMinutes, "unchanged fields ride the NULL-keeps contract")
        XCTAssertNil(intent.assigneeIds)
        XCTAssertEqual(intent.reminderOverride, .keep)
        XCTAssertTrue(intent.hasChanges)
    }

    func testSeedDefaultLandsOnlyWhileUntouched() {
        var form = BookSiteVisitForm.create(
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30,
            startingAt: futureDate(hour: 10)
        )
        form.seedDefaultHeadsUp(45)
        XCTAssertEqual(form.headsUpMinutes, 45)
        XCTAssertFalse(form.headsUpTouched)

        form.selectHeadsUp(60)
        form.seedDefaultHeadsUp(15)
        XCTAssertEqual(form.headsUpMinutes, 60, "a touched row never moves under the operator")
    }

    func testSeedDefaultNeverDisplacesExistingOverride() {
        var form = BookSiteVisitForm.reschedule(
            existing: existingSnapshot(reminder: 15),
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30
        )
        form.seedDefaultHeadsUp(45)
        XCTAssertEqual(form.headsUpMinutes, 15)
    }

    func testRescheduleTouchedHeadsUpBecomesOverride() {
        var form = BookSiteVisitForm.reschedule(
            existing: existingSnapshot(reminder: nil),
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30
        )
        form.selectHeadsUp(120)

        XCTAssertEqual(form.rescheduleIntent().reminderOverride, .set(120))
    }

    func testRescheduleKeepsPastTimeValidWhenTimeUntouched() {
        // The appointment time already passed; changing only the crew must not
        // trip time validation — the RPC only validates a provided time.
        let past = BookSiteVisitForm.BookingSnapshot(
            siteVisitId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            scheduledAt: mergedDate(daysFromNow: -1, hour: 9),
            durationMinutes: 60,
            assigneeIds: [bookerId],
            reminderLeadMinutes: nil
        )
        var form = BookSiteVisitForm.reschedule(
            existing: past,
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30
        )
        form.setAssignees([bookerId, mateId])

        XCTAssertTrue(form.isValid(now: now))
        XCTAssertNil(form.rescheduleIntent().scheduledAt)
    }

    // MARK: - Chip option sets

    func testDurationOptionsArePresetsPlusCurrentValue() {
        let form = BookSiteVisitForm.reschedule(
            existing: existingSnapshot(duration: 45),
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30
        )

        XCTAssertEqual(form.durationOptions, [30, 45, 60, 90, 120, 240])
    }

    func testHeadsUpOptionsArePresetsPlusCurrentOverride() {
        let form = BookSiteVisitForm.reschedule(
            existing: existingSnapshot(reminder: 10),
            bookerId: bookerId,
            defaultHeadsUpMinutes: 30
        )

        XCTAssertEqual(form.headsUpOptions, [10, 15, 30, 60, 120])
    }

    func testDurationLabelsReadInTradeUnits() {
        XCTAssertEqual(BookSiteVisitForm.durationLabel(30), "30 MIN")
        XCTAssertEqual(BookSiteVisitForm.durationLabel(60), "1 HR")
        XCTAssertEqual(BookSiteVisitForm.durationLabel(90), "90 MIN")
        XCTAssertEqual(BookSiteVisitForm.durationLabel(120), "2 HR")
        XCTAssertEqual(BookSiteVisitForm.durationLabel(240), "4 HR")
    }

    // MARK: - Helpers

    private func futureDate(hour: Int) -> Date {
        mergedDate(daysFromNow: 1, hour: hour)
    }

    private func mergedDate(daysFromNow: Int, hour: Int) -> Date {
        let base = calendar.date(byAdding: .day, value: daysFromNow, to: now)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }
}
