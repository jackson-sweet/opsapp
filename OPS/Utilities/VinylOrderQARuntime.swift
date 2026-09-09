//
//  VinylOrderQARuntime.swift
//  OPS
//
//  DEBUG-only launch gate for the vinyl ORDER LAYOUT workspace. Mirrors
//  SiteVisitCaptureQARuntime: a simulator-only harness that renders the REAL
//  workspace over the REAL entry card with a synthetic plan — no auth, no
//  network, no deck design — so the whole screen can be driven and screenshotted
//  in one command.
//
//  Guards bug 317da29f ("cuts off ~48px from the right edge, the +/- buttons are
//  redundant, there are no tools to adjust the order") and bug 1a8e48af ("the
//  title divider line doesn't need to be there, need to show the deck
//  dimensions").
//

import Foundation

enum VinylOrderQARuntime {
    static let launchArgument = "-OPS_VINYL_ORDER_QA"

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
