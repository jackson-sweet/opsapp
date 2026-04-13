//
//  OPSNavigationManager.swift
//  OPS
//
//  Navigation state manager using MKDirections for route calculation.
//  Tracks progress along a route and provides turn-by-turn state
//  for the NavigationHeader UI. Can be upgraded to Mapbox Navigation
//  SDK when the account is configured.
//

import Foundation
import MapKit
import CoreLocation
import Combine
import AVFoundation

@MainActor
final class OPSNavigationManager: ObservableObject {

    // ──────────────────────────────────────────────
    // MARK: - Published State (UI binding)
    // ──────────────────────────────────────────────

    @Published var isActive: Bool = false
    @Published var currentRoute: MKRoute?
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var currentInstruction: String = ""
    @Published var distanceToNextManeuver: CLLocationDistance = 0
    @Published var maneuverIcon: String = "arrow.up" // SF Symbol
    @Published var timeRemaining: TimeInterval = 0
    @Published var distanceRemaining: CLLocationDistance = 0
    @Published var estimatedArrival: Date?
    @Published var hasArrived: Bool = false
    @Published var isVoiceEnabled: Bool = true

    /// All route steps with non-empty instructions. Published so the UI
    /// can render an expanded turn-by-turn list.
    @Published var routeSteps: [MKRoute.Step] = []
    /// Index of the step the user is currently approaching. Published so
    /// the UI updates as the driver progresses along the route.
    @Published var currentStepIndex: Int = 0

    /// Steps ahead of the driver (includes the current step), used to
    /// drive the expanded turn-by-turn list. Empty when not navigating.
    var upcomingSteps: [MKRoute.Step] {
        guard currentStepIndex < routeSteps.count else { return [] }
        return Array(routeSteps[currentStepIndex...])
    }

    /// Returns the SF Symbol name for a given route step's instruction.
    /// Exposed so the expanded turn list can reuse the same icon mapping
    /// the maneuver header uses for the current step.
    func icon(for step: MKRoute.Step) -> String {
        sfSymbolForInstruction(step.instructions)
    }

    // ──────────────────────────────────────────────
    // MARK: - Private State
    // ──────────────────────────────────────────────

    private var progressTimer: Timer?
    private var destination: CLLocationCoordinate2D?
    private weak var locationManager: LocationManager?

    /// Voice guidance synthesizer. Lazily built so the audio engine is
    /// only warmed when the user actually enables voice. Created once
    /// and reused for the lifetime of the manager.
    private lazy var speechSynthesizer: AVSpeechSynthesizer = {
        let synth = AVSpeechSynthesizer()
        return synth
    }()

    // Reroute tracking
    private var lastRerouteTime: Date = .distantPast
    private let rerouteDistanceThreshold: CLLocationDistance = 30 // meters off route
    private let rerouteCooldown: TimeInterval = 15 // seconds between reroutes

    // ──────────────────────────────────────────────
    // MARK: - Init
    // ──────────────────────────────────────────────

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    // ──────────────────────────────────────────────
    // MARK: - Public API
    // ──────────────────────────────────────────────

    /// Calculate a route and start turn-by-turn progress tracking.
    func startNavigation(from origin: CLLocationCoordinate2D, to dest: CLLocationCoordinate2D) async throws {
        destination = dest

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        guard let route = response.routes.first else {
            throw NSError(domain: "OPSNav", code: 1, userInfo: [NSLocalizedDescriptionKey: "No route found"])
        }

        currentRoute = route
        routeCoordinates = extractCoordinates(from: route.polyline)
        routeSteps = route.steps.filter { !$0.instructions.isEmpty }
        currentStepIndex = 0
        timeRemaining = route.expectedTravelTime
        distanceRemaining = route.distance
        estimatedArrival = Date().addingTimeInterval(route.expectedTravelTime)
        hasArrived = false
        isActive = true

        updateCurrentStep()
        startProgressTimer()
    }

    /// Stop navigation and reset all state.
    func stopNavigation() {
        isActive = false
        hasArrived = false
        currentRoute = nil
        routeCoordinates = []
        routeSteps = []
        currentStepIndex = 0
        currentInstruction = ""
        distanceToNextManeuver = 0
        timeRemaining = 0
        distanceRemaining = 0
        estimatedArrival = nil
        destination = nil
        progressTimer?.invalidate()
        progressTimer = nil
        stopSpeaking()
    }

    /// Toggle voice guidance on/off.
    /// - Off → On: immediately speak the current maneuver instruction so
    ///   the user gets audio feedback that the toggle worked.
    /// - On → Off: stop any in-progress utterance.
    func toggleVoice() {
        let newValue = !isVoiceEnabled
        isVoiceEnabled = newValue

        if newValue {
            speakCurrentInstruction()
        } else {
            stopSpeaking()
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Voice Guidance
    // ──────────────────────────────────────────────

    /// Speak the current maneuver instruction. Safe to call even when
    /// voice is disabled — it no-ops in that case.
    private func speakCurrentInstruction() {
        guard isVoiceEnabled else { return }
        let text = currentInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        configureAudioSessionIfNeeded()

        // Stop any in-flight utterance so the new one takes over.
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
    }

    /// Halt any in-progress speech immediately. Called when the user
    /// toggles voice off and when navigation stops.
    private func stopSpeaking() {
        guard speechSynthesizer.isSpeaking else { return }
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    /// Configure the shared audio session for playback + ducking once,
    /// so voice guidance interrupts/ducks other audio cleanly.
    private func configureAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playback else { return }
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setActive(true, options: [])
        } catch {
            // Best-effort — if session configuration fails, fall back to
            // whatever the default is. The synthesizer still plays.
        }
    }

    // ──────────────────────────────────────────────
    // MARK: - Progress Timer
    // ──────────────────────────────────────────────

    /// Fires every 1 second to update navigation progress.
    /// Added to `.common` run loop mode so it keeps firing during scroll/gesture tracking.
    private func startProgressTimer() {
        progressTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func updateProgress() {
        guard isActive,
              let location = locationManager?.currentLocation,
              let dest = destination else { return }

        // Update distance remaining to destination
        let destLocation = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        distanceRemaining = location.distance(from: destLocation)

        // Update time remaining (rough estimate based on speed)
        if location.speed > 1 {
            timeRemaining = distanceRemaining / location.speed
        }
        estimatedArrival = Date().addingTimeInterval(timeRemaining)

        // Check arrival (30m threshold)
        if distanceRemaining < 30 {
            hasArrived = true
            progressTimer?.invalidate()
            return
        }

        // Advance through route steps
        advanceStepIfNeeded(location: location)
    }

    // ──────────────────────────────────────────────
    // MARK: - Step Tracking
    // ──────────────────────────────────────────────

    private func advanceStepIfNeeded(location: CLLocation) {
        guard currentStepIndex < routeSteps.count else { return }

        let currentStep = routeSteps[currentStepIndex]
        let stepEndPoint = currentStep.polyline.coordinate // endpoint of current step
        let distanceToStepEnd = location.distance(
            from: CLLocation(latitude: stepEndPoint.latitude, longitude: stepEndPoint.longitude)
        )

        distanceToNextManeuver = distanceToStepEnd

        // Advance to next step if within 30m of step endpoint
        if distanceToStepEnd < 30 && currentStepIndex < routeSteps.count - 1 {
            currentStepIndex += 1
            updateCurrentStep()
        }
    }

    private func updateCurrentStep() {
        guard currentStepIndex < routeSteps.count else {
            currentInstruction = "Arrive at destination"
            maneuverIcon = "mappin.circle.fill"
            speakCurrentInstruction()
            return
        }

        let step = routeSteps[currentStepIndex]
        currentInstruction = step.instructions
        distanceToNextManeuver = step.distance
        maneuverIcon = sfSymbolForInstruction(step.instructions)

        // Speak the new maneuver whenever we advance to the next step
        // while voice is enabled. Safe to call when voice is off — it
        // no-ops in that branch.
        speakCurrentInstruction()
    }

    // ──────────────────────────────────────────────
    // MARK: - Instruction → SF Symbol Mapping
    // ──────────────────────────────────────────────

    private func sfSymbolForInstruction(_ instruction: String) -> String {
        let lower = instruction.lowercased()
        if lower.contains("turn right") || lower.contains("right on") { return "arrow.turn.up.right" }
        if lower.contains("turn left") || lower.contains("left on") { return "arrow.turn.up.left" }
        if lower.contains("slight right") { return "arrow.up.right" }
        if lower.contains("slight left") { return "arrow.up.left" }
        if lower.contains("u-turn") || lower.contains("make a u") { return "arrow.uturn.down" }
        if lower.contains("merge") { return "arrow.merge" }
        if lower.contains("exit") || lower.contains("ramp") { return "arrow.up.right" }
        if lower.contains("roundabout") || lower.contains("rotary") { return "arrow.triangle.turn.up.right.circle" }
        if lower.contains("arrive") || lower.contains("destination") { return "mappin.circle.fill" }
        if lower.contains("continue") || lower.contains("straight") || lower.contains("head") { return "arrow.up" }
        return "arrow.up"
    }

    // ──────────────────────────────────────────────
    // MARK: - Polyline Coordinate Extraction
    // ──────────────────────────────────────────────

    /// Extract coordinates from an MKPolyline (avoids extension conflict with InProgressManager).
    private func extractCoordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords
    }
}
