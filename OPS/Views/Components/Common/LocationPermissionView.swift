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
            OPSStyle.Colors.imageOverlay
                .ignoresSafeArea()
            
            VStack(spacing: OPSStyle.Layout.spacing4) {
                // Icon
                Image(systemName: "location.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding()
                
                // Title
                Text("Location Access Required")
                    .font(OPSStyle.Typography.pageTitle)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                    .multilineTextAlignment(.center)
                
                // Description
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
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
                VStack(spacing: OPSStyle.Layout.spacing2_5) {
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
                                .foregroundColor(OPSStyle.Colors.primaryText)
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
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        
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
                                .foregroundColor(OPSStyle.Colors.primaryText)
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
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                    }
                }
            }
            .padding(OPSStyle.Layout.spacing4)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackground)
            )
            .padding(OPSStyle.Layout.spacing4)
        }
    }
}

struct PermissionBulletPoint: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
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