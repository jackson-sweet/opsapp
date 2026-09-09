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
struct LeadAttachment: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let filename: String?
    let mimeType: String?
    let sourceUrl: String?
    let fromEmail: String?
    let ingestStatus: String
    let occurredAt: String?
    let createdAt: String

    // NOTE: no storage_path — the sanctioned RPC deliberately withholds it
    // (private bucket key); `stored` rows stream via the ops-web proxy by id.
    enum CodingKeys: String, CodingKey {
        case id, filename
        case mimeType     = "mime_type"
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

/// The lead's latest MEANINGFUL correspondence, either party — the LAST WORD
/// row on the lead document. Direction is the ledger's raw value
/// ("inbound"/"outbound").
struct LeadCorrespondence: Equatable {
    let subject: String?
    let direction: String
    let occurredAt: Date
    let source: String?

    var isInbound: Bool { direction.lowercased() == "inbound" }
}

/// Where the lead's person stands against the client roster (spec §5.9).
enum LeadContactRosterState: Equatable {
    case mirrorsClient   // the contact IS the client — no roster line
    case onFile          // matched a sub_clients row (email first, then name)
    case notOnFile       // client exists, contact unmatched — offer ADD TO CLIENT
    case noClient        // lead has no client link
}

/// A lead's client link, read the same way everywhere.
///
/// `opportunities.client_id` arrives as an optional string that is sometimes
/// an empty one, so "has a client" is a rule rather than a nil check — and it
/// has to be the SAME rule in the view model that loads the roster and in the
/// row that decides whether to show a client or invite one (bug 908888f6).
enum LeadClientLink {
    /// The link, or nil when there is none. Empty and whitespace-only are none.
    static func normalised(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True when the lead is linked to a client, whatever that client's row
    /// has loaded yet.
    static func isLinked(_ raw: String?) -> Bool { normalised(raw) != nil }
}

/// How the dossier fetches the linked client and its people.
///
/// Injected so the reload rule — *the roster follows the lead's CURRENT link* —
/// is assertable without a network. Production hands in `ClientRepository`.
struct LeadClientRosterLoader {
    var client: @MainActor (String) async throws -> Client
    var subClients: @MainActor (String) async throws -> [SubClient]
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
    @Published var latestCorrespondence: LeadCorrespondence?
    @Published var isLoading = false
    @Published var loadError: String? = nil

    private let opportunityId: String
    private let companyId: String
    /// The client link the roster currently reflects. NOT a snapshot of the
    /// link the screen opened with: a lead gains its first client while the
    /// dossier is open (the CLIENT row's picker writes it), and a roster frozen
    /// at open time is what made an assignment that DID land read as a
    /// failure — the row fell back to its ASSIGN CLIENT invitation over a
    /// client that was already saved (bug 908888f6).
    private var clientId: String?
    private let repository: OpportunityRepository
    private let activityRepository: ActivityRepository
    private let rosterLoader: LeadClientRosterLoader

    init(
        opportunityId: String,
        companyId: String,
        clientId: String? = nil,
        rosterLoader: LeadClientRosterLoader? = nil
    ) {
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.clientId = LeadClientLink.normalised(clientId)
        self.repository = OpportunityRepository(companyId: companyId)
        self.activityRepository = ActivityRepository(companyId: companyId)
        self.rosterLoader = rosterLoader ?? Self.liveRosterLoader(companyId: companyId)
    }

    /// Production roster fetch — the two `ClientRepository` reads the dossier
    /// has always made, behind the seam.
    static func liveRosterLoader(companyId: String) -> LeadClientRosterLoader {
        let repo = ClientRepository(companyId: companyId)
        return LeadClientRosterLoader(
            client: { id in Self.mapClient(try await repo.fetchOne(id)) },
            subClients: { id in try await repo.fetchSubClients(for: id).map(Self.mapSubClient) }
        )
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
        async let lastWordTask: () = loadLatestCorrespondence()
        _ = await (actsTask, fusTask, stsTask, rosterTask, filesTask, estTask, subjTask, lastWordTask)
    }

    private func loadActivities() async {
        do {
            let dtos = try await repository.fetchActivities(for: opportunityId)
            activities = dtos.map { $0.toModel() }
        } catch { print("[LeadDetail] activities failed: \(error)") }
    }

    func reloadActivities() async {
        await loadActivities()
    }

    nonisolated static func activityNotificationTargets(
        _ notification: Notification,
        opportunityId: String
    ) -> Bool {
        notification.userInfo?["leadId"] as? String == opportunityId
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
        guard let clientId else {
            // Unlinked: the roster states nothing rather than keeping the last
            // client it happened to hold.
            client = nil
            subClients = []
            return
        }
        do {
            client = try await rosterLoader.client(clientId)
        } catch { print("[LeadDetail] client failed: \(error)") }
        do {
            subClients = try await rosterLoader.subClients(clientId)
        } catch { print("[LeadDetail] sub-clients failed: \(error)") }
    }

    /// The lead's client link moved — re-point the roster at it.
    ///
    /// Called whenever `opportunity.clientId` changes under the open dossier:
    /// the CLIENT row's picker, its RETRY, or any other writer. Idempotent —
    /// a link that has not actually moved costs nothing, so wiring it to a
    /// view's `onChange` is free.
    func clientLinkChanged(to newClientId: String?) async {
        let next = LeadClientLink.normalised(newClientId)
        guard next != clientId else { return }
        clientId = next
        await loadClientRoster()
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

    private func loadLatestCorrespondence() async {
        do {
            latestCorrespondence = try await repository
                .latestCorrespondence(for: opportunityId)
        } catch { print("[LeadDetail] last word failed: \(error)") }
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

    /// Amend an already-logged note (bug f740400e). Notes only — the repository
    /// re-checks the type — and the rail is repainted from the server's row, so
    /// what the operator sees after saving is what was actually stored.
    func updateNoteBody(activity: Activity, body: String) async throws {
        let updated = try await activityRepository.updateNoteBody(
            activityId: activity.id,
            type: activity.type,
            body: body
        ).toModel()

        if let index = activities.firstIndex(where: { $0.id == updated.id }) {
            activities[index] = updated
        } else {
            await loadActivities()
        }
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
