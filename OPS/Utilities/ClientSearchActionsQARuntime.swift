//
//  ClientSearchActionsQARuntime.swift
//  OPS
//
//  DEBUG-only launch gate for the Universal Search client long-press harness.
//

import Foundation

enum ClientSearchActionsQARuntime {
    static let launchArgument = "-OPS_CLIENT_SEARCH_ACTIONS_QA"

    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        arguments.contains(launchArgument)
        #else
        false
        #endif
    }
}
