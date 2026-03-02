//
//  GeofenceManager.swift
//  OPS
//
//  Monitors the nearest 18 job sites using CLCircularRegion.
//  Surfaces clock-in/out banners on region entry/exit with 15s auto-dismiss.
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class GeofenceManager: ObservableObject {

    @Published var pendingArrival: GeofenceEvent?
    @Published var pendingDeparture: GeofenceEvent?

    struct GeofenceEvent: Equatable {
        let projectId: String
        let projectName: String
        let address: String
        let timestamp: Date

        static func == (lhs: GeofenceEvent, rhs: GeofenceEvent) -> Bool {
            lhs.projectId == rhs.projectId && lhs.timestamp == rhs.timestamp
        }
    }

    private let locationManager: LocationManager
    private var monitoredProjectIds: Set<String> = []
    private var projectLookup: [String: (name: String, address: String)] = [:]
    private var clockedInProjectId: String?

    // Auto-dismiss timer
    private var dismissTimer: Timer?

    private var cancellables = Set<AnyCancellable>()

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        subscribeToGeofenceNotifications()
    }

    // MARK: - Notification Subscriptions

    private func subscribeToGeofenceNotifications() {
        NotificationCenter.default.publisher(for: Notification.Name("GeofenceEntry"))
            .compactMap { $0.userInfo?["region"] as? CLRegion }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] region in
                self?.handleRegionEntry(region)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: Notification.Name("GeofenceExit"))
            .compactMap { $0.userInfo?["region"] as? CLRegion }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] region in
                self?.handleRegionExit(region)
            }
            .store(in: &cancellables)
    }

    // MARK: - Geofence Management

    func updateGeofences(for currentLocation: CLLocation, jobSites: [Project]) {
        // Sort by distance, take closest 18 (iOS limit is 20, reserve 2)
        let sorted = jobSites
            .compactMap { project -> (Project, CLLocationDistance)? in
                guard let lat = project.latitude, let lng = project.longitude else { return nil }
                let distance = currentLocation.distance(from: CLLocation(latitude: lat, longitude: lng))
                return (project, distance)
            }
            .sorted { $0.1 < $1.1 }

        let desired = Set(sorted.prefix(18).map { $0.0.id })
        let current = monitoredProjectIds

        // Remove stale regions
        for id in current.subtracting(desired) {
            if let region = locationManager.monitoredRegions.first(where: { $0.identifier == id }) {
                locationManager.stopMonitoringRegion(region)
            }
            projectLookup.removeValue(forKey: id)
        }

        // Add new regions
        for (project, _) in sorted.prefix(18) where !current.contains(project.id) {
            guard let lat = project.latitude, let lng = project.longitude else { continue }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                radius: 100,
                identifier: project.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            locationManager.startMonitoringRegion(region)
            projectLookup[project.id] = (
                name: project.title,
                address: project.address ?? ""
            )
        }

        monitoredProjectIds = desired
    }

    // MARK: - Region Event Handling

    func handleRegionEntry(_ region: CLRegion) {
        guard let info = projectLookup[region.identifier] else { return }
        pendingArrival = GeofenceEvent(
            projectId: region.identifier,
            projectName: info.name,
            address: info.address,
            timestamp: Date()
        )
        startDismissTimer()
    }

    func handleRegionExit(_ region: CLRegion) {
        guard clockedInProjectId == region.identifier,
              let info = projectLookup[region.identifier] else { return }
        pendingDeparture = GeofenceEvent(
            projectId: region.identifier,
            projectName: info.name,
            address: info.address,
            timestamp: Date()
        )
        startDismissTimer()
    }

    // MARK: - Clock In/Out Actions

    func clockIn(projectId: String) {
        clockedInProjectId = projectId
        pendingArrival = nil
        dismissTimer?.invalidate()
        // TODO: Post clock-in to backend
    }

    func clockOut() {
        clockedInProjectId = nil
        pendingDeparture = nil
        dismissTimer?.invalidate()
        // TODO: Post clock-out to backend
    }

    func dismissBanner() {
        pendingArrival = nil
        pendingDeparture = nil
        dismissTimer?.invalidate()
    }

    // MARK: - Auto-Dismiss

    private func startDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.pendingArrival = nil
                self?.pendingDeparture = nil
            }
        }
    }
}
