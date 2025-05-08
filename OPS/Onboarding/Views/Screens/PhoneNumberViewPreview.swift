//
//  PhoneNumberViewPreview.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

// MARK: - Preview for PhoneNumberView
struct PhoneNumberViewPreview: View {
    var body: some View {
        let viewModel = OnboardingViewModel()
        viewModel.email = "user@example.com"
        viewModel.password = "password123"
        viewModel.firstName = "John"
        viewModel.lastName = "Doe"
        viewModel.phoneNumber = "555-123-4567"
        
        return PhoneNumberView(viewModel: viewModel)
            .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
            .environment(\.colorScheme, .dark)
    }
}

#Preview("Phone Number Screen") {
    PhoneNumberViewPreview()
}