//
//  CompletionView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI

struct CompletionView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @EnvironmentObject var dataController: DataController
    var onComplete: () -> Void = {}

    // Animation states
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // OPS Logo
                Image("LogoWhite")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .opacity(logoOpacity)
                
                // Welcome text
                Text("WELCOME TO OPS.")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                    .opacity(textOpacity)
                
                Spacer()
            }
        }
        .onAppear {
            // NOTE: No sync calls here - createCompany() already performed a full sync
            // in Step 8 (Company Details). Redundant syncs removed to improve performance.

            // Start animation sequence
            withAnimation(.easeIn(duration: 0.8)) {
                logoOpacity = 1.0
            }

            // Fade in text after logo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeIn(duration: 0.8)) {
                    textOpacity = 1.0
                }
            }

            // Automatically continue to welcome guide after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                onboardingViewModel.moveToNextStep()
            }
        }
    }
}

// MARK: - Preview
#Preview("Completion Screen") {
    struct PreviewCompletionView: View {
        @State private var demoMode = true
        
        var body: some View {
            VStack {
                CompletionView {
                    demoMode.toggle()
                }
                
                // Add controls for Xcode adjustments
                if demoMode {
                    VStack {
                        Text("Preview Controls")
                            .font(.headline)
                        
                        Divider()
                        
                        Button("Run Animation Again") {
                            demoMode.toggle()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                demoMode.toggle()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.vertical, 8)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding()
                }
            }
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        }
    }
    
    // Add styles to the environment for the preview
    return PreviewCompletionView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(DataController())
}
