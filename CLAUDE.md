# OPS Brand & Design Guide for Development

This guide serves as the primary reference for maintaining OPS brand consistency and design philosophy throughout development. All code changes should align with these principles.

## Quick Reference

### Brand Essence: Dependable Field Partner

OPS (Operational Project System) exists to make trade workers' lives easier through technology that "just works" in any environment. We serve as the invisible, reliable companion that helps field crews accomplish their work without adding complexity or demanding attention.

## Core Brand Values

1. **Built By Trades, For Trades** - Created by actual trade workers who understand the real challenges of managing projects and crews in the field, not tech people who've "never swung a hammer."

2. **No Unnecessary Complexity** - We don't burden users with features they'll never use or processes that take more time than they save.

3. **Reliability Above All** - In the field, reliability isn't a feature—it's a requirement. OPS works when other technologies fail, maintaining dependability in challenging conditions with poor connectivity.

4. **Field-First Design** - Every aspect of OPS is designed for the realities of job sites, not office environments. We embrace dirt, gloves, sunlight, and noise as the natural working conditions of our users.

5. **Time Is Money** - We respect that every minute spent managing software is a minute not spent on billable work.

## Brand Voice & Tone

### Personality
OPS speaks with the confident, straightforward voice of an experienced field supervisor who has earned respect through practical knowledge. We are:

- **Direct** - We get to the point without unnecessary words
- **Practical** - We focus on solutions, not theory
- **Dependable** - We communicate consistently and reliably
- **Genuine** - We avoid corporate speak and marketing hype
- **Focused** - We stick to what matters for getting the job done

### Tone Principles

1. **Clarity Over Cleverness** - We prioritize being understood over being entertaining
2. **Actionable Information** - Every communication should help the user accomplish a task or make a decision
3. **Respectful Simplicity** - Simple language without being condescending
4. **Field-Appropriate Confidence** - The quiet confidence of someone who knows what they're talking about
5. **Situational Awareness** - Adjust tone based on context (errors, education, etc.)

## Visual Identity

### Color Palette

- **Primary Background** (Near Black): #000000
  - Reduces screen glare in bright environments
  - Conserves battery life
  - Creates high contrast for improved readability

- **Card Background** (Dark Gray): #0D0D0D
  - Provides subtle distinction from main background
  - Maintains dark theme benefits while creating visual hierarchy

- **Primary Accent** (Blue): #59779F
  - Used for primary interactive elements and branding
  - Creates recognition without eye strain
  - Visible under various lighting conditions

- **Status Colors**:
  - Success: #A5B368 (Muted Green)
  - Warning: #C4A868 (Amber)
  - Error: #931A32 (Deep Red)
  - Project status-specific colors as defined in the app

### Typography

- **Primary Font**: Mohave
  - Main font family for titles, body text, and UI elements
  - Available in multiple weights (Light, Regular, Medium, SemiBold, Bold)
  - Clean, modern appearance optimized for field readability
  - Used for headers, body text, buttons, and status indicators

- **Supporting Font**: Kosugi
  - Used for subtitles, captions, and supporting text
  - Provides clear contrast to Mohave for improved hierarchy
  - Excellent legibility at smaller sizes

- **Display Font**: Bebas Neue (available but rarely used)
  - Reserved for special branding moments only
  - Not part of regular UI typography

- **Font Sizes**:
  - Large Title: 32pt (Mohave Bold)
  - Title: 28pt (Mohave SemiBold)
  - Subtitle: 22pt (Kosugi Regular)
  - Body: 16pt (Mohave Regular)
  - Caption: 14pt (Kosugi Regular)
  - Small Caption: 12pt (Kosugi Regular)

### Layout & Spacing

- **Touch Targets**: Minimum 44×44pt for all interactive elements, with preference for 56×56pt for main actions
- **Field-Friendly Padding**: Generous white space between elements (minimum 8pt)
- **Consistent Grid**: 8pt layout grid for all components and spacing
- **Screen Organization**: Critical actions at bottom of screen for thumb accessibility
- **Clear Hierarchy**: Primary actions prominently displayed and visually distinguished

## UI Design Guidelines

### Consistency & Uniformity Principles

**CRITICAL**: Consistency is paramount in OPS. Every similar component must look and behave identically across the entire application.

1. **Section Layout Pattern**
   - Section headers ALWAYS appear above cards, never inside them
   - Section headers use `OPSStyle.Typography.captionBold` in `OPSStyle.Colors.secondaryText`
   - Section headers should be formatted as: "SECTION NAME" (all caps)
   - Cards containing content have consistent padding: `.padding(.vertical, 14).padding(.horizontal, 16)`
   - Cards use `OPSStyle.Colors.cardBackgroundDark.opacity(0.8)` for background
   - Never nest cards within cards (no double backgrounds)

2. **Component Uniformity**
   - If a component appears in multiple places, it MUST look identical
   - Contact information rows (email, phone, address) must have the same layout everywhere
   - Buttons with the same function must have identical styling
   - Spacing between similar elements must be consistent

3. **Visual Hierarchy**
   - Maintain consistent visual hierarchy across all views
   - Primary actions use `OPSStyle.Colors.primaryAccent`
   - Secondary information uses `OPSStyle.Colors.secondaryText`
   - Disabled/unavailable items use `OPSStyle.Colors.tertiaryText`

### Background Colors
- **Primary Background**: Always use solid `OPSStyle.Colors.background` (near black) for main screens.
- **Card Background**: Use `OPSStyle.Colors.cardBackground` or `OPSStyle.Colors.cardBackgroundDark` for cards and content containers.
- **IMPORTANT**: Never use opacity modifiers (e.g., `.opacity(0.5)`) on background colors. Instead, use the appropriate solid color for the context.

### Accent Colors
- **Primary Accent** (`OPSStyle.Colors.primaryAccent`): Use for:
  - Primary interactive elements (buttons, clickable icons)
  - Main call-to-action elements
  - Navigation elements
  - Must be less than 10% of visible UI colors

- **Secondary Accent** (`OPSStyle.Colors.secondaryAccent`): 
  - **ONLY** use to indicate active projects or active state
  - Never use for general UI elements, decoration, or non-active items

### Text Colors
- **Primary Text** (`OPSStyle.Colors.primaryText`): Use for:
  - Main text content
  - Non-clickable icons
  - Headers and titles

- **Secondary Text** (`OPSStyle.Colors.secondaryText`): Use for:
  - Supporting text
  - Labels
  - Subtitles and captions

- **Tertiary Text** (`OPSStyle.Colors.tertiaryText`): Use for:
  - Hints and less important information
  - Disabled text

### Component Styling Guidelines

#### Buttons
1. **Primary Button**: 
   - Background: `OPSStyle.Colors.primaryAccent`
   - Text: White
   - Used for main actions on a screen

2. **Secondary Button**:
   - Background: Black
   - Text/Border: `OPSStyle.Colors.primaryAccent`
   - Used for alternative actions

3. **Text Button**:
   - No background
   - Text: `OPSStyle.Colors.primaryAccent`
   - Used for tertiary actions

#### Cards
- **Always use solid backgrounds** without opacity modifiers
- Corner radius should be consistent: `OPSStyle.Layout.cornerRadius`
- Shadow (if used) should be solid black without opacity: `.shadow(color: Color.black, radius: 4, x: 0, y: 2)`

#### Icons
- **Clickable Icons**: Use `OPSStyle.Colors.primaryAccent`
- **Non-clickable/Informational Icons**: Use `OPSStyle.Colors.primaryText`
- **Status Icons**: Use appropriate status color

## Development Best Practices

### Code Quality Standards
- **Simplicity First** - Write code that's easy to understand and maintain
- **Field-Tested Logic** - Consider offline scenarios, poor connectivity, and error states
- **Performance Matters** - Every millisecond counts on older devices in the field
- **Defensive Programming** - Assume things will go wrong and handle gracefully

### Git Commit Guidelines
- **Never include Claude as co-author** - Do not add Claude or any AI attribution to git commits
- **Clear commit messages** - Write concise, descriptive commit messages that explain the changes
- **Atomic commits** - Each commit should represent a single logical change

### AI Model Guidelines
- **Use Sonnet 4 instead of Opus 4** - For development assistance, prefer Claude Sonnet 4 over Opus 4 for better performance and cost efficiency

### Testing Requirements
- **Test with gloves** - Ensure all touch targets work with reduced precision
- **Test in sunlight** - Verify contrast and readability outdoors
- **Test offline** - Confirm all critical features work without connectivity
- **Test on older devices** - Support 3-year-old hardware minimum

### Key Implementation Details
- **Touch targets**: Minimum 44×44pt, prefer 60×60pt for primary actions
- **Text sizes**: Minimum 16pt, prefer 18-20pt for important information
- **Contrast ratios**: Minimum 7:1 for normal text, 4.5:1 for large text
- **Offline storage**: Cache all data needed for current day's work
- **Sync strategy**: Queue changes locally, sync opportunistically
- **Error handling**: Always provide actionable next steps

### Quick Decisions
When in doubt:
1. Choose reliability over features
2. Choose simplicity over flexibility
3. Choose clarity over cleverness
4. Choose field needs over office preferences
5. Choose proven patterns over innovation

## Remember
"You've got to start with the customer experience and work backwards to the technology." - Steve Jobs

Our customers swing hammers, not keyboards. Build accordingly.