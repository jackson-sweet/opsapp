//
//  UIComponents.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI

// MARK: - Loading Views

/// Full-screen loading view with logo for app initialization
struct SplashLoadingView: View {
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                    
                    HStack(alignment: .bottom){
                        // Logo
                        Image("LogoWhite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                    }
                    .padding(.bottom, 40)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                        .scaleEffect(1.2)
                    
                    
                Spacer()
                
                // Version info
                Text("[ VERSION \(AppConfiguration.AppInfo.version.uppercased()) ]")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.bottom, OPSStyle.Layout.spacing3)
            }
        }
    }
}

/// Tactical console-style loading view for initial data sync
struct TacticalInitialLoadingView: View {
    @ObservedObject var dataController: DataController

    @State private var visibleLines: [String] = []
    @State private var currentLineIndex = 0

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)

            VStack(spacing: 32) {
                Spacer()

                // Logo
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .opacity(0.8)

                // Loading bar
                TacticalLoadingBarAnimated(
                    barCount: 12,
                    barWidth: 3,
                    barHeight: 8,
                    spacing: 5,
                    emptyColor: OPSStyle.Colors.primaryAccent.opacity(0.2),
                    fillColor: OPSStyle.Colors.primaryAccent
                )

                // Console output
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 8) {
                            Text(">")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(OPSStyle.Colors.primaryAccent.opacity(0.6))

                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .opacity(index == visibleLines.count - 1 ? 1.0 : 0.5)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(height: 100, alignment: .bottom)
                .padding(.horizontal, 40)

                Spacer()

                // Version info
                Text("[ VERSION \(AppConfiguration.AppInfo.version.uppercased()) ]")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.bottom, OPSStyle.Layout.spacing3)
            }
        }
        .onAppear {
            startLoadingSequence()
        }
        .onChange(of: dataController.syncStatusMessage) { _, newMessage in
            if !newMessage.isEmpty && !visibleLines.contains(newMessage) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    visibleLines.append(newMessage)
                    if visibleLines.count > 5 {
                        visibleLines.removeFirst()
                    }
                }
            }
        }
    }

    private func startLoadingSequence() {
        let initialMessages = [
            "INITIALIZING SYSTEM...",
            "AUTHENTICATING USER...",
            "LOADING COMPANY DATA..."
        ]

        for (index, message) in initialMessages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.3) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    visibleLines.append(message)
                }
            }
        }
    }
}

/// Overlay loading view for in-progress operations
struct LoadingView: View {
    var message: String = "Processing..."
    var isFullScreen: Bool = false

    var body: some View {
        ZStack {
            if isFullScreen {
                OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            } else {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
            }

            VStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)

                if !message.isEmpty {
                    Text(message)
                        .foregroundColor(.white)
                        .padding(.top, 12)
                }
            }
            .padding(24)
            .background(Color(white: 0.1))
            .cornerRadius(12)
        }
    }
}
