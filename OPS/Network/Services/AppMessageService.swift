//
//  AppMessageService.swift
//  OPS
//
//  Service for fetching app messages from Bubble
//  Used to display update notices, maintenance alerts, and announcements on app launch
//

import Foundation

class AppMessageService {
    private let baseURL: URL

    init(baseURL: URL = AppConfiguration.bubbleBaseURL) {
        self.baseURL = baseURL
    }

    /// Fetches the active app message from Bubble
    /// Returns nil if no active message exists or if the fetch fails
    /// If multiple active messages exist, returns the most recent by Created Date
    func fetchActiveMessage() async -> AppMessageDTO? {
        // Build URL with constraint for active = true
        let endpoint = baseURL.appendingPathComponent("api/1.1/obj/AppMessage")

        var urlComponents = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)

        // Constraint: active = true, sorted by Created Date descending
        let constraints: [[String: Any]] = [
            [
                "key": "active",
                "constraint_type": "equals",
                "value": true
            ]
        ]

        do {
            let constraintsData = try JSONSerialization.data(withJSONObject: constraints)
            let constraintsString = String(data: constraintsData, encoding: .utf8) ?? "[]"

            urlComponents?.queryItems = [
                URLQueryItem(name: "constraints", value: constraintsString),
                URLQueryItem(name: "sort_field", value: "Created Date"),
                URLQueryItem(name: "descending", value: "true"),
                URLQueryItem(name: "limit", value: "1")
            ]
        } catch {
            print("[APP_MESSAGE] Failed to encode constraints: \(error)")
            return nil
        }

        guard let url = urlComponents?.url else {
            print("[APP_MESSAGE] Failed to construct URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // No authorization needed - AppMessage is a public table
        request.timeoutInterval = 10 // Don't block app launch too long

        print("[APP_MESSAGE] Fetching active message from: \(url.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[APP_MESSAGE] Invalid response type")
                return nil
            }

            print("[APP_MESSAGE] Response status: \(httpResponse.statusCode)")

            // Print raw JSON for debugging
            if let rawJSON = String(data: data, encoding: .utf8) {
                print("[APP_MESSAGE] Raw JSON response:")
                print(rawJSON)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                print("[APP_MESSAGE] Non-success status code: \(httpResponse.statusCode)")
                return nil
            }

            let decoder = JSONDecoder()
            let messageResponse = try decoder.decode(AppMessageResponse.self, from: data)

            if let message = messageResponse.response.results.first {
                print("[APP_MESSAGE] Found active message: \(message.title ?? "No title")")
                print("[APP_MESSAGE]   - Type: \(message.messageType ?? "unknown")")
                print("[APP_MESSAGE]   - Dismissable: \(message.dismissable ?? true)")
                print("[APP_MESSAGE]   - Target users: \(message.targetUserTypes ?? [])")
                return message
            } else {
                print("[APP_MESSAGE] No active messages found")
                return nil
            }

        } catch {
            print("[APP_MESSAGE] Failed to fetch message: \(error)")
            return nil
        }
    }

    /// Checks if a message should be shown to the current user based on their role
    func shouldShowMessage(_ message: AppMessageDTO, forUserRole role: UserRole?) -> Bool {
        // If no target user types specified, show to all
        guard let targetTypes = message.targetUserTypes, !targetTypes.isEmpty else {
            return true
        }

        // If no user role (not logged in), show messages that target all or have no restrictions
        guard let role = role else {
            return targetTypes.isEmpty
        }

        // Map UserRole to the strings used in Bubble
        let roleString: String
        switch role {
        case .admin:
            roleString = "admin"
        case .officeCrew:
            roleString = "officeCrew"
        case .fieldCrew:
            roleString = "fieldCrew"
        }

        return targetTypes.contains(roleString)
    }
}
