//
//  PermissionsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI
import UserNotifications
import CoreLocation

struct PermissionsView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var isInConsolidatedFlow: Bool = false
    @State private var isRequestingLocation = false
    @State private var isRequestingNotifications = false
    @State private var showLocationDeniedAlert = false
    @State private var showNotificationDeniedAlert = false
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        if viewModel.selectedUserType == .employee {
            return 5 // Employee flow position - after company code
        } else {
            return 8 // Company flow position - after team invites (adjusted after removing logo step)
        }
    }
    
    private var totalSteps: Int {
        if viewModel.selectedUserType == .employee {
            return 8 // Employee flow has 8 total steps
        } else {
            return 9 // Company flow has 9 total steps (reduced from 10 after removing logo step)
        }
    }
    
    var body: some View {
        ZStack {
            // Background color - conditional theming
            (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Navigation bar for consolidated flow
                if isInConsolidatedFlow {
                    HStack {
                        Button(action: {
                            viewModel.moveToPreviousStepV2()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(OPSStyle.Typography.captionBold)
                                Text("Back")
                                    .font(OPSStyle.Typography.bodyBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.logoutAndReturnToLogin()
                        }) {
                            Text("Sign Out")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    
                    // Step indicator bars
                    HStack(spacing: 4) {
                        ForEach(0..<totalSteps, id: \.self) { step in
                            Rectangle()
                                .fill(step < currentStepNumber ? 
                                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent) : 
                                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.4) : OPSStyle.Colors.secondaryText.opacity(0.4)))
                                .frame(height: 4)
                        }
                    }
                    .padding(.bottom, 16)
                }
                
                // Content area
                if isInConsolidatedFlow {
                    // Consolidated permissions view
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Header
                            VStack(alignment: .leading, spacing: 8) {
                                Text("APP PERMISSIONS")
                                    .font(OPSStyle.Typography.title)
                                    .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
                                
                                Text("These permissions help OPS work better in the field.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Location permission
                            VStack(alignment: .leading, spacing: 12) {
                                Text("LOCATION")
                                    .font(OPSStyle.Typography.cardSubtitle)
                                    .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : Color.gray)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "location.fill")
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            .font(OPSStyle.Typography.subtitle)
                                        
                                        Text("LOCATION ACCESS")
                                            .font(OPSStyle.Typography.cardSubtitle)
                                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : .white)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            isRequestingLocation = true
                                            viewModel.requestLocationPermission()
                                            
                                            // Check for denied status after a delay
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                if viewModel.locationManager.authorizationStatus == .denied || 
                                                   viewModel.locationManager.authorizationStatus == .restricted {
                                                    showLocationDeniedAlert = true
                                                }
                                            }
                                        }) {
                                            Text(viewModel.isLocationPermissionGranted ? "Granted" : "Allow")
                                                .font(OPSStyle.Typography.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(viewModel.isLocationPermissionGranted ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)
                                                .foregroundColor(.white)
                                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        }
                                        .opacity(isRequestingLocation ? 0.5 : 1)
                                        .disabled(isRequestingLocation)
                                    }
                                    
                                    Text("Shows nearby jobs and enables navigation to job sites. Most useful in 'Always Allow' mode.")
                                        .font(OPSStyle.Typography.cardBody)
                                        .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : Color.gray)
                                }
                                .padding()
                                .background(viewModel.shouldUseLightTheme ? Color.white : Color(white: 0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(viewModel.shouldUseLightTheme ? OPSStyle.Colors.cardBackground : Color.clear, lineWidth: 1)
                                )
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            
                            // Notification permission
                            VStack(alignment: .leading, spacing: 12) {
                                Text("NOTIFICATIONS")
                                    .font(OPSStyle.Typography.cardSubtitle)
                                    .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : Color.gray)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "bell.fill")
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            .font(OPSStyle.Typography.subtitle)
                                        
                                        Text("PUSH NOTIFICATIONS")
                                            .font(OPSStyle.Typography.cardSubtitle)
                                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : .white)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            isRequestingNotifications = true
                                            viewModel.requestNotificationsPermission()
                                            
                                            // Check for denied status after a delay
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                UNUserNotificationCenter.current().getNotificationSettings { settings in
                                                    DispatchQueue.main.async {
                                                        if settings.authorizationStatus == .denied {
                                                            showNotificationDeniedAlert = true
                                                        }
                                                    }
                                                }
                                            }
                                        }) {
                                            Text(viewModel.isNotificationsPermissionGranted ? "Granted" : "Allow")
                                                .font(OPSStyle.Typography.caption)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(viewModel.isNotificationsPermissionGranted ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)
                                                .foregroundColor(.white)
                                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        }
                                        .opacity(isRequestingNotifications ? 0.5 : 1)
                                        .disabled(isRequestingNotifications)
                                    }
                                    
                                    Text("Get updates about your jobs and team activities. Critical for staying informed about schedule changes.")
                                        .font(OPSStyle.Typography.cardBody)
                                        .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : Color.gray)
                                }
                                .padding()
                                .background(viewModel.shouldUseLightTheme ? Color.white : Color(white: 0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(viewModel.shouldUseLightTheme ? OPSStyle.Colors.cardBackground : Color.clear, lineWidth: 1)
                                )
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            
                            // Info message
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .font(OPSStyle.Typography.body)
                                
                                Text("You can change these permissions later in your device settings if needed.")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : Color.gray)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Consolidated flow continue button
                    StandardContinueButton(
                        onTap: {
                            // Store permission status
                            UserDefaults.standard.set(viewModel.isLocationPermissionGranted, forKey: "location_permission_granted")
                            UserDefaults.standard.set(viewModel.isNotificationsPermissionGranted, forKey: "notifications_permission_granted")
                            
                            // Proceed to field setup step
                            viewModel.moveToNextStepV2()
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                } else {
                    // Original permissions view
                    // Navigation header with step indicator
                    HStack {
                        Button(action: {
                            viewModel.previousStep()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(OPSStyle.Typography.caption)
                                Text("Back")
                                    .font(OPSStyle.Typography.body)
                            }
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.logoutAndReturnToLogin()
                        }) {
                            Text("Sign Out")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 24)
                    
                    // Step indicator bars
                    HStack(spacing: 4) {
                        ForEach(0..<totalSteps, id: \.self) { step in
                            Rectangle()
                                .fill(step < currentStepNumber ? 
                                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryAccent : OPSStyle.Colors.primaryAccent) : 
                                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.4) : OPSStyle.Colors.secondaryText.opacity(0.4)))
                                .frame(height: 4)
                        }
                    }
                    .padding(.bottom, 16)
                    .padding(.horizontal, 24)
                    
                    VStack(spacing: 24) {
                        // Header
                        OnboardingHeaderView(
                            title: "We also need access to Location",
                            subtitle: "Your location will keep you and your teammates moving as a unit, allowing nearby crew to reach out for help, or coordinate material runs.",
                            isLightTheme: viewModel.shouldUseLightTheme
                        )
                        
                        Spacer()
                        
                        // Location icon and animation
                        ZStack {
                            // Ripple circles animation
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    .frame(width: 120 + CGFloat(index * 60), height: 120 + CGFloat(index * 60))
                            }
                            
                            // Location pin
                            Image(systemName: "location.fill")
                                .font(OPSStyle.Typography.largeTitle)
                                .foregroundColor(.white)
                        }
                        .frame(height: 240)
                        
                        Spacer()
                        
                        // Warning box
                        VStack(spacing: 16) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Color.yellow)
                                    .font(OPSStyle.Typography.title)
                                
                                Text("It is very important that you choose the \"Always Allow\" option in the next dialog. This will allow your teammates to locate you and improve comms.")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : .white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .background(viewModel.shouldUseLightTheme ? Color.white : Color.black.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.yellow, lineWidth: 1)
                        )
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        
                        // Buttons
                        Button(action: {
                            print("PermissionsView: Allow location access button tapped")
                            // Request location permission
                            viewModel.requestLocationPermission()
                            
                            // Check for denied status after a delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                if viewModel.locationManager.authorizationStatus == .denied || 
                                   viewModel.locationManager.authorizationStatus == .restricted {
                                    showLocationDeniedAlert = true
                                }
                            }
                        }) {
                            Text("ALLOW LOCATION ACCESS")
                                .font(OPSStyle.Typography.bodyBold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OPSStyle.Colors.primaryAccent)
                                .foregroundColor(.white)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                        .padding(.top, 24)
                        
                        // Continue button
                        StandardContinueButton(
                            onTap: {
                                viewModel.moveToNextStep()
                            }
                        )
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
            }
            .padding(.horizontal, isInConsolidatedFlow ? OPSStyle.Layout.spacing3 : 0)
            .onChange(of: viewModel.isLocationPermissionGranted) { _, _ in
                isRequestingLocation = false
            }
            .onChange(of: viewModel.isNotificationsPermissionGranted) { _, _ in
                isRequestingNotifications = false
            }
        }
        // Location Permission Denied Alert
        .alert("Location Access Required", isPresented: $showLocationDeniedAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("OPS needs location access to show nearby jobs and navigate to job sites. Please enable location access in Settings to use these features.")
        }
        // Notification Permission Denied Alert
        .alert("Notifications Required", isPresented: $showNotificationDeniedAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("OPS needs notification access to keep you updated about schedule changes and job assignments. Please enable notifications in Settings.")
        }
    }
}

// MARK: - Preview
#Preview("Permissions Screen") {
    let viewModel: OnboardingViewModel = {
        let vm = OnboardingViewModel()
        vm.email = "user@example.com"
        vm.password = "password123"
        vm.firstName = "John"
        vm.lastName = "Doe"
        vm.phoneNumber = "5551234567"
        vm.companyName = "Demo Company, Inc."
        return vm
    }()
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    return PermissionsView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(dataController)
        .environment(\.colorScheme, .dark)
}