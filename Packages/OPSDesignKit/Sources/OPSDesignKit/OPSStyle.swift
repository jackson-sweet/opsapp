//
//  OPSStyle.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// OPSStyle.swift
import SwiftUI
#if canImport(UIKit)
import UIKit  // UIAccessibility.isReduceMotionEnabled (reduce-motion-aware Animation tokens)
#elseif canImport(AppKit)
import AppKit
#endif

private enum OPSDesignBundle {
    static let bundle = Bundle.module
}

private func opsColor(_ name: String) -> Color {
    Color(name, bundle: OPSDesignBundle.bundle)
}

/// The main styling system for the OPS app — spec v2 (2026-04-17).
///
/// Canonical source of truth: `ops-design-system/project/DESIGN.md` + `mobile/MOBILE.md`.
///
/// Semantic tokens (prefer these for new code):
///
///   Colors
///   ─────────────────────────────────────────────────
///   opsAccent      #6F94B0  primary CTA + focus ring ONLY
///   text           #EDEDED  primary body, hero numbers, names, active nav
///   text2          #B5B5B5  secondary values, ghost buttons, links
///   text3          #8A8A8A  labels, metadata, subtitles, placeholders
///   textMute       #6A6A6A  decorative ONLY — `//` slashes, separators
///   olive          #9DB582  success / completed / nominal / +delta
///   tan            #C4A868  attention / warning / site visit / expiring
///   rose           #B58289  error / overdue / cost
///   brick          #93321A  destructive borders/dots ONLY — not body text
///
///   Radii (sharp, tactical — no 999px pills except avatars)
///   ─────────────────────────────────────────────────
///   panelRadius         10  cards, widgets, panels
///   modalRadius         12  modals, popovers, dropdowns, toasts
///   buttonRadius         5  buttons, inputs
///   chipRadius           4  tags, badges, chips
///   progressBarRadius    2  funnel bars, progress tracks
///   sidebarHoverRadius   6  sidebar hover background
///
///   Motion: single easing curve `cubic-bezier(0.22, 1, 0.36, 1)` — no spring.
///
/// Legacy token names (primaryAccent, cardBackground, cornerRadius, etc.) are
/// preserved as aliases so existing call sites keep compiling. Prefer the new
/// semantic names above in any new or touched code.
///
/// For reusable UI components, see Styles/Components/.
///
public enum OPSStyle {
    // MARK: - Colors
    public enum Colors {
        // Brand colors
        public static let primaryAccent = opsColor("AccentPrimary")   // #6F94B0 steel blue — prefer `opsAccent`
        public static let secondaryAccent = opsColor("AccentSecondary") // #C4A868 tan — prefer `tan`

        // Background colors (legacy — prefer `.glassSurface()` / `.glassDense()` modifiers)
        public static let background = opsColor("Background")                // #000000 pure black
        public static let darkBackground = opsColor("DarkBackground")        // #090C15 (legacy — deprecated)
        public static let cardBackground = opsColor("CardBackground")        // #191919 flat card (legacy — migrate to glass)
        public static let cardBackgroundDark = opsColor("CardBackgroundDark") // #0D0D0D (legacy — deprecated)
        public static let statusBackground = opsColor("StatusBackground")    // #1D1D1D (legacy — deprecated)

        // Border colors (spec v2 — hairline-quiet, not heavy)
        public static let cardBorder = Color.white.opacity(0.09) // Glass panel edge — was 0.2, aligned to --glass-border
        public static let cardBorderSubtle = Color.white.opacity(0.05) // Subtle card border for less prominent cards
        public static let inputFieldBorder = Color.white.opacity(0.10) // Input fields, text editors — was 0.2, aligned to --line
        public static let buttonBorder = Color.white.opacity(0.10) // Secondary action buttons — was 0.4, aligned to --line
        public static let darkBorder = Color.black.opacity(0.5) // Dark borders; used by GracePeriodBanner
        
        // Text colors (prefer `text` / `text2` / `text3` / `textMute` below)
        public static let primaryText   = opsColor("TextPrimary")     // #EDEDED — prefer `text`
        public static let secondaryText = opsColor("TextSecondary")   // #B5B5B5 — prefer `text2`
        public static let tertiaryText  = opsColor("TextTertiary")    // #8A8A8A — prefer `text3`
        public static let inactiveText  = opsColor("TextInactive")    // #6A6A6A — prefer `textMute` (decorative only)

        // Status colors
        public static let successStatus  = opsColor("StatusSuccess")  // #9DB582 olive — prefer `olive`
        public static let warningStatus  = opsColor("StatusWarning")  // #C4A868 tan — prefer `tan`
        public static let errorStatus    = opsColor("StatusError")    // #93321A brick — prefer `brick` (border) or `rose` (text)
        public static let inactiveStatus = opsColor("StatusInactive") // #8E8E93 gray
        public static let statusRFQ = opsColor("StatusRFQ")
        public static let statusEstimated = opsColor("StatusEstimated")
        public static let statusAccepted = opsColor("StatusAccepted")
        public static let statusInProgress = opsColor("StatusInProgress")
        public static let statusCompleted = opsColor("StatusCompleted")
        public static let statusClosed = opsColor("StatusClosed")
        public static let statusArchived = opsColor("StatusArchived")

        // Mobile-bright status tag variants (outdoor glare set, per MOBILE.md).
        // Use on tags/badges that need to read in direct sunlight.
        public static let oliveMobile = opsColor("StatusSuccessMobile")  // #B5C998
        public static let tanMobile   = opsColor("StatusWarningMobile")  // #DBC07F
        public static let roseMobile  = opsColor("StatusErrorMobile")    // #C99AA1

        // Web parity: 0.06 alpha for subtle dividers inside cards / chart gridlines.
        public static let lineSoft = Color.white.opacity(0.06)

        // Status text colors (for foreground, not background)
        // Reuse existing status asset colors for text as well
        public static let errorText = opsColor("StatusError")     // Same as errorStatus - works for both bg and text
        public static let successText = opsColor("StatusSuccess") // Same as successStatus - works for both bg and text
        public static let warningText = opsColor("StatusWarning") // Same as warningStatus - works for both bg and text

        // Status background colors (for banner/alert backgrounds)
        public static let warningBackground = opsColor("StatusWarning").opacity(0.1) // Warning banner backgrounds

        // UI state colors
        public static let disabledText = opsColor("TextTertiary") // Reuse tertiaryText for disabled state
        public static let placeholderText = Color(red: 0.6, green: 0.6, blue: 0.6)  // #999999 (medium gray)

        // Button-specific colors
        public static let buttonText = Color.white  // For text on accent backgrounds
        public static let invertedText = Color.black  // For light-on-dark inversions

        // Wizard accent (muted warm amber — used for wizard highlights, onboarding spotlights)
        public static let wizardAccent = Color(red: 0.85, green: 0.68, blue: 0.35) // #D9AD59

        // Overlays & Loading
        public static let modalOverlay = Color.black.opacity(0.5)  // Modal and loading overlay backgrounds
        public static let imageOverlay = Color.black.opacity(0.7)  // Photo/image overlays (for thumbnails, photo grids)
        public static let overlayMedium = Color.black.opacity(0.6)   // Medium overlay (tooltips, dimming)
        public static let overlayStrong = Color.black.opacity(0.7)   // Strong overlay (popups, menus) — same value as imageOverlay
        public static let overlayHeavy = Color.black.opacity(0.85)   // Heavy overlay (full-screen dimming)
        public static let avatarOverlay = Color.black.opacity(0.3) // Avatar badge overlays
        public static let loadingSpinner = opsColor("TextPrimary")    // Loading spinner/ProgressView tint (white)

        // Calendar-specific
        public static let todayHighlight = opsColor("AccentPrimary").opacity(0.5)  // Today's date background in calendar

        // UI State Indicators
        public static let pageIndicatorInactive = Color.white.opacity(0.5) // Inactive page indicator dots in carousels
        public static let pinDotNeutral = Color.white.opacity(0.3) // PIN entry neutral/inactive state; also used by TacticalLoadingBar empty color
        public static let pinDotActive = Color.white.opacity(0.8)  // PIN entry active state; also used by TacticalLoadingBar fill color

        // Shadows
        public static let shadowColor = Color.black.opacity(0.15)  // Standard shadow (consolidated from 0.15, 0.3, 0.5 variations)

        // Separators & Subtle Backgrounds
        public static let separator = Color.white.opacity(0.10)  // For divider lines — was 0.15, aligned to --line
        public static let subtleBackground = Color.white.opacity(0.1) // Subtle row backgrounds within cards (consolidated from 0.05, 0.1 variations)

        // Accounting palette
        public static let accountingRevenue = opsColor("Accounting/AccountingRevenue")     // Amber gold (#C4A868)
        public static let accountingProfit = opsColor("Accounting/AccountingProfit")       // Muted green (#9DB582)
        public static let accountingCost = opsColor("Accounting/AccountingCost")           // Muted rose (#B58289)
        public static let accountingReceivables = opsColor("Accounting/AccountingReceivables") // Warm amber (#D4A574)
        public static let accountingOverdue = opsColor("Accounting/AccountingOverdue")     // Deep red (#93321A)
        
        // Gradients
        public static let backgroundGradient = LinearGradient(
            gradient: Gradient(colors: [opsColor("BackgroundGradientStart"), opsColor("BackgroundGradientEnd")]),
            startPoint: .top,
            endPoint: .bottom
        )

        // MARK: - Semantic tokens (spec v2 — preferred for new code)
        //
        // These are the canonical names from the design system. Prefer them over
        // the legacy names above (primaryAccent, secondaryAccent, primaryText, …).
        // The legacy names remain as aliases so existing call sites keep compiling.

        // Accent — primary CTA and focus ring ONLY. Never on links, toggles, nav, tags.
        public static let opsAccent = opsColor("AccentPrimary")     // #6F94B0 steel blue

        // Text ladder — `textMute` is decorative only (`//`, separators).
        public static let text      = opsColor("TextPrimary")       // #EDEDED
        public static let text2     = opsColor("TextSecondary")     // #B5B5B5
        public static let text3     = opsColor("TextTertiary")      // #8A8A8A
        public static let textMute  = opsColor("TextInactive")      // #6A6A6A

        // Earth tones — semantic only, never decorative.
        public static let olive     = opsColor("StatusSuccess")     // #9DB582 positive / success / completed
        public static let tan       = opsColor("AccentSecondary")   // #C4A868 attention / warning / site visit
        public static let rose      = opsColor("Rose")              // #B58289 negative / error / overdue / cost
        public static let brick     = opsColor("StatusError")       // #93321A destructive border/dot ONLY

        // Soft fills and hairlines derived from earth tones (12% / 30% alpha).
        public static let oliveSoft = opsColor("StatusSuccess").opacity(0.12)
        public static let oliveLine = opsColor("StatusSuccess").opacity(0.30)
        public static let tanSoft   = opsColor("AccentSecondary").opacity(0.12)
        public static let tanLine   = opsColor("AccentSecondary").opacity(0.30)
        public static let roseSoft  = opsColor("Rose").opacity(0.12)
        public static let roseLine  = opsColor("Rose").opacity(0.30)
        public static let brickLine = opsColor("StatusError").opacity(0.50)

        // Mobile outdoor-glare uplift per `ops-design-system/project/mobile/MOBILE.md` §1.
        // Earth-tones at higher fill / border / text contrast than their desktop variants.
        // Use these in any mobile UI; the legacy soft / line variants remain for non-mobile
        // surfaces (desktop OPS-Web parity).
        //   • fillM   — 20% alpha (vs 12% desktop)
        //   • lineM   — 55% alpha (vs 30% desktop)
        //   • textM   — tone hex shifted ~25% brighter than the base
        public static let oliveFillM = opsColor("StatusSuccess").opacity(0.20)
        public static let oliveLineM = opsColor("StatusSuccess").opacity(0.55)
        public static let oliveTextM = Color(red: 0.710, green: 0.788, blue: 0.627)   // #B5C9A0
        public static let tanFillM   = opsColor("AccentSecondary").opacity(0.20)
        public static let tanLineM   = opsColor("AccentSecondary").opacity(0.55)
        public static let tanTextM   = Color(red: 0.839, green: 0.737, blue: 0.510)   // #D6BC82
        public static let roseFillM  = opsColor("Rose").opacity(0.20)
        public static let roseLineM  = opsColor("Rose").opacity(0.55)
        public static let roseTextM  = Color(red: 0.788, green: 0.612, blue: 0.639)   // #C99CA3

        // Financial
        public static let finRevenue     = opsColor("AccentSecondary")   // #C4A868 revenue / income
        public static let finProfit      = opsColor("StatusSuccess")     // #9DB582 profit
        public static let finCost        = opsColor("Rose")              // #B58289 expense / cost
        public static let finReceivables = opsColor("FinReceivables")    // #D4A574 outstanding receivables
        public static let finOverdue     = opsColor("StatusError")       // #93321A past-due

        // Surfaces — transparent fills used over #000000 canvas.
        public static let surfaceInput   = Color.white.opacity(0.04)  // Input field fill
        public static let surfaceHover   = Color.white.opacity(0.05)  // Interactive row / button hover
        public static let surfaceActive  = Color.white.opacity(0.08)  // Active toggle, pressed state

        // Borders & neutral fills
        public static let line           = Color.white.opacity(0.10)  // Standard hairline — panels, inputs, L1 dividers
        public static let glassBorder    = Color.white.opacity(0.09)  // L1 glass panel edge (MOBILE.md §3)
        public static let nestedBorder   = Color.white.opacity(0.08)  // L2 nested-card edge (MOBILE.md §3)
        public static let fillNeutral    = Color.white.opacity(0.14)  // Bar fills, progress tracks
        public static let fillNeutralDim = Color.white.opacity(0.06)  // Track backgrounds, skeletons

        // Glass approximation — prefer the `.glassSurface()` / `.glassDense()` view
        // modifiers in Phase 4 which layer `.ultraThinMaterial` + border + top gradient.
        // These flat approximations are a fallback only.
        public static let glassApprox      = Color(red: 18/255, green: 18/255, blue: 20/255).opacity(0.58)
        public static let glassDenseApprox = Color(red: 18/255, green: 18/255, blue: 20/255).opacity(0.78)

        // MARK: - Light Theme (Employee Onboarding)
        public enum Light {
            // Background colors
            public static let background = Color.white
            public static let cardBackground = Color(red: 0.95, green: 0.95, blue: 0.97) // Light gray
            public static let cardBackgroundDark = Color(red: 0.92, green: 0.92, blue: 0.95) // Slightly darker light gray
            
            // Text colors
            public static let primaryText = Color.black
            public static let secondaryText = Color(red: 0.4, green: 0.4, blue: 0.4) // Medium gray
            public static let tertiaryText = Color(red: 0.6, green: 0.6, blue: 0.6) // Light gray
            
            // Brand colors (keep the same)
            public static let primaryAccent = Colors.primaryAccent
            public static let secondaryAccent = Colors.secondaryAccent
            
            // Status colors (keep the same)
            public static let successStatus = Colors.successStatus
            public static let warningStatus = Colors.warningStatus
            public static let errorStatus = Colors.errorStatus
            public static let inactiveStatus = Colors.inactiveStatus
        }
        
    }
    
    // MARK: - Typography (spec v2)
    //
    // Three families, each with one job:
    //   • Mohave          — body, names, hero numbers
    //   • JetBrains Mono  — numbers, timestamps, `//` prefixes, `[brackets]`, micro labels
    //   • Cake Mono Light — uppercase display voice (titles, buttons, badges, sections)
    //
    public enum Typography {

        // MARK: New semantic roles (spec v2 — prefer these for new code)

        /// Hero number — Mohave Light 80pt (dashboard hero, revenue total)
        public static let hero = Font.custom("Mohave-Light", size: 80)

        /// Hero number on carousel cards — Mohave Light 60pt.
        /// Tracking (-0.025em) and tabular-nums applied at call site, not here.
        public static let heroNumber = Font.custom("Mohave-Light", size: 60)

        /// Hero number on CONDENSED carousel cards — Mohave Light 38pt.
        /// Compact glance variant of `heroNumber`; full 60pt lives in the
        /// expand-to-sheet detail. Tracking + tabular-nums applied at call site.
        public static let heroNumberCondensed = Font.custom("Mohave-Light", size: 38)

        /// Page title — Cake Mono Light 22pt (TopBar H1, root-route page heading)
        public static let pageTitle = Font.custom("CakeMono-Light", size: 22)

        /// Display heading — Cake Mono Light 30pt (auth h1s, wizard step titles)
        public static let display = Font.custom("CakeMono-Light", size: 30)

        /// Screen title — Cake Mono Light 28pt. The canonical screen / nav-bar
        /// header per MOBILE.md §2.1: uppercase, left-aligned, `Colors.text`.
        /// For dynamic titles, prefer `screenTitle(for:)` so long strings drop
        /// to 22pt automatically.
        public static let screenTitle = Font.custom("CakeMono-Light", size: 28)

        /// Long-title variant of `screenTitle` — Cake Mono Light 22pt (>14 chars).
        public static let screenTitleLong = Font.custom("CakeMono-Light", size: 22)

        /// Picks the screen-title font by length: 28pt normally, 22pt once the
        /// title exceeds 14 characters (MOBILE.md §2.1 long-title rule).
        public static func screenTitle(for title: String) -> Font {
            title.count > 14 ? screenTitleLong : screenTitle
        }

        /// Section heading — Cake Mono Light 18pt (settings subheads)
        public static let section = Font.custom("CakeMono-Light", size: 18)

        /// Button label — Cake Mono Light 14pt (primary / secondary button text)
        public static let buttonLabel = Font.custom("CakeMono-Light", size: 14)

        /// Badge — Cake Mono Light 11pt
        public static let badgeCake = Font.custom("CakeMono-Light", size: 11)

        /// Panel title — JetBrains Mono 11pt (widget and section titles, with `//` prefix)
        public static let panelTitle = Font.custom("JetBrainsMono-Regular", size: 11)

        /// Data value (large) — JetBrains Mono Medium 20pt (hero metrics)
        public static let dataValueLg = Font.custom("JetBrainsMono-Medium", size: 20)

        /// Data value — JetBrains Mono 13pt (standard data values)
        public static let dataValue = Font.custom("JetBrainsMono-Regular", size: 13)

        /// Category label — JetBrains Mono 11pt (BOOKED, INVOICED)
        public static let category = Font.custom("JetBrainsMono-Regular", size: 11)

        /// Metadata — JetBrains Mono 11pt (timestamps, IDs, subtotals)
        public static let metadata = Font.custom("JetBrainsMono-Regular", size: 11)

        // MARK: Legacy roles (preserved so existing call sites keep compiling)

        // Titles
        public static let largeTitle = Font.custom("Mohave-Bold", size: 32)
        public static let title = Font.custom("Mohave-SemiBold", size: 28)
        public static let subtitle = Font.custom("JetBrainsMono-Regular", size: 22)

        // Body text (Mohave)
        public static let body = Font.custom("Mohave-Regular", size: 16)
        public static let bodyBold = Font.custom("Mohave-Medium", size: 16)
        public static let bodyEmphasis = Font.custom("Mohave-SemiBold", size: 16)

        // Supporting text (→ JetBrains Mono)
        public static let caption = Font.custom("JetBrainsMono-Regular", size: 14)
        public static let captionBold = Font.custom("JetBrainsMono-Medium", size: 14)
        public static let smallCaption = Font.custom("JetBrainsMono-Regular", size: 12)
        public static let smallBody = Font.custom("Mohave-Light", size: 14)

        // Cards
        public static let cardTitle = Font.custom("Mohave-Medium", size: 18)
        public static let cardSubtitle = Font.custom("JetBrainsMono-Regular", size: 15)
        public static let cardBody = Font.custom("Mohave-Regular", size: 14)

        // Status text → JetBrains Mono Medium 12pt (uppercase at call site)
        public static let status = Font.custom("JetBrainsMono-Medium", size: 12)

        // Buttons — `buttonLabel` (Cake Mono Light) is the new primary role
        public static let button = Font.custom("Mohave-Regular", size: 16)
        public static let smallButton = Font.custom("Mohave-Medium", size: 14)
        public static let smallButtonBold = Font.custom("Mohave-Medium", size: 14).weight(.bold)
        public static let buttonLarge = Font.custom("Mohave-SemiBold", size: 18)

        // Compact UI labels (legacy Kosugi → remapped to JetBrains Mono)
        public static let miniLabel = Font.custom("JetBrainsMono-Regular", size: 10)
        public static let microLabel = Font.custom("JetBrainsMono-Regular", size: 11)
        public static let tagLabel = Font.custom("JetBrainsMono-Regular", size: 12)
        public static let previewLabel = Font.custom("JetBrainsMono-Regular", size: 18)
        public static let sectionLabel = Font.custom("JetBrainsMono-Regular", size: 12)

        // Legacy headings (Mohave)
        public static let heading = Font.custom("Mohave-Medium", size: 20)
        public static let headingBold = Font.custom("Mohave-Bold", size: 22)
        public static let headingLarge = Font.custom("Mohave-SemiBold", size: 24)

        // Legacy display (Mohave)
        public static let displayLarge = Font.custom("Mohave-Bold", size: 48)
        public static let displayQuantity = Font.custom("Mohave-Bold", size: 56)
        public static let displayXL = Font.custom("Mohave-Bold", size: 60)

        // Legacy monospaced numeric display — for dimensions, measurements, stair specs
        public static let headlineMono = SwiftUI.Font.system(size: 24, weight: .bold, design: .monospaced)
        public static let titleMono = SwiftUI.Font.system(size: 20, weight: .bold, design: .monospaced)
        public static let monoValue = SwiftUI.Font.system(size: 14, weight: .bold, design: .monospaced)
    }
    
    // MARK: - Layout
    public enum Layout {
        // Standard spacing
        public static let spacing1 = 4.0
        public static let spacing2 = 8.0
        public static let spacing3 = 16.0
        public static let spacing2_5: CGFloat = 12.0  // Between spacing2 (8) and spacing3 (16)
        public static let spacing3_5: CGFloat = 20.0  // Between spacing3 (16) and spacing4 (24)
        public static let spacing4 = 24.0
        public static let spacing5 = 32.0

        // Content padding
        public static let contentPadding = EdgeInsets(
            top: spacing3,
            leading: spacing3,
            bottom: spacing3,
            trailing: spacing3
        )

        // Touch targets - Minimum 44×44 as per Apple HIG, but we go larger for field use
        public static let touchTargetMin = 44.0
        public static let touchTargetStandard = 56.0
        public static let touchTargetLarge = 64.0

        // Mobile control heights — `ops-design-system/project/mobile/MOBILE.md`.
        // Spec'd component heights that sit between the touch-target presets.
        public static let inputHeight: CGFloat = 48.0          // §9 text input height (mobile touch)
        public static let bottomCTAHeight: CGFloat = 52.0      // §8 bottom-anchored primary CTA (thumb zone)
        public static let chipMinHeight: CGFloat = 36.0        // §4.3 filter / form-picker chip — the one sanctioned sub-44pt target

        // MARK: - Corner radius (spec v2 — sharp, tactical, no 999px pills)
        // Prefer the new semantic names (panelRadius, chipRadius, etc.).
        // Legacy names are kept as aliases so existing call sites still compile.

        // New semantic names
        public static let panelRadius = 10.0         // Cards, widgets, panels (L1 glass surfaces)
        public static let modalRadius = 12.0         // Modals, popovers, dropdowns, toasts
        public static let cardRadius = 6.0           // L2 nested cards — KPI tiles, peer-grouped chips
        public static let chipRadius = 4.0           // Tags, badges, chips
        public static let progressBarRadius = 2.0    // Funnel bars, progress tracks
        public static let sidebarHoverRadius = 6.0   // Sidebar hover background

        // Legacy aliases (retained for backwards compatibility — values updated to spec)
        public static let cornerRadius = 5.0         // Standard inputs / general small containers (spec: buttons/inputs = 5)
        public static let buttonRadius = 5.0         // Buttons (spec: 5)
        public static let smallCornerRadius = 4.0    // Was 2.5 — now aligned to chipRadius
        public static let cardCornerRadius = 10.0    // Was 8 — now aligned to panelRadius
        public static let largeCornerRadius = 12.0   // Modals / sheets (spec: 12) — aligned to modalRadius

        // Icon sizes
        public enum IconSize {
            public static let xs: CGFloat = 12.0   // Tiny indicators
            public static let sm: CGFloat = 16.0   // Inline icons, captions
            public static let md: CGFloat = 20.0   // Standard icons
            public static let lg: CGFloat = 24.0   // Section header icons
            public static let xl: CGFloat = 32.0   // Action icons, prominent UI
            public static let xxl: CGFloat = 48.0  // Large decorative icons (location overlay, etc.)
        }

        // Tab bar icon size
        public static let tabBarIconSize: CGFloat = 28.0

        // Border widths
        public enum Border {
            public static let standard: CGFloat = 1.0
            public static let thick: CGFloat = 2.0
        }

        // Dot/indicator sizes
        public enum Indicator {
            public static let dotSM: CGFloat = 6.0
            public static let dotMD: CGFloat = 8.0
        }

        // Opacity presets
        public enum Opacity {
            public static let subtle = 0.1   // Disabled, very light overlays
            public static let light = 0.3    // Light overlays
            public static let medium = 0.5   // Medium overlays
            public static let strong = 0.7   // Strong overlays
            public static let heavy = 0.9    // Almost opaque
        }

        // Shadow presets — DEPRECATED (spec v2: zero box-shadows on dark backgrounds.
        // Depth = glass + hairlines only. Kept for backward compat — do NOT use in new code.)
        public enum Shadow {
            public static let card = (color: Color.black.opacity(0.1), radius: 4.0, x: 0.0, y: 2.0)
            public static let elevated = (color: Color.black.opacity(0.2), radius: 8.0, x: 0.0, y: 4.0)
            public static let floating = (color: Color.black.opacity(0.3), radius: 12.0, x: 0.0, y: 6.0)
        }

        // Gradient presets
        public enum Gradients {
            // Header fade: opaque to transparent (used by HomeContentView header)
            public static let headerFade = LinearGradient(
                colors: [Color.black.opacity(1), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Carousel left fade: dark to transparent (used by JobBoardDashboard carousel)
            public static let carouselFadeLeft = LinearGradient(
                colors: [Color.black.opacity(0.8), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Carousel right fade: transparent to dark (used by JobBoardDashboard carousel)
            public static let carouselFadeRight = LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Page indicator fade: transparent to dark to opaque (used by JobBoardDashboard page indicators)
            public static let pageIndicatorFade = LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.8), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        // SearchField styling configuration
        public enum SearchField {
            // Input field styling
            public static let inputPadding: CGFloat = 12
            public static let inputBackground = OPSStyle.Colors.surfaceInput
            public static let inputCornerRadius = OPSStyle.Layout.cornerRadius
            public static let inputBorderColor = OPSStyle.Colors.inputFieldBorder
            public static let inputBorderWidth: CGFloat = 1

            // Icon styling
            public static let iconSize: CGFloat = 14
            public static let iconColor = OPSStyle.Colors.secondaryText
            public static let clearButtonSize: CGFloat = 16
            public static let clearButtonColor = OPSStyle.Colors.tertiaryText

            // Text styling
            public static let textFont = OPSStyle.Typography.body
            public static let textColor = OPSStyle.Colors.primaryText
            public static let placeholderColor = OPSStyle.Colors.placeholderText

            // Suggestions dropdown styling
            public static let dropdownBackground = OPSStyle.Colors.surfaceInput
            public static let dropdownCornerRadius = OPSStyle.Layout.cornerRadius
            public static let dropdownBorderColor = OPSStyle.Colors.inputFieldBorder
            public static let dropdownBorderWidth: CGFloat = 1
            public static let dropdownShadowColor = OPSStyle.Colors.shadowColor
            public static let dropdownShadowRadius: CGFloat = 8
            public static let dropdownShadowOffset = CGSize(width: 0, height: 4)
            public static let dropdownTopPadding: CGFloat = 4
            public static let dropdownMaxResults = 5

            // Suggestion row styling
            public static let rowPaddingHorizontal: CGFloat = 16
            public static let rowPaddingVertical: CGFloat = 12
            public static let rowTitleFont = OPSStyle.Typography.body
            public static let rowTitleColor = OPSStyle.Colors.primaryText
            public static let rowSubtitleFont = OPSStyle.Typography.caption
            public static let rowSubtitleColor = OPSStyle.Colors.secondaryText
            public static let rowIconSize: CGFloat = 14
            public static let rowCheckmarkSize: CGFloat = 14
            public static let rowCheckmarkColor = OPSStyle.Colors.primaryAccent

            // Divider styling
            public static let dividerColor = OPSStyle.Colors.tertiaryText.opacity(0.3)

            // Animation
            public static let animationDuration: CGFloat = 0.2
            public static let animationCurve = SwiftUI.Animation.easeInOut(duration: 0.2)
            public static let transition = AnyTransition.opacity.combined(with: .move(edge: .top))
        }
    }
    
    // MARK: - Animation (spec v2 — single easing curve, no spring physics)
    //
    // One curve for everything: `cubic-bezier(0.22, 1, 0.36, 1)` (EASE_SMOOTH).
    // No spring, no bounce. Exception: drag-and-drop reorder only.
    // Every animation must respect reduced-motion — fall back to 150ms opacity crossfade.
    //
    public enum Animation {
        // MARK: Easing — the single authorized curve
        /// Control points of the one OPS easing curve: `cubic-bezier(0.22, 1, 0.36, 1)`.
        /// Fast start, smooth finish, confident stop. Pass these to `Animation.timingCurve(...)`
        /// or use one of the pre-built `.hover` / `.panel` / `.page` / `.flip` values below.
        public static let easeSmoothP1x: Double = 0.22
        public static let easeSmoothP1y: Double = 1.0
        public static let easeSmoothP2x: Double = 0.36
        public static let easeSmoothP2y: Double = 1.0

        // MARK: Durations (named per spec)
        public static let durationHover:    Double = 0.150  // 150ms — hover transitions
        public static let durationPanel:    Double = 0.200  // 200ms — panel enter
        public static let durationPage:     Double = 0.250  // 250ms — page transitions
        public static let durationStagger:  Double = 0.300  // 300ms base + 50ms per item — row stagger
        public static let durationStaggerStep: Double = 0.050
        public static let durationChartBar: Double = 0.400  // 400-600ms — chart bar grow (add index delay)
        public static let durationFlip:     Double = 0.350  // 350ms — card flip
        public static let durationCountUp:  Double = 0.800  // 800ms — hero number count-up

        // MARK: Reduce-motion (spec v2 §8/§14 — "always honor prefers-reduced-motion")
        // Every pre-built token below is a COMPUTED value that reads the system
        // setting at animation-creation time and softens to a 150ms crossfade when
        // Reduce Motion is on. This makes ~all token-based animations app-wide honor
        // the setting with zero call-site changes — fix lives in one place.
        /// True when the user has enabled Reduce Motion in platform accessibility settings.
        public static var reduceMotion: Bool {
#if canImport(UIKit)
            UIAccessibility.isReduceMotionEnabled
#elseif canImport(AppKit)
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
#else
            false
#endif
        }
        /// Reduce-motion fallback — gentle 150ms crossfade (no slide/scale character).
        public static let reducedFallback = SwiftUI.Animation.easeInOut(duration: 0.150)
        /// The single OPS curve at `duration`, or the reduce-motion fallback.
        public static func curve(_ duration: Double) -> SwiftUI.Animation {
            reduceMotion ? reducedFallback : .timingCurve(0.22, 1, 0.36, 1, duration: duration)
        }

        // MARK: Pre-built Animation values (reduce-motion aware)
        public static var hover: SwiftUI.Animation { curve(durationHover) }
        public static var panel: SwiftUI.Animation { curve(durationPanel) }
        public static var page:  SwiftUI.Animation { curve(durationPage) }
        public static var flip:  SwiftUI.Animation { curve(durationFlip) }

        // MARK: Legacy aliases (reduce-motion aware; retained for backwards compatibility)
        /// Deprecated — prefer `.page` (250ms). Kept for existing call sites.
        public static var standard: SwiftUI.Animation { curve(0.250) }
        /// Deprecated — prefer `.hover` (150ms). Kept for existing call sites.
        public static var quick:    SwiftUI.Animation { curve(0.150) }
        /// Deprecated — prefer `.hover` (150ms).
        public static var fast:     SwiftUI.Animation { reduceMotion ? reducedFallback : .easeInOut(duration: 0.2) }
        public static var faster:   SwiftUI.Animation { reduceMotion ? reducedFallback : .easeOut(duration: 0.15) }
        // Spring tokens — DEPRECATED. Spec v2 bans spring physics (no bounce); these
        // now resolve to the single OPS curve so every legacy call site conforms.
        // The genuine drag-and-drop reorder exception uses raw `.spring(...)` at its
        // call site (PriorityQueueView), not these tokens.
        public static var spring:     SwiftUI.Animation { curve(0.300) }
        public static var springFast: SwiftUI.Animation { curve(0.200) }
    }

    // MARK: - Icons
    public enum Icons {
        // MARK: - OPS Domain Semantic Icons
        // These are THE standardized icons for core OPS concepts
        // Always use these for their designated purpose to maintain consistency

        // Core entities
        public static let project = "folder.fill"                  // THE icon for Projects
        public static let task = "checklist"                       // THE icon for Tasks
        public static let taskType = "tag.fill"                    // THE icon for Task Types
        public static let client = "person.circle.fill"            // THE icon for Clients
        public static let subClient = "person.2.fill"              // THE icon for Sub-clients
        public static let teamMember = "person.fill"               // THE icon for Team Members
        public static let crew = "person.3.fill"                   // THE icon for Crews/Teams

        // Scheduling & Time
        public static let schedule = "calendar.badge.clock"        // THE icon for Scheduling
        public static let deadline = "calendar.badge.exclamationmark" // THE icon for Deadlines
        public static let duration = "clock.fill"                  // THE icon for Duration/Time

        // Location & Site
        public static let jobSite = "location.fill"                // THE icon for Job Sites
        public static let address = "mappin.and.ellipse"           // THE icon for Addresses

        // Content & Media
        public static let notes = "note.text"                      // THE icon for Notes
        public static let description = "text.alignleft"           // THE icon for Description
        public static let photos = "photo.on.rectangle"            // THE icon for Photos
        public static let documents = "doc.text.fill"              // THE icon for Documents

        // Actions
        public static let add = "plus.circle.fill"                 // THE icon for Add/Create
        public static let edit = "pencil.circle.fill"              // THE icon for Edit
        public static let delete = "trash.fill"                    // THE icon for Delete
        public static let sync = "arrow.triangle.2.circlepath"     // THE icon for Sync
        public static let share = "square.and.arrow.up"            // THE icon for Share
        public static let filter = "line.horizontal.3.decrease.circle" // THE icon for Filter
        public static let sort = "arrow.up.arrow.down.circle"      // THE icon for Sort
        public static let addContact = "person.crop.circle.badge.plus" // THE icon for Add from Contacts
        public static let addProject = "folder.badge.plus"         // THE icon for Create Project

        // Status & State
        public static let complete = "checkmark.circle.fill"       // THE icon for Complete
        public static let incomplete = "circle"                    // THE icon for Incomplete
        public static let inProgress = "clock.arrow.circlepath"    // THE icon for In Progress (if needed)
        public static let alert = "exclamationmark.triangle.fill"  // THE icon for Alerts/Warnings
        public static let error = "xmark.octagon.fill"             // THE icon for Errors
        public static let info = "info.circle.fill"                // THE icon for Information

        // System
        public static let settings = "gearshape.fill"              // THE icon for Settings
        public static let search = "magnifyingglass"               // THE icon for Search
        public static let menu = "line.3.horizontal"               // THE icon for Menu
        public static let close = "xmark"                          // THE icon for Close/Dismiss
        public static let back = "chevron.left"                    // THE icon for Back navigation
        public static let forward = "chevron.right"                // THE icon for Forward navigation
        public static let arrowRight = "arrow.right"               // THE icon for a directional right arrow (list-row affordance)

        // MARK: - Legacy SF Symbols (Currently in Use)
        // These are used in existing code - during Track F migration, replace with semantic icons above
        // Example: Replace `OPSStyle.Icons.calendar` with `OPSStyle.Icons.schedule`

        public static let calendar = "calendar"
        public static let calendarFill = "calendar.fill"
        public static let calendarBadgeCheckmark = "calendar.badge.checkmark"
        public static let person = "person"
        public static let personFill = "person.fill"
        public static let personTwo = "person.2"
        public static let personTwoFill = "person.2.fill"
        public static let personCircle = "person.circle"
        public static let personCircleFill = "person.circle.fill"
        public static let location = "location"
        public static let locationFill = "location.fill"
        public static let phone = "phone"
        public static let phoneFill = "phone.fill"
        public static let envelope = "envelope"
        public static let envelopeFill = "envelope.fill"
        public static let folder = "folder"
        public static let folderFill = "folder.fill"
        public static let checklist = "checklist"
        public static let checkmark = "checkmark"
        public static let checkmarkSquare = "checkmark.square"
        public static let checkmarkSquareFill = "checkmark.square.fill"
        public static let checkmarkCircle = "checkmark.circle"
        public static let checkmarkCircleFill = "checkmark.circle.fill"
        public static let circle = "circle"
        public static let square = "square"
        public static let squareFill = "square.fill"
        public static let xmark = "xmark"
        public static let xmarkCircle = "xmark.circle"
        public static let xmarkCircleFill = "xmark.circle.fill"
        public static let chevronRight = "chevron.right"
        public static let chevronLeft = "chevron.left"
        public static let chevronUp = "chevron.up"
        public static let chevronDown = "chevron.down"
        public static let plus = "plus"
        public static let plusCircle = "plus.circle"
        public static let plusCircleFill = "plus.circle.fill"
        public static let minus = "minus"
        public static let minusCircle = "minus.circle"
        public static let minusCircleFill = "minus.circle.fill"
        public static let exclamationmarkTriangle = "exclamationmark.triangle"
        public static let exclamationmarkTriangleFill = "exclamationmark.triangle.fill"
        public static let gearshape = "gearshape"
        public static let gearshapeFill = "gearshape.fill"
        public static let house = "house"
        public static let houseFill = "house.fill"
        public static let map = "map"
        public static let mapFill = "map.fill"
        public static let ellipsis = "ellipsis"
        public static let ellipsisCircle = "ellipsis.circle"
        public static let ellipsisCircleFill = "ellipsis.circle.fill"
        public static let listBullet = "list.bullet"
        public static let trash = "trash"
        public static let trashFill = "trash.fill"
        public static let pencil = "pencil"
        public static let pencilCircle = "pencil.circle"
        public static let pencilCircleFill = "pencil.circle.fill"
        public static let arrowClockwise = "arrow.clockwise"
        public static let arrowCounterclockwise = "arrow.counterclockwise"
        public static let magnifyingglass = "magnifyingglass"
        public static let magnifyingglassCircle = "magnifyingglass.circle"
        public static let magnifyingglassCircleFill = "magnifyingglass.circle.fill"
        public static let bellFill = "bell.fill"
        public static let photo = "photo"
        public static let photoFill = "photo.fill"
        public static let camera = "camera"
        public static let cameraFill = "camera.fill"
        public static let clock = "clock"
        public static let copy = "doc.on.doc"

        // Pipeline & Financial (Feb 2026)
        public static let opportunity      = "arrow.up.right.circle.fill"
        public static let pipelineChart    = "chart.bar.doc.horizontal.fill"
        public static let estimateDoc      = "doc.text.fill"
        public static let invoiceReceipt   = "receipt"
        public static let paymentDollar    = "dollarsign.circle.fill"
        public static let siteVisitPin     = "mappin.circle.fill"
        public static let activityBubble   = "bubble.left.and.text.bubble.right.fill"
        public static let followUpAlarm    = "alarm.fill"
        public static let stageAdvance     = "arrow.forward.circle.fill"
        public static let dealWon          = "checkmark.seal.fill"
        public static let dealLost         = "xmark.seal.fill"
        public static let accountingChart  = "chart.bar.fill"
        public static let productTag       = "tag.fill"
        public static let inventoryTracking = "shippingbox.circle.fill" // Inventory tracking on/off (stock state) — NOT the sync glyph
        public static let stale            = "exclamationmark.triangle.fill"
        public static let expense          = "dollarsign.circle"
        public static let banknoteFill     = "banknote.fill"
        public static let undo             = "arrow.uturn.backward"
        public static let sendFill         = "arrow.up.circle.fill"
        public static let bell             = "bell"
        public static let mention          = "at"
        public static let assignmentNotification = "person.badge.plus"
        public static let pencilTip        = "pencil.tip"
        public static let receipt          = "doc.text.viewfinder"
        public static let clockFill        = "clock.fill"
        public static let exclamationmarkCircleFill = "exclamationmark.circle.fill"
        public static let lockFill         = "lock.fill"
    }

    // MARK: - Wizard
    public enum Wizard {
        public static let accentColor = Colors.wizardAccent
        public static let pulseDuration: Double = 1.0

        /// Button / tappable element — rounded rectangle glow
        public enum Button {
            public static let fillOpacityHigh: Double = 0.35
            public static let fillOpacityLow: Double = 0.15
            public static let borderOpacityHigh: Double = 0.9
            public static let borderOpacityLow: Double = 0.4
            public static let borderWidth: CGFloat = 2
            public static let cornerRadius: CGFloat = Layout.cornerRadius
        }

        /// Circular element — FAB, avatar, round button
        public enum Circle {
            public static let fillOpacityHigh: Double = 0.35
            public static let fillOpacityLow: Double = 0.15
            public static let borderOpacityHigh: Double = 0.9
            public static let borderOpacityLow: Double = 0.4
            public static let borderWidth: CGFloat = 2
        }

        /// Input field — subtle fill so text stays readable, prominent border
        public enum Input {
            public static let fillOpacityHigh: Double = 0.12
            public static let fillOpacityLow: Double = 0.04
            public static let borderOpacityHigh: Double = 0.9
            public static let borderOpacityLow: Double = 0.4
            public static let borderWidth: CGFloat = 2
            public static let cornerRadius: CGFloat = Layout.smallCornerRadius
        }

        /// List row / card — full-width highlight
        public enum Row {
            public static let fillOpacityHigh: Double = 0.25
            public static let fillOpacityLow: Double = 0.10
            public static let borderOpacityHigh: Double = 0.7
            public static let borderOpacityLow: Double = 0.3
            public static let borderWidth: CGFloat = 1.5
            public static let cornerRadius: CGFloat = Layout.cornerRadius
        }
    }

    // MARK: - Inventory
    public enum Inventory {
        /// Size variants for tag badges
        public enum TagSize {
            case compact   // For display in cards, lists
            case standard  // Default size
            case button    // Larger for touch targets in management screens

            public var font: Font {
                switch self {
                case .compact: return Typography.smallCaption
                case .standard: return Typography.smallCaption
                case .button: return Typography.caption
                }
            }

            public var paddingHorizontal: CGFloat {
                switch self {
                case .compact: return 6
                case .standard: return 6
                case .button: return 12
                }
            }

            public var paddingVertical: CGFloat {
                switch self {
                case .compact: return 2
                case .standard: return 2
                case .button: return 8
                }
            }

            public var cornerRadius: CGFloat {
                switch self {
                case .compact: return 4
                case .standard: return 4
                case .button: return 6
                }
            }
        }

        // Tag badge styling (monochromatic)
        public enum TagBadge {
            public static let font = Typography.smallCaption
            public static let textColor = Colors.secondaryText
            public static let backgroundColor = Colors.cardBackgroundDark
            public static let borderColor = Colors.cardBorder
            public static let paddingHorizontal: CGFloat = 8
            public static let paddingVertical: CGFloat = 4
            public static let cornerRadius: CGFloat = Layout.cornerRadius
            public static let spacing: CGFloat = 6
        }

        // Status/threshold badge styling
        public enum ThresholdBadge {
            public static let font = Typography.smallCaption
            public static let paddingHorizontal: CGFloat = 6
            public static let paddingVertical: CGFloat = 2
            public static let cornerRadius: CGFloat = 4
            public static let maxWidth: CGFloat = 60
        }

        // Card scaling
        public enum CardScale {
            public static let minScale: CGFloat = 0.8
            public static let maxScale: CGFloat = 1.5
            public static let tagVisibilityThreshold: CGFloat = 0.9
            public static let metadataVisibilityThreshold: CGFloat = 1.0
        }
    }
}
