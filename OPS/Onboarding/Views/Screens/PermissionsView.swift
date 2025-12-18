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
    @State private var isRequestingLocation = false
    @State private var isRequestingNotifications = false
    @State private var showLocationDeniedAlert = false
    @State private var showNotificationDeniedAlert = false
    @State private var currentPhase: PermissionPhase = .location
    
    enum PermissionPhase {
        case location
        case notifications
    }
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return viewModel.currentStep.stepNumber(for: viewModel.selectedUserType) ?? 5
    }
    
    private var totalSteps: Int {
        guard let userType = viewModel.selectedUserType else { return 7 }
        return OnboardingStep.totalSteps(for: userType)
    }
    
    var body: some View {
        ZStack {
            // Background color - conditional theming
            (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Navigation bar
                HStack {
                    Button(action: {
                        viewModel.moveToPreviousStep()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(OPSStyle.Typography.button)
                            Text("Back")
                                .font(OPSStyle.Typography.button)
                        }
                        .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.logoutAndReturnToLogin()
                    }) {
                        Text("Cancel")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ?
                                  (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText) :
                                    (viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText.opacity(0.3) : OPSStyle.Colors.secondaryText.opacity(0.3)))
                            .frame(height: 2)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                
                // Two-phase permissions content
                VStack(spacing: 0) {
                    if currentPhase == .location {
                        // Location permission phase
                        LocationPermissionPhase(
                            viewModel: viewModel,
                            isRequestingLocation: $isRequestingLocation,
                            showLocationDeniedAlert: $showLocationDeniedAlert,
                            onContinue: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentPhase = .notifications
                                }
                            }
                        )
                    } else {
                        // Notifications permission phase
                        NotificationPermissionPhase(
                            viewModel: viewModel,
                            isRequestingNotifications: $isRequestingNotifications,
                            showNotificationDeniedAlert: $showNotificationDeniedAlert,
                            onContinue: {
                                viewModel.moveToNextStep()
                            }
                        )
                    }
                }
            }
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

// MARK: - Location Permission Phase
struct LocationPermissionPhase: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Binding var isRequestingLocation: Bool
    @Binding var showLocationDeniedAlert: Bool
    let onContinue: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("LOCATION ACCESS")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            
            Spacer()
            
            HStack {
                Spacer()
                
                // Location icon and animation
                ZStack{
                    // Ripple circles animation
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(OPSStyle.Colors.primaryAccent.opacity(0.2), lineWidth: 1)
                            .frame(width: 100 + CGFloat(index * 50), height: 100 + CGFloat(index * 50))
                    }
                    
                    // Location pin
                    Image(systemName: "location")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .frame(height: 200)
                
                Spacer()
            }
            
            Spacer()
            
            // Info box
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: OPSStyle.Icons.info)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .font(OPSStyle.Typography.body)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why we need this:".uppercased())
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)

                        Text("• Show nearby job sites".uppercased())
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)

                        Text("• Navigate to sites".uppercased())
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)

                        Text("• Help crew find you".uppercased())
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                    }
                    Spacer()
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(viewModel.shouldUseLightTheme ? Color.white : Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(viewModel.shouldUseLightTheme ? OPSStyle.Colors.cardBackground : Color.clear, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            
            Spacer()
            
            // Continue button for location
            Button(action: {
                isRequestingLocation = true
                viewModel.requestLocationPermission { isAllowed in
                    // Check immediately if permission was denied
                    if !isAllowed {
                        DispatchQueue.main.async {
                            showLocationDeniedAlert = true
                            isRequestingLocation = false
                        }
                    } else {
                        // Permission granted or still pending, move to next phase after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            onContinue()
                            isRequestingLocation = false
                        }
                    }
                }
            }) {
                HStack {
                    Text("CONTINUE")
                        .font(OPSStyle.Typography.bodyBold)
                        .opacity(isRequestingLocation ? 0 : 1)
                    
                    if isRequestingLocation {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    }
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                )
            }
            .disabled(isRequestingLocation)
        }
        .padding(40)
        .transition(.opacity)
    }
}

// MARK: - Notification Permission Phase
struct NotificationPermissionPhase: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @Binding var isRequestingNotifications: Bool
    @Binding var showNotificationDeniedAlert: Bool
    let onContinue: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("STAY UPDATED")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            
            Spacer()
            
            HStack{
                Spacer()
                // Notification icon and animation
                ZStack {
                    // Notification bell
                    Image(systemName: "bell")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    // Notification badge
                    Circle()
                        .fill(OPSStyle.Colors.errorStatus)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text("1")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(.white)
                        )
                        .offset(x: 25, y: -25)
                }
                .frame(height: 200)
                
                Spacer()
            }
            
            Spacer()
            
            // Info box
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: OPSStyle.Icons.info)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .font(OPSStyle.Typography.body)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why we need this:".uppercased())
                            .font(OPSStyle.Typography.cardTitle)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)

                        Text("• Job assignments".uppercased())
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)

                        Text("• Schedule changes".uppercased())
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)

                        Text("• Crew messages".uppercased())
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                    }
                    
                    Spacer()
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(viewModel.shouldUseLightTheme ? Color.white : Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(viewModel.shouldUseLightTheme ? OPSStyle.Colors.cardBackground : Color.clear, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            
            Spacer()
            
            // Continue button for notifications
            Button(action: {
                isRequestingNotifications = true
                viewModel.requestNotificationsPermission()
                
                // After requesting permission, proceed to next step
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    // Store permission status
                    UserDefaults.standard.set(viewModel.isLocationPermissionGranted, forKey: "location_permission_granted")
                    UserDefaults.standard.set(viewModel.isNotificationsPermissionGranted, forKey: "notifications_permission_granted")
                    
                    // Proceed to field setup step
                    onContinue()
                    isRequestingNotifications = false
                    
                    // Check if permission was denied
                    UNUserNotificationCenter.current().getNotificationSettings { settings in
                        DispatchQueue.main.async {
                            if settings.authorizationStatus == .denied {
                                showNotificationDeniedAlert = true
                            }
                        }
                    }
                }
            }) {
                HStack {
                    Text("CONTINUE")
                        .font(OPSStyle.Typography.bodyBold)
                        .opacity(isRequestingNotifications ? 0 : 1)
                    
                    if isRequestingNotifications {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    }
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                )
            }
            .disabled(isRequestingNotifications)
        }
        .padding(40)
        .transition(.opacity)
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