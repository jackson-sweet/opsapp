//
//  Fonts.swift
//  OPS
//
//  OPS typography system — spec v2 (2026-04-17).
//  Three font families, each with one job:
//
//    • Mohave            — body copy, names, hero numbers
//    • JetBrains Mono    — numbers, timestamps, `//` prefixes, `[brackets]`, micro labels
//    • Cake Mono Light   — uppercase display voice (titles, buttons, badges, section headers)
//
//  Kosugi and Bebas Neue were deprecated 2026-04-17 and removed from the bundle.
//  Every former Kosugi role now maps to JetBrains Mono.
//

import Foundation
import SwiftUI

extension Font {

    // MARK: - Display voice (Cake Mono Light)
    //
    // The uppercase, confident, branded voice. Always weight 300 (Light).
    // Call sites should apply `.textCase(.uppercase)` at the view level.

    /// Page title — Cake Mono Light 22pt (TopBar H1, root-route page heading)
    public static var pageTitle: Font {
        return Font.custom("CakeMono-Light", size: 22)
    }

    /// Display heading — Cake Mono Light 30pt (auth h1s, wizard step titles)
    public static var display: Font {
        return Font.custom("CakeMono-Light", size: 30)
    }

    /// Section heading — Cake Mono Light 18pt (settings subheads, admin section headers)
    public static var section: Font {
        return Font.custom("CakeMono-Light", size: 18)
    }

    /// Button label — Cake Mono Light 14pt (primary / secondary button text)
    public static var buttonLabel: Font {
        return Font.custom("CakeMono-Light", size: 14)
    }

    /// Badge (Cake Mono variant) — Cake Mono Light 11pt
    public static var badgeCake: Font {
        return Font.custom("CakeMono-Light", size: 11)
    }

    // MARK: - Data / tactical voice (JetBrains Mono)
    //
    // Numbers, timestamps, `//` prefixes, `[brackets]`, micro labels, shortcut chips.
    // Always rendered with `.monospacedDigit()` plus tabular-lining via feature settings
    // where possible (SwiftUI doesn't expose `font-feature-settings` directly — use
    // `.monospacedDigit()` on the view modifier for tabular-lining behavior).

    /// Panel title — JetBrains Mono 11pt (widget and section titles, prefixed with `//`)
    public static var panelTitle: Font {
        return Font.custom("JetBrainsMono-Regular", size: 11)
    }

    /// Data value (large) — JetBrains Mono Medium 20pt (hero metrics in widgets)
    public static var dataValueLg: Font {
        return Font.custom("JetBrainsMono-Medium", size: 20)
    }

    /// Data value — JetBrains Mono 13pt (standard data values)
    public static var dataValue: Font {
        return Font.custom("JetBrainsMono-Regular", size: 13)
    }

    /// Category label — JetBrains Mono 11pt (BOOKED, INVOICED, etc.)
    public static var category: Font {
        return Font.custom("JetBrainsMono-Regular", size: 11)
    }

    /// Metadata — JetBrains Mono 11pt (timestamps, IDs, subtotals)
    public static var metadata: Font {
        return Font.custom("JetBrainsMono-Regular", size: 11)
    }

    // MARK: - Body / narrative (Mohave)

    /// Hero number — Mohave Light 80pt (dashboard hero, revenue total)
    public static var hero: Font {
        return Font.custom("Mohave-Light", size: 80)
    }

    /// Body text — Mohave Regular 16pt
    public static var body: Font {
        return Font.custom("Mohave-Regular", size: 16)
    }

    /// Bold body text — Mohave Medium 16pt
    public static var bodyBold: Font {
        return Font.custom("Mohave-Medium", size: 16)
    }

    /// Emphasized body text — Mohave SemiBold 16pt
    public static var bodyEmphasis: Font {
        return Font.custom("Mohave-SemiBold", size: 16)
    }

    /// Small body text — Mohave Light 14pt
    public static var smallBody: Font {
        return Font.custom("Mohave-Light", size: 14)
    }

    /// Card body text — Mohave Regular 14pt
    public static var cardBody: Font {
        return Font.custom("Mohave-Regular", size: 14)
    }

    // MARK: - Legacy role names (mapped to new fonts)
    //
    // These names are preserved so existing call sites continue to compile.
    // Each role has been remapped to match the spec v2 voice assignment.
    // Prefer the new role names above for any new code.

    /// Large title — Mohave Bold 32pt (non-uppercase display)
    public static var largeTitle: Font {
        return Font.custom("Mohave-Bold", size: 32)
    }

    /// Title — Mohave SemiBold 28pt (non-uppercase display)
    public static var title: Font {
        return Font.custom("Mohave-SemiBold", size: 28)
    }

    /// Subtitle — formerly Kosugi 22pt. Now JetBrains Mono 22pt for tactical feel.
    public static var subtitle: Font {
        return Font.custom("JetBrainsMono-Regular", size: 22)
    }

    /// Caption text — formerly Kosugi 14pt. Now JetBrains Mono 14pt.
    public static var caption: Font {
        return Font.custom("JetBrainsMono-Regular", size: 14)
    }

    /// Bold caption — formerly Kosugi 14pt. Now JetBrains Mono Medium 14pt.
    public static var captionBold: Font {
        return Font.custom("JetBrainsMono-Medium", size: 14)
    }

    /// Small caption — formerly Kosugi 12pt. Now JetBrains Mono 12pt
    /// (content rendered with bracket wrapping — `[caption text]`).
    public static var smallCaption: Font {
        return Font.custom("JetBrainsMono-Regular", size: 12)
    }

    /// Card title — Mohave Medium 18pt
    public static var cardTitle: Font {
        return Font.custom("Mohave-Medium", size: 18)
    }

    /// Card subtitle — formerly Kosugi 15pt. Now JetBrains Mono 15pt.
    public static var cardSubtitle: Font {
        return Font.custom("JetBrainsMono-Regular", size: 15)
    }

    /// Status text — JetBrains Mono Medium 12pt (uppercase at call site)
    public static var status: Font {
        return Font.custom("JetBrainsMono-Medium", size: 12)
    }

    /// Button text — legacy name. New primary surface should use `.buttonLabel` (Cake Mono Light).
    /// Kept at Mohave Regular 16pt for any view still depending on a sentence-case button.
    public static var button: Font {
        return Font.custom("Mohave-Regular", size: 16)
    }

    /// Small button text — Mohave Medium 14pt.
    public static var smallButton: Font {
        return Font.custom("Mohave-Medium", size: 14)
    }
}
