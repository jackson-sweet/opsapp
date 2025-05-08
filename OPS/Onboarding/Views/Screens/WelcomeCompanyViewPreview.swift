//
//  WelcomeCompanyViewPreview.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

// MARK: - Preview for WelcomeCompanyView
struct WelcomeCompanyViewPreview: View {
    var body: some View {
        let viewModel = OnboardingViewModel()
        viewModel.email = "user@example.com"
        viewModel.password = "password123"
        viewModel.firstName = "John"
        viewModel.lastName = "Doe"
        viewModel.phoneNumber = "5551234567"
        viewModel.companyCode = "DEMO123"
        viewModel.companyName = "Demo Company, Inc."
        viewModel.isCompanyJoined = true
        
        return WelcomeCompanyView(viewModel: viewModel)
            .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
            .environment(\.colorScheme, .dark)
    }
}

#Preview("Welcome Company Screen") {
    WelcomeCompanyViewPreview()
}