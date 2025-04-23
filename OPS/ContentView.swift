//
//  ContentView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
// ContentView.swift (updating existing file)
import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var dataController: DataController
    @StateObject private var appState = AppState()
    @State private var showingOnboarding = false
    
    var body: some View {
        Group {
            if !dataController.isAuthenticated {
                LoginView()
            } else if showingOnboarding {
                Text("Onboarding placeholder")
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .onAppear {
                        // For now, skip onboarding
                        self.showingOnboarding = false
                    }
            } else {
                MainTabView()
                    .environmentObject(appState)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Check if this is the first launch
            let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
            showingOnboarding = firstLaunch
            
            if firstLaunch {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            }
        }
    }
}

// Simple login placeholder
struct LoginView: View {
    @EnvironmentObject private var dataController: DataController
    @State private var username = "demo"
    @State private var password = "password"
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                Image(systemName: "p.circle.fill")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.bottom, 50)
                
                Text("OPS")
                    .font(OPSStyle.Typography.largeTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.bottom, 30)
                
                Button("Login (Tap to enter)") {
                    Task {
                        _ = await dataController.login(username: username, password: password)
                    }
                }
                .font(OPSStyle.Typography.bodyBold)
                .padding()
                .frame(maxWidth: .infinity)
                .background(OPSStyle.Colors.primaryAccent)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .cornerRadius(OPSStyle.Layout.buttonRadius)
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
    }
}
