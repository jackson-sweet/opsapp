# OPS Brand Identity Guide

## Brand Essence: Dependable Field Partner

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

- **Primary Font**: System font (San Francisco on iOS)
  - Optimized for device screens and OS accessibility features
  - Consistent with platform experience for intuitive use
  - Available in multiple weights for clear hierarchy

- **Heading Font**: Bebas Neue for titles only
  - Used sparingly for main titles to create brand distinction
  - Condensed to maximize screen real estate
  - Strong vertical rhythm for scan-ability

- **Font Sizes**:
  - Large Title: 32pt
  - Title: 28pt
  - Subtitle: 22pt
  - Body: 17pt
  - Caption: 15pt
  - Small Caption: 13pt

### Layout & Spacing

- **Touch Targets**: Minimum 44×44pt for all interactive elements, with preference for 56×56pt for main actions
- **Field-Friendly Padding**: Generous white space between elements (minimum 8pt)
- **Consistent Grid**: 8pt layout grid for all components and spacing
- **Screen Organization**: Critical actions at bottom of screen for thumb accessibility
- **Clear Hierarchy**: Primary actions prominently displayed and visually distinguished

## UI Design Guidelines

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

## Best Practices

- **Offline-First Architecture** - All critical operations work locally first with intelligent sync
- **Field-Optimized Interface** - Dark mode default for sunlight readability, large touch targets for gloved operation
- **Simplified Workflows** - One-tap status updates, minimal steps to complete common tasks
- **Reliable Performance** - Battery-efficient operation, quick loading even on older devices