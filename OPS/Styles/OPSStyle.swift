//
//  OPSStyle.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// OPSStyle.swift
import SwiftUI

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
enum OPSStyle {
    // MARK: - Colors
    enum Colors {
        // Brand colors
        static let primaryAccent = Color("AccentPrimary")   // #6F94B0 steel blue — prefer `opsAccent`
        static let secondaryAccent = Color("AccentSecondary") // #C4A868 tan — prefer `tan`

        // Background colors (legacy — prefer `.glassSurface()` / `.glassDense()` modifiers)
        static let background = Color("Background")                // #000000 pure black
        static let darkBackground = Color("DarkBackground")        // #090C15 (legacy — deprecated)
        static let cardBackground = Color("CardBackground")        // #191919 flat card (legacy — migrate to glass)
        static let cardBackgroundDark = Color("CardBackgroundDark") // #0D0D0D (legacy — deprecated)
        static let statusBackground = Color("StatusBackground")    // #1D1D1D (legacy — deprecated)

        // Border colors (spec v2 — hairline-quiet, not heavy)
        static let cardBorder = Color.white.opacity(0.09) // Glass panel edge — was 0.2, aligned to --glass-border
        static let cardBorderSubtle = Color.white.opacity(0.05) // Subtle card border for less prominent cards
        static let inputFieldBorder = Color.white.opacity(0.10) // Input fields, text editors — was 0.2, aligned to --line
        static let buttonBorder = Color.white.opacity(0.10) // Secondary action buttons — was 0.4, aligned to --line
        static let darkBorder = Color.black.opacity(0.5) // Dark borders; used by GracePeriodBanner
        
        // Text colors (prefer `text` / `text2` / `text3` / `textMute` below)
        static let primaryText   = Color("TextPrimary")     // #EDEDED — prefer `text`
        static let secondaryText = Color("TextSecondary")   // #B5B5B5 — prefer `text2`
        static let tertiaryText  = Color("TextTertiary")    // #8A8A8A — prefer `text3`
        static let inactiveText  = Color("TextInactive")    // #6A6A6A — prefer `textMute` (decorative only)

        // Status colors
        static let successStatus  = Color("StatusSuccess")  // #9DB582 olive — prefer `olive`
        static let warningStatus  = Color("StatusWarning")  // #C4A868 tan — prefer `tan`
        static let errorStatus    = Color("StatusError")    // #93321A brick — prefer `brick` (border) or `rose` (text)
        static let inactiveStatus = Color("StatusInactive") // #8E8E93 gray

        // Mobile-bright status tag variants (outdoor glare set, per MOBILE.md).
        // Use on tags/badges that need to read in direct sunlight.
        static let oliveMobile = Color("StatusSuccessMobile")  // #B5C998
        static let tanMobile   = Color("StatusWarningMobile")  // #DBC07F
        static let roseMobile  = Color("StatusErrorMobile")    // #C99AA1

        // Web parity: 0.06 alpha for subtle dividers inside cards / chart gridlines.
        static let lineSoft = Color.white.opacity(0.06)

        // Status text colors (for foreground, not background)
        // Reuse existing status asset colors for text as well
        static let errorText = Color("StatusError")     // Same as errorStatus - works for both bg and text
        static let successText = Color("StatusSuccess") // Same as successStatus - works for both bg and text
        static let warningText = Color("StatusWarning") // Same as warningStatus - works for both bg and text

        // Status background colors (for banner/alert backgrounds)
        static let warningBackground = Color("StatusWarning").opacity(0.1) // Warning banner backgrounds

        // UI state colors
        static let disabledText = Color("TextTertiary") // Reuse tertiaryText for disabled state
        static let placeholderText = Color(red: 0.6, green: 0.6, blue: 0.6)  // #999999 (medium gray)

        // Button-specific colors
        static let buttonText = Color.white  // For text on accent backgrounds
        static let invertedText = Color.black  // For light-on-dark inversions

        // Wizard accent (muted warm amber — used for wizard highlights, onboarding spotlights)
        static let wizardAccent = Color(red: 0.85, green: 0.68, blue: 0.35) // #D9AD59

        // Overlays & Loading
        static let modalOverlay = Color.black.opacity(0.5)  // Modal and loading overlay backgrounds
        static let imageOverlay = Color.black.opacity(0.7)  // Photo/image overlays (for thumbnails, photo grids)
        static let overlayMedium = Color.black.opacity(0.6)   // Medium overlay (tooltips, dimming)
        static let overlayStrong = Color.black.opacity(0.7)   // Strong overlay (popups, menus) — same value as imageOverlay
        static let overlayHeavy = Color.black.opacity(0.85)   // Heavy overlay (full-screen dimming)
        static let avatarOverlay = Color.black.opacity(0.3) // Avatar badge overlays
        static let loadingSpinner = Color("TextPrimary")    // Loading spinner/ProgressView tint (white)

        // Calendar-specific
        static let todayHighlight = Color("AccentPrimary").opacity(0.5)  // Today's date background in calendar

        // UI State Indicators
        static let pageIndicatorInactive = Color.white.opacity(0.5) // Inactive page indicator dots in carousels
        static let pinDotNeutral = Color.white.opacity(0.3) // PIN entry neutral/inactive state; also used by TacticalLoadingBar empty color
        static let pinDotActive = Color.white.opacity(0.8)  // PIN entry active state; also used by TacticalLoadingBar fill color

        // Shadows
        static let shadowColor = Color.black.opacity(0.15)  // Standard shadow (consolidated from 0.15, 0.3, 0.5 variations)

        // Separators & Subtle Backgrounds
        static let separator = Color.white.opacity(0.10)  // For divider lines — was 0.15, aligned to --line
        static let subtleBackground = Color.white.opacity(0.1) // Subtle row backgrounds within cards (consolidated from 0.05, 0.1 variations)

        // Accounting palette
        static let accountingRevenue = Color("Accounting/AccountingRevenue")     // Amber gold (#C4A868)
        static let accountingProfit = Color("Accounting/AccountingProfit")       // Muted green (#9DB582)
        static let accountingCost = Color("Accounting/AccountingCost")           // Muted rose (#B58289)
        static let accountingReceivables = Color("Accounting/AccountingReceivables") // Warm amber (#D4A574)
        static let accountingOverdue = Color("Accounting/AccountingOverdue")     // Deep red (#93321A)
        
        // Gradients
        static let backgroundGradient = LinearGradient(
            gradient: Gradient(colors: [Color("BackgroundGradientStart"), Color("BackgroundGradientEnd")]),
            startPoint: .top,
            endPoint: .bottom
        )

        // MARK: - Semantic tokens (spec v2 — preferred for new code)
        //
        // These are the canonical names from the design system. Prefer them over
        // the legacy names above (primaryAccent, secondaryAccent, primaryText, …).
        // The legacy names remain as aliases so existing call sites keep compiling.

        // Accent — primary CTA and focus ring ONLY. Never on links, toggles, nav, tags.
        static let opsAccent = Color("AccentPrimary")     // #6F94B0 steel blue

        // Text ladder — `textMute` is decorative only (`//`, separators).
        static let text      = Color("TextPrimary")       // #EDEDED
        static let text2     = Color("TextSecondary")     // #B5B5B5
        static let text3     = Color("TextTertiary")      // #8A8A8A
        static let textMute  = Color("TextInactive")      // #6A6A6A

        // Earth tones — semantic only, never decorative.
        static let olive     = Color("StatusSuccess")     // #9DB582 positive / success / completed
        static let tan       = Color("AccentSecondary")   // #C4A868 attention / warning / site visit
        static let rose      = Color("Rose")              // #B58289 negative / error / overdue / cost
        static let brick     = Color("StatusError")       // #93321A destructive border/dot ONLY

        // Soft fills and hairlines derived from earth tones (12% / 30% alpha).
        static let oliveSoft = Color("StatusSuccess").opacity(0.12)
        static let oliveLine = Color("StatusSuccess").opacity(0.30)
        static let tanSoft   = Color("AccentSecondary").opacity(0.12)
        static let tanLine   = Color("AccentSecondary").opacity(0.30)
        static let roseSoft  = Color("Rose").opacity(0.12)
        static let roseLine  = Color("Rose").opacity(0.30)
        static let brickLine = Color("StatusError").opacity(0.50)

        // Mobile outdoor-glare uplift per `ops-design-system/project/mobile/MOBILE.md` §1.
        // Earth-tones at higher fill / border / text contrast than their desktop variants.
        // Use these in any mobile UI; the legacy soft / line variants remain for non-mobile
        // surfaces (desktop OPS-Web parity).
        //   • fillM   — 20% alpha (vs 12% desktop)
        //   • lineM   — 55% alpha (vs 30% desktop)
        //   • textM   — tone hex shifted ~25% brighter than the base
        static let oliveFillM = Color("StatusSuccess").opacity(0.20)
        static let oliveLineM = Color("StatusSuccess").opacity(0.55)
        static let oliveTextM = Color(red: 0.710, green: 0.788, blue: 0.627)   // #B5C9A0
        static let tanFillM   = Color("AccentSecondary").opacity(0.20)
        static let tanLineM   = Color("AccentSecondary").opacity(0.55)
        static let tanTextM   = Color(red: 0.839, green: 0.737, blue: 0.510)   // #D6BC82
        static let roseFillM  = Color("Rose").opacity(0.20)
        static let roseLineM  = Color("Rose").opacity(0.55)
        static let roseTextM  = Color(red: 0.788, green: 0.612, blue: 0.639)   // #C99CA3

        // Financial
        static let finRevenue     = Color("AccentSecondary")   // #C4A868 revenue / income
        static let finProfit      = Color("StatusSuccess")     // #9DB582 profit
        static let finCost        = Color("Rose")              // #B58289 expense / cost
        static let finReceivables = Color("FinReceivables")    // #D4A574 outstanding receivables
        static let finOverdue     = Color("StatusError")       // #93321A past-due

        // Surfaces — transparent fills used over #000000 canvas.
        static let surfaceInput   = Color.white.opacity(0.04)  // Input field fill
        static let surfaceHover   = Color.white.opacity(0.05)  // Interactive row / button hover
        static let surfaceActive  = Color.white.opacity(0.08)  // Active toggle, pressed state

        // Borders & neutral fills
        static let line           = Color.white.opacity(0.10)  // Standard hairline — panels, inputs
        static let glassBorder    = Color.white.opacity(0.09)  // Glass panel edge
        static let fillNeutral    = Color.white.opacity(0.14)  // Bar fills, progress tracks
        static let fillNeutralDim = Color.white.opacity(0.06)  // Track backgrounds, skeletons

        // Glass approximation — prefer the `.glassSurface()` / `.glassDense()` view
        // modifiers in Phase 4 which layer `.ultraThinMaterial` + border + top gradient.
        // These flat approximations are a fallback only.
        static let glassApprox      = Color(red: 18/255, green: 18/255, blue: 20/255).opacity(0.58)
        static let glassDenseApprox = Color(red: 18/255, green: 18/255, blue: 20/255).opacity(0.78)

        // MARK: - Light Theme (Employee Onboarding)
        enum Light {
            // Background colors
            static let background = Color.white
            static let cardBackground = Color(red: 0.95, green: 0.95, blue: 0.97) // Light gray
            static let cardBackgroundDark = Color(red: 0.92, green: 0.92, blue: 0.95) // Slightly darker light gray
            
            // Text colors
            static let primaryText = Color.black
            static let secondaryText = Color(red: 0.4, green: 0.4, blue: 0.4) // Medium gray
            static let tertiaryText = Color(red: 0.6, green: 0.6, blue: 0.6) // Light gray
            
            // Brand colors (keep the same)
            static let primaryAccent = Colors.primaryAccent
            static let secondaryAccent = Colors.secondaryAccent
            
            // Status colors (keep the same)
            static let successStatus = Colors.successStatus
            static let warningStatus = Colors.warningStatus
            static let errorStatus = Colors.errorStatus
            static let inactiveStatus = Colors.inactiveStatus
        }
        
        // MARK: - Pipeline stage colors (spec v2 — each stage is globally unique)
        // Cool slate → steel → teal → warm gold → amber → terracotta, branching to
        // olive (won) / rose (lost). Every hex is unique across all enum palettes.
        static func pipelineStageColor(for stage: PipelineStage) -> Color {
            switch stage {
            case .newLead:     return Color(hex: "#6A7A8A")! // cool slate
            case .qualifying:  return Color(hex: "#6F94B0")! // = opsAccent (steel)
            case .quoting:     return Color(hex: "#7CA5B8")! // teal-steel
            case .quoted:      return Color(hex: "#BFAE8A")! // warm gold
            case .followUp:    return Color(hex: "#C4A868")! // = tan
            case .negotiation: return Color(hex: "#CA9670")! // terracotta
            case .won:         return Color(hex: "#9DB582")! // = olive
            case .lost:        return Color(hex: "#B58289")! // = rose
            case .discarded:   return Color(hex: "#5A5E66")! // muted graphite (discarded)
            }
        }

        static func statusColor(for status: Status) -> Color {
            switch status {
            case .rfq:
                return Color("StatusRFQ")
            case .estimated:
                return Color("StatusEstimated")
            case .accepted:
                return Color("StatusAccepted")
            case .inProgress:
                return Color("StatusInProgress")
            case .completed:
                return Color("StatusCompleted")
            case .closed:
                return Color("StatusClosed")
            case .archived:
                return Color("StatusArchived")
            }
        }
    }
    
    // MARK: - Typography (spec v2)
    //
    // Three families, each with one job:
    //   • Mohave          — body, names, hero numbers
    //   • JetBrains Mono  — numbers, timestamps, `//` prefixes, `[brackets]`, micro labels
    //   • Cake Mono Light — uppercase display voice (titles, buttons, badges, sections)
    //
    enum Typography {

        // MARK: New semantic roles (spec v2 — prefer these for new code)

        /// Hero number — Mohave Light 80pt (dashboard hero, revenue total)
        static let hero = Font.hero

        /// Hero number on carousel cards — Mohave Light 60pt.
        /// Tracking (-0.025em) and tabular-nums applied at call site, not here.
        static let heroNumber = Font.custom("Mohave-Light", size: 60)

        /// Hero number on CONDENSED carousel cards — Mohave Light 38pt.
        /// Compact glance variant of `heroNumber`; full 60pt lives in the
        /// expand-to-sheet detail. Tracking + tabular-nums applied at call site.
        static let heroNumberCondensed = Font.custom("Mohave-Light", size: 38)

        /// Page title — Cake Mono Light 22pt (TopBar H1, root-route page heading)
        static let pageTitle = Font.pageTitle

        /// Display heading — Cake Mono Light 30pt (auth h1s, wizard step titles)
        static let display = Font.display

        /// Section heading — Cake Mono Light 18pt (settings subheads)
        static let section = Font.section

        /// Button label — Cake Mono Light 14pt (primary / secondary button text)
        static let buttonLabel = Font.buttonLabel

        /// Badge — Cake Mono Light 11pt
        static let badgeCake = Font.badgeCake

        /// Panel title — JetBrains Mono 11pt (widget and section titles, with `//` prefix)
        static let panelTitle = Font.panelTitle

        /// Data value (large) — JetBrains Mono Medium 20pt (hero metrics)
        static let dataValueLg = Font.dataValueLg

        /// Data value — JetBrains Mono 13pt (standard data values)
        static let dataValue = Font.dataValue

        /// Category label — JetBrains Mono 11pt (BOOKED, INVOICED)
        static let category = Font.category

        /// Metadata — JetBrains Mono 11pt (timestamps, IDs, subtotals)
        static let metadata = Font.metadata

        // MARK: Legacy roles (preserved so existing call sites keep compiling)

        // Titles
        static let largeTitle = Font.largeTitle
        static let title = Font.title
        static let subtitle = Font.subtitle                // → JetBrains Mono 22pt

        // Body text (Mohave)
        static let body = Font.body
        static let bodyBold = Font.bodyBold
        static let bodyEmphasis = Font.bodyEmphasis

        // Supporting text (→ JetBrains Mono)
        static let caption = Font.caption                  // → JetBrains Mono 14pt
        static let captionBold = Font.captionBold          // → JetBrains Mono Medium 14pt
        static let smallCaption = Font.smallCaption        // → JetBrains Mono 12pt
        static let smallBody = Font.smallBody              // → Mohave Light 14pt

        // Cards
        static let cardTitle = Font.cardTitle
        static let cardSubtitle = Font.cardSubtitle        // → JetBrains Mono 15pt
        static let cardBody = Font.cardBody

        // Status text → JetBrains Mono Medium 12pt (uppercase at call site)
        static let status = Font.status

        // Buttons — `buttonLabel` (Cake Mono Light) is the new primary role
        static let button = Font.button
        static let smallButton = Font.smallButton
        static let smallButtonBold = Font.smallButton.weight(.bold)
        static let buttonLarge = Font.buttonLarge

        // Compact UI labels (legacy Kosugi → remapped to JetBrains Mono)
        static let miniLabel = Font.miniLabel
        static let microLabel = Font.microLabel
        static let tagLabel = Font.tagLabel
        static let previewLabel = Font.previewLabel
        static let sectionLabel = Font.sectionLabel

        // Legacy headings (Mohave)
        static let heading = Font.heading
        static let headingBold = Font.headingBold
        static let headingLarge = Font.headingLarge

        // Legacy display (Mohave)
        static let displayLarge = Font.displayLarge
        static let displayQuantity = Font.displayQuantity
        static let displayXL = Font.displayXL

        // Legacy monospaced numeric display — for dimensions, measurements, stair specs
        static let headlineMono = SwiftUI.Font.system(size: 24, weight: .bold, design: .monospaced)
        static let titleMono = SwiftUI.Font.system(size: 20, weight: .bold, design: .monospaced)
        static let monoValue = SwiftUI.Font.system(size: 14, weight: .bold, design: .monospaced)
    }
    
    // MARK: - Layout
    enum Layout {
        // Standard spacing
        static let spacing1 = 4.0
        static let spacing2 = 8.0
        static let spacing3 = 16.0
        static let spacing2_5: CGFloat = 12.0  // Between spacing2 (8) and spacing3 (16)
        static let spacing3_5: CGFloat = 20.0  // Between spacing3 (16) and spacing4 (24)
        static let spacing4 = 24.0
        static let spacing5 = 32.0

        // Content padding
        static let contentPadding = EdgeInsets(
            top: spacing3,
            leading: spacing3,
            bottom: spacing3,
            trailing: spacing3
        )

        // Touch targets - Minimum 44×44 as per Apple HIG, but we go larger for field use
        static let touchTargetMin = 44.0
        static let touchTargetStandard = 56.0
        static let touchTargetLarge = 64.0

        // MARK: - Corner radius (spec v2 — sharp, tactical, no 999px pills)
        // Prefer the new semantic names (panelRadius, chipRadius, etc.).
        // Legacy names are kept as aliases so existing call sites still compile.

        // New semantic names
        static let panelRadius = 10.0         // Cards, widgets, panels (L1 glass surfaces)
        static let modalRadius = 12.0         // Modals, popovers, dropdowns, toasts
        static let cardRadius = 6.0           // L2 nested cards — KPI tiles, peer-grouped chips
        static let chipRadius = 4.0           // Tags, badges, chips
        static let progressBarRadius = 2.0    // Funnel bars, progress tracks
        static let sidebarHoverRadius = 6.0   // Sidebar hover background

        // Legacy aliases (retained for backwards compatibility — values updated to spec)
        static let cornerRadius = 5.0         // Standard inputs / general small containers (spec: buttons/inputs = 5)
        static let buttonRadius = 5.0         // Buttons (spec: 5)
        static let smallCornerRadius = 4.0    // Was 2.5 — now aligned to chipRadius
        static let cardCornerRadius = 10.0    // Was 8 — now aligned to panelRadius
        static let largeCornerRadius = 12.0   // Modals / sheets (spec: 12) — aligned to modalRadius

        // Icon sizes
        enum IconSize {
            static let xs: CGFloat = 12.0   // Tiny indicators
            static let sm: CGFloat = 16.0   // Inline icons, captions
            static let md: CGFloat = 20.0   // Standard icons
            static let lg: CGFloat = 24.0   // Section header icons
            static let xl: CGFloat = 32.0   // Action icons, prominent UI
            static let xxl: CGFloat = 48.0  // Large decorative icons (location overlay, etc.)
        }

        // Tab bar icon size
        static let tabBarIconSize: CGFloat = 28.0

        // Border widths
        enum Border {
            static let standard: CGFloat = 1.0
            static let thick: CGFloat = 2.0
        }

        // Dot/indicator sizes
        enum Indicator {
            static let dotSM: CGFloat = 6.0
            static let dotMD: CGFloat = 8.0
        }

        // Opacity presets
        enum Opacity {
            static let subtle = 0.1   // Disabled, very light overlays
            static let light = 0.3    // Light overlays
            static let medium = 0.5   // Medium overlays
            static let strong = 0.7   // Strong overlays
            static let heavy = 0.9    // Almost opaque
        }

        // Shadow presets — DEPRECATED (spec v2: zero box-shadows on dark backgrounds.
        // Depth = glass + hairlines only. Kept for backward compat — do NOT use in new code.)
        enum Shadow {
            static let card = (color: Color.black.opacity(0.1), radius: 4.0, x: 0.0, y: 2.0)
            static let elevated = (color: Color.black.opacity(0.2), radius: 8.0, x: 0.0, y: 4.0)
            static let floating = (color: Color.black.opacity(0.3), radius: 12.0, x: 0.0, y: 6.0)
        }

        // Gradient presets
        enum Gradients {
            // Header fade: opaque to transparent (used by HomeContentView header)
            static let headerFade = LinearGradient(
                colors: [Color.black.opacity(1), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Carousel left fade: dark to transparent (used by JobBoardDashboard carousel)
            static let carouselFadeLeft = LinearGradient(
                colors: [Color.black.opacity(0.8), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Carousel right fade: transparent to dark (used by JobBoardDashboard carousel)
            static let carouselFadeRight = LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Page indicator fade: transparent to dark to opaque (used by JobBoardDashboard page indicators)
            static let pageIndicatorFade = LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.8), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        // SearchField styling configuration
        enum SearchField {
            // Input field styling
            static let inputPadding: CGFloat = 12
            static let inputBackground = OPSStyle.Colors.cardBackgroundDark
            static let inputCornerRadius = OPSStyle.Layout.cornerRadius
            static let inputBorderColor = OPSStyle.Colors.cardBorder
            static let inputBorderWidth: CGFloat = 1

            // Icon styling
            static let iconSize: CGFloat = 14
            static let iconColor = OPSStyle.Colors.secondaryText
            static let clearButtonSize: CGFloat = 16
            static let clearButtonColor = OPSStyle.Colors.tertiaryText

            // Text styling
            static let textFont = OPSStyle.Typography.body
            static let textColor = OPSStyle.Colors.primaryText
            static let placeholderColor = OPSStyle.Colors.placeholderText

            // Suggestions dropdown styling
            static let dropdownBackground = OPSStyle.Colors.cardBackgroundDark
            static let dropdownCornerRadius = OPSStyle.Layout.cornerRadius
            static let dropdownBorderColor = OPSStyle.Colors.cardBorder
            static let dropdownBorderWidth: CGFloat = 1
            static let dropdownShadowColor = OPSStyle.Colors.shadowColor
            static let dropdownShadowRadius: CGFloat = 8
            static let dropdownShadowOffset = CGSize(width: 0, height: 4)
            static let dropdownTopPadding: CGFloat = 4
            static let dropdownMaxResults = 5

            // Suggestion row styling
            static let rowPaddingHorizontal: CGFloat = 16
            static let rowPaddingVertical: CGFloat = 12
            static let rowTitleFont = OPSStyle.Typography.body
            static let rowTitleColor = OPSStyle.Colors.primaryText
            static let rowSubtitleFont = OPSStyle.Typography.caption
            static let rowSubtitleColor = OPSStyle.Colors.secondaryText
            static let rowIconSize: CGFloat = 14
            static let rowCheckmarkSize: CGFloat = 14
            static let rowCheckmarkColor = OPSStyle.Colors.primaryAccent

            // Divider styling
            static let dividerColor = OPSStyle.Colors.tertiaryText.opacity(0.3)

            // Animation
            static let animationDuration: CGFloat = 0.2
            static let animationCurve = SwiftUI.Animation.easeInOut(duration: 0.2)
            static let transition = AnyTransition.opacity.combined(with: .move(edge: .top))
        }
    }
    
    // MARK: - Animation (spec v2 — single easing curve, no spring physics)
    //
    // One curve for everything: `cubic-bezier(0.22, 1, 0.36, 1)` (EASE_SMOOTH).
    // No spring, no bounce. Exception: drag-and-drop reorder only.
    // Every animation must respect reduced-motion — fall back to 150ms opacity crossfade.
    //
    enum Animation {
        // MARK: Easing — the single authorized curve
        /// Control points of the one OPS easing curve: `cubic-bezier(0.22, 1, 0.36, 1)`.
        /// Fast start, smooth finish, confident stop. Pass these to `Animation.timingCurve(...)`
        /// or use one of the pre-built `.hover` / `.panel` / `.page` / `.flip` values below.
        static let easeSmoothP1x: Double = 0.22
        static let easeSmoothP1y: Double = 1.0
        static let easeSmoothP2x: Double = 0.36
        static let easeSmoothP2y: Double = 1.0

        // MARK: Durations (named per spec)
        static let durationHover:    Double = 0.150  // 150ms — hover transitions
        static let durationPanel:    Double = 0.200  // 200ms — panel enter
        static let durationPage:     Double = 0.250  // 250ms — page transitions
        static let durationStagger:  Double = 0.300  // 300ms base + 50ms per item — row stagger
        static let durationStaggerStep: Double = 0.050
        static let durationChartBar: Double = 0.400  // 400-600ms — chart bar grow (add index delay)
        static let durationFlip:     Double = 0.350  // 350ms — card flip
        static let durationCountUp:  Double = 0.800  // 800ms — hero number count-up

        // MARK: Pre-built Animation values
        static let hover = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: durationHover)
        static let panel = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: durationPanel)
        static let page  = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: durationPage)
        static let flip  = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: durationFlip)

        // MARK: Legacy aliases (retained for backwards compatibility)
        /// Deprecated — prefer `.page` (250ms). Kept for existing call sites.
        static let standard = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.250)
        /// Deprecated — prefer `.hover` (150ms). Kept for existing call sites.
        static let quick    = SwiftUI.Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.150)
        /// Deprecated — prefer `.hover` (150ms).
        static let fast     = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let faster   = SwiftUI.Animation.easeOut(duration: 0.15)
        // Spring — DEPRECATED (spec v2: no spring physics, no bounce. Exception: drag-and-drop reorder only.)
        // Kept for backward compat — migrate call sites to .hover / .panel / .page.
        static let spring     = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let springFast = SwiftUI.Animation.spring(response: 0.2, dampingFraction: 0.7)
    }

    // MARK: - Icons
    enum Icons {
        // MARK: - OPS Domain Semantic Icons
        // These are THE standardized icons for core OPS concepts
        // Always use these for their designated purpose to maintain consistency

        // Core entities
        static let project = "folder.fill"                  // THE icon for Projects
        static let task = "checklist"                       // THE icon for Tasks
        static let taskType = "tag.fill"                    // THE icon for Task Types
        static let client = "person.circle.fill"            // THE icon for Clients
        static let subClient = "person.2.fill"              // THE icon for Sub-clients
        static let teamMember = "person.fill"               // THE icon for Team Members
        static let crew = "person.3.fill"                   // THE icon for Crews/Teams

        // Scheduling & Time
        static let schedule = "calendar.badge.clock"        // THE icon for Scheduling
        static let deadline = "calendar.badge.exclamationmark" // THE icon for Deadlines
        static let duration = "clock.fill"                  // THE icon for Duration/Time

        // Location & Site
        static let jobSite = "location.fill"                // THE icon for Job Sites
        static let address = "mappin.and.ellipse"           // THE icon for Addresses

        // Content & Media
        static let notes = "note.text"                      // THE icon for Notes
        static let description = "text.alignleft"           // THE icon for Description
        static let photos = "photo.on.rectangle"            // THE icon for Photos
        static let documents = "doc.text.fill"              // THE icon for Documents

        // Actions
        static let add = "plus.circle.fill"                 // THE icon for Add/Create
        static let edit = "pencil.circle.fill"              // THE icon for Edit
        static let delete = "trash.fill"                    // THE icon for Delete
        static let sync = "arrow.triangle.2.circlepath"     // THE icon for Sync
        static let share = "square.and.arrow.up"            // THE icon for Share
        static let filter = "line.horizontal.3.decrease.circle" // THE icon for Filter
        static let sort = "arrow.up.arrow.down.circle"      // THE icon for Sort
        static let addContact = "person.crop.circle.badge.plus" // THE icon for Add from Contacts
        static let addProject = "folder.badge.plus"         // THE icon for Create Project

        // Status & State
        static let complete = "checkmark.circle.fill"       // THE icon for Complete
        static let incomplete = "circle"                    // THE icon for Incomplete
        static let inProgress = "clock.arrow.circlepath"    // THE icon for In Progress (if needed)
        static let alert = "exclamationmark.triangle.fill"  // THE icon for Alerts/Warnings
        static let error = "xmark.octagon.fill"             // THE icon for Errors
        static let info = "info.circle.fill"                // THE icon for Information

        // System
        static let settings = "gearshape.fill"              // THE icon for Settings
        static let search = "magnifyingglass"               // THE icon for Search
        static let menu = "line.3.horizontal"               // THE icon for Menu
        static let close = "xmark"                          // THE icon for Close/Dismiss
        static let back = "chevron.left"                    // THE icon for Back navigation
        static let forward = "chevron.right"                // THE icon for Forward navigation

        // MARK: - Legacy SF Symbols (Currently in Use)
        // These are used in existing code - during Track F migration, replace with semantic icons above
        // Example: Replace `OPSStyle.Icons.calendar` with `OPSStyle.Icons.schedule`

        static let calendar = "calendar"
        static let calendarFill = "calendar.fill"
        static let calendarBadgeCheckmark = "calendar.badge.checkmark"
        static let person = "person"
        static let personFill = "person.fill"
        static let personTwo = "person.2"
        static let personTwoFill = "person.2.fill"
        static let personCircle = "person.circle"
        static let personCircleFill = "person.circle.fill"
        static let location = "location"
        static let locationFill = "location.fill"
        static let phone = "phone"
        static let phoneFill = "phone.fill"
        static let envelope = "envelope"
        static let envelopeFill = "envelope.fill"
        static let folder = "folder"
        static let folderFill = "folder.fill"
        static let checklist = "checklist"
        static let checkmark = "checkmark"
        static let checkmarkSquare = "checkmark.square"
        static let checkmarkSquareFill = "checkmark.square.fill"
        static let checkmarkCircle = "checkmark.circle"
        static let checkmarkCircleFill = "checkmark.circle.fill"
        static let circle = "circle"
        static let square = "square"
        static let squareFill = "square.fill"
        static let xmark = "xmark"
        static let xmarkCircle = "xmark.circle"
        static let xmarkCircleFill = "xmark.circle.fill"
        static let chevronRight = "chevron.right"
        static let chevronLeft = "chevron.left"
        static let chevronUp = "chevron.up"
        static let chevronDown = "chevron.down"
        static let plus = "plus"
        static let plusCircle = "plus.circle"
        static let plusCircleFill = "plus.circle.fill"
        static let minus = "minus"
        static let minusCircle = "minus.circle"
        static let minusCircleFill = "minus.circle.fill"
        static let exclamationmarkTriangle = "exclamationmark.triangle"
        static let exclamationmarkTriangleFill = "exclamationmark.triangle.fill"
        static let gearshape = "gearshape"
        static let gearshapeFill = "gearshape.fill"
        static let house = "house"
        static let houseFill = "house.fill"
        static let map = "map"
        static let mapFill = "map.fill"
        static let ellipsis = "ellipsis"
        static let ellipsisCircle = "ellipsis.circle"
        static let ellipsisCircleFill = "ellipsis.circle.fill"
        static let listBullet = "list.bullet"
        static let trash = "trash"
        static let trashFill = "trash.fill"
        static let pencil = "pencil"
        static let pencilCircle = "pencil.circle"
        static let pencilCircleFill = "pencil.circle.fill"
        static let arrowClockwise = "arrow.clockwise"
        static let arrowCounterclockwise = "arrow.counterclockwise"
        static let magnifyingglass = "magnifyingglass"
        static let magnifyingglassCircle = "magnifyingglass.circle"
        static let magnifyingglassCircleFill = "magnifyingglass.circle.fill"
        static let bellFill = "bell.fill"
        static let photo = "photo"
        static let photoFill = "photo.fill"
        static let camera = "camera"
        static let cameraFill = "camera.fill"
        static let clock = "clock"
        static let copy = "doc.on.doc"

        // Pipeline & Financial (Feb 2026)
        static let opportunity      = "arrow.up.right.circle.fill"
        static let pipelineChart    = "chart.bar.doc.horizontal.fill"
        static let estimateDoc      = "doc.text.fill"
        static let invoiceReceipt   = "receipt"
        static let paymentDollar    = "dollarsign.circle.fill"
        static let siteVisitPin     = "mappin.circle.fill"
        static let activityBubble   = "bubble.left.and.text.bubble.right.fill"
        static let followUpAlarm    = "alarm.fill"
        static let stageAdvance     = "arrow.forward.circle.fill"
        static let dealWon          = "checkmark.seal.fill"
        static let dealLost         = "xmark.seal.fill"
        static let accountingChart  = "chart.bar.fill"
        static let productTag       = "tag.fill"
        static let inventoryTracking = "shippingbox.circle.fill" // Inventory tracking on/off (stock state) — NOT the sync glyph
        static let stale            = "exclamationmark.triangle.fill"
        static let expense          = "dollarsign.circle"
        static let banknoteFill     = "banknote.fill"
        static let undo             = "arrow.uturn.backward"
        static let sendFill         = "arrow.up.circle.fill"
        static let bell             = "bell"
        static let mention          = "at"
        static let assignmentNotification = "person.badge.plus"
        static let pencilTip        = "pencil.tip"
        static let receipt          = "doc.text.viewfinder"
        static let clockFill        = "clock.fill"
        static let exclamationmarkCircleFill = "exclamationmark.circle.fill"
    }

    // MARK: - Wizard
    enum Wizard {
        static let accentColor = Colors.wizardAccent
        static let pulseDuration: Double = 1.0

        /// Button / tappable element — rounded rectangle glow
        enum Button {
            static let fillOpacityHigh: Double = 0.35
            static let fillOpacityLow: Double = 0.15
            static let borderOpacityHigh: Double = 0.9
            static let borderOpacityLow: Double = 0.4
            static let borderWidth: CGFloat = 2
            static let cornerRadius: CGFloat = Layout.cornerRadius
        }

        /// Circular element — FAB, avatar, round button
        enum Circle {
            static let fillOpacityHigh: Double = 0.35
            static let fillOpacityLow: Double = 0.15
            static let borderOpacityHigh: Double = 0.9
            static let borderOpacityLow: Double = 0.4
            static let borderWidth: CGFloat = 2
        }

        /// Input field — subtle fill so text stays readable, prominent border
        enum Input {
            static let fillOpacityHigh: Double = 0.12
            static let fillOpacityLow: Double = 0.04
            static let borderOpacityHigh: Double = 0.9
            static let borderOpacityLow: Double = 0.4
            static let borderWidth: CGFloat = 2
            static let cornerRadius: CGFloat = Layout.smallCornerRadius
        }

        /// List row / card — full-width highlight
        enum Row {
            static let fillOpacityHigh: Double = 0.25
            static let fillOpacityLow: Double = 0.10
            static let borderOpacityHigh: Double = 0.7
            static let borderOpacityLow: Double = 0.3
            static let borderWidth: CGFloat = 1.5
            static let cornerRadius: CGFloat = Layout.cornerRadius
        }
    }

    // MARK: - Inventory
    enum Inventory {
        /// Size variants for tag badges
        enum TagSize {
            case compact   // For display in cards, lists
            case standard  // Default size
            case button    // Larger for touch targets in management screens

            var font: Font {
                switch self {
                case .compact: return Typography.smallCaption
                case .standard: return Typography.smallCaption
                case .button: return Typography.caption
                }
            }

            var paddingHorizontal: CGFloat {
                switch self {
                case .compact: return 6
                case .standard: return 6
                case .button: return 12
                }
            }

            var paddingVertical: CGFloat {
                switch self {
                case .compact: return 2
                case .standard: return 2
                case .button: return 8
                }
            }

            var cornerRadius: CGFloat {
                switch self {
                case .compact: return 4
                case .standard: return 4
                case .button: return 6
                }
            }
        }

        // Tag badge styling (monochromatic)
        enum TagBadge {
            static let font = Typography.smallCaption
            static let textColor = Colors.secondaryText
            static let backgroundColor = Colors.cardBackgroundDark
            static let borderColor = Colors.cardBorder
            static let paddingHorizontal: CGFloat = 8
            static let paddingVertical: CGFloat = 4
            static let cornerRadius: CGFloat = Layout.cornerRadius
            static let spacing: CGFloat = 6
        }

        // Status/threshold badge styling
        enum ThresholdBadge {
            static let font = Typography.smallCaption
            static let paddingHorizontal: CGFloat = 6
            static let paddingVertical: CGFloat = 2
            static let cornerRadius: CGFloat = 4
            static let maxWidth: CGFloat = 60
        }

        // Card scaling
        enum CardScale {
            static let minScale: CGFloat = 0.8
            static let maxScale: CGFloat = 1.5
            static let tagVisibilityThreshold: CGFloat = 0.9
            static let metadataVisibilityThreshold: CGFloat = 1.0
        }
    }
}

// OPSComponents.swift
import SwiftUI

// MARK: - Buttons
struct PrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(OPSStyle.Typography.button)
            .foregroundColor(.white)
            .padding()
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .frame(maxWidth: .infinity)
            .background(OPSStyle.Colors.primaryAccent)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
    }
}

struct SecondaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(OPSStyle.Typography.button)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding()
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .frame(maxWidth: .infinity)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
            )
    }
}

struct IconActionButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 24))
            .foregroundColor(.white)
            .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
            .background(Circle().fill(OPSStyle.Colors.primaryAccent))
    }
}

struct DisabledButtonStyle: ViewModifier {
    let isDisabled: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isDisabled ? 0.7 : 1.0)
    }
}

// Legacy status badge - use the new StatusBadge component for new code
struct LegacyStatusBadge: View {
    let status: Status
    
    var body: some View {
        Text(status.rawValue.uppercased())
            .font(OPSStyle.Typography.smallCaption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(OPSStyle.Colors.statusColor(for: status))
            .cornerRadius(OPSStyle.Layout.cornerRadius / 2)
    }
}

// MARK: - Extension for easy usage (Legacy)
extension View {
    // Deprecated - use opsPrimaryButtonStyle() from ButtonStyles.swift
    func primaryButtonStyle() -> some View {
        self.modifier(PrimaryButton())
    }
    
    // Deprecated - use opsSecondaryButtonStyle() from ButtonStyles.swift 
    func secondaryButtonStyle() -> some View {
        self.modifier(SecondaryButton())
    }
    
    // Deprecated - use opsIconButtonStyle() from ButtonStyles.swift
    func iconButtonStyle() -> some View {
        self.modifier(IconActionButton())
    }

    // Apply disabled button styling (reduces opacity when disabled)
    func disabledButtonStyle(isDisabled: Bool) -> some View {
        self.modifier(DisabledButtonStyle(isDisabled: isDisabled))
    }

    // Deprecated - use opsCardStyle() from CardStyles.swift
    /// Applies standard card styling with background, border, and corner radius
    ///
    /// - Parameters:
    ///   - background: Background color (default: cardBackgroundDark)
    ///   - borderColor: Border color (default: cardBorder)
    ///   - borderWidth: Border width (default: 1)
    ///   - padding: Edge insets for content padding (default: 16pt all sides)
    func cardStyle(
        background: Color = OPSStyle.Colors.cardBackgroundDark,
        borderColor: Color = OPSStyle.Colors.cardBorder,
        borderWidth: CGFloat = 1,
        padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    ) -> some View {
        self
            .padding(padding)
            .background(background)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
    }
}

// MARK: - Blur View

struct BlurView: UIViewRepresentable {

    let style: UIBlurEffect.Style

    func makeUIView(context: UIViewRepresentableContext<BlurView>) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        let blurEffect = UIBlurEffect(style: style)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(blurView, at: 0)
        NSLayoutConstraint.activate([
            blurView.heightAnchor.constraint(equalTo: view.heightAnchor),
            blurView.widthAnchor.constraint(equalTo: view.widthAnchor),
        ])
        return view
    }

    func updateUIView(_ uiView: UIView,
                      context: UIViewRepresentableContext<BlurView>) {

    }

}

// MARK: - Color(hex:) Initializer
// The failable `init?(hex:)` lives in OPS/Views/Components/UserAvatar.swift and
// handles both 6- and 8-char hex (with or without `#`). All call sites use the
// failable form with `?? fallback` or `if let c = Color(hex:)`.
