//
//  ConsolidatedPermissionsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI

struct ConsolidatedPermissionsView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Navigation header with step indicator
                HStack {
                    Button(action: {
                        viewModel.moveToPreviousStepV2()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                            Text("Back")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    
                    Spacer()
                    
                    Text("Step 5 of 7")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.gray)
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, 24)
                
                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<7) { step in
                        Rectangle()
                            .fill(step < 5 ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.4))
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 24)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enable")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("permissions.")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.bottom, 12)
                            
                            Text("OPS works best with location and notification permissions enabled. These help you stay updated on projects and navigate to job sites.")
                                .font(.system(size: 16))
                                .foregroundColor(Color.gray)
                                .lineSpacing(4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 30)
                        
                        // Location Permission Card
                        PermissionCard(
                            title: "Location Services",
                            description: "Enables navigation to job sites, helps coordinate with your team, and optimizes your route planning.",
                            icon: "location.fill",
                            isEnabled: viewModel.isLocationPermissionGranted,
                            actionButtonText: viewModel.isLocationPermissionGranted ? "Enabled" : "Enable",
                            onActionTapped: {
                                requestLocationPermission()
                            }
                        )
                        
                        // Notifications Permission Card
                        PermissionCard(
                            title: "Notifications",
                            description: "Receive updates about job schedules, new assignments, and team communication.",
                            icon: "bell.fill",
                            isEnabled: viewModel.isNotificationsPermissionGranted,
                            actionButtonText: viewModel.isNotificationsPermissionGranted ? "Enabled" : "Enable",
                            onActionTapped: {
                                requestNotificationsPermission()
                            }
                        )
                        
                        // Skip note
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.system(size: 14))
                            
                            Text("You can enable these permissions later in Settings, but some features will be limited.")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.top, 20)
                        
                        Spacer()
                        
                        // Navigation buttons
                        OnboardingNavigationButtons(
                            primaryText: "Continue",
                            secondaryText: "Skip for Now",
                            onPrimaryTapped: {
                                print("ConsolidatedPermissionsView: Continue button tapped")
                                viewModel.moveToNextStepV2()
                            },
                            onSecondaryTapped: {
                                print("ConsolidatedPermissionsView: Skip button tapped")
                                viewModel.moveToNextStepV2()
                            }
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
        }
    }
    
    private func requestLocationPermission() {
        // Note: In a real implementation, this would use LocationManager
        // to request actual location permissions from the user.
        // For now, we'll just set the flag
        viewModel.isLocationPermissionGranted = true
    }
    
    private func requestNotificationsPermission() {
        // Note: In a real implementation, this would use UserNotifications framework
        // to request actual notification permissions from the user.
        // For now, we'll just set the flag
        viewModel.requestNotificationsPermission()
    }
}

struct PermissionCard: View {
    let title: String
    let description: String
    let icon: String
    let isEnabled: Bool
    let actionButtonText: String
    let onActionTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Icon and title
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(isEnabled ? .green : .white)
                    .frame(width: 32, height: 32)
                
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Status indicator
                if isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                }
            }
            
            // Description
            Text(description)
                .font(.system(size: 15))
                .foregroundColor(.gray)
                .lineSpacing(4)
                .padding(.leading, 44)
            
            // Action button
            Button(action: onActionTapped) {
                Text(actionButtonText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        isEnabled ?
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green.opacity(0.7), Color.green]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.9), Color.white]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .cornerRadius(8)
            }
            .padding(.top, 8)
            .disabled(isEnabled)
        }
        .padding(20)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(12)
    }
}

#Preview {
    let viewModel = OnboardingViewModel()
    viewModel.isLocationPermissionGranted = false
    viewModel.isNotificationsPermissionGranted = true
    
    return ConsolidatedPermissionsView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}