//
//  CompletionView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

// TODO: REDO COMPLETION PAGE
// This completion page needs to be redesigned to better reflect
// the OPS brand and provide a more seamless transition into the app.
// Consider simplifying the animation and focusing on key messaging.

import SwiftUI
import Combine

struct CompletionView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @EnvironmentObject var dataController: DataController
    var onComplete: () -> Void = {}
    
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
    @State private var companyDataFetched = false
    
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
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(2)
                        .foregroundColor(Color.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text(formattedCurrentTime())
                        .font(OPSStyle.Typography.captionBold)
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
                            .font(OPSStyle.Typography.largeTitle)
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
                                    .font(OPSStyle.Typography.caption)
                                    .tracking(1)
                                    .foregroundColor(Color.white.opacity(0.9))
                                
                                Spacer()
                                
                                if statusCheckmarks[index] {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        .font(OPSStyle.Typography.captionBold)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 16)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
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
                            .font(OPSStyle.Typography.subtitle)
                            .tracking(3)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Your operational control center is ready")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(Color.gray)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(textOpacity)
                    
                    Spacer()
                    
                    // Enter button
                    StandardContinueButton(
                        isDisabled: !showContinueButton,
                        onTap: {
                            print("CompletionView: ENTER APP button tapped")
                            // Move to welcome guide
                            onboardingViewModel.nextStep()
                        }
                    )
                    .opacity(buttonOpacity)
                    .offset(y: buttonOffset)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            animateTacticalSequence()
            fetchCompanyDataIfNeeded()
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
    
    // Fetch company data if user is a company owner
    private func fetchCompanyDataIfNeeded() {
        // Only fetch if user is a company owner and hasn't fetched yet
        guard !companyDataFetched,
              onboardingViewModel.selectedUserType == .company,
              let companyId = UserDefaults.standard.string(forKey: "company_id"),
              !companyId.isEmpty else {
            print("CompletionView: No need to fetch company data")
            return
        }
        
        print("CompletionView: Fetching company data for ID: \(companyId)")
        companyDataFetched = true
        
        Task {
            do {
                // Force refresh company data from API
                try await dataController.forceRefreshCompany(id: companyId)
                print("CompletionView: Successfully fetched and stored company data")
                
                // Update status to show company is fully linked
                await MainActor.run {
                    // Ensure the "COMPANY LINKED" checkmark shows after data is fetched
                    if !statusCheckmarks[2] {
                        withAnimation(.spring()) {
                            statusCheckmarks[2] = true
                        }
                    }
                }
            } catch {
                print("CompletionView: Error fetching company data: \(error.localizedDescription)")
                // Don't block the user from continuing even if fetch fails
                // They can still proceed and data will be fetched on next app launch
            }
        }
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