//
//  SiteVisitOwnCopyRepairTests.swift
//  OPSTests
//
//  A visit photo whose only pointer is a server address the bucket refuses
//  (site-visits/ was never made public-read, 2026-09-15) must still open on the
//  phone that took it: the original capture file is on disk, it just is not
//  referenced any more. The repair seeds the remote-URL cache from that file.
//

import XCTest
@testable import OPS

final class SiteVisitOwnCopyRepairTests: XCTestCase {
    private let visitId = "96090555-b4d0-4a34-9800-3587a80653a5"
    private let companyId = "a612edc0-5c18-4c4d-af97-55b9410dd077"

    private func artifact(id: String, localAssetURL: String?) -> SiteVisitCaptureArtifact {
        SiteVisitCaptureArtifact(
            id: id,
            siteVisitId: visitId,
            companyId: companyId,
            kind: .photo,
            source: .camera,
            localAssetURL: localAssetURL
        )
    }

    func testUploadedPhotoWithItsOriginalStillOnDiskIsSeededUnderTheRemoteURL() {
        let remote = "https://ops-app-files-prod.s3.us-west-2.amazonaws.com/site-visits/c/v/76710377-470a-4922-83a0-7fa3409bf10f/original.jpg"
        let uploaded = artifact(id: "76710377-470a-4922-83a0-7fa3409bf10f", localAssetURL: remote)
        let plan = SiteVisitOwnCopyRepair.plan(
            artifacts: [uploaded],
            hasCache: { _ in false },
            hasLocalFile: { $0 == "local://project_images/capture_76710377-470a-4922-83a0-7fa3409bf10f.jpg" }
        )
        XCTAssertEqual(plan, [
            .init(localID: "local://project_images/capture_76710377-470a-4922-83a0-7fa3409bf10f.jpg", remoteURL: remote)
        ])
    }

    func testNothingToSeedWhenThePointerIsStillLocalOrTheCacheAlreadyExistsOrNoOriginalRemains() {
        let remote = "https://ops-app-files-prod.s3.us-west-2.amazonaws.com/site-visits/c/v/a/original.jpg"
        let stillLocal = artifact(id: "aaaaaaaa-0000-4000-8000-000000000001", localAssetURL: "local://project_images/capture_aaaaaaaa-0000-4000-8000-000000000001.jpg")
        let cached = artifact(id: "aaaaaaaa-0000-4000-8000-000000000002", localAssetURL: remote)
        let noOriginal = artifact(id: "aaaaaaaa-0000-4000-8000-000000000003", localAssetURL: remote)
        let noPointer = artifact(id: "aaaaaaaa-0000-4000-8000-000000000004", localAssetURL: nil)

        XCTAssertTrue(SiteVisitOwnCopyRepair.plan(
            artifacts: [stillLocal, noPointer],
            hasCache: { _ in false },
            hasLocalFile: { _ in true }
        ).isEmpty)
        XCTAssertTrue(SiteVisitOwnCopyRepair.plan(
            artifacts: [cached],
            hasCache: { $0 == remote },
            hasLocalFile: { _ in true }
        ).isEmpty)
        XCTAssertTrue(SiteVisitOwnCopyRepair.plan(
            artifacts: [noOriginal],
            hasCache: { _ in false },
            hasLocalFile: { _ in false }
        ).isEmpty)
    }

    func testOlderCaptureNamingIsRecognisedToo() {
        let remote = "https://ops-app-files-prod.s3.us-west-2.amazonaws.com/site-visits/c/v/d1320778-ecd7-4b11-a8ec-ce803bb1244b/original.jpg"
        let legacy = artifact(id: "D1320778-ECD7-4B11-A8EC-CE803BB1244B", localAssetURL: remote)
        let plan = SiteVisitOwnCopyRepair.plan(
            artifacts: [legacy],
            hasCache: { _ in false },
            hasLocalFile: { $0 == "local://project_images/site_visit_D1320778-ECD7-4B11-A8EC-CE803BB1244B.jpg" }
        )
        XCTAssertEqual(plan.map(\.localID), ["local://project_images/site_visit_D1320778-ECD7-4B11-A8EC-CE803BB1244B.jpg"])
    }
}
