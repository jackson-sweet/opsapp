//
//  PreferenceKeys.swift
//  OPS
//
//  Preference keys and view modifiers for capturing element frames
//  to position the tutorial overlay cutouts correctly.
//

import SwiftUI

// MARK: - Preference Keys

/// Preference key for capturing a single target frame
struct TutorialTargetFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        // Only update if the new value is non-zero
        if next != .zero {
            value = next
        }
    }
}

/// Preference key for capturing multiple named target frames
struct TutorialNamedFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Preference key for capturing frame associated with a specific phase
struct TutorialPhaseFrameKey: PreferenceKey {
    static var defaultValue: [TutorialPhase: CGRect] = [:]

    static func reduce(value: inout [TutorialPhase: CGRect], nextValue: () -> [TutorialPhase: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - View Extensions

extension View {
    /// Marks a view as a tutorial target, capturing its frame in global coordinates
    /// - Parameter phase: The tutorial phase this target is associated with
    /// - Returns: Modified view that reports its frame
    func tutorialTarget(for phase: TutorialPhase) -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: TutorialPhaseFrameKey.self,
                        value: [phase: geometry.frame(in: .global)]
                    )
            }
        )
    }

    /// Marks a view as a named tutorial target
    /// - Parameter id: Unique identifier for this target
    /// - Returns: Modified view that reports its frame
    func tutorialTarget(id: String) -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: TutorialNamedFramesKey.self,
                        value: [id: geometry.frame(in: .global)]
                    )
            }
        )
    }

    /// Captures the view's frame as the primary tutorial target
    /// - Returns: Modified view that reports its frame
    func tutorialTargetFrame() -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: TutorialTargetFrameKey.self,
                        value: geometry.frame(in: .global)
                    )
            }
        )
    }

    /// Reads the captured frame for a specific phase and calls the handler
    /// - Parameters:
    ///   - phase: The tutorial phase to read the frame for
    ///   - handler: Closure called with the frame when it changes
    /// - Returns: Modified view
    func onTutorialFrameChange(
        for phase: TutorialPhase,
        perform handler: @escaping (CGRect) -> Void
    ) -> some View {
        self.onPreferenceChange(TutorialPhaseFrameKey.self) { frames in
            if let frame = frames[phase] {
                handler(frame)
            }
        }
    }

    /// Reads all captured named frames and calls the handler
    /// - Parameter handler: Closure called with the frames dictionary when it changes
    /// - Returns: Modified view
    func onTutorialNamedFrameChange(
        perform handler: @escaping ([String: CGRect]) -> Void
    ) -> some View {
        self.onPreferenceChange(TutorialNamedFramesKey.self) { frames in
            handler(frames)
        }
    }

    /// Reads the primary target frame and calls the handler
    /// - Parameter handler: Closure called with the frame when it changes
    /// - Returns: Modified view
    func onTutorialTargetFrameChange(
        perform handler: @escaping (CGRect) -> Void
    ) -> some View {
        self.onPreferenceChange(TutorialTargetFrameKey.self) { frame in
            handler(frame)
        }
    }
}

// MARK: - Frame Coordinator

/// Coordinator for managing tutorial target frames across the view hierarchy
@MainActor
class TutorialFrameCoordinator: ObservableObject {
    /// All captured frames by phase
    @Published var framesByPhase: [TutorialPhase: CGRect] = [:]

    /// All captured frames by name
    @Published var framesByName: [String: CGRect] = [:]

    /// Updates frame for a specific phase
    func setFrame(_ frame: CGRect, for phase: TutorialPhase) {
        framesByPhase[phase] = frame
    }

    /// Updates frame for a specific name
    func setFrame(_ frame: CGRect, named name: String) {
        framesByName[name] = frame
    }

    /// Gets frame for a specific phase
    func frame(for phase: TutorialPhase) -> CGRect {
        framesByPhase[phase] ?? .zero
    }

    /// Gets frame for a specific name
    func frame(named name: String) -> CGRect {
        framesByName[name] ?? .zero
    }

    /// Clears all captured frames
    func clearFrames() {
        framesByPhase.removeAll()
        framesByName.removeAll()
    }
}

// MARK: - Environment Key

/// Environment key for accessing the frame coordinator
private struct TutorialFrameCoordinatorKey: EnvironmentKey {
    static let defaultValue: TutorialFrameCoordinator? = nil
}

extension EnvironmentValues {
    var tutorialFrameCoordinator: TutorialFrameCoordinator? {
        get { self[TutorialFrameCoordinatorKey.self] }
        set { self[TutorialFrameCoordinatorKey.self] = newValue }
    }
}

// MARK: - Preview

#if DEBUG
struct PreferenceKeys_Previews: PreviewProvider {
    static var previews: some View {
        PreferenceKeysDemo()
    }
}

struct PreferenceKeysDemo: View {
    @State private var targetFrame: CGRect = .zero

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Text("Target View Below")
                    .foregroundColor(.white)

                // Target element
                Button("Tutorial Target") {
                    // Action
                }
                .padding()
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(8)
                .tutorialTargetFrame()
            }

            // Show captured frame
            if targetFrame != .zero {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: targetFrame.width, height: targetFrame.height)
                    .position(x: targetFrame.midX, y: targetFrame.midY)

                Text("Frame: \(Int(targetFrame.minX)), \(Int(targetFrame.minY))")
                    .font(.caption)
                    .foregroundColor(.green)
                    .position(x: targetFrame.midX, y: targetFrame.maxY + 20)
            }
        }
        .onTutorialTargetFrameChange { frame in
            targetFrame = frame
        }
    }
}
#endif
