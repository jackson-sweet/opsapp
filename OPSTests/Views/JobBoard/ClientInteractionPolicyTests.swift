//
//  ClientInteractionPolicyTests.swift
//  OPSTests
//
//  Regression coverage for bug 9a8bbe5e: client deletion must preserve the
//  operator's reassignment intent, dismiss invalidated detail routes, and expose
//  the same permission-aware long-press actions in Universal Search.
//

import XCTest
@testable import OPS

@MainActor
final class ClientInteractionPolicyTests: XCTestCase {

    func testClientLongPressActionsArePermissionScoped() {
        XCTAssertEqual(
            ClientLongPressActionPolicy.actions(
                canCreateProject: false,
                canDeleteClient: false
            ),
            [.viewClient]
        )

        XCTAssertEqual(
            ClientLongPressActionPolicy.actions(
                canCreateProject: true,
                canDeleteClient: false
            ),
            [.viewClient, .addProject]
        )

        XCTAssertEqual(
            ClientLongPressActionPolicy.actions(
                canCreateProject: false,
                canDeleteClient: true
            ),
            [.viewClient, .deleteClient]
        )

        XCTAssertEqual(
            ClientLongPressActionPolicy.actions(
                canCreateProject: true,
                canDeleteClient: true
            ),
            [.viewClient, .addProject, .deleteClient]
        )
    }

    func testDeletionTargetsAcceptUUIDsAndRejectSelfDeletedAndOtherCompanies() {
        let deleting = Client(
            id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            name: "Delete me",
            companyId: "company-a"
        )
        let validUUID = Client(
            id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            name: "Valid target",
            companyId: "company-a"
        )
        let deleted = Client(
            id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
            name: "Deleted target",
            companyId: "company-a"
        )
        deleted.deletedAt = Date()
        let otherCompany = Client(
            id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
            name: "Wrong company",
            companyId: "company-b"
        )

        let result = ClientDeletionTargetPolicy.candidates(
            from: [deleting, validUUID, deleted, otherCompany],
            deleting: deleting
        )

        XCTAssertEqual(result.map(\.id), [validUUID.id])
    }

    func testDeletionTargetsDeduplicateCaseVariantIdsWithoutCrashing() {
        let deleting = Client(id: "CLIENT-SELF", name: "Delete me", companyId: "company-a")
        let duplicateA = Client(id: "CLIENT-TARGET", name: "Alpha", companyId: "company-a")
        let duplicateB = Client(id: "client-target", name: "Beta", companyId: "company-a")
        let duplicateExact = Client(id: "CLIENT-TARGET", name: "Gamma", companyId: "company-a")
        let selfCaseVariant = Client(id: "client-self", name: "Duplicate self", companyId: "company-a")

        let result = ClientDeletionTargetPolicy.candidates(
            from: [duplicateB, duplicateExact, selfCaseVariant, duplicateA, deleting],
            deleting: deleting
        )

        XCTAssertEqual(result.map(\.id), [duplicateA.id])
    }

    func testBulkReassignmentMapsEveryChildToSelectedTarget() {
        let result = DeletionSheetSelectionResolver.resolve(
            mode: .bulk,
            childIds: ["project-a", "project-b"],
            bulkSelectedItem: "client-target",
            bulkDeleteAll: false,
            individualReassignments: [:],
            individualDeletions: []
        )

        XCTAssertEqual(
            result.reassignments,
            ["project-a": "client-target", "project-b": "client-target"]
        )
        XCTAssertTrue(result.deletions.isEmpty)
    }

    func testBulkReassignmentToleratesDuplicateChildIds() {
        let result = DeletionSheetSelectionResolver.resolve(
            mode: .bulk,
            childIds: ["project-a", "project-a"],
            bulkSelectedItem: "client-target",
            bulkDeleteAll: false,
            individualReassignments: [:],
            individualDeletions: []
        )

        XCTAssertEqual(result.reassignments, ["project-a": "client-target"])
    }

    func testBulkDeleteAllMarksEveryChildForDeletion() {
        let result = DeletionSheetSelectionResolver.resolve(
            mode: .bulk,
            childIds: ["project-a", "project-b"],
            bulkSelectedItem: nil,
            bulkDeleteAll: true,
            individualReassignments: [:],
            individualDeletions: []
        )

        XCTAssertTrue(result.reassignments.isEmpty)
        XCTAssertEqual(result.deletions, ["project-a", "project-b"])
    }

    func testIndividualSelectionsPassThroughWithoutBulkState() {
        let result = DeletionSheetSelectionResolver.resolve(
            mode: .individual,
            childIds: ["project-a", "project-b"],
            bulkSelectedItem: "ignored-client",
            bulkDeleteAll: true,
            individualReassignments: ["project-a": "client-target"],
            individualDeletions: ["project-b"]
        )

        XCTAssertEqual(result.reassignments, ["project-a": "client-target"])
        XCTAssertEqual(result.deletions, ["project-b"])
    }

    func testClientDetailMustDisappearBeforeClientIdentityIsInvalidated() async {
        let appState = AppState()
        appState.viewClientDetailsById("client-1")
        let presentationGate = ClientDeletionPresentationGate()
        let dismissalRequested = expectation(description: "dismissal requested")
        let detailDisappeared = expectation(description: "detail disappeared")
        var events: [String] = []

        let operation = Task { @MainActor in
            await ClientDeletionPresentationCoordinator.performInvalidatingMutation(
                dismissPresentations: {
                    events.append("dismiss")
                    appState.requestClientDetailsDismissal()
                    dismissalRequested.fulfill()
                },
                waitForDismissal: {
                    await presentationGate.waitUntilDismissed()
                    events.append("disappeared")
                    detailDisappeared.fulfill()
                    await appState.waitForClientDetailsDismissal()
                    events.append("route-cleared")
                },
                mutation: {
                    events.append("delete")
                }
            )
        }

        await fulfillment(of: [dismissalRequested], timeout: 1)

        XCTAssertEqual(events, ["dismiss"])
        XCTAssertFalse(appState.showClientDetails)
        XCTAssertEqual(appState.selectedClientId, "client-1")

        presentationGate.signalDismissed()
        await fulfillment(of: [detailDisappeared], timeout: 1)

        XCTAssertEqual(events, ["dismiss", "disappeared"])
        XCTAssertEqual(appState.selectedClientId, "client-1")

        // Mirrors MainTabView's sheet onDismiss callback. The model mutation
        // must remain blocked until both the view and its route identity clear.
        appState.dismissClientDetails()
        await operation.value

        XCTAssertEqual(events, ["dismiss", "disappeared", "route-cleared", "delete"])
        XCTAssertFalse(appState.showClientDetails)
        XCTAssertNil(appState.selectedClientId)
    }
}
