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
    
    /// Small button text - Kosugi Regular (12pt) — ALL CAPS via .textCase(.uppercase)
    public static var smallButton: Font {
        return Font.custom("Kosugi-Regular", size: 12)
    }

    /// Button text - Kosugi Regular (14pt) — ALL CAPS via .textCase(.uppercase)
    public static var button: Font {
        return Font.custom("Kosugi-Regular", size: 14)
    }

    /// Section label - Kosugi Regular (12pt) — ALL CAPS, tracked
    public static var sectionLabel: Font {
        return Font.custom("Kosugi-Regular", size: 12)
    }

    // MARK: - Dynamic Sizing

    /// Avatar initials — Mohave Bold, dynamically sized relative to the avatar frame.
    /// Use for initials inside Circle/RoundedRectangle avatars where size varies.
    public static func avatarInitials(size: CGFloat) -> Font {
        return Font.custom("Mohave-Bold", size: size)
    }

    // MARK: - Compact UI Labels (Kosugi)

    /// Mini label — Kosugi Regular (10pt). Avatar initials inside small circles (28-32pt).
    public static var miniLabel: Font {
        return Font.custom("Kosugi-Regular", size: 10)
    }

    /// Micro label — Kosugi Regular (11pt). Sheet section labels, toolbar cancel buttons.
    public static var microLabel: Font {
        return Font.custom("Kosugi-Regular", size: 11)
    }

    /// Tag label — Kosugi Regular (12pt). Small tags, dependency bar labels, chip text.
    public static var tagLabel: Font {
        return Font.custom("Kosugi-Regular", size: 12)
    }

    /// Preview label — Kosugi Regular (18pt). Task type preview badges, large chip text.
    public static var previewLabel: Font {
        return Font.custom("Kosugi-Regular", size: 18)
    }

    // MARK: - Additional Sizes

    /// Button large — Mohave SemiBold (18pt). Medium-prominence buttons (Reset, secondary actions).
    public static var buttonLarge: Font {
        return Font.custom("Mohave-SemiBold", size: 18)
    }

    /// Heading text - Mohave Medium (20pt)
    public static var heading: Font {
        return Font.custom("Mohave-Medium", size: 20)
    }

    /// Heading bold — Mohave Bold (22pt). Large avatar initials, prominent display text.
    public static var headingBold: Font {
        return Font.custom("Mohave-Bold", size: 22)
    }

    /// Large heading text - Mohave SemiBold (24pt)
    public static var headingLarge: Font {
        return Font.custom("Mohave-SemiBold", size: 24)
    }

    /// Quantity display — Mohave Bold (56pt). Inventory quantity counters.
    public static var displayQuantity: Font {
        return Font.custom("Mohave-Bold", size: 56)
    }

    /// Display large - Mohave Bold (48pt)
    public static var displayLarge: Font {
        return Font.custom("Mohave-Bold", size: 48)
    }

    /// Display extra large - Mohave Bold (60pt)
    public static var displayXL: Font {
        return Font.custom("Mohave-Bold", size: 60)
    }
}
