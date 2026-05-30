//
//  PhotoPrefetchWarmupPlannerTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class PhotoPrefetchWarmupPlannerTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func testPlanPrioritizesActiveAndTodayProjectsAndCapsPhotos() {
        let now = date(2026, 5, 25)
        let archived = makeProject(
            id: "archive",
            status: .archived,
            start: date(2025, 1, 1),
            end: date(2025, 1, 2),
            photos: ["https://cdn.ops/archive-1.jpg"]
        )
        let today = makeProject(
            id: "today",
            status: .inProgress,
            start: date(2026, 5, 25),
            end: date(2026, 5, 25),
            photos: ["https://cdn.ops/today-1.jpg", "https://cdn.ops/today-2.jpg"]
        )
        let upcoming = makeProject(
            id: "upcoming",
            status: .accepted,
            start: date(2026, 5, 26),
            end: date(2026, 5, 28),
            photos: ["https://cdn.ops/upcoming-1.jpg"]
        )

        let plan = PhotoPrefetchWarmupPlanner.plan(
            projects: [archived, upcoming, today],
            now: now,
            maxProjects: 2,
            maxPhotos: 3
        )

        XCTAssertEqual(plan.map(\.projectId), ["today", "today", "upcoming"])
        XCTAssertEqual(plan.map(\.url), [
            "https://cdn.ops/today-1.jpg",
            "https://cdn.ops/today-2.jpg",
            "https://cdn.ops/upcoming-1.jpg"
        ])
    }

    func testPlannerBuildsLargeDemoPlanUnderTenMilliseconds() {
        let now = date(2026, 5, 25)
        let projects = (0..<500).map { idx in
            makeProject(
                id: "project-\(idx)",
                status: idx % 6 == 0 ? .archived : .inProgress,
                start: date(2026, 5, 25 + (idx % 5)),
                end: date(2026, 5, 25 + (idx % 5)),
                photos: (0..<6).map { "https://cdn.ops/project-\(idx)-\($0).jpg" }
            )
        }

        measure {
            _ = PhotoPrefetchWarmupPlanner.plan(
                projects: projects,
                now: now,
                maxProjects: 12,
                maxPhotos: 24
            )
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeProject(
        id: String,
        status: Status,
        start: Date,
        end: Date,
        photos: [String]
    ) -> Project {
        let project = Project(id: id, title: id, status: status)
        project.startDate = start
        project.endDate = end
        project.setProjectImageURLs(photos)
        return project
    }
}
