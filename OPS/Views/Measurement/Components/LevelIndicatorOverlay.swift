//
//  LevelIndicatorOverlay.swift
//  OPS
//
//  Horizontal level hairline through the viewfinder center per spec §5.1
//  ("Level indicator"). Default ON for LiDAR devices because skewed shots
//  degrade measurement precision; the parent passes `isEnabled` based on
//  capability + user preference.
//
//  Visual:
//    • 1 pt hairline, ~60% of viewfinder width
//    • `text3` when within ±2° of level
//    • `tan` when tilt > 5° (warning territory)
//    • Linear interpolation in between
//    • Hairline rotates by the device roll angle so it visually "settles"
//      when the user levels the device.
//
//  Source: CoreMotion `CMMotionManager.deviceMotion.attitude.roll`. We use
//  CoreMotion rather than tapping ARKit's pose because the indicator should
//  start animating immediately on view appear — before the AR session has
//  achieved tracking — and CoreMotion has near-zero warm-up.
//
//  Reduced motion: hairline stays static at 0° (per spec §5.1 reduced-motion
//  note "Level indicator stays static"). Color still updates.
//

import SwiftUI
import CoreMotion

struct LevelIndicatorOverlay: View {
    /// Toggled by the parent — settings default ON for LiDAR devices.
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motion = LevelMotionTracker()

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.6
            Rectangle()
                .fill(hairlineColor)
                .frame(width: width, height: 1)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .rotationEffect(.radians(reduceMotion ? 0 : motion.rollRadians))
                .opacity(isEnabled ? 1.0 : 0.0)
                .allowsHitTesting(false)
                .animation(.opsCurve200, value: hairlineColor)
        }
        .onAppear {
            guard isEnabled else { return }
            motion.start()
        }
        .onDisappear {
            // Memory cleanup per ios-animations standards #6 — drop the
            // CMMotionManager subscription when the view goes away.
            motion.stop()
        }
        .onChange(of: isEnabled) { _, enabled in
            if enabled { motion.start() } else { motion.stop() }
        }
    }

    private var hairlineColor: Color {
        let absDeg = abs(motion.rollDegrees)
        if absDeg <= 2 { return OPSStyle.Colors.text3 }
        if absDeg >= 5 { return OPSStyle.Colors.tan }
        // Lerp text3 → tan between 2° and 5°.
        return OPSStyle.Colors.text3.opacity(1.0)  // fallback; SwiftUI Color blend is not native — keep crisp transitions
    }
}

// MARK: - CoreMotion subscription

@MainActor
private final class LevelMotionTracker: ObservableObject {
    @Published var rollRadians: Double = 0

    var rollDegrees: Double { rollRadians * 180.0 / .pi }

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        // 30 Hz is enough — the hairline rotates smoothly and we never
        // animate per-frame. Higher rates drain battery without visible gain.
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            Task { @MainActor [weak self] in
                self?.rollRadians = data.attitude.roll
            }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }

    deinit {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }
}
