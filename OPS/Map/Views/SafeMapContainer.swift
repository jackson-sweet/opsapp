//
//  SafeMapContainer.swift
//  OPS
//
//  Wrapper to safely initialize the new map without crashes

import SwiftUI

struct SafeMapContainer: View {
    let projects: [Project]
    let selectedIndex: Int
    let onProjectSelected: (Project) -> Void
    let onNavigationStarted: (Project) -> Void
    @ObservedObject var appState: AppState
    
    @State private var isMapReady = false
    
    var body: some View {
        Group {
            if isMapReady {
                MapContainer(
                    projects: projects,
                    selectedIndex: selectedIndex,
                    onProjectSelected: onProjectSelected,
                    onNavigationStarted: onNavigationStarted,
                    appState: appState
                )
            } else {
                // Show loading while we prepare
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            .scaleEffect(1.5)
                        
                        Text("Loading map...")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.top)
                    }
                }
                .onAppear {
                    // Delay map initialization to avoid conflicts
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isMapReady = true
                    }
                }
            }
        }
    }
}