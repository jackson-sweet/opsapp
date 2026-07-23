//
//  SharePhotoEndpoint.swift
//  Shared between the OPS app and OPSShareExtension.
//
//  Builds the one idempotent server request used by both upload paths. The
//  extension may start it immediately; the app retries the same request from the
//  durable App Group queue. Matching project + job IDs guarantee both requests
//  address the same object and database record.
//

import Foundation

enum SharePhotoEndpoint {
    enum RequestError: Error, Equatable {
        case invalidBaseURL
        case invalidProjectId
        case invalidJobId
        case missingBearerToken
    }

    static let productionBaseURL = URL(string: "https://app.opsapp.co")!

    static func makeRequest(
        baseURL: URL = productionBaseURL,
        projectId: String,
        jobId: String,
        takenAt: Date,
        bearerToken: String
    ) throws -> URLRequest {
        guard baseURL.scheme == "https", baseURL.host != nil else {
            throw RequestError.invalidBaseURL
        }
        guard UUID(uuidString: projectId) != nil else {
            throw RequestError.invalidProjectId
        }
        guard UUID(uuidString: jobId) != nil else {
            throw RequestError.invalidJobId
        }
        guard !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RequestError.missingBearerToken
        }

        let endpoint = baseURL.appendingPathComponent("api/uploads/share-photo")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw RequestError.invalidBaseURL
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        components.queryItems = [
            URLQueryItem(name: "projectId", value: projectId),
            URLQueryItem(name: "jobId", value: jobId),
            URLQueryItem(name: "takenAt", value: formatter.string(from: takenAt)),
        ]
        guard let url = components.url else {
            throw RequestError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Builds the authenticated acknowledgement request used when a
    /// deterministic upload failure has exhausted its retry budget. The server
    /// owns the dismissible notification copy and dedupes it by this same job ID.
    static func makeRecoveryReportRequest(
        baseURL: URL = productionBaseURL,
        projectId: String,
        jobId: String,
        bearerToken: String
    ) throws -> URLRequest {
        guard baseURL.scheme == "https", baseURL.host != nil else {
            throw RequestError.invalidBaseURL
        }
        let recoveryProjectId = projectId.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let recoveryJobId = jobId.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        // Recovery reporting must remain available precisely when a deployed or
        // corrupt queue row contains an invalid UUID. The server treats bounded
        // non-UUID identifiers as an unlinked recovery alert, never as routing
        // authority.
        guard isBoundedRecoveryIdentifier(recoveryProjectId) else {
            throw RequestError.invalidProjectId
        }
        guard isBoundedRecoveryIdentifier(recoveryJobId) else {
            throw RequestError.invalidJobId
        }
        guard !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RequestError.missingBearerToken
        }

        let endpoint = baseURL
            .appendingPathComponent("api/uploads/share-photo/recovery")
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw RequestError.invalidBaseURL
        }
        components.queryItems = [
            URLQueryItem(name: "projectId", value: recoveryProjectId),
            URLQueryItem(name: "jobId", value: recoveryJobId),
        ]
        guard let url = components.url else {
            throw RequestError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func isBoundedRecoveryIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 128
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}
