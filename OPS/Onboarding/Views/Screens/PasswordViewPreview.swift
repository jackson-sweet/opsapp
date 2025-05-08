//
//  PasswordViewPreview.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

// MARK: - Preview Extension for PasswordView
struct PasswordViewPreview: View {
    var body: some View {
        let viewModel = OnboardingViewModel()
        viewModel.email = "user@example.com"
        viewModel.password = "password123"
        viewModel.confirmPassword = "password123"
        
        return PasswordView(viewModel: viewModel)
            .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
            .environment(\.colorScheme, .dark)
    }
}

#Preview("Password Screen") {
    PasswordViewPreview()
}