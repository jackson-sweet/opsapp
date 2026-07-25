//
//  LeadImageStoragePathTests.swift
//  OPSTests
//
//  Lead photos must use the publicly readable project-media namespace even
//  before conversion. The opportunity id remains in the key so deletion can
//  continue to authorize against the canonical lead edit boundary.
//

import XCTest
@testable import OPS

final class LeadImageStoragePathTests: XCTestCase {

    func test_folder_usesPublicProjectMediaLeadNamespace() {
        XCTAssertEqual(
            LeadImageStoragePath.folder(
                companyId: "11111111-1111-4111-8111-111111111111",
                opportunityId: "22222222-2222-4222-8222-222222222222"
            ),
            "projects/11111111-1111-4111-8111-111111111111/leads/22222222-2222-4222-8222-222222222222"
        )
    }
}
