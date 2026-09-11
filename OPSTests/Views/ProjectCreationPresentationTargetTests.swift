import Combine
import XCTest
@testable import OPS

@MainActor
final class ProjectCreationPresentationTargetTests: XCTestCase {
    func testMissingTargetUsesRootFallbackOnce() {
        var fallbackCount = 0

        ProjectCreationPresentationTarget.deliver(.project(makeProject()), to: nil) {
            fallbackCount += 1
        }

        XCTAssertEqual(fallbackCount, 1)
    }

    func testTargetDoesNotRetainDismissedParentEndpoint() throws {
        var endpoint: ProjectCreationPresentationEndpoint? = ProjectCreationPresentationEndpoint()
        endpoint?.appeared()
        weak var weakEndpoint = endpoint
        let target = ProjectCreationPresentationTarget(endpoint: try XCTUnwrap(endpoint))
        endpoint = nil
        XCTAssertNil(weakEndpoint)
        var fallbackCount = 0

        ProjectCreationPresentationTarget.deliver(.project(makeProject()), to: target) {
            fallbackCount += 1
        }

        XCTAssertEqual(fallbackCount, 1)
    }

    func testUnpresentedEndpointFallsBackWithoutArmingItsSheet() {
        let endpoint = ProjectCreationPresentationEndpoint()
        let target = ProjectCreationPresentationTarget(endpoint: endpoint)
        var fallbackCount = 0

        ProjectCreationPresentationTarget.deliver(.denied("Project unavailable"), to: target) {
            fallbackCount += 1
        }

        XCTAssertEqual(fallbackCount, 1)
        XCTAssertNil(endpoint.destination)
    }

    func testAvailableEndpointReceivesExactProjectWithoutRootFallback() {
        let endpoint = ProjectCreationPresentationEndpoint()
        endpoint.appeared()
        let target = ProjectCreationPresentationTarget(endpoint: endpoint)
        let project = makeProject()
        var fallbackCount = 0

        ProjectCreationPresentationTarget.deliver(.project(project), to: target) {
            fallbackCount += 1
        }

        guard case .project(let delivered)? = endpoint.destination else {
            return XCTFail("The available parent must receive the project destination")
        }
        XCTAssertTrue(delivered === project)
        XCTAssertEqual(fallbackCount, 0)
    }

    func testAvailableEndpointReceivesAccessDenialWithoutOpeningAProject() {
        let endpoint = ProjectCreationPresentationEndpoint()
        endpoint.appeared()
        let target = ProjectCreationPresentationTarget(endpoint: endpoint)
        var fallbackCount = 0

        ProjectCreationPresentationTarget.deliver(.denied("This project is outside your access."), to: target) {
            fallbackCount += 1
        }

        guard case .denied(let message)? = endpoint.destination else {
            return XCTFail("Access denial must stay a denial at the parent presentation boundary")
        }
        XCTAssertEqual(message, "This project is outside your access.")
        XCTAssertEqual(fallbackCount, 0)
    }

    func testCompletedParentDismissalRetiresTargetEvenWhileEndpointIsRetained() {
        let endpoint = ProjectCreationPresentationEndpoint()
        endpoint.appeared()
        let target = ProjectCreationPresentationTarget(endpoint: endpoint)
        let original = makeProject()
        ProjectCreationPresentationTarget.deliver(.project(original), to: target) {
            XCTFail("The initially presented parent must be available")
        }
        endpoint.dismissed()
        var fallbackCount = 0

        ProjectCreationPresentationTarget.deliver(.denied("New route denied"), to: target) {
            fallbackCount += 1
        }

        XCTAssertEqual(fallbackCount, 1)
        guard case .project(let retained)? = endpoint.destination else {
            return XCTFail("A retired parent must not receive a later destination")
        }
        XCTAssertTrue(retained === original)
    }

    func testRepeatedProjectIdentityDoesNotPublishAnotherPresentation() {
        let endpoint = ProjectCreationPresentationEndpoint()
        endpoint.appeared()
        let target = ProjectCreationPresentationTarget(endpoint: endpoint)
        let original = makeProject(id: "project-a", title: "North deck")
        let refreshed = makeProject(id: "project-a", title: "Updated North deck")
        var presentationCount = 0
        let observation = endpoint.$destination.dropFirst().sink { _ in presentationCount += 1 }
        defer { observation.cancel() }

        ProjectCreationPresentationTarget.deliver(.project(original), to: target) {
            XCTFail("The available parent must own the first presentation")
        }
        ProjectCreationPresentationTarget.deliver(.project(refreshed), to: target) {
            XCTFail("Duplicate delivery must not fall through to a competing root sheet")
        }

        XCTAssertEqual(presentationCount, 1)
        guard case .project(let delivered)? = endpoint.destination else {
            return XCTFail("The existing project presentation must remain selected")
        }
        XCTAssertTrue(delivered === original)
    }

    func testDifferentProjectsWithIdenticalTitlesRemainDistinctDestinations() {
        let endpoint = ProjectCreationPresentationEndpoint()
        endpoint.appeared()
        let target = ProjectCreationPresentationTarget(endpoint: endpoint)
        let original = makeProject(id: "project-a", title: "Deck")
        let next = makeProject(id: "project-b", title: "Deck")

        ProjectCreationPresentationTarget.deliver(.project(original), to: target) {
            XCTFail("The available parent must own the first destination")
        }
        ProjectCreationPresentationTarget.deliver(.project(next), to: target) {
            XCTFail("A different project must still route through its available parent")
        }

        guard case .project(let delivered)? = endpoint.destination else {
            return XCTFail("The second project must become the selected destination")
        }
        XCTAssertTrue(delivered === next)
    }

    func testClosingChildDestinationAllowsSameProjectToOpenAgain() {
        let endpoint = ProjectCreationPresentationEndpoint()
        endpoint.appeared()
        let target = ProjectCreationPresentationTarget(endpoint: endpoint)
        let project = makeProject()
        ProjectCreationPresentationTarget.deliver(.project(project), to: target) {
            XCTFail("The available parent must own the first destination")
        }
        // SwiftUI clears the item binding when only the destination sheet closes.
        endpoint.destination = nil

        ProjectCreationPresentationTarget.deliver(.project(project), to: target) {
            XCTFail("Closing a child must not retire its still-presented parent")
        }

        guard case .project(let reopened)? = endpoint.destination else {
            return XCTFail("The same project must be openable again after closing its sheet")
        }
        XCTAssertTrue(reopened === project)
    }

    private func makeProject(id: String = "project-a", title: String = "North deck") -> Project {
        Project(id: id, title: title, status: .rfq)
    }
}
