import XCTest
@testable import OPS

@MainActor
final class ProjectPrimaryContactTests: XCTestCase {
    private func fixture() -> (Project, Client, SubClient) {
        let client = Client(
            id: "client-1",
            name: "Northline Builders",
            email: "office@northline.example",
            phoneNumber: "2505550100",
            companyId: "company-1"
        )
        let contact = SubClient(
            id: "contact-1",
            name: "Maya Stone",
            title: "Project manager",
            email: "maya@northline.example",
            phoneNumber: "2505550101"
        )
        contact.client = client
        client.subClients = [contact]

        let project = Project(id: "project-1", title: "Cedar deck", status: .accepted)
        project.companyId = "company-1"
        project.clientId = client.id
        project.client = client
        return (project, client, contact)
    }

    func testExplicitActiveSubClientWinsProjectContactChannels() {
        let (project, _, contact) = fixture()
        project.primarySubClientId = contact.id

        XCTAssertEqual(project.primaryProjectContact?.id, contact.id)
        XCTAssertEqual(project.effectiveProjectContactName, "Maya Stone")
        XCTAssertEqual(project.effectiveClientEmail, "maya@northline.example")
        XCTAssertEqual(project.effectiveClientPhone, "2505550101")
        XCTAssertEqual(project.effectiveClientName, "Northline Builders")
    }

    func testNoSelectionUsesParentOnlyAndNeverAnArbitrarySubClient() {
        let (project, client, _) = fixture()
        client.email = nil
        client.phoneNumber = nil

        XCTAssertNil(project.primaryProjectContact)
        XCTAssertEqual(project.effectiveProjectContactName, "Northline Builders")
        XCTAssertNil(project.effectiveClientEmail)
        XCTAssertNil(project.effectiveClientPhone)
    }

    func testDeletedSelectionFallsBackToParentClient() {
        let (project, client, contact) = fixture()
        project.primarySubClientId = contact.id
        contact.deletedAt = Date()

        XCTAssertNil(project.primaryProjectContact)
        XCTAssertEqual(project.effectiveProjectContactName, client.name)
        XCTAssertEqual(project.effectiveClientEmail, client.email)
        XCTAssertEqual(project.effectiveClientPhone, client.phoneNumber)
    }

    func testRecordScopedProjectEditAllowsAllOrAssignedTeamOnly() {
        let (project, _, _) = fixture()
        let store = PermissionStore.shared
        store.permissions = ["projects.edit": "assigned"]

        project.setTeamMemberIds(["operator-1"])
        XCTAssertTrue(store.canEditProject(project, userId: "OPERATOR-1"))
        XCTAssertFalse(store.canEditProject(project, userId: "operator-2"))

        store.permissions = ["projects.edit": "all"]
        XCTAssertTrue(store.canEditProject(project, userId: "operator-2"))
        store.permissions = [:]
    }
}

