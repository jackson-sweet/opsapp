//
//  ShareTheme.swift
//  OPSShareExtension
//
//  Self-contained design tokens for the share extension's picker UI.
//
//  WHY THIS EXISTS (and isn't just OPSStyle): an app extension is a separate
//  bundle and cannot resolve the app's asset-catalog colors (OPSStyle uses
//  `Color("AccentPrimary")` etc., which only exist in the OPS.app asset
//  catalog). So the extension reproduces the exact token VALUES from the OPS
//  design system as literals here. These MIRROR `OPS/Styles/OPSStyle.swift` and
//  the design system — keep them in sync; do not improvise new values.
//

import SwiftUI

enum ShareTheme {

    // MARK: - Color (literal mirrors of OPSStyle / DESIGN.md)

    enum Color {
        /// #000000 — pure black canvas.
        static let background = SwiftUI.Color.black
        /// #6F94B0 — steel-blue accent. The ONLY accent; used for the selected
        /// row + primary CTA. Never decorative.
        static let accent = SwiftUI.Color(red: 0x6F / 255, green: 0x94 / 255, blue: 0xB0 / 255)
        /// #EDEDED — primary text.
        static let textPrimary = SwiftUI.Color(red: 0xED / 255, green: 0xED / 255, blue: 0xED / 255)
        /// #B5B5B5 — secondary text.
        static let textSecondary = SwiftUI.Color(red: 0xB5 / 255, green: 0xB5 / 255, blue: 0xB5 / 255)
        /// #8A8A8A — tertiary text.
        static let textTertiary = SwiftUI.Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x8A / 255)
        /// #6A6A6A — muted / decorative text.
        static let textMute = SwiftUI.Color(red: 0x6A / 255, green: 0x6A / 255, blue: 0x6A / 255)
        /// #9DB582 — olive, success.
        static let success = SwiftUI.Color(red: 0x9D / 255, green: 0xB5 / 255, blue: 0x82 / 255)
        /// #B58289 — muted rose, destructive/error state.
        static let error = SwiftUI.Color(red: 0xB5 / 255, green: 0x82 / 255, blue: 0x89 / 255)

        /// Input field fill (white @ 4%).
        static let surfaceInput = SwiftUI.Color.white.opacity(0.04)
        /// Hover / interactive row fill (white @ 5%).
        static let surfaceHover = SwiftUI.Color.white.opacity(0.05)
        /// Active / selected fill (white @ 8%).
        static let surfaceActive = SwiftUI.Color.white.opacity(0.08)
        /// Standard hairline (white @ 10%).
        static let line = SwiftUI.Color.white.opacity(0.10)
    }

    // MARK: - Spacing (OPSStyle.Layout)

    enum Spacing {
        static let none: CGFloat = 0
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s2_5: CGFloat = 12
        static let s3: CGFloat = 16
        static let s3_5: CGFloat = 20
        static let s4: CGFloat = 24
        static let s5: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let chip: CGFloat = 4
        static let button: CGFloat = 5
        static let card: CGFloat = 6
        static let panel: CGFloat = 10
    }

    // MARK: - Touch targets (glove-friendly, MOBILE.md)

    enum Size {
        static let touchMin: CGFloat = 44
        static let touchStandard: CGFloat = 56
        static let touchLarge: CGFloat = 64
        static let cta: CGFloat = 56
        static let outcomeCircle: CGFloat = 72
        static let outcomeGlyph: CGFloat = 30
        static let messageGlyph: CGFloat = 44
        static let smallGlyph: CGFloat = 16
        static let selectionControl: CGFloat = 22
        static let selectionGlyph: CGFloat = 12
    }

    enum Border {
        static let hairline: CGFloat = 1
        static let selected: CGFloat = 1.5
    }

    enum Opacity {
        static let semanticSoft: Double = 0.12
    }

    // MARK: - Motion

    enum Motion {
        /// OPS's single deceleration curve. State changes are quick and settled;
        /// never spring or bounce.
        static let state = SwiftUI.Animation.timingCurve(
            0.22,
            1,
            0.36,
            1,
            duration: 0.2
        )
        static let press = SwiftUI.Animation.timingCurve(
            0.22,
            1,
            0.36,
            1,
            duration: 0.15
        )
        static let pressedScale: CGFloat = 0.98
    }

    // MARK: - Typography (Mohave / JetBrains Mono / Cake Mono)

    enum Font {
        /// Cake Mono Light — uppercase display / authority.
        static func title(_ size: CGFloat = 22) -> SwiftUI.Font { .custom("CakeMono-Light", size: size) }
        static func buttonLabel(_ size: CGFloat = 14) -> SwiftUI.Font { .custom("CakeMono-Light", size: size) }
        /// Mohave — body, names.
        static func body(_ size: CGFloat = 16) -> SwiftUI.Font { .custom("Mohave-Regular", size: size) }
        static func bodyBold(_ size: CGFloat = 16) -> SwiftUI.Font { .custom("Mohave-Medium", size: size) }
        static func bodyLight(_ size: CGFloat = 14) -> SwiftUI.Font { .custom("Mohave-Light", size: size) }
        /// JetBrains Mono — numbers, [brackets], micro labels.
        static func mono(_ size: CGFloat = 13) -> SwiftUI.Font { .custom("JetBrainsMono-Regular", size: size) }
        static func monoMedium(_ size: CGFloat = 12) -> SwiftUI.Font { .custom("JetBrainsMono-Medium", size: size) }

        // Semantic picker roles. Screen code never invents font sizes.
        static let headerTitle = title(20)
        static let headerMetadata = monoMedium(11)
        static let cancelAction = body(15)
        static let searchBody = body(16)
        static let statusMetadata = mono(13)
        static let outcomeTitle = title(24)
        static let messageTitle = title(18)
        static let rowTitle = bodyBold(16)
        static let rowMetadata = mono(12)
        static let primaryAction = buttonLabel(14)
        static let errorLabel = monoMedium(10)
        static let errorMessage = bodyLight(14)
    }

    enum Tracking {
        /// MOBILE.md error label: 0.14em at 10pt.
        static let errorLabel: CGFloat = 1.4
    }
}
