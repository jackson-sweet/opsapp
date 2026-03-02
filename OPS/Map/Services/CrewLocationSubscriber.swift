//
//  CrewLocationSubscriber.swift
//  OPS
//
//  Subscribes to crew location updates for the current org.
//  Loads initial state from Supabase DB, then listens for real-time changes.
//

import Foundation
import Combine

@MainActor
final class CrewLocationSubscriber: ObservableObject {

    @Published var crewLocations: [String: CrewLocationUpdate] = [:]

    private var cancellables = Set<AnyCancellable>()
    private var pollingTimer: Timer?
    private var orgId: String = ""

    // MARK: - Subscribe / Unsubscribe

    func subscribe(orgId: String) async {
        self.orgId = orgId

        // Load initial state from DB
        await loadInitialState()

        // Listen for local broadcasts (from CrewLocationBroadcaster on same device)
        NotificationCenter.default.publisher(for: .crewLocationDidUpdate)
            .compactMap { $0.userInfo?["update"] as? CrewLocationUpdate }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.crewLocations[update.userId] = update
            }
            .store(in: &cancellables)

        // Poll DB periodically for updates from other devices (every 15s)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.loadInitialState()
            }
        }
    }

    func unsubscribe() {
        cancellables.removeAll()
        pollingTimer?.invalidate()
        pollingTimer = nil
        crewLocations.removeAll()
    }

    // MARK: - Load from Supabase

    private func loadInitialState() async {
        guard !orgId.isEmpty else { return }
        let client = SupabaseService.shared.client

        do {
            let rows: [CrewLocationRow] = try await client.from("crew_locations")
                .select()
                .eq("org_id", value: orgId)
                .execute()
                .value

            for row in rows {
                let update = CrewLocationUpdate(
                    userId: row.user_id,
                    orgId: row.org_id,
                    firstName: row.first_name,
                    lastName: row.last_name,
                    lat: row.lat,
                    lng: row.lng,
                    heading: row.heading ?? -1,
                    speed: row.speed ?? 0,
                    accuracy: row.accuracy ?? 0,
                    timestamp: row.updated_at,
                    batteryLevel: row.battery_level ?? 0,
                    isBackground: row.is_background ?? false,
                    currentTaskName: row.current_task_name,
                    currentProjectName: row.current_project_name,
                    currentProjectId: row.current_project_id,
                    currentProjectAddress: row.current_project_address,
                    phoneNumber: row.phone_number
                )
                crewLocations[row.user_id] = update
            }
        } catch {
            print("[CrewSubscriber] Load failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - DB Row Mapping

struct CrewLocationRow: Codable {
    let user_id: String
    let org_id: String
    let first_name: String
    let last_name: String?
    let lat: Double
    let lng: Double
    let heading: Double?
    let speed: Double?
    let accuracy: Double?
    let battery_level: Float?
    let is_background: Bool?
    let current_task_name: String?
    let current_project_name: String?
    let current_project_id: String?
    let current_project_address: String?
    let phone_number: String?
    let updated_at: Date
}
