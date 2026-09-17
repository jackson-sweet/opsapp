//
//  LineItemCountsQARuntime.swift
//  OPS
//
//  DEBUG-only launch gate for the line item count-options harness. Mirrors
//  SiteVisitCaptureQARuntime: a simulator-only host that presents the REAL
//  `LineItemEditSheet` for a Canpro-shaped railing product in an in-memory
//  store — no auth, no network — so blank counts, the blocked save, and an
//  entered 0 can be driven and screenshotted from a UI test.
//
//  `-OPS_LINE_ITEM_COUNTS_QA` opens a new line for the product.
//  Adding `-OPS_LINE_ITEM_COUNTS_QA_EDIT` opens an existing line instead,
//  presented the way the estimate form presents it (no product handed in).
//

import Foundation

enum LineItemCountsQARuntime {
    static let launchArgument = "-OPS_LINE_ITEM_COUNTS_QA"
    static let editLaunchArgument = "-OPS_LINE_ITEM_COUNTS_QA_EDIT"

    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        arguments.contains(launchArgument)
        #else
        false
        #endif
    }

    static func opensExistingLine(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        arguments.contains(editLaunchArgument)
        #else
        false
        #endif
    }
}
