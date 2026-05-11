//
//  ModelContainerHolder.swift
//  OPS
//
//  Bridge so non-View, non-injected services (the CalendarMirrorService
//  singleton) can reach the app's main SwiftData ModelContainer. Set once
//  from OPSApp at launch.
//

import Foundation
import SwiftData

@MainActor
enum ModelContainerHolder {
    static var shared: ModelContainer?

    /// Convenience: returns the container's main context if set.
    static var mainContext: ModelContext? {
        shared?.mainContext
    }
}
