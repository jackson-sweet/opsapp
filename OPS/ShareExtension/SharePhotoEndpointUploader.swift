//
//  SharePhotoEndpointUploader.swift
//  OPS
//
//  App-side retry for photos captured by the share extension. It deliberately
//  uses the exact same endpoint and stable job ID as the extension's instant
//  background request, so any overlap is an idempotent retry rather than a
//  second upload with a different storage key.
//

import Foundation

@MainActor
enum SharePhotoEndpointUploader {

    enum UploadError: LocalizedError, Equatable {
        case accountChanged
        case unreadableFile
        case invalidResponse
        case invalidPayload
        case rejected(statusCode: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .accountChanged:
                return "The signed-in account changed before upload."
            case .unreadableFile:
                return "The queued photo file is unavailable."
            case .invalidResponse:
                return "The upload server returned an invalid response."
            case .invalidPayload:
                return "The upload server did not confirm the photo."
            case .rejected(let statusCode, let message):
                return message ?? "The upload server rejected the photo (HTTP \(statusCode))."
            }
        }
    }

    private struct ResponseBody: Decodable {
        let success: Bool?
        let url: String?
        let error: String?
    }

    /// Uploads one durable queue job. A 401/403 gets one forced Firebase-token
    /// refresh before returning; the coordinator then retains and retries the
    /// job if authentication or the backend is still temporarily unavailable.
    @discardableResult
    static func upload(_ job: ShareUploadJob) async throws -> URL {
        guard let fileURL = job.fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            throw UploadError.unreadableFile
        }
        guard UserDefaults.standard.string(forKey: "currentUserId") == job.uploadedBy else {
            throw UploadError.accountChanged
        }

        let token = try await FirebaseAuthService.shared.getIDToken()
        guard UserDefaults.standard.string(forKey: "currentUserId") == job.uploadedBy else {
            throw UploadError.accountChanged
        }
        do {
            return try await perform(job: job, fileURL: fileURL, token: token)
        } catch UploadError.rejected(let statusCode, _) where statusCode == 401 || statusCode == 403 {
            let refreshed = try await FirebaseAuthService.shared.getIDToken(forcingRefresh: true)
            guard UserDefaults.standard.string(forKey: "currentUserId") == job.uploadedBy else {
                throw UploadError.accountChanged
            }
            return try await perform(job: job, fileURL: fileURL, token: refreshed)
        }
    }

    private static func perform(
        job: ShareUploadJob,
        fileURL: URL,
        token: String
    ) async throws -> URL {
        let request = try SharePhotoEndpoint.makeRequest(
            baseURL: AppConfiguration.apiBaseURL,
            projectId: job.projectId,
            jobId: job.id,
            takenAt: job.createdAt,
            bearerToken: token
        )
        let (data, response) = try await URLSession.shared.upload(
            for: request,
            fromFile: fileURL
        )
        guard let http = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }

        let body = try? JSONDecoder().decode(ResponseBody.self, from: data)
        guard (200..<300).contains(http.statusCode) else {
            throw UploadError.rejected(
                statusCode: http.statusCode,
                message: body?.error
            )
        }
        guard body?.success == true,
              let rawURL = body?.url,
              let url = URL(string: rawURL),
              url.scheme == "https" else {
            throw UploadError.invalidPayload
        }
        return url
    }

    /// Temporary transport, auth, throttling, and server failures retry forever
    /// without consuming the parking budget. A 403 reaches this policy only
    /// after one forced token refresh, so it is a deterministic project-access
    /// failure and eventually parks with a visible recovery notice.
    nonisolated static func isTransient(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff:
                return true
            default:
                return false
            }
        }

        if error is SharePhotoEndpoint.RequestError {
            // Base URL and UUID/token validation is deterministic. Retrying the
            // same malformed job forever cannot heal it.
            return false
        }

        guard let uploadError = error as? UploadError else {
            // Token providers and decoding/transport layers can fail without a
            // stable status code. Retain and retry rather than burn the photo.
            return true
        }
        switch uploadError {
        case .invalidResponse, .invalidPayload:
            return true
        case .accountChanged, .unreadableFile:
            return false
        case .rejected(let statusCode, _):
            return statusCode == 401
                || statusCode == 408
                || statusCode == 429
                || statusCode >= 500
        }
    }
}
