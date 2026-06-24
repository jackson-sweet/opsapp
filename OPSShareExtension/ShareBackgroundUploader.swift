//
//  ShareBackgroundUploader.swift
//  OPSShareExtension
//
//  Best-effort INSTANT upload from the share extension. POSTs a captured photo's
//  bytes straight to the ops-web share-photo endpoint on a background URLSession
//  that iOS keeps running after the share sheet is dismissed — so the photo can
//  reach the project even if OPS is never opened.
//
//  This is a bonus path on top of the durable queue: the app's drain is the
//  guaranteed backstop, and the endpoint is idempotent by jobId (the app's drain
//  detects an endpoint-filed job and skips it), so this can never duplicate.
//  Failures here (offline / expired token / endpoint not yet deployed) are silent
//  — those jobs simply land when OPS is next opened.
//

import Foundation

final class ShareBackgroundUploader: NSObject, URLSessionDelegate {
    static let shared = ShareBackgroundUploader()

    /// Mirrors `AppConfiguration.apiBaseURL` in the app target (the extension
    /// can't import it). Keep in sync.
    private static let shareEndpoint = "https://app.opsapp.co/api/uploads/share-photo"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: AppGroupConfig.backgroundSessionIdentifier)
        config.sharedContainerIdentifier = AppGroupConfig.identifier
        // The server does all the work, so the app never needs to be relaunched to
        // handle completion — keep launch events off (no wasted wakeups, no
        // app-side session/handler required).
        config.sessionSendsLaunchEvents = false
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() { super.init() }

    /// Starts a background POST of the inbox file to the share-photo endpoint.
    /// Survives the extension being dismissed. iOS holds the transfer and retries
    /// it across connectivity changes on its own.
    func startUpload(fileURL: URL, projectId: String, jobId: String, idToken: String) {
        guard var components = URLComponents(string: Self.shareEndpoint) else { return }
        components.queryItems = [
            URLQueryItem(name: "projectId", value: projectId),
            URLQueryItem(name: "jobId", value: jobId),
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = jobId
        task.resume()
    }
}
