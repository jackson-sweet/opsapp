//
//  VerifyPhoneView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-06.
//

import SwiftUI

// This is a placeholder view that immediately redirects to the next step
// It exists only to maintain compatibility until it can be properly removed from the build system
struct VerifyPhoneView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                Text("Processing...")
                    .foregroundColor(.white)
            }
            .onAppear {
                // Immediately redirect to the next step
                DispatchQueue.main.async {
                    viewModel.moveTo(step: .email)
                }
            }
        }
    }
}

// MARK: - Preview
#Preview("Phone Verification") {
    let viewModel = OnboardingViewModel()
    viewModel.phoneNumber = "+15551234567"
    
    return VerifyPhoneView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}