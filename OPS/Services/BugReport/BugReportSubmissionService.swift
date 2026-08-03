//
//  BugReportSubmissionService.swift
//  OPS
//
//  Accepts bug reports into a durable local outbox, then delivers them to Supabase.
//

import Foundation
import UIKit

// MARK: - Supabase Insert DTO

/// Fully Encodable DTO for Supabase insert.
/// Uses snake_case CodingKeys to match the `bug_reports` table columns.
struct BugReportInsertDTO: Encodable {
    let id: String
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
    let freeDiskMb: Int
    let freeRamMb: Int
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
        case id
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

/// Type-safe JSON values used by the bug_reports JSONB columns.
indirect enum JSONValue: Encodable, Equatable {
    case array([[String: JSONPrimitive]])
    case dictionary([String: JSONPrimitive])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let array):
            try container.encode(array)
        case .dictionary(let dictionary):
            try container.encode(dictionary)
        case .null:
            try container.encodeNil()
        }
    }
}

/// Codable JSON primitives retained in the durable report envelope.
indirect enum JSONPrimitive: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case nested([String: JSONPrimitive])
    case nestedArray([JSONPrimitive])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONPrimitive].self) {
            self = .nested(value)
        } else if let value = try? container.decode([JSONPrimitive].self) {
            self = .nestedArray(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value in bug report outbox"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .nested(let dictionary): try container.encode(dictionary)
        case .nestedArray(let array): try container.encode(array)
        }
    }
}

// MARK: - Submission Service

typealias BugReportOnlineSubmitter = @MainActor (
    _ dto: BugReportInsertDTO,
    _ screenshot: UIImage?,
    _ companyId: String
) async throws -> Void

@MainActor
final class BugReportSubmissionService {
    static let shared = BugReportSubmissionService(
        offlineQueue: BugReportOfflineQueue(),
        backgroundWorkEnabled: true,
        onlineSubmitter: { dto, screenshot, companyId in
            try await BugReportSubmissionService.submitOnline(
                dto: dto,
                screenshot: screenshot,
                companyId: companyId
            )
        }
    )

    private let offlineQueue: BugReportOfflineQueue
    private let backgroundWorkEnabled: Bool
    private let onlineSubmitter: BugReportOnlineSubmitter
    private var isDraining = false
    private var drainRequested = false

    init(
        offlineQueue: BugReportOfflineQueue,
        backgroundWorkEnabled: Bool,
        onlineSubmitter: @escaping BugReportOnlineSubmitter
    ) {
        self.offlineQueue = offlineQueue
        self.backgroundWorkEnabled = backgroundWorkEnabled
        self.onlineSubmitter = onlineSubmitter
    }

    // MARK: - Submit Report

    /// Captures a report, durably accepts it, and lets delivery continue independently.
    func submitReport(
        description: String,
        category: String,
        screenshot: UIImage?,
        appState: AppState,
        dataController: DataController
    ) async throws {
        let capture = BugReportCaptureService.shared
        let deviceInfo = capture.captureDeviceInfo()
        let stateSnapshot = capture.captureStateSnapshot(
            appState: appState,
            dataController: dataController
        )
        let consoleLogs = DebugLogger.shared.getLogSnapshot()
        let breadcrumbs = capture.getBreadcrumbSnapshot()
        let networkLog = capture.getNetworkLogSnapshot()

        let user = dataController.currentUser
        let companyId = user?.companyId ?? ""
        let reporterId = user?.id ?? ""
        let reporterName = user?.fullName ?? ""
        let reporterEmail = user?.email ?? ""

        let shouldAttemptSync = dataController.connectivity?.shouldAttemptSync ?? false
        let networkType: String
        if let connectivity = dataController.connectivity {
            if shouldAttemptSync {
                let quality = connectivity.state.quality
                networkType = quality == .excellent || quality == .good ? "wifi" : "cellular"
            } else {
                networkType = "none"
            }
        } else {
            networkType = deviceInfo["networkType"] as? String ?? "unknown"
        }

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
            freeDiskMb: Int((deviceInfo["freeDiskMb"] as? Double ?? -1).rounded()),
            freeRamMb: Int((deviceInfo["freeRamMb"] as? Double ?? -1).rounded()),
            consoleLogs: Self.convertToJSONArray(consoleLogs),
            breadcrumbs: Self.convertToJSONArray(breadcrumbs),
            networkLog: Self.convertToJSONArray(networkLog),
            stateSnapshot: Self.convertToJSONDict(stateSnapshot),
            reporterName: reporterName,
            reporterEmail: reporterEmail
        )

        try acceptReport(
            payload: payload,
            screenshot: screenshot,
            shouldAttemptSync: shouldAttemptSync
        )
    }

    /// The acceptance boundary is the successful local write, never the network response.
    func acceptReport(
        payload: BugReportPayload,
        screenshot: UIImage?,
        shouldAttemptSync: Bool
    ) throws {
        let queuedReport = try offlineQueue.enqueue(payload: payload, screenshot: screenshot)
        DebugLogger.shared.log(
            "Bug report saved for delivery: \(queuedReport.id)",
            level: .info,
            category: "BugReport"
        )

        guard shouldAttemptSync, backgroundWorkEnabled else { return }
        Task { @MainActor [weak self] in
            await self?.drainQueuedReports()
        }
    }

    // MARK: - Online Delivery

    /// Uses the client-generated UUID as the conflict key so a lost response can be retried safely.
    private static func submitOnline(
        dto: BugReportInsertDTO,
        screenshot: UIImage?,
        companyId: String
    ) async throws {
        try await SupabaseService.shared.client
            .from("bug_reports")
            .upsert(
                dto,
                onConflict: "id",
                returning: .minimal,
                ignoreDuplicates: true
            )
            .execute()

        DebugLogger.shared.log(
            "Bug report delivered: \(dto.id)",
            level: .info,
            category: "BugReport"
        )

        guard let screenshot else { return }
        do {
            try await PresignedURLUploadService.shared.uploadBugReportScreenshot(
                screenshot,
                reportId: dto.id,
                companyId: companyId
            )
            DebugLogger.shared.log(
                "Screenshot attached to report \(dto.id)",
                level: .info,
                category: "BugReport"
            )
        } catch {
            // Keep the outbox envelope and retry the same report ID until all evidence lands.
            DebugLogger.shared.log(
                "Screenshot upload failed for report \(dto.id): \(error.localizedDescription)",
                level: .warning,
                category: "BugReport"
            )
            throw error
        }
    }

    // MARK: - Drain Outbox

    /// Attempts delivery when the app knows network synchronization is viable.
    func drainOfflineQueue(dataController: DataController) async {
        guard dataController.connectivity?.shouldAttemptSync ?? false else { return }
        await drainQueuedReports()
    }

    /// Serially delivers the current durable outbox. Failed items remain for the next trigger.
    func drainQueuedReports() async {
        if isDraining {
            drainRequested = true
            return
        }

        isDraining = true
        defer {
            isDraining = false
            if drainRequested {
                drainRequested = false
                Task { @MainActor [weak self] in
                    await self?.drainQueuedReports()
                }
            }
        }

        let queued: [QueuedBugReport]
        do {
            queued = try offlineQueue.loadQueue()
        } catch {
            DebugLogger.shared.log(
                "Bug report outbox could not be read: \(error.localizedDescription)",
                level: .error,
                category: "BugReport"
            )
            return
        }

        guard !queued.isEmpty else { return }
        DebugLogger.shared.log(
            "Delivering \(queued.count) queued bug reports",
            level: .info,
            category: "BugReport"
        )

        for item in queued {
            do {
                let screenshot = try loadScreenshot(for: item)
                try await onlineSubmitter(
                    Self.makeDTO(id: item.id, payload: item.payload),
                    screenshot,
                    item.payload.companyId
                )
                try offlineQueue.remove(id: item.id)
                DebugLogger.shared.log(
                    "Removed delivered report from outbox: \(item.id)",
                    level: .info,
                    category: "BugReport"
                )
            } catch {
                DebugLogger.shared.log(
                    "Queued report retained after delivery failure \(item.id): \(error.localizedDescription)",
                    level: .error,
                    category: "BugReport"
                )
            }
        }
    }

    private func loadScreenshot(for item: QueuedBugReport) throws -> UIImage? {
        guard item.screenshotFilename != nil else { return nil }
        guard let url = offlineQueue.screenshotURL(for: item) else {
            throw BugReportError.failedToCreateReport
        }

        let data = try Data(contentsOf: url)
        guard let screenshot = UIImage(data: data) else {
            throw BugReportError.failedToCreateReport
        }
        return screenshot
    }

    private static func makeDTO(id: String, payload: BugReportPayload) -> BugReportInsertDTO {
        BugReportInsertDTO(
            id: id,
            companyId: payload.companyId,
            reporterId: payload.reporterId,
            description: payload.description,
            category: payload.category,
            platform: payload.platform,
            appVersion: payload.appVersion,
            buildNumber: payload.buildNumber,
            osName: payload.osName,
            osVersion: payload.osVersion,
            deviceModel: payload.deviceModel,
            screenName: payload.screenName,
            networkType: payload.networkType,
            batteryLevel: payload.batteryLevel,
            freeDiskMb: payload.freeDiskMb,
            freeRamMb: payload.freeRamMb,
            consoleLogs: .array(payload.consoleLogs ?? []),
            breadcrumbs: .array(payload.breadcrumbs ?? []),
            networkLog: .array(payload.networkLog ?? []),
            stateSnapshot: .dictionary(payload.stateSnapshot ?? [:]),
            customMetadata: .dictionary([:]),
            reporterName: payload.reporterName,
            reporterEmail: payload.reporterEmail,
            priority: "none",
            status: "new"
        )
    }

    // MARK: - JSON Conversion Helpers

    private static func convertToJSONArray(_ array: [[String: Any]]) -> [[String: JSONPrimitive]] {
        array.map { dictionary in
            dictionary.mapValues(convertToPrimitive)
        }
    }

    private static func convertToJSONDict(_ dictionary: [String: Any]) -> [String: JSONPrimitive] {
        dictionary.mapValues(convertToPrimitive)
    }

    private static func convertToPrimitive(_ value: Any) -> JSONPrimitive {
        // Check Bool before Int — NSNumber-backed booleans can also bridge to integers.
        if let value = value as? Bool { return .bool(value) }

        switch value {
        case let value as String: return .string(value)
        case let value as Int: return .int(value)
        case let value as Double: return .double(value)
        case let value as Float: return .double(Double(value))
        case let value as [String: Any]:
            return .nested(value.mapValues(convertToPrimitive))
        case let value as [Any]:
            return .nestedArray(value.map(convertToPrimitive))
        default:
            return .string(String(describing: value))
        }
    }
}

// MARK: - Bug Report Payload

struct BugReportPayload: Codable, Equatable {
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
    let freeDiskMb: Int
    let freeRamMb: Int
    let consoleLogs: [[String: JSONPrimitive]]?
    let breadcrumbs: [[String: JSONPrimitive]]?
    let networkLog: [[String: JSONPrimitive]]?
    let stateSnapshot: [String: JSONPrimitive]?
    let reporterName: String
    let reporterEmail: String

    init(
        companyId: String,
        reporterId: String,
        description: String,
        category: String,
        platform: String,
        appVersion: String,
        buildNumber: String,
        osName: String,
        osVersion: String,
        deviceModel: String,
        screenName: String,
        networkType: String,
        batteryLevel: Float,
        freeDiskMb: Int,
        freeRamMb: Int,
        consoleLogs: [[String: JSONPrimitive]]? = nil,
        breadcrumbs: [[String: JSONPrimitive]]? = nil,
        networkLog: [[String: JSONPrimitive]]? = nil,
        stateSnapshot: [String: JSONPrimitive]? = nil,
        reporterName: String,
        reporterEmail: String
    ) {
        self.companyId = companyId
        self.reporterId = reporterId
        self.description = description
        self.category = category
        self.platform = platform
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osName = osName
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.screenName = screenName
        self.networkType = networkType
        self.batteryLevel = batteryLevel
        self.freeDiskMb = freeDiskMb
        self.freeRamMb = freeRamMb
        self.consoleLogs = consoleLogs
        self.breadcrumbs = breadcrumbs
        self.networkLog = networkLog
        self.stateSnapshot = stateSnapshot
        self.reporterName = reporterName
        self.reporterEmail = reporterEmail
    }
}

// MARK: - Error

enum BugReportError: LocalizedError, Equatable {
    case failedToCreateReport
    case offlineQueueFull

    var errorDescription: String? {
        switch self {
        case .failedToCreateReport:
            return "Couldn’t save report. Try again."
        case .offlineQueueFull:
            return "Report queue is full. Connect, then try again."
        }
    }
}
