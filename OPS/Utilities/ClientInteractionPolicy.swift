//
//  ClientInteractionPolicy.swift
//  OPS
//
//  Shared client-action policy and deletion presentation ordering.
//

import Foundation
import Combine

enum ClientLongPressAction: Hashable, Identifiable {
    case viewClient
    case addProject
    case deleteClient

    var id: Self { self }
}

enum ClientLongPressActionPolicy {
    static func actions(
        canCreateProject: Bool,
        canDeleteClient: Bool
    ) -> [ClientLongPressAction] {
        var result: [ClientLongPressAction] = [.viewClient]
        if canCreateProject {
            result.append(.addProject)
        }
        if canDeleteClient {
            result.append(.deleteClient)
        }
        return result
    }
}

enum ClientDeletionTargetPolicy {
    static func candidates(from clients: [Client], deleting client: Client) -> [Client] {
        let deletingId = canonicalId(client.id)
        var seenIds = Set<String>()

        return clients
            .filter {
                canonicalId($0.id) != deletingId &&
                $0.companyId == client.companyId &&
                $0.deletedAt == nil
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            .filter { seenIds.insert(canonicalId($0.id)).inserted }
    }

    private static func canonicalId(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
final class ClientDeletionPresentationGate: ObservableObject {
    private var didDisappear = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilDismissed() async {
        guard !didDisappear else { return }

        await withCheckedContinuation { continuation in
            if didDisappear {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func signalDismissed() {
        guard !didDisappear else { return }
        didDisappear = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}

enum ClientDeletionPresentationCoordinator {
    @MainActor
    static func performInvalidatingMutation(
        dismissPresentations: @MainActor () -> Void,
        waitForDismissal: @MainActor () async -> Void,
        mutation: @MainActor () async throws -> Void
    ) async rethrows {
        dismissPresentations()
        await waitForDismissal()
        try await mutation()
    }
}
