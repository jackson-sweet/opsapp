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

    /// No project-edit grant at all: nothing is deletable, attributed or not.
    func testNoProjectEditGrantDeletesNothing() {
        XCTAssertFalse(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: mine,
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: false
            ),
            "own-photo ownership still rides on holding some projects.edit grant"
        )
        XCTAssertFalse(
            ProjectPhotoDeleteAuthorization.allows(
                rawUploader: nil,
                rawCurrentUser: mine,
                hasFullProjectEdit: false,
                hasAnyProjectEdit: false
            )
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
