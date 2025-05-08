//
//  NotificationsViewPreview.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

// MARK: - Preview for NotificationsView
struct NotificationsViewPreview: View {
    var body: some View {
        let viewModel = OnboardingViewModel()
        viewModel.email = "user@example.com"
        viewModel.password = "password123"
        viewModel.firstName = "John"
        viewModel.lastName = "Doe"
        viewModel.phoneNumber = "5551234567"
        viewModel.isLocationPermissionGranted = true
        
        return NotificationsView(viewModel: viewModel)
            .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
            .environment(\.colorScheme, .dark)
    }
}

#Preview("Notifications Screen") {
    NotificationsViewPreview()
}