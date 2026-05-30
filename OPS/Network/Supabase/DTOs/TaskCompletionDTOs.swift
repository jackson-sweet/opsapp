//
//  TaskCompletionDTOs.swift
//  OPS
//
//  DTOs and sync helpers for server-authoritative task completion.
//

import Foundation
import Supabase

struct CompleteProjectTaskRPCParams: Encodable {
    let p_task_id: String
    let p_idempotency_key: String
    let p_material_adjustments: [String: AnyJSON]
}

struct CompleteProjectTaskResponseDTO: Codable {
    let ok: Bool
    let taskId: String
    let companyId: String?
    let inventoryMode: String?
    let consumptionPerformed: Bool
    let demandCount: Int?
    let allocationCount: Int?
    let stockUnitCount: Int?
    let unavailableAllocationCount: Int?
    let consumedQuantity: Double
    let overrunQuantity: Double
    let snapshotId: String?
    let inventoryDeductionIds: [String]
    let stockUnitEventIds: [String]
    let requestId: String
    let taskStatusChanged: Bool?
    let completedBy: String?
    let completedAt: String?
    let idempotentReplay: Bool?
    let taskConsumptionReplay: Bool?

    enum CodingKeys: String, CodingKey {
        case ok
        case taskId = "task_id"
        case companyId = "company_id"
        case inventoryMode = "inventory_mode"
        case consumptionPerformed = "consumption_performed"
        case demandCount = "demand_count"
        case allocationCount = "allocation_count"
        case stockUnitCount = "stock_unit_count"
        case unavailableAllocationCount = "unavailable_allocation_count"
        case consumedQuantity = "consumed_quantity"
        case overrunQuantity = "overrun_quantity"
        case snapshotId = "snapshot_id"
        case inventoryDeductionIds = "inventory_deduction_ids"
        case stockUnitEventIds = "stock_unit_event_ids"
        case requestId = "request_id"
        case taskStatusChanged = "task_status_changed"
        case completedBy = "completed_by"
        case completedAt = "completed_at"
        case idempotentReplay = "idempotent_replay"
        case taskConsumptionReplay = "task_consumption_replay"
    }

    init(
        ok: Bool,
        taskId: String,
        companyId: String?,
        inventoryMode: String?,
        consumptionPerformed: Bool,
        demandCount: Int?,
        allocationCount: Int?,
        stockUnitCount: Int?,
        unavailableAllocationCount: Int?,
        consumedQuantity: Double,
        overrunQuantity: Double,
        snapshotId: String?,
        inventoryDeductionIds: [String],
        stockUnitEventIds: [String],
        requestId: String,
        taskStatusChanged: Bool?,
        completedBy: String?,
        completedAt: String?,
        idempotentReplay: Bool?,
        taskConsumptionReplay: Bool?
    ) {
        self.ok = ok
        self.taskId = taskId
        self.companyId = companyId
        self.inventoryMode = inventoryMode
        self.consumptionPerformed = consumptionPerformed
        self.demandCount = demandCount
        self.allocationCount = allocationCount
        self.stockUnitCount = stockUnitCount
        self.unavailableAllocationCount = unavailableAllocationCount
        self.consumedQuantity = consumedQuantity
        self.overrunQuantity = overrunQuantity
        self.snapshotId = snapshotId
        self.inventoryDeductionIds = inventoryDeductionIds
        self.stockUnitEventIds = stockUnitEventIds
        self.requestId = requestId
        self.taskStatusChanged = taskStatusChanged
        self.completedBy = completedBy
        self.completedAt = completedAt
        self.idempotentReplay = idempotentReplay
        self.taskConsumptionReplay = taskConsumptionReplay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        taskId = try container.decode(String.self, forKey: .taskId)
        companyId = try container.decodeIfPresent(String.self, forKey: .companyId)
        inventoryMode = try container.decodeIfPresent(String.self, forKey: .inventoryMode)
        consumptionPerformed = try container.decodeIfPresent(Bool.self, forKey: .consumptionPerformed) ?? false
        demandCount = try container.decodeIfPresent(Int.self, forKey: .demandCount)
        allocationCount = try container.decodeIfPresent(Int.self, forKey: .allocationCount)
        stockUnitCount = try container.decodeIfPresent(Int.self, forKey: .stockUnitCount)
        unavailableAllocationCount = try container.decodeIfPresent(Int.self, forKey: .unavailableAllocationCount)
        consumedQuantity = try container.decodeIfPresent(Double.self, forKey: .consumedQuantity) ?? 0
        overrunQuantity = try container.decodeIfPresent(Double.self, forKey: .overrunQuantity) ?? 0
        snapshotId = try container.decodeIfPresent(String.self, forKey: .snapshotId)
        inventoryDeductionIds = try container.decodeIfPresent([String].self, forKey: .inventoryDeductionIds) ?? []
        stockUnitEventIds = try container.decodeIfPresent([String].self, forKey: .stockUnitEventIds) ?? []
        requestId = try container.decode(String.self, forKey: .requestId)
        taskStatusChanged = try container.decodeIfPresent(Bool.self, forKey: .taskStatusChanged)
        completedBy = try container.decodeIfPresent(String.self, forKey: .completedBy)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        idempotentReplay = try container.decodeIfPresent(Bool.self, forKey: .idempotentReplay)
        taskConsumptionReplay = try container.decodeIfPresent(Bool.self, forKey: .taskConsumptionReplay)
    }
}

enum TaskCompletionSync {
    static let idempotencyKeyPayloadKey = "complete_project_task_idempotency_key"
    static let materialAdjustmentsPayloadKey = "material_adjustments"

    static func stableCompletionIdempotencyKey(taskId: String) -> String {
        "ios:complete_project_task:\(taskId.lowercased())"
    }

    static func isCompletionPayload(_ payload: [String: Any]) -> Bool {
        statusString(from: payload["status"]) == TaskStatus.completed.rawValue
    }

    static func isCompletionStatus(_ value: AnyJSON?) -> Bool {
        guard case let .string(status)? = value else { return false }
        return status == TaskStatus.completed.rawValue
    }

    static func idempotencyKey(from payload: [String: Any], taskId: String) -> String {
        if let stored = payload[idempotencyKeyPayloadKey] as? String {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return stableCompletionIdempotencyKey(taskId: taskId)
    }

    static func materialAdjustments(from payload: [String: Any]) -> [String: AnyJSON] {
        guard let raw = payload[materialAdjustmentsPayloadKey] else { return [:] }
        guard let object = raw as? [String: Any] else { return [:] }
        return object.mapValues { anyJSON(from: $0) }
    }

    private static func statusString(from value: Any?) -> String? {
        if let status = value as? String {
            return status
        }
        if let anyJSON = value as? AnyJSON {
            if case let .string(status) = anyJSON {
                return status
            }
        }
        return nil
    }

    private static func anyJSON(from value: Any) -> AnyJSON {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .integer(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map { anyJSON(from: $0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { anyJSON(from: $0) })
        case is NSNull:
            return .null
        default:
            return .string("\(value)")
        }
    }
}

extension SupabaseProjectTaskDTO {
    func replacingStatus(_ status: String) -> SupabaseProjectTaskDTO {
        SupabaseProjectTaskDTO(
            id: id,
            bubbleId: bubbleId,
            companyId: companyId,
            projectId: projectId,
            taskTypeId: taskTypeId,
            customTitle: customTitle,
            taskNotes: taskNotes,
            status: status,
            taskColor: taskColor,
            displayOrder: displayOrder,
            teamMemberIds: teamMemberIds,
            sourceLineItemId: sourceLineItemId,
            sourceEstimateId: sourceEstimateId,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            dependencyOverrides: dependencyOverrides,
            startTime: startTime,
            endTime: endTime,
            pairedFromTaskId: pairedFromTaskId,
            scheduleLocked: scheduleLocked,
            deletedAt: deletedAt,
            createdAt: createdAt
        )
    }
}
