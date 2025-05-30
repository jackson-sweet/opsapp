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
    @State private var showAnimatedLogo = true
    @State private var buttonOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 100
    @State private var showContinueButton: Bool = false
    @State private var companyDataFetched = false
    
    var body: some View {
        ZStack {
            if showAnimatedLogo {
                // Show animated logo
                AnimatedOPSLogo(onAnimationComplete: {
                    // Transition to button
                    withAnimation(.easeOut(duration: 0.5)) {
                        showAnimatedLogo = false
                    }
                    
                    // Show continue button
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showContinueButton = true
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            buttonOffset = 0
                            buttonOpacity = 1.0
                        }
                    }
                })
                .transition(.opacity)
            } else {
                // Dark background after animation
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
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
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
            }
        }
        .onAppear {
            fetchCompanyDataIfNeeded()
        }
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
                
                // Company data successfully fetched
            } catch {
                print("CompletionView: Error fetching company data: \(error.localizedDescription)")
                // Don't block the user from continuing even if fetch fails
                // They can still proceed and data will be fetched on next app launch
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
