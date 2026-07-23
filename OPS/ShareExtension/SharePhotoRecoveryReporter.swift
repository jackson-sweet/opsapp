//
//  SharePhotoRecoveryReporter.swift
//  OPS
//
//  A durably queued photo that exhausts deterministic retries is never allowed
//  to disappear into a silent local parking lot. This reports the stable job ID
//  to OPS Web, which creates one dismissible, deduped notification directing the
//  uploader back to the project. Failed reports remain at the threshold and are
//  retried on the next drain.
//

import Foundation

@MainActor
enum SharePhotoRecoveryReporter {
    private struct ResponseBody: Decodable {
        let success: Bool?
    }

    static func report(_ job: ShareUploadJob) async -> Bool {
        guard UserDefaults.standard.string(
            forKey: "currentUserId"
        ) == job.uploadedBy else {
            return false
        }

        do {
            let token = try await FirebaseAuthService.shared.getIDToken()
            guard UserDefaults.standard.string(
                forKey: "currentUserId"
            ) == job.uploadedBy else {
                return false
            }
            do {
                return try await perform(job: job, token: token)
            } catch ReportError.unauthorized {
                let refreshed = try await FirebaseAuthService.shared
                    .getIDToken(forcingRefresh: true)
                guard UserDefaults.standard.string(
                    forKey: "currentUserId"
                ) == job.uploadedBy else {
                    return false
                }
                return try await perform(job: job, token: refreshed)
            }
        } catch {
            return false
        }
    }

    private enum ReportError: Error {
        case unauthorized
        case rejected
    }

    private static func perform(
        job: ShareUploadJob,
        token: String
    ) async throws -> Bool {
        let request = try SharePhotoEndpoint.makeRecoveryReportRequest(
            baseURL: AppConfiguration.apiBaseURL,
            projectId: job.projectId,
            jobId: job.id,
            bearerToken: token
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReportError.rejected
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ReportError.unauthorized
        }
        guard (200..<300).contains(http.statusCode),
              (try? JSONDecoder().decode(
                ResponseBody.self,
                from: data
              ))?.success == true else {
            throw ReportError.rejected
        }
        return true
    }
}
