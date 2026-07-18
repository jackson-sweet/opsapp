//
//  LeadDetailViewModel.swift
//  OPS
//
//  Loads everything the lead dossier renders beyond the Opportunity row
//  itself: activities, follow-ups, stage transitions, the client roster
//  (client + sub_clients for the ON FILE state), lead files (attributed
//  email attachments + estimates), and the latest correspondence subject
//  (CONTACT sheet email compose). Every load fails soft — a lost fetch
//  degrades one section, never the screen.
//

import SwiftUI

/// One FILES row — an email attachment the pipeline attributed to this lead.
/// `stored` rows stream through the authenticated ops-web proxy; `external`
/// rows open their source URL.
struct LeadAttachment: Decodable, Identifiable, Equatable {
    let id: String
    let filename: String?
    let mimeType: String?
    let storagePath: String?
    let sourceUrl: String?
    let fromEmail: String?
    let ingestStatus: String
    let occurredAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, filename
        case mimeType     = "mime_type"
        case storagePath  = "storage_path"
        case sourceUrl    = "source_url"
        case fromEmail    = "from_email"
        case ingestStatus = "ingest_status"
        case occurredAt   = "occurred_at"
        case createdAt    = "created_at"
    }

    var displayName: String {
        let trimmed = filename?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? "attachment" : trimmed
    }

    var date: Date? {
        SupabaseDate.parse(occurredAt ?? createdAt)
    }
}

/// Where the lead's person stands against the client roster (spec §5.9).
enum LeadContactRosterState: Equatable {
    case mirrorsClient   // the contact IS the client — no roster line
    case onFile          // matched a sub_clients row (email first, then name)
    case notOnFile       // client exists, contact unmatched — offer ADD TO CLIENT
    case noClient        // lead has no client link
}

@MainActor
class LeadDetailViewModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var followUps: [FollowUp] = []
    @Published var stageTransitions: [StageTransition] = []
    @Published var client: Client?
    @Published var subClients: [SubClient] = []
    @Published var attachments: [LeadAttachment] = []
    @Published var estimates: [Estimate] = []
    @Published var latestThreadSubject: String?
    @Published var isLoading = false
    @Published var loadError: String? = nil

    private let opportunityId: String
    private let companyId: String
    private let clientId: String?
    private let repository: OpportunityRepository
    private let activityRepository: ActivityRepository

    init(opportunityId: String, companyId: String, clientId: String? = nil) {
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.clientId = clientId
        self.repository = OpportunityRepository(companyId: companyId)
        self.activityRepository = ActivityRepository(companyId: companyId)
    }

    func loadAll() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        async let actsTask: () = loadActivities()
        async let fusTask: () = loadFollowUps()
        async let stsTask: () = loadStageTransitions()
        async let rosterTask: () = loadClientRoster()
        async let filesTask: () = loadAttachments()
        async let estTask: () = loadEstimates()
        async let subjTask: () = loadThreadSubject()
        _ = await (actsTask, fusTask, stsTask, rosterTask, filesTask, estTask, subjTask)
    }

    private func loadActivities() async {
        do {
            let dtos = try await repository.fetchActivities(for: opportunityId)
            activities = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] activities failed: \(error)") }
    }

    private func loadFollowUps() async {
        do {
            let dtos = try await repository.fetchFollowUps(for: opportunityId)
            followUps = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] follow-ups failed: \(error)") }
    }

    private func loadStageTransitions() async {
        do {
            let dtos = try await repository.fetchStageTransitions(for: opportunityId)
            stageTransitions = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] transitions failed: \(error)") }
    }

    private func loadClientRoster() async {
        guard let clientId, !clientId.isEmpty else { return }
        let repo = ClientRepository(companyId: companyId)
        do {
            let dto = try await repo.fetchOne(clientId)
            client = Self.mapClient(dto)
        } catch { print("[LeadDetail] client failed: \(error)") }
        do {
            let dtos = try await repo.fetchSubClients(for: clientId)
            subClients = dtos.map(Self.mapSubClient)
        } catch { print("[LeadDetail] sub-clients failed: \(error)") }
    }

    private func loadAttachments() async {
        do {
            attachments = try await repository.fetchEmailAttachments(for: opportunityId)
        } catch { print("[LeadDetail] attachments failed: \(error)") }
    }

    private func loadEstimates() async {
        do {
            let dtos = try await EstimateRepository(companyId: companyId)
                .fetchForOpportunity(opportunityId)
            estimates = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] estimates failed: \(error)") }
    }

    private func loadThreadSubject() async {
        do {
            latestThreadSubject = try await repository
                .latestCorrespondenceSubject(for: opportunityId)
        } catch { print("[LeadDetail] thread subject failed: \(error)") }
    }

    // MARK: - Roster state (pure — mirrors web DealContactRow rules)

    /// Where the lead's person stands against the roster. Mirrors the web's
    /// normalization exactly: mirrors-client by name OR email OR phone; on
    /// file when a live sub_clients row matches by email first, then name.
    nonisolated static func rosterState(
        contactName: String?, contactEmail: String?, contactPhone: String?,
        client: Client?, subClients: [SubClient]
    ) -> LeadContactRosterState {
        guard let client else { return .noClient }
        func norm(_ s: String?) -> String {
            (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        func normPhone(_ s: String?) -> String { (s ?? "").filter(\.isNumber) }
        let mirrors = norm(contactName) == norm(client.name)
            || (!norm(contactEmail).isEmpty && norm(contactEmail) == norm(client.email))
            || (!normPhone(contactPhone).isEmpty && normPhone(contactPhone) == normPhone(client.phoneNumber))
        if mirrors { return .mirrorsClient }
        let onFile = subClients.contains { sc in
            guard sc.deletedAt == nil else { return false }
            if !norm(contactEmail).isEmpty, norm(sc.email) == norm(contactEmail) { return true }
            return !norm(contactName).isEmpty && norm(sc.name) == norm(contactName)
        }
        return onFile ? .onFile : .notOnFile
    }

    /// ADD TO CLIENT — files the lead's person as a sub_client on the linked
    /// client (the same write path SubClientEditSheet uses).
    func addContactToClient(name: String, email: String?, phone: String?) async throws {
        guard let clientId, !clientId.isEmpty else { return }
        let dto = try await ClientRepository(companyId: companyId).createSubClient(
            clientId: clientId,
            name: name,
            title: nil,
            email: email,
            phone: phone,
            address: nil
        )
        subClients.append(Self.mapSubClient(dto))
    }

    // MARK: - DTO → detached model mapping (display-only, never inserted)

    nonisolated private static func mapClient(_ dto: SupabaseClientDTO) -> Client {
        Client(
            id: dto.id,
            name: dto.name,
            email: dto.email,
            phoneNumber: dto.phoneNumber,
            address: dto.address,
            companyId: dto.companyId,
            notes: dto.notes
        )
    }

    nonisolated private static func mapSubClient(_ dto: SupabaseSubClientDTO) -> SubClient {
        let s = SubClient(
            id: dto.id,
            name: dto.name,
            title: dto.title,
            email: dto.email,
            phoneNumber: dto.phoneNumber,
            address: dto.address
        )
        s.deletedAt = dto.deletedAt.flatMap { SupabaseDate.parse($0) }
        return s
    }

    // MARK: - Activity logging

    /// `createdBy` MUST be the operator's Supabase `users.id`
    /// (`dataController.currentUser?.id`) — never the Firebase UID. Routed
    /// through `ActivityRepository` (the unified activity write path) rather
    /// than `OpportunityRepository.logActivity`.
    func logActivity(type: ActivityType, subject: String?, body: String?, direction: String? = nil, outcome: String? = nil, durationMinutes: Int? = nil, callSource: String? = nil, callerNumber: String? = nil, callStartedAt: Date? = nil, createdBy: String?) async throws {
        let resultDTO = try await activityRepository.logActivity(
            target: .opportunity(makeOpportunityStub()),
            type: type,
            subject: subject,
            body: body,
            direction: direction,
            outcome: outcome,
            durationMinutes: durationMinutes,
            callSource: callSource,
            callerNumber: callerNumber,
            callStartedAt: callStartedAt,
            createdBy: createdBy
        )
        activities.insert(resultDTO.toModel(), at: 0)
    }

    /// `ActivityTarget.opportunity` carries the full model (its `parentKey`
    /// only reads `.id`, but the enum case requires an `Opportunity`). This
    /// view model only ever holds `opportunityId`/`companyId` strings, so a
    /// minimal stub is built at the call boundary rather than widening the
    /// view model's stored state.
    private func makeOpportunityStub() -> Opportunity {
        Opportunity(id: opportunityId, companyId: companyId, contactName: "", stage: .newLead)
    }

    func addFollowUp(title: String, description: String?, type: FollowUpType, dueAt: Date, reminderAt: Date?, assignedTo: String?) async throws {
        let dto = CreateFollowUpDTO(
            companyId: companyId,
            opportunityId: opportunityId,
            title: title,
            description: description,
            type: type.rawValue,
            dueAt: SupabaseDate.format(dueAt),
            reminderAt: reminderAt.map { SupabaseDate.format($0) },
            assignedTo: assignedTo
        )
        let resultDTO = try await repository.createFollowUp(dto)
        followUps.append(resultDTO.toModel())
        followUps.sort { $0.dueAt < $1.dueAt }
    }
}
