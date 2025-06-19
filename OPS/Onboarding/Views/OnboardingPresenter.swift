//
//  OnboardingPresenter.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI
import Combine
import SwiftData

/// Manages the presentation of the onboarding flow
struct OnboardingPresenter: View {
    @State private var showOnboarding: Bool = false
    @EnvironmentObject private var dataController: DataController
    
    // Create notification observer
    private let showOnboardingPublisher = NotificationCenter.default.publisher(for: Notification.Name("ShowOnboarding"))
    private let dismissOnboardingPublisher = NotificationCenter.default.publisher(for: Notification.Name("DismissOnboarding"))
    
    var body: some View {
        ZStack {
            // Only show if triggered
            if showOnboarding {
                // Use the unified container - it handles flow selection internally
                OnboardingView()
                    .environmentObject(dataController)
                    .transition(.opacity)
                    .zIndex(2) // Ensure it appears above other content
            }
        }
        .animation(.easeInOut, value: showOnboarding)
        .onReceive(showOnboardingPublisher) { _ in
            showOnboarding = true
        }
        .onReceive(dismissOnboardingPublisher) { _ in
            showOnboarding = false
        }
        .onAppear {
            // Debug log to confirm the presenter is loaded
        }
    }
}

// Extension to make it easy to add onboarding to any view
extension View {
    func withOnboarding() -> some View {
        ZStack {
            self
            OnboardingPresenter()
        }
    }
    
    /// Trigger the onboarding flow from any view
    func showOnboarding() {
        NotificationCenter.default.post(name: Notification.Name("ShowOnboarding"), object: nil)
    }
    
    /// Dismiss the onboarding flow from any view
    func dismissOnboarding() {
        NotificationCenter.default.post(name: Notification.Name("DismissOnboarding"), object: nil)
    }
}