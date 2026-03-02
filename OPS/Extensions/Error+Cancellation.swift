//
//  Error+Cancellation.swift
//  OPS
//
//  Utility to detect user-initiated task cancellation errors (e.g. pull-to-refresh cancelled).
//

import Foundation

extension Error {
    /// Returns true when the error is a user-initiated cancellation (e.g. pull-to-refresh dismissed).
    var isCancellation: Bool {
        if self is CancellationError { return true }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
