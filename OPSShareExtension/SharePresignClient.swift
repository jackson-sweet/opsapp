//
//  SharePresignClient.swift
//  OPSShareExtension
//
//  The extension's own presign + background-upload path. It uses the bridged
//  Firebase ID token directly (no Firebase SDK in the extension) to request a
//  presigned S3 URL from ops-web, then pushes the bytes on a background
//  URLSession that survives the extension being dismissed. The app re-attaches
//  to the same background session identifier to finalize the DB rows.
//

import Foundation

enum SharePresignClient {

    /// Mirrors `AppConfiguration.apiBaseURL` in the app target. One duplicated
    /// string (the extension can't see AppConfiguration) — keep in sync.
    private static let presignEndpoint = URL(string: "https://app.opsapp.co/api/uploads/presign")!

    struct PresignResponse: Decodable {
        let uploadUrl: String
        let publicUrl: String
    }

    /// Requests a presigned S3 PUT URL. Returns nil on any failure (the caller
    /// then leaves the job pending for the app to presign + upload on next drain).
    /// Replicates `PresignedURLUploadService.requestPresignedURL` exactly, except
    /// the bearer token comes from the session bridge rather than Firebase.
    static func presign(filename: String, folder: String, idToken: String) async -> PresignResponse? {
        var request = URLRequest(url: presignEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "contentType", value: "image/jpeg"),
            URLQueryItem(name: "folder", value: folder)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode),
            let decoded = try? JSONDecoder().decode(PresignResponse.self, from: data)
        else {
            return nil
        }
        return decoded
    }
}

/// Owns the extension's background upload session. The session identifier +
/// shared container match the app's `ShareUploadCoordinator`, so iOS hands
/// completion events to the app once the extension is gone.
final class ShareBackgroundUploader: NSObject, URLSessionDelegate {
    static let shared = ShareBackgroundUploader()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: AppGroupConfig.backgroundSessionIdentifier)
        config.sharedContainerIdentifier = AppGroupConfig.identifier
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Starts a background PUT of `fileURL` to the presigned `uploadURL`. The
    /// task's `taskDescription` is the job id so the app can map the completion
    /// back to the manifest. Survives the extension being dismissed.
    func startUpload(fileURL: URL, uploadURL: URL, jobId: String) {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = jobId
        task.resume()
    }
}
