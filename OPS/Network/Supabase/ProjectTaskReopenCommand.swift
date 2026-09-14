import Foundation
import Supabase

enum ProjectTaskReopenError: Error, Equatable {
    case invalidCommand
    case companyMismatch
    case invalidReceipt
}

/// A persisted request, not an ordinary project field PATCH. Its timestamp is
/// the original wire string: Date round-tripping would discard CAS precision.
struct ProjectTaskReopenCommand: Equatable {
    let commandId: String
    let projectId: String
    let companyId: String
    let expectedUpdatedAt: String
    let targetStatus: String

    init(projectId: String, companyId: String, fields: [String: AnyJSON]) throws {
        guard Set(fields.keys) == ["status", "_reopen_command_id", "_expected_updated_at", "company_id"],
              case .string(let commandId) = fields["_reopen_command_id"],
              case .string(let expectedUpdatedAt) = fields["_expected_updated_at"],
              case .string(let targetStatus) = fields["status"],
              case .string(let payloadCompanyId) = fields["company_id"],
              UUID(uuidString: commandId) != nil,
              UUID(uuidString: projectId) != nil,
              UUID(uuidString: companyId) != nil,
              UUID(uuidString: payloadCompanyId) != nil,
              SupabaseDate.parse(expectedUpdatedAt) != nil,
              ["accepted", "in_progress"].contains(targetStatus) else {
            throw ProjectTaskReopenError.invalidCommand
        }
        guard payloadCompanyId.lowercased() == companyId.lowercased() else {
            throw ProjectTaskReopenError.companyMismatch
        }
        self.commandId = commandId.lowercased()
        self.projectId = projectId.lowercased()
        self.companyId = companyId.lowercased()
        self.expectedUpdatedAt = expectedUpdatedAt
        self.targetStatus = targetStatus
    }

    var rpcParameters: [String: AnyJSON] {
        ["p_command_id": .string(commandId), "p_project_id": .string(projectId),
         "p_expected_updated_at": .string(expectedUpdatedAt),
         "p_target_status": .string(targetStatus)]
    }

    func validateReceipt(_ response: Data) throws -> ProjectTaskReopenReceipt {
        guard let receipt = try? JSONDecoder().decode(ProjectTaskReopenReceipt.self, from: response),
              receipt.commandId.lowercased() == commandId,
              receipt.projectId.lowercased() == projectId,
              receipt.companyId.lowercased() == companyId,
              receipt.status == targetStatus, receipt.changed,
              SupabaseDate.parse(receipt.updatedAt) != nil else {
            throw ProjectTaskReopenError.invalidReceipt
        }
        return receipt
    }
}

/// Historical proof that this command committed. A replay can describe an old
/// successful reopen after the office archived the project again; consumers
/// settle the command and must not overwrite the current cached project state.
struct ProjectTaskReopenReceipt: Decodable, Equatable {
    let commandId: String
    let projectId: String
    let companyId: String
    let status: String
    let updatedAt: String
    let changed: Bool
    let replayed: Bool

    enum CodingKeys: String, CodingKey {
        case commandId = "command_id"
        case projectId = "project_id"
        case companyId = "company_id"
        case updatedAt = "updated_at"
        case status, changed, replayed
    }
}
