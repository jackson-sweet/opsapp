//
//  ProjectPhotoDisplayMapperTests.swift
//  OPSTests
//

import XCTest
@testable import OPS

final class ProjectPhotoDisplayMapperTests: XCTestCase {

    func test_itemsDisplayRenderedDeliverableWhilePreservingSourceURL() {
        let sourceURL = "https://example.test/project-photo.heic"
        let renderedURL = "https://example.test/project-photo.rendered.png"

        let items = ProjectPhotoDisplayMapper.items(
            sourceURLs: [sourceURL],
            renderedURLsBySource: [sourceURL: renderedURL],
            renderedDeliverableURLs: [renderedURL]
        )

        XCTAssertEqual(items, [
            ProjectPhotoDisplayItem(displayURL: renderedURL, sourceURL: sourceURL)
        ])
    }

    func test_sourceURLForRenderedDisplayURLResolvesDeleteTargetToSourcePhoto() {
        let sourceURL = "https://example.test/project-photo.heic"
        let renderedURL = "https://example.test/project-photo.rendered.png"

        let resolved = ProjectPhotoDisplayMapper.sourceURL(
            forDisplayURL: renderedURL,
            sourceURLs: [sourceURL],
            renderedURLsBySource: [sourceURL: renderedURL],
            renderedDeliverableURLs: [renderedURL]
        )

        XCTAssertEqual(resolved, sourceURL)
    }

    func test_sourcePresentRenderedDeliverableUsesProjectImageDeleteTarget() {
        let sourceURL = "https://example.test/project-photo.heic"
        let renderedURL = "https://example.test/project-photo.rendered.png"

        let item = ProjectPhotoDisplayMapper.items(
            sourceURLs: [sourceURL],
            renderedURLsBySource: [sourceURL: renderedURL],
            renderedDeliverableURLs: [renderedURL]
        ).first

        XCTAssertEqual(item?.deleteTarget, .projectImage(sourceURL: sourceURL))
    }

    func test_annotationOnlyRenderedDeliverableUsesAnnotationDeleteTarget() {
        let sourceURL = "https://example.test/missing-source.heic"
        let renderedURL = "https://example.test/missing-source.rendered.png"

        let item = ProjectPhotoDisplayMapper.items(
            sourceURLs: [],
            renderedURLsBySource: [sourceURL: renderedURL],
            renderedDeliverableURLs: [renderedURL]
        ).first

        XCTAssertEqual(item?.sourceURL, sourceURL)
        XCTAssertEqual(item?.syncStatusURL, sourceURL)
        XCTAssertEqual(
            item?.deleteTarget,
            .annotation(sourceURL: sourceURL, renderedURL: renderedURL)
        )
    }

    func test_annotationOnlyDeleteTargetMatchesBackingAnnotation() {
        let sourceURL = "https://example.test/missing-source.heic"
        let renderedURL = "https://example.test/missing-source.rendered.png"
        let annotation = PhotoAnnotation(
            id: "annotation-1",
            projectId: "project-1",
            companyId: "company-1",
            photoURL: sourceURL,
            authorId: "user-1"
        )
        annotation.renderedPhotoURL = renderedURL

        XCTAssertTrue(
            ProjectPhotosGrid.annotationMatchesDeleteTarget(
                annotation,
                sourceURL: sourceURL,
                renderedURL: renderedURL
            )
        )
    }

    func test_syncStatusURLForRenderedDisplayURLUsesSourcePhotoURL() {
        let sourceURL = "local://project_images/source-photo.heic"
        let renderedURL = "https://example.test/source-photo.rendered.png"

        let items = ProjectPhotoDisplayMapper.items(
            sourceURLs: [sourceURL],
            renderedURLsBySource: [sourceURL: renderedURL],
            renderedDeliverableURLs: [renderedURL]
        )

        XCTAssertEqual(items.first?.syncStatusURL, sourceURL)
        XCTAssertNotEqual(items.first?.syncStatusURL, renderedURL)
    }
}
