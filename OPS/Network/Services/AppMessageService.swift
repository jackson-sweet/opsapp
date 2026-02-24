//
//  AppMessageService.swift
//  OPS
//
//  Service for fetching app messages from Supabase
//  Used to display update notices, maintenance alerts, and announcements on app launch
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
}

// MARK: - App Message Service

class AppMessageService {

    /// Fetches the active app message from Supabase
    /// Returns nil if no active message exists or if the fetch fails
    func fetchActiveMessage() async -> AppMessageDTO? {
        do {
            let response: [AppMessageDTO] = try await SupabaseService.shared.client
                .from("app_messages")
                .select()
                .eq("active", value: true)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            return response.first
        } catch {
            print("[APP_MESSAGE] Failed to fetch app messages: \(error.localizedDescription)")
            return nil
        }
    }

    /// Checks if a message should be shown to the current user based on their role
    func shouldShowMessage(_ message: AppMessageDTO, forUserRole role: UserRole?) -> Bool {
        guard let targetTypes = message.targetUserTypes, !targetTypes.isEmpty else {
            return true
        }

        guard let role = role else {
            return targetTypes.isEmpty
        }

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
