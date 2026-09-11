import XCTest
@testable import OPS

@MainActor
final class ProjectCreatedToastPINReplayTests: XCTestCase {
    func testConsumedToastRetainsExactProjectAndTargetForUnlockReplayThenClears() throws {
        let notifications = NotificationCenter()
        let coordinator = DeepLinkCoordinator(notificationCenter: notifications)
        let endpoint = ProjectCreationPresentationEndpoint()
        endpoint.appeared()
        let target = ProjectCreationPresentationTarget(endpoint: endpoint)
        var received: [Notification] = []
        let observer = notifications.addObserver(forName: .openProjectDetails, object: nil, queue: nil) {
            received.append($0)
        }
        defer {
            notifications.removeObserver(observer)
            coordinator.clear()
            ToastCenter.shared.reset()
        }
        let completion = ProjectCreationCompletion { notification in
            ToastCenter.shared.present(ProjectCreationCompletion.toast(for: notification, coordinator: coordinator))
        }
        ToastCenter.shared.reset()
        completion.projectCreated(id: "offline-project-a", title: "North deck", presentationTarget: target)
        completion.presentationDidDismiss()
        let toast = try XCTUnwrap(ToastCenter.shared.current)
        ToastCenter.shared.handleTap(toastID: toast.id, target: .message)

        // A PIN-blocked handler returns without presenting or clearing. The
        // consumed toast must already have registered replayable intent.
        XCTAssertNil(ToastCenter.shared.current)
        XCTAssertNil(endpoint.destination)
        let pending = try XCTUnwrap(coordinator.pendingLink)
        XCTAssertEqual(pending.id, "offline-project-a")
        XCTAssertEqual(pending.entity, "projects")
        XCTAssertTrue(pending.projectCreationPresentationTarget === target)
        XCTAssertEqual(received.count, 1)

        coordinator.drain(context: "pin_unlocked")
        XCTAssertEqual(received.count, 2)
        for notification in received {
            XCTAssertEqual(notification.userInfo?["projectId"] as? String, "offline-project-a")
            XCTAssertEqual(notification.userInfo?[DeepLinkCoordinator.deepLinkIdUserInfoKey] as? String,
                           pending.deepLinkId.uuidString)
            XCTAssertTrue(notification.userInfo?[ProjectCreationPresentationTarget.userInfoKey] as? ProjectCreationPresentationTarget === target)
        }
        // After the unchanged route resolves or denies, its existing clear
        // retires the entire intent. Further readiness drains do nothing.
        coordinator.clear()
        coordinator.drain(context: "pin_unlocked")
        XCTAssertNil(coordinator.pendingLink)
        XCTAssertEqual(received.count, 2)
    }

    func testRetainedIntentDoesNotRetainParentAndExpiredReplayUsesRoot() throws {
        let notifications = NotificationCenter()
        let coordinator = DeepLinkCoordinator(notificationCenter: notifications)
        var endpoint: ProjectCreationPresentationEndpoint? = ProjectCreationPresentationEndpoint()
        endpoint?.appeared()
        weak var weakEndpoint = endpoint
        let target = ProjectCreationPresentationTarget(endpoint: try XCTUnwrap(endpoint))
        coordinator.receive(entity: "projects", id: "project-a", scheme: "toast", projectCreationPresentationTarget: target)
        endpoint = nil
        XCTAssertNil(weakEndpoint)
        var replay: Notification?
        let observer = notifications.addObserver(forName: .openProjectDetails, object: nil, queue: nil) { replay = $0 }
        defer {
            notifications.removeObserver(observer)
            coordinator.clear()
        }

        coordinator.drain(context: "pin_unlocked")
        let replayTarget = try XCTUnwrap(replay?.userInfo?[ProjectCreationPresentationTarget.userInfoKey] as? ProjectCreationPresentationTarget)
        XCTAssertTrue(replayTarget === target)
        var fallbackCount = 0
        ProjectCreationPresentationTarget.deliver(
            .project(Project(id: "project-a", title: "North deck", status: .rfq)), to: replayTarget
        ) { fallbackCount += 1 }
        XCTAssertEqual(fallbackCount, 1)
    }

    func testNewIntentReplacesProjectTargetAndOtherEntitiesNeverCarryIt() {
        let notifications = NotificationCenter()
        let coordinator = DeepLinkCoordinator(notificationCenter: notifications)
        let firstEndpoint = ProjectCreationPresentationEndpoint()
        let secondEndpoint = ProjectCreationPresentationEndpoint()
        let firstTarget = ProjectCreationPresentationTarget(endpoint: firstEndpoint)
        let secondTarget = ProjectCreationPresentationTarget(endpoint: secondEndpoint)
        var received: [Notification] = []
        let observer = notifications.addObserver(forName: nil, object: nil, queue: nil) { received.append($0) }
        defer {
            notifications.removeObserver(observer)
            coordinator.clear()
        }

        coordinator.receive(entity: "projects", id: "project-a", scheme: "toast", projectCreationPresentationTarget: firstTarget)
        coordinator.receive(entity: "projects", id: "project-b", scheme: "toast", projectCreationPresentationTarget: secondTarget)
        XCTAssertEqual(coordinator.pendingLink?.id, "project-b")
        coordinator.drain(context: "pin_unlocked")
        XCTAssertEqual(received.last?.userInfo?["projectId"] as? String, "project-b")
        XCTAssertTrue(received.last?.userInfo?[ProjectCreationPresentationTarget.userInfoKey] as? ProjectCreationPresentationTarget === secondTarget)

        coordinator.receive(entity: "clients", id: "client-a", scheme: "ops", projectCreationPresentationTarget: secondTarget)
        coordinator.drain(context: "main_tab_appear")
        XCTAssertEqual(received.last?.userInfo?["clientId"] as? String, "client-a")
        XCTAssertNil(received.last?.userInfo?[ProjectCreationPresentationTarget.userInfoKey])
        XCTAssertNil(coordinator.pendingLink?.projectCreationPresentationTarget)

        coordinator.receive(entity: "projects", id: "project-c", scheme: "ops")
        XCTAssertNil(coordinator.pendingLink?.projectCreationPresentationTarget)
        XCTAssertNil(received.last?.userInfo?[ProjectCreationPresentationTarget.userInfoKey])
    }

    func testReplacementAndClearReleaseOnlyTheRetainedTargetWrapper() {
        let coordinator = DeepLinkCoordinator(notificationCenter: NotificationCenter())
        let endpoint = ProjectCreationPresentationEndpoint()
        var target: ProjectCreationPresentationTarget? = ProjectCreationPresentationTarget(endpoint: endpoint)
        weak var weakTarget = target
        coordinator.receive(entity: "projects", id: "project-a", scheme: "toast", projectCreationPresentationTarget: target)
        target = nil
        XCTAssertNotNil(weakTarget)

        coordinator.receive(entity: "projects", id: "project-b", scheme: "ops")
        XCTAssertNil(weakTarget)

        target = ProjectCreationPresentationTarget(endpoint: endpoint)
        weakTarget = target
        coordinator.receive(entity: "projects", id: "project-c", scheme: "toast", projectCreationPresentationTarget: target)
        target = nil
        XCTAssertNotNil(weakTarget)
        coordinator.clear()
        XCTAssertNil(weakTarget)
    }
}
