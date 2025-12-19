//
//  TutorialEnvironment.swift
//  OPS
//
//  Environment keys for the interactive tutorial system.
//  Allows child views to detect when they're in tutorial mode and adjust behavior.
//

import SwiftUI

// MARK: - Tutorial Mode Environment Key

/// Environment key to indicate whether views are in tutorial mode
struct TutorialModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// When true, views should filter to demo data and may have restricted interactions
    var tutorialMode: Bool {
        get { self[TutorialModeKey.self] }
        set { self[TutorialModeKey.self] = newValue }
    }
}

// MARK: - Tutorial Phase Environment Key

/// Environment key to provide the current tutorial phase to child views
struct TutorialPhaseKey: EnvironmentKey {
    static let defaultValue: TutorialPhase? = nil
}

extension EnvironmentValues {
    /// The current phase of the tutorial, nil when not in tutorial
    var tutorialPhase: TutorialPhase? {
        get { self[TutorialPhaseKey.self] }
        set { self[TutorialPhaseKey.self] = newValue }
    }
}

// MARK: - Tutorial State Manager Environment Key

/// Environment key to provide access to the tutorial state manager
struct TutorialStateManagerKey: EnvironmentKey {
    static let defaultValue: TutorialStateManager? = nil
}

extension EnvironmentValues {
    /// The tutorial state manager, nil when not in tutorial
    var tutorialStateManager: TutorialStateManager? {
        get { self[TutorialStateManagerKey.self] }
        set { self[TutorialStateManagerKey.self] = newValue }
    }
}

// MARK: - View Extensions for Tutorial Mode

extension View {
    /// Injects tutorial mode into the environment
    func tutorialMode(_ enabled: Bool) -> some View {
        environment(\.tutorialMode, enabled)
    }

    /// Injects the current tutorial phase into the environment
    func tutorialPhase(_ phase: TutorialPhase?) -> some View {
        environment(\.tutorialPhase, phase)
    }

    /// Injects the tutorial state manager into the environment
    func tutorialStateManager(_ manager: TutorialStateManager?) -> some View {
        environment(\.tutorialStateManager, manager)
    }
}
