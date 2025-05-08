//
//  OnboardingEnvironmentKey.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

// Environment key to toggle between onboarding flows
struct UseConsolidatedOnboardingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var useConsolidatedOnboarding: Bool {
        get { self[UseConsolidatedOnboardingKey.self] }
        set { self[UseConsolidatedOnboardingKey.self] = newValue }
    }
}