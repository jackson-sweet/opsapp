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
    var isInConsolidatedFlow: Bool = true
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
                    // Two-phase permissions view
                    VStack(spacing: 0) {
                        if currentPhase == .location {
                            // Location permission phase
                            VStack(alignment: .leading, spacing: 24) {
                                // Header
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("LOCATION ACCESS")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
                                    
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 40)
                                
                                
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
                                        Image(systemName: "info.circle.fill")
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            .font(OPSStyle.Typography.body)
                                        
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Why we need location access:".uppercased())
                                                .font(OPSStyle.Typography.cardTitle)
                                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
                                            
                                            Text("• Show nearby job sites on the map".uppercased())
                                                .font(OPSStyle.Typography.cardBody)
                                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                                            
                                            Text("• Navigate to work locations".uppercased())
                                                .font(OPSStyle.Typography.cardBody)
                                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                                            
                                            Text("• Help teammates find you in the field".uppercased())
                                                .font(OPSStyle.Typography.cardBody)
                                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                                            
                                        }
                                        Spacer()
                                    }
                                }
                                .padding(16)
                                .background(viewModel.shouldUseLightTheme ? Color.white : Color.clear)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(viewModel.shouldUseLightTheme ? OPSStyle.Colors.cardBackground : Color.clear, lineWidth: 1)
                                )
                                .padding(.horizontal, 24)
                                
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
                                                withAnimation(.easeInOut(duration: 0.3)) {
                                                    currentPhase = .notifications
                                                }
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
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                    )
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 40)
                                .disabled(isRequestingLocation)
                            }
                            .transition(.opacity)
                        } else {
                            
                            // Notifications permission phase
                            VStack(alignment: .leading, spacing: 24) {
                                // Header
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("GET NOTIFIED")
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
                                    
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 40)
                                
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
                                        Image(systemName: "info.circle.fill")
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            .font(OPSStyle.Typography.body)
                                        
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Why we need notifications:".uppercased())
                                                .font(OPSStyle.Typography.cardTitle)
                                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
                                            
                                            Text("• Job assignments and updates".uppercased())
                                                .font(OPSStyle.Typography.cardBody)
                                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                                            
                                            Text("• Schedule changes and reminders".uppercased())
                                                .font(OPSStyle.Typography.cardBody)
                                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                                            
                                            Text("• Important team messages".uppercased())
                                                .font(OPSStyle.Typography.cardBody)
                                                .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                                            
                                            
                                        }
                                        
                                        
                                        Spacer()
                                    }
                                }
                                .padding(16)
                                .background(viewModel.shouldUseLightTheme ? Color.white : Color.clear)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(viewModel.shouldUseLightTheme ? OPSStyle.Colors.cardBackground : Color.clear, lineWidth: 1)
                                )
                                .padding(.horizontal, 24)
                                
                                
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
                                        viewModel.moveToNextStepV2()
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
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                    )
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 40)
                                .disabled(isRequestingNotifications)
                            }
                            .transition(.opacity)
                        }
                    }
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
                            // Request location permission with completion handler
                            viewModel.requestLocationPermission { isAllowed in
                                if !isAllowed {
                                    // Permission was denied, show alert immediately
                                    DispatchQueue.main.async {
                                        showLocationDeniedAlert = true
                                    }
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
