//
//  ProjectPhotoTaskIndexTests.swift
//  OPSTests
//
//  Bug a290934f — every surface asks "which task is this photo of?" through one
//  index, so the answer is proven once, here.
//
//  The rules that matter are the negative ones. A link that names a task this
//  project does not have — deleted, cancelled, or belonging to another job —
//  must read as NO link, not as a badge nobody can act on and a strip nobody
//  can open. That is the same rule the server's write guard enforces, and the
//  two have to agree or the UI offers writes the database refuses.
//

import SwiftData
import SwiftUI
import XCTest
@testable import OPS

@MainActor
final class ProjectPhotoTaskIndexTests: XCTestCase {
    private var container: ModelContainer!
    private let projectID = "e3cf8105-3e83-4126-9aa1-16ebcfd096f5"
    private let companyID = "a612edc0-5c18-4c4d-af97-55b9410dd077"
    private let uploaderID = "283d49df-90a1-4abb-b94c-3e9f17f02c0d"

    override func setUpWithError() throws {
        let schema = Schema([Project.self, ProjectTask.self, TaskType.self, TaskTypeReminder.self,
            TaskReminder.self, User.self, Client.self, SubClient.self, ProjectNote.self, ProjectPhoto.self,
            SyncOperation.self, ProjectVinylOrderMarker.self, ProjectPrimaryContactSelection.self, Opportunity.self])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func task(
        id: String,
        title: String,
        order: Int,
        status: TaskStatus = .active,
        deleted: Bool = false
    ) -> ProjectTask {
        let task = ProjectTask(
            id: id,
            projectId: projectID,
            taskTypeId: "type-\(order)",
            companyId: companyID,
            status: status
        )
        task.customTitle = title
        task.displayOrder = order
        if deleted { task.deletedAt = Date() }
        return task
    }

    private func photo(
        url: String,
        taskID: String?,
        createdAt: Date,
        deleted: Bool = false,
        thumbnail: String? = nil
    ) -> ProjectPhoto {
        let photo = ProjectPhoto(
            id: UUID().uuidString.lowercased(),
            projectId: projectID,
            companyId: companyID,
            url: url,
            thumbnailURL: thumbnail,
            source: "in_progress",
            taskId: taskID,
            uploadedBy: uploaderID,
            createdAt: createdAt
        )
        if deleted { photo.deletedAt = Date() }
        return photo
    }

    // MARK: - Resolution

    func testAPhotoResolvesToTheLiveTaskItNames() {
        let deck = task(id: "2b0004b3-4696-49c5-9c74-8bd65bc66c39", title: "Deck frame", order: 0)
        let index = ProjectPhotoTaskIndex(
            photos: [photo(url: "https://cdn.example/a.jpg", taskID: deck.id.uppercased(), createdAt: Date())],
            tasks: [deck]
        )

        let resolved = index.task(forURL: "https://cdn.example/a.jpg")
        XCTAssertEqual(resolved?.id, deck.id.lowercased(), "Casing never decides whether a link resolves")
        XCTAssertEqual(resolved?.title, deck.displayTitle)
        XCTAssertEqual(index.urls(forTaskID: deck.id), ["https://cdn.example/a.jpg"])
        XCTAssertTrue(index.hasAnyTaggedPhoto)
    }

    func testAPhotoWithNoLinkResolvesToNothing() {
        let deck = task(id: "2b0004b3-4696-49c5-9c74-8bd65bc66c39", title: "Deck frame", order: 0)
        let index = ProjectPhotoTaskIndex(
            photos: [photo(url: "https://cdn.example/a.jpg", taskID: nil, createdAt: Date())],
            tasks: [deck]
        )

        XCTAssertNil(index.task(forURL: "https://cdn.example/a.jpg"))
        XCTAssertTrue(index.urls(forTaskID: deck.id).isEmpty)
        XCTAssertFalse(index.hasAnyTaggedPhoto)
    }

    func testALinkNamingADeletedOrCancelledTaskReadsAsUnlinked() {
        let deleted = task(id: "11111111-1111-4111-8111-111111111111", title: "Removed", order: 0, deleted: true)
        let cancelled = task(id: "22222222-2222-4222-8222-222222222222", title: "Called off", order: 1, status: .cancelled)
        let index = ProjectPhotoTaskIndex(
            photos: [
                photo(url: "https://cdn.example/a.jpg", taskID: deleted.id, createdAt: Date()),
                photo(url: "https://cdn.example/b.jpg", taskID: cancelled.id, createdAt: Date())
            ],
            tasks: [deleted, cancelled]
        )

        XCTAssertNil(index.task(forURL: "https://cdn.example/a.jpg"))
        XCTAssertNil(index.task(forURL: "https://cdn.example/b.jpg"))
        XCTAssertTrue(index.tasks.isEmpty, "Neither task is assignable, so neither is offered")
        XCTAssertFalse(index.hasAnyTaggedPhoto)
    }

    func testALinkNamingAnotherProjectsTaskReadsAsUnlinked() {
        let deck = task(id: "2b0004b3-4696-49c5-9c74-8bd65bc66c39", title: "Deck frame", order: 0)
        let index = ProjectPhotoTaskIndex(
            photos: [photo(
                url: "https://cdn.example/a.jpg",
                taskID: "ebf1cb4d-056c-4317-b54d-d2816d542f9f",
                createdAt: Date()
            )],
            tasks: [deck]
        )

        XCTAssertNil(index.task(forURL: "https://cdn.example/a.jpg"))
        XCTAssertTrue(index.urls(forTaskID: deck.id).isEmpty)
    }

    func testASoftDeletedPhotoIsNotPartOfTheTasksEvidence() {
        let deck = task(id: "2b0004b3-4696-49c5-9c74-8bd65bc66c39", title: "Deck frame", order: 0)
        let index = ProjectPhotoTaskIndex(
            photos: [
                photo(url: "https://cdn.example/live.jpg", taskID: deck.id, createdAt: Date()),
                photo(url: "https://cdn.example/gone.jpg", taskID: deck.id, createdAt: Date(), deleted: true)
            ],
            tasks: [deck]
        )

        XCTAssertEqual(index.urls(forTaskID: deck.id), ["https://cdn.example/live.jpg"])
        XCTAssertNil(index.task(forURL: "https://cdn.example/gone.jpg"))
    }

    // MARK: - Order

    func testATasksPhotosComeBackNewestFirst() {
        let deck = task(id: "2b0004b3-4696-49c5-9c74-8bd65bc66c39", title: "Deck frame", order: 0)
        let base = Date(timeIntervalSince1970: 3_000_000)
        let index = ProjectPhotoTaskIndex(
            photos: [
                photo(url: "https://cdn.example/oldest.jpg", taskID: deck.id, createdAt: base),
                photo(url: "https://cdn.example/newest.jpg", taskID: deck.id, createdAt: base.addingTimeInterval(600)),
                photo(url: "https://cdn.example/middle.jpg", taskID: deck.id, createdAt: base.addingTimeInterval(300))
            ],
            tasks: [deck]
        )

        XCTAssertEqual(
            index.urls(forTaskID: deck.id),
            [
                "https://cdn.example/newest.jpg",
                "https://cdn.example/middle.jpg",
                "https://cdn.example/oldest.jpg"
            ],
            "The photo someone just took is the one they are looking for"
        )
    }

    func testTasksAreOfferedInTheProjectsOwnOrder() {
        let second = task(id: "22222222-2222-4222-8222-222222222222", title: "Railing", order: 5)
        let first = task(id: "11111111-1111-4111-8111-111111111111", title: "Deck frame", order: 1)
        let index = ProjectPhotoTaskIndex(photos: [], tasks: [second, first])

        XCTAssertEqual(index.tasks.map(\.title), [first.displayTitle, second.displayTitle])
    }

    // MARK: - Thumbnails

    func testThumbnailsRideAlongForTheStripsThatDrawThem() {
        let deck = task(id: "2b0004b3-4696-49c5-9c74-8bd65bc66c39", title: "Deck frame", order: 0)
        let index = ProjectPhotoTaskIndex(
            photos: [
                photo(
                    url: "https://cdn.example/a.jpg",
                    taskID: deck.id,
                    createdAt: Date(),
                    thumbnail: "https://cdn.example/a-thumb.jpg"
                ),
                photo(url: "https://cdn.example/b.jpg", taskID: deck.id, createdAt: Date(), thumbnail: "")
            ],
            tasks: [deck]
        )

        XCTAssertEqual(index.thumbnails["https://cdn.example/a.jpg"], "https://cdn.example/a-thumb.jpg")
        XCTAssertNil(index.thumbnails["https://cdn.example/b.jpg"], "An empty thumbnail is no thumbnail")
    }

    // MARK: - Strip model

    func testTheSectionStripShowsEveryPhotoAndNeverOverflows() {
        let urls = (0..<9).map { "https://cdn.example/\($0).jpg" }
        let model = TaskPhotoStripModel(urls: urls, limit: TaskPhotoStrip.Size.section.limit)

        XCTAssertEqual(model.visibleURLs, urls, "The section strip scrolls as far as the work goes")
        XCTAssertEqual(model.overflowCount, 0)
        XCTAssertFalse(model.isEmpty)
    }

    func testTheCompactStripCapsAtFourSlotsWithTheLastCountingTheRest() {
        let urls = (0..<9).map { "https://cdn.example/\($0).jpg" }
        let model = TaskPhotoStripModel(urls: urls, limit: TaskPhotoStrip.Size.compact.limit)

        XCTAssertEqual(model.visibleURLs.count, 3, "Three tiles plus the +N tile fills the four slots")
        XCTAssertEqual(model.visibleURLs, Array(urls.prefix(3)))
        XCTAssertEqual(model.overflowCount, 6, "The count stands for every photo it replaced, including its own slot")
    }

    func testTheCompactStripShowsAllFourWhenThereAreExactlyFour() {
        let urls = (0..<4).map { "https://cdn.example/\($0).jpg" }
        let model = TaskPhotoStripModel(urls: urls, limit: TaskPhotoStrip.Size.compact.limit)

        XCTAssertEqual(model.visibleURLs.count, 4, "A +1 tile standing in for one photo would be absurd")
        XCTAssertEqual(model.overflowCount, 0)
    }

    func testAnEmptyStripIsEmpty() {
        let model = TaskPhotoStripModel(urls: [], limit: TaskPhotoStrip.Size.compact.limit)
        XCTAssertTrue(model.isEmpty)
        XCTAssertEqual(model.overflowCount, 0)
    }

    // MARK: - Viewer availability

    func testTheViewerOffersTheTaskActionOnlyWhenTheServerWouldAcceptTheWrite() {
        let uploader = ProjectPhotoUploaderAttribution.known(uploaderID)

        XCTAssertTrue(
            AssignTaskAvailability.canAssign(
                hasSyncedRow: true, hasProjectTasks: true, uploader: uploader,
                currentUserID: uploaderID, hasFullProjectEdit: false
            ),
            "A crew member may always tag their own photo — the same rule that lets them delete it"
        )
        XCTAssertTrue(
            AssignTaskAvailability.canAssign(
                hasSyncedRow: true, hasProjectTasks: true, uploader: uploader,
                currentUserID: "11111111-1111-4111-8111-111111111111", hasFullProjectEdit: true
            ),
            "projects.edit at scope all tags any company photo"
        )
        XCTAssertFalse(
            AssignTaskAvailability.canAssign(
                hasSyncedRow: true, hasProjectTasks: true, uploader: uploader,
                currentUserID: "11111111-1111-4111-8111-111111111111", hasFullProjectEdit: false
            ),
            "Someone else's photo without the admin grant is a write the server refuses"
        )
        XCTAssertFalse(
            AssignTaskAvailability.canAssign(
                hasSyncedRow: false, hasProjectTasks: true, uploader: .unattributed,
                currentUserID: uploaderID, hasFullProjectEdit: true
            ),
            "A legacy CSV url has no project_photos row to carry the link"
        )
        XCTAssertFalse(
            AssignTaskAvailability.canAssign(
                hasSyncedRow: true, hasProjectTasks: false, uploader: uploader,
                currentUserID: uploaderID, hasFullProjectEdit: true
            ),
            "A project with no tasks has nothing to assign to"
        )
        XCTAssertFalse(
            AssignTaskAvailability.canAssign(
                hasSyncedRow: true, hasProjectTasks: true, uploader: .unmatchable,
                currentUserID: uploaderID, hasFullProjectEdit: false
            ),
            "A server-written 'system' uploader matches no operator"
        )
    }
}
