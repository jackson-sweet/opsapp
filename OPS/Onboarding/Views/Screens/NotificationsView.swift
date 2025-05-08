//
//  NotificationsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-06.
//

import SwiftUI
import UserNotifications

struct NotificationsView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                // Header
                OnboardingHeaderView(
                    title: "Enable Push Notifications",
                    subtitle: "Get real-time project updates, important announcements, and stay informed about changes to your schedule."
                )
                
                // Illustration
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 100))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.top, 20)
                
                Spacer()
                
                // Buttons
                OnboardingNavigationButtons(
                    primaryText: "ENABLE NOTIFICATIONS",
                    secondaryText: "SKIP",
                    isPrimaryDisabled: false,
                    isLoading: viewModel.isLoading,
                    onPrimaryTapped: {
                        print("NotificationsView: Enable button tapped")
                        requestNotificationPermission()
                    },
                    onSecondaryTapped: {
                        print("NotificationsView: Skip button tapped")
                        // Skip notifications but continue
                        viewModel.moveToNextStep()
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 30)
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                viewModel.isNotificationsPermissionGranted = granted
                print("NotificationsView: Notifications permission \(granted ? "granted" : "denied")")
                
                // Move to next step regardless of permission result
                viewModel.moveToNextStep()
            }
        }
    }
}

// MARK: - Preview
#Preview("Notifications Screen") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    viewModel.phoneNumber = "5551234567"
    viewModel.isLocationPermissionGranted = true
    
    return NotificationsView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}