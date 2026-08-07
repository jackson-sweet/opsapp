//
//  LeadAttachmentPresentationTests.swift
//  OPSTests
//
//  Regression coverage for the compact Lead Details attachment row and for
//  deciding which email attachments also belong in the Lead Photos viewer.
//

import XCTest
@testable import OPS

final class LeadAttachmentPresentationTests: XCTestCase {
    func test_rasterImagesAreRecognizedFromMimeOrFilename() {
        XCTAssertEqual(
            LeadAttachmentPresentation.kind(
                mimeType: "image/jpeg",
                filename: "site-photo.bin"
            ),
            .image
        )
        XCTAssertEqual(
            LeadAttachmentPresentation.kind(
                mimeType: nil,
                filename: "measurement.HEIC"
            ),
            .image
        )
    }

    func test_pdfAndGenericFilesStayOutOfLeadPhotos() {
        XCTAssertEqual(
            LeadAttachmentPresentation.kind(
                mimeType: "application/pdf",
                filename: "drawing.pdf"
            ),
            .pdf
        )
        XCTAssertEqual(
            LeadAttachmentPresentation.kind(
                mimeType: "image/svg+xml",
                filename: "logo.svg"
            ),
            .file
        )
        XCTAssertEqual(
            LeadAttachmentPresentation.kind(
                mimeType: "application/zip",
                filename: "archive.zip"
            ),
            .file
        )
    }

    func test_summaryUsesNaturalSingularAndPluralCopy() {
        XCTAssertEqual(LeadAttachmentPresentation.summary(count: 1), "1 attachment")
        XCTAssertEqual(LeadAttachmentPresentation.summary(count: 12), "12 attachments")
    }

    func test_onlyStoredRasterImagesJoinLeadPhotos() {
        XCTAssertTrue(
            LeadAttachmentPresentation.isLeadPhoto(
                ingestStatus: "stored",
                mimeType: "image/jpeg",
                filename: "site.jpg"
            )
        )
        XCTAssertFalse(
            LeadAttachmentPresentation.isLeadPhoto(
                ingestStatus: "external",
                mimeType: "image/jpeg",
                filename: "linked.jpg"
            )
        )
        XCTAssertFalse(
            LeadAttachmentPresentation.isLeadPhoto(
                ingestStatus: "stored",
                mimeType: "application/pdf",
                filename: "plan.pdf"
            )
        )
    }

    func test_safeFilenameDiscardsPathsAndRestoresUsefulExtensions() {
        XCTAssertEqual(
            LeadAttachmentPresentation.safeFilename(
                filename: "../../private/roof plan.pdf",
                mimeType: "application/pdf"
            ),
            "roof plan.pdf"
        )
        XCTAssertEqual(
            LeadAttachmentPresentation.safeFilename(
                filename: "..\\..\\site.jpg",
                mimeType: "image/jpeg"
            ),
            "site.jpg"
        )
        XCTAssertEqual(
            LeadAttachmentPresentation.safeFilename(
                filename: nil,
                mimeType: "image/jpeg"
            ),
            "attachment.jpg"
        )
        XCTAssertEqual(
            LeadAttachmentPresentation.safeFilename(
                filename: "..",
                mimeType: nil
            ),
            "attachment"
        )
    }
}
