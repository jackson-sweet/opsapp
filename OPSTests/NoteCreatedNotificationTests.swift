//
//  NoteCreatedNotificationTests.swift
//  OPSTests
//
//  Four notification surfaces — project-note @mention, project-note team
//  broadcast, photo-comment @mention, photo-comment photo owner — all created
//  their rail rows with direct `notifications` INSERTs. The 2026-07-15
//  notification-creation hardening revoked app-role INSERT on that table, so
//  every one of them 42501'd and went silently dead: the operator posted, the
//  push may or may not have gone out, and nothing ever reached the rail.
//
//  All four now cross ONE narrow SECURITY DEFINER RPC (`notify_note_created`),
//  which derives the author, the mentions, the photo owner, and the assigned
//  crew from the stored note row and renders the rail copy server-side.
//
//  What these tests pin:
//    1. Both view models reach the RPC exactly once per created note, with
//       that note's id — no per-recipient loop survives on either surface.
//    2. The push lanes are built from the RPC's returned fanout and nothing
//       else. Push targeting used to be computed independently of the rail
//       rows, so the two could disagree about who was told; now a push can
//       only reach someone the server actually wrote a rail row for.
//    3. Each surface owns exactly its own lanes: a plain note never opens the
//       photo-owner lane, a photo comment never opens the crew broadcast.
//    4. A failed RPC is survivable and silent — no rail row means no push.
//
//  A note on what is NOT driven here: no test hands a NON-empty fanout to
//  `dispatchNoteCreatedNotifications`. `OneSignalService` has no test seam and
//  its send path (`sendViaOpsWeb`) posts to the live ops-web push endpoint, so
//  a unit test that exercised a populated fanout would send real pushes to
//  real operators. The push targeting is therefore asserted on the pure plan
//  types instead, which is where the branching actually lives — the dispatch
//  funcs read their recipients from a plan and from nowhere else, so a lane
//  the plan does not open cannot be sent.
//

import SwiftData
import XCTest
@testable import OPS

/// Server fanout fixture. Defaults to "nobody received a new rail row", which
/// is the only shape safe to drive all the way through a dispatch call — it
/// opens no push lane. File scope (not a member of the `@MainActor` test case)
/// so the non-isolated spy below can call it from a property initializer.
private func makeFanout(
    kind: String = "project_note",
    mentionUserIds: [String] = [],
    photoOwnerId: String? = nil,
    teamUserIds: [String] = []
) -> NotificationRepository.NoteCreatedFanout {
    NotificationRepository.NoteCreatedFanout(
        kind: kind,
        mentionUserIds: mentionUserIds,
        photoOwnerId: photoOwnerId,
        teamUserIds: teamUserIds
    )
}

@MainActor
final class NoteCreatedNotificationTests: XCTestCase {

    // MARK: - Spy

    /// Records every note id reported to `notify_note_created`, and hands back
    /// a canned fanout (or a transport failure). Both view models call the RPC
    /// sequentially from the main actor, so plain storage is race-free.
    private final class NoteCreatedSpy: NoteCreatedNotifying {
        private(set) var noteIds: [String] = []
        var fanout = makeFanout()
        var transportError: Error?

        func notifyNoteCreated(
            noteId: String
        ) async throws -> NotificationRepository.NoteCreatedFanout {
            noteIds.append(noteId)
            if let transportError {
                throw transportError
            }
            return fanout
        }
    }

    // MARK: - 1. One RPC call per created note, carrying that note's id

    /// The project-note surface used to run two separate dispatches (mentions,
    /// then the crew broadcast), each looping a `notifications` INSERT per
    /// recipient. One note is now one server call.
    func test_projectNotesDispatchReachesTheRpcOnceWithTheCreatedNoteId() async {
        let spy = NoteCreatedSpy()
        let viewModel = ProjectNotesViewModel(projectId: "project-1")
        viewModel.noteSyncer = spy

        await viewModel.dispatchNoteCreatedNotifications(
            noteId: "note-1",
            noteText: "Rebar delivered",
            attachmentURLs: []
        )

        XCTAssertEqual(
            spy.noteIds,
            ["note-1"],
            "One created note must produce exactly one notify_note_created call, carrying that note's id"
        )
    }

    /// Same contract on the photo-comment surface, which used to run a mention
    /// loop plus a separate owner dispatch that queried `project_photos` for
    /// `uploaded_by` on its own.
    func test_photoCommentsDispatchReachesTheRpcOnceWithTheCreatedNoteId() async {
        let spy = NoteCreatedSpy()
        let viewModel = makePhotoCommentsViewModel()
        viewModel.noteSyncer = spy

        await viewModel.dispatchNoteCreatedNotifications(
            noteId: "comment-1",
            noteText: "Check the flashing here"
        )

        XCTAssertEqual(
            spy.noteIds,
            ["comment-1"],
            "One created comment must produce exactly one notify_note_created call, carrying that comment's id"
        )
    }

    /// An empty fanout — everyone already had a rail row, or the note reached
    /// nobody — must complete silently rather than fanning out to a client-
    /// computed recipient set the way the old code would have.
    func test_dispatchCompletesSilentlyWhenTheServerReportsNoRecipients() async {
        let notesSpy = NoteCreatedSpy()
        let notesViewModel = ProjectNotesViewModel(projectId: "project-1")
        notesViewModel.noteSyncer = notesSpy

        await notesViewModel.dispatchNoteCreatedNotifications(
            noteId: "note-1",
            noteText: "Rebar delivered",
            attachmentURLs: ["https://example.invalid/a.jpg"]
        )

        let commentsSpy = NoteCreatedSpy()
        let commentsViewModel = makePhotoCommentsViewModel()
        commentsViewModel.noteSyncer = commentsSpy

        await commentsViewModel.dispatchNoteCreatedNotifications(
            noteId: "comment-1",
            noteText: "Check the flashing here"
        )

        XCTAssertEqual(notesSpy.noteIds, ["note-1"])
        XCTAssertEqual(commentsSpy.noteIds, ["comment-1"])
        XCTAssertTrue(
            ProjectNotePushPlan(fanout: notesSpy.fanout).isEmpty,
            "An empty fanout must open no project-note push lane"
        )
        XCTAssertTrue(
            PhotoCommentPushPlan(fanout: commentsSpy.fanout).isEmpty,
            "An empty fanout must open no photo-comment push lane"
        )
    }

    // MARK: - 2. A failed RPC is survivable, and sends nothing

    /// The rail write is the consistency anchor: if it did not happen there is
    /// no row for a push to match, so the dispatch must fall through quietly
    /// rather than pushing anyway. `try?` on the RPC leaves no fanout, and
    /// every push lane is derived from that fanout, so nothing downstream is
    /// reachable — the plan tests below pin the derivation half.
    func test_projectNotesDispatchSurvivesAFailedRpc() async {
        let spy = NoteCreatedSpy()
        spy.transportError = URLError(.notConnectedToInternet)
        let viewModel = ProjectNotesViewModel(projectId: "project-1")
        viewModel.noteSyncer = spy

        await viewModel.dispatchNoteCreatedNotifications(
            noteId: "note-1",
            noteText: "Rebar delivered",
            attachmentURLs: []
        )

        XCTAssertEqual(
            spy.noteIds,
            ["note-1"],
            "The RPC is attempted once; its failure is swallowed, not retried per recipient"
        )
    }

    func test_photoCommentsDispatchSurvivesAFailedRpc() async {
        let spy = NoteCreatedSpy()
        spy.transportError = URLError(.timedOut)
        let viewModel = makePhotoCommentsViewModel()
        viewModel.noteSyncer = spy

        await viewModel.dispatchNoteCreatedNotifications(
            noteId: "comment-1",
            noteText: "Check the flashing here"
        )

        XCTAssertEqual(
            spy.noteIds,
            ["comment-1"],
            "The RPC is attempted once; its failure is swallowed, not retried per recipient"
        )
    }

    // MARK: - 3. The real call site dispatches the SERVER's note id

    /// Wiring proof through `postComment` itself: the id handed to the RPC is
    /// the id of the row the server stored, not the optimistic local one. A
    /// mismatch here would make the RPC derive its recipients from the wrong
    /// note — or from no note at all.
    ///
    /// `ProjectNotesViewModel.postNote` has no equivalent create seam (its
    /// repository call is live network), which is why its dispatch func is
    /// internal and driven directly above.
    func test_postCommentDispatchesTheServerAssignedCommentId() async throws {
        let context = try makeContext()
        let spy = NoteCreatedSpy()
        let createdId = "33333333-3333-4333-8333-333333333333"
        let createdDTO = try noteDTO(id: createdId, projectId: "project-1")

        let viewModel = PhotoCommentsViewModel(
            photoURL: "https://example.invalid/photo.jpg",
            projectId: "project-1",
            createCommentOverride: { _ in createdDTO },
            postRetryBaseDelaySeconds: 0
        )
        viewModel.setup(
            companyId: "company-1",
            currentUserId: "user-1",
            teamMembers: [],
            modelContext: context,
            dataController: nil
        )
        viewModel.noteSyncer = spy
        viewModel.newCommentText = "Check the flashing here"

        let posted = await viewModel.postComment()

        XCTAssertTrue(posted, "Precondition: the comment posted")
        XCTAssertEqual(
            spy.noteIds,
            [createdId],
            "postComment must fan out the server's note id, exactly once"
        )
    }

    // MARK: - 4. Push lanes come only from the server's fanout

    /// A plain note pushes to the mention list verbatim and hands the crew a
    /// SINGLE batched list — `notifyProjectNoteAdded` takes `userIds:`, so the
    /// per-recipient loop that used to exist here has nowhere left to live.
    func test_projectNotePushPlanTargetsTheServersMentionAndCrewLists() {
        let plan = ProjectNotePushPlan(
            fanout: makeFanout(
                mentionUserIds: ["user-2", "user-3"],
                teamUserIds: ["user-4", "user-5"]
            )
        )

        XCTAssertEqual(plan.mentionUserIds, ["user-2", "user-3"])
        XCTAssertEqual(
            plan.teamUserIds,
            ["user-4", "user-5"],
            "The crew broadcast is one batched push, not one push per crew member"
        )
        XCTAssertFalse(plan.isEmpty)
    }

    /// The photo-owner lane belongs to the photo-comment surface. A plain note
    /// has no photo to own, so a `photo_owner_id` on this surface must not
    /// open anything.
    func test_projectNotePushPlanIgnoresThePhotoOwnerLane() {
        let plan = ProjectNotePushPlan(
            fanout: makeFanout(photoOwnerId: "user-9")
        )

        XCTAssertTrue(
            plan.isEmpty,
            "A project note must never push a photo-owner lane"
        )
    }

    /// A photo comment pushes to the mention list verbatim, plus the uploader
    /// the SERVER resolved. The client no longer queries `project_photos` for
    /// `uploaded_by`, and no longer re-applies the self / already-mentioned
    /// exclusions — those are the server's, and re-applying them client-side
    /// is how push and rail drifted apart.
    func test_photoCommentPushPlanTargetsTheServersMentionAndOwnerLists() {
        let plan = PhotoCommentPushPlan(
            fanout: makeFanout(
                kind: "photo_comment",
                mentionUserIds: ["user-2"],
                photoOwnerId: "user-7"
            )
        )

        XCTAssertEqual(plan.mentionUserIds, ["user-2"])
        XCTAssertEqual(plan.photoOwnerId, "user-7")
        XCTAssertFalse(plan.isEmpty)
    }

    /// The crew broadcast belongs to the project-note surface. A comment on a
    /// photo must not turn into a whole-crew push.
    func test_photoCommentPushPlanIgnoresTheCrewBroadcastLane() {
        let plan = PhotoCommentPushPlan(
            fanout: makeFanout(
                kind: "photo_comment",
                teamUserIds: ["user-4", "user-5"]
            )
        )

        XCTAssertTrue(
            plan.isEmpty,
            "A photo comment must never push the crew-broadcast lane"
        )
    }

    /// An empty-string owner is not a recipient. `notifyPhotoComment` would
    /// otherwise be handed "" as a user id.
    func test_photoCommentPushPlanDropsAnEmptyOwnerId() {
        let plan = PhotoCommentPushPlan(
            fanout: makeFanout(kind: "photo_comment", photoOwnerId: "")
        )

        XCTAssertNil(plan.photoOwnerId)
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: - Fixtures

    /// Containers outlive the contexts they vend, for the whole test case. A
    /// `ModelContext` does not keep its container alive, and inserting into a
    /// context whose container has been released traps inside SwiftData
    /// (uncatchable EXC_BREAKPOINT) — the test dies before its first assertion.
    private var retainedContainers: [ModelContainer] = []

    override func tearDown() {
        retainedContainers.removeAll()
        super.tearDown()
    }

    private func makeContext() throws -> ModelContext {
        let container = try makeContainer()
        retainedContainers.append(container)
        return ModelContext(container)
    }

    /// Every container seeds one inert SyncOperation. A `#Predicate` fetch of
    /// SyncOperation TRAPS (uncatchable EXC_BREAKPOINT, not a thrown error)
    /// against a table that has never held a row, so no test here is green by
    /// luck of ordering. Same remedy as ProjectDetailsLocalFirstTests.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: OPSSchemaV23.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])

        let warmUp = ModelContext(container)
        warmUp.insert(SyncOperation(
            entityType: SyncEntityType.project.rawValue,
            entityId: "sync-operation-warm-up",
            operationType: "update",
            payload: Data(),
            changedFields: ["id"]
        ))
        try warmUp.save()

        return container
    }

    /// A view model with no `setup` — the dispatch funcs must not depend on a
    /// resolved operator, roster, or store to reach the RPC. Author name and
    /// project name feed push copy only, and no push lane opens in these tests.
    private func makePhotoCommentsViewModel() -> PhotoCommentsViewModel {
        PhotoCommentsViewModel(
            photoURL: "https://example.invalid/photo.jpg",
            projectId: "project-1"
        )
    }

    private func noteDTO(id: String, projectId: String) throws -> ProjectNoteDTO {
        let json = """
        {
          "id": "\(id)",
          "project_id": "\(projectId)",
          "company_id": "company-1",
          "author_id": "user-1",
          "content": "Check the flashing here",
          "photo_url": "https://example.invalid/photo.jpg",
          "created_at": "2026-08-17T17:00:00Z"
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(ProjectNoteDTO.self, from: json)
    }
}
