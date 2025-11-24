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
    @AppStorage("historicalDataMonths") private var historicalDataMonths = 6 // Months of historical data to sync
    
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
                    VStack(spacing: 0 ) {
                        // Synchronization Settings
                        SectionCard(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Synchronization",
                            contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                        ) {
                                    VStack(spacing: 0) {
                                SettingsToggle(
                                    title: "Sync on App Launch",
                                    description: "Get data from online when app starts",
                                    isOn: $syncOnLaunch
                                )

                                Divider()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .padding(.vertical, 8)

                                SettingsToggle(
                                    title: "Background Sync",
                                    description: "Get data from online when app is not open",
                                    isOn: $backgroundSyncEnabled
                                )

                                Divider()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .padding(.vertical, 8)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Historical Data Range")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(.white)

                                    Text("Sync projects and tasks from the past \(historicalDataMonths) months")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    VStack(spacing: 8) {
                                        let monthOptions = [1, 3, 6, 12, 24, 36, -1]
                                        let sliderSteps = Double(monthOptions.count - 1)

                                        Slider(value: Binding(
                                            get: {
                                                if let index = monthOptions.firstIndex(of: historicalDataMonths) {
                                                    return Double(index)
                                                }
                                                return 2.0
                                            },
                                            set: { newValue in
                                                let index = Int(round(newValue))
                                                if index >= 0 && index < monthOptions.count {
                                                    historicalDataMonths = monthOptions[index]
                                                }
                                            }
                                        ), in: 0...sliderSteps, step: 1)
                                        .accentColor(OPSStyle.Colors.primaryAccent)

                                        HStack(alignment: .center, spacing: 0) {
                                            ForEach(0..<monthOptions.count, id: \.self) { index in
                                                if index > 0 {
                                                    Spacer(minLength: 0)
                                                }

                                                Text(formatMonthsLabel(monthOptions[index]))
                                                    .font(OPSStyle.Typography.smallCaption)
                                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                                    .frame(width: index == 0 || index == monthOptions.count - 1 ? 20 : 40)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.8)

                                                if index == 0 {
                                                    Spacer(minLength: 0)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .frame(height: 20)
                                    }

                                    HStack {
                                        Spacer()
                                        Text(formatMonthsRange(historicalDataMonths))
                                            .font(OPSStyle.Typography.smallBody)
                                            .foregroundColor(.white)
                                    }

                                    if historicalDataMonths == -1 {
                                        Text("Sync all historical data. This may take longer on first sync.")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                            .padding(.top, 4)
                                    } else if historicalDataMonths == 1 {
                                        Text("Only sync data from the past month. Reduces data usage.")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                            .padding(.top, 4)
                                    }
                                }
                                .padding(16)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Storage Settings
                        SectionCard(
                            icon: "externaldrive",
                            title: "Storage",
                            contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                        ) {
                            VStack(spacing: 0) {
                                SettingsToggle(
                                    title: "Cache Project Images",
                                    description: "Store project images on device, so you can see them even when no internet connection",
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
                                            Text("\(formatStorageSize(maxStorageSize)) limit")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                        }
                                    }
                                }
                                .padding(16)
                                
                                Divider()
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .padding(.vertical, 8)
                                
                                // Storage limit slider
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Storage Limit")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(.white)
                                    
                                    VStack(spacing: 8) {
                                        // Storage options: 0, 250, 500, 1000, 2500, 5000, unlimited (-1)
                                        let storageOptions = [0, 250, 500, 1000, 2500, 5000, -1]
                                        let sliderSteps = Double(storageOptions.count - 1)
                                        
                                        ZStack(alignment: .center) {
                                            // Tick marks for each snap point
                                            GeometryReader { geometry in
                                                ForEach(0..<storageOptions.count, id: \.self) { index in
                                                    Rectangle()
                                                        .fill(OPSStyle.Colors.secondaryText.opacity(0.3))
                                                        .frame(width: 1, height: 12)
                                                        .position(
                                                            x: geometry.size.width * CGFloat(index) / CGFloat(storageOptions.count - 1),
                                                            y: geometry.size.height / 2
                                                        )
                                                }
                                            }
                                            .frame(height: 12)
                                            
                                            Slider(value: Binding(
                                                get: {
                                                    // Convert storage value to slider position (0-6)
                                                    if let index = storageOptions.firstIndex(of: maxStorageSize) {
                                                        return Double(index)
                                                    }
                                                    // Default to 500 MB (index 2)
                                                    return 2.0
                                                },
                                                set: { newValue in
                                                    // Convert slider position to storage value
                                                    let index = Int(round(newValue))
                                                    if index >= 0 && index < storageOptions.count {
                                                        maxStorageSize = storageOptions[index]
                                                    }
                                                }
                                            ), in: 0...sliderSteps, step: 1)
                                            .accentColor(OPSStyle.Colors.primaryAccent)
                                        }
                                        
                                        // Snap point markers - evenly spaced
                                        HStack(alignment: .center, spacing: 0) {
                                            ForEach(0..<storageOptions.count, id: \.self) { index in
                                                if index > 0 {
                                                    Spacer(minLength: 0)
                                                }
                                                
                                                Text(formatStorageLabel(storageOptions[index]))
                                                    .font(OPSStyle.Typography.smallCaption)
                                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                                    .frame(width: index == 0 || index == storageOptions.count - 1 ? 20 : 40)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.8)
                                                
                                                if index == 0 {
                                                    Spacer(minLength: 0)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .frame(height: 20)
                                    }
                                    
                                    HStack {
                                        Spacer()
                                        Text(formatStorageSize(maxStorageSize))
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
                                .padding(16)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Clear data buttons
                        SectionCard(
                            icon: "trash.circle",
                            title: "Data Management"
                        ) {
                            VStack(spacing: 16) {
                            SettingsButton(
                                title: "Clear Image Cache",
                                icon: OPSStyle.Icons.photo,
                                style: .secondary,
                                action: {
                                    clearImageCache()
                                }
                            )
                            
                            SettingsButton(
                                title: "Clear All Offline Data",
                                icon: OPSStyle.Icons.trash,
                                style: .destructive,
                                action: {
                                    clearAllOfflineData()
                                }
                            )
                            }
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
    
    private func formatMonthsLabel(_ months: Int) -> String {
        if months == -1 {
            return "All"
        } else if months == 1 {
            return "1m"
        } else if months == 12 {
            return "1y"
        } else if months == 24 {
            return "2y"
        } else if months == 36 {
            return "3y"
        } else {
            return "\(months)m"
        }
    }

    private func formatMonthsRange(_ months: Int) -> String {
        if months == -1 {
            return "All Data"
        } else if months == 1 {
            return "1 Month"
        } else if months == 12 {
            return "1 Year"
        } else if months == 24 {
            return "2 Years"
        } else if months == 36 {
            return "3 Years"
        } else {
            return "\(months) Months"
        }
    }

    private func formatStorageSize(_ size: Int) -> String {
        if size == -1 {
            return "∞"
        } else if size == 0 {
            return "0 MB"
        } else if size >= 1000 {
            let gb = Double(size) / 1000.0
            return String(format: "%.1f GB", gb)
        } else {
            return "\(size) MB"
        }
    }
    
    private func formatStorageLabel(_ size: Int) -> String {
        if size == -1 {
            return "∞"
        } else if size == 0 {
            return "0"
        } else if size >= 1000 {
            let gb = Double(size) / 1000.0
            if gb == floor(gb) {
                return "\(Int(gb))GB"
            } else {
                return String(format: "%.1fGB", gb)
            }
        } else {
            return "\(size)"
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
