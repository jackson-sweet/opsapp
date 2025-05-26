//
//  FieldSetupView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI
import SwiftData

struct FieldSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var dataController: DataController
    
    @State private var syncSetting: SyncSetting = .auto
    @State private var selectedStorageIndex: Int = 3 // Default to 500MB
    @State private var isLoading = false
    
    enum SyncSetting: String, CaseIterable {
        case auto = "Automatic"
        case manual = "Manual"
        case never = "Never"
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
                        text: OnboardingStep.fieldSetup.stepIndicator
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
                                
                                // Offline data settings with storage slider
                                SettingsSection(
                                    title: "Offline Storage",
                                    description: "Choose how much data to store for offline use"
                                ) {
                                    StorageOptionSlider(selectedStorageIndex: $selectedStorageIndex)
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
        
        // Save offline storage settings based on slider selection
        let storageValues = [0, 100, 250, 500, 1000, 5000, -1] // -1 for unlimited
        let storageMB = storageValues[selectedStorageIndex]
        
        UserDefaults.standard.set(storageMB, forKey: "offlineStorageLimitMB")
        
        // Set cache behavior based on storage selection
        if selectedStorageIndex == 0 {
            // No storage
            UserDefaults.standard.set(false, forKey: "cacheImages")
            UserDefaults.standard.set(false, forKey: "cacheProjectData")
        } else if selectedStorageIndex == 6 {
            // Unlimited
            UserDefaults.standard.set(true, forKey: "cacheImages")
            UserDefaults.standard.set(true, forKey: "cacheProjectData")
            UserDefaults.standard.set(-1, forKey: "offlineStorageLimitMB")
        } else {
            // Limited storage
            UserDefaults.standard.set(true, forKey: "cacheImages")
            UserDefaults.standard.set(true, forKey: "cacheProjectData")
        }
        
        // Simulate a brief loading period
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isLoading = false
            viewModel.moveToNextStep()
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
    
}

// MARK: - Helper Components

struct SettingsSection<Content: View>: View {
    var title: String
    var description: String
    @ViewBuilder var content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(.white)
            
            Text(description)
                .font(OPSStyle.Typography.caption)
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
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(OPSStyle.Typography.caption)
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