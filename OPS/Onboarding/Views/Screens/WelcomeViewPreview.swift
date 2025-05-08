//
//  WelcomeViewPreview.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

// MARK: - Preview for WelcomeView
struct WelcomeViewPreview: View {
    var body: some View {
        let viewModel = OnboardingViewModel()
        
        return WelcomeView(viewModel: viewModel)
            .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
            .environment(\.colorScheme, .dark)
    }
}

#Preview("Welcome Screen") {
    WelcomeViewPreview()
}