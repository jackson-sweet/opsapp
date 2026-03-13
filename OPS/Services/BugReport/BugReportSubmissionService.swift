//
//  BugReportSubmissionService.swift
//  OPS
//
//  Submits bug reports to Supabase and uploads screenshots to S3.
//  Handles offline queueing for submissions when connectivity is unavailable.
//

import UIKit
import Foundation

// MARK: - Supabase Insert DTO

/// Fully Encodable DTO for Supabase insert.
/// Uses snake_case CodingKeys to match the `bug_reports` table columns.
/// JSONB fields are encoded as JSON strings for Supabase compatibility.
struct BugReportInsertDTO: Encodable {
    let companyId: String
    let reporterId: String
    let description: String
    let category: String
    let platform: String
    let appVersion: String
    let buildNumber: String
    let osName: String
    let osVersion: String
    let deviceModel: String
    let screenName: String
    let networkType: String
    let batteryLevel: Float
    let freeDiskMb: Double
    let freeRamMb: Double
    let consoleLogs: JSONValue
    let breadcrumbs: JSONValue
    let networkLog: JSONValue
    let stateSnapshot: JSONValue
    let customMetadata: JSONValue
    let reporterName: String
    let reporterEmail: String
    let priority: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case reporterId = "reporter_id"
        case description
        case category
        case platform
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case osName = "os_name"
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case screenName = "screen_name"
        case networkType = "network_type"
        case batteryLevel = "battery_level"
        case freeDiskMb = "free_disk_mb"
        case freeRamMb = "free_ram_mb"
        case consoleLogs = "console_logs"
        case breadcrumbs
        case networkLog = "network_log"
        case stateSnapshot = "state_snapshot"
        case customMetadata = "custom_metadata"
        case reporterName = "reporter_name"
        case reporterEmail = "reporter_email"
        case priority
        case status
    }
}

/// Type-erased JSON value that can encode any JSON-compatible value
indirect enum JSONValue: Encodable {
    case array([[String: JSONPrimitive]])
    case dictionary([String: JSONPrimitive])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let arr):
            try container.encode(arr)
        case .dictionary(let dict):
            try container.encode(dict)
        case .null:
            try container.encodeNil()
        }
    }
}

/// Primitive JSON values for JSONB encoding — supports nested structures
indirect enum JSONPrimitive: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case nested([String: JSONPrimitive])
    case nestedArray([JSONPrimitive])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .nested(let dict): try container.encode(dict)
        case .nestedArray(let arr): try container.encode(arr)
        }
    }
}

/// Response from Supabase insert with select("id")
private struct BugReportInsertResponse: Decodable {
    let id: String
}

// MARK: - Submission Service

@MainActor
final class BugReportSubmissionService {
    static let shared = BugReportSubmissionService()

    private let offlineQueue = BugReportOfflineQueue()
    private var isDraining = false

    private init() {}

    // MARK: - Submit Report

    /// Submit a bug report. If offline, queues for later submission.
    func submitReport(
        description: String,
        category: String,
        screenshot: UIImage?,
        appState: AppState,
        dataController: DataController
    ) async throws {
        let capture = BugReportCaptureService.shared

        // Gather all context
        let deviceInfo = capture.captureDeviceInfo()
        let stateSnapshot = capture.captureStateSnapshot(appState: appState, dataController: dataController)
        let consoleLogs = DebugLogger.shared.getLogSnapshot()
        let breadcrumbs = capture.getBreadcrumbSnapshot()
        let networkLog = capture.getNetworkLogSnapshot()

        // User info
        let user = dataController.currentUser
        let companyId = user?.companyId ?? ""
        let reporterId = user?.id ?? ""
        let reporterName = user?.fullName ?? ""
        let reporterEmail = user?.email ?? ""

        // Network type from ConnectivityManager
        let networkType: String
        if let connectivity = dataController.connectivity {
            if connectivity.shouldAttemptSync {
                let quality = connectivity.state.quality
                networkType = quality == .excellent || quality == .good ? "wifi" : "cellular"
            } else {
                networkType = "none"
            }
        } else {
            networkType = deviceInfo["networkType"] as? String ?? "unknown"
        }

        // Build payload for offline queue persistence
        let payload = BugReportPayload(
            companyId: companyId,
            reporterId: reporterId,
            description: description,
            category: category,
            platform: "ios",
            appVersion: deviceInfo["appVersion"] as? String ?? "",
            buildNumber: deviceInfo["buildNumber"] as? String ?? "",
            osName: "iOS",
            osVersion: deviceInfo["osVersion"] as? String ?? "",
            deviceModel: deviceInfo["deviceModel"] as? String ?? "",
            screenName: capture.currentScreenName,
            networkType: networkType,
            batteryLevel: deviceInfo["batteryLevel"] as? Float ?? -1,
            freeDiskMb: deviceInfo["freeDiskMb"] as? Double ?? -1,
            freeRamMb: deviceInfo["freeRamMb"] as? Double ?? -1,
            reporterName: reporterName,
            reporterEmail: reporterEmail
        )

        // Build Supabase DTO with JSONB fields
        let dto = BugReportInsertDTO(
            companyId: companyId,
            reporterId: reporterId,
            description: description,
            category: category,
            platform: "ios",
            appVersion: payload.appVersion,
            buildNumber: payload.buildNumber,
            osName: "iOS",
            osVersion: payload.osVersion,
            deviceModel: payload.deviceModel,
            screenName: payload.screenName,
            networkType: networkType,
            batteryLevel: payload.batteryLevel,
            freeDiskMb: payload.freeDiskMb,
            freeRamMb: payload.freeRamMb,
            consoleLogs: Self.convertToJSONArray(consoleLogs),
            breadcrumbs: Self.convertToJSONArray(breadcrumbs),
            networkLog: Self.convertToJSONArray(networkLog),
            stateSnapshot: Self.convertToJSONDict(stateSnapshot),
            customMetadata: .dictionary([:]),
            reporterName: reporterName,
            reporterEmail: reporterEmail,
            priority: "none",
            status: "new"
        )

        // Check connectivity
        let isOnline = dataController.connectivity?.shouldAttemptSync ?? false

        if isOnline {
            try await submitOnline(dto: dto, screenshot: screenshot, companyId: companyId)
        } else {
            try offlineQueue.enqueue(payload: payload, screenshot: screenshot)
            DebugLogger.shared.log("Bug report queued for offline submission", level: .info, category: "BugReport")
        }
    }

    // MARK: - Online Submission

    private func submitOnline(dto: BugReportInsertDTO, screenshot: UIImage?, companyId: String) async throws {
        let supabase = SupabaseService.shared.client

        // 1. Insert the bug report row
        let response: BugReportInsertResponse = try await supabase
            .from("bug_reports")
            .insert(dto)
            .select("id")
            .single()
            .execute()
            .value

        let reportId = response.id

        DebugLogger.shared.log("Bug report created: \(reportId)", level: .info, category: "BugReport")

        // 2. Upload screenshot to S3
        if let screenshot = screenshot {
            do {
                let screenshotUrl = try await S3UploadService.shared.uploadBugReportScreenshot(
                    screenshot,
                    reportId: reportId,
                    companyId: companyId
                )

                // 3. Update the row with screenshot URL
                struct ScreenshotUpdate: Encodable {
                    let screenshotUrl: String
                    enum CodingKeys: String, CodingKey {
                        case screenshotUrl = "screenshot_url"
                    }
                }

                try await supabase
                    .from("bug_reports")
                    .update(ScreenshotUpdate(screenshotUrl: screenshotUrl))
                    .eq("id", value: reportId)
                    .execute()

                DebugLogger.shared.log("Screenshot attached to report \(reportId)", level: .info, category: "BugReport")
            } catch {
                // Report was created, screenshot failed — log but don't fail the whole submission
                DebugLogger.shared.log("Screenshot upload failed for report \(reportId): \(error.localizedDescription)", level: .warning, category: "BugReport")
            }
        }
    }

    // MARK: - Drain Offline Queue

    /// Attempt to submit any queued offline reports. Call when connectivity returns.
    func drainOfflineQueue(dataController: DataController) async {
        guard !isDraining else { return }
        guard dataController.connectivity?.shouldAttemptSync ?? false else { return }

        let queued = offlineQueue.loadQueue()
        guard !queued.isEmpty else { return }

        isDraining = true
        defer { isDraining = false }

        DebugLogger.shared.log("Draining \(queued.count) queued bug reports", level: .info, category: "BugReport")

        for item in queued {
            do {
                // Load screenshot from file using relative filename
                var screenshot: UIImage?
                if let url = offlineQueue.screenshotURL(for: item),
                   let data = try? Data(contentsOf: url) {
                    screenshot = UIImage(data: data)
                }

                // Rebuild DTO from payload (offline reports have no diagnostic context)
                let dto = BugReportInsertDTO(
                    companyId: item.payload.companyId,
                    reporterId: item.payload.reporterId,
                    description: item.payload.description,
                    category: item.payload.category,
                    platform: item.payload.platform,
                    appVersion: item.payload.appVersion,
                    buildNumber: item.payload.buildNumber,
                    osName: item.payload.osName,
                    osVersion: item.payload.osVersion,
                    deviceModel: item.payload.deviceModel,
                    screenName: item.payload.screenName,
                    networkType: item.payload.networkType,
                    batteryLevel: item.payload.batteryLevel,
                    freeDiskMb: item.payload.freeDiskMb,
                    freeRamMb: item.payload.freeRamMb,
                    consoleLogs: .array([]),
                    breadcrumbs: .array([]),
                    networkLog: .array([]),
                    stateSnapshot: .dictionary([:]),
                    customMetadata: .dictionary([:]),
                    reporterName: item.payload.reporterName,
                    reporterEmail: item.payload.reporterEmail,
                    priority: "none",
                    status: "new"
                )

                try await submitOnline(
                    dto: dto,
                    screenshot: screenshot,
                    companyId: item.payload.companyId
                )

                offlineQueue.remove(id: item.id)
                DebugLogger.shared.log("Submitted queued report \(item.id)", level: .info, category: "BugReport")
            } catch {
                DebugLogger.shared.log("Failed to submit queued report \(item.id): \(error.localizedDescription)", level: .error, category: "BugReport")
            }
        }
    }

    // MARK: - JSON Conversion Helpers

    /// Convert [[String: Any]] to JSONValue.array for Encodable compatibility
    private static func convertToJSONArray(_ array: [[String: Any]]) -> JSONValue {
        let converted: [[String: JSONPrimitive]] = array.map { dict in
            var result: [String: JSONPrimitive] = [:]
            for (key, value) in dict {
                result[key] = convertToPrimitive(value)
            }
            return result
        }
        return .array(converted)
    }

    /// Convert [String: Any] to JSONValue.dictionary
    private static func convertToJSONDict(_ dict: [String: Any]) -> JSONValue {
        var result: [String: JSONPrimitive] = [:]
        for (key, value) in dict {
            result[key] = convertToPrimitive(value)
        }
        return .dictionary(result)
    }

    private static func convertToPrimitive(_ value: Any) -> JSONPrimitive {
        // Check Bool before Int — NSNumber-backed bools match `as Int` first
        if let b = value as? Bool { return .bool(b) }
        switch value {
        case let s as String: return .string(s)
        case let i as Int: return .int(i)
        case let d as Double: return .double(d)
        case let f as Float: return .double(Double(f))
        case let dict as [String: Any]:
            var result: [String: JSONPrimitive] = [:]
            for (k, v) in dict { result[k] = convertToPrimitive(v) }
            return .nested(result)
        case let arr as [Any]:
            return .nestedArray(arr.map { convertToPrimitive($0) })
        default: return .string(String(describing: value))
        }
    }
}

// MARK: - Bug Report Payload (for offline queue persistence)

struct BugReportPayload: Codable {
    let companyId: String
    let reporterId: String
    let description: String
    let category: String
    let platform: String
    let appVersion: String
    let buildNumber: String
    let osName: String
    let osVersion: String
    let deviceModel: String
    let screenName: String
    let networkType: String
    let batteryLevel: Float
    let freeDiskMb: Double
    let freeRamMb: Double
    let reporterName: String
    let reporterEmail: String
}

// MARK: - Error

enum BugReportError: LocalizedError {
    case failedToCreateReport
    case offlineQueueFull

    var errorDescription: String? {
        switch self {
        case .failedToCreateReport:
            return "Failed to create bug report"
        case .offlineQueueFull:
            return "Offline queue is full (max 10 reports)"
        }
    }
}
