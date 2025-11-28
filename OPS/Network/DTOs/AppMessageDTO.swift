//
//  AppMessageDTO.swift
//  OPS
//
//  DTO for app messages fetched from Bubble
//  Used to display update notices, maintenance alerts, and announcements
//

import Foundation

struct AppMessageDTO: Codable, Identifiable {
    let id: String
    let active: Bool?
    let title: String?
    let body: String?
    let messageType: String?
    let dismissable: Bool?
    let targetUserTypes: [String]?
    let appStoreUrl: String?
    let createdDate: Date?

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case active
        case title
        case body
        case messageType
        case dismissable
        case targetUserTypes
        case appStoreUrl
        case createdDate = "Created Date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        messageType = try container.decodeIfPresent(String.self, forKey: .messageType)
        dismissable = try container.decodeIfPresent(Bool.self, forKey: .dismissable)
        targetUserTypes = try container.decodeIfPresent([String].self, forKey: .targetUserTypes)
        appStoreUrl = try container.decodeIfPresent(String.self, forKey: .appStoreUrl)

        // Parse date from ISO8601 string
        if let dateString = try container.decodeIfPresent(String.self, forKey: .createdDate) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            createdDate = formatter.date(from: dateString)
        } else {
            createdDate = nil
        }
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

// MARK: - Bubble Response Wrapper

struct AppMessageResponse: Codable {
    let response: AppMessageResponseData
}

struct AppMessageResponseData: Codable {
    let results: [AppMessageDTO]
    let remaining: Int?
    let count: Int?
}
