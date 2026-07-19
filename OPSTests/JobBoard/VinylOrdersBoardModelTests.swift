//
//  VinylOrdersBoardModelTests.swift
//  OPSTests
//
//  Spec § 4: population (won + active + open vinyl phase only), grouping,
//  and both group sort orders.
//

import XCTest
@testable import OPS

final class VinylOrdersBoardModelTests: XCTestCase {

    private func input(
        id: String,
        title: String? = nil,
        status: Status = .inProgress,
        starts: [Date?] = [nil],
        hasIncompleteVinyl: Bool = true,
        createdAt: Date? = nil,
        ordered: Bool = false,
        orderedAt: Date? = nil
    ) -> VinylBoardRowInput {
        VinylBoardRowInput(
            projectId: id,
            title: title ?? id,
            status: status,
            vinylTaskStartDates: starts,
            hasIncompleteVinylTask: hasIncompleteVinyl,
            createdAt: createdAt,
            ordered: ordered,
            orderedAt: orderedAt
        )
    }

    private func date(_ day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(1_752_000_000 + day * 86_400))
    }

    // MARK: - Population

    func testExcludesEveryNonActiveStatus() {
        let excluded: [Status] = [.rfq, .estimated, .completed, .closed, .archived]
        let inputs = excluded.map { input(id: "p-\($0.rawValue)", status: $0) }
            + [input(id: "p-accepted", status: .accepted), input(id: "p-active", status: .inProgress)]

        let (toOrder, ordered) = VinylOrdersBoardModel.rows(from: inputs)

        XCTAssertEqual(Set(toOrder.map(\.projectId)), Set(["p-accepted", "p-active"]))
        XCTAssertTrue(ordered.isEmpty)
    }

    /// A job whose vinyl tasks are ALL completed leaves the board even when it
    /// was marked ordered — the vinyl phase is done, this is not an archive.
    func testAllVinylTasksCompletedDropsEvenWhenOrdered() {
        let inputs = [
            input(id: "p-open", hasIncompleteVinyl: true, ordered: true, orderedAt: date(1)),
            input(id: "p-done", hasIncompleteVinyl: false, ordered: true, orderedAt: date(2)),
            input(id: "p-done-unordered", hasIncompleteVinyl: false)
        ]

        let (toOrder, ordered) = VinylOrdersBoardModel.rows(from: inputs)

        XCTAssertTrue(toOrder.isEmpty)
        XCTAssertEqual(ordered.map(\.projectId), ["p-open"])
    }

    // MARK: - TO ORDER sort

    func testScheduledSortAscendingWithUnscheduledAfter() {
        let inputs = [
            input(id: "later", starts: [date(20)]),
            input(id: "unscheduled", starts: [nil]),
            input(id: "soonest", starts: [date(5), date(30)]),   // min wins
            input(id: "middle", starts: [nil, date(10)])          // nil ignored when a date exists
        ]

        let (toOrder, _) = VinylOrdersBoardModel.rows(from: inputs)

        XCTAssertEqual(toOrder.map(\.projectId), ["soonest", "middle", "later", "unscheduled"])
    }

    func testUnscheduledTieBrokenByCreatedAtDescendingThenTitle() {
        let inputs = [
            input(id: "old", title: "ALPHA", starts: [nil], createdAt: date(1)),
            input(id: "new", title: "ZULU", starts: [nil], createdAt: date(9)),
            input(id: "b", title: "BRAVO", starts: [nil], createdAt: nil),
            input(id: "a", title: "ANCHOR", starts: [nil], createdAt: nil)
        ]

        let (toOrder, _) = VinylOrdersBoardModel.rows(from: inputs)

        XCTAssertEqual(toOrder.map(\.projectId), ["new", "old", "a", "b"])
    }

    // MARK: - ORDERED sort

    func testOrderedSortedByOrderedAtDescendingNilLast() {
        let inputs = [
            input(id: "oldest", ordered: true, orderedAt: date(1)),
            input(id: "newest", ordered: true, orderedAt: date(9)),
            input(id: "undated", ordered: true, orderedAt: nil),
            input(id: "middle", ordered: true, orderedAt: date(5))
        ]

        let (toOrder, ordered) = VinylOrdersBoardModel.rows(from: inputs)

        XCTAssertTrue(toOrder.isEmpty)
        XCTAssertEqual(ordered.map(\.projectId), ["newest", "middle", "oldest", "undated"])
    }

    func testGroupingSplitsOnOrderedFlag() {
        let inputs = [
            input(id: "todo", ordered: false),
            input(id: "done", ordered: true, orderedAt: date(3))
        ]

        let (toOrder, ordered) = VinylOrdersBoardModel.rows(from: inputs)

        XCTAssertEqual(toOrder.map(\.projectId), ["todo"])
        XCTAssertEqual(ordered.map(\.projectId), ["done"])
    }
}
