//
//  OnboardingPreviewHelpers.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

/// Preview helpers for onboarding screens
struct OnboardingPreviewHelpers {
    
    /// Mock OPSStyle for previews
    class PreviewStyles: ObservableObject {
        struct Colors {
            static let primaryAccent = Color.blue // Use actual accent color in real app
            static let background = Color.black
            static let primaryText = Color.white
            static let secondaryText = Color.gray
            static let cardBackground = Color(white: 0.1)
        }
        
        struct Typography {
            static let title = Font.system(size: 24, weight: .bold)
            static let body = Font.system(size: 16)
            static let caption = Font.system(size: 12)
            static let smallCaption = Font.system(size: 10, weight: .medium)
            static let bodyBold = Font.system(size: 16, weight: .bold)
            static let captionBold = Font.system(size: 12, weight: .bold)
            static let largeTitle = Font.system(size: 34, weight: .bold)
        }
        
        struct Layout {
            static let spacing1: CGFloat = 4
            static let spacing2: CGFloat = 8
            static let spacing3: CGFloat = 12
            static let spacing4: CGFloat = 16
            static let spacing5: CGFloat = 24
            static let cornerRadius: CGFloat = 8
            static let buttonRadius: CGFloat = 8
        }
    }
}

// Helper for OPSStyle in previews
extension OnboardingPreviewHelpers.PreviewStyles: Equatable {
    static func == (lhs: OnboardingPreviewHelpers.PreviewStyles, rhs: OnboardingPreviewHelpers.PreviewStyles) -> Bool {
        return true
    }
}

// Extensions to make styles available globally for previews
extension OnboardingPreviewHelpers {
    struct OPSStyle {
        typealias Colors = PreviewStyles.Colors
        typealias Typography = PreviewStyles.Typography
        typealias Layout = PreviewStyles.Layout
    }
}