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

// MARK: - Wizard Trigger Service Environment Key

struct WizardTriggerServiceKey: EnvironmentKey {
    static let defaultValue: WizardTriggerService? = nil
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

    /// The wizard trigger service, nil when not yet configured
    var wizardTriggerService: WizardTriggerService? {
        get { self[WizardTriggerServiceKey.self] }
        set { self[WizardTriggerServiceKey.self] = newValue }
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

    /// Injects the wizard trigger service into the environment
    func wizardTriggerService(_ service: WizardTriggerService?) -> some View {
        environment(\.wizardTriggerService, service)
    }
}
