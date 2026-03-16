//
//  ConnectivityManager.swift
//  OPS
//
//  Quality-aware connectivity manager for offline-first sync.
//  Replaces ConnectivityMonitor with richer signal quality tracking,
//  health checks, and sync-decision helpers.
//
//  Uses shared types from SyncTypes.swift:
//    ConnectionStatus, ConnectionQuality, ConnectionState
//

import Foundation
import Network

// MARK: - ConnectivityManager

@MainActor
final class ConnectivityManager: ObservableObject {

    // MARK: Notifications

    static let connectivityChangedNotification =
        Notification.Name("ConnectivityManagerDidChangeState")

    // MARK: Published state

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var state: ConnectionState = .offline

    /// Optional callback invoked on every state change (fires on MainActor).
    var onStateChanged: ((ConnectionState) -> Void)?

    // MARK: Sync decision helpers

    /// True when network is not offline and quality is not unusable.
    var shouldAttemptSync: Bool {
        state.status != .offline && state.quality > .unusable
    }

    /// True when quality is at least good (suitable for large uploads).
    var shouldUploadPhotos: Bool {
        state.quality >= .good
    }

    /// True when quality is at least poor (lightweight pulls are OK).
    var shouldPullData: Bool {
        state.quality >= .poor
    }

    /// Recommended URLRequest timeout based on current quality.
    var recommendedTimeout: TimeInterval {
        switch state.quality {
        case .excellent: return 15
        case .good:      return 30
        case .poor:      return 10
        case .unusable:  return 5
        }
    }

    // MARK: Private properties

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.ops.connectivity")

    /// Current interface type detected by NWPathMonitor.
    private var currentInterfaceType: NWInterface.InterfaceType?

    /// Rolling window of recent request durations (newest last).
    private var recentDurations: [TimeInterval] = []
    /// Rolling window of recent request successes.
    private var recentSuccesses: [Bool] = []
    /// Maximum number of samples to keep.
    private let windowSize = 5

    /// Timestamp of the last successful request (any kind, including health check).
    private var lastSuccessfulRequest: Date?

    /// Timer that fires periodic health checks.
    private var healthCheckTimer: Timer?

    /// Timer used to debounce connectivity state change notifications.
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 2.0

    /// The REST health-check URL derived from SupabaseConfig.
    private let healthCheckURL: URL = {
        // Supabase REST endpoint — a lightweight HEAD to /rest/v1/ returns quickly.
        var components = URLComponents(url: SupabaseConfig.url, resolvingAgainstBaseURL: false)!
        components.path = "/rest/v1/"
        return components.url!
    }()

    /// Seconds without a successful request before we declare "lying WiFi".
    private let lyingWiFiThreshold: TimeInterval = 60

    /// Health check interval in seconds.
    private let healthCheckInterval: TimeInterval = 30

    // MARK: - Lifecycle

    init() {
        setupNWPathMonitor()
        startHealthCheckTimer()
    }

    deinit {
        monitor.cancel()
        healthCheckTimer?.invalidate()
        debounceTimer?.invalidate()
    }

    // MARK: - NWPathMonitor

    private func setupNWPathMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let connected = path.status == .satisfied

                let interfaceType: NWInterface.InterfaceType?
                if path.usesInterfaceType(.wifi) {
                    interfaceType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    interfaceType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    interfaceType = .wiredEthernet
                } else {
                    interfaceType = nil
                }

                self.isConnected = connected
                self.currentInterfaceType = interfaceType

                if !connected {
                    // Clear performance history when we go offline.
                    self.recentDurations.removeAll()
                    self.recentSuccesses.removeAll()
                }

                self.recalculateState()
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Request performance tracking

    /// Call after every Supabase network request to feed quality data.
    func recordRequestResult(duration: TimeInterval, success: Bool) {
        recentDurations.append(duration)
        recentSuccesses.append(success)

        // Keep only the most recent `windowSize` samples.
        if recentDurations.count > windowSize {
            recentDurations.removeFirst(recentDurations.count - windowSize)
        }
        if recentSuccesses.count > windowSize {
            recentSuccesses.removeFirst(recentSuccesses.count - windowSize)
        }

        if success {
            lastSuccessfulRequest = Date()
        }

        recalculateState()
    }

    // MARK: - Health checks

    private func startHealthCheckTimer() {
        healthCheckTimer = Timer.scheduledTimer(
            withTimeInterval: healthCheckInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isConnected else { return }
                await self.performHealthCheck()
            }
        }
    }

    /// Lightweight HEAD request to the Supabase REST endpoint.
    private func performHealthCheck() async {
        var request = URLRequest(url: healthCheckURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(start)
            let httpResponse = response as? HTTPURLResponse
            let success = (httpResponse?.statusCode ?? 0) < 500
            recordRequestResult(duration: duration, success: success)
        } catch {
            let duration = Date().timeIntervalSince(start)
            recordRequestResult(duration: duration, success: false)
        }
    }

    // MARK: - Quality calculation

    /// Recalculates state and publishes changes.
    private func recalculateState() {
        let status: ConnectionStatus
        let quality: ConnectionQuality

        if !isConnected {
            status = .offline
            quality = .unusable
        } else if isLyingWiFi() {
            status = .degraded
            quality = .unusable
        } else if recentDurations.isEmpty {
            // No data yet — assume good until proven otherwise.
            status = .online
            quality = .good
        } else {
            let avgDuration = recentDurations.reduce(0, +) / Double(recentDurations.count)
            let failureCount = recentSuccesses.filter { !$0 }.count
            let failureRate = Double(failureCount) / Double(recentSuccesses.count)

            if failureRate > 0.5 || avgDuration > 10 {
                status = .degraded
                quality = .unusable
            } else if avgDuration > 5 {
                status = .degraded
                quality = .poor
            } else if avgDuration > 2 {
                status = .online
                quality = .good
            } else {
                status = .online
                quality = .excellent
            }
        }

        // Compute estimated bandwidth from avg latency (rough heuristic).
        let estimatedBandwidth: Double?
        if !recentDurations.isEmpty {
            let avg = recentDurations.reduce(0, +) / Double(recentDurations.count)
            // Inverse relationship: lower latency → higher relative bandwidth score.
            estimatedBandwidth = avg > 0 ? (1.0 / avg) : nil
        } else {
            estimatedBandwidth = nil
        }

        let newState = ConnectionState(
            status: status,
            type: currentInterfaceType,
            quality: quality,
            estimatedBandwidth: estimatedBandwidth,
            lastSuccessfulRequest: lastSuccessfulRequest
        )

        let changed = newState.status != state.status
            || newState.type != state.type
            || newState.quality != state.quality

        state = newState
        isConnected = (status != .offline)

        if changed {
            // Debounce both callbacks to prevent duplicate sync triggers from rapid flaps
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.debounceTimer?.invalidate()
                self.debounceTimer = Timer.scheduledTimer(withTimeInterval: self.debounceInterval, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.onStateChanged?(newState)
                    NotificationCenter.default.post(
                        name: ConnectivityManager.connectivityChangedNotification,
                        object: self,
                        userInfo: ["state": newState]
                    )
                }
            }
        }
    }

    /// Detects "lying WiFi" — OS says connected but no successful traffic
    /// for `lyingWiFiThreshold` seconds.
    private func isLyingWiFi() -> Bool {
        guard isConnected else { return false }
        // If we've never had a successful request we can't judge yet.
        guard let lastSuccess = lastSuccessfulRequest else { return false }
        return Date().timeIntervalSince(lastSuccess) > lyingWiFiThreshold
    }
}
