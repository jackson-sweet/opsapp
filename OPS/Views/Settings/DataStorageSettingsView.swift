//
//  DataStorageSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-13.
//

import SwiftUI

struct DataStorageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    // Sync and data preferences
    @AppStorage("syncOnLaunch") private var syncOnLaunch = true
    @AppStorage("backgroundSyncEnabled") private var backgroundSyncEnabled = true
    @AppStorage("imageCacheEnabled") private var imageCacheEnabled = true
    @AppStorage("maxStorageSize") private var maxStorageSize = 500 // MB
    
    @State private var estimatedStorageUsed: Double = 0
    @State private var isCalculatingStorage = false
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Data & Storage",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Synchronization Settings
                        SettingsSectionHeader(title: "SYNCHRONIZATION")
                        
                        SettingsCard(title: "", showTitle: false) {
                            VStack(spacing: 0) {
                                SettingsToggle(
                                    title: "Sync on App Launch",
                                    description: "Automatically sync data when app starts",
                                    isOn: $syncOnLaunch
                                )
                                
                                Divider()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .padding(.vertical, 8)
                                
                                SettingsToggle(
                                    title: "Background Sync",
                                    description: "Sync data when app is in the background",
                                    isOn: $backgroundSyncEnabled
                                )
                            }
                            .padding(.horizontal, -16) // Counteract card padding
                        }
                        
                        // Storage Settings
                        SettingsSectionHeader(title: "STORAGE")
                        
                        SettingsCard(title: "", showTitle: false) {
                            VStack(spacing: 0) {
                                SettingsToggle(
                                    title: "Cache Project Images",
                                    description: "Store project images on device for offline use",
                                    isOn: $imageCacheEnabled
                                )
                                
                                Divider()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .padding(.vertical, 8)
                                
                                // Storage Meter
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Storage Usage")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(.white)
                                    
                                    // Storage bar
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            // Background
                                            Rectangle()
                                                .fill(OPSStyle.Colors.cardBackground)
                                                .frame(height: 8)
                                                .cornerRadius(4)
                                            
                                            // Usage
                                            Rectangle()
                                                .fill(OPSStyle.Colors.primaryAccent)
                                                .frame(width: maxStorageSize == -1 ? 
                                                      // For infinite storage, show a small relative usage
                                                      geometry.size.width * CGFloat(min(estimatedStorageUsed / 10000, 0.1)) : 
                                                      // For limited storage, show percent used
                                                      geometry.size.width * CGFloat(min(maxStorageSize == 0 ? 1.0 : estimatedStorageUsed / Double(maxStorageSize), 1.0)), 
                                                      height: 8)
                                                .cornerRadius(4)
                                        }
                                    }
                                    .frame(height: 8)
                                    
                                    // Usage labels
                                    HStack {
                                        if isCalculatingStorage {
                                            Text("Calculating...")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        } else {
                                            Text("\(Int(estimatedStorageUsed)) MB used")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                        
                                        Spacer()
                                        
                                        if maxStorageSize == -1 {
                                            Text("Unlimited storage")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.successStatus)
                                        } else if maxStorageSize == 0 {
                                            Text("No local storage")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.warningStatus)
                                        } else {
                                            Text("\(maxStorageSize) MB limit")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                
                                Divider()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .padding(.vertical, 8)
                                
                                // Storage limit slider
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Storage Limit")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(.white)
                                    
                                    VStack(spacing: 2) {
                                        Slider(value: Binding(
                                            get: { 
                                                // Infinite storage represented as 5500 for the slider
                                                if maxStorageSize == -1 {
                                                    return 5500
                                                }
                                                return Double(maxStorageSize)
                                            },
                                            set: { newValue in
                                                // Snap to predefined storage points
                                                if newValue >= 5250 {
                                                    // Infinite storage
                                                    maxStorageSize = -1
                                                } else {
                                                    // Convert to one of: 0, 250, 500, 1000, 2000, 5000
                                                    let snapPoints = [0, 250, 500, 1000, 2000, 5000]
                                                    
                                                    // Find the closest snap point
                                                    let closestPoint = snapPoints.min(by: { 
                                                        abs(Double($0) - newValue) < abs(Double($1) - newValue) 
                                                    }) ?? 500
                                                    
                                                    maxStorageSize = closestPoint
                                                }
                                            }
                                        ), in: 0...5500, step: 1)
                                        .accentColor(OPSStyle.Colors.primaryAccent)
                                        
                                        // Snap point markers
                                        HStack(spacing: 0) {
                                            Text("0")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                            
                                            Spacer()
                                            
                                            Text("500")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                            
                                            Spacer()
                                            
                                            Text("1000")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                            
                                            Spacer()
                                            
                                            Text("∞")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(height: 20)
                                    }
                                    
                                    HStack {
                                        Spacer()
                                        Text(maxStorageSize == -1 ? "∞" : "\(maxStorageSize) MB")
                                            .font(OPSStyle.Typography.smallBody)
                                            .foregroundColor(.white)
                                            .frame(width: 80)
                                    }
                                    
                                    // Message for no local storage or infinite storage
                                    if maxStorageSize == 0 {
                                        Text("No local data storage. This requires constant network connectivity.")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.warningStatus)
                                            .padding(.top, 4)
                                    } else if maxStorageSize == -1 {
                                        Text("Unlimited local storage. Uses more device storage but provides the best offline experience.")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.successStatus)
                                            .padding(.top, 4)
                                    }
                                }
                            }
                            .padding(.horizontal, -16) // Counteract card padding
                        }
                        
                        // Clear data buttons
                        SettingsSectionHeader(title: "DATA MANAGEMENT")
                        
                        VStack(spacing: 16) {
                            SettingsButton(
                                title: "Clear Image Cache",
                                icon: "photo",
                                style: .secondary,
                                action: {
                                    clearImageCache()
                                }
                            )
                            
                            SettingsButton(
                                title: "Clear All Offline Data",
                                icon: "trash",
                                style: .destructive,
                                action: {
                                    clearAllOfflineData()
                                }
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 24)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            calculateStorageUsage()
        }
    }
    
    private func calculateStorageUsage() {
        // Simulate calculation of storage
        isCalculatingStorage = true
        
        // In a real app, you would use FileManager to calculate actual usage
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // This is a placeholder - real implementation would calculate actual usage
            if maxStorageSize == 0 {
                // No local storage should show 0 used
                estimatedStorageUsed = 0
            } else if maxStorageSize == -1 {
                // For infinite storage, show a reasonable number
                estimatedStorageUsed = Double.random(in: 200...800)
            } else {
                // For finite storage, show a random amount under the limit
                estimatedStorageUsed = Double.random(in: 50...min(Double(maxStorageSize) * 0.9, Double(maxStorageSize) - 10))
            }
            isCalculatingStorage = false
        }
    }
    
    private func clearImageCache() {
        // Simulate clearing the image cache
        // In a real app, you would use ImageCache to clear the cache
        if maxStorageSize != 0 {
            // Reduce storage by approximately 40%
            estimatedStorageUsed *= 0.6
        }
    }
    
    private func clearAllOfflineData() {
        // Simulate clearing all offline data
        // In a real app, you would use DataController to clear the database
        estimatedStorageUsed = 0
        
        // Display notification to user
        // This would trigger a toast or notification in a real app
        
        // For the purpose of this demo, we'll simply recalculate storage after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            calculateStorageUsage()
        }
    }
}

#Preview {
    DataStorageSettingsView()
        .preferredColorScheme(.dark)
        .environmentObject(DataController())
}