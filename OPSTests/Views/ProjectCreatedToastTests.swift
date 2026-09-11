import SwiftUI
import UIKit
import XCTest
@testable import OPS

@MainActor
final class ProjectCreatedToastTests: XCTestCase {
    private var center: ToastCenter { .shared }

    override func setUp() {
        super.setUp()
        center.reset()
    }

    override func tearDown() {
        center.reset()
        super.tearDown()
    }

    func testCreationWaitsForCompletedDismissalAndPostsOnlyOnce() {
        var notifications: [Notification] = []
        let completion = ProjectCreationCompletion(post: { notifications.append($0) })
        completion.projectCreated(id: "project-a", title: "North deck")
        XCTAssertTrue(notifications.isEmpty)

        completion.presentationDidDismiss()
        completion.presentationDidDismiss()
        completion.projectCreated(id: "project-b", title: "Later state")

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.name, ProjectCreationCompletion.notificationName)
        XCTAssertEqual(notifications.first?.userInfo?["projectId"] as? String, "project-a")
        XCTAssertEqual(notifications.first?.userInfo?["projectTitle"] as? String, "North deck")
    }

    func testSaveCompletingAfterDismissalStillPostsExactProject() {
        var notifications: [Notification] = []
        let completion = ProjectCreationCompletion(post: { notifications.append($0) })
        completion.presentationDidDismiss()
        XCTAssertTrue(notifications.isEmpty)
        completion.projectCreated(id: "offline-project", title: "Saved locally")
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.userInfo?["projectId"] as? String, "offline-project")
    }

    func testToastBodyPostsExistingRouteWithImmutableProjectIDOnce() {
        let notifications = NotificationCenter()
        var routes: [Notification] = []
        let observer = notifications.addObserver(forName: .openProjectDetails, object: nil, queue: nil) {
            routes.append($0)
        }
        defer { notifications.removeObserver(observer) }
        var info = ["projectId": "project-a", "projectTitle": "North deck"]
        let toast = ProjectCreationCompletion.toast(
            for: Notification(name: ProjectCreationCompletion.notificationName, userInfo: info),
            notificationCenter: notifications
        )
        info["projectId"] = "project-b"
        center.present(toast)
        center.handleTap(toastID: toast.id, target: .message)
        center.handleTap(toastID: toast.id, target: .action)

        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes.first?.userInfo?["projectId"] as? String, "project-a")
        XCTAssertNil(routes.first?.userInfo?["projectID"])
        XCTAssertNil(center.current)
    }

    func testViewActionOpensOnceWithoutDismissingQueuedToast() {
        var opened: [String] = []
        let toast = Feedback.JobBoard.projectCreated(title: "Deck", projectID: "project-a") { opened.append($0) }
        let next = Feedback.saved("client")
        center.present(toast)
        center.present(next)
        center.handleTap(toastID: toast.id, target: .action)
        center.handleTap(toastID: toast.id, target: .message)
        XCTAssertEqual(opened, ["project-a"])
        XCTAssertEqual(center.current?.id, next.id)
    }

    func testLegacyAndTutorialPayloadsHaveNoProjectAction() {
        for projectID: String? in [nil, "", "  \n", "DEMO_PROJECT_123"] {
            let toast = Feedback.JobBoard.projectCreated(title: "Demo", projectID: projectID) { _ in
                XCTFail("Missing and tutorial identities must never route")
            }
            XCTAssertNil(toast.action)
            XCTAssertFalse(toast.bodyTapInvokesAction)
            XCTAssertFalse(toast.haptics)
        }
    }

    func testCopyPreservesResolvedTitleAndOffersViewAction() {
        let toast = Feedback.JobBoard.projectCreated(title: "  North deck  ", projectID: "project-a") { _ in }
        XCTAssertEqual(toast.label, "// PROJECT CREATED · NORTH DECK")
        XCTAssertEqual(toast.action?.label, "VIEW")
        XCTAssertEqual(toast.action?.accessibilityLabel, "View project")
        XCTAssertTrue(toast.bodyTapInvokesAction)
        XCTAssertEqual(toast.autoDismissAfter, 6)
        XCTAssertFalse(toast.haptics)
        let unnamed = Feedback.JobBoard.projectCreated(title: "  ", projectID: "project-b") { _ in }
        XCTAssertEqual(unnamed.label, "// PROJECT CREATED")
    }

    func testSameTitleDifferentProjectsRemainSeparateAndDuplicateIDCoalesces() {
        let first = Feedback.JobBoard.projectCreated(title: "Deck", projectID: "project-a") { _ in }
        let second = Feedback.JobBoard.projectCreated(title: "Deck", projectID: "project-b") { _ in }
        let duplicate = Feedback.JobBoard.projectCreated(title: "Deck", projectID: "project-b") { _ in }
        center.present(first)
        center.present(second)
        center.present(duplicate)
        XCTAssertEqual(center.current?.id, first.id)
        XCTAssertEqual(center.queue.map(\.id), [second.id])
    }

    func testOtherToastBodiesStillDismissWithoutRunningTheirAction() {
        var actions = 0
        let toast = Toast(label: "// EXISTING", tone: .success, action: ToastAction(label: "VIEW") { actions += 1 })
        center.present(toast)
        center.handleTap(toastID: toast.id, target: .message)
        XCTAssertEqual(actions, 0)
        XCTAssertNil(center.current)
        center.present(toast)
        center.handleTap(toastID: toast.id, target: .action)
        XCTAssertEqual(actions, 1)
    }

    func testExistingLabelCoalescingIsUnchanged() {
        center.present(Feedback.saved("client"))
        center.present(Feedback.saved("client"))
        XCTAssertTrue(center.queue.isEmpty)
    }
}

#if DEBUG
@MainActor
final class ProjectCreationDismissalTests: XCTestCase {
    private var window: UIWindow!
    private var originalRoot: UIViewController?
    private var presenter: UIViewController!

    override func setUpWithError() throws {
        window = try AppHostWindow.acquire()
        originalRoot = window.rootViewController
        presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        presenter.loadViewIfNeeded()
    }

    override func tearDown() {
        ToastCenter.shared.reset()
        presenter.dismiss(animated: false)
        window.rootViewController = originalRoot
        window.makeKeyAndVisible()
        presenter = nil
        originalRoot = nil
        window = nil
        super.tearDown()
    }

    func testCreatedProjectToastSnapshot() throws {
        ToastCenter.shared.reset()
        ToastCenter.shared.present(Feedback.JobBoard.projectCreated(title: "North deck", projectID: "project-a") { _ in })
        let host = UIHostingController(rootView: ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            ToastHostView()
        }.environment(\.colorScheme, .dark))
        window.rootViewController = host
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Project created toast — tap to open North deck"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testRealSheetPublishesOnlyAfterItsDismissalAndCanImmediatelyOpenDestination() async {
        let posted = expectation(description: "Creation emitted after completed sheet dismissal")
        var sheet: UIViewController!
        let destination = UIViewController()
        var count = 0
        let completion = ProjectCreationCompletion { _ in
            count += 1
            XCTAssertNil(sheet.presentingViewController)
            XCTAssertNil(self.presenter.presentedViewController)
            self.presenter.present(destination, animated: false) { posted.fulfill() }
        }
        sheet = makeSheet(completion)
        await present(sheet, from: presenter)
        completion.projectCreated(id: "project-a", title: "Deck")
        XCTAssertEqual(count, 0)
        await dismiss(sheet)
        await fulfillment(of: [posted], timeout: 3)
        XCTAssertEqual(count, 1)
        XCTAssertTrue(presenter.presentedViewController === destination)
    }

    func testRealSheetDismissalBeforeSaveCompletionIsRetained() async {
        let posted = expectation(description: "Late save emitted after dismissal")
        var count = 0
        let completion = ProjectCreationCompletion { _ in count += 1; posted.fulfill() }
        let sheet = makeSheet(completion)
        await present(sheet, from: presenter)
        await dismiss(sheet)
        XCTAssertEqual(count, 0)
        completion.projectCreated(id: "offline-project", title: "Offline deck")
        await fulfillment(of: [posted], timeout: 3)
        XCTAssertEqual(count, 1)
    }

    func testFullScreenChildAndBackgroundDoNotReleaseCreationFeedback() async {
        var count = 0
        let completion = ProjectCreationCompletion { _ in count += 1 }
        let sheet = makeSheet(completion)
        await present(sheet, from: presenter)
        completion.projectCreated(id: "project-a", title: "Deck")
        let child = UIViewController()
        child.modalPresentationStyle = .fullScreen
        await present(child, from: sheet)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(count, 0)
        await dismiss(child)
        XCTAssertEqual(count, 0)
        await dismiss(sheet)
    }

    func testCancelledInteractiveSheetDismissalCannotReleaseCreationFeedback() async {
        var count = 0
        let completion = ProjectCreationCompletion { _ in count += 1 }
        let sheet = makeSheet(completion)
        let transition = ControlledDismissalTransition()
        sheet.modalPresentationStyle = .fullScreen
        sheet.transitioningDelegate = transition
        await present(sheet, from: presenter)
        completion.projectCreated(id: "project-a", title: "Deck")

        let started = expectation(description: "Interactive dismissal started")
        let cancelled = expectation(description: "Interactive dismissal canceled")
        transition.onStart = { started.fulfill() }
        transition.onEnd = { cancelled.fulfill() }
        transition.interaction = UIPercentDrivenInteractiveTransition()
        sheet.dismiss(animated: true)
        await fulfillment(of: [started], timeout: 3)
        transition.interaction?.update(0.3)
        transition.interaction?.cancel()
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertEqual(count, 0)
        XCTAssertTrue(presenter.presentedViewController === sheet)
        transition.interaction = nil
        transition.onStart = nil
        transition.onEnd = nil
        await dismiss(sheet)
    }

    private func makeSheet(_ completion: ProjectCreationCompletion) -> UIViewController {
        let sheet = UIHostingController(rootView: Color.clear.background(ProjectCreationDismissalObserver(completion: completion)))
        sheet.modalPresentationStyle = .pageSheet
        return sheet
    }

    private func present(_ controller: UIViewController, from source: UIViewController) async {
        await withCheckedContinuation { continuation in
            source.present(controller, animated: true) { continuation.resume() }
        }
    }

    private func dismiss(_ controller: UIViewController) async {
        await withCheckedContinuation { continuation in
            controller.dismiss(animated: true) { continuation.resume() }
        }
    }
}

/// Drives a genuine UIKit interactive cancellation without synthesizing
/// lifecycle callbacks or depending on a gesture's pixel coordinates.
@MainActor
private final class ControlledDismissalTransition: NSObject, UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning {
    var interaction: UIPercentDrivenInteractiveTransition?
    var onStart: (() -> Void)?
    var onEnd: (() -> Void)?

    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { self }
    func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? { interaction }
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval { 0.2 }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let view = transitionContext.view(forKey: .from) else {
            transitionContext.completeTransition(false)
            return
        }
        UIView.animate(withDuration: transitionDuration(using: transitionContext)) {
            view.transform = CGAffineTransform(translationX: 0, y: view.bounds.height)
        } completion: { _ in
            view.transform = .identity
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            self.onEnd?()
        }
        onStart?()
    }
}
#endif
