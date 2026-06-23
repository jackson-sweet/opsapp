//
//  NetworkRetry.swift
//  OPS
//
//  Shared transient-retry primitive for the upload / write layer.
//
//  Background: the photo-upload pipeline (PresignedURLUploadService /
//  ImageSyncManager) and the note/comment create path both issue a single
//  network request with no retry, so one signal blip on a field connection
//  surfaced as a hard failure — a partial photo batch and a raw "request timed
//  out" in the note composer. This consolidates the retry logic both paths now
//  share: retry the operation while the failure is transient (signal blinked,
//  server hiccup), give up immediately when the failure is permanent (the
//  server rejected the request and will keep rejecting it — an RLS violation,
//  a 4xx, a malformed URL).
//
//  Classification is delegated to `UploadErrorClassifier` so the retry decision
//  matches the rest of the upload layer exactly.
//

import Foundation

enum NetworkRetry {

    /// Run `operation`, retrying transient/unknown failures up to `maxAttempts`
    /// total with exponential backoff (`baseDelaySeconds * 3^(attempt-1)`).
    /// A failure classified `.permanent` by `UploadErrorClassifier` throws
    /// immediately — retrying a server rejection only wastes the user's battery
    /// and signal. The last error is rethrown once attempts are exhausted.
    ///
    /// `baseDelaySeconds` of 0 disables the backoff sleep (used by tests).
    static func run<T>(
        maxAttempts: Int,
        baseDelaySeconds: Double,
        operation: () async throws -> T
    ) async throws -> T {
        let attempts = max(1, maxAttempts)
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // A permanent rejection (RLS, 4xx, malformed URL) will keep
                // failing — stop now rather than burn the user's battery and
                // signal on retries the server will never accept.
                if case .permanent = UploadErrorClassifier.classify(error) {
                    throw error
                }

                // Back off before the next attempt (exponential: base·3^(n-1)).
                if attempt < attempts && baseDelaySeconds > 0 {
                    let delay = baseDelaySeconds * pow(3.0, Double(attempt - 1))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }
}
