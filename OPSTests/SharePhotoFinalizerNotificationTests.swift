//
//  SharePhotoFinalizerNotificationTests.swift
//  OPSTests
//
//  The share-extension completion rail row must cross the narrow server RPC
//  (`notify_share_photos_finalized`), never a direct `notifications` insert —
//  the 2026-07-15 notification-creation hardening revoked app-role INSERT, so
//  the legacy client-side insert 42501'd and the "your photos landed"
//  confirmation went silently dead for every share.
//
//  What these tests pin:
//    1. The project id and the photo count reach the syncer verbatim — one call
//       per finalized batch, no client-side clamping and no singular/plural
//       branch. Copy, recipient, and project title are SERVER-rendered now; a
//       client that reintroduced any of them would be shipping a second source
//       of truth for the rail's wording.
//    2. A missing uploader identity skips the call entirely. Empty
//       `uploadedBy` / `companyId` means the share ran with no authenticated
//       context to attribute the row to — firing the RPC anyway would post the
//       confirmation to whoever happens to hold the session.
//    3. Transport failure stays swallowed. The notification is best-effort and
//       runs after the durable writes have already landed; a throwing RPC must
//       not surface, hang, or otherwise disturb the finalize path.
//

import XCTest
@testable import OPS

@MainActor
final class SharePhotoFinalizerNotificationTests: XCTestCase {

    // MARK: - Spy

    /// Records every (projectId, photoCount) pair handed to the RPC binding.
    /// Optionally throws to prove the caller's best-effort contract. Calls are
    /// sequential and awaited, so plain storage is race-free.
    private final class SharePhotoFinalizeNotifySpy: SharePhotoFinalizeNotifying {
        struct Call: Equatable {
            let projectId: String
            let photoCount: Int
        }

        private(set) var calls: [Call] = []
        var shouldFail = false

        func notifySharePhotosFinalized(projectId: String, photoCount: Int) async throws -> String {
            calls.append(Call(projectId: projectId, photoCount: photoCount))
            if shouldFail {
                throw URLError(.notConnectedToInternet)
            }
            return "created"
        }
    }

    private let projectId = "3f8b1c22-5d41-4a90-9d0e-6b1a77c04e11"
    private let uploadedBy = "11111111-1111-1111-1111-111111111111"
    private let companyId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    // MARK: - Forwarding

    func test_postCompletionNotification_forwardsProjectIdAndCountVerbatim() async {
        let spy = SharePhotoFinalizeNotifySpy()

        await SharePhotoFinalizer.postCompletionNotification(
            count: 7,
            projectId: projectId,
            uploadedBy: uploadedBy,
            companyId: companyId,
            syncer: spy
        )

        XCTAssertEqual(
            spy.calls,
            [.init(projectId: projectId, photoCount: 7)],
            "One finalized batch must produce exactly one RPC call carrying the id and count untouched"
        )
    }

    /// A single photo is the case the retired client copy special-cased
    /// ("1 photo on <title>"). The count must still travel raw — the server
    /// owns the singular/plural rendering.
    func test_postCompletionNotification_forwardsSinglePhotoCountUnbranched() async {
        let spy = SharePhotoFinalizeNotifySpy()

        await SharePhotoFinalizer.postCompletionNotification(
            count: 1,
            projectId: projectId,
            uploadedBy: uploadedBy,
            companyId: companyId,
            syncer: spy
        )

        XCTAssertEqual(spy.calls, [.init(projectId: projectId, photoCount: 1)])
    }

    // MARK: - Identity guard

    func test_postCompletionNotification_skipsWhenUploaderMissing() async {
        let spy = SharePhotoFinalizeNotifySpy()

        await SharePhotoFinalizer.postCompletionNotification(
            count: 3,
            projectId: projectId,
            uploadedBy: "",
            companyId: companyId,
            syncer: spy
        )

        XCTAssertTrue(spy.calls.isEmpty, "No uploader identity — the RPC must not fire")
    }

    func test_postCompletionNotification_skipsWhenCompanyMissing() async {
        let spy = SharePhotoFinalizeNotifySpy()

        await SharePhotoFinalizer.postCompletionNotification(
            count: 3,
            projectId: projectId,
            uploadedBy: uploadedBy,
            companyId: "",
            syncer: spy
        )

        XCTAssertTrue(spy.calls.isEmpty, "No company context — the RPC must not fire")
    }

    func test_postCompletionNotification_skipsWhenIdentityFullyMissing() async {
        let spy = SharePhotoFinalizeNotifySpy()

        await SharePhotoFinalizer.postCompletionNotification(
            count: 3,
            projectId: projectId,
            uploadedBy: "",
            companyId: "",
            syncer: spy
        )

        XCTAssertTrue(spy.calls.isEmpty)
    }

    // MARK: - Best effort

    /// The durable writes (project_images + project_photos) have already
    /// committed by the time this runs, so a failed rail row must never turn a
    /// landed share into a failed one. The signature is non-throwing, so the
    /// compiler covers propagation; what this pins is that the call is actually
    /// attempted and the failure is caught rather than trapped or hung on.
    func test_postCompletionNotification_swallowsTransportFailure() async {
        let spy = SharePhotoFinalizeNotifySpy()
        spy.shouldFail = true

        await SharePhotoFinalizer.postCompletionNotification(
            count: 2,
            projectId: projectId,
            uploadedBy: uploadedBy,
            companyId: companyId,
            syncer: spy
        )

        XCTAssertEqual(
            spy.calls,
            [.init(projectId: projectId, photoCount: 2)],
            "The failure must come from an attempted call, not a skipped one"
        )
    }
}
