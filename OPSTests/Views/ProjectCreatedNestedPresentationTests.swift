#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

/// Exercises both real MainTabView parent-sheet placements with the production
/// local host: the FAB's sibling branch and Search/Contact's outer container.
@MainActor
final class ProjectCreatedNestedPresentationTests: XCTestCase {
    func testRootProjectRouteOpensAboveNestedParentAndPreservesItsDraft() async throws {
        try await assertNestedPresentation(parentPlacement: .siblingBranch)
    }

    func testRootProjectRouteOpensAboveOuterContainerParentAndPreservesItsDraft() async throws {
        try await assertNestedPresentation(parentPlacement: .outerContainer)
    }

    func testPermissionDenialIsVisibleAboveParentAndPreservesItsDraft() async throws {
        try await assertNestedPresentation(parentPlacement: .outerContainer, outcome: .denied)
    }

    func testDismissedParentTargetFallsBackToVisibleRootDestination() async throws {
        try await assertNestedPresentation(parentPlacement: .outerContainer, outcome: .parentClosed)
    }

    private func assertNestedPresentation(
        parentPlacement: ParentSheetPlacement,
        outcome: RouteOutcome = .allowed
    ) async throws {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        let state = AppState()
        let presentation = NestedCreationPresentation(outcome: outcome)
        let routes = NotificationCenter()
        let created = expectation(description: "Child creation finished dismissal")
        let parentVisible = expectation(description: "Parent form fully presented")
        let parentClosed = outcome == .parentClosed
            ? expectation(description: "Parent form finished dismissal") : nil
        let creationVisible = expectation(description: "Creation child fully presented")
        let destinationVisible = expectation(description: "Validated route destination visibly presented")
        let destinationClosed = expectation(description: "Route destination finished dismissal")
        let completion = ProjectCreationCompletion { notification in
            ToastCenter.shared.present(ProjectCreationCompletion.toast(for: notification, notificationCenter: routes))
            created.fulfill()
        }
        let host = UIHostingController(rootView: NestedCreationRoot(
            presentation: presentation, appState: state, completion: completion,
            routes: routes, parentPlacement: parentPlacement
        ))
        defer {
            ToastCenter.shared.reset()
            presentation.editDraft = nil
            presentation.readDraft = nil
            presentation.saveCreation = nil
            presentation.closeDestination = nil
            host.dismiss(animated: false)
            window.rootViewController = originalRoot
            window.makeKeyAndVisible()
        }
        ToastCenter.shared.reset()
        presentation.onParentVisible = { parentVisible.fulfill() }
        presentation.onParentClosed = { parentClosed?.fulfill() }
        presentation.onCreationVisible = { creationVisible.fulfill() }
        presentation.onDestinationVisible = { destinationVisible.fulfill() }
        presentation.onDestinationClosed = { destinationClosed.fulfill() }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        presentation.showParent = true
        await fulfillment(of: [parentVisible], timeout: 3)
        let parent = try XCTUnwrap(presentation.parentController)
        let parentIdentity = try XCTUnwrap(presentation.parentIdentity)
        presentation.editDraft?("Unfinished task: return Thursday")
        XCTAssertEqual(presentation.readDraft?(), "Unfinished task: return Thursday")

        presentation.showCreation = true
        await fulfillment(of: [creationVisible], timeout: 3)
        XCTAssertNotNil(parent.presentedViewController)
        try XCTUnwrap(presentation.saveCreation)()
        presentation.showCreation = false
        await fulfillment(of: [created], timeout: 3)
        XCTAssertTrue(presentation.showParent)
        XCTAssertTrue(host.presentedViewController === parent)
        XCTAssertNil(parent.presentedViewController)

        if outcome == .parentClosed {
            presentation.showParent = false
            await fulfillment(of: [try XCTUnwrap(parentClosed)], timeout: 3)
            XCTAssertNil(host.presentedViewController)
        }

        let toast = try XCTUnwrap(ToastCenter.shared.current)
        ToastCenter.shared.handleTap(toastID: toast.id, target: .message)
        await fulfillment(of: [destinationVisible], timeout: 3)
        let destination = try XCTUnwrap(presentation.destinationController)
        XCTAssertEqual(presentation.routedIDs, ["project-a"])
        XCTAssertTrue(presentation.receivedOriginTarget)
        XCTAssertEqual(presentation.displayedDestinationID,
                       outcome == .denied ? "denied:\(NestedCreationPresentation.denialMessage)" : "project:project-a")
        if outcome == .parentClosed {
            XCTAssertTrue(host.presentedViewController === destination)
            XCTAssertEqual(state.activeProjectID, "project-a")
        } else {
            XCTAssertTrue(host.presentedViewController === parent)
            XCTAssertTrue(parent.presentedViewController === destination)
            XCTAssertNil(state.activeProjectID)
            XCTAssertFalse(state.showProjectDetails)
            XCTAssertTrue(presentation.showParent)
            XCTAssertEqual(presentation.parentIdentity, parentIdentity)
            XCTAssertEqual(presentation.readDraft?(), "Unfinished task: return Thursday")
        }

        try XCTUnwrap(presentation.closeDestination)()
        await fulfillment(of: [destinationClosed], timeout: 3)
        if outcome == .parentClosed {
            XCTAssertNil(host.presentedViewController)
        } else {
            XCTAssertTrue(host.presentedViewController === parent)
            XCTAssertNil(parent.presentedViewController)
            XCTAssertEqual(presentation.parentIdentity, parentIdentity)
            XCTAssertEqual(presentation.readDraft?(), "Unfinished task: return Thursday")
        }
        presentation.onParentClosed = nil
    }
}

private enum ParentSheetPlacement: Equatable {
    case siblingBranch
    case outerContainer
}

private enum RouteOutcome: Equatable {
    case allowed
    case denied
    case parentClosed
}

@MainActor
private final class NestedCreationPresentation: ObservableObject {
    static let denialMessage = "You don't have permission to view this project."
    let outcome: RouteOutcome
    @Published var showParent = false
    @Published var showCreation = false
    weak var parentController: UIViewController?
    weak var destinationController: UIViewController?
    var parentIdentity: UUID?
    var routedIDs: [String] = []
    var receivedOriginTarget = false
    var displayedDestinationID: String?
    var editDraft: ((String) -> Void)?
    var readDraft: (() -> String)?
    var saveCreation: (() -> Void)?
    var closeDestination: (() -> Void)?
    var onParentVisible: (() -> Void)?
    var onParentClosed: (() -> Void)?
    var onCreationVisible: (() -> Void)?
    var onDestinationVisible: (() -> Void)?
    var onDestinationClosed: (() -> Void)?

    init(outcome: RouteOutcome) { self.outcome = outcome }
}

private struct NestedCreationRoot: View {
    @ObservedObject var presentation: NestedCreationPresentation
    @ObservedObject var appState: AppState
    let completion: ProjectCreationCompletion
    let routes: NotificationCenter
    let parentPlacement: ParentSheetPlacement

    var body: some View {
        container
            .onReceive(routes.publisher(for: .openProjectDetails)) { notification in
                guard let id = notification.userInfo?["projectId"] as? String else { return }
                let target = notification.userInfo?[ProjectCreationPresentationTarget.userInfoKey] as? ProjectCreationPresentationTarget
                presentation.routedIDs.append(id)
                presentation.receivedOriginTarget = target != nil
                // The actual production handoff, after MainTabView's existing
                // local-first resolution and unchanged authorization checks.
                let destination: ProjectCreationDestination = presentation.outcome == .denied
                    ? .denied(NestedCreationPresentation.denialMessage)
                    : .project(Project(id: id, title: "North deck", status: .rfq))
                ProjectCreationPresentationTarget.deliver(destination, to: target) {
                    appState.viewProjectDetailsById(id)
                }
            }
    }

    @ViewBuilder
    private var container: some View {
        if parentPlacement == .outerContainer {
            rootContents
                .sheet(isPresented: $presentation.showParent, onDismiss: { presentation.onParentClosed?() }) {
                    NestedCreationParent(presentation: presentation, completion: completion)
                }
        } else {
            rootContents
        }
    }

    private var rootContents: some View {
        ZStack {
            if parentPlacement == .siblingBranch {
                Color.clear
                    .sheet(isPresented: $presentation.showParent, onDismiss: { presentation.onParentClosed?() }) {
                        NestedCreationParent(presentation: presentation, completion: completion)
                    }
            }
            // Matches the independent root ProjectSheetContainer branch.
            Color.clear
                .sheet(isPresented: $appState.showProjectDetails) {
                    NestedCreationDestination(
                        presentation: presentation,
                        destination: .project(Project(id: appState.activeProjectID ?? "missing", title: "North deck", status: .rfq))
                    )
                }
        }
    }
}

private struct NestedCreationParent: View {
    @ObservedObject var presentation: NestedCreationPresentation
    let completion: ProjectCreationCompletion
    @State private var draft = "Initial draft"
    @State private var instanceID = UUID()

    var body: some View {
        TextField("Parent draft", text: $draft)
            .background(PresentationDidAppear { controller in
                presentation.parentController = controller
                presentation.parentIdentity = instanceID
                presentation.editDraft = { draft = $0 }
                presentation.readDraft = { draft }
                let callback = presentation.onParentVisible
                presentation.onParentVisible = nil
                callback?()
            })
            .sheet(isPresented: $presentation.showCreation) {
                NestedCreationChild(presentation: presentation, completion: completion)
            }
            .modifier(ProjectCreationPresentationHost { destination in
                NestedCreationDestination(presentation: presentation, destination: destination)
            })
    }
}

private struct NestedCreationChild: View {
    @Environment(\.projectCreationPresentationTarget) private var target
    @ObservedObject var presentation: NestedCreationPresentation
    let completion: ProjectCreationCompletion

    var body: some View {
        Text("Creation form")
            .background(ProjectCreationDismissalObserver(completion: completion))
            .background(PresentationDidAppear { _ in
                presentation.saveCreation = {
                    completion.projectCreated(id: "project-a", title: "North deck", presentationTarget: target)
                }
                let callback = presentation.onCreationVisible
                presentation.onCreationVisible = nil
                callback?()
            })
    }
}

private struct NestedCreationDestination: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var presentation: NestedCreationPresentation
    let destination: ProjectCreationDestination

    var body: some View {
        Group {
            switch destination {
            case .project(let project): Text(project.title)
            case .denied(let message): AccessDeniedSheet(message: message)
            }
        }
        .background(PresentationDidAppear { controller in
            presentation.destinationController = controller
            presentation.displayedDestinationID = destination.id
            presentation.closeDestination = { dismiss() }
            let callback = presentation.onDestinationVisible
            presentation.onDestinationVisible = nil
            callback?()
        })
        .background(PresentationDidDismiss {
            let callback = presentation.onDestinationClosed
            presentation.onDestinationClosed = nil
            callback?()
        })
    }
}

private struct PresentationDidDismiss: UIViewControllerRepresentable {
    let callback: () -> Void
    func makeUIViewController(context: Context) -> ProjectCreationDismissalViewController {
        ProjectCreationDismissalViewController(onDismissal: callback)
    }
    func updateUIViewController(_ controller: ProjectCreationDismissalViewController, context: Context) {}
}

/// Waits on a real completed appearance, not a SwiftUI onAppear or a sleep.
private struct PresentationDidAppear: UIViewControllerRepresentable {
    let callback: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(callback: callback) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.callback = callback }

    final class Controller: UIViewController {
        var callback: (UIViewController) -> Void
        init(callback: @escaping (UIViewController) -> Void) {
            self.callback = callback
            super.init(nibName: nil, bundle: nil)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Use init(callback:)") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            var host: UIViewController = self
            while let parent = host.parent { host = parent }
            callback(host)
        }
    }
}
#endif
