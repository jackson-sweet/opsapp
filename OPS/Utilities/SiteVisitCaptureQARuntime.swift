//
//  SiteVisitCaptureQARuntime.swift
//  OPS
//
//  DEBUG-only launch gate for the site-visit capture QA host. Mirrors
//  ScheduleLongPressQARuntime: a simulator-only harness that renders the REAL
//  capture console inside the REAL `.fullScreenCover` presentation with no auth
//  and no network, so a picked device contact can be driven end-to-end.
//  Guards bug 5d5df5b0 (contact import tore down the visit and left an empty
//  intake form) and bug 13c66762 (a queued lead reported as a failure).
//

import Foundation

enum SiteVisitCaptureQARuntime {
    static let launchArgument = "-OPS_SITE_VISIT_CAPTURE_QA"

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
