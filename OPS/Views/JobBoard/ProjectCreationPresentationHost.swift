import SwiftUI
import UIKit

enum ProjectCreationDestination: Identifiable {
    case project(Project)
    case denied(String)

    var id: String {
        switch self {
        case .project(let project): return "project:\(project.id)"
        case .denied(let message): return "denied:\(message)"
        }
    }
}

/// A presentation address, never an authorization grant. The existing root
/// project route must validate access before delivering either outcome here.
/// Keeping only a weak endpoint lets a toast outlive a dismissed parent form.
@MainActor
final class ProjectCreationPresentationTarget {
    static let userInfoKey = "projectCreationPresentationTarget"
    private weak var endpoint: ProjectCreationPresentationEndpoint?

    init(endpoint: ProjectCreationPresentationEndpoint) { self.endpoint = endpoint }

    static func deliver(
        _ destination: ProjectCreationDestination,
        to target: ProjectCreationPresentationTarget?,
        fallback: () -> Void
    ) {
        guard let endpoint = target?.endpoint, endpoint.isAvailable else {
            fallback()
            return
        }
        guard endpoint.destination?.id != destination.id else { return }
        endpoint.destination = destination
    }
}

@MainActor
final class ProjectCreationPresentationEndpoint: ObservableObject {
    @Published var destination: ProjectCreationDestination?
    private(set) var isAvailable = false

    func appeared() { isAvailable = true }
    func dismissed() { isAvailable = false }
}

private struct ProjectCreationPresentationTargetKey: EnvironmentKey {
    static let defaultValue: ProjectCreationPresentationTarget? = nil
}

extension EnvironmentValues {
    var projectCreationPresentationTarget: ProjectCreationPresentationTarget? {
        get { self[ProjectCreationPresentationTargetKey.self] }
        set { self[ProjectCreationPresentationTargetKey.self] = newValue }
    }
}

/// The sheet belongs to the parent that launched creation, so displaying a
/// project does not dismiss or reconstruct that parent's unfinished draft.
/// The generic destination lets hosted tests exercise this exact modifier
/// without starting ProjectDetailsView's data-loading side effects.
@MainActor
struct ProjectCreationPresentationHost<Destination: View>: ViewModifier {
    @StateObject private var endpoint = ProjectCreationPresentationEndpoint()
    let destination: (ProjectCreationDestination) -> Destination

    init(@ViewBuilder destination: @escaping (ProjectCreationDestination) -> Destination) {
        self.destination = destination
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $endpoint.destination) { destination($0) }
            .background(ProjectCreationPresentationLifetime(endpoint: endpoint)
                .allowsHitTesting(false)
                .accessibilityHidden(true))
            .environment(\.projectCreationPresentationTarget, ProjectCreationPresentationTarget(endpoint: endpoint))
    }
}

/// Reuses the proven creation-sheet lifecycle bridge. A covering child never
/// expires the parent; a real completed dismissal does, even if SwiftUI keeps
/// the parent's StateObject alive while retiring its presentation.
private struct ProjectCreationPresentationLifetime: UIViewControllerRepresentable {
    let endpoint: ProjectCreationPresentationEndpoint

    func makeUIViewController(context: Context) -> ProjectCreationDismissalViewController {
        let controller = ProjectCreationDismissalViewController(onDismissal: { [weak endpoint] in endpoint?.dismissed() })
        controller.onDidAppear = { [weak endpoint] in endpoint?.appeared() }
        return controller
    }

    func updateUIViewController(_ controller: ProjectCreationDismissalViewController, context: Context) {}
}

extension View {
    @MainActor
    func projectCreationToastHost() -> some View {
        modifier(ProjectCreationPresentationHost { destination in
            switch destination {
            case .project(let project):
                NavigationView {
                    ProjectDetailsView(project: project)
                }
                .interactiveDismissDisabled(true)
            case .denied(let message):
                AccessDeniedSheet(message: message)
            }
        })
    }
}
