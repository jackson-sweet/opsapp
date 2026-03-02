//
//  CrewLocationBroadcaster.swift
//  OPS
//
//  Broadcasts the current user's location via Supabase Realtime
//  and persists to the crew_locations table. Active only when clocked in.
//

import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
final class CrewLocationBroadcaster: ObservableObject {

    @Published var isBroadcasting: Bool = false

    private var locationManager: LocationManager
    private var cancellables = Set<AnyCancellable>()

    private var lastBroadcastTime: Date = .distantPast
    private var lastPersistTime: Date = .distantPast
    private var lastCoordinate: CLLocationCoordinate2D?

    // User info
    private var userId: String = ""
    private var orgId: String = ""
    private var firstName: String = ""
    private var lastName: String = ""
    private var phoneNumber: String?

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    // MARK: - Start / Stop

    func startBroadcasting(
        userId: String,
        orgId: String,
        firstName: String,
        lastName: String,
        phoneNumber: String?
    ) {
        self.userId = userId
        self.orgId = orgId
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber

        locationManager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleLocation(location)
                }
            }
            .store(in: &cancellables)

        isBroadcasting = true
    }

    func stopBroadcasting() {
        isBroadcasting = false
        cancellables.removeAll()
        lastBroadcastTime = .distantPast
        lastPersistTime = .distantPast
        lastCoordinate = nil
    }

    // MARK: - Location Handling

    private func handleLocation(_ location: CLLocation) async {
        guard isBroadcasting else { return }
        guard shouldAcceptLocation(location) else { return }

        let isMoving = location.speed > 1
        let broadcastInterval: TimeInterval = isMoving ? 5 : 30
        guard abs(lastBroadcastTime.timeIntervalSinceNow) >= broadcastInterval else { return }

        lastBroadcastTime = Date()
        lastCoordinate = location.coordinate

        let update = CrewLocationUpdate(
            userId: userId,
            orgId: orgId,
            firstName: firstName,
            lastName: lastName.isEmpty ? nil : lastName,
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            heading: location.course,
            speed: location.speed,
            accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp,
            batteryLevel: UIDevice.current.batteryLevel,
            isBackground: UIApplication.shared.applicationState == .background,
            currentTaskName: nil,
            currentProjectName: nil,
            currentProjectId: nil,
            currentProjectAddress: nil,
            phoneNumber: phoneNumber
        )

        // Broadcast to local subscribers (other map components)
        NotificationCenter.default.post(
            name: .crewLocationDidUpdate,
            object: nil,
            userInfo: ["update": update]
        )

        // Persist to Supabase DB (throttled separately)
        let persistInterval: TimeInterval = isMoving ? 10 : 60
        if abs(lastPersistTime.timeIntervalSinceNow) >= persistInterval {
            lastPersistTime = Date()
            await persistToSupabase(update)
        }
    }

    // MARK: - Supabase Persistence

    private struct CrewLocationUpsertDTO: Codable {
        let userId: String
        let orgId: String
        let firstName: String
        let lastName: String
        let lat: Double
        let lng: Double
        let heading: Double
        let speed: Double
        let accuracy: Double
        let batteryLevel: Double
        let isBackground: Bool
        let phoneNumber: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case orgId = "org_id"
            case firstName = "first_name"
            case lastName = "last_name"
            case lat, lng, heading, speed, accuracy
            case batteryLevel = "battery_level"
            case isBackground = "is_background"
            case phoneNumber = "phone_number"
            case updatedAt = "updated_at"
        }
    }

    private func persistToSupabase(_ update: CrewLocationUpdate) async {
        let client = SupabaseService.shared.client
        let isoFormatter = ISO8601DateFormatter()

        let dto = CrewLocationUpsertDTO(
            userId: update.userId,
            orgId: update.orgId,
            firstName: update.firstName,
            lastName: update.lastName ?? "",
            lat: update.lat,
            lng: update.lng,
            heading: update.heading,
            speed: update.speed,
            accuracy: update.accuracy,
            batteryLevel: Double(update.batteryLevel),
            isBackground: update.isBackground,
            phoneNumber: update.phoneNumber ?? "",
            updatedAt: isoFormatter.string(from: Date())
        )

        do {
            try await client.from("crew_locations")
                .upsert(dto)
                .execute()
        } catch {
            print("[CrewBroadcaster] Persist failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Noise Filtering

    private func shouldAcceptLocation(_ location: CLLocation) -> Bool {
        // Reject stale readings (> 10 seconds old)
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return false }
        // Reject inaccurate readings (> 50m accuracy or invalid)
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 50 else { return false }

        // Skip if identical coordinate
        if let last = lastCoordinate,
           last.latitude == location.coordinate.latitude,
           last.longitude == location.coordinate.longitude {
            return false
        }

        return true
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let crewLocationDidUpdate = Notification.Name("crewLocationDidUpdate")
}
