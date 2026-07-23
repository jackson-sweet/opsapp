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
//  guaranteed backstop, and both paths use the same endpoint + jobId, so an
//  overlap is the same operation rather than a second, random-key upload.
//  Failures here (offline / expired token / endpoint not yet deployed) are silent
//  — those jobs simply land when OPS is next opened.
//

import Foundation
import os

final class ShareBackgroundUploader: NSObject, URLSessionDelegate {
    static let shared = ShareBackgroundUploader()

    private let log = Logger(
        subsystem: "co.opsapp.ops.share",
        category: "background-upload"
    )

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
    @discardableResult
    func startUpload(
        fileURL: URL,
        projectId: String,
        jobId: String,
        takenAt: Date,
        idToken: String
    ) -> Bool {
        let request: URLRequest
        do {
            request = try SharePhotoEndpoint.makeRequest(
                projectId: projectId,
                jobId: jobId,
                takenAt: takenAt,
                bearerToken: idToken
            )
        } catch {
            log.error(
                "instant request rejected before upload for \(jobId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }

        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.taskDescription = jobId
        task.resume()
        return true
    }
}
