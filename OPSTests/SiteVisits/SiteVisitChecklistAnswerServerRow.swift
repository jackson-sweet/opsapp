import Foundation
@testable import OPS

extension SiteVisitChecklistAnswerDTO {
    /// The row the server echoes for `answer` once the versioned write path has
    /// saved it: exactly the wire values `SiteVisitWriteModels.values` ships,
    /// plus the identity and audit columns only the server stamps. Tests read
    /// inbound answers through this so they exercise the live outbound wire,
    /// not a hand-typed row.
    static func serverRow(
        for answer: SiteVisitChecklistAnswer,
        writeRevision: Int64? = nil
    ) throws -> SiteVisitChecklistAnswerDTO {
        guard case .object(var row) = SiteVisitWriteModels.values(answer),
              let createdBy = answer.createdBy, !createdBy.isEmpty else {
            throw SiteVisitPayloadError.missingRequiredField("created_by")
        }
        row["opportunity_id"] = answer.opportunityId.map { .string($0.lowercased()) } ?? .null
        row["created_by"] = .string(createdBy.lowercased())
        row["created_at"] = .string(SupabaseDate.format(answer.createdAt))
        row["updated_at"] = .string(SupabaseDate.format(answer.updatedAt ?? answer.createdAt))
        if let writeRevision { row["write_revision"] = .number(Double(writeRevision)) }
        return try JSONDecoder().decode(
            SiteVisitChecklistAnswerDTO.self,
            from: JSONEncoder().encode(SiteVisitWriteJSON.object(row))
        )
    }
}
