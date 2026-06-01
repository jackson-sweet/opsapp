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

        XCTAssertEqual(item?.displayURL, renderedURL)
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

    func test_localQueuedAnnotationOnlyRenderedDeletePlanRemovesRenderedStateWithoutRemoteSoftDelete() {
        let sourceURL = "local://project_images/source-photo.heic"
        let renderedURL = "local://project_images/source-photo.rendered.png"
        let localID = "local-3E7D4E50-5A4A-4AC4-9D98-3D6D94DA8A20"
        let candidate = ProjectPhotoAnnotationDeleteCandidate(
            id: localID,
            companyId: "company-1"
        )
        let item = ProjectPhotoDisplayMapper.items(
            sourceURLs: [],
            renderedURLsBySource: [sourceURL: renderedURL],
            renderedDeliverableURLs: [renderedURL]
        ).first

        let plan = ProjectPhotoAnnotationDeletePlanner.plan(candidates: [candidate])

        XCTAssertEqual(item?.deleteTarget, .annotation(sourceURL: sourceURL, renderedURL: renderedURL))
        XCTAssertEqual(plan.remoteSoftDeleteCandidates, [])
        XCTAssertEqual(plan.localOnlyCandidateIDs, [localID])
        XCTAssertFalse(ProjectPhotoAnnotationDeletePlanner.shouldMarkNeedsSyncAfterLocalDelete(annotationID: localID))

        let state = ProjectPhotoRenderedDeleteState(
            dimensionedURLs: [sourceURL, renderedURL],
            renderedURLsBySource: [sourceURL: renderedURL],
            renderedDeliverableURLs: [renderedURL]
        )
        let updated = ProjectPhotoAnnotationDeletePlanner.removingRenderedState(
            sourceURL: sourceURL,
            renderedURL: renderedURL,
            from: state
        )

        XCTAssertFalse(updated.dimensionedURLs.contains(sourceURL))
        XCTAssertFalse(updated.dimensionedURLs.contains(renderedURL))
        XCTAssertNil(updated.renderedURLsBySource[sourceURL])
        XCTAssertFalse(updated.renderedDeliverableURLs.contains(renderedURL))
    }

    func test_serverBackedAnnotationDeletePlanKeepsRemoteSoftDeleteAndPendingTombstone() {
        let candidate = ProjectPhotoAnnotationDeleteCandidate(
            id: "annotation-server-id",
            companyId: "company-1"
        )

        let plan = ProjectPhotoAnnotationDeletePlanner.plan(candidates: [candidate])

        XCTAssertEqual(plan.remoteSoftDeleteCandidates, [candidate])
        XCTAssertEqual(plan.localOnlyCandidateIDs, [])
        XCTAssertTrue(ProjectPhotoAnnotationDeletePlanner.shouldMarkNeedsSyncAfterLocalDelete(annotationID: candidate.id))
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
