//
//  ShareUploadRoutingTests.swift
//  OPSTests
//
//  Queued shares survive logout. Current-account filtering must therefore happen
//  before project grouping, or another account's older row can block or
//  misattribute a new share to the same project on a shared device.
//

import XCTest
@testable import OPS

final class ShareUploadRoutingTests: XCTestCase {

    func testAnotherAccountsJobCannotBlockTheCurrentUsersSameProjectJob() {
        let projectId = "B7EB718E-357D-45F9-A19D-68B2350F6544"
        let accountA = "1D6C2CDA-0B5D-40C4-B1B0-C10A248388A8"
        let accountB = "A6B2258D-DAFF-48E8-A450-65F9277B1D87"
        let jobs = [
            job(
                id: "34F5B3D8-9D8D-4CE1-9467-CBA35133890F",
                projectId: projectId,
                companyId: "3EEC649E-598D-4EA5-A916-80B89B7DA0F4",
                uploadedBy: accountA
            ),
            job(
                id: "BD8EA30C-AD29-4B83-BF7E-56051447F35D",
                projectId: projectId,
                companyId: "3EEC649E-598D-4EA5-A916-80B89B7DA0F4",
                uploadedBy: accountB
            ),
        ]

        let groups = ShareUploadCoordinator.drainGroups(
            jobs,
            currentUserId: accountB
        )

        XCTAssertEqual(groups.flatMap { $0 }.map(\.id), [jobs[1].id])
    }

    func testCompanyContextRemainsPartOfTheDrainGroupIdentity() {
        let account = "1D6C2CDA-0B5D-40C4-B1B0-C10A248388A8"
        let projectId = "B7EB718E-357D-45F9-A19D-68B2350F6544"
        let jobs = [
            job(
                id: "34F5B3D8-9D8D-4CE1-9467-CBA35133890F",
                projectId: projectId,
                companyId: "3EEC649E-598D-4EA5-A916-80B89B7DA0F4",
                uploadedBy: account
            ),
            job(
                id: "BD8EA30C-AD29-4B83-BF7E-56051447F35D",
                projectId: projectId,
                companyId: "E38B9D72-5E0B-4C03-92D4-D702F9CD5E8F",
                uploadedBy: account
            ),
        ]

        let groups = ShareUploadCoordinator.drainGroups(
            jobs,
            currentUserId: account
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.flatMap { $0 }.map(\.id)), Set(jobs.map(\.id)))
    }

    private func job(
        id: String,
        projectId: String,
        companyId: String,
        uploadedBy: String
    ) -> ShareUploadJob {
        ShareUploadJob(
            id: id,
            fileName: "\(id).jpg",
            projectId: projectId,
            projectTitle: "580 Beach Dr",
            companyId: companyId,
            uploadedBy: uploadedBy,
            createdAt: Date(timeIntervalSince1970: 1_785_700_574)
        )
    }
}
