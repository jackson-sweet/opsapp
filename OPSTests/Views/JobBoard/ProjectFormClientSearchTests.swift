//
//  ProjectFormClientSearchTests.swift
//  OPSTests
//
//  Regression coverage for JobBoard project-form client search.
//

import XCTest
@testable import OPS

final class ProjectFormClientSearchTests: XCTestCase {

    func testClientSearchMatchesActiveSubClientName() {
        let parent = Client(id: "client-a", name: "Canpro Decks", companyId: "company-a")
        let subClient = SubClient(id: "sub-a", name: "Maya Stone", title: "Estimator")
        parent.subClients.append(subClient)

        let matches = ProjectFormClientSearch.matchingClients(
            from: [parent],
            query: "maya",
            tutorialMode: false
        )

        XCTAssertEqual(matches.map(\.id), ["client-a"])
    }

    func testClientSearchIgnoresDeletedSubClients() {
        let parent = Client(id: "client-a", name: "Canpro Decks", companyId: "company-a")
        let subClient = SubClient(id: "sub-a", name: "Deleted Contact", title: nil)
        subClient.deletedAt = Date()
        parent.subClients.append(subClient)

        let matches = ProjectFormClientSearch.matchingClients(
            from: [parent],
            query: "deleted",
            tutorialMode: false
        )

        XCTAssertTrue(matches.isEmpty)
    }
}
