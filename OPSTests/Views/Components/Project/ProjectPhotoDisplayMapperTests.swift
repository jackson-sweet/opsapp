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

    func test_sourcePresentRenderedDeliverablePreservesSourceURLForDeletion() {
        let sourceURL = "https://example.test/project-photo.heic"
        let renderedURL = "https://example.test/project-photo.rendered.png"

        let item = ProjectPhotoDisplayMapper.items(
            sourceURLs: [sourceURL],
            renderedURLsBySource: [sourceURL: renderedURL],
            renderedDeliverableURLs: [renderedURL]
        ).first

        // The `deleteTarget` enum (`.projectImage(sourceURL:)`) the original
        // assertion referenced no longer exists on `ProjectPhotoDisplayItem`.
        // The item now exposes only `displayURL` / `sourceURL`, and
        // `ProjectPhotosGrid` routes deletion by passing `item.sourceURL`
        // straight into `deletePhoto(_:)` (which removes it from
        // `project.getProjectImages()`). For a source-backed rendered
        // deliverable that means the rendered PNG is what we display while the
        // underlying source photo URL is what a delete operates on — assert
        // exactly that contract.
        XCTAssertEqual(item?.displayURL, renderedURL)
        XCTAssertEqual(item?.sourceURL, sourceURL)
    }

    func test_annotationOnlyRenderedDeliverableResolvesToAnnotationSourceURL() {
        let sourceURL = "https://example.test/missing-source.heic"
        let renderedURL = "https://example.test/missing-source.rendered.png"

        let item = ProjectPhotoDisplayMapper.items(
            sourceURLs: [],
            renderedURLsBySource: [sourceURL: renderedURL],
            renderedDeliverableURLs: [renderedURL]
        ).first

        // For a rendered deliverable with no backing source photo in the
        // project's image list, the mapper still resolves the item's
        // `sourceURL` (and therefore its `syncStatusURL`) back to the
        // annotation's source-photo URL via the rendered→source reverse map.
        XCTAssertEqual(item?.sourceURL, sourceURL)
        XCTAssertEqual(item?.syncStatusURL, sourceURL)
        // The `deleteTarget` enum (`.annotation(sourceURL:renderedURL:)`) the
        // original assertion referenced no longer exists on
        // `ProjectPhotoDisplayItem` — the type now exposes only `displayURL` /
        // `sourceURL` / `syncStatusURL`, with no delete-routing value object.
    }

    // Removed: test_annotationOnlyDeleteTargetMatchesBackingAnnotation.
    // Its sole assertion exercised `ProjectPhotosGrid.annotationMatchesDeleteTarget(_:sourceURL:renderedURL:)`,
    // a static helper that no longer exists on `ProjectPhotosGrid` and has no
    // current-API equivalent. The production grid does not model an
    // "annotation" delete target: `deletePhoto(_:)` removes the URL from
    // `project.getProjectImages()` only, so there is nothing to assert about
    // matching a `PhotoAnnotation` to a delete target. Dropped rather than
    // rewritten because no surviving public API expresses this behavior.

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
