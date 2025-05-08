//
//  CompletionView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI
import Combine

struct CompletionView: View {
    var onComplete: () -> Void
    
    // Animation states
    @State private var logoScale: CGFloat = 0.1
    @State private var scanLineOffset: CGFloat = -400
    @State private var lineProgress: CGFloat = 0
    @State private var statusItemsOpacity: [Double] = [0, 0, 0, 0]
    @State private var statusCheckmarks: [Bool] = [false, false, false, false]
    @State private var textOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 100
    @State private var showContinueButton: Bool = false
    
    // Dynamic properties
    let statusItems = ["IDENTITY VERIFIED", "PROFILE CREATED", "COMPANY LINKED", "ACCESS GRANTED"]
    
    var body: some View {
        ZStack {
            // Tactical background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Moving scan line effect
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 2)
                .offset(y: scanLineOffset)
                .ignoresSafeArea()
            
            VStack {
                // Header
                HStack {
                    Text("OPS // ONBOARDING")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundColor(Color.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text(formattedCurrentTime())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)
                
                // Main content area
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Central logo
                    VStack(spacing: 20) {
                        // Logo
                        Text("OPS")
                            .font(.system(size: 42, weight: .heavy))
                            .tracking(4)
                            .foregroundColor(.white)
                            .scaleEffect(logoScale)
                        
                        // Horizontal line
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(OPSStyle.Colors.primaryAccent)
                                .frame(width: lineProgress * geometry.size.width, height: 2)
                                .frame(width: geometry.size.width, alignment: .leading)
                        }
                        .frame(height: 2)
                    }
                    
                    // Status verification indicators
                    VStack(spacing: 12) {
                        ForEach(0..<statusItems.count, id: \.self) { index in
                            HStack {
                                Text(statusItems[index])
                                    .font(.system(size: 14, weight: .medium))
                                    .tracking(1)
                                    .foregroundColor(Color.white.opacity(0.9))
                                
                                Spacer()
                                
                                if statusCheckmarks[index] {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        .font(.system(size: 14, weight: .bold))
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .opacity(statusItemsOpacity[index])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Welcome message
                    VStack(spacing: 8) {
                        Text("SETUP COMPLETE")
                            .font(.system(size: 22, weight: .heavy))
                            .tracking(3)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Your operational control center is ready")
                            .font(.system(size: 16))
                            .foregroundColor(Color.gray)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(textOpacity)
                    
                    Spacer()
                    
                    // Enter button
                    Button(action: {
                        print("CompletionView: ENTER APP button tapped")
                        onComplete()
                    }) {
                        Text("ENTER OPS")
                            .font(.system(size: 16, weight: .bold))
                            .tracking(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(OPSStyle.Colors.primaryAccent)
                            .foregroundColor(.white)
                            .cornerRadius(5)
                    }
                    .opacity(buttonOpacity)
                    .offset(y: buttonOffset)
                    .disabled(!showContinueButton)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            animateTacticalSequence()
        }
        .onReceive(timer) { newTime in
            currentTime = newTime
        }
    }
    
    // State to track current time
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // Format current time for display
    private func formattedCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: currentTime)
    }
    
    // Simplified tactical animation sequence
    private func animateTacticalSequence() {
        // Reset scan line position and start animation
        scanLineOffset = -400
        withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) {
            scanLineOffset = 400
        }
        
        // Logo animation
        withAnimation(.easeInOut(duration: 1.0)) {
            logoScale = 1.0
        }
        
        // Line progress animation
        withAnimation(.easeInOut(duration: 1.5).delay(0.5)) {
            lineProgress = 1.0
        }
        
        // Show status items one by one
        for i in 0..<statusItems.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.6 + 1.5) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    statusItemsOpacity[i] = 1.0
                }
                
                // Show checkmark after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring()) {
                        statusCheckmarks[i] = true
                    }
                }
            }
        }
        
        // Show text after status verifications
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.easeInOut(duration: 0.8)) {
                textOpacity = 1.0
            }
        }
        
        // Show button last
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            showContinueButton = true
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                buttonOffset = 0
                buttonOpacity = 1.0
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
                    print("Preview: Completion callback triggered")
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
                    .cornerRadius(8)
                    .padding()
                }
            }
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        }
    }
    
    // Add styles to the environment for the preview
    return PreviewCompletionView()
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
}