import SwiftUI
import UIKit

/// Holds the identity of one successful creation until its form has actually
/// left presentation. Save and dismissal may finish in either order.
@MainActor
final class ProjectCreationCompletion: ObservableObject {
    static let notificationName = Notification.Name("ProjectCreatedSuccess")

    private var createdProject: (id: String, title: String, presentationTarget: ProjectCreationPresentationTarget?)?
    private var didDismiss = false
    private var didPost = false
    private let post: (Notification) -> Void

    init(post: @escaping (Notification) -> Void = { NotificationCenter.default.post($0) }) {
        self.post = post
    }

    func projectCreated(id: String, title: String, presentationTarget: ProjectCreationPresentationTarget? = nil) {
        guard !didPost, createdProject == nil else { return }
        createdProject = (id, title, presentationTarget)
        postIfReady()
    }

    func presentationDidDismiss() {
        didDismiss = true
        postIfReady()
    }

    private func postIfReady() {
        guard didDismiss, !didPost, let createdProject else { return }
        didPost = true
        var info: [AnyHashable: Any] = ["projectId": createdProject.id, "projectTitle": createdProject.title]
        if let target = createdProject.presentationTarget {
            info[ProjectCreationPresentationTarget.userInfoKey] = target
        }
        post(Notification(name: Self.notificationName, userInfo: info))
    }

    static func toast(
        for notification: Notification,
        notificationCenter: NotificationCenter = .default
    ) -> Toast {
        let target = notification.userInfo?[ProjectCreationPresentationTarget.userInfoKey] as? ProjectCreationPresentationTarget
        return Feedback.JobBoard.projectCreated(
            title: notification.userInfo?["projectTitle"] as? String ?? "",
            projectID: notification.userInfo?["projectId"] as? String
        ) { projectID in
            // The existing mounted route checks permissions and resolves the
            // local project first, including projects still waiting to sync.
            var info: [AnyHashable: Any] = ["projectId": projectID]
            if let target { info[ProjectCreationPresentationTarget.userInfoKey] = target }
            notificationCenter.post(
                name: .openProjectDetails,
                object: nil,
                userInfo: info
            )
        }
    }
}

/// Observes the sheet's UIKit lifecycle without taking ownership of its
/// SwiftUI binding or interfering with its presentation-controller delegate.
struct ProjectCreationDismissalObserver: UIViewControllerRepresentable {
    let completion: ProjectCreationCompletion

    func makeUIViewController(context: Context) -> ProjectCreationDismissalViewController {
        ProjectCreationDismissalViewController(completion: completion)
    }

    func updateUIViewController(_ controller: ProjectCreationDismissalViewController, context: Context) {}
}

final class ProjectCreationDismissalViewController: UIViewController {
    private let onDismissal: () -> Void
    var onDidAppear: (() -> Void)?
    private var isDismissingPresentation = false

    convenience init(completion: ProjectCreationCompletion) {
        self.init(onDismissal: completion.presentationDidDismiss)
    }

    init(onDismissal: @escaping () -> Void) {
        self.onDismissal = onDismissal
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(onDismissal:)") }

    override func loadView() {
        let view = UIView()
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // An interactive dismissal that is canceled comes back through here.
        isDismissingPresentation = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onDidAppear?()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Covering this sheet with a camera/full-screen child is not dismissal.
        // Walk containment because the actual sheet host owns isBeingDismissed.
        var ancestor: UIViewController? = self
        isDismissingPresentation = false
        while let controller = ancestor {
            if controller.isBeingDismissed {
                isDismissingPresentation = true
                break
            }
            ancestor = controller.parent
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isDismissingPresentation,
              transitionCoordinator?.isCancelled != true else { return }
        isDismissingPresentation = false
        let onDismissal = onDismissal
        // UIKit calls viewDidDisappear before it retires the presentation and
        // calls dismiss's completion. Let that same main-thread transaction
        // unwind before exposing a navigation action; no guessed delay.
        DispatchQueue.main.async { onDismissal() }
    }
}
