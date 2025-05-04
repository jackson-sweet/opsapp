//
//  LocationPermissionView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI
import CoreLocation

struct LocationPermissionView: View {
    @ObservedObject var locationManager: LocationManager
    @Binding var isPresented: Bool
    var onRequestPermission: () -> Void
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "location.fill")
                    .font(.system(size: 60))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding()
                
                // Title
                Text("Location Access Required")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.center)
                
                // Description
                VStack(alignment: .leading, spacing: 12) {
                    PermissionBulletPoint(
                        icon: "map.fill",
                        text: "Navigation to project sites"
                    )
                    
                    PermissionBulletPoint(
                        icon: "location.fill",
                        text: "Track work location for accurate reporting"
                    )
                    
                    PermissionBulletPoint(
                        icon: "clock.fill",
                        text: "Calculate travel time and directions"
                    )
                }
                .padding(.horizontal)
                
                // Permission status message
                Group {
                    switch locationManager.authorizationStatus {
                    case .denied, .restricted:
                        Text("Location permission has been denied. Please enable it in Settings.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                    case .notDetermined:
                        Text("OPS needs location access to help you navigate to projects and track your work.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                    default:
                        EmptyView()
                    }
                }
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                        // Settings button
                        Button(action: {
                            locationManager.openAppSettings()
                        }) {
                            Text("Open Settings")
                                .font(OPSStyle.Typography.bodyBold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(OPSStyle.Colors.primaryAccent)
                                .foregroundColor(.white)
                                .cornerRadius(OPSStyle.Layout.buttonRadius)
                        }
                        
                        // Skip button
                        Button(action: {
                            isPresented = false
                        }) {
                            Text("Continue Without Location")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.vertical, 8)
                        
                    } else {
                        // Request permission button
                        Button(action: {
                            onRequestPermission()
                        }) {
                            Text("Enable Location Access")
                                .font(OPSStyle.Typography.bodyBold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(OPSStyle.Colors.primaryAccent)
                                .foregroundColor(.white)
                                .cornerRadius(OPSStyle.Layout.buttonRadius)
                        }
                        
                        // Skip button
                        Button(action: {
                            isPresented = false
                        }) {
                            Text("Not Now")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackground)
            )
            .shadow(radius: 20)
            .padding(24)
        }
    }
}

struct PermissionBulletPoint: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 24)
            
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }
}

// Modifier to present the location permission view as an overlay
extension View {
    func locationPermissionOverlay(
        isPresented: Binding<Bool>,
        locationManager: LocationManager,
        onRequestPermission: @escaping () -> Void
    ) -> some View {
        self.overlay(
            ZStack {
                if isPresented.wrappedValue {
                    LocationPermissionView(
                        locationManager: locationManager,
                        isPresented: isPresented,
                        onRequestPermission: onRequestPermission
                    )
                }
            }
        )
    }
}