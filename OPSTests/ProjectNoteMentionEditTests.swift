//
//  ProjectNoteMentionEditTests.swift
//  OPSTests
//
//  Regression coverage for authoritative mention replacement when an
//  existing Activity note or photo comment is edited.
//

import SwiftData
import XCTest
@testable import OPS

@MainActor
final class ProjectNoteMentionEditTests: XCTestCase {

    private enum ForcedDiscardFailure: Error {
        case claimRejected
        case competitorDidNotStart
        case missingOperation
        case recoveryTimedOut
        case stop
        case unexpectedSuccess
    }

    private let aliceId = "11111111-1111-4111-8111-111111111111"
    private let bobId = "22222222-2222-4222-8222-222222222222"
    private let authorId = "33333333-3333-4333-8333-333333333333"
    private let noteId = "44444444-4444-4444-8444-444444444444"
    private let eventId = "55555555-5555-4555-8555-555555555555"
    private let secondEventId = "88888888-8888-4888-8888-888888888888"
    private let secondBobId = "99999999-9999-4999-8999-999999999999"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: "feature.useDataActor")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "feature.useDataActor")
        super.tearDown()
    }

    func testEditingNoteReplacesMentionsInLocalStateAndAtomicSyncPayload() throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let plan = ProjectNoteMentionEditPlan.make(
            content: "Confirm with @Bob Builder before ordering.",
            teamMembers: teamMembers,
            currentUserId: authorId
        )

        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: plan.content,
            mentionedUserIds: plan.mentionedUserIds,
            mentionEventId: eventId
        )

        XCTAssertEqual(harness.note.mentionedUserIds, [bobId])

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let update = try XCTUnwrap(
            operations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )
        XCTAssertEqual(
            Set(update.getChangedFields()),
            Set([
                "content",
                "mentionedUserIdsString",
            ])
        )

        let payload = try decodedPayload(update)
        XCTAssertEqual(payload[ProjectNoteMentionEditSync.noteIdPayloadKey] as? String, noteId)
        XCTAssertEqual(
            payload[ProjectNoteMentionEditSync.contentPayloadKey] as? String,
            plan.content
        )
        XCTAssertEqual(
            payload[ProjectNoteMentionEditSync.mentionedUserIdsPayloadKey] as? [String],
            [bobId]
        )
        XCTAssertEqual(payload[ProjectNoteMentionEditSync.eventIdPayloadKey] as? String, eventId)

        let dispatch = try XCTUnwrap(
            operations.first {
                $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
            }
        )
        XCTAssertEqual(dispatch.dependsOnId, update.id.uuidString)
        XCTAssertEqual(dispatch.entityId, eventId)
        let dispatchPayload = try decodedPayload(dispatch)
        XCTAssertEqual(
            Set(dispatchPayload.keys),
            [ProjectNoteMentionEditSync.eventIdPayloadKey]
        )
        XCTAssertEqual(
            dispatchPayload[ProjectNoteMentionEditSync.eventIdPayloadKey] as? String,
            eventId
        )
    }

    func testEditingNoteWithoutMentionsQueuesExplicitEmptyMentionArrayAndDispatch() throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let plan = ProjectNoteMentionEditPlan.make(
            content: "No teammate is required for this check.",
            teamMembers: teamMembers,
            currentUserId: authorId
        )

        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: plan.content,
            mentionedUserIds: plan.mentionedUserIds,
            mentionEventId: eventId
        )

        XCTAssertTrue(harness.note.mentionedUserIds.isEmpty)

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let update = try XCTUnwrap(
            operations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )
        let payload = try decodedPayload(update)
        let storedIds = try XCTUnwrap(
            payload[ProjectNoteMentionEditSync.mentionedUserIdsPayloadKey] as? [Any]
        )
        XCTAssertTrue(storedIds.isEmpty, "mention removal must write an explicit []")
        let dispatch = try XCTUnwrap(
            operations.first {
                $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
            }
        )
        XCTAssertEqual(
            dispatch.dependsOnId,
            update.id.uuidString,
            "the server event is authoritative even when the local cache predicts no recipients"
        )
    }

    func testEditingNoteQueuesOneServerAuthoritativeDispatch() throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let plan = ProjectNoteMentionEditPlan.make(
            content: "@Alice Able and @Bob Builder should review this.",
            teamMembers: teamMembers,
            currentUserId: authorId
        )

        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: plan.content,
            mentionedUserIds: plan.mentionedUserIds,
            mentionEventId: eventId
        )

        XCTAssertEqual(plan.mentionedUserIds, [aliceId, bobId])

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(
            operations.filter {
                $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
            }.count,
            1,
            "the server-backed event fans out only the newly added recipient set"
        )
    }

    func testAllTeamResolutionExcludesTheAuthorAndPreservesTeamOrder() {
        let plan = ProjectNoteMentionEditPlan.make(
            content: "@All Team check the revised field note.",
            teamMembers: teamMembers,
            currentUserId: authorId
        )

        XCTAssertEqual(plan.mentionedUserIds, [aliceId, bobId])
    }

    func testMentionResolutionRequiresACompleteMentionBoundary() {
        let plan = ProjectNoteMentionEditPlan.make(
            content: "mail@Alice Able, @Alice Ableton, then @Bob Builder.",
            teamMembers: teamMembers,
            currentUserId: authorId
        )

        XCTAssertEqual(
            plan.mentionedUserIds,
            [bobId],
            "email fragments and longer names must not resolve as mentions"
        )
    }

    func testMentionResolutionChoosesLongestRosterNameAtEachToken() {
        let annId = "66666666-6666-4666-8666-666666666666"
        let annMarieId = "77777777-7777-4777-8777-777777777777"
        let members = [
            TeamMember(
                id: annId,
                firstName: "Ann",
                lastName: "Marie",
                role: "Crew"
            ),
            TeamMember(
                id: annMarieId,
                firstName: "Ann",
                lastName: "Marie Smith",
                role: "Crew"
            ),
        ]

        let plan = ProjectNoteMentionEditPlan.make(
            content: "Review the revision with @Ann Marie Smith.",
            teamMembers: members,
            currentUserId: authorId
        )

        XCTAssertEqual(
            plan.mentionedUserIds,
            [annMarieId],
            "a longer mention must not also grant access to its name prefix"
        )
    }

    func testDuplicateNameTokenNeverExpandsWithoutAnExactIdentity() {
        let duplicateMembers = teamMembers + [
            TeamMember(
                id: secondBobId,
                firstName: "Bob",
                lastName: "Builder",
                role: "Office"
            ),
        ]

        let unresolved = ProjectNoteMentionEditPlan.make(
            content: "Ask @Bob Builder to review.",
            teamMembers: duplicateMembers,
            currentUserId: authorId
        )
        XCTAssertTrue(unresolved.mentionedUserIds.isEmpty)
        XCTAssertEqual(
            unresolved.unresolvedMentionNames,
            ["@Bob Builder"]
        )

        let selected = ProjectNoteMentionEditPlan.make(
            content: "Ask @Bob Builder to review.",
            teamMembers: duplicateMembers,
            currentUserId: authorId,
            preferredMentionedUserIds: [secondBobId]
        )
        XCTAssertEqual(selected.mentionedUserIds, [secondBobId])
        XCTAssertTrue(selected.unresolvedMentionNames.isEmpty)
    }

    func testDuplicateIdentityRoundTripsInTextualOrderAfterReopen() {
        let duplicateMembers = teamMembers + [
            TeamMember(
                id: secondBobId,
                firstName: "Bob",
                lastName: "Builder",
                role: "Office"
            ),
        ]
        let content = "@Bob Builder first, then @Bob Builder."
        let firstRange = (content as NSString).range(
            of: "@Bob Builder"
        )
        let secondRange = (content as NSString).range(
            of: "@Bob Builder",
            options: [],
            range: NSRange(
                location: NSMaxRange(firstRange),
                length: (content as NSString).length - NSMaxRange(firstRange)
            )
        )
        let initialSpans = [
            ProjectNoteMentionSpan(
                range: firstRange,
                displayText: "@Bob Builder",
                recipient: .user(id: bobId)
            ),
            ProjectNoteMentionSpan(
                range: secondRange,
                displayText: "@Bob Builder",
                recipient: .user(id: secondBobId)
            ),
        ]

        let saved = ProjectNoteMentionEditPlan.make(
            content: content,
            teamMembers: duplicateMembers,
            currentUserId: authorId,
            identitySpans: initialSpans
        )
        XCTAssertEqual(saved.mentionedUserIds, [bobId, secondBobId])

        let reopenedDraft = ProjectNoteMentionParser.editableDraft(
            in: saved.content,
            mentionedUserIds: saved.mentionedUserIds,
            teamMembers: duplicateMembers,
            currentUserId: authorId
        )
        XCTAssertEqual(
            reopenedDraft.identitySpans.compactMap {
                guard case .user(let id) = $0.recipient else { return nil }
                return id
            },
            [bobId, secondBobId]
        )
        let reopened = ProjectNoteMentionEditPlan.make(
            content: reopenedDraft.text,
            teamMembers: duplicateMembers,
            currentUserId: authorId,
            identitySpans: reopenedDraft.identitySpans
        )
        XCTAssertEqual(reopened.mentionedUserIds, [bobId, secondBobId])
        XCTAssertEqual(reopened.content, saved.content)
        XCTAssertTrue(reopened.unresolvedMentionNames.isEmpty)
    }

    func testReservedAllTeamGroupAndSameNamedPersonStayDistinctAfterReopen() {
        let namedAllTeamId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let namedAllTeam = TeamMember(
            id: namedAllTeamId,
            firstName: "All",
            lastName: "Team",
            role: "Crew"
        )
        let members = teamMembers + [namedAllTeam]

        let group = ProjectNoteMentionEditPlan.make(
            content: "@All Team check this.",
            teamMembers: members,
            currentUserId: authorId
        )
        XCTAssertEqual(
            group.mentionedUserIds,
            [aliceId, bobId, namedAllTeamId]
        )
        XCTAssertEqual(
            group.content,
            "@[All Team](all-team) check this."
        )
        let groupDraft = ProjectNoteMentionParser.editableDraft(
            in: group.content,
            mentionedUserIds: group.mentionedUserIds,
            teamMembers: members,
            currentUserId: authorId
        )
        XCTAssertEqual(groupDraft.text, "@All Team check this.")
        let reopenedGroup = ProjectNoteMentionEditPlan.make(
            content: groupDraft.text,
            teamMembers: members,
            currentUserId: authorId,
            identitySpans: groupDraft.identitySpans
        )
        XCTAssertEqual(reopenedGroup.content, group.content)
        XCTAssertEqual(reopenedGroup.mentionedUserIds, group.mentionedUserIds)

        let personText = "Ask @All Team (person) to check this."
        let personSpan = ProjectNoteMentionSpan(
            range: (personText as NSString).range(
                of: "@All Team (person)"
            ),
            displayText: "@All Team (person)",
            recipient: .user(id: namedAllTeamId)
        )
        let person = ProjectNoteMentionEditPlan.make(
            content: personText,
            teamMembers: members,
            currentUserId: authorId,
            identitySpans: [personSpan]
        )
        XCTAssertEqual(person.mentionedUserIds, [namedAllTeamId])
        XCTAssertEqual(
            person.content,
            "Ask @[All Team (person)](\(namedAllTeamId)) to check this."
        )

        let reopenedDraft = ProjectNoteMentionParser.editableDraft(
            in: person.content,
            mentionedUserIds: person.mentionedUserIds,
            teamMembers: members,
            currentUserId: authorId
        )
        let reopened = ProjectNoteMentionEditPlan.make(
            content: reopenedDraft.text,
            teamMembers: members,
            currentUserId: authorId,
            identitySpans: reopenedDraft.identitySpans
        )
        XCTAssertEqual(reopened.mentionedUserIds, [namedAllTeamId])
        XCTAssertEqual(reopened.content, person.content)
        XCTAssertFalse(
            reopened.mentionedUserIds.contains(aliceId),
            "the named person token must never reopen as the reserved group"
        )
    }

    func testWebMentionMarkupBecomesIdentitySafePlainDraftAndRoundTrips() {
        let webContent = "Ask @[Bob Builder](\(bobId)) to verify."
        let draft = ProjectNoteMentionParser.editableDraft(
            in: webContent,
            mentionedUserIds: [bobId],
            teamMembers: teamMembers,
            currentUserId: authorId
        )

        XCTAssertEqual(draft.text, "Ask @Bob Builder to verify.")
        XCTAssertFalse(draft.text.contains(bobId))
        XCTAssertEqual(
            ProjectNoteMentionParser.displayText(from: webContent),
            draft.text
        )
        let saved = ProjectNoteMentionEditPlan.make(
            content: draft.text,
            teamMembers: teamMembers,
            currentUserId: authorId,
            identitySpans: draft.identitySpans,
            baseline: ProjectNoteMentionBaseline(
                content: webContent,
                mentionedUserIds: [bobId]
            )
        )
        XCTAssertEqual(saved.mentionedUserIds, [bobId])
        XCTAssertEqual(saved.content, webContent)
        XCTAssertTrue(saved.unresolvedMentionNames.isEmpty)

        let reopened = ProjectNoteMentionParser.editableDraft(
            in: saved.content,
            mentionedUserIds: saved.mentionedUserIds,
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        XCTAssertEqual(
            reopened.identitySpans.compactMap {
                guard case .user(let id) = $0.recipient else { return nil }
                return id
            },
            [bobId]
        )
    }

    func testInconsistentWebMarkupCannotGrantIdentityOrExpandGroup() {
        let maliciousUser = ProjectNoteMentionParser.editableDraft(
            in: "Ask @[Bob Builder](\(bobId)) to verify.",
            mentionedUserIds: [],
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        let maliciousPlan = ProjectNoteMentionEditPlan.make(
            content: maliciousUser.text,
            teamMembers: teamMembers,
            currentUserId: authorId,
            identitySpans: maliciousUser.identitySpans,
            baseline: ProjectNoteMentionBaseline(
                content: "Ask @[Bob Builder](\(bobId)) to verify.",
                mentionedUserIds: []
            )
        )
        XCTAssertTrue(maliciousPlan.mentionedUserIds.isEmpty)
        XCTAssertFalse(maliciousPlan.unresolvedMentionNames.isEmpty)

        let malformedGroup = ProjectNoteMentionParser.editableDraft(
            in: "@[All Team](ALL-TEAM) check this.",
            mentionedUserIds: [aliceId, bobId],
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        let malformedPlan = ProjectNoteMentionEditPlan.make(
            content: malformedGroup.text,
            teamMembers: teamMembers,
            currentUserId: authorId,
            identitySpans: malformedGroup.identitySpans
        )
        XCTAssertTrue(malformedPlan.mentionedUserIds.isEmpty)
        XCTAssertFalse(malformedPlan.unresolvedMentionNames.isEmpty)
    }

    func testCanonicalMentionDeletionRevokesOnlyRemovedIdentity() {
        let baselineContent =
            "Ask @[Alice Able](\(aliceId)) and "
                + "@[Bob Builder](\(bobId)) to review."
        let currentContent = "Ask @Alice Able to review."
        let aliceSpan = ProjectNoteMentionSpan(
            range: (currentContent as NSString).range(
                of: "@Alice Able"
            ),
            displayText: "@Alice Able",
            recipient: .user(id: aliceId)
        )

        let plan = ProjectNoteMentionEditPlan.make(
            content: currentContent,
            teamMembers: teamMembers,
            currentUserId: authorId,
            identitySpans: [aliceSpan],
            baseline: ProjectNoteMentionBaseline(
                content: baselineContent,
                mentionedUserIds: [aliceId, bobId]
            )
        )

        XCTAssertEqual(plan.mentionedUserIds, [aliceId])
        XCTAssertEqual(
            plan.content,
            "Ask @[Alice Able](\(aliceId)) to review."
        )
        XCTAssertTrue(plan.unresolvedMentionNames.isEmpty)

        let removedGroup = ProjectNoteMentionEditPlan.make(
            content: "Check this.",
            teamMembers: teamMembers,
            currentUserId: authorId,
            baseline: ProjectNoteMentionBaseline(
                content: "@[All Team](all-team) check this.",
                mentionedUserIds: [aliceId, bobId]
            )
        )
        XCTAssertTrue(removedGroup.mentionedUserIds.isEmpty)
        XCTAssertTrue(removedGroup.unresolvedMentionNames.isEmpty)
    }

    func testStaleVisibleMentionCanBeExplicitlyRemoved() {
        let plan = ProjectNoteMentionEditPlan.make(
            content: "Check this.",
            teamMembers: teamMembers.filter { $0.id != aliceId },
            currentUserId: authorId,
            baseline: ProjectNoteMentionBaseline(
                content: "@Former Member check this.",
                mentionedUserIds: [aliceId]
            )
        )

        XCTAssertTrue(plan.mentionedUserIds.isEmpty)
        XCTAssertTrue(plan.unresolvedMentionNames.isEmpty)
    }

    func testSoloAuthorAllTeamRoundTripsWithNoRecipients() {
        let soloTeam = [teamMembers[2]]
        let saved = ProjectNoteMentionEditPlan.make(
            content: "@All Team check this.",
            teamMembers: soloTeam,
            currentUserId: authorId
        )
        XCTAssertTrue(saved.mentionedUserIds.isEmpty)
        XCTAssertEqual(
            saved.content,
            "@[All Team](all-team) check this."
        )

        let draft = ProjectNoteMentionParser.editableDraft(
            in: saved.content,
            mentionedUserIds: [],
            teamMembers: soloTeam,
            currentUserId: authorId
        )
        XCTAssertEqual(draft.identitySpans.map(\.recipient), [.allTeam])
        let reopened = ProjectNoteMentionEditPlan.make(
            content: draft.text,
            teamMembers: soloTeam,
            currentUserId: authorId,
            identitySpans: draft.identitySpans
        )
        XCTAssertEqual(reopened, saved)
    }

    func testSelfSelectionNeverSerializesInconsistentMarkup() throws {
        let content = "Ask @Alex Author to check this."
        let selfSpan = ProjectNoteMentionSpan(
            range: (content as NSString).range(of: "@Alex Author"),
            displayText: "@Alex Author",
            recipient: .user(id: authorId)
        )
        let saved = ProjectNoteMentionEditPlan.make(
            content: content,
            teamMembers: teamMembers,
            currentUserId: authorId,
            identitySpans: [selfSpan]
        )

        XCTAssertTrue(saved.mentionedUserIds.isEmpty)
        XCTAssertEqual(saved.content, content)
        XCTAssertFalse(saved.content.contains(authorId))
        XCTAssertTrue(saved.unresolvedMentionNames.isEmpty)

        let reopened = ProjectNoteMentionEditPlan.make(
            content: saved.content,
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        XCTAssertEqual(reopened, saved)

        let harness = try makeHarness(previousMentionIds: [])
        let viewModel = ProjectNotesViewModel(projectId: noteId)
        viewModel.setup(
            companyId: "77777777-7777-4777-8777-777777777777",
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: harness.dataController
        )
        viewModel.newNoteText = "@"
        viewModel.composeSelectedRange = NSRange(location: 1, length: 0)
        viewModel.handleMentionInput("@")
        XCTAssertFalse(
            viewModel.mentionSuggestions.contains {
                $0.id == authorId
            }
        )
    }

    func testUnknownMentionIntentIsUnresolvedButEmailIsPlainText() {
        let typo = ProjectNoteMentionEditPlan.make(
            content: "Ask @Bbo Builder to review.",
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        XCTAssertTrue(typo.mentionedUserIds.isEmpty)
        XCTAssertEqual(typo.unresolvedMentionNames, ["@Bbo"])

        let typoEdit = ProjectNoteMentionEditPlan.make(
            content: "Ask @Bbo Builder to review.",
            teamMembers: teamMembers,
            currentUserId: authorId,
            baseline: ProjectNoteMentionBaseline(
                content: "Ask @[Bob Builder](\(bobId)) to review.",
                mentionedUserIds: [bobId]
            )
        )
        XCTAssertFalse(typoEdit.unresolvedMentionNames.isEmpty)

        let email = ProjectNoteMentionEditPlan.make(
            content: "Send it to crew@example.com.",
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        XCTAssertTrue(email.unresolvedMentionNames.isEmpty)
    }

    func testRenderedSegmentsPreserveIdentityAndFullVisibleNames() {
        let duplicateMembers = teamMembers + [
            TeamMember(
                id: secondBobId,
                firstName: "Bob",
                lastName: "Builder",
                role: "Office"
            ),
        ]
        let duplicateSegments =
            ProjectNoteMentionParser.renderedSegments(
                in: "Ask @[Bob Builder](\(secondBobId)) now.",
                mentionedUserIds: [secondBobId],
                teamMembers: duplicateMembers,
                currentUserId: authorId
            )
        let duplicateMention = duplicateSegments.first {
            $0.isMention
        }
        XCTAssertEqual(duplicateMention?.text, "@Bob Builder")
        XCTAssertEqual(
            duplicateMention?.recipient,
            .user(id: secondBobId)
        )
        XCTAssertFalse(
            duplicateSegments.map(\.text).joined().contains(secondBobId)
        )

        let legacyPlainSegments =
            ProjectNoteMentionParser.renderedSegments(
                in: "Ask @Bob Builder now.",
                mentionedUserIds: [],
                teamMembers: teamMembers,
                currentUserId: authorId
            )
        XCTAssertEqual(
            legacyPlainSegments.first { $0.isMention }?.text,
            "@Bob Builder"
        )
        XCTAssertEqual(
            legacyPlainSegments.first { $0.isMention }?.recipient,
            .unresolved
        )

        let namedAllTeamId =
            "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let namedAllTeam = TeamMember(
            id: namedAllTeamId,
            firstName: "All",
            lastName: "Team",
            role: "Crew"
        )
        let groupSegments = ProjectNoteMentionParser.renderedSegments(
            in: "@[All Team](all-team) check this.",
            mentionedUserIds: [aliceId, bobId, namedAllTeamId],
            teamMembers: teamMembers + [namedAllTeam],
            currentUserId: authorId
        )
        XCTAssertEqual(
            groupSegments.first { $0.isMention }?.recipient,
            .allTeam
        )
        let namedPersonSegments =
            ProjectNoteMentionParser.renderedSegments(
                in:
                    "Ask @[All Team (person)](\(namedAllTeamId)) now.",
                mentionedUserIds: [namedAllTeamId],
                teamMembers: teamMembers + [namedAllTeam],
                currentUserId: authorId
            )
        XCTAssertEqual(
            namedPersonSegments.first { $0.isMention }?.text,
            "@All Team (person)"
        )
        XCTAssertEqual(
            namedPersonSegments.first { $0.isMention }?.recipient,
            .user(id: namedAllTeamId)
        )

        let threeWordId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let threeWord = TeamMember(
            id: threeWordId,
            firstName: "Ann Marie",
            lastName: "Smith",
            role: "Crew"
        )
        let threeWordSegments =
            ProjectNoteMentionParser.renderedSegments(
                in: "Ask @[Ann Marie Smith](\(threeWordId)) now.",
                mentionedUserIds: [threeWordId],
                teamMembers: teamMembers + [threeWord],
                currentUserId: authorId
            )
        XCTAssertEqual(
            threeWordSegments.first { $0.isMention }?.text,
            "@Ann Marie Smith"
        )
        XCTAssertEqual(
            threeWordSegments.first { $0.isMention }?.recipient,
            .user(id: threeWordId)
        )
    }

    func testStaleOrRenamedRetainedIdentityIsPreservedOrExplicitlyBlocked() {
        let baseline = ProjectNoteMentionBaseline(
            content: "@Alice Able should review this.",
            mentionedUserIds: [aliceId]
        )
        let rosterWithoutAlice = teamMembers.filter { $0.id != aliceId }
        let unchangedStaleRosterDraft = ProjectNoteMentionEditPlan.make(
            content: baseline.content,
            teamMembers: rosterWithoutAlice,
            currentUserId: authorId,
            baseline: baseline
        )
        XCTAssertEqual(
            unchangedStaleRosterDraft.mentionedUserIds,
            [aliceId]
        )
        XCTAssertTrue(
            unchangedStaleRosterDraft.unresolvedMentionNames.isEmpty
        )

        let staleRosterEdit = ProjectNoteMentionEditPlan.make(
            content: "Updated details. @Alice Able should review this.",
            teamMembers: rosterWithoutAlice,
            currentUserId: authorId,
            baseline: baseline
        )
        XCTAssertTrue(staleRosterEdit.mentionedUserIds.isEmpty)
        XCTAssertFalse(staleRosterEdit.unresolvedMentionNames.isEmpty)

        let renamedRoster = [
            TeamMember(
                id: aliceId,
                firstName: "Alicia",
                lastName: "Able",
                role: "Crew"
            ),
            teamMembers[1],
            teamMembers[2],
        ]
        let renamedEdit = ProjectNoteMentionEditPlan.make(
            content: "Updated details. @Alice Able should review this.",
            teamMembers: renamedRoster,
            currentUserId: authorId,
            baseline: baseline
        )
        XCTAssertTrue(renamedEdit.mentionedUserIds.isEmpty)
        XCTAssertFalse(renamedEdit.unresolvedMentionNames.isEmpty)

        let changedUnknownMention = ProjectNoteMentionEditPlan.make(
            content: "@Someone Else should review this.",
            teamMembers: rosterWithoutAlice,
            currentUserId: authorId,
            baseline: baseline
        )
        XCTAssertFalse(changedUnknownMention.unresolvedMentionNames.isEmpty)
        XCTAssertFalse(
            changedUnknownMention.mentionedUserIds.contains(aliceId),
            "changing an unresolvable retained token must block, not retain hidden access"
        )

        let invalidCanonicalBaseline =
            ProjectNoteMentionBaseline(
                content: "Ask @[Eve Example](\(bobId)) to review.",
                mentionedUserIds: [bobId]
            )
        let invalidCanonicalDraft =
            ProjectNoteMentionParser.editableDraft(
                in: invalidCanonicalBaseline.content,
                mentionedUserIds:
                    invalidCanonicalBaseline.mentionedUserIds,
                teamMembers: teamMembers,
                currentUserId: authorId
            )
        let invalidCanonicalUnchanged =
            ProjectNoteMentionEditPlan.make(
                content: invalidCanonicalDraft.text,
                teamMembers: teamMembers,
                currentUserId: authorId,
                identitySpans:
                    invalidCanonicalDraft.identitySpans,
                baseline: invalidCanonicalBaseline
            )
        XCTAssertFalse(
            invalidCanonicalUnchanged.unresolvedMentionNames.isEmpty,
            "unchanged malformed markup must not become hidden retained access"
        )

        let threeWordBaseline = ProjectNoteMentionBaseline(
            content: "@Ann Marie Smith should review this.",
            mentionedUserIds: [aliceId]
        )
        let changedThirdName = ProjectNoteMentionEditPlan.make(
            content: "@Ann Marie Jones should review this.",
            teamMembers: rosterWithoutAlice,
            currentUserId: authorId,
            baseline: threeWordBaseline
        )
        XCTAssertFalse(changedThirdName.unresolvedMentionNames.isEmpty)
        XCTAssertFalse(changedThirdName.mentionedUserIds.contains(aliceId))

        let lowercaseParticleBaseline = ProjectNoteMentionBaseline(
            content: "@Ludwig van Beethoven should review this.",
            mentionedUserIds: [aliceId]
        )
        let unchangedLowercaseParticle =
            ProjectNoteMentionEditPlan.make(
                content: lowercaseParticleBaseline.content,
                teamMembers: rosterWithoutAlice,
                currentUserId: authorId,
                baseline: lowercaseParticleBaseline
            )
        XCTAssertEqual(
            unchangedLowercaseParticle.mentionedUserIds,
            [aliceId]
        )
        XCTAssertTrue(
            unchangedLowercaseParticle.unresolvedMentionNames.isEmpty
        )
        let editedLowercaseParticle = ProjectNoteMentionEditPlan.make(
            content:
                "Updated details. @Ludwig van Beethoven should review this.",
            teamMembers: rosterWithoutAlice,
            currentUserId: authorId,
            baseline: lowercaseParticleBaseline
        )
        XCTAssertTrue(editedLowercaseParticle.mentionedUserIds.isEmpty)
        XCTAssertFalse(
            editedLowercaseParticle.unresolvedMentionNames.isEmpty
        )

        let hiddenBaseline = ProjectNoteMentionBaseline(
            content: "No visible mention.",
            mentionedUserIds: [aliceId]
        )
        let hiddenIdentity = ProjectNoteMentionEditPlan.make(
            content: "Unrelated edit with no visible mention.",
            teamMembers: rosterWithoutAlice,
            currentUserId: authorId,
            baseline: hiddenBaseline
        )
        XCTAssertFalse(hiddenIdentity.unresolvedMentionNames.isEmpty)
        XCTAssertFalse(hiddenIdentity.mentionedUserIds.contains(aliceId))
    }

    func testMentionResolutionDeduplicatesRosterRowsWithoutChangingTeamOrder() {
        let duplicateAlice = TeamMember(
            id: aliceId.uppercased(),
            firstName: "Alice",
            lastName: "Able",
            role: "Crew"
        )
        let plan = ProjectNoteMentionEditPlan.make(
            content: "@All Team check the revised field note.",
            teamMembers: [teamMembers[0], duplicateAlice, teamMembers[1], teamMembers[2]],
            currentUserId: authorId
        )

        XCTAssertEqual(plan.mentionedUserIds, [aliceId, bobId])
    }

    func testPhotoEditMentionPickerUsesSharedMatchingAndInsertionRules() throws {
        let match = try XCTUnwrap(
            ProjectNotesViewModel.mentionMatch(
                for: "Confirm with @bo",
                in: teamMembers
            )
        )

        XCTAssertEqual(match.suggestions.map(\.id), [bobId])
        XCTAssertFalse(match.showAllTeam)
        XCTAssertEqual(
            ProjectNotesViewModel.textInserting(
                mention: match.suggestions[0].fullName,
                into: "Confirm with @bo"
            ),
            "Confirm with @Bob Builder "
        )

        let allTeamMatch = try XCTUnwrap(
            ProjectNotesViewModel.mentionMatch(
                for: "Confirm with @All T",
                in: teamMembers
            )
        )
        XCTAssertTrue(allTeamMatch.showAllTeam)
    }

    func testCaretScopedMentionEditingPreservesSuffixAndBoundaries() throws {
        let middleText = "Before @bo after"
        let middleCaret = NSRange(
            location: ("Before @bo" as NSString).length,
            length: 0
        )
        let middleMatch = try XCTUnwrap(
            ProjectNoteMentionEditor.match(
                in: middleText,
                selectedRange: middleCaret,
                members: teamMembers
            )
        )
        XCTAssertEqual(middleMatch.suggestions.map(\.id), [bobId])
        let middleReplacement = try XCTUnwrap(
            ProjectNoteMentionEditor.replacingActiveMention(
                with: "Bob Builder",
                in: middleText,
                selectedRange: middleCaret
            )
        )
        XCTAssertEqual(
            middleReplacement.text,
            "Before @Bob Builder after"
        )
        XCTAssertEqual(
            middleReplacement.selectedRange,
            NSRange(
                location: ("Before @Bob Builder " as NSString).length,
                length: 0
            )
        )

        let twoMentions = "@Alice Able first, then @bo later"
        let secondMentionCaret = NSRange(
            location: ("@Alice Able first, then @bo" as NSString).length,
            length: 0
        )
        XCTAssertEqual(
            ProjectNoteMentionEditor.match(
                in: twoMentions,
                selectedRange: secondMentionCaret,
                members: teamMembers
            )?.suggestions.map(\.id),
            [bobId]
        )
        XCTAssertNil(
            ProjectNoteMentionEditor.match(
                in: twoMentions,
                selectedRange: NSRange(
                    location: (twoMentions as NSString).length,
                    length: 0
                ),
                members: teamMembers
            ),
            "moving the caret beyond the token must hide the picker without changing text"
        )

        let selectedText = "Ask @bo tomorrow"
        let selectedQuery = NSRange(
            location: ("Ask @" as NSString).length,
            length: ("bo" as NSString).length
        )
        XCTAssertEqual(
            ProjectNoteMentionEditor.replacingActiveMention(
                with: "Bob Builder",
                in: selectedText,
                selectedRange: selectedQuery
            )?.text,
            "Ask @Bob Builder tomorrow"
        )

        let multilineEmojiText = "🔨 first\nAsk @bo tomorrow"
        let multilineCaret = NSRange(
            location: ("🔨 first\nAsk @bo" as NSString).length,
            length: 0
        )
        XCTAssertEqual(
            ProjectNoteMentionEditor.replacingActiveMention(
                with: "Bob Builder",
                in: multilineEmojiText,
                selectedRange: multilineCaret
            )?.text,
            "🔨 first\nAsk @Bob Builder tomorrow"
        )

        let allTeamText = "Ask @All T tomorrow"
        let allTeamCaret = NSRange(
            location: ("Ask @All T" as NSString).length,
            length: 0
        )
        XCTAssertTrue(
            ProjectNoteMentionEditor.match(
                in: allTeamText,
                selectedRange: allTeamCaret,
                members: teamMembers
            )?.showAllTeam == true
        )
        XCTAssertEqual(
            ProjectNoteMentionEditor.replacingActiveMention(
                with: "All Team",
                in: allTeamText,
                selectedRange: allTeamCaret
            )?.text,
            "Ask @All Team tomorrow"
        )

        let invalidBoundaryText = "mail@bo now"
        XCTAssertNil(
            ProjectNoteMentionEditor.match(
                in: invalidBoundaryText,
                selectedRange: NSRange(
                    location: ("mail@bo" as NSString).length,
                    length: 0
                ),
                members: teamMembers
            )
        )
    }

    func testIdentitySpansTrackUTF16EditsAndInvalidateTouchedMentions() throws {
        let text = "🔨 Before @bo after"
        let caret = NSRange(
            location: ("🔨 Before @bo" as NSString).length,
            length: 0
        )
        let replacement = try XCTUnwrap(
            ProjectNoteMentionEditor.replacingActiveMention(
                with: "Bob Builder",
                in: text,
                selectedRange: caret,
                recipient: .user(id: bobId),
                visibleMentionText: "@Bob Builder"
            )
        )
        XCTAssertEqual(replacement.text, "🔨 Before @Bob Builder after")
        let span = try XCTUnwrap(replacement.mentionSpans.first)
        XCTAssertEqual(
            span.range,
            (replacement.text as NSString).range(of: "@Bob Builder")
        )
        XCTAssertEqual(span.recipient, .user(id: bobId))

        let shifted = ProjectNoteMentionEditor.adjustingMentionSpans(
            replacement.mentionSpans,
            replacing: NSRange(location: 0, length: 0),
            with: "🧰 "
        )
        XCTAssertEqual(
            shifted.first?.range.location,
            span.range.location + ("🧰 " as NSString).length
        )

        let touched = ProjectNoteMentionEditor.adjustingMentionSpans(
            shifted,
            replacing: NSRange(
                location: try XCTUnwrap(shifted.first).range.location + 2,
                length: 1
            ),
            with: "x"
        )
        XCTAssertTrue(
            touched.isEmpty,
            "editing a visible mention must invalidate its hidden identity"
        )

        let duplicates = "@Bob Builder and @Bob Builder"
        let firstRange = (duplicates as NSString).range(
            of: "@Bob Builder"
        )
        let secondRange = (duplicates as NSString).range(
            of: "@Bob Builder",
            options: [],
            range: NSRange(
                location: NSMaxRange(firstRange),
                length:
                    (duplicates as NSString).length
                        - NSMaxRange(firstRange)
            )
        )
        let survivingDuplicateSpans =
            ProjectNoteMentionEditor.adjustingMentionSpans(
                [
                    ProjectNoteMentionSpan(
                        range: firstRange,
                        displayText: "@Bob Builder",
                        recipient: .user(id: bobId)
                    ),
                    ProjectNoteMentionSpan(
                        range: secondRange,
                        displayText: "@Bob Builder",
                        recipient: .user(id: secondBobId)
                    ),
                ],
                replacing: firstRange,
                with: ""
            )
        XCTAssertEqual(
            survivingDuplicateSpans.map(\.recipient),
            [.user(id: secondBobId)],
            "deleting one duplicate token must preserve the other selected identity"
        )
    }

    func testActivityEditReturnsFailureWithoutDurableQueueSoEditorStaysOpen() async throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let originalContent = harness.note.content
        let originalMentions = harness.note.mentionedUserIds
        let viewModel = ProjectNotesViewModel(projectId: harness.note.projectId)
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: nil
        )

        let didQueueSave = await viewModel.updateNoteContent(
            harness.note,
            newContent: "@Bob Builder should review this."
        )

        XCTAssertFalse(
            didQueueSave,
            "Activity must keep its edit field open until the save is durably queued"
        )
        XCTAssertEqual(harness.note.content, originalContent)
        XCTAssertEqual(harness.note.mentionedUserIds, originalMentions)
        XCTAssertEqual(viewModel.error, "Couldn't save. Try again.")
    }

    func testActivityEditRetryClearsStaleQueueFailure() async throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let viewModel = ProjectNotesViewModel(
            projectId: harness.note.projectId
        )
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: nil
        )
        let firstAttemptQueued = await viewModel.updateNoteContent(
            harness.note,
            newContent: "@Bob Builder first attempt."
        )
        XCTAssertFalse(firstAttemptQueued)
        XCTAssertNotNil(viewModel.error)

        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: harness.dataController
        )
        let retryQueued = await viewModel.updateNoteContent(
            harness.note,
            newContent: "@Bob Builder retry."
        )
        XCTAssertTrue(retryQueued)
        XCTAssertNil(viewModel.error)
    }

    func testPhotoEditRefusesNonDurableRPCFallbackAndKeepsEditOpen() async throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let photoURL = "https://example.com/photo.jpg"
        harness.note.photoURL = photoURL
        try harness.context.save()
        let originalContent = harness.note.content
        let originalMentions = harness.note.mentionedUserIds
        let viewModel = PhotoCommentsViewModel(
            photoURL: photoURL,
            projectId: harness.note.projectId
        )
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: nil
        )
        viewModel.startEditing(harness.note)
        viewModel.editText = "@Bob Builder should review this."

        await viewModel.saveEdit()

        XCTAssertEqual(harness.note.content, originalContent)
        XCTAssertEqual(harness.note.mentionedUserIds, originalMentions)
        XCTAssertEqual(viewModel.editingNoteId, harness.note.id)
        XCTAssertEqual(viewModel.error, "Couldn't save. Try again.")
    }

    func testPhotoEmptyEditShowsFailureAndKeepsEditorOpen() async throws {
        let harness = try makeHarness(previousMentionIds: [])
        let photoURL = "https://example.com/photo-empty-edit.jpg"
        harness.note.photoURL = photoURL
        try harness.context.save()
        let viewModel = PhotoCommentsViewModel(
            photoURL: photoURL,
            projectId: harness.note.projectId
        )
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: harness.dataController
        )
        viewModel.startEditing(harness.note)
        viewModel.editText = "   "

        await viewModel.saveEdit()

        XCTAssertEqual(viewModel.editingNoteId, harness.note.id)
        XCTAssertEqual(
            viewModel.error,
            "Enter a comment before saving."
        )
        XCTAssertEqual(
            viewModel.errorFeedbackLabel,
            Feedback.Err.saveFailed
        )
    }

    func testPhotoRetryClearsStaleEditFailureAfterDurableSave() async throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let photoURL = "https://example.com/photo-retry.jpg"
        harness.note.photoURL = photoURL
        try harness.context.save()
        let viewModel = PhotoCommentsViewModel(
            photoURL: photoURL,
            projectId: harness.note.projectId
        )
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: nil
        )
        viewModel.startEditing(harness.note)
        viewModel.editText = "@Bob Builder first attempt."
        await viewModel.saveEdit()
        XCTAssertNotNil(viewModel.error)

        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: harness.dataController
        )
        viewModel.editText = "@Bob Builder retry."
        await viewModel.saveEdit()

        XCTAssertNil(viewModel.error)
        XCTAssertNil(viewModel.editingNoteId)
    }

    func testUnresolvedPhotoPostReturnsFailureForToastGate() async throws {
        let harness = try makeHarness(previousMentionIds: [])
        let photoURL = "https://example.com/photo-post.jpg"
        let duplicateMembers = teamMembers + [
            TeamMember(
                id: secondBobId,
                firstName: "Bob",
                lastName: "Builder",
                role: "Office"
            ),
        ]
        let viewModel = PhotoCommentsViewModel(
            photoURL: photoURL,
            projectId: harness.note.projectId
        )
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: duplicateMembers,
            modelContext: harness.context,
            dataController: harness.dataController
        )
        viewModel.newCommentText = "@Bob Builder check this."

        let didPost = await viewModel.postComment()

        XCTAssertFalse(
            didPost,
            "the viewer's success toast gate must stay closed on unresolved mentions"
        )
        XCTAssertEqual(
            viewModel.error,
            "Select the teammate again before posting."
        )
        XCTAssertEqual(
            viewModel.errorFeedbackLabel,
            Feedback.Err.saveFailed
        )
    }

    func testPhotoPostNetworkFailureReturnsFalseForSuccessToastGate() async throws {
        let harness = try makeHarness(previousMentionIds: [])
        var attempts = 0
        let viewModel = PhotoCommentsViewModel(
            photoURL: "https://example.com/photo-network-failure.jpg",
            projectId: harness.note.projectId,
            createCommentOverride: { _ in
                attempts += 1
                throw URLError(.notConnectedToInternet)
            },
            postRetryBaseDelaySeconds: 0
        )
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: harness.dataController
        )
        viewModel.newCommentText = "Network regression."

        let didPost = await viewModel.postComment()

        XCTAssertFalse(
            didPost,
            "the viewer must not present COMMENT POSTED after the repository fails"
        )
        XCTAssertEqual(attempts, 3)
        XCTAssertNotNil(viewModel.error)
        XCTAssertEqual(
            viewModel.newCommentText,
            "Network regression.",
            "failed posts must preserve the operator's draft"
        )
        XCTAssertTrue(
            try harness.context.fetch(FetchDescriptor<ProjectNote>())
                .allSatisfy {
                    $0.content != "Network regression."
                },
            "the failed optimistic row must be removed"
        )
    }

    func testPhotoDeleteQueueFailureIsVisibleAndPreservesComment() async throws {
        let harness = try makeHarness(previousMentionIds: [])
        let photoURL = "https://example.com/photo-delete-failure.jpg"
        harness.note.photoURL = photoURL
        try harness.context.save()
        let failingController = DataController()
        let viewModel = PhotoCommentsViewModel(
            photoURL: photoURL,
            projectId: harness.note.projectId
        )
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: failingController
        )

        let didDelete = await viewModel.deleteComment(harness.note)

        XCTAssertFalse(didDelete)
        XCTAssertNil(harness.note.deletedAt)
        XCTAssertEqual(
            viewModel.error,
            "Couldn't delete comment. Try again."
        )
        XCTAssertEqual(
            viewModel.errorFeedbackLabel,
            Feedback.Err.deleteFailed
        )
    }

    func testActivityDeleteQueueFailurePreservesNoteAndOwnedPhoto() async throws {
        let harness = try makeHarness(previousMentionIds: [])
        let photoURL = "https://example.com/owned-photo.jpg"
        harness.note.photoURL = photoURL
        harness.note.attachments = [photoURL]
        let project = Project(
            id: harness.note.projectId,
            title: "Test project",
            status: .inProgress
        )
        project.companyId = harness.note.companyId
        project.setProjectImageURLs([photoURL])
        let projectPhoto = ProjectPhoto(
            projectId: harness.note.projectId,
            companyId: harness.note.companyId,
            url: photoURL,
            uploadedBy: authorId
        )
        harness.context.insert(project)
        harness.context.insert(projectPhoto)
        try harness.context.save()

        let failingController = DataController()
        let viewModel = ProjectNotesViewModel(
            projectId: harness.note.projectId
        )
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: failingController
        )

        await viewModel.deleteNote(
            harness.note,
            deletePhoto: true
        )

        XCTAssertNil(harness.note.deletedAt)
        XCTAssertEqual(viewModel.error, "Couldn't delete. Try again.")
        XCTAssertEqual(project.getProjectImageURLs(), [photoURL])
        XCTAssertNil(projectPhoto.deletedAt)
        XCTAssertTrue(
            try harness.context.fetch(FetchDescriptor<SyncOperation>())
                .isEmpty,
            "failed queueing must not report or apply any destructive follow-up"
        )
    }

    func testPhotoEditHumanizesCanonicalMarkupBeforePresentation() throws {
        let harness = try makeHarness(previousMentionIds: [bobId])
        let photoURL = "https://example.com/photo-canonical.jpg"
        harness.note.photoURL = photoURL
        harness.note.content =
            "Ask @[Bob Builder](\(bobId)) to review."
        try harness.context.save()
        let viewModel = PhotoCommentsViewModel(
            photoURL: photoURL,
            projectId: harness.note.projectId
        )
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: harness.dataController
        )

        viewModel.startEditing(harness.note)

        XCTAssertEqual(
            viewModel.editText,
            "Ask @Bob Builder to review."
        )
        XCTAssertFalse(viewModel.editText.contains(bobId))
        XCTAssertEqual(viewModel.editingNoteId, harness.note.id)
    }

    func testPhotoEditPreservesRawWhitespaceAndIdentitySpanOffsets() async throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let photoURL = "https://example.com/photo-whitespace.jpg"
        harness.note.photoURL = photoURL
        try harness.context.save()
        let viewModel = PhotoCommentsViewModel(
            photoURL: photoURL,
            projectId: harness.note.projectId
        )
        viewModel.setup(
            companyId: harness.note.companyId,
            currentUserId: authorId,
            teamMembers: teamMembers,
            modelContext: harness.context,
            dataController: harness.dataController
        )
        let content = "  @Bob Builder should review this.  "
        let span = ProjectNoteMentionSpan(
            range: (content as NSString).range(of: "@Bob Builder"),
            displayText: "@Bob Builder",
            recipient: .user(id: bobId)
        )
        viewModel.startEditing(harness.note)
        viewModel.editText = content

        await viewModel.saveEdit(identitySpans: [span])

        XCTAssertEqual(
            ProjectNoteMentionParser.displayText(
                from: harness.note.content
            ),
            content
        )
        XCTAssertEqual(
            harness.note.content,
            "  @[Bob Builder](\(bobId)) should review this.  "
        )
        XCTAssertEqual(harness.note.mentionedUserIds, [bobId])
        XCTAssertNil(viewModel.editingNoteId)
    }

    func testLaterOfflineEditDependsOnEarlierUpdateAndHoldsItsDispatch() throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])

        let firstPlan = ProjectNoteMentionEditPlan.make(
            content: "@Bob Builder should review this.",
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: firstPlan.content,
            mentionedUserIds: firstPlan.mentionedUserIds,
            mentionEventId: eventId
        )

        let secondPlan = ProjectNoteMentionEditPlan.make(
            content: "No teammate is required after all.",
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: secondPlan.content,
            mentionedUserIds: secondPlan.mentionedUserIds,
            mentionEventId: secondEventId
        )

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let updates = operations
            .filter { $0.operationType == ProjectNoteMentionEditSync.updateOperationType }
            .sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(updates.count, 2)
        let firstUpdate = try XCTUnwrap(updates.first)
        let secondUpdate = try XCTUnwrap(updates.last)
        XCTAssertEqual(secondUpdate.dependsOnId, firstUpdate.id.uuidString)

        let dispatches = operations.filter {
            $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
        }
        XCTAssertEqual(dispatches.count, 2)
        XCTAssertTrue(
            dispatches.allSatisfy {
                $0.dependsOnId == secondUpdate.id.uuidString
            },
            "every event must wait for the newest queued note state"
        )
    }

    func testFirstEditWaitsForUnresolvedCreateAndRevivesTransientFailure() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: harness.note.id,
                operationType: "create",
                changedFields: [
                    "id": harness.note.id,
                    "content": harness.note.content,
                ],
                deferPush: true
            )
        )
        create.status = "failed"
        create.retryCount = 5
        create.lastAttemptedAt = Date()
        try harness.context.save()

        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@[Bob Builder](\(bobId)) review this.",
                mentionedUserIds: [bobId],
                mentionEventId: eventId
            )
        )

        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let update = try XCTUnwrap(
            operations.first {
                ProjectNoteMentionEditSync.isUpdateOperation($0)
            }
        )
        XCTAssertEqual(update.dependsOnId, create.id.uuidString)
        XCTAssertEqual(create.status, "pending")
        XCTAssertEqual(create.retryCount, 0)
        XCTAssertNil(create.lastAttemptedAt)
    }

    func testDiscardUnresolvedCreateRemovesLocalNoteAndMentionDescendants() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: harness.note.id,
                operationType: "create",
                changedFields: [
                    "id": harness.note.id,
                    "content": harness.note.content,
                ],
                deferPush: true
            )
        )
        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@[Bob Builder](\(bobId)) review this.",
                mentionedUserIds: [bobId],
                mentionEventId: eventId
            )
        )

        harness.dataController.syncEngine.cancelOperation(create)

        let notes = try harness.context.fetch(
            FetchDescriptor<ProjectNote>()
        )
        XCTAssertFalse(notes.contains { $0.id == noteId })
        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        XCTAssertFalse(
            operations.contains {
                $0.entityType == SyncEntityType.projectNote.rawValue
                    && (
                        $0.entityId.lowercased() == noteId
                            || $0.entityId.lowercased() == eventId
                    )
            },
            "discarding an uncommitted create must retire every dependent update and dispatch"
        )
    }

    func testDeleteRetiresPendingMentionDeliveryAtomically() throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@[Bob Builder](\(bobId)) review this.",
                mentionedUserIds: [bobId],
                mentionEventId: eventId
            )
        )

        harness.dataController.deleteProjectNote(note: harness.note)

        XCTAssertNotNil(harness.note.deletedAt)
        XCTAssertTrue(harness.note.needsSync)
        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        XCTAssertFalse(
            operations.contains {
                ProjectNoteMentionEditSync.bypassesGenericCoalescing($0)
            }
        )
        let delete = try XCTUnwrap(
            operations.first {
                $0.entityType == SyncEntityType.projectNote.rawValue
                    && $0.entityId.lowercased() == noteId
                    && $0.operationType == "delete"
            }
        )
        XCTAssertNil(delete.dependsOnId)
    }

    func testOfflineCreateEditDeleteKeepsOnlyCreateThenDeleteChain() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: harness.note.id,
                operationType: "create",
                changedFields: [
                    "id": harness.note.id,
                    "content": harness.note.content,
                ],
                deferPush: true
            )
        )
        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@[Bob Builder](\(bobId)) review this.",
                mentionedUserIds: [bobId],
                mentionEventId: eventId
            )
        )

        harness.dataController.deleteProjectNote(note: harness.note)

        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        XCTAssertFalse(
            operations.contains {
                ProjectNoteMentionEditSync.bypassesGenericCoalescing($0)
            }
        )
        let delete = try XCTUnwrap(
            operations.first {
                $0.entityType == SyncEntityType.projectNote.rawValue
                    && $0.entityId.lowercased() == noteId
                    && $0.operationType == "delete"
            }
        )
        XCTAssertEqual(delete.dependsOnId, create.id.uuidString)
        XCTAssertTrue(operations.contains { $0.id == create.id })
    }

    func testDeleteRevivesFailedUnresolvedCreate() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: harness.note.id,
                operationType: "create",
                changedFields: [
                    "id": harness.note.id,
                    "content": harness.note.content,
                ],
                deferPush: true
            )
        )
        create.status = "failed"
        create.retryCount = SyncOperationFailurePolicy.maxRetries
        create.lastAttemptedAt = Date()
        try harness.context.save()

        harness.dataController.deleteProjectNote(note: harness.note)

        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let delete = try XCTUnwrap(
            operations.first {
                $0.entityId.lowercased() == noteId
                    && $0.operationType == "delete"
            }
        )
        XCTAssertEqual(create.status, "pending")
        XCTAssertEqual(create.retryCount, 0)
        XCTAssertNil(create.lastAttemptedAt)
        XCTAssertEqual(delete.dependsOnId, create.id.uuidString)
    }

    func testDeleteRetiresAlreadyParkedLocalOnlyCreateChain() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: harness.note.id,
                operationType: "create",
                changedFields: [
                    "id": harness.note.id,
                    "content": harness.note.content,
                ],
                deferPush: true
            )
        )
        create.status = "parked"
        create.lastError = "Permanent rejection"
        try harness.context.save()

        harness.dataController.deleteProjectNote(note: harness.note)

        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        XCTAssertNotNil(harness.note.deletedAt)
        XCTAssertFalse(harness.note.needsSync)
        XCTAssertTrue(
            operations
                .filter {
                    $0.entityType
                        == SyncEntityType.projectNote.rawValue
                        && $0.entityId.lowercased() == noteId
                }
                .allSatisfy { $0.status == "completed" }
        )
    }

    func testInFlightCreateParkingRetiresQueuedDelete() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: harness.note.id,
                operationType: "create",
                changedFields: [
                    "id": harness.note.id,
                    "content": harness.note.content,
                ],
                deferPush: true
            )
        )
        create.status = "inProgress"
        try harness.context.save()
        harness.dataController.deleteProjectNote(note: harness.note)
        var operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let delete = try XCTUnwrap(
            operations.first {
                $0.entityId.lowercased() == noteId
                    && $0.operationType == "delete"
            }
        )
        XCTAssertEqual(delete.dependsOnId, create.id.uuidString)

        create.status = "parked"
        XCTAssertTrue(
            ProjectNoteMentionEditSync
                .retireParkedCreateWithQueuedDelete(
                    create,
                    in: operations
                )
        )
        operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        XCTAssertEqual(create.status, "completed")
        XCTAssertEqual(delete.status, "completed")
    }

    func testDependencyDrainReleasesGenericDeleteInSamePushCycle() {
        let create = SyncOperation(
            entityType: SyncEntityType.projectNote.rawValue,
            entityId: noteId,
            operationType: "create",
            payload: Data(),
            changedFields: []
        )
        create.status = "completed"
        let delete = SyncOperation(
            entityType: SyncEntityType.projectNote.rawValue,
            entityId: noteId,
            operationType: "delete",
            payload: Data(),
            changedFields: [],
            dependsOnId: create.id.uuidString
        )

        let ready = ProjectNoteMentionEditSync
            .readyPendingOperationIds(in: [create, delete])
        XCTAssertEqual(ready, Set([delete.id]))
        XCTAssertTrue(
            ProjectNoteMentionEditSync.shouldContinueDrain(
                readyBeforePass: [],
                readyAfterPass: ready
            )
        )
    }

    func testLaterEditRevivesFailedPredecessorBeforeDependingOnIt() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able should review this.",
            mentionedUserIds: [aliceId],
            mentionEventId: eventId
        )

        let firstOperations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let firstUpdate = try XCTUnwrap(
            firstOperations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )
        firstUpdate.status = "failed"
        firstUpdate.retryCount = SyncOperationFailurePolicy.maxRetries
        firstUpdate.lastAttemptedAt = Date()
        firstUpdate.lastError = "Timed out"
        try harness.context.save()

        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder should review this.",
            mentionedUserIds: [bobId],
            mentionEventId: secondEventId
        )

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let firstUpdateAfter = try XCTUnwrap(
            operations.first { $0.id == firstUpdate.id }
        )
        let laterUpdate = try XCTUnwrap(
            operations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
                    && $0.id != firstUpdate.id
            }
        )

        XCTAssertEqual(firstUpdateAfter.status, "pending")
        XCTAssertEqual(firstUpdateAfter.retryCount, 0)
        XCTAssertNil(firstUpdateAfter.lastAttemptedAt)
        XCTAssertEqual(
            laterUpdate.dependsOnId,
            firstUpdate.id.uuidString,
            "the uncertain predecessor must replay before the later authoritative edit"
        )
    }

    func testLaterEditRevivesFailedDispatchAndRetargetsIt() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able should review this.",
            mentionedUserIds: [aliceId],
            mentionEventId: eventId
        )

        let firstOperations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let firstUpdate = try XCTUnwrap(
            firstOperations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )
        let firstDispatch = try XCTUnwrap(
            firstOperations.first {
                $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
            }
        )
        firstUpdate.status = "completed"
        firstUpdate.completedAt = Date()
        firstDispatch.status = "failed"
        firstDispatch.retryCount = SyncOperationFailurePolicy.maxRetries
        firstDispatch.lastAttemptedAt = Date()
        try harness.context.save()

        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able and @Bob Builder should review this.",
            mentionedUserIds: [aliceId, bobId],
            mentionEventId: secondEventId
        )

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let laterUpdate = try XCTUnwrap(
            operations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
                    && $0.id != firstUpdate.id
            }
        )
        XCTAssertEqual(firstDispatch.status, "pending")
        XCTAssertEqual(firstDispatch.retryCount, 0)
        XCTAssertNil(firstDispatch.lastAttemptedAt)
        XCTAssertEqual(firstDispatch.dependsOnId, laterUpdate.id.uuidString)
    }

    func testParkedPredecessorIsSupersededWhenLaterReplacementExists() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able should review this.",
            mentionedUserIds: [aliceId],
            mentionEventId: eventId
        )

        let firstOperations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let firstUpdate = try XCTUnwrap(
            firstOperations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )
        let firstDispatch = try XCTUnwrap(
            firstOperations.first {
                $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
                    && $0.entityId == eventId
            }
        )

        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder should review this.",
            mentionedUserIds: [bobId],
            mentionEventId: secondEventId
        )

        let queued = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let laterUpdate = try XCTUnwrap(
            queued.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
                    && $0.id != firstUpdate.id
            }
        )
        XCTAssertEqual(laterUpdate.dependsOnId, firstUpdate.id.uuidString)

        firstUpdate.status = "parked"
        try harness.context.save()

        XCTAssertTrue(
            harness.dataController.syncEngine
                .reconcileSupersededParkedProjectNoteMentionUpdates()
        )

        let reconciled = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(firstUpdate.status, "completed")
        XCTAssertNotNil(firstUpdate.completedAt)
        XCTAssertEqual(
            firstDispatch.status,
            "completed",
            "a rejected update never committed its event, so its dispatch must be retired"
        )
        XCTAssertTrue(
            ProjectNoteMentionEditSync.readyPendingOperationIds(in: reconciled)
                .contains(laterUpdate.id),
            "the later full replacement must be released immediately"
        )
    }

    func testDiscardMentionUpdateRewiresReplacementAndRemovesItsDispatch() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able should review this.",
            mentionedUserIds: [aliceId],
            mentionEventId: eventId
        )

        let firstOperations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let firstUpdate = try XCTUnwrap(
            firstOperations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )
        let firstDispatch = try XCTUnwrap(
            firstOperations.first {
                $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
                    && $0.entityId == eventId
            }
        )

        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder should review this.",
            mentionedUserIds: [bobId],
            mentionEventId: secondEventId
        )

        let unrelated = SyncOperation(
            entityType: SyncEntityType.project.rawValue,
            entityId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            operationType: "update",
            payload: try JSONSerialization.data(withJSONObject: ["title": "Unrelated"]),
            changedFields: ["title"]
        )
        harness.context.insert(unrelated)
        try harness.context.save()

        let queued = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let laterUpdate = try XCTUnwrap(
            queued.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
                    && $0.id != firstUpdate.id
            }
        )
        let laterDispatch = try XCTUnwrap(
            queued.first {
                $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
                    && $0.entityId == secondEventId
            }
        )
        XCTAssertEqual(laterUpdate.dependsOnId, firstUpdate.id.uuidString)

        harness.dataController.syncEngine.cancelOperation(firstUpdate)

        let remaining = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let remainingIds = Set(remaining.map(\.id))
        XCTAssertFalse(remainingIds.contains(firstUpdate.id))
        XCTAssertFalse(
            remainingIds.contains(firstDispatch.id),
            "discarding an uncommitted update must also discard its impossible event"
        )
        XCTAssertNil(
            laterUpdate.dependsOnId,
            "the later full replacement safely inherits the discarded predecessor's dependency"
        )
        XCTAssertEqual(laterDispatch.dependsOnId, laterUpdate.id.uuidString)
        XCTAssertTrue(remainingIds.contains(unrelated.id))
        XCTAssertNil(unrelated.dependsOnId)
        XCTAssertFalse(
            remaining.contains { $0.dependsOnId == firstUpdate.id.uuidString },
            "discard must never leave a dangling mention dependency"
        )
        XCTAssertEqual(harness.note.content, "@Bob Builder should review this.")
        XCTAssertEqual(harness.note.mentionedUserIds, [bobId])
        XCTAssertTrue(
            harness.note.needsSync,
            "the surviving replacement remains the local authoritative state"
        )
    }

    func testDiscardFailureRestoresUpdateNoteQueueAndEveryDependency() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able first.",
            mentionedUserIds: [aliceId],
            mentionEventId: eventId
        )
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder second.",
            mentionedUserIds: [bobId],
            mentionEventId: secondEventId
        )
        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let updates = operations
            .filter {
                ProjectNoteMentionEditSync.isUpdateOperation($0)
            }
            .sorted { $0.createdAt < $1.createdAt }
        let first = try XCTUnwrap(updates.first)
        let second = try XCTUnwrap(updates.last)
        XCTAssertEqual(second.dependsOnId, first.id.uuidString)
        let additionalDependent = SyncOperation(
            entityType: SyncEntityType.projectNote.rawValue,
            entityId: harness.note.id,
            operationType: "delete",
            payload: Data(),
            changedFields: ["deletedAt"],
            dependsOnId: second.id.uuidString
        )
        harness.context.insert(additionalDependent)
        try harness.context.save()
        let beforeOperations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let before = ProjectNoteMentionEditSync.discardStateSnapshot(
            note: harness.note,
            operations: beforeOperations
        )
        _ = ProjectNoteMentionEditSync.prepareForDiscard(
            second,
            in: beforeOperations
        )
        XCTAssertEqual(
            try currentDiscardState(
                noteId: harness.note.id,
                context: harness.context
            ),
            before,
            "discard planning must be side-effect free"
        )

        var didInjectFailure = false
        harness.dataController.syncEngine
            .projectNoteDiscardFailureInjector = {
                didInjectFailure = true
                throw ForcedDiscardFailure.stop
            }
        defer {
            harness.dataController.syncEngine
                .projectNoteDiscardFailureInjector = nil
        }

        harness.dataController.syncEngine.cancelOperation(second)

        XCTAssertTrue(didInjectFailure)
        XCTAssertEqual(
            try currentDiscardState(
                noteId: harness.note.id,
                context: harness.context
            ),
            before,
            "failed update discard must restore the full note and queue"
        )
        XCTAssertEqual(
            additionalDependent.dependsOnId,
            second.id.uuidString,
            "every surviving dependency edge must be restored"
        )
    }

    func testFailedDiscardRecoveryCompletesBeforeCompetingClaimCommits() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able first.",
            mentionedUserIds: [aliceId],
            mentionEventId: eventId
        )
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder second.",
            mentionedUserIds: [bobId],
            mentionEventId: secondEventId
        )

        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let first = try XCTUnwrap(
            operations.first {
                ProjectNoteMentionEditSync.isUpdateOperation($0)
                    && mentionEventId(in: $0) == eventId
            }
        )
        let second = try XCTUnwrap(
            operations.first {
                ProjectNoteMentionEditSync.isUpdateOperation($0)
                    && mentionEventId(in: $0) == secondEventId
            }
        )
        let before = ProjectNoteMentionEditSync.discardStateSnapshot(
            note: harness.note,
            operations: operations
        )
        let container = harness.context.container
        let firstId = first.id
        let claimDate = Date(timeIntervalSince1970: 1_760_000_000)
        let competitorAttempting = DispatchSemaphore(value: 0)
        let competitorFinished = DispatchSemaphore(value: 0)
        let competitorError = ThreadSafeErrorBox()
        var didInjectFailure = false

        harness.dataController.syncEngine
            .projectNoteDiscardFailureInjector = {
                didInjectFailure = true
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { competitorFinished.signal() }
                    do {
                        let context = ModelContext(container)
                        let descriptor = FetchDescriptor<SyncOperation>(
                            predicate: #Predicate {
                                $0.id == firstId
                            }
                        )
                        guard let operation =
                            try context.fetch(descriptor).first else {
                            throw ForcedDiscardFailure.missingOperation
                        }
                        competitorAttempting.signal()
                        let didClaim =
                            try ProjectNoteMentionEditSync
                            .claimForExecution(
                                operation,
                                context: context,
                                refreshFromStore: true,
                                now: claimDate
                            )
                        guard didClaim else {
                            throw ForcedDiscardFailure.claimRejected
                        }
                        ProjectNoteMentionQueueCoordinator.shared.release(
                            operationId: firstId
                        )
                    } catch {
                        competitorError.store(error)
                    }
                }
                guard competitorAttempting.wait(
                    timeout: .now() + 5
                ) == .success else {
                    throw ForcedDiscardFailure.competitorDidNotStart
                }
                throw ForcedDiscardFailure.stop
            }
        defer {
            harness.dataController.syncEngine
                .projectNoteDiscardFailureInjector = nil
        }

        harness.dataController.syncEngine.cancelOperation(second)

        XCTAssertTrue(didInjectFailure)
        XCTAssertEqual(
            competitorFinished.wait(timeout: .now() + 5),
            .success
        )
        if let error = competitorError.value {
            XCTFail("competing queue claim failed: \(error)")
        }

        let verificationContext = ModelContext(container)
        let after = try currentDiscardState(
            noteId: harness.note.id,
            context: verificationContext
        )
        XCTAssertEqual(after.note, before.note)
        XCTAssertEqual(
            after.operations.map(\.id),
            before.operations.map(\.id),
            "failed discard recovery must restore every removed queue row exactly once"
        )
        XCTAssertEqual(
            after.operations.filter { $0.id != firstId },
            before.operations.filter { $0.id != firstId },
            "a competing claim may change only the operation it legitimately owns"
        )
        let claimed = try XCTUnwrap(
            after.operations.first { $0.id == firstId }
        )
        XCTAssertEqual(claimed.status, "inProgress")
        XCTAssertEqual(claimed.lastAttemptedAt, claimDate)
    }

    func testQueueCoordinatorKeepsRecoveryAheadOfWaitingMutation() throws {
        let coordinator = ProjectNoteMentionQueueCoordinator.shared
        let recoveryStarted = DispatchSemaphore(value: 0)
        let allowRecoveryToFinish = DispatchSemaphore(value: 0)
        let ownerFinished = DispatchSemaphore(value: 0)
        let competitorAttempting = DispatchSemaphore(value: 0)
        let competitorEntered = DispatchSemaphore(value: 0)
        let backgroundError = ThreadSafeErrorBox()

        DispatchQueue.global(qos: .userInitiated).async {
            defer { ownerFinished.signal() }
            do {
                let _: Void = try coordinator.withMutation(
                    recoveringWith: { _ in
                        recoveryStarted.signal()
                        guard allowRecoveryToFinish.wait(
                            timeout: .now() + 5
                        ) == .success else {
                            backgroundError.store(
                                ForcedDiscardFailure.recoveryTimedOut
                            )
                            return
                        }
                    }
                ) { _ in
                    throw ForcedDiscardFailure.stop
                }
                backgroundError.store(
                    ForcedDiscardFailure.unexpectedSuccess
                )
            } catch ForcedDiscardFailure.stop {
                return
            } catch {
                backgroundError.store(error)
            }
        }

        XCTAssertEqual(
            recoveryStarted.wait(timeout: .now() + 5),
            .success
        )
        DispatchQueue.global(qos: .userInitiated).async {
            competitorAttempting.signal()
            _ = coordinator.withMutation { _ in
                competitorEntered.signal()
            }
        }
        XCTAssertEqual(
            competitorAttempting.wait(timeout: .now() + 5),
            .success
        )
        XCTAssertEqual(
            competitorEntered.wait(timeout: .now() + 0.1),
            .timedOut,
            "a waiting queue mutation must not enter while recovery is running"
        )

        allowRecoveryToFinish.signal()
        XCTAssertEqual(
            ownerFinished.wait(timeout: .now() + 5),
            .success
        )
        XCTAssertEqual(
            competitorEntered.wait(timeout: .now() + 5),
            .success
        )
        if let error = backgroundError.value {
            XCTFail("queue coordinator recovery failed: \(error)")
        }
    }

    func testFailedDiscardDoesNotOverwriteUnrelatedActiveCompletion() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able first.",
            mentionedUserIds: [aliceId],
            mentionEventId: eventId
        )
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder second.",
            mentionedUserIds: [bobId],
            mentionEventId: secondEventId
        )
        let unrelated = SyncOperation(
            entityType: SyncEntityType.project.rawValue,
            entityId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            operationType: "update",
            payload: try JSONSerialization.data(
                withJSONObject: ["title": "Unrelated"]
            ),
            changedFields: ["title"]
        )
        harness.context.insert(unrelated)
        try harness.context.save()

        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let discarded = try XCTUnwrap(
            operations.first {
                ProjectNoteMentionEditSync.isUpdateOperation($0)
                    && mentionEventId(in: $0) == secondEventId
            }
        )
        let discardedId = discarded.id
        let actorContext = ModelContext(harness.context.container)
        let unrelatedId = unrelated.id
        let actorOperation = try XCTUnwrap(
            actorContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate {
                        $0.id == unrelatedId
                    }
                )
            ).first
        )
        let claimedAt = Date(timeIntervalSince1970: 1_760_000_000)
        var leaseActive = try ProjectNoteMentionEditSync.claimForExecution(
            actorOperation,
            context: actorContext,
            refreshFromStore: true,
            now: claimedAt
        )
        XCTAssertTrue(leaseActive)
        defer {
            if leaseActive {
                ProjectNoteMentionQueueCoordinator.shared.release(
                    operationId: unrelatedId
                )
            }
        }

        let completedAt = Date(timeIntervalSince1970: 1_760_000_100)
        var didCommitUnrelatedCompletion = false
        harness.dataController.syncEngine
            .projectNoteDiscardFailureInjector = {
                try actorContext.transaction {
                    actorOperation.status = "completed"
                    actorOperation.completedAt = completedAt
                }
                didCommitUnrelatedCompletion = true
                throw ForcedDiscardFailure.stop
            }
        defer {
            harness.dataController.syncEngine
                .projectNoteDiscardFailureInjector = nil
        }

        harness.dataController.syncEngine.cancelOperation(discarded)

        XCTAssertTrue(didCommitUnrelatedCompletion)
        let verificationContext = ModelContext(harness.context.container)
        let completedOperation = try XCTUnwrap(
            verificationContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate {
                        $0.id == unrelatedId
                    }
                )
            ).first
        )
        XCTAssertEqual(completedOperation.status, "completed")
        XCTAssertEqual(completedOperation.completedAt, completedAt)
        XCTAssertNotNil(
            try verificationContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate {
                        $0.id == discardedId
                    }
                )
            ).first,
            "the failed discard must still restore its own deleted operation"
        )

        ProjectNoteMentionQueueCoordinator.shared.release(
            operationId: unrelatedId
        )
        leaseActive = false
    }

    func testFailedDiscardPreservesConcurrentInboundNoteFields() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able first.",
            mentionedUserIds: [aliceId],
            mentionEventId: eventId
        )
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder second.",
            mentionedUserIds: [bobId],
            mentionEventId: secondEventId
        )
        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let discarded = try XCTUnwrap(
            operations.first {
                ProjectNoteMentionEditSync.isUpdateOperation($0)
                    && mentionEventId(in: $0) == secondEventId
            }
        )
        let discardedId = discarded.id
        let expectedContent = harness.note.content
        let expectedMentions = harness.note.mentionedUserIdsString
        let expectedNeedsSync = harness.note.needsSync
        let expectedUpdatedAt = harness.note.updatedAt

        let inboundContext = ModelContext(harness.context.container)
        let inboundNote = try XCTUnwrap(
            ProjectNoteMentionEditSync.fetchProjectNote(
                matching: harness.note.id,
                in: inboundContext
            )
        )
        let inboundLastSyncedAt =
            Date(timeIntervalSince1970: 1_760_000_200)
        let inboundAttachments =
            #"["https://example.com/inbound-photo.jpg"]"#
        var didCommitInboundMerge = false
        harness.dataController.syncEngine
            .projectNoteDiscardFailureInjector = {
                try inboundContext.transaction {
                    inboundNote.lastSyncedAt = inboundLastSyncedAt
                    inboundNote.attachmentsJSON = inboundAttachments
                }
                didCommitInboundMerge = true
                throw ForcedDiscardFailure.stop
            }
        defer {
            harness.dataController.syncEngine
                .projectNoteDiscardFailureInjector = nil
        }

        harness.dataController.syncEngine.cancelOperation(discarded)

        XCTAssertTrue(didCommitInboundMerge)
        let verificationContext = ModelContext(harness.context.container)
        let restoredNote = try XCTUnwrap(
            ProjectNoteMentionEditSync.fetchProjectNote(
                matching: harness.note.id,
                in: verificationContext
            )
        )
        XCTAssertEqual(restoredNote.content, expectedContent)
        XCTAssertEqual(
            restoredNote.mentionedUserIdsString,
            expectedMentions
        )
        XCTAssertEqual(restoredNote.needsSync, expectedNeedsSync)
        XCTAssertEqual(restoredNote.updatedAt, expectedUpdatedAt)
        XCTAssertEqual(restoredNote.lastSyncedAt, inboundLastSyncedAt)
        XCTAssertEqual(restoredNote.attachmentsJSON, inboundAttachments)
        XCTAssertNotNil(
            try verificationContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate {
                        $0.id == discardedId
                    }
                )
            ).first
        )
    }

    func testFailedOfflineCreateDiscardPreservesConcurrentSurvivingNote() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.note.needsSync = true
        try harness.context.save()
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: harness.note.id,
                operationType: "create",
                changedFields: [
                    "id": harness.note.id,
                    "project_id": harness.note.projectId,
                    "company_id": harness.note.companyId,
                    "author_id": harness.note.authorId,
                    "content": harness.note.content,
                ],
                deferPush: true
            )
        )
        let createId = create.id
        let inboundContext = ModelContext(harness.context.container)
        let inboundNote = try XCTUnwrap(
            ProjectNoteMentionEditSync.fetchProjectNote(
                matching: harness.note.id,
                in: inboundContext
            )
        )
        let inboundLastSyncedAt =
            Date(timeIntervalSince1970: 1_760_000_300)
        let inboundAttachments =
            #"["https://example.com/surviving-note.jpg"]"#
        var didCommitInboundMerge = false
        harness.dataController.syncEngine
            .projectNoteDiscardFailureInjector = {
                try inboundContext.transaction {
                    inboundNote.lastSyncedAt = inboundLastSyncedAt
                    inboundNote.attachmentsJSON = inboundAttachments
                }
                didCommitInboundMerge = true
                throw ForcedDiscardFailure.stop
            }
        defer {
            harness.dataController.syncEngine
                .projectNoteDiscardFailureInjector = nil
        }

        harness.dataController.syncEngine.cancelOperation(create)

        XCTAssertTrue(didCommitInboundMerge)
        let verificationContext = ModelContext(harness.context.container)
        let survivingNote = try XCTUnwrap(
            ProjectNoteMentionEditSync.fetchProjectNote(
                matching: harness.note.id,
                in: verificationContext
            )
        )
        XCTAssertEqual(survivingNote.lastSyncedAt, inboundLastSyncedAt)
        XCTAssertEqual(survivingNote.attachmentsJSON, inboundAttachments)
        XCTAssertNotNil(
            try verificationContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate {
                        $0.id == createId
                    }
                )
            ).first
        )
    }

    func testDiscardFailureRestoresDeleteTombstoneAndQueue() throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let deletedAt = Date(timeIntervalSince1970: 1_750_000_000)
        XCTAssertTrue(
            harness.dataController.syncEngine.recordProjectNoteDelete(
                note: harness.note,
                deletedAt: deletedAt
            )
        )
        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let delete = try XCTUnwrap(
            operations.first {
                $0.entityType == SyncEntityType.projectNote.rawValue
                    && $0.operationType == "delete"
            }
        )
        let before = ProjectNoteMentionEditSync.discardStateSnapshot(
            note: harness.note,
            operations: operations
        )
        var didInjectFailure = false
        harness.dataController.syncEngine
            .projectNoteDiscardFailureInjector = {
                didInjectFailure = true
                throw ForcedDiscardFailure.stop
            }
        defer {
            harness.dataController.syncEngine
                .projectNoteDiscardFailureInjector = nil
        }

        harness.dataController.syncEngine.cancelOperation(delete)

        XCTAssertTrue(didInjectFailure)
        XCTAssertEqual(
            try currentDiscardState(
                noteId: harness.note.id,
                context: harness.context
            ),
            before,
            "failed delete discard must restore its tombstone and queue"
        )
        XCTAssertEqual(harness.note.deletedAt, deletedAt)
        XCTAssertTrue(harness.note.needsSync)
    }

    func testDiscardFailureRestoresOfflineCreateChainAndLocalNote() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.note.needsSync = true
        try harness.context.save()
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: harness.note.id,
                operationType: "create",
                changedFields: [
                    "id": harness.note.id,
                    "project_id": harness.note.projectId,
                    "company_id": harness.note.companyId,
                    "author_id": harness.note.authorId,
                    "content": harness.note.content,
                ],
                deferPush: true
            )
        )
        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@Bob Builder offline edit.",
                mentionedUserIds: [bobId],
                mentionEventId: eventId
            )
        )
        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        XCTAssertEqual(operations.count, 3)
        let before = ProjectNoteMentionEditSync.discardStateSnapshot(
            note: harness.note,
            operations: operations
        )
        var didInjectFailure = false
        harness.dataController.syncEngine
            .projectNoteDiscardFailureInjector = {
                didInjectFailure = true
                throw ForcedDiscardFailure.stop
            }
        defer {
            harness.dataController.syncEngine
                .projectNoteDiscardFailureInjector = nil
        }

        harness.dataController.syncEngine.cancelOperation(create)

        XCTAssertTrue(didInjectFailure)
        XCTAssertEqual(
            try currentDiscardState(
                noteId: harness.note.id,
                context: harness.context
            ),
            before,
            "failed create discard must restore the note and complete chain"
        )
    }

    func testDiscardOnlyMentionUpdateRestoresPersistedPreEditState() throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let originalContent = harness.note.content
        let originalUpdatedAt = harness.note.updatedAt
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder should review this.",
            mentionedUserIds: [bobId],
            mentionEventId: eventId
        )
        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let update = try XCTUnwrap(
            operations.first {
                $0.operationType
                    == ProjectNoteMentionEditSync.updateOperationType
            }
        )

        harness.dataController.syncEngine.cancelOperation(update)

        XCTAssertEqual(harness.note.content, originalContent)
        XCTAssertEqual(harness.note.mentionedUserIds, [aliceId])
        XCTAssertNil(originalUpdatedAt)
        XCTAssertNil(harness.note.updatedAt)
        XCTAssertFalse(harness.note.needsSync)
        let remaining = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        XCTAssertFalse(
            remaining.contains {
                ProjectNoteMentionEditSync.bypassesGenericCoalescing($0)
            }
        )
    }

    func testDiscardMentionUpdateRestoresNonNilPreviousTimestamp() throws {
        let harness = try makeHarness(previousMentionIds: [aliceId])
        let originalUpdatedAt = Date(
            timeIntervalSince1970: 1_700_000_000
        )
        harness.note.updatedAt = originalUpdatedAt
        try harness.context.save()
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder should review this.",
            mentionedUserIds: [bobId],
            mentionEventId: eventId
        )
        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let update = try XCTUnwrap(
            operations.first {
                $0.operationType
                    == ProjectNoteMentionEditSync.updateOperationType
            }
        )

        harness.dataController.syncEngine.cancelOperation(update)

        XCTAssertEqual(
            try XCTUnwrap(harness.note.updatedAt)
                .timeIntervalSince1970,
            originalUpdatedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testDiscardNewestMentionUpdateRestoresSurvivingOlderPayload() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able first state.",
            mentionedUserIds: [aliceId],
            mentionEventId: eventId
        )
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder discarded state.",
            mentionedUserIds: [bobId],
            mentionEventId: secondEventId
        )
        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let updates = operations
            .filter {
                $0.operationType
                    == ProjectNoteMentionEditSync.updateOperationType
            }
            .sorted { $0.createdAt < $1.createdAt }
        let firstUpdate = try XCTUnwrap(updates.first)
        let newestUpdate = try XCTUnwrap(updates.last)

        harness.dataController.syncEngine.cancelOperation(newestUpdate)

        XCTAssertEqual(harness.note.content, "@Alice Able first state.")
        XCTAssertEqual(harness.note.mentionedUserIds, [aliceId])
        XCTAssertTrue(harness.note.needsSync)
        let remaining = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        XCTAssertTrue(remaining.contains { $0.id == firstUpdate.id })
        XCTAssertFalse(remaining.contains { $0.id == newestUpdate.id })
    }

    func testLaterEditDoesNotRetargetAnotherNotesDispatch() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder should review this.",
            mentionedUserIds: [bobId],
            mentionEventId: eventId
        )

        let firstOperations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let firstUpdate = try XCTUnwrap(
            firstOperations.first {
                $0.entityId == noteId
                    && $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )

        let otherNote = ProjectNote(
            id: "99999999-9999-4999-8999-999999999999",
            projectId: harness.note.projectId,
            companyId: harness.note.companyId,
            authorId: authorId,
            content: "Initial note."
        )
        harness.context.insert(otherNote)
        try harness.context.save()

        harness.dataController.updateProjectNoteContent(
            note: otherNote,
            content: "@Alice Able should review this.",
            mentionedUserIds: [aliceId],
            mentionEventId: secondEventId
        )

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let firstDispatch = try XCTUnwrap(
            operations.first {
                $0.entityId == eventId
                    && $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
            }
        )
        XCTAssertEqual(
            firstDispatch.dependsOnId,
            firstUpdate.id.uuidString,
            "an edit may only reorder dispatches created for that same note"
        )
    }

    func testCompletedUpdateReleasesDependentMentionDispatchForSameDrain() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder should review this.",
            mentionedUserIds: [bobId],
            mentionEventId: eventId
        )

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let update = try XCTUnwrap(
            operations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )
        let dispatch = try XCTUnwrap(
            operations.first {
                $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
            }
        )

        update.status = "completed"
        update.completedAt = Date()

        XCTAssertEqual(
            ProjectNoteMentionEditSync.readyPendingOperationIds(in: operations),
            Set([dispatch.id]),
            "the completed update must release its dispatch for the same push drain"
        )
    }

    func testLongLivedDataActorRefreshesMainContextDispatchRetarget() async throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Alice Able should review this.",
            mentionedUserIds: [aliceId],
            mentionEventId: eventId
        )

        let initialOperations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let firstUpdate = try XCTUnwrap(
            initialOperations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )
        let firstDispatch = try XCTUnwrap(
            initialOperations.first {
                $0.operationType == ProjectNoteMentionEditSync.dispatchOperationType
            }
        )

        let actor = DataActor(modelContainer: harness.context.container)
        await actor.configure()
        let initiallyReadyIds =
            await actor.readyPendingProjectNoteMentionOperationIds()
        XCTAssertEqual(
            initiallyReadyIds,
            Set([firstUpdate.id])
        )

        firstUpdate.status = "completed"
        firstUpdate.completedAt = Date()
        try harness.context.save()
        let readyAfterCompletion =
            await actor.readyPendingProjectNoteMentionOperationIds()
        XCTAssertEqual(
            readyAfterCompletion,
            Set([firstDispatch.id]),
            "the actor must first register D1 as ready"
        )
        let staleEligibleSnapshot = Set([firstDispatch.id])

        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder should review this.",
            mentionedUserIds: [bobId],
            mentionEventId: secondEventId
        )
        let retargetedOperations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let secondUpdate = try XCTUnwrap(
            retargetedOperations.first {
                $0.operationType
                    == ProjectNoteMentionEditSync.updateOperationType
                    && $0.id != firstUpdate.id
            }
        )
        XCTAssertEqual(firstDispatch.dependsOnId, secondUpdate.id.uuidString)
        XCTAssertTrue(staleEligibleSnapshot.contains(firstDispatch.id))
        XCTAssertFalse(
            ProjectNoteMentionEditSync.isReadyForExecution(
                firstDispatch,
                in: retargetedOperations
            ),
            "an operation eligible in the pass snapshot must fail the immediate preflight after retarget"
        )

        let refreshedReadyIds =
            await actor.readyPendingProjectNoteMentionOperationIds()
        XCTAssertEqual(refreshedReadyIds, Set([secondUpdate.id]))
        XCTAssertFalse(
            refreshedReadyIds.contains(firstDispatch.id),
            "the long-lived actor must not execute stale D1 before retargeted U2"
        )
    }

    func testMentionEditOperationsBypassGenericCoalescing() throws {
        let harness = try makeHarness(previousMentionIds: [])
        for (content, event) in [
            ("@Alice Able first pass.", eventId),
            ("@Bob Builder second pass.", secondEventId),
        ] {
            let plan = ProjectNoteMentionEditPlan.make(
                content: content,
                teamMembers: teamMembers,
                currentUserId: authorId
            )
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: plan.content,
                mentionedUserIds: plan.mentionedUserIds,
                mentionEventId: event
            )
        }

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let coalesced = OutboundProcessor().coalesceOperations(operations)

        XCTAssertEqual(
            coalesced.filter {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }.count,
            2,
            "each immutable edit event must reach the RPC in order"
        )
        XCTAssertTrue(
            operations.allSatisfy { $0.status == "pending" },
            "coalescing must not mark any durable mention operation superseded"
        )
    }

    func testMentionFieldMergeProtectionIncludesLocalStorageAlias() {
        let payload = try! JSONSerialization.data(
            withJSONObject: [ProjectNoteMentionEditSync.mentionedUserIdsPayloadKey: [bobId]]
        )
        let operation = SyncOperation(
            entityType: SyncEntityType.projectNote.rawValue,
            entityId: noteId,
            operationType: ProjectNoteMentionEditSync.updateOperationType,
            payload: payload,
            changedFields: [
                ProjectNoteMentionEditSync.mentionedUserIdsPayloadKey,
                "content",
            ]
        )
        operation.status = "parked"
        operation.createdAt = Date(timeIntervalSince1970: 0)

        let protected = SyncFieldGuard.protectedFields(
            from: [operation],
            now: Date()
        )

        XCTAssertTrue(protected.contains("mentioned_user_ids"))
        XCTAssertTrue(
            protected.contains("mentionedUserIdsString"),
            "a stale echo must not restore the old local mention list"
        )
        XCTAssertTrue(
            protected.contains("content"),
            "an unresolved durable edit stays authoritative until completion or explicit discard"
        )
    }

    func testUnresolvedMentionUpdatePreservesDirtyStateForBothInboundPaths() throws {
        let harness = try makeHarness(previousMentionIds: [])
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: "@Bob Builder should review this.",
            mentionedUserIds: [bobId],
            mentionEventId: eventId
        )

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let update = try XCTUnwrap(
            operations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )

        for unresolvedStatus in ["pending", "inProgress", "failed", "parked"] {
            update.status = unresolvedStatus
            XCTAssertTrue(
                ProjectNoteMentionEditSync.hasUnresolvedUpdate(
                    for: noteId,
                    in: operations
                ),
                "\(unresolvedStatus) must keep realtime and actor merges from clearing needsSync"
            )
        }

        update.status = "completed"
        XCTAssertFalse(
            ProjectNoteMentionEditSync.hasUnresolvedUpdate(
                for: noteId,
                in: operations
            ),
            "only a terminal server-confirmed update may release the dirty flag"
        )
    }

    func testUnresolvedDeletePreservesDirtyStateAcrossUUIDCase() {
        let legacyUppercaseId =
            "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF"
        let delete = SyncOperation(
            entityType: SyncEntityType.projectNote.rawValue,
            entityId: legacyUppercaseId.lowercased(),
            operationType: "delete",
            payload: Data(),
            changedFields: ["deleted_at"]
        )

        for unresolvedStatus in [
            "pending",
            "inProgress",
            "failed",
            "parked",
        ] {
            delete.status = unresolvedStatus
            XCTAssertTrue(
                ProjectNoteMentionEditSync.hasUnresolvedWrite(
                    for: legacyUppercaseId,
                    in: [delete]
                ),
                "\(unresolvedStatus) delete must keep inbound merges from clearing needsSync"
            )
        }

        delete.status = "completed"
        XCTAssertFalse(
            ProjectNoteMentionEditSync.hasUnresolvedWrite(
                for: legacyUppercaseId,
                in: [delete]
            )
        )
    }

    func testProjectNoteDeleteFieldGuardProtectsPullAndRealtimeAcrossLifecycleAndUUIDCase() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let legacyUppercaseId =
            "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF"
        let delete = SyncOperation(
            entityType: SyncEntityType.projectNote.rawValue,
            entityId: legacyUppercaseId.lowercased(),
            operationType: "delete",
            payload: Data(),
            // Legacy builds persisted the Supabase spelling. The alias must
            // keep those already-durable rows safe after upgrade.
            changedFields: ["deleted_at"]
        )
        delete.createdAt = Date(timeIntervalSince1970: 0)
        harness.context.insert(delete)
        try harness.context.save()

        for unresolvedStatus in [
            "pending",
            "inProgress",
            "failed",
            "parked",
        ] {
            delete.status = unresolvedStatus
            delete.lastAttemptedAt = nil
            delete.completedAt = nil
            try harness.context.save()
            let caseTolerantOperations =
                try ProjectNoteMentionEditSync
                .fetchProjectNoteOperations(
                    matching: legacyUppercaseId,
                    in: harness.context
                )
            let protected = SyncFieldGuard.protectedFields(
                from: caseTolerantOperations,
                now: Date(timeIntervalSince1970: 2_000_000_000)
            )
            let inboundAcceptedFields =
                Set(["content", "deletedAt"])
                .subtracting(protected)
            let realtimeProtectedFields = protected

            XCTAssertFalse(
                inboundAcceptedFields.contains("deletedAt"),
                "InboundProcessor must keep the local tombstone for \(unresolvedStatus)"
            )
            XCTAssertTrue(
                realtimeProtectedFields.contains("deletedAt"),
                "RealtimeProcessor must keep the local tombstone for \(unresolvedStatus)"
            )
            XCTAssertTrue(protected.contains("deleted_at"))
        }
    }

    func testNewProjectNoteDeleteRecordsCanonicalLocalGuardField() throws {
        let harness = try makeHarness(previousMentionIds: [])
        XCTAssertTrue(
            harness.dataController.syncEngine.recordProjectNoteDelete(
                note: harness.note
            )
        )
        let delete = try XCTUnwrap(
            try harness.context.fetch(FetchDescriptor<SyncOperation>())
                .first { $0.operationType == "delete" }
        )
        XCTAssertEqual(delete.getChangedFields(), ["deletedAt"])
        XCTAssertTrue(
            SyncFieldGuard.protectedFields(
                from: [delete],
                now: Date()
            ).contains("deletedAt")
        )
    }

    func testCleanupRetainsCompletedUpdateReferencedByPendingDispatch() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let plan = ProjectNoteMentionEditPlan.make(
            content: "@Bob Builder should review this.",
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        harness.dataController.updateProjectNoteContent(
            note: harness.note,
            content: plan.content,
            mentionedUserIds: plan.mentionedUserIds,
            mentionEventId: eventId
        )

        let operations = try harness.context.fetch(FetchDescriptor<SyncOperation>())
        let update = try XCTUnwrap(
            operations.first {
                $0.operationType == ProjectNoteMentionEditSync.updateOperationType
            }
        )
        update.status = "completed"
        update.completedAt = Date().addingTimeInterval(-25 * 60 * 60)
        try harness.context.save()

        harness.dataController.syncEngine.cleanupCompletedOperations()

        let remainingIds = Set(
            try harness.context.fetch(FetchDescriptor<SyncOperation>()).map(\.id)
        )
        XCTAssertTrue(
            remainingIds.contains(update.id),
            "cleanup must retain a completed dependency until its child finishes"
        )
    }

    func testDispatchRequestContainsOnlyPersistedEventProof() throws {
        let body = try JSONEncoder().encode(
            ProjectNoteMentionDispatchRequest(mentionEventId: eventId)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(Set(object.keys), ["eventType", "mentionEventId"])
        XCTAssertEqual(object["eventType"] as? String, "mention_edit")
        XCTAssertEqual(object["mentionEventId"] as? String, eventId)
    }

    func testLegacyAllTeamIdentityRequiresExactAuthoritativeRosterSet() {
        let canonicalMismatch = ProjectNoteMentionParser.editableDraft(
            in: "@[All Team](all-team) check this.",
            mentionedUserIds: [aliceId],
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        XCTAssertEqual(
            canonicalMismatch.identitySpans.map(\.recipient),
            [.unresolved]
        )
        let canonicalPlan = ProjectNoteMentionEditPlan.make(
            content: canonicalMismatch.text,
            teamMembers: teamMembers,
            currentUserId: authorId,
            identitySpans: canonicalMismatch.identitySpans
        )
        XCTAssertTrue(canonicalPlan.mentionedUserIds.isEmpty)
        XCTAssertEqual(canonicalPlan.unresolvedMentionNames, ["@All Team"])

        let plainMismatch = ProjectNoteMentionParser.editableDraft(
            in: "@All Team check this.",
            mentionedUserIds: [aliceId],
            teamMembers: teamMembers,
            currentUserId: authorId
        )
        XCTAssertEqual(
            plainMismatch.identitySpans.map(\.recipient),
            [.unresolved],
            "legacy plain group text must not widen a partial recipient set"
        )
        let plainPlan = ProjectNoteMentionEditPlan.make(
            content: plainMismatch.text,
            teamMembers: teamMembers,
            currentUserId: authorId,
            identitySpans: plainMismatch.identitySpans
        )
        XCTAssertTrue(plainPlan.mentionedUserIds.isEmpty)
        XCTAssertFalse(plainPlan.unresolvedMentionNames.isEmpty)
    }

    func testIdentitySpanRequiresCompleteBoundariesForUserAndGroup() {
        let userText = "mail@Bob Builder now"
        let userSpan = ProjectNoteMentionSpan(
            range: (userText as NSString).range(of: "@Bob Builder"),
            displayText: "@Bob Builder",
            recipient: .user(id: bobId)
        )
        let userPlan = ProjectNoteMentionEditPlan.make(
            content: userText,
            teamMembers: teamMembers,
            currentUserId: authorId,
            identitySpans: [userSpan]
        )
        XCTAssertTrue(userPlan.mentionedUserIds.isEmpty)
        XCTAssertFalse(userPlan.content.contains(bobId))

        let groupText = "@All Teamwork check this."
        let groupSpan = ProjectNoteMentionSpan(
            range: (groupText as NSString).range(of: "@All Team"),
            displayText: "@All Team",
            recipient: .allTeam
        )
        let groupPlan = ProjectNoteMentionEditPlan.make(
            content: groupText,
            teamMembers: teamMembers,
            currentUserId: authorId,
            identitySpans: [groupSpan]
        )
        XCTAssertTrue(groupPlan.mentionedUserIds.isEmpty)
        XCTAssertFalse(groupPlan.content.contains("(all-team)"))
    }

    func testAdjacentTextEditsInvalidateHiddenMentionIdentity() {
        let text = "@Bob Builder check this."
        let range = (text as NSString).range(of: "@Bob Builder")
        let span = ProjectNoteMentionSpan(
            range: range,
            displayText: "@Bob Builder",
            recipient: .user(id: bobId)
        )

        XCTAssertTrue(
            ProjectNoteMentionEditor.adjustingMentionSpans(
                [span],
                replacing: NSRange(
                    location: NSMaxRange(range),
                    length: 1
                ),
                with: ""
            ).isEmpty,
            "deleting the separator after a mention must drop its identity"
        )
        XCTAssertTrue(
            ProjectNoteMentionEditor.adjustingMentionSpans(
                [span],
                replacing: NSRange(
                    location: range.location,
                    length: 0
                ),
                with: "x"
            ).isEmpty,
            "an alphanumeric prefix must turn the token into ordinary text"
        )
        XCTAssertTrue(
            ProjectNoteMentionEditor.adjustingMentionSpans(
                [span],
                replacing: NSRange(
                    location: NSMaxRange(range),
                    length: 0
                ),
                with: "x"
            ).isEmpty,
            "an alphanumeric suffix must turn the token into ordinary text"
        )
    }

    func testEditBeforeClaimRetargetsStaleActorDispatchAndRejectsClaim() throws {
        let harness = try makeHarness(previousMentionIds: [])
        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@[Alice Able](\(aliceId)) first.",
                mentionedUserIds: [aliceId],
                mentionEventId: eventId
            )
        )
        let initial = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let firstUpdate = try XCTUnwrap(
            initial.first {
                ProjectNoteMentionEditSync.isUpdateOperation($0)
            }
        )
        let firstDispatch = try XCTUnwrap(
            initial.first {
                ProjectNoteMentionEditSync.isDispatchOperation($0)
            }
        )
        firstUpdate.status = "completed"
        firstUpdate.completedAt = Date()
        try harness.context.save()

        let actorContext = ModelContext(harness.context.container)
        let dispatchId = firstDispatch.id
        let staleActorDispatch = try XCTUnwrap(
            actorContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate { $0.id == dispatchId }
                )
            ).first
        )

        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@[Bob Builder](\(bobId)) second.",
                mentionedUserIds: [bobId],
                mentionEventId: secondEventId
            )
        )
        XCTAssertFalse(
            try ProjectNoteMentionEditSync.claimForExecution(
                staleActorDispatch,
                context: actorContext,
                refreshFromStore: true
            ),
            "a retarget committed first must invalidate the actor's stale ready snapshot"
        )
    }

    func testClaimBeforeEditKeepsActiveDispatchOnOriginalDependency() throws {
        let harness = try makeHarness(previousMentionIds: [])
        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@[Alice Able](\(aliceId)) first.",
                mentionedUserIds: [aliceId],
                mentionEventId: eventId
            )
        )
        let initial = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let firstUpdate = try XCTUnwrap(
            initial.first {
                ProjectNoteMentionEditSync.isUpdateOperation($0)
            }
        )
        let firstDispatch = try XCTUnwrap(
            initial.first {
                ProjectNoteMentionEditSync.isDispatchOperation($0)
            }
        )
        firstUpdate.status = "completed"
        firstUpdate.completedAt = Date()
        try harness.context.save()

        let actorContext = ModelContext(harness.context.container)
        let dispatchId = firstDispatch.id
        let actorDispatch = try XCTUnwrap(
            actorContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate { $0.id == dispatchId }
                )
            ).first
        )
        var leaseActive = try ProjectNoteMentionEditSync.claimForExecution(
            actorDispatch,
            context: actorContext,
            refreshFromStore: true
        )
        XCTAssertTrue(leaseActive)
        defer {
            if leaseActive {
                ProjectNoteMentionQueueCoordinator.shared.release(
                    operationId: dispatchId
                )
            }
        }

        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@[Bob Builder](\(bobId)) second.",
                mentionedUserIds: [bobId],
                mentionEventId: secondEventId
            )
        )
        let refreshed = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let persistedDispatch = try XCTUnwrap(
            refreshed.first { $0.id == dispatchId }
        )
        XCTAssertEqual(persistedDispatch.status, "inProgress")
        XCTAssertEqual(
            persistedDispatch.dependsOnId,
            firstUpdate.id.uuidString,
            "an already-claimed request must not be moved behind a later edit"
        )
        ProjectNoteMentionQueueCoordinator.shared.release(
            operationId: dispatchId
        )
        leaseActive = false
    }

    func testDeleteBeforeClaimRemovesStaleDispatchAndRejectsActorClaim() throws {
        let harness = try makeHarness(previousMentionIds: [])
        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@[Bob Builder](\(bobId)) review.",
                mentionedUserIds: [bobId],
                mentionEventId: eventId
            )
        )
        let initial = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let update = try XCTUnwrap(
            initial.first {
                ProjectNoteMentionEditSync.isUpdateOperation($0)
            }
        )
        let dispatch = try XCTUnwrap(
            initial.first {
                ProjectNoteMentionEditSync.isDispatchOperation($0)
            }
        )
        update.status = "completed"
        update.completedAt = Date()
        try harness.context.save()
        let actorContext = ModelContext(harness.context.container)
        let dispatchId = dispatch.id
        let staleDispatch = try XCTUnwrap(
            actorContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate { $0.id == dispatchId }
                )
            ).first
        )

        XCTAssertTrue(
            harness.dataController.syncEngine.recordProjectNoteDelete(
                note: harness.note
            )
        )
        XCTAssertFalse(
            try ProjectNoteMentionEditSync.claimForExecution(
                staleDispatch,
                context: actorContext,
                refreshFromStore: true
            )
        )
    }

    func testClaimBeforeDeletePreservesDispatchAndOrdersDeleteBehindIt() throws {
        let harness = try makeHarness(previousMentionIds: [])
        XCTAssertTrue(
            harness.dataController.updateProjectNoteContent(
                note: harness.note,
                content: "@[Bob Builder](\(bobId)) review.",
                mentionedUserIds: [bobId],
                mentionEventId: eventId
            )
        )
        let initial = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let update = try XCTUnwrap(
            initial.first {
                ProjectNoteMentionEditSync.isUpdateOperation($0)
            }
        )
        let dispatch = try XCTUnwrap(
            initial.first {
                ProjectNoteMentionEditSync.isDispatchOperation($0)
            }
        )
        update.status = "completed"
        update.completedAt = Date()
        try harness.context.save()
        let actorContext = ModelContext(harness.context.container)
        let dispatchId = dispatch.id
        let actorDispatch = try XCTUnwrap(
            actorContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate { $0.id == dispatchId }
                )
            ).first
        )
        var leaseActive = try ProjectNoteMentionEditSync.claimForExecution(
            actorDispatch,
            context: actorContext,
            refreshFromStore: true
        )
        XCTAssertTrue(leaseActive)
        defer {
            if leaseActive {
                ProjectNoteMentionQueueCoordinator.shared.release(
                    operationId: dispatchId
                )
            }
        }

        XCTAssertTrue(
            harness.dataController.syncEngine.recordProjectNoteDelete(
                note: harness.note
            )
        )
        let operations = try harness.context.fetch(
            FetchDescriptor<SyncOperation>()
        )
        let persistedDispatch = try XCTUnwrap(
            operations.first { $0.id == dispatchId }
        )
        let delete = try XCTUnwrap(
            operations.first {
                $0.entityType == SyncEntityType.projectNote.rawValue
                    && $0.entityId.lowercased() == noteId
                    && $0.operationType == "delete"
            }
        )
        XCTAssertEqual(persistedDispatch.status, "inProgress")
        XCTAssertEqual(delete.dependsOnId, dispatchId.uuidString)
        ProjectNoteMentionQueueCoordinator.shared.release(
            operationId: dispatchId
        )
        leaseActive = false
    }

    func testClaimLeaseBlocksConcurrentClaimButAllowsPersistedRetry() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let operation = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .project,
                entityId: harness.note.projectId,
                operationType: "update",
                changedFields: ["title": "Retry"],
                deferPush: true
            )
        )
        let actorContext = ModelContext(harness.context.container)
        let operationId = operation.id
        let actorOperation = try XCTUnwrap(
            actorContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate { $0.id == operationId }
                )
            ).first
        )
        var leaseActive = try ProjectNoteMentionEditSync.claimForExecution(
            actorOperation,
            context: actorContext,
            refreshFromStore: true
        )
        XCTAssertTrue(leaseActive)
        defer {
            if leaseActive {
                ProjectNoteMentionQueueCoordinator.shared.release(
                    operationId: operationId
                )
            }
        }
        XCTAssertFalse(
            try ProjectNoteMentionEditSync.claimForExecution(
                actorOperation,
                context: actorContext,
                refreshFromStore: true
            ),
            "a truly concurrent second execution must not claim the same row"
        )

        try actorContext.transaction {
            actorOperation.status = "pending"
            actorOperation.retryCount = 1
            actorOperation.lastError = "Transient"
        }
        ProjectNoteMentionQueueCoordinator.shared.release(
            operationId: operationId
        )
        leaseActive = false

        XCTAssertTrue(
            try ProjectNoteMentionEditSync.claimForExecution(
                actorOperation,
                context: actorContext,
                refreshFromStore: true
            ),
            "a later persisted retry must receive a fresh execution lease"
        )
        leaseActive = true
    }

    func testActiveClaimCannotBeDiscardedFromAnotherContext() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let operation = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .project,
                entityId: harness.note.projectId,
                operationType: "update",
                changedFields: ["title": "Claimed"],
                deferPush: true
            )
        )
        let actorContext = ModelContext(harness.context.container)
        let operationId = operation.id
        let actorOperation = try XCTUnwrap(
            actorContext.fetch(
                FetchDescriptor<SyncOperation>(
                    predicate: #Predicate { $0.id == operationId }
                )
            ).first
        )
        var leaseActive = try ProjectNoteMentionEditSync.claimForExecution(
            actorOperation,
            context: actorContext,
            refreshFromStore: true
        )
        XCTAssertTrue(leaseActive)
        defer {
            if leaseActive {
                ProjectNoteMentionQueueCoordinator.shared.release(
                    operationId: operationId
                )
            }
        }

        harness.dataController.syncEngine.cancelOperation(operation)
        XCTAssertTrue(
            try harness.context.fetch(
                FetchDescriptor<SyncOperation>()
            ).contains { $0.id == operationId },
            "discard must lose when execution claimed the row first"
        )
        ProjectNoteMentionQueueCoordinator.shared.release(
            operationId: operationId
        )
        leaseActive = false
    }

    func testDiscardFailedOrParkedDeleteRestoresNoteTombstone() throws {
        for status in ["failed", "parked"] {
            let harness = try makeHarness(previousMentionIds: [])
            XCTAssertTrue(
                harness.dataController.syncEngine.recordProjectNoteDelete(
                    note: harness.note
                )
            )
            let operations = try harness.context.fetch(
                FetchDescriptor<SyncOperation>()
            )
            let delete = try XCTUnwrap(
                operations.first {
                    $0.entityType == SyncEntityType.projectNote.rawValue
                        && $0.operationType == "delete"
                }
            )
            delete.status = status
            try harness.context.save()

            harness.dataController.syncEngine.cancelOperation(delete)

            let restored = try XCTUnwrap(
                ProjectNoteMentionEditSync.fetchProjectNote(
                    matching: noteId,
                    in: harness.context
                )
            )
            XCTAssertNil(
                restored.deletedAt,
                "\(status) delete discard must make the note visible again"
            )
            XCTAssertFalse(restored.needsSync)
            let remaining = try harness.context.fetch(
                FetchDescriptor<SyncOperation>()
            )
            XCTAssertFalse(remaining.contains { $0.id == delete.id })
            XCTAssertFalse(
                remaining.contains {
                    $0.dependsOnId?.lowercased()
                        == delete.id.uuidString.lowercased()
                }
            )
        }
    }

    func testDiscardDeleteKeepsDirtyStateWhenCreateStillSurvives() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: harness.note.id,
                operationType: "create",
                changedFields: ["id": harness.note.id],
                deferPush: true
            )
        )
        XCTAssertTrue(
            harness.dataController.syncEngine.recordProjectNoteDelete(
                note: harness.note
            )
        )
        let delete = try XCTUnwrap(
            harness.context.fetch(FetchDescriptor<SyncOperation>())
                .first {
                    $0.operationType == "delete"
                        && $0.entityId.lowercased() == noteId
                }
        )
        delete.status = "failed"
        try harness.context.save()

        harness.dataController.syncEngine.cancelOperation(delete)

        XCTAssertTrue(
            try harness.context.fetch(FetchDescriptor<SyncOperation>())
                .contains { $0.id == create.id }
        )
        let restored = try XCTUnwrap(
            ProjectNoteMentionEditSync.fetchProjectNote(
                matching: noteId,
                in: harness.context
            )
        )
        XCTAssertNil(restored.deletedAt)
        XCTAssertTrue(
            restored.needsSync,
            "the surviving unpushed create still owns the note's dirty state"
        )
    }

    func testRestartRecoveryRetiresParkedCreateDeleteChainAtomically() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let legacyId = "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF"
        harness.note.id = legacyId
        try harness.context.save()
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: legacyId.lowercased(),
                operationType: "create",
                changedFields: ["id": legacyId.lowercased()],
                deferPush: true
            )
        )
        create.status = "inProgress"
        try harness.context.save()
        XCTAssertTrue(
            harness.dataController.syncEngine.recordProjectNoteDelete(
                note: harness.note
            )
        )
        create.status = "parked"
        create.lastError = "Permanent rejection before retirement"
        try harness.context.save()

        let relaunchedContext = ModelContext(harness.context.container)
        let relaunchedController = DataController()
        relaunchedController.setModelContext(relaunchedContext)
        relaunchedController.syncEngine.configure(
            modelContext: relaunchedContext,
            connectivity: relaunchedController.connectivity
        )
        XCTAssertTrue(
            relaunchedController.syncEngine
                .reconcileParkedProjectNoteCreateDeleteChains()
        )

        let recoveredOperations = try relaunchedContext.fetch(
            FetchDescriptor<SyncOperation>()
        )
        XCTAssertTrue(
            recoveredOperations
                .filter {
                    $0.entityType == SyncEntityType.projectNote.rawValue
                        && $0.entityId.lowercased()
                            == legacyId.lowercased()
                }
                .allSatisfy { $0.status == "completed" }
        )
        let recoveredNote = try XCTUnwrap(
            ProjectNoteMentionEditSync.fetchProjectNote(
                matching: legacyId.lowercased(),
                in: relaunchedContext
            )
        )
        XCTAssertEqual(recoveredNote.id, legacyId)
        XCTAssertNotNil(recoveredNote.deletedAt)
        XCTAssertFalse(recoveredNote.needsSync)
    }

    func testNewProjectNoteIdsAreCanonicalLowercase() {
        let note = ProjectNote(
            projectId: "project",
            companyId: "company",
            authorId: authorId
        )
        XCTAssertEqual(note.id, note.id.lowercased())
    }

    func testLegacyUppercaseNoteIsFoundWhenDiscardingLowercaseCreate() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let legacyId = "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF"
        harness.note.id = legacyId
        try harness.context.save()
        let create = try XCTUnwrap(
            harness.dataController.syncEngine.recordOperation(
                entityType: .projectNote,
                entityId: legacyId.lowercased(),
                operationType: "create",
                changedFields: ["id": legacyId.lowercased()],
                deferPush: true
            )
        )

        harness.dataController.syncEngine.cancelOperation(create)

        XCTAssertNil(
            try ProjectNoteMentionEditSync.fetchProjectNote(
                matching: legacyId.lowercased(),
                in: harness.context
            )
        )
    }

    func testLegacyUppercaseInboundEchoPreservesLowercaseDeleteTombstone() throws {
        let harness = try makeHarness(previousMentionIds: [])
        let legacyId = "ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF"
        harness.note.id = legacyId
        harness.note.deletedAt = Date(timeIntervalSince1970: 1_720_000_000)
        harness.note.needsSync = true
        let delete = SyncOperation(
            entityType: SyncEntityType.projectNote.rawValue,
            entityId: legacyId.lowercased(),
            operationType: "delete",
            payload: try JSONSerialization.data(
                withJSONObject: ["deleted_at": "2026-07-23T00:00:00Z"]
            ),
            changedFields: ["deleted_at"]
        )
        harness.context.insert(delete)
        try harness.context.save()
        let originalDeletedAt = harness.note.deletedAt

        let dto = ProjectNoteDTO(
            id: legacyId.lowercased(),
            projectId: harness.note.projectId,
            companyId: harness.note.companyId,
            authorId: authorId,
            content: "Stale server content",
            attachments: [],
            mentionedUserIds: [],
            photoURL: nil,
            eventKind: nil,
            contentMetadata: nil,
            createdAt: "2026-07-23T00:00:00Z",
            updatedAt: nil,
            deletedAt: nil
        )
        ProjectNotesViewModel.mergeFetchedNotes(
            [dto],
            projectId: harness.note.projectId,
            context: harness.context
        )

        let notes = try harness.context.fetch(
            FetchDescriptor<ProjectNote>()
        )
        XCTAssertEqual(notes.count, 1)
        let preserved = try XCTUnwrap(notes.first)
        XCTAssertEqual(preserved.id, legacyId)
        XCTAssertEqual(preserved.deletedAt, originalDeletedAt)
        XCTAssertTrue(preserved.needsSync)
        XCTAssertEqual(preserved.content, "@Alice Able should review this.")
        XCTAssertEqual(
            try ProjectNoteMentionEditSync.fetchProjectNoteOperations(
                matching: legacyId,
                in: harness.context
            ).map(\.id),
            [delete.id],
            "case-tolerant inbound protection must see the lowercase queued delete"
        )
    }

    private var teamMembers: [TeamMember] {
        [
            TeamMember(id: aliceId, firstName: "Alice", lastName: "Able", role: "Crew"),
            TeamMember(id: bobId, firstName: "Bob", lastName: "Builder", role: "Crew"),
            TeamMember(id: authorId, firstName: "Alex", lastName: "Author", role: "Crew"),
        ]
    }

    private func currentDiscardState(
        noteId: String,
        context: ModelContext
    ) throws -> ProjectNoteMentionEditSync.DiscardStateSnapshot {
        let note = try XCTUnwrap(
            ProjectNoteMentionEditSync.fetchProjectNote(
                matching: noteId,
                in: context
            )
        )
        return ProjectNoteMentionEditSync.discardStateSnapshot(
            note: note,
            operations: try context.fetch(
                FetchDescriptor<SyncOperation>()
            )
        )
    }

    private func makeHarness(
        previousMentionIds: [String]
    ) throws -> (
        dataController: DataController,
        context: ModelContext,
        note: ProjectNote
    ) {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let note = ProjectNote(
            id: noteId,
            projectId: "66666666-6666-4666-8666-666666666666",
            companyId: "77777777-7777-4777-8777-777777777777",
            authorId: authorId,
            content: "@Alice Able should review this."
        )
        note.mentionedUserIds = previousMentionIds
        context.insert(note)
        try context.save()

        let dataController = DataController()
        dataController.setModelContext(context)
        dataController.syncEngine.configure(
            modelContext: context,
            connectivity: dataController.connectivity
        )

        return (dataController, context, note)
    }

    private func decodedPayload(_ operation: SyncOperation) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: operation.payload) as? [String: Any]
        )
    }

    private func mentionEventId(
        in operation: SyncOperation
    ) -> String? {
        guard let payload =
            try? JSONSerialization.jsonObject(
                with: operation.payload
            ) as? [String: Any] else {
            return nil
        }
        return payload[
            ProjectNoteMentionEditSync.eventIdPayloadKey
        ] as? String
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Project.self,
            ProjectTask.self,
            TaskType.self,
            TaskTypeReminder.self,
            TaskReminder.self,
            User.self,
            Client.self,
            SubClient.self,
            ProjectNote.self,
            ProjectPhoto.self,
            SyncOperation.self,
            ProjectVinylOrderMarker.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private final class ThreadSafeErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Error?

    var value: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func store(_ error: Error) {
        lock.lock()
        storedValue = error
        lock.unlock()
    }
}
