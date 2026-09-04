//
//  ActivityEntryEditAttachmentsTests.swift
//  OPSTests
//
//  Bug f5f57917 — "When editing a comment, user is not able to remove the
//  attached photo."
//
//  Edit mode used to render no photo at all and offered no remove affordance,
//  so the only way to drop a note's photo was Delete, which destroys the whole
//  note. These pin the two rules that decide what an inline edit may detach.
//  They assert the presentation contract directly rather than by driving
//  SwiftUI `@State`, which a unit test cannot reach.
//

import XCTest
@testable import OPS

final class ActivityEntryEditAttachmentsTests: XCTestCase {

    private let sketch = "https://example.com/sketch.jpg"
    private let rail = "https://example.com/rail.jpg"

    // MARK: - What an edit may detach

    /// A note whose `photoURL` is set was posted from the photo viewer's
    /// comment composer: the photo is the comment's SUBJECT, not an
    /// attachment. Detaching it would orphan the sentence, so those notes must
    /// expose nothing removable and keep Delete as their route.
    func testPhotoCommentEditOffersNoAttachmentRemoval() {
        XCTAssertTrue(
            ActivityEditAttachmentPresentation.removableAttachments(
                photoURL: sketch,
                attachments: [rail]
            ).isEmpty
        )
    }

    func testNoteWithAttachmentsOffersEveryAttachmentForRemoval() {
        XCTAssertEqual(
            ActivityEditAttachmentPresentation.removableAttachments(
                photoURL: nil,
                attachments: [sketch, rail]
            ),
            [sketch, rail]
        )
    }

    /// An empty `photo_url` is not a photo comment — the column is nullable and
    /// legacy rows carry blanks. Those notes must still offer their photos.
    func testBlankPhotoURLIsNotTreatedAsAPhotoComment() {
        XCTAssertEqual(
            ActivityEditAttachmentPresentation.removableAttachments(
                photoURL: "   ",
                attachments: [sketch]
            ),
            [sketch]
        )
    }

    /// A blank entry is corrupt data, not a photo. The read-only strip already
    /// skips those, so the edit strip must agree or the two modes of the same
    /// card would disagree about what it holds.
    func testBlankAttachmentEntriesAreNotOfferedForRemoval() {
        XCTAssertEqual(
            ActivityEditAttachmentPresentation.removableAttachments(
                photoURL: nil,
                attachments: ["", sketch, ""]
            ),
            [sketch]
        )
    }

    // MARK: - An edit may never become a delete

    func testRemovingTheLastPhotoFromAnEmptyNoteStrandsIt() {
        XCTAssertTrue(
            ActivityEditAttachmentPresentation.wouldStrandNote(
                content: "   ",
                photoURL: nil,
                attachments: []
            )
        )
    }

    func testKeepingWordsIsEnough() {
        XCTAssertFalse(
            ActivityEditAttachmentPresentation.wouldStrandNote(
                content: "Rail run measured at 38 ft.",
                photoURL: nil,
                attachments: []
            )
        )
    }

    func testKeepingOnePhotoIsEnough() {
        XCTAssertFalse(
            ActivityEditAttachmentPresentation.wouldStrandNote(
                content: "",
                photoURL: nil,
                attachments: [sketch]
            )
        )
    }

    /// A photo comment's subject photo cannot be detached, so it always keeps
    /// the note alive — clearing the text of one is not a stranding.
    func testPhotoCommentIsNeverStrandedByClearingItsText() {
        XCTAssertFalse(
            ActivityEditAttachmentPresentation.wouldStrandNote(
                content: "",
                photoURL: sketch,
                attachments: []
            )
        )
    }

    func testBlankAttachmentEntriesDoNotKeepAnEmptyNoteAlive() {
        XCTAssertTrue(
            ActivityEditAttachmentPresentation.wouldStrandNote(
                content: "",
                photoURL: nil,
                attachments: ["", "  "]
            )
        )
    }
}
