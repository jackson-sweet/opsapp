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
