//
//  LeadSummaryRefreshService.swift
//  OPS
//
//  Best-effort handoff from a durable human activity write to the Phase C
//  summary engine. The activity save is authoritative and must never be
//  rolled back or shown as failed because this derived refresh is unavailable.
//

import Foundation

protocol LeadSummaryRefreshing: Sendable {
    func requestRefresh(opportunityId: String) async
}

struct LeadSummaryRefreshService: LeadSummaryRefreshing {
    static let shared = LeadSummaryRefreshService()

    private let baseURL: URL
    private let tokenProvider: @Sendable () async throws -> String
    private let requestSender: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        baseURL: URL = AppConfiguration.apiBaseURL,
        tokenProvider: @escaping @Sendable () async throws -> String = {
            try await FirebaseAuthService.shared.getIDToken()
        },
        requestSender: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.requestSender = requestSender
    }

    func requestRefresh(opportunityId: String) async {
        let normalizedId = opportunityId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard UUID(uuidString: normalizedId) != nil else { return }

        do {
            let token = try await tokenProvider()
            let endpoint = baseURL
                .appendingPathComponent("api")
                .appendingPathComponent("opportunities")
                .appendingPathComponent(normalizedId)
                .appendingPathComponent("summary-refresh")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (_, response) = try await requestSender(request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return
            }
        } catch {
            // Phase C is derived data. The durable activity remains successful,
            // and the recurring server refresh is the recovery boundary.
        }
    }
}
