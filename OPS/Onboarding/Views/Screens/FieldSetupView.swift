//
//  FieldSetupView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

struct FieldSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var dataController: DataController
    
    @State private var syncSetting: SyncSetting = .auto
    @State private var offlineData: OfflineSetting = .standardCache
    @State private var isLoading = false
    
    enum SyncSetting: String, CaseIterable {
        case auto = "Automatic"
        case manual = "Manual"
        case never = "Never"
    }
    
    enum OfflineSetting: String, CaseIterable {
        case standardCache = "Standard"
        case extendedCache = "Extended"
        case minimal = "Minimal"
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Progress indicator
                    OnboardingStepIndicator(
                        currentStep: .fieldSetup,
                        text: OnboardingStepV2.fieldSetup.stepIndicator
                    )
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    
                    ScrollView {
                        VStack(spacing: 0) {
                            // Header
                            OnboardingHeaderView(
                                title: "Field Setup",
                                subtitle: "Customize how OPS should work when you're on job sites with limited connectivity."
                            )
                            .padding(.bottom, 30)
                            
                            // Field settings
                            VStack(spacing: 24) {
                                // Sync settings
                                SettingsSection(
                                    title: "Data Synchronization",
                                    description: "Choose how you want OPS to sync data when in the field"
                                ) {
                                    ForEach(SyncSetting.allCases, id: \.self) { setting in
                                        SettingOptionCard(
                                            isSelected: syncSetting == setting,
                                            title: setting.rawValue,
                                            description: getSyncDescription(setting),
                                            onTap: {
                                                syncSetting = setting
                                            }
                                        )
                                    }
                                }
                                
                                // Offline data settings
                                SettingsSection(
                                    title: "Offline Data",
                                    description: "Choose how much data to store for offline use"
                                ) {
                                    ForEach(OfflineSetting.allCases, id: \.self) { setting in
                                        SettingOptionCard(
                                            isSelected: offlineData == setting,
                                            title: setting.rawValue,
                                            description: getOfflineDescription(setting),
                                            onTap: {
                                                offlineData = setting
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            
                            Spacer(minLength: geometry.size.height * 0.1)
                        }
                        .frame(minHeight: geometry.size.height - 100)
                    }
                    
                    // Continue button
                    Button(action: {
                        applySettings()
                    }) {
                        ZStack {
                            Text("CONTINUE")
                                .opacity(isLoading ? 0 : 1)
                            
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                        }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .frame(maxWidth: .infinity)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
        }
    }
    
    // Apply settings and move to next step
    private func applySettings() {
        isLoading = true
        
        // Save sync settings to UserDefaults
        switch syncSetting {
        case .auto:
            UserDefaults.standard.set(true, forKey: "syncOnLaunch")
            UserDefaults.standard.set(true, forKey: "syncOnWiFi")
            UserDefaults.standard.set(3600, forKey: "syncInterval") // Every hour
        case .manual:
            UserDefaults.standard.set(false, forKey: "syncOnLaunch")
            UserDefaults.standard.set(false, forKey: "syncOnWiFi")
        case .never:
            UserDefaults.standard.set(false, forKey: "syncOnLaunch")
            UserDefaults.standard.set(false, forKey: "syncOnWiFi")
            UserDefaults.standard.set(false, forKey: "autoSync")
        }
        
        // Save offline data settings
        switch offlineData {
        case .standardCache:
            UserDefaults.standard.set(30, forKey: "offlineDaysToCache")
            UserDefaults.standard.set(true, forKey: "cacheImages")
        case .extendedCache:
            UserDefaults.standard.set(90, forKey: "offlineDaysToCache")
            UserDefaults.standard.set(true, forKey: "cacheImages")
            UserDefaults.standard.set(true, forKey: "cacheAllProjects")
        case .minimal:
            UserDefaults.standard.set(7, forKey: "offlineDaysToCache")
            UserDefaults.standard.set(false, forKey: "cacheImages")
        }
        
        // Simulate a brief loading period
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isLoading = false
            viewModel.moveToNextStepV2()
        }
    }
    
    // Get description for sync settings
    private func getSyncDescription(_ setting: SyncSetting) -> String {
        switch setting {
        case .auto:
            return "Automatically sync data when app launches and on WiFi"
        case .manual:
            return "Only sync data when you manually request it"
        case .never:
            return "Never sync automatically (use with caution)"
        }
    }
    
    // Get description for offline data settings
    private func getOfflineDescription(_ setting: OfflineSetting) -> String {
        switch setting {
        case .standardCache:
            return "Cache 30 days of project data and images (recommended)"
        case .extendedCache:
            return "Cache 90 days of project data and all images (uses more storage)"
        case .minimal:
            return "Cache only 7 days of data without images (saves storage)"
        }
    }
}

// MARK: - Helper Components

struct SettingsSection<Content: View>: View {
    var title: String
    var description: String
    @ViewBuilder var content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Text(description)
                .font(.system(size: 14))
                .foregroundColor(Color.gray)
                .padding(.bottom, 4)
            
            content
        }
    }
}

struct SettingOptionCard: View {
    var isSelected: Bool
    var title: String
    var description: String
    var onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(.top, 2)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.system(size: 14))
                        .foregroundColor(Color.gray)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(OPSStyle.Colors.cardBackground.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear, lineWidth: isSelected ? 1 : 0)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
#Preview("Field Setup View") {
    let viewModel = OnboardingViewModel()
    let dataController = DataController()
    
    return FieldSetupView(viewModel: viewModel)
        .environmentObject(dataController)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}