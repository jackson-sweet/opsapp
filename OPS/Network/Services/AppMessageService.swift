//
//  AppMessageService.swift
//  OPS
//
//  Fetches app messages (force/optional update walls, maintenance notices,
//  announcements) shown on app launch.
//
//  IMPORTANT: this read is INTENTIONALLY anonymous. The shared Supabase client
//  (`SupabaseService.shared.client`) throws when no Firebase user is signed in
//  (it refuses to send anon-key requests to avoid RLS bypass during sign-out).
//  The Update Gate must work BEFORE login — a blocker bug can break sign-in
//  itself — so this hits PostgREST directly with the anon key. The
//  `app_messages` table has an anon SELECT policy and holds only broadcast
//  copy (no customer/company data). The request works in every auth state.
//

import Foundation

// MARK: - App Message DTO

struct AppMessageDTO: Codable, Identifiable {
    let id: String
    let active: Bool?
    let title: String?
    let body: String?
    let messageType: String?
    let dismissable: Bool?
    let targetUserTypes: [String]?
    let appStoreUrl: String?
    let createdAt: String?
    let minimumVersion: String?
    let maximumVersion: String?
    let platform: String?
    let startDate: String?
    let endDate: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case active
        case title
        case body
        case messageType = "message_type"
        case dismissable
        case targetUserTypes = "target_user_types"
        case appStoreUrl = "app_store_url"
        case createdAt = "created_at"
        case minimumVersion = "minimum_version"
        case maximumVersion = "maximum_version"
        case platform
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

// MARK: - Message Type Enum

enum AppMessageType: String {
    case mandatoryUpdate = "mandatory_update"
    case optionalUpdate = "optional_update"
    case maintenance = "maintenance"
    case announcement = "announcement"
    case info = "info"

    var iconName: String {
        switch self {
        case .mandatoryUpdate:
            return "exclamationmark.triangle"
        case .optionalUpdate:
            return "arrow.down.circle"
        case .maintenance:
            return "wrench"
        case .announcement:
            return "megaphone"
        case .info:
            return "info.circle"
        }
    }

    var displayName: String {
        switch self {
        case .mandatoryUpdate:
            return "Required Update"
        case .optionalUpdate:
            return "Update Available"
        case .maintenance:
            return "Maintenance"
        case .announcement:
            return "Announcement"
        case .info:
            return "Notice"
        }
    }

    /// Higher wins when more than one message applies to the same install.
    var priority: Int {
        switch self {
        case .mandatoryUpdate: return 4
        case .optionalUpdate: return 3
        case .maintenance: return 2
        case .announcement: return 1
        case .info: return 0
        }
    }
}

// MARK: - App Message Service

final class AppMessageService {

    /// Fetches all currently-active app messages. The Update Gate decides which
    /// (if any) actually applies to this install. Fails open (empty array) on
    /// any error so a backend outage can never block the app.
    func fetchActiveMessages() async -> [AppMessageDTO] {
        guard var components = URLComponents(
            url: SupabaseConfig.url.appendingPathComponent("rest/v1/app_messages"),
            resolvingAgainstBaseURL: false
        ) else {
            return []
        }
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "active", value: "eq.true"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "10")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return []
            }
            return (try? JSONDecoder().decode([AppMessageDTO].self, from: data)) ?? []
        } catch {
            print("[APP_MESSAGE] Anonymous fetch failed (fail-open): \(error.localizedDescription)")
            return []
        }
    }
}
