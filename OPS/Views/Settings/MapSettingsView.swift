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
    @AppStorage("mapShowCompass") private var mapShowCompass = true
    @AppStorage("mapAutoCenter") private var mapAutoCenter = true
    @AppStorage("map3DBuildings") private var map3DBuildings = false
    @AppStorage("mapTrafficDisplay") private var mapTrafficDisplay = false
    @AppStorage("mapDefaultType") private var mapDefaultType = "standard"
    
    // Map types for picker
    private let mapTypes = ["standard", "satellite", "hybrid"]
    private let mapTypeLabels = ["Standard", "Satellite", "Hybrid"]
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Map Settings",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                ScrollView {
                    VStack(spacing: 24) {
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
                                    title: "Show Compass",
                                    description: "Display compass for orientation",
                                    isOn: $mapShowCompass
                                )
                                
                                Divider()
                                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                                    .padding(.vertical, 8)
                                
                                SettingsToggle(
                                    title: "Auto Center/Rotate",
                                    description: "Re-center map when moving between projects",
                                    isOn: $mapAutoCenter
                                )
                            }
                            .padding(.horizontal, -16) // Counteract card padding
                        }
                        
                        // Map Display
                        SettingsSectionHeader(title: "MAP DISPLAY")
                        
                        SettingsCard(title: "", showTitle: false) {
                            VStack(spacing: 0) {
                                // Map type picker
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Map Type")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Picker("Map Type", selection: $mapDefaultType) {
                                        ForEach(0..<mapTypes.count, id: \.self) { index in
                                            Text(mapTypeLabels[index])
                                                .tag(mapTypes[index])
                                        }
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                    .padding(.vertical, 8)
                                }
                                
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
                        
                        // Visual example of map settings
                        SettingsCard(title: "PREVIEW") {
                            ZStack {
                                if mapDefaultType == "satellite" {
                                    Image(systemName: "map.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 180)
                                        .clipped()
                                        .overlay(
                                            Color.black.opacity(0.1)
                                        )
                                } else if mapDefaultType == "hybrid" {
                                    Image(systemName: "map.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 180)
                                        .clipped()
                                        .overlay(
                                            Color.black.opacity(0.3)
                                        )
                                } else {
                                    Image(systemName: "map")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 180)
                                        .clipped()
                                        .overlay(
                                            Color.white.opacity(0.1)
                                        )
                                }
                                
                                // Show compass if enabled
                                if mapShowCompass {
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Image(systemName: "location.north.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(.white)
                                                .background(
                                                    Circle()
                                                        .fill(Color.black.opacity(0.5))
                                                        .frame(width: 36, height: 36)
                                                )
                                                .padding(16)
                                        }
                                        Spacer()
                                    }
                                }
                                
                                // Simulated markers
                                ForEach(0..<3) { i in
                                    Circle()
                                        .fill(OPSStyle.Colors.primaryAccent)
                                        .frame(width: 16, height: 16)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 2)
                                        )
                                        .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                                        .offset(
                                            x: CGFloat([40, -60, 20][i % 3]),
                                            y: CGFloat([20, -30, 50][i % 3])
                                        )
                                }
                            }
                            .frame(height: 180)
                            .cornerRadius(8)
                            .clipped()
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
    }
    
    private func resetToDefaults() {
        mapAutoZoom = true
        mapShowCompass = true
        mapAutoCenter = true
        map3DBuildings = false
        mapTrafficDisplay = false
        mapDefaultType = "standard"
    }
}

#Preview {
    MapSettingsView()
        .environmentObject(DataController())
}