//
//  LeadFollowUpService.swift
//  OPS
//
//  Authenticated transport for the operator-triggered one-tap lead follow-up.
//  The server owns recipient, mailbox, thread, template, signature, delivery,
//  and reconciliation. The client owns only a durable idempotency key.
//

import Foundation

// MARK: - Public contract

@MainActor
protocol LeadFollowUpServiceProtocol {
    func sendFollowUp(
        opportunityId: String,
        scope: LeadFollowUpAttemptScope
    ) async -> LeadFollowUpResult
}

struct LeadFollowUpAttemptScope: Equatable {
    let companyId: String
    let actorUserId: String
    let nextFollowUpAt: Date?
    let handledAt: Date?
    let lastOutboundAt: Date?
}

enum LeadFollowUpResult {
    /// Provider delivery and the lead-state transition are both reconciled.
    case reconciled(opportunity: OpportunityDTO, comebackAt: Date?)

    /// A retry found the immutable server receipt for an already-reconciled
    /// send. The canonical row may have changed since the original request, so
    /// the client refreshes instead of applying a stale opportunity snapshot.
    case reconciledReceipt(comebackAt: Date?)

    /// The provider accepted the email, but OPS is still reconciling local state.
    /// Retrying must use the same idempotency key.
    case providerAcceptedPending(intentId: String?)

    /// The request crossed a boundary where delivery can no longer be proven
    /// either way. Retrying must use the same idempotency key.
    case deliveryUnknown(intentId: String?)

    /// Another device or request already owns the unresolved send for this
    /// lead. The client must not invite a manual or second automated send.
    case alreadyInProgress(intentId: String?)

    /// Current lead/mailbox/thread state cannot support the stock follow-up.
    case unavailable(reason: String?)

    /// The server or provider definitively rejected the attempt before delivery.
    case rejected(reason: String?)

    /// A matching send is already being processed.
    case busy(intentId: String?)

    /// The connected mailbox cannot send until its required signature exists.
    case signatureRequired

    /// The actor is unauthenticated or lacks permission to send this follow-up.
    case permissionDenied

    /// Authentication refresh or transport failed without a definitive response.
    case networkError
}

// MARK: - Durable request-key storage

struct StoredLeadFollowUpAttempt: Codable, Equatable {
    let requestKey: String
    let cycleAt: Date?
    let handledAtAtCreation: Date?
    let lastOutboundAtAtCreation: Date?
}

@MainActor
protocol LeadFollowUpRequestKeyStoring: AnyObject {
    func attempt(
        for opportunityId: String,
        companyId: String,
        actorUserId: String
    ) -> StoredLeadFollowUpAttempt?
    func saveAttempt(
        _ attempt: StoredLeadFollowUpAttempt,
        for opportunityId: String,
        companyId: String,
        actorUserId: String
    )
    func clearAttempt(
        for opportunityId: String,
        companyId: String,
        actorUserId: String
    )
}

@MainActor
final class UserDefaultsLeadFollowUpRequestKeyStore: LeadFollowUpRequestKeyStoring {
    private static let keyPrefix = "ops.leads.followUp.idempotency.v2."

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func attempt(
        for opportunityId: String,
        companyId: String,
        actorUserId: String
    ) -> StoredLeadFollowUpAttempt? {
        guard
            let data = defaults.data(
                forKey: storageKey(
                    for: opportunityId,
                    companyId: companyId,
                    actorUserId: actorUserId
                )
            )
        else {
            return nil
        }
        return try? decoder.decode(StoredLeadFollowUpAttempt.self, from: data)
    }

    func saveAttempt(
        _ attempt: StoredLeadFollowUpAttempt,
        for opportunityId: String,
        companyId: String,
        actorUserId: String
    ) {
        guard let data = try? encoder.encode(attempt) else { return }
        defaults.set(
            data,
            forKey: storageKey(
                for: opportunityId,
                companyId: companyId,
                actorUserId: actorUserId
            )
        )
    }

    func clearAttempt(
        for opportunityId: String,
        companyId: String,
        actorUserId: String
    ) {
        defaults.removeObject(
            forKey: storageKey(
                for: opportunityId,
                companyId: companyId,
                actorUserId: actorUserId
            )
        )
    }

    private func storageKey(
        for opportunityId: String,
        companyId: String,
        actorUserId: String
    ) -> String {
        [
            Self.keyPrefix,
            Self.normalizedIdentifier(companyId),
            ".",
            Self.normalizedIdentifier(actorUserId),
            ".",
            Self.normalizedIdentifier(opportunityId),
        ].joined()
    }

    private static func normalizedIdentifier(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - HTTP seam

@MainActor
protocol LeadFollowUpHTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

@MainActor
final class URLSessionLeadFollowUpHTTPClient: LeadFollowUpHTTPClientProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

// MARK: - Service

@MainActor
final class LeadFollowUpService: LeadFollowUpServiceProtocol {
    static let shared = LeadFollowUpService()

    private let baseURL: URL
    private let httpClient: LeadFollowUpHTTPClientProtocol
    private let tokenProvider: () async throws -> String
    private let requestKeyStore: LeadFollowUpRequestKeyStoring
    private let requestKeyGenerator: () -> String

    init(
        baseURL: URL = AppConfiguration.apiBaseURL,
        httpClient: LeadFollowUpHTTPClientProtocol? = nil,
        tokenProvider: @escaping () async throws -> String = {
            try await FirebaseAuthService.shared.getIDToken()
        },
        requestKeyStore: LeadFollowUpRequestKeyStoring? = nil,
        requestKeyGenerator: @escaping () -> String = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.baseURL = baseURL
        self.httpClient = httpClient ?? URLSessionLeadFollowUpHTTPClient()
        self.tokenProvider = tokenProvider
        self.requestKeyStore = requestKeyStore ?? UserDefaultsLeadFollowUpRequestKeyStore()
        self.requestKeyGenerator = requestKeyGenerator
    }

    func sendFollowUp(
        opportunityId: String,
        scope: LeadFollowUpAttemptScope
    ) async -> LeadFollowUpResult {
        let normalizedOpportunityId = opportunityId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedCompanyId = scope.companyId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedActorUserId = scope.actorUserId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard
            UUID(uuidString: normalizedOpportunityId) != nil,
            !normalizedCompanyId.isEmpty,
            !normalizedActorUserId.isEmpty
        else {
            return .unavailable(reason: "invalid_opportunity")
        }

        let normalizedScope = LeadFollowUpAttemptScope(
            companyId: normalizedCompanyId,
            actorUserId: normalizedActorUserId,
            nextFollowUpAt: scope.nextFollowUpAt,
            handledAt: scope.handledAt,
            lastOutboundAt: scope.lastOutboundAt
        )
        let requestKey = durableRequestKey(
            for: normalizedOpportunityId,
            scope: normalizedScope
        )

        let token: String
        do {
            token = try await tokenProvider()
        } catch {
            if isDefiniteAuthenticationFailure(error) {
                return .permissionDenied
            }
            return .networkError
        }

        let request: URLRequest
        do {
            request = try makeRequest(
                opportunityId: normalizedOpportunityId,
                requestKey: requestKey,
                token: token
            )
        } catch {
            requestKeyStore.clearAttempt(
                for: normalizedOpportunityId,
                companyId: normalizedScope.companyId,
                actorUserId: normalizedScope.actorUserId
            )
            return .rejected(reason: "invalid_request")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            return .networkError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .deliveryUnknown(intentId: nil)
        }

        let payload = try? JSONDecoder().decode(LeadFollowUpAPIResponse.self, from: data)
        return classify(
            payload: payload,
            statusCode: httpResponse.statusCode,
            opportunityId: normalizedOpportunityId,
            scope: normalizedScope
        )
    }

    private func durableRequestKey(
        for opportunityId: String,
        scope: LeadFollowUpAttemptScope
    ) -> String {
        if let existing = requestKeyStore.attempt(
            for: opportunityId,
            companyId: scope.companyId,
            actorUserId: scope.actorUserId
        ), !existing.requestKey.isEmpty, !startsNewCycle(existing, scope: scope) {
            return existing.requestKey
        }

        let generated = requestKeyGenerator().lowercased()
        requestKeyStore.saveAttempt(
            StoredLeadFollowUpAttempt(
                requestKey: generated,
                cycleAt: scope.nextFollowUpAt,
                handledAtAtCreation: scope.handledAt,
                lastOutboundAtAtCreation: scope.lastOutboundAt
            ),
            for: opportunityId,
            companyId: scope.companyId,
            actorUserId: scope.actorUserId
        )
        return generated
    }

    private func startsNewCycle(
        _ existing: StoredLeadFollowUpAttempt,
        scope: LeadFollowUpAttemptScope
    ) -> Bool {
        guard
            let priorCycle = existing.cycleAt,
            let currentCycle = scope.nextFollowUpAt,
            currentCycle > priorCycle
        else {
            return false
        }
        return canonicalDateAdvanced(
            from: existing.handledAtAtCreation,
            to: scope.handledAt
        ) || canonicalDateAdvanced(
            from: existing.lastOutboundAtAtCreation,
            to: scope.lastOutboundAt
        )
    }

    private func canonicalDateAdvanced(from prior: Date?, to current: Date?) -> Bool {
        guard let current else { return false }
        guard let prior else { return true }
        return current > prior
    }

    private func makeRequest(
        opportunityId: String,
        requestKey: String,
        token: String
    ) throws -> URLRequest {
        let endpoint = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("leads")
            .appendingPathComponent(opportunityId)
            .appendingPathComponent("follow-up")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            LeadFollowUpRequest(idempotencyKey: requestKey)
        )
        return request
    }

    private func classify(
        payload: LeadFollowUpAPIResponse?,
        statusCode: Int,
        opportunityId: String,
        scope: LeadFollowUpAttemptScope
    ) -> LeadFollowUpResult {
        if payload?.deliveryUnknown == true {
            return .deliveryUnknown(intentId: payload?.intentId)
        }

        if payload?.delivered == true {
            if payload?.reconciliationPending == true {
                return .providerAcceptedPending(intentId: payload?.intentId)
            }

            let hasImmutableReceipt =
                payload?.opportunityId?.lowercased() == opportunityId
                && payload?.outcomeAppliedAt.flatMap(SupabaseDate.parse) != nil
                && payload?.notificationId?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false

            if
                hasImmutableReceipt,
                let opportunity = payload?.opportunity
            {
                requestKeyStore.clearAttempt(
                    for: opportunityId,
                    companyId: scope.companyId,
                    actorUserId: scope.actorUserId
                )
                return .reconciled(
                    opportunity: opportunity,
                    comebackAt: payload?.comebackAt.flatMap(SupabaseDate.parse)
                )
            }

            if hasImmutableReceipt {
                requestKeyStore.clearAttempt(
                    for: opportunityId,
                    companyId: scope.companyId,
                    actorUserId: scope.actorUserId
                )
                return .reconciledReceipt(
                    comebackAt: payload?.comebackAt.flatMap(SupabaseDate.parse)
                )
            }

            // Provider acceptance is already irreversible. Missing canonical
            // reconciliation fields must never cause a fresh provider send.
            return .providerAcceptedPending(intentId: payload?.intentId)
        }

        if payload?.reconciliationPending == true {
            return .deliveryUnknown(intentId: payload?.intentId)
        }

        let responseReason = payload?.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let responseError = payload?.error?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = responseReason.flatMap { $0.isEmpty ? nil : $0 }
            ?? responseError.flatMap { $0.isEmpty ? nil : $0 }
        let normalizedClassification = [responseError, responseReason]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if payload?.definitiveNoDelivery == true {
            requestKeyStore.clearAttempt(
                for: opportunityId,
                companyId: scope.companyId,
                actorUserId: scope.actorUserId
            )
        }

        if normalizedClassification.contains("signature") {
            return .signatureRequired
        }

        if
            statusCode == 401
                || statusCode == 403
                || normalizedClassification.contains("permission")
                || normalizedClassification.contains("forbidden")
                || normalizedClassification.contains("unauthorized")
                || normalizedClassification.contains("unauthenticated")
        {
            return .permissionDenied
        }

        if isRejectedReason(normalizedClassification) {
            if isDefinitiveNoDeliveryRejection(normalizedClassification) {
                requestKeyStore.clearAttempt(
                    for: opportunityId,
                    companyId: scope.companyId,
                    actorUserId: scope.actorUserId
                )
            }
            return .rejected(reason: reason)
        }

        if isAlreadyInProgressReason(normalizedClassification) {
            return .alreadyInProgress(intentId: payload?.intentId)
        }

        if isUnavailableReason(normalizedClassification) || statusCode == 404 || statusCode == 422 {
            return .unavailable(reason: reason)
        }

        if isBusyReason(normalizedClassification) || statusCode == 409 || statusCode == 429 {
            return .busy(intentId: payload?.intentId)
        }

        if statusCode == 400 {
            requestKeyStore.clearAttempt(
                for: opportunityId,
                companyId: scope.companyId,
                actorUserId: scope.actorUserId
            )
            return .rejected(reason: reason)
        }

        if (200...299).contains(statusCode) || statusCode == 408 || statusCode >= 500 {
            return .deliveryUnknown(intentId: payload?.intentId)
        }

        return .rejected(reason: reason)
    }

    private func isDefiniteAuthenticationFailure(_ error: Error) -> Bool {
        guard
            let authError = error as? FirebaseAuthService.FirebaseAuthServiceError
        else {
            return false
        }
        if case .notAuthenticated = authError {
            return true
        }
        return false
    }

    private func isBusyReason(_ reason: String) -> Bool {
        reason.contains("busy")
            || reason.contains("in_progress")
            || reason.contains("in progress")
            || reason.contains("processing")
            || reason.contains("locked")
    }

    private func isAlreadyInProgressReason(_ reason: String) -> Bool {
        reason.contains("lead_follow_up_already_in_progress")
    }

    private func isRejectedReason(_ reason: String) -> Bool {
        reason.contains("rejected")
            || reason.contains("idempotency_conflict")
            || reason.contains("fingerprint_mismatch")
            || reason.contains("invalid_request")
    }

    private func isDefinitiveNoDeliveryRejection(_ reason: String) -> Bool {
        reason.contains("provider_rejected")
            || reason.contains("invalid_request")
    }

    private func isUnavailableReason(_ reason: String) -> Bool {
        reason.contains("unavailable")
            || reason.contains("no_safe_thread")
            || reason.contains("no_thread")
            || reason.contains("no_recipient")
            || reason.contains("no_contact_email")
            || reason.contains("no_connected_mailbox")
            || reason.contains("no_active_mailbox")
            || reason.contains("no_template")
            || reason.contains("newer_inbound")
            || reason.contains("not_due")
            || reason.contains("not_open")
            || reason.contains("not_found")
            || reason.contains("lead_follow_up_thread_required")
            || reason.contains("lead_follow_up_thread_empty")
            || reason.contains("lead_follow_up_thread_invalid")
            || reason.contains("lead_follow_up_thread_ambiguous")
            || reason.contains("lead_follow_up_thread_conflict")
            || reason.contains("lead_follow_up_draft_ambiguous")
            || reason.contains("lead_follow_up_draft_conflict")
            || reason.contains("lead_follow_up_timezone_invalid")
            || reason.contains("lead_follow_up_conversation_changed")
            || reason.contains("response_required")
            || reason.contains("recipient_required")
            || reason.contains("thread_mismatch")
            || reason.contains("connection_invalid")
            || reason.contains("opportunity_stale")
    }
}

// MARK: - Wire models

private struct LeadFollowUpRequest: Encodable {
    let idempotencyKey: String
}

private struct LeadFollowUpAPIResponse: Decodable {
    let ok: Bool?
    let delivered: Bool?
    let reconciliationPending: Bool?
    let deliveryUnknown: Bool?
    let definitiveNoDelivery: Bool?
    let opportunity: OpportunityDTO?
    let opportunityId: String?
    let comebackAt: String?
    let outcomeAppliedAt: String?
    let notificationId: String?
    let intentId: String?
    let error: String?
    let reason: String?
}
