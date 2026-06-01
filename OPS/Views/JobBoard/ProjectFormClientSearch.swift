//
//  ProjectFormClientSearch.swift
//  OPS
//
//  Pure search rules for the JobBoard project form client picker.
//

import Foundation

enum ProjectFormClientSearch {
    static func matchingClients(
        from clients: [Client],
        query: String,
        tutorialMode: Bool
    ) -> [Client] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if tutorialMode && trimmedQuery.isEmpty {
            return clients
        }
        guard !trimmedQuery.isEmpty else { return [] }

        return clients.filter { client in
            if client.name.localizedCaseInsensitiveContains(trimmedQuery) {
                return true
            }

            return client.subClients.contains { subClient in
                guard subClient.deletedAt == nil else { return false }
                return subClientSearchFields(subClient).contains { field in
                    field.localizedCaseInsensitiveContains(trimmedQuery)
                }
            }
        }
    }

    private static func subClientSearchFields(_ subClient: SubClient) -> [String] {
        [
            subClient.name,
            subClient.title,
            subClient.email,
            subClient.phoneNumber,
            subClient.address
        ].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
