//
//  ProjectPhotoDeleteAuthorizationTests.swift
//  OPSTests
//
//  Locks the client-side photo-delete gate to the rule the database enforces in
//  `trg_project_photos_00_write_guard`:
//
//      IF lower(OLD.uploaded_by) <> lower(v_uid::text)
//         AND NOT private.current_user_has_permission('projects.edit', 'all')
//      THEN RAISE 'soft-delete allowed on own photos only'
//
//  A UI that offers a delete the server will reject is the defect — Jackson's
//  2026-07-29 call: field crews delete their own photos, admins delete any.
//
//  Note what the server does NOT ask for. No `project_photos` UPDATE policy
//  requires a `projects.edit` grant (verified against production 2026-08-18:
//  the only UPDATE-applicable policy is `company_isolation`; DELETE is denied
//  outright and INSERT carries its own restrictive policy). Owning the photo is
//  therefore sufficient on its own, and hiding that delete is as much a defect
//  as offering one the trigger rejects.
//

import XCTest
@testable import OPS

final class ProjectPhotoDeleteAuthorizationTests: XCTestCase {

    private let mine = "6C2E5A2E-9B1F-4C0E-9D3A-0F1A2B3C4D5E"
    private let theirs = "11111111-2222-3333-4444-555555555555"

    // MARK: - Crew (no `all` grant)

    func testCrewMayDeleteTheirOwnPhoto() {
        XCTAssertTrue(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: mine,
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: true
            )
        )
    }

    func testCrewMayNotDeleteATeammatesPhoto() {
        XCTAssertFalse(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: theirs,
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: true
            ),
            "an assigned-scope projects.edit grant must not offer a delete the trigger rejects"
        )
    }

    /// `uploaded_by` is TEXT and the UUID casing in production is inconsistent.
    /// The trigger compares with `lower()`; so must the client.
    func testOwnershipIgnoresUUIDCasingAndWhitespace() {
        XCTAssertTrue(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: mine.lowercased(),
                rawCurrentUser: mine.uppercased(),
                hasFullProjectEdit: false,
                hasAnyProjectEdit: true
            )
        )
        XCTAssertTrue(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: "  \(mine.lowercased())  ",
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: true
            )
        )
    }

    /// The trigger bails when the requesting user cannot be resolved.
    func testNoSignedInOperatorMayNotDelete() {
        XCTAssertFalse(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: mine,
                rawCurrentUser: nil,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: true
            )
        )
    }

    /// An unparseable identity is not an identity — it must never match.
    func testNonUUIDIdentitiesNeverMatch() {
        XCTAssertFalse(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: "firebase-uid-not-a-uuid",
                rawCurrentUser: "firebase-uid-not-a-uuid",
                hasFullProjectEdit: false,
                hasAnyProjectEdit: true
            )
        )
    }

    /// The shape production actually holds. 37 `project_photos` rows carry the
    /// literal `'system'` in `uploaded_by` — server-written, `source = 'other'`,
    /// 10 of them still live in the carousel. `lower('system')` equals no
    /// operator's id, so the trigger rejects the soft-delete for everyone below
    /// scope `all`, however wide the crew member's grant is otherwise.
    func testServerWrittenSystemUploaderIsNotDeletableByCrew() {
        XCTAssertFalse(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: "system",
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: true
            ),
            "an uploader that cannot resolve to a user id is unmatchable, not unattributed"
        )
        // The admin half of the guard still clears it.
        XCTAssertTrue(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: "system",
                rawCurrentUser: mine,
                hasFullProjectEdit: true,
                hasAnyProjectEdit: true
            )
        )
    }

    /// Without the company-wide grant nothing beyond your OWN photo is
    /// deletable — not a teammate's, not the server's `'system'` rows, not one
    /// this device cannot attribute.
    ///
    /// Your own photo is the exception, and it is deletable with no
    /// `projects.edit` grant whatsoever: the trigger asks only for a resolvable
    /// user and `lower(OLD.uploaded_by) = lower(v_uid::text)`, and no UPDATE
    /// policy adds a permission requirement. Withholding that badge would leave
    /// a crew member unable to remove a photo the server would happily delete.
    func testNoFullGrantDeletesNothingBeyondYourOwnPhoto() {
        XCTAssertFalse(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: theirs,
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: false
            ),
            "without projects.edit at scope `all`, a teammate's photo is untouchable"
        )
        XCTAssertFalse(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: "system",
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: false
            ),
            "an unmatchable uploader needs the `all` grant, which this operator lacks"
        )
        XCTAssertFalse(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: nil,
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: false
            ),
            "the unattributed fallback rides on the grant, so no grant offers nothing"
        )
        XCTAssertTrue(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: mine,
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: false
            ),
            "ownership alone satisfies the trigger — never hide a delete the server accepts"
        )
    }

    // MARK: - Admin (`projects.edit` at scope `all`)

    func testFullProjectEditDeletesAnyPhoto() {
        XCTAssertTrue(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: theirs,
                rawCurrentUser: mine,
                hasFullProjectEdit: true,
                hasAnyProjectEdit: true
            )
        )
        // Even a photo with no local attribution at all.
        XCTAssertTrue(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: nil,
                rawCurrentUser: nil,
                hasFullProjectEdit: true,
                hasAnyProjectEdit: false
            )
        )
    }

    // MARK: - Not-yet-synced attribution

    /// A photo just taken has its `project_photos` row inserted remotely but not
    /// pulled back, so this device knows no uploader. The server will accept the
    /// delete — the operator IS the uploader — so the affordance stays.
    func testUnattributedPhotoFallsBackToTheProjectEditGrant() {
        XCTAssertTrue(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: nil,
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: true
            )
        )
    }
}
