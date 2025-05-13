//
//  Fonts.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-12.
//

import Foundation
import SwiftUI

extension Font {
    // MARK: - Title Fonts (Mohave)
    
    /// Large title - Mohave Bold (32pt)
    public static var largeTitle: Font {
        return Font.custom("Mohave-Bold", size: 32)
    }
    
    /// Title - Mohave SemiBold (28pt)
    public static var title: Font {
        return Font.custom("Mohave-SemiBold", size: 28)
    }
    
    /// Subtitle - Kosugi Regular (22pt)
    public static var subtitle: Font {
        return Font.custom("Kosugi-Regular", size: 22)
    }
    
    // MARK: - Body Fonts (Mohave)
    
    /// Body text - Mohave Regular (16pt)
    public static var body: Font {
        return Font.custom("Mohave-Regular", size: 16)
    }
    
    /// Bold body text - Mohave Medium (16pt)
    public static var bodyBold: Font {
        return Font.custom("Mohave-Medium", size: 16)
    }
    
    /// Emphasized body text - Mohave SemiBold (16pt)
    public static var bodyEmphasis: Font {
        return Font.custom("Mohave-SemiBold", size: 16)
    }
    
    // MARK: - Supporting Text (Kosugi)
    
    /// Caption text - Kosugi Regular (14pt)
    public static var caption: Font {
        return Font.custom("Kosugi-Regular", size: 14)
    }
    
    /// Bold caption - Kosugi Regular (14pt)
    public static var captionBold: Font {
        return Font.custom("Kosugi-Regular", size: 14)
    }
    
    /// Small caption - Kosugi Regular (12pt)
    public static var smallCaption: Font {
        return Font.custom("Kosugi-Regular", size: 12)
    }
    
    /// Small body text - Mohave Light (14pt)
    public static var smallBody: Font {
        return Font.custom("Mohave-Light", size: 14)
    }
    
    // MARK: - Card Fonts
    
    /// Card title - Mohave Medium (18pt)
    public static var cardTitle: Font {
        return Font.custom("Mohave-Medium", size: 18)
    }
    
    /// Card subtitle - Kosugi Regular (15pt)
    public static var cardSubtitle: Font {
        return Font.custom("Kosugi-Regular", size: 15)
    }
    
    /// Card body text - Mohave Regular (14pt)
    public static var cardBody: Font {
        return Font.custom("Mohave-Regular", size: 14)
    }
    
    // MARK: - UI Elements
    
    /// Status text - Mohave Medium (12pt)
    public static var status: Font {
        return Font.custom("Mohave-Medium", size: 12)
    }
    
    /// Small button text - Mohave Medium (14pt)
    public static var smallButton: Font {
        return Font.custom("Mohave-Medium", size: 14)
    }
    
    /// Button text - Mohave SemiBold (16pt)
    public static var button: Font {
        return Font.custom("Mohave-SemiBold", size: 16)
    }
}
