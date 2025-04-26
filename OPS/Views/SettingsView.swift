//
//  SettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @State private var showLogoutConfirmation = false
    
    @AppStorage("syncOnLaunch") private var syncOnLaunch = true
       @AppStorage("backgroundSyncEnabled") private var backgroundSyncEnabled = true
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                // Header
                Text("Settings")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal)
                
                if let user = dataController.currentUser {
                    Text(user.fullName)
                        .font(OPSStyle.Typography.subtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal)
                }
                
                // Content - settings options would go here
                settingsContent
                
                Spacer()
                
                Text("DATA SYNC")
                                   .font(OPSStyle.Typography.captionBold)
                                   .foregroundColor(OPSStyle.Colors.secondaryText)
                                   .padding(.top)
                               
                               Toggle("Sync on app launch", isOn: $syncOnLaunch)
                                   .tint(OPSStyle.Colors.secondaryAccent)
                               
                               Toggle("Background sync", isOn: $backgroundSyncEnabled)
                                   .tint(OPSStyle.Colors.secondaryAccent)
                
                // Footer with logout and version
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    // Logout button
                    Button(action: {
                        showLogoutConfirmation = true
                    }) {
                        HStack {
                            Text("Log Out")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(Color.red)
                            
                            Image(systemName: "arrow.right.square")
                                .font(.system(size: 18))
                                .foregroundColor(Color.red)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .background(OPSStyle.Colors.background)
                    
                    // App version and logo
                    HStack {
                        Text("OPS APP")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Text("v1.0.0")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        // App logo
                        Image("AppIcon") // Add this asset or use a system icon if needed
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 36, height: 36)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, OPSStyle.Layout.spacing4)
                }
            }
            .padding(.top)
        }
        .alert(isPresented: $showLogoutConfirmation) {
            Alert(
                title: Text("Log Out"),
                message: Text("Are you sure you want to log out?"),
                primaryButton: .destructive(Text("Log Out")) {
                    logout()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private var settingsContent: some View {
        VStack(spacing: OPSStyle.Layout.spacing4) {
            // Placeholder for settings content
            // We'll replace this with actual menu items
            Text("Settings content goes here")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .padding(.horizontal)
        }
    }
    
    private func logout() {
        // Simple, direct logout function
        dataController.logout()
    }
}
