//
//  CrewLocationUpdate.swift
//  OPS
//
//  Data model for real-time crew location updates received via Supabase Realtime.
//

import Foundation

/// Represents a single location update from a crew member's device.
struct CrewLocationUpdate: Codable {
    let userId: String
    let orgId: String
    let firstName: String
    var lastName: String?
    let lat: Double
    let lng: Double
    let heading: Double
    let speed: Double
    let accuracy: Double
    let timestamp: Date
    let batteryLevel: Float
    let isBackground: Bool
    var currentTaskName: String?
    var currentProjectName: String?
    var currentProjectId: String?
    var currentProjectAddress: String?
    var phoneNumber: String?
}
