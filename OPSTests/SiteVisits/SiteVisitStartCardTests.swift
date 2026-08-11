import XCTest
@testable import OPS

/// START card lifecycle: who gets a card, when it appears, and how dismissal
/// behaves (per-visit, per-day, kills the card only — never the pushes).
final class SiteVisitStartCardTests: XCTestCase {
    private let companyId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private let me = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    private let mate = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 7))!
    }

    private func visit(
        id: String = UUID().uuidString.lowercased(),
        status: SiteVisitStatus = .scheduled,
        booked: Bool = true,
        assignees: [String]? = nil,
        hour: Int = 10,
        dayOffset: Int = 0
    ) -> SiteVisit {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: now)!
        let visit = SiteVisit(
            id: id,
            opportunityId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            companyId: companyId,
            status: status,
            scheduledAt: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!,
            durationMinutes: 60,
            assigneeIds: assignees ?? [me],
            createdBy: me
        )
        if booked {
            visit.bookedAt = now.addingTimeInterval(-86_400)
        }
        return visit
    }

    private func freshStore() -> SiteVisitStartCardStore {
        let defaults = UserDefaults(suiteName: "start-card-tests-\(UUID().uuidString)")!
        return SiteVisitStartCardStore(defaults: defaults, calendar: calendar)
    }

    // MARK: - Candidates

    func testTodaysBookedAssignedVisitsGetCardsEarliestFirst() {
        let early = visit(hour: 9)
        let late = visit(hour: 14)
        let cards = SiteVisitStartCardCandidates.resolve(
            visits: [late, early],
            userId: me,
            store: freshStore(),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(cards.map(\.id), [early.id, late.id])
    }

    func testOtherDaysWalkUpsStartedAndUnassignedGetNoCard() {
        let tomorrow = visit(dayOffset: 1)
        let walkUp = visit(booked: false)
        let started = visit(status: .inProgress)
        let cancelled = visit(status: .cancelled)
        let theirs = visit(assignees: [mate])

        let cards = SiteVisitStartCardCandidates.resolve(
            visits: [tomorrow, walkUp, started, cancelled, theirs],
            userId: me,
            store: freshStore(),
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(cards.isEmpty)
    }

    func testCardShowsFromTheMorningEvenBeforeTheSlot() {
        // 7:00 now, visit at 10:00 — the card is a standing readiness surface,
        // not a fire-time alarm (the pushes own timing).
        let cards = SiteVisitStartCardCandidates.resolve(
            visits: [visit(hour: 10)],
            userId: me,
            store: freshStore(),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(cards.count, 1)
    }

    // MARK: - Dismissal

    func testDismissalIsPerVisitAndKillsOnlyThatCard() {
        let store = freshStore()
        let first = visit(hour: 9)
        let second = visit(hour: 14)

        store.dismiss(visitId: first.id, day: now)
        let cards = SiteVisitStartCardCandidates.resolve(
            visits: [first, second],
            userId: me,
            store: store,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(cards.map(\.id), [second.id])
    }

    func testDismissalExpiresWithTheDay() {
        let store = freshStore()
        let visit = visit(hour: 9)
        store.dismiss(visitId: visit.id, day: now)

        XCTAssertTrue(store.isDismissed(visitId: visit.id, day: now))
        let nextDay = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertFalse(store.isDismissed(visitId: visit.id, day: nextDay))
    }
}
