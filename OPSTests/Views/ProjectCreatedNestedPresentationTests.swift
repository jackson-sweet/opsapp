#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import OPS

/// Reproduces both MainTabView parent-sheet placements: the FAB owns a sibling
/// branch; UniversalSearch and ContactDetail attach to the outer root container.
/// ProjectSheetContainer independently owns the root project-details binding.
@MainActor
final class ProjectCreatedNestedPresentationTests: XCTestCase {
    func testRootProjectRouteOpensAboveNestedParentAndPreservesItsDraft() async throws {
        try await assertNestedPresentation(parentPlacement: .siblingBranch)
    }

    func testRootProjectRouteOpensAboveOuterContainerParentAndPreservesItsDraft() async throws {
        try await assertNestedPresentation(parentPlacement: .outerContainer)
    }

    private func assertNestedPresentation(parentPlacement: ParentSheetPlacement) async throws {
        let window = try AppHostWindow.acquire()
        let originalRoot = window.rootViewController
        let state = AppState()
        let presentation = NestedCreationPresentation()
        let routes = NotificationCenter()
        let created = expectation(description: "Child creation finished dismissal")
        let parentVisible = expectation(description: "Parent form fully presented")
        let creationVisible = expectation(description: "Creation child fully presented")
        let destinationVisible = expectation(description: "Root project destination visible above parent")
        let destinationClosed = expectation(description: "Project destination closed")
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
            host.dismiss(animated: false)
            window.rootViewController = originalRoot
            window.makeKeyAndVisible()
        }
        ToastCenter.shared.reset()
        presentation.onParentVisible = { parentVisible.fulfill() }
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
        completion.projectCreated(id: "project-a", title: "North deck")
        presentation.showCreation = false
        await fulfillment(of: [created], timeout: 3)
        XCTAssertTrue(presentation.showParent)
        XCTAssertTrue(host.presentedViewController === parent)
        XCTAssertNil(parent.presentedViewController)

        let toast = try XCTUnwrap(ToastCenter.shared.current)
        ToastCenter.shared.handleTap(toastID: toast.id, target: .message)
        await fulfillment(of: [destinationVisible], timeout: 3)
        let destination = try XCTUnwrap(presentation.destinationController)
        XCTAssertTrue(host.presentedViewController === parent)
        XCTAssertTrue(parent.presentedViewController === destination)
        XCTAssertEqual(state.activeProjectID, "project-a")
        XCTAssertTrue(presentation.showParent)
        XCTAssertEqual(presentation.parentIdentity, parentIdentity)
        XCTAssertEqual(presentation.readDraft?(), "Unfinished task: return Thursday")

        state.dismissProjectDetails()
        await fulfillment(of: [destinationClosed], timeout: 3)
        XCTAssertTrue(host.presentedViewController === parent)
        XCTAssertNil(parent.presentedViewController)
        XCTAssertEqual(presentation.parentIdentity, parentIdentity)
        XCTAssertEqual(presentation.readDraft?(), "Unfinished task: return Thursday")
    }
}

private enum ParentSheetPlacement: Equatable {
    case siblingBranch
    case outerContainer
}

@MainActor
private final class NestedCreationPresentation: ObservableObject {
    @Published var showParent = false
    @Published var showCreation = false
    weak var parentController: UIViewController?
    weak var destinationController: UIViewController?
    var parentIdentity: UUID?
    var editDraft: ((String) -> Void)?
    var readDraft: (() -> String)?
    var onParentVisible: (() -> Void)?
    var onCreationVisible: (() -> Void)?
    var onDestinationVisible: (() -> Void)?
    var onDestinationClosed: (() -> Void)?
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
                // Uses the actual presentation-state handoff called after the
                // production route's local-first resolution and permission checks.
                appState.viewProjectDetailsById(id)
            }
    }

    @ViewBuilder
    private var container: some View {
        if parentPlacement == .outerContainer {
            // UniversalSearch and ContactDetail attach outside MainTabView's
            // ZStack, while ProjectSheetContainer remains a child inside it.
            rootContents
                .sheet(isPresented: $presentation.showParent) {
                    NestedCreationParent(presentation: presentation, completion: completion)
                }
        } else {
            rootContents
        }
    }

    private var rootContents: some View {
        ZStack {
            if parentPlacement == .siblingBranch {
                // The FAB owns its sheet on a sibling inside MainTabView.
                Color.clear
                    .sheet(isPresented: $presentation.showParent) {
                        NestedCreationParent(presentation: presentation, completion: completion)
                    }
            }
            // Matches the independent root ProjectSheetContainer branch.
            Color.clear
                .sheet(isPresented: $appState.showProjectDetails, onDismiss: {
                    appState.dismissProjectDetails()
                    presentation.onDestinationClosed?()
                }) {
                    Text("Project destination")
                        .background(PresentationDidAppear { controller in
                            presentation.destinationController = controller
                            let callback = presentation.onDestinationVisible
                            presentation.onDestinationVisible = nil
                            callback?()
                        })
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
                Text("Creation form")
                    .background(ProjectCreationDismissalObserver(completion: completion))
                    .background(PresentationDidAppear { _ in
                        let callback = presentation.onCreationVisible
                        presentation.onCreationVisible = nil
                        callback?()
                    })
            }
    }
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
