//
//  AppSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-13.
//

import SwiftUI

// Use standardized components directly (internal modules don't need import)

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    // App settings sections
    enum AppSettingSection: String, Identifiable, CaseIterable {
        case mapSettings = "Map Settings"
        case notifications = "Notification Settings"
        case dataStorage = "Data & Storage"
        case security = "Security & PIN"
        
        var id: String { self.rawValue }
        
        var iconName: String {
            switch self {
            case .mapSettings:
                return "map"
            case .notifications:
                return "bell"
            case .dataStorage:
                return "externaldrive"
            case .security:
                return "lock"
            }
        }
        
        var description: String {
            switch self {
            case .mapSettings:
                return "Customize map display and behavior"
            case .notifications:
                return "Manage notifications and reminders"
            case .dataStorage:
                return "Control synchronization and storage"
            case .security:
                return "Manage app security preferences"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Header - fixed, not part of scroll view
                    SettingsHeader(
                        title: "App Settings",
                        onBackTapped: {
                            dismiss()
                        }
                    )
                    .padding(.bottom, 8)
                    
                    // App settings categories - scrollable content

                        VStack(spacing: 24) {
                            // Map, notifications, data, security
                            VStack(spacing: 24) {
                                ForEach(AppSettingSection.allCases) { section in
                                    NavigationLink(destination: destinationFor(section)) {
                                        settingRow(for: section)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            
                            Spacer()
                            
                            // App version and information section
                            appInfoCard
                                .padding(.horizontal, 20)
                        }
                        .padding(.vertical, 24)
                    
                }
            }
            .navigationBarBackButtonHidden(true)
        }
    }
    
    // App info card with logo and version
    private var appInfoCard: some View {
        HStack(spacing: 20) {
            // App logo
            HStack(alignment: .center) {
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                
                // App name
                Text("OPS APP")
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            VStack (alignment: .trailing) {
                // Version number
                Text("Version 1.0.0")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                // Copyright info
                Text("© 2025 OPS Construction Software")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            }
        .frame(maxWidth: .infinity)
    }
    
    private func settingRow(for section: AppSettingSection) -> some View {
        CategoryCard(
            title: section.rawValue,
            description: section.description,
            iconName: section.iconName
        )
    }
    
    @ViewBuilder
    private func destinationFor(_ section: AppSettingSection) -> some View {
        switch section {
        case .mapSettings:
            MapSettingsView()
        case .notifications:
            NotificationSettingsView()
        case .dataStorage:
            DataStorageSettingsView()
        case .security:
            SecuritySettingsView()
        }
    }
}

#Preview {
    AppSettingsView()
        .preferredColorScheme(.dark)
        .environmentObject(DataController())
}
