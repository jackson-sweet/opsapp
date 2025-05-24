//
//  MapSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-12.
//

import SwiftUI

struct MapSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
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
                    title: "Map Settings",
                    onBackTapped: {
                        dismiss()
                    }
                )
                .padding(.bottom, 8)
                
                // Content - Scrollable when needed
                ScrollView {
                    VStack(spacing: 20) {
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
        .onChange(of: mapAutoCenterTime) { _, newValue in
            print("🔧 MapSettingsView: mapAutoCenterTime changed to \(newValue)")
            // Force UserDefaults to synchronize immediately
            UserDefaults.standard.synchronize()
        }
        .onChange(of: mapAutoCenter) { _, newValue in
            print("🔧 MapSettingsView: mapAutoCenter changed to \(newValue)")
            UserDefaults.standard.synchronize()
        }
        .onChange(of: mapZoomLevel) { _, newValue in
            print("🔧 MapSettingsView: mapZoomLevel changed to \(newValue)")
            UserDefaults.standard.synchronize()
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
