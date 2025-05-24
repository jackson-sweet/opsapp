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
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Navigation bar for consolidated flow
                if isInConsolidatedFlow {
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
                        
                        Text("Step 4 of 6")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.gray)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    
                    // Step indicator bars
                    HStack(spacing: 4) {
                        ForEach(0..<6) { step in
                            Rectangle()
                                .fill(step <= 3 ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.4))
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
                                Text("App Permissions")
                                    .font(OPSStyle.Typography.title)
                                    .foregroundColor(.white)
                                
                                Text("These permissions help OPS work better in the field.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(Color.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Location permission
                            VStack(alignment: .leading, spacing: 12) {
                                Text("LOCATION")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color.gray)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "location.fill")
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            .font(.system(size: 20))
                                        
                                        Text("Location Access")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            isRequestingLocation = true
                                            viewModel.requestLocationPermission()
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
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(Color.gray)
                                }
                                .padding()
                                .background(Color(white: 0.15))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            
                            // Notification permission
                            VStack(alignment: .leading, spacing: 12) {
                                Text("NOTIFICATIONS")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color.gray)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "bell.fill")
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            .font(.system(size: 20))
                                        
                                        Text("Push Notifications")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            isRequestingNotifications = true
                                            viewModel.requestNotificationsPermission()
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
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(Color.gray)
                                }
                                .padding()
                                .background(Color(white: 0.15))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            
                            // Info message
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .font(.system(size: 16))
                                
                                Text("You can change these permissions later in your device settings if needed.")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(Color.gray)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Consolidated flow continue button
                    Button(action: {
                        // Store permission status
                        UserDefaults.standard.set(viewModel.isLocationPermissionGranted, forKey: "location_permission_granted")
                        UserDefaults.standard.set(viewModel.isNotificationsPermissionGranted, forKey: "notifications_permission_granted")
                        
                        // Proceed to field setup step
                        viewModel.moveToNextStepV2()
                    }) {
                        Text("CONTINUE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                            .padding()
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .frame(maxWidth: .infinity)
                            .background(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                } else {
                    // Original permissions view
                    VStack(spacing: 24) {
                        // Header
                        OnboardingHeaderView(
                            title: "We also need access to Location",
                            subtitle: "Your location will keep you and your teammates moving as a unit, allowing nearby crew to reach out for help, or coordinate material runs."
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
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                        }
                        .frame(height: 240)
                        
                        Spacer()
                        
                        // Warning box
                        VStack(spacing: 16) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Color.yellow)
                                    .font(.system(size: 24))
                                
                                Text("It is very important that you choose the \"Always Allow\" option in the next dialog. This will allow your teammates to locate you and improve comms.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.yellow, lineWidth: 1)
                        )
                        .cornerRadius(8)
                        
                        // Buttons
                        Button(action: {
                            print("PermissionsView: Allow location access button tapped")
                            // For testing, simulate permission granted and move to next step
                            viewModel.isLocationPermissionGranted = true
                            
                            // Go to next step
                            viewModel.moveToNextStep()
                        }) {
                            Text("ALLOW LOCATION ACCESS")
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OPSStyle.Colors.primaryAccent)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.top, 24)
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
    
    return PermissionsView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}