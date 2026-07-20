//
//  ScheduleLongPressQARuntime.swift
//  OPS
//
//  DEBUG-only launch gate for the Schedule long-press quick-actions QA host.
//  Mirrors CatalogSetupQARuntime: a simulator-only harness that renders the real
//  calendar cards (day CalendarEventCard + month EventBar) with no auth / no
//  network so an XCUITest can drive a real long-press and assert the quick-action
//  context menu actually opens. Guards bug 75318af9 (quick reschedule actions
//  vanished when a second context menu was stacked on the day card).
//

import Foundation

enum ScheduleLongPressQARuntime {
    static let launchArgument = "-OPS_SCHEDULE_LONGPRESS_QA"

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
