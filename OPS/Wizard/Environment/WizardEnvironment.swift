//
//  WizardEnvironment.swift
//  OPS
//
//  Environment keys for the wizard system.
//  Allows child views to detect active wizards and current step.
//

import SwiftUI

// MARK: - Wizard Active Environment Key

struct WizardActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - Wizard State Manager Environment Key

struct WizardStateManagerKey: EnvironmentKey {
    static let defaultValue: WizardStateManager? = nil
}

extension EnvironmentValues {
    /// Whether a wizard is currently active
    var wizardActive: Bool {
        get { self[WizardActiveKey.self] }
        set { self[WizardActiveKey.self] = newValue }
    }

    /// The wizard state manager, nil when no wizard system is initialized
    var wizardStateManager: WizardStateManager? {
        get { self[WizardStateManagerKey.self] }
        set { self[WizardStateManagerKey.self] = newValue }
    }
}

// MARK: - View Extensions

extension View {
    /// Injects wizard active state into the environment
    func wizardActive(_ active: Bool) -> some View {
        environment(\.wizardActive, active)
    }

    /// Injects the wizard state manager into the environment
    func wizardStateManager(_ manager: WizardStateManager?) -> some View {
        environment(\.wizardStateManager, manager)
    }
}
