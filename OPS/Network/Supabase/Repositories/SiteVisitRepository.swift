//
//  SiteVisitRepository.swift
//  OPS
//
//  One tenant-scoped Supabase boundary for site-visit parents and packet rows.
//  Writes are single-attempt by design; the durable local SyncOperation queue
//  owns retry and dependency ordering.
//

import Foundation
import Supabase

enum SiteVisitRemoteTable: String, CaseIterable, Equatable {
    case visits = "site_visits"
    case artifacts = "site_visit_artifacts"
    case checklistAnswers = "site_visit_checklist_answers"
    case identityDrafts = "site_visit_identity_drafts"
}

enum SiteVisitRemoteRequest: Equatable {
    case fetch(
        table: SiteVisitRemoteTable,
        companyId: String,
        since: Date?,
        siteVisitId: String?
    )
    case upsert(table: SiteVisitRemoteTable, companyId: String, payload: Data)
    case update(table: SiteVisitRemoteTable, id: String, companyId: String, payload: Data)
    case softDelete(table: SiteVisitRemoteTable, id: String, companyId: String, deletedAt: Date)
    case complete(id: String, companyId: String, payload: Data)
}

protocol SiteVisitRemoteTransport: AnyObject {
    func send(_ request: SiteVisitRemoteRequest) async throws -> Data
}

enum SiteVisitRepositoryError: Error, Equatable {
    case authorization(String)
    case dependency(String)
    case schemaCapability(String)
    case transport(String)
    case malformedServerData(String)
    case companyMismatch(expected: String, received: String)
    case visitNotFound(String)

    static func classify(postgrestCode: String?, message: String) -> SiteVisitRepositoryError {
        let code = postgrestCode ?? ""
        if code == "42501" || code.hasPrefix("PGRST3")
            || message.contains("401") || message.localizedCaseInsensitiveContains("JWT") {
            return .authorization(message)
        }
        if code == "23503" || code == "23502" || code == "P0002" {
            return .dependency(message)
        }
        if code == "PGRST202" || code == "PGRST204" || code.hasPrefix("PGRST2")
            || code == "42P01" || code == "42703" || code == "42883" {
            return .schemaCapability(message)
        }
        return .transport(message)
    }

    static func wrapping(_ error: Error) -> SiteVisitRepositoryError {
        if let typed = error as? SiteVisitRepositoryError {
            return typed
        }
        if let decoding = error as? DecodingError {
            return .malformedServerData(String(describing: decoding))
        }
        if let postgrest = error as? PostgrestError {
            return classify(postgrestCode: postgrest.code, message: postgrest.message)
        }
        if let http = error as? HTTPError {
            let status = http.response.statusCode
            if status == 401 || status == 403 {
                return .authorization("HTTP \(status)")
            }
            if status == 404 {
                return .schemaCapability("HTTP 404")
            }
        }
        return .transport(error.localizedDescription)
    }
}

final class SiteVisitRepository {
    private let companyId: String
    private let transport: SiteVisitRemoteTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        companyId: String,
        transport: SiteVisitRemoteTransport
    ) {
        self.companyId = companyId.lowercased()
        self.transport = transport
    }

    @MainActor
    convenience init(companyId: String) {
        self.init(
            companyId: companyId,
            transport: SupabaseSiteVisitRemoteTransport(
                client: SupabaseService.shared.client
            )
        )
    }

    // MARK: - Reads

    func fetchAll(since: Date? = nil) async throws -> SiteVisitDeltaBundleDTO {
        do {
            let visits: [SiteVisitDTO] = try await fetch(.visits, since: since)
            let artifacts: [SiteVisitArtifactDTO] = try await fetch(.artifacts, since: since)
            let answers: [SiteVisitChecklistAnswerDTO] = try await fetch(.checklistAnswers, since: since)
            let drafts: [SiteVisitIdentityDraftDTO] = try await fetch(.identityDrafts, since: since)
            return SiteVisitDeltaBundleDTO(
                visits: visits,
                artifacts: artifacts,
                checklistAnswers: answers,
                identityDrafts: drafts
            )
        } catch {
            throw SiteVisitRepositoryError.wrapping(error)
        }
    }

    func fetchBundle(siteVisitId: String) async throws -> SiteVisitBundleDTO {
        let canonicalId = siteVisitId.lowercased()
        do {
            let visits: [SiteVisitDTO] = try await fetch(.visits, siteVisitId: canonicalId)
            guard let visit = visits.first else {
                throw SiteVisitRepositoryError.visitNotFound(canonicalId)
            }
            let artifacts: [SiteVisitArtifactDTO] = try await fetch(.artifacts, siteVisitId: canonicalId)
            let answers: [SiteVisitChecklistAnswerDTO] = try await fetch(.checklistAnswers, siteVisitId: canonicalId)
            let drafts: [SiteVisitIdentityDraftDTO] = try await fetch(.identityDrafts, siteVisitId: canonicalId)
            return SiteVisitBundleDTO(
                visit: visit,
                artifacts: artifacts,
                checklistAnswers: answers,
                identityDrafts: drafts
            )
        } catch {
            throw SiteVisitRepositoryError.wrapping(error)
        }
    }

    // MARK: - Parent writes

    @discardableResult
    func upsertVisit(_ payload: CreateSiteVisitDTO) async throws -> SiteVisitDTO {
        try requireCompany(payload.companyId)
        return try await sendAndDecode(
            .upsert(
                table: .visits,
                companyId: companyId,
                payload: try encoder.encode(payload)
            )
        )
    }

    @discardableResult
    func updateVisit(id: String, payload: SiteVisitUpdateDTO) async throws -> SiteVisitDTO {
        try await sendAndDecode(
            .update(
                table: .visits,
                id: id.lowercased(),
                companyId: companyId,
                payload: try encoder.encode(payload)
            )
        )
    }

    // MARK: - Child writes

    @discardableResult
    func upsertArtifact(_ payload: UpsertSiteVisitArtifactDTO) async throws -> SiteVisitArtifactDTO {
        try requireCompany(payload.companyId)
        return try await sendAndDecode(
            .upsert(
                table: .artifacts,
                companyId: companyId,
                payload: try encoder.encode(payload)
            )
        )
    }

    @discardableResult
    func upsertChecklistAnswer(
        _ payload: UpsertSiteVisitChecklistAnswerDTO
    ) async throws -> SiteVisitChecklistAnswerDTO {
        try requireCompany(payload.companyId)
        return try await sendAndDecode(
            .upsert(
                table: .checklistAnswers,
                companyId: companyId,
                payload: try encoder.encode(payload)
            )
        )
    }

    @discardableResult
    func upsertIdentityDraft(
        _ payload: UpsertSiteVisitIdentityDraftDTO
    ) async throws -> SiteVisitIdentityDraftDTO {
        try requireCompany(payload.companyId)
        return try await sendAndDecode(
            .upsert(
                table: .identityDrafts,
                companyId: companyId,
                payload: try encoder.encode(payload)
            )
        )
    }

    // MARK: - Lifecycle writes

    func softDelete(
        _ table: SiteVisitRemoteTable,
        id: String,
        at deletedAt: Date = Date()
    ) async throws {
        do {
            _ = try await transport.send(
                .softDelete(
                    table: table,
                    id: id.lowercased(),
                    companyId: companyId,
                    deletedAt: deletedAt
                )
            )
        } catch {
            throw SiteVisitRepositoryError.wrapping(error)
        }
    }

    func completeSiteVisit(
        _ id: String,
        completion: SiteVisitCompletionPayload
    ) async throws -> SiteVisitCompletionResponseDTO {
        do {
            return try await sendAndDecode(
                .complete(
                    id: id.lowercased(),
                    companyId: companyId,
                    payload: try encoder.encode(completion)
                )
            )
        } catch {
            throw SiteVisitRepositoryError.wrapping(error)
        }
    }

    // MARK: - Internals

    private func fetch<T: Decodable>(
        _ table: SiteVisitRemoteTable,
        since: Date? = nil,
        siteVisitId: String? = nil
    ) async throws -> [T] {
        let data = try await transport.send(
            .fetch(
                table: table,
                companyId: companyId,
                since: since,
                siteVisitId: siteVisitId
            )
        )
        return try decoder.decode([T].self, from: data)
    }

    private func sendAndDecode<T: Decodable>(_ request: SiteVisitRemoteRequest) async throws -> T {
        do {
            let data = try await transport.send(request)
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SiteVisitRepositoryError.wrapping(error)
        }
    }

    private func requireCompany(_ received: String) throws {
        let canonical = received.lowercased()
        guard canonical == companyId else {
            throw SiteVisitRepositoryError.companyMismatch(
                expected: companyId,
                received: canonical
            )
        }
    }
}

// MARK: - Live Supabase adapter

private final class SupabaseSiteVisitRemoteTransport: SiteVisitRemoteTransport {
    private let client: SupabaseClient
    private let decoder = JSONDecoder()

    init(client: SupabaseClient) {
        self.client = client
    }

    func send(_ request: SiteVisitRemoteRequest) async throws -> Data {
        switch request {
        case let .fetch(table, companyId, since, siteVisitId):
            return try await fetch(
                table: table,
                companyId: companyId,
                since: since,
                siteVisitId: siteVisitId
            )

        case let .upsert(table, _, payload):
            switch table {
            case .visits:
                return try await upsert(
                    try decoder.decode(CreateSiteVisitDTO.self, from: payload),
                    table: table.rawValue
                )
            case .artifacts:
                return try await upsert(
                    try decoder.decode(UpsertSiteVisitArtifactDTO.self, from: payload),
                    table: table.rawValue
                )
            case .checklistAnswers:
                return try await upsert(
                    try decoder.decode(UpsertSiteVisitChecklistAnswerDTO.self, from: payload),
                    table: table.rawValue
                )
            case .identityDrafts:
                return try await upsert(
                    try decoder.decode(UpsertSiteVisitIdentityDraftDTO.self, from: payload),
                    table: table.rawValue
                )
            }

        case let .update(table, id, companyId, payload):
            guard table == .visits else {
                throw SiteVisitRepositoryError.schemaCapability(
                    "Partial updates are supported only for site_visits"
                )
            }
            let update = try decoder.decode(SiteVisitUpdateDTO.self, from: payload)
            return try await client
                .from(table.rawValue)
                .update(update)
                .eq("id", value: id)
                .eq("company_id", value: companyId)
                .select()
                .single()
                .execute()
                .data

        case let .softDelete(table, id, companyId, deletedAt):
            let payload = SiteVisitSoftDeleteDTO(
                deletedAt: SupabaseDate.format(deletedAt)
            )
            return try await client
                .from(table.rawValue)
                .update(payload)
                .eq("id", value: id)
                .eq("company_id", value: companyId)
                .select()
                .execute()
                .data

        case let .complete(id, _, payload):
            let completion = try decoder.decode(SiteVisitCompletionPayload.self, from: payload)
            let params = CompleteSiteVisitRPCParams(
                p_site_visit_id: id,
                p_completion: completion
            )
            return try await client
                .rpc("complete_site_visit_guarded", params: params)
                .execute()
                .data
        }
    }

    private func fetch(
        table: SiteVisitRemoteTable,
        companyId: String,
        since: Date?,
        siteVisitId: String?
    ) async throws -> Data {
        var query = client
            .from(table.rawValue)
            .select()
            .eq("company_id", value: companyId)

        if let since {
            query = query.gte("updated_at", value: SupabaseDate.format(since))
        }
        if let siteVisitId {
            let idColumn = table == .visits ? "id" : "site_visit_id"
            query = query.eq(idColumn, value: siteVisitId)
        }

        return try await query
            .order("updated_at", ascending: true)
            .execute()
            .data
    }

    private func upsert<Payload: Encodable>(
        _ payload: Payload,
        table: String
    ) async throws -> Data {
        try await client
            .from(table)
            .upsert(payload, onConflict: "id")
            .select()
            .single()
            .execute()
            .data
    }
}

private struct SiteVisitSoftDeleteDTO: Codable {
    let deletedAt: String

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
    }
}
