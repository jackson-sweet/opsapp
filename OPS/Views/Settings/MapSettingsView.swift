//
//  MapSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-12.
//

import SwiftUI
import CoreLocation

struct MapSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var locationManager: LocationManager
    
    // Map settings preferences
    @AppStorage("mapAutoZoom") private var mapAutoZoom = true
    @AppStorage("mapAutoCenter") private var mapAutoCenter = true
    @AppStorage("map3DBuildings") private var map3DBuildings = false
    @AppStorage("mapTrafficDisplay") private var mapTrafficDisplay = false
    @AppStorage("mapDefaultType") private var mapDefaultType = "standard"
    
    // New configurable settings for re-centering and zoom levels
    @AppStorage("mapAutoCenterTime") private var mapAutoCenterTime = "10" // "off", "2", "5", "10" seconds
    @AppStorage("mapZoomLevel") private var mapZoomLevel = "medium" // "close", "medium", "far"
    
    
    // Map types for picker
    private let mapTypes = ["standard", "satellite", "hybrid"]
    private let mapTypeLabels = ["Standard", "Satellite", "Hybrid"]
    
    // Auto center time options
    private let autoCenterTimes = ["off", "2", "5", "10"]
    private let autoCenterLabels = ["Off", "2 sec", "5 sec", "10 sec"]
    
    // Zoom level options
    private let zoomLevels = ["close", "medium", "far"]
    private let zoomLevelLabels = ["Close", "Medium", "Far"]
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            // Main content layout with fixed header
            VStack(spacing: 0) {
                // Header - Always visible, not part of ScrollView
                SettingsHeader(
                    title: "Maps",
                    onBackTapped: {
                        dismiss()
                    }
                )
                .padding(.bottom, 8)
                
                // Content - Scrollable when needed
                ScrollView {
                    VStack(spacing: 20) {
                        // Location Permission Status Card
                        locationStatusCard
                        
                        // Map Features
                        SettingsSectionHeader(title: "MAP FEATURES")
                        
                        SettingsCard(title: "", showTitle: false) {
                            VStack(spacing: 0) {
                                SettingsToggle(
                                    title: "Auto Zoom",
                                    description: "Automatically zoom to fit all markers",
                                    isOn: $mapAutoZoom
                                )
                                
                                Divider()
                                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                                    .padding(.vertical, 8)
                                
                                SettingsToggle(
                                    title: "Auto Center/Rotate",
                                    description: "Re-center map when moving between projects",
                                    isOn: $mapAutoCenter
                                )
                                
                                Divider()
                                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                                    .padding(.vertical, 8)
                                
                                // Auto-center time picker
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Auto Re-center Time")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.white)
                                        
                                        Text("Time before the map automatically re-centers")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                    
                                    SegmentedControl(
                                        selection: $mapAutoCenterTime,
                                        options: Array(zip(autoCenterTimes, autoCenterLabels))
                                    )
                                    .disabled(!mapAutoCenter) // Disable when auto-center is off
                                    .opacity(mapAutoCenter ? 1.0 : 0.6)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 16)
                                
                                Divider()
                                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                                    .padding(.vertical, 8)
                                
                                // Zoom level picker 
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Auto Zoom Level")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.white)
                                        
                                        Text("Default zoom level when showing projects")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                    
                                    SegmentedControl(
                                        selection: $mapZoomLevel,
                                        options: Array(zip(zoomLevels, zoomLevelLabels))
                                    )
                                    .disabled(!mapAutoZoom) // Disable when auto-zoom is off
                                    .opacity(mapAutoZoom ? 1.0 : 0.6)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 16)
                            }
                            .padding(.horizontal, -16) // Counteract card padding
                        }
                        
                        // Map Display
                        SettingsSectionHeader(title: "MAP DISPLAY")
                        
                        SettingsCard(title: "", showTitle: false) {
                            VStack(spacing: 0) {
                                // Map type picker
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Map Type")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.white)
                                        
                                        Text("Choose the map display style")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                    }
                                    
                                    SegmentedControl(
                                        selection: $mapDefaultType,
                                        options: Array(zip(mapTypes, mapTypeLabels))
                                    )
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 16)
                                
                                Divider()
                                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                                    .padding(.vertical, 8)
                                
                                SettingsToggle(
                                    title: "3D Buildings",
                                    description: "Show 3D building models on map",
                                    isOn: $map3DBuildings
                                )
                                
                                Divider()
                                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                                    .padding(.vertical, 8)
                                
                                SettingsToggle(
                                    title: "Traffic Display",
                                    description: "Show traffic conditions on map",
                                    isOn: $mapTrafficDisplay
                                )
                            }
                            .padding(.horizontal, -16) // Counteract card padding
                        }
                        
                        // Reset to defaults button
                        SettingsButton(
                            title: "Reset to Defaults",
                            icon: "arrow.clockwise",
                            style: .secondary
                        ) {
                            resetToDefaults()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                    .padding(.vertical, 24)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Request current location authorization status
            locationManager.requestPermissionIfNeeded(requestAlways: false)
        }
        .onChange(of: mapAutoCenterTime) { _, newValue in
            // Force UserDefaults to synchronize immediately
            UserDefaults.standard.synchronize()
        }
        .onChange(of: mapAutoCenter) { _, newValue in
            UserDefaults.standard.synchronize()
        }
        .onChange(of: mapZoomLevel) { _, newValue in
            UserDefaults.standard.synchronize()
        }
    }
    
    // MARK: - Location Status Card
    
    private var locationStatusCard: some View {
        HStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(locationManager.authorizationStatus == .authorizedAlways || 
                          locationManager.authorizationStatus == .authorizedWhenInUse ? 
                          OPSStyle.Colors.successStatus.opacity(0.2) : 
                          OPSStyle.Colors.errorStatus.opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Image(systemName: locationManager.authorizationStatus == .authorizedAlways || 
                                  locationManager.authorizationStatus == .authorizedWhenInUse ? 
                      "location.fill" : "location.slash.fill")
                    .font(.system(size: 24))
                    .foregroundColor(locationManager.authorizationStatus == .authorizedAlways || 
                                     locationManager.authorizationStatus == .authorizedWhenInUse ? 
                                   OPSStyle.Colors.successStatus : 
                                   OPSStyle.Colors.errorStatus)
            }
            
            // Status Text
            VStack(alignment: .leading, spacing: 4) {
                Text(locationStatusText)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(.white)
                
                Text(locationStatusDescription)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            
            Spacer()
            
            // Action Button
            Button {
                handleLocationAction()
            } label: {
                Text(locationActionText)
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(locationManager.authorizationStatus == .authorizedAlways || 
                                   locationManager.authorizationStatus == .authorizedWhenInUse ? 
                                   OPSStyle.Colors.primaryText : .black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(locationManager.authorizationStatus == .authorizedAlways || 
                                locationManager.authorizationStatus == .authorizedWhenInUse ? 
                                Color.clear : OPSStyle.Colors.primaryText)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(locationManager.authorizationStatus == .authorizedAlways || 
                                  locationManager.authorizationStatus == .authorizedWhenInUse ? 
                                  OPSStyle.Colors.primaryText : Color.clear, 
                                  lineWidth: 1)
                    )
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .padding(24)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal, 20)
    }
    
    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return "LOCATION ALWAYS ENABLED"
        case .authorizedWhenInUse:
            return "LOCATION WHEN IN USE"
        case .denied, .restricted:
            return "LOCATION DISABLED"
        case .notDetermined:
            return "LOCATION NOT SET"
        @unknown default:
            return "LOCATION STATUS UNKNOWN"
        }
    }
    
    private var locationStatusDescription: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return "Full location access enabled"
        case .authorizedWhenInUse:
            return "Location available when app is open"
        case .denied, .restricted:
            return "Enable to see your location on map"
        case .notDetermined:
            return "Grant permission to use location"
        @unknown default:
            return "Check location settings"
        }
    }
    
    private var locationActionText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "MANAGE"
        case .denied, .restricted:
            return "ENABLE"
        case .notDetermined:
            return "ALLOW"
        @unknown default:
            return "SETTINGS"
        }
    }
    
    private func handleLocationAction() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse, .restricted:
            // Open app settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .denied, .notDetermined:
            // Request permission
            locationManager.requestPermissionIfNeeded(requestAlways: true)
        @unknown default:
            // Open settings as fallback
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    private func resetToDefaults() {
        mapAutoZoom = true
        mapAutoCenter = true
        map3DBuildings = false
        mapTrafficDisplay = false
        mapDefaultType = "standard"
        
        // Reset new settings to defaults
        mapAutoCenterTime = "10"
        mapZoomLevel = "medium"
    }
}

#Preview {
    MapSettingsView()
        .environmentObject(DataController())
}
