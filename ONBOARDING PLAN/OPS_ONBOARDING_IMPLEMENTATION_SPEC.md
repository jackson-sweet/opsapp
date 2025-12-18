# OPS Onboarding Implementation Specification

**Version**: 1.0  
**Date**: December 2024  
**Status**: Ready for Technical Review  
**Target**: Claude Code Implementation

---

## Purpose

This document specifies the complete redesign of the OPS onboarding experience. Claude Code should review this against the existing codebase to identify reusable components and determine what new components must be created.

---

## Design Philosophy

### Tactical/Military Minimalism

Every element must adhere to the OPS visual identity:

- **High contrast**: Dark backgrounds, light text
- **Generous negative space**: Elements breathe, no cramped layouts
- **Understated feedback**: Subtle state changes, never celebratory
- **Functional typography**: Readable, not decorative
- **Monochromatic palette**: Single accent color only
- **Flat design**: No shadows, no gradients (except background if existing)
- **Minimal corner radius**: Sharp or near-sharp corners
- **Icons serve function only**: No decorative icons

### What to Avoid

- Emojis (never, anywhere)
- Bouncy or playful animations
- Celebratory language ("Nice work!", "Awesome!", "You did it!")
- Soft, rounded, friendly shapes
- Multiple accent colors
- Decorative illustrations or graphics
- Exclamation points in UI copy
- Large iconography as visual centerpieces

### Reference Aesthetic

Think: Terminal interface, cockpit HUD, military briefing screen.  
Not: Consumer fintech app, social media, gamified fitness tracker.

---

## Flow Architecture

### Company Creator Flow (4 screens)

```
Welcome → Credentials → Profile + Company + Invite → Ready
```

### Employee Flow (3 screens)

```
Welcome → Credentials → Profile + Join → Ready
```

### Screens Eliminated from Current Implementation

| Removed | Disposition |
|---------|-------------|
| AccountType | Merged into Welcome |
| Profile | Merged into Screen 3 |
| CompanyDetails | Merged into Screen 3A |
| CompanyCodeDisplay | Inline in Screen 3A |
| CompanyCode | Merged into Screen 3B |
| Permissions | Deferred to contextual in-app requests |
| Preferences | Moved to Settings, use smart defaults |
| Billing | Moved to Settings |
| Tutorial | Phase 2, separate implementation |
| Complete | Merged into Ready |

---

## Reusable Component Architecture

### Layout Components

| Component | Purpose |
|-----------|---------|
| OnboardingScaffold | Master page wrapper with header, content, and footer slots |
| OnboardingHeader | Top bar with optional back button |
| OnboardingFooter | Bottom action area with primary button and optional secondary elements |
| OnboardingContentStack | Vertical stack with consistent spacing for form content |

### Input Components

| Component | Purpose |
|-----------|---------|
| OnboardingTextField | Standard text input with label, placeholder, validation, error state |
| OnboardingSecureField | Password input with visibility toggle |
| OnboardingPhoneField | Phone input with auto-formatting |
| OnboardingAddressField | Address input with MapKit autocomplete |
| OnboardingCodeField | Company code input with bracket display |

### Button Components

| Component | Purpose |
|-----------|---------|
| OnboardingPrimaryButton | Main CTA with loading state |
| OnboardingSecondaryButton | Alternative action with optional leading icon |
| OnboardingTextButton | Tertiary action, minimal styling |
| OnboardingSocialButton | Google and Apple sign-in buttons |

### Display Components

| Component | Purpose |
|-----------|---------|
| OnboardingSectionHeader | Form section label |
| OnboardingDivider | Horizontal separator with optional inline text |
| OnboardingCodeDisplay | Company code block with copy action |
| OnboardingLoadingOverlay | Full-content loading state with tactical loader |

### Sheet Components

| Component | Purpose |
|-----------|---------|
| InviteSheet | Modal for sending email invites to crew |

---

## Component Specifications

### OnboardingScaffold

Master wrapper for every onboarding screen.

**Structure**:
```
┌─────────────────────────────────┐
│ Safe Area Top                   │
│ ┌─────────────────────────────┐ │
│ │ HEADER SLOT                 │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │ CONTENT SLOT (Scrollable)   │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ FOOTER SLOT                 │ │
│ └─────────────────────────────┘ │
│ Safe Area Bottom                │
└─────────────────────────────────┘
```

**Properties**:
- `header`: Optional view slot for OnboardingHeader
- `content`: ViewBuilder for screen-specific content
- `footer`: Optional view slot for OnboardingFooter
- `footerPinnedToBottom`: Bool (true = footer fixed at bottom, false = footer scrolls with content)

**Behavior**:
- Applies OPSStyle background color
- Handles keyboard avoidance
- Applies consistent horizontal padding to content
- Header and footer manage their own padding

---

### OnboardingHeader

Top bar for navigation.

**Layout**:
```
┌─────────────────────────────────┐
│  ←                              │
└─────────────────────────────────┘
```

**Properties**:
- `showBackButton`: Bool
- `onBack`: Callback

**Notes**:
- Back button uses existing OPSStyle back icon or chevron
- Minimal height, no decorative elements
- No progress indicators (removed for simplicity)

---

### OnboardingFooter

Bottom action area.

**Layout Variants**:

Primary only:
```
┌─────────────────────────────────┐
│  ┌─────────────────────────┐    │
│  │     PRIMARY ACTION       │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

Primary + tertiary:
```
┌─────────────────────────────────┐
│  ┌─────────────────────────┐    │
│  │     PRIMARY ACTION       │    │
│  └─────────────────────────┘    │
│                                 │
│        Tertiary link            │
└─────────────────────────────────┘
```

**Properties**:
- `primaryButton`: Configuration for OnboardingPrimaryButton
- `tertiaryLink`: Optional configuration for OnboardingTextButton

---

### OnboardingContentStack

Vertical container for form content.

**Behavior**:
- Applies consistent vertical spacing between elements
- All content left-aligned
- Section headers receive additional top margin

---

### OnboardingTextField

Standard text input.

**States**:
- Default: Standard border
- Focused: Accent border
- Error: Error border with message below

**Properties**:
- `label`: Optional string above field
- `placeholder`: String
- `text`: Binding
- `keyboardType`: UIKeyboardType
- `textContentType`: UITextContentType
- `isRequired`: Bool
- `validation`: Optional closure returning Bool
- `errorMessage`: String

**Visual**:
- Uses OPSStyle input colors
- Minimum touch target height
- No rounded corners (minimal radius only)

---

### OnboardingSecureField

Password input with visibility toggle.

**Properties**:
- Same as OnboardingTextField
- `isSecure`: Bool (toggleable via icon button)

**Visual**:
- Eye icon for toggle (functional, not decorative)
- Secure entry by default

---

### OnboardingPhoneField

Phone number input.

**Behavior**:
- Auto-formats as user types
- Numeric keyboard
- Strips formatting for storage

---

### OnboardingAddressField

Address with MapKit autocomplete.

**Behavior**:
- Shows suggestions as user types
- Debounced search
- Selection fills field with full address

---

### OnboardingCodeField

Company code entry.

**Visual**:
- Displays brackets as part of field chrome: `[                    ]`
- User types inside brackets
- Monospace font for code text

**Behavior**:
- Handles paste of full code
- No auto-formatting

---

### OnboardingPrimaryButton

Main call-to-action.

**States**:
- Default: Accent background, contrasting text
- Disabled: Reduced opacity
- Loading: Tactical loader with loading text

**Properties**:
- `title`: String
- `loadingTitle`: String
- `isEnabled`: Bool
- `isLoading`: Bool
- `action`: Callback

**Visual**:
- Full width
- Minimal corner radius
- Uses OPSStyle button height and typography

---

### OnboardingSecondaryButton

Alternative action button.

**Properties**:
- `title`: String
- `icon`: Optional SF Symbol name
- `action`: Callback

**Visual**:
- Transparent background
- Accent border
- Accent text
- Icon left of text if present

---

### OnboardingTextButton

Tertiary action.

**Properties**:
- `title`: String
- `action`: Callback

**Visual**:
- No background or border
- Secondary text color
- No arrows or decorative elements

---

### OnboardingSocialButton

Google and Apple sign-in.

**Properties**:
- `provider`: Enum (google, apple)
- `action`: Callback

**Visual**:
- Follow platform guidelines
- Consistent sizing

---

### OnboardingSectionHeader

Form section divider.

**Properties**:
- `title`: String

**Visual**:
- Uppercase text
- Uses OPSStyle section header typography
- Extra top margin for separation
- Left-aligned

---

### OnboardingDivider

Horizontal separator.

**Properties**:
- `text`: Optional string (displayed inline)

**Visual**:
- Thin line using OPSStyle divider color
- If text present, line breaks around centered text
- Text in secondary color, small size

---

### OnboardingCodeDisplay

Company code display with copy function.

**Layout**:
```
┌─────────────────────────────────┐
│  [ 1736017234629x684127636 ]    │
│                                 │
│            COPY                 │
└─────────────────────────────────┘
```

**Properties**:
- `code`: String
- `onCopy`: Callback

**Behavior**:
- Tap COPY copies to clipboard
- Haptic feedback on copy
- Button text changes briefly to confirm (no toast, no animation)

**Visual**:
- Code in monospace font
- Brackets are display chrome, not part of code
- Minimal card background or no background

---

### OnboardingLoadingOverlay

Loading state overlay.

**Layout**:
```
┌─────────────────────────────────┐
│                                 │
│                                 │
│      [Tactical Loader]          │
│                                 │
│      STATUS MESSAGE             │
│                                 │
│                                 │
└─────────────────────────────────┘
```

**Properties**:
- `message`: String

**Behavior**:
- Covers content area
- Uses existing tactical loader component
- Message is status text, not friendly chat

---

### InviteSheet

Modal for email invites.

**Layout**:
```
┌─────────────────────────────────┐
│  INVITE TEAM MEMBER         ✕   │
│                                 │
│  ┌─────────────────────────┐    │
│  │ Email address            │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │      SEND INVITE         │    │
│  └─────────────────────────┘    │
│                                 │
│  + Add another                  │
│                                 │
│  SENT                           │
│  mike@email.com                 │
│  sarah@email.com                │
│                                 │
└─────────────────────────────────┘
```

**Behavior**:
- Email validation before send
- Shows list of sent invites
- Add another clears field for next entry
- Close button dismisses sheet

---

## Screen Specifications

### Screen 1: Welcome

**Purpose**: Brand introduction and account type selection.

**Layout**:
```
┌─────────────────────────────────┐
│                                 │
│                                 │
│  [OPS LOGO]                     │
│                                 │
│                                 │
│  FIELD-FIRST                    │
│  PROJECT MANAGEMENT             │
│                                 │
│  Built by trades.               │
│  For trades.                    │
│                                 │
│                                 │
│                                 │
│  ┌─────────────────────────┐    │
│  │  I'M STARTING A TEAM    │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │  I'M JOINING A TEAM     │    │
│  └─────────────────────────┘    │
│                                 │
│                                 │
│  Already have an account?       │
│  Sign in                        │
│                                 │
└─────────────────────────────────┘
```

**Components Used**:
- OnboardingScaffold (no header, no footer)
- OPS logo asset
- OnboardingPrimaryButton (x2)
- OnboardingTextButton

**Interactions**:
- Tap "I'M STARTING A TEAM" → Set userType to company, advance to Credentials
- Tap "I'M JOINING A TEAM" → Set userType to employee, advance to Credentials
- Tap "Sign in" → Dismiss onboarding, present login

**Data Saved**:
- `state.userType`

---

### Screen 2: Credentials

**Purpose**: Account creation.

**Layout**:
```
┌─────────────────────────────────┐
│  ←                              │
│                                 │
│  CREATE YOUR ACCOUNT            │
│                                 │
│                                 │
│  ┌─────────────────────────┐    │
│  │ Email                    │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │ Password             👁  │    │
│  └─────────────────────────┘    │
│                                 │
│                                 │
│  ────── or continue with ────── │
│                                 │
│  ┌───────────┐  ┌───────────┐   │
│  │  Google   │  │   Apple   │   │
│  └───────────┘  └───────────┘   │
│                                 │
│                                 │
├─────────────────────────────────┤
│  ┌─────────────────────────┐    │
│  │     CREATE ACCOUNT       │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

**Components Used**:
- OnboardingScaffold
- OnboardingHeader (back button)
- OnboardingTextField (email)
- OnboardingSecureField (password)
- OnboardingDivider (with text)
- OnboardingSocialButton (x2)
- OnboardingFooter with OnboardingPrimaryButton

**Validation**:
- Email: Valid format
- Password: Minimum 8 characters

**Loading State**:
- Primary button shows tactical loader
- Button text changes to loading text
- Form fields disabled

**API Integration**:
- Company path: `POST /api/1.1/wf/sign_company_up`
- Employee path: `POST /api/1.1/wf/sign_employee_up`

**Data Saved**:
- `state.email`
- `state.userId`
- `state.usedSocialLogin` (if social auth)

---

### Screen 3A: Profile + Company + Invite (Company Creator)

**Purpose**: Collect profile, create company, show code, enable invites.

This screen has three phases that transition inline.

#### Phase 1: Form Input

**Layout**:
```
┌─────────────────────────────────┐
│  ←                              │
│                                 │
│  ABOUT YOU                      │
│                                 │
│  ┌─────────────────────────┐    │
│  │ First name              │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │ Last name               │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │ Phone (optional)        │    │
│  └─────────────────────────┘    │
│                                 │
│                                 │
│  YOUR COMPANY                   │
│                                 │
│  ┌─────────────────────────┐    │
│  │ Company name            │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │ Address (optional)      │    │
│  └─────────────────────────┘    │
│                                 │
├─────────────────────────────────┤
│  ┌─────────────────────────┐    │
│  │     CREATE COMPANY       │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

**Components Used**:
- OnboardingScaffold
- OnboardingHeader
- OnboardingSectionHeader (x2)
- OnboardingTextField (first name, last name, company name)
- OnboardingPhoneField
- OnboardingAddressField
- OnboardingFooter with OnboardingPrimaryButton

**Validation**:
- First name: Required
- Last name: Required
- Phone: Optional
- Company name: Required
- Address: Optional

#### Phase 2: Loading

**Layout**:
```
┌─────────────────────────────────┐
│                                 │
│                                 │
│                                 │
│      [Tactical Loader]          │
│                                 │
│      CREATING COMPANY           │
│                                 │
│                                 │
│                                 │
└─────────────────────────────────┘
```

**Components Used**:
- OnboardingLoadingOverlay

**API Call**:
- `POST /api/1.1/wf/update_company`

#### Phase 3: Success + Invite

**Layout**:
```
┌─────────────────────────────────┐
│  ←                              │
│                                 │
│  COMPANY CREATED                │
│                                 │
│  Share this code with your      │
│  crew so they can join.         │
│                                 │
│  ┌─────────────────────────┐    │
│  │ [ 1736017234629x6841 ]  │    │
│  │          COPY           │    │
│  └─────────────────────────┘    │
│                                 │
│                                 │
│  INVITE YOUR CREW               │
│                                 │
│  ┌─────────────────────────┐    │
│  │    Send Email Invite    │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │  Choose from Contacts   │    │
│  └─────────────────────────┘    │
│                                 │
│                                 │
├─────────────────────────────────┤
│  ┌─────────────────────────┐    │
│  │        CONTINUE          │    │
│  └─────────────────────────┘    │
│                                 │
│      I'll do this later         │
└─────────────────────────────────┘
```

**Components Used**:
- OnboardingScaffold
- OnboardingHeader
- OnboardingCodeDisplay
- OnboardingSectionHeader
- OnboardingSecondaryButton (x2)
- OnboardingFooter with OnboardingPrimaryButton and OnboardingTextButton

**Interactions**:
- Tap COPY → Copy code to clipboard, haptic feedback, brief text confirmation
- Tap "Send Email Invite" → Present InviteSheet
- Tap "Choose from Contacts" → Present native contact picker
- Tap CONTINUE → Advance to Ready
- Tap "I'll do this later" → Advance to Ready

**Data Saved**:
- `state.firstName`
- `state.lastName`
- `state.phone`
- `state.companyName`
- `state.companyAddress`
- `state.companyId`
- `state.companyCode`

---

### Screen 3B: Profile + Join (Employee)

**Purpose**: Collect profile and join company.

#### Phase 1: Form Input

**Layout**:
```
┌─────────────────────────────────┐
│  ←                              │
│                                 │
│  ABOUT YOU                      │
│                                 │
│  ┌─────────────────────────┐    │
│  │ First name              │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │ Last name               │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │ Phone (optional)        │    │
│  └─────────────────────────┘    │
│                                 │
│                                 │
│  JOIN YOUR COMPANY              │
│                                 │
│  Enter the code from your       │
│  company admin.                 │
│                                 │
│  ┌─────────────────────────┐    │
│  │ [                      ]│    │
│  └─────────────────────────┘    │
│                                 │
├─────────────────────────────────┤
│  ┌─────────────────────────┐    │
│  │      JOIN COMPANY        │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

**Components Used**:
- OnboardingScaffold
- OnboardingHeader
- OnboardingSectionHeader (x2)
- OnboardingTextField (first name, last name)
- OnboardingPhoneField
- OnboardingCodeField
- OnboardingFooter with OnboardingPrimaryButton

**Skip Logic**:
- If user already has `company_id`, hide JOIN YOUR COMPANY section
- Show only profile fields
- Change button to CONTINUE

#### Phase 2: Loading

Same pattern as Screen 3A.

**API Call**:
- `POST /api/1.1/wf/join_company`

#### Phase 3: Success

Brief confirmation, then auto-advance or show minimal success state before Ready screen.

**Data Saved**:
- `state.firstName`
- `state.lastName`
- `state.phone`
- `state.companyCode`
- `state.companyId`

---

### Screen 4: Ready

**Purpose**: Confirm completion, transition to app.

**Layout**:
```
┌─────────────────────────────────┐
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│  YOU'RE SET                     │
│                                 │
│  Welcome to OPS, [FirstName].   │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
├─────────────────────────────────┤
│  ┌─────────────────────────┐    │
│  │    LET'S GET TO WORK     │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘
```

**Components Used**:
- OnboardingScaffold (no header)
- OnboardingFooter with OnboardingPrimaryButton

**Visual Notes**:
- No large checkmark icon
- No animation
- Simple text confirmation
- Generous negative space

**On Completion**:
- Set `state.isComplete = true`
- Set `state.completedAt = Date()`
- Persist `onboarding_completed = true`
- Persist `is_authenticated = true`
- Apply default preferences
- Trigger transition to main app

---

## State Management

### OnboardingState Model

```
Properties:
- currentScreen: OnboardingScreen enum
- userType: UserType enum (company, employee)
- email: String (optional)
- userId: String (optional)
- usedSocialLogin: Bool
- firstName: String (optional)
- lastName: String (optional)
- phone: String (optional)
- companyId: String (optional)
- companyCode: String (optional)
- companyName: String (optional)
- companyAddress: String (optional)
- isComplete: Bool
- completedAt: Date (optional)
```

### Screen Enumeration

```
- welcome
- credentials
- profileCompany
- profileJoin
- ready
```

### Persistence

- State persisted to UserDefaults as JSON
- Key: `onboarding_state_v3`
- Allows resume if app closes mid-flow
- Clear state on completion

### Navigation Logic

**Forward**:
- Welcome → Credentials
- Credentials → ProfileCompany (if company) or ProfileJoin (if employee)
- ProfileCompany → Ready
- ProfileJoin → Ready
- Ready → Main app

**Back**:
- Credentials → Welcome
- ProfileCompany → Credentials (warn if data entered)
- ProfileJoin → Credentials (warn if data entered)
- Ready → No back

---

## Copy Specifications

All copy must be direct, practical, and field-appropriate. No corporate speak. No exclamation points.

### Screen 1: Welcome

| Element | Copy |
|---------|------|
| Headline | FIELD-FIRST PROJECT MANAGEMENT |
| Subheadline | Built by trades. For trades. |
| Company Button | I'M STARTING A TEAM |
| Employee Button | I'M JOINING A TEAM |
| Sign In Link | Already have an account? Sign in |

### Screen 2: Credentials

| Element | Copy |
|---------|------|
| Headline | CREATE YOUR ACCOUNT |
| Email Placeholder | Email |
| Password Placeholder | Password |
| Primary Button | CREATE ACCOUNT |
| Primary Button Loading | CREATING |
| Divider Text | or continue with |
| Error: Invalid Email | Enter a valid email |
| Error: Password Short | Password needs 8 or more characters |
| Error: Duplicate Account | Account already exists. Sign in instead. |

### Screen 3A: Profile + Company + Invite

**Phase 1**

| Element | Copy |
|---------|------|
| Section Header 1 | ABOUT YOU |
| First Name Placeholder | First name |
| Last Name Placeholder | Last name |
| Phone Placeholder | Phone (optional) |
| Section Header 2 | YOUR COMPANY |
| Company Name Placeholder | Company name |
| Address Placeholder | Address (optional) |
| Primary Button | CREATE COMPANY |
| Primary Button Loading | CREATING |

**Phase 2**

| Element | Copy |
|---------|------|
| Loading Message | CREATING COMPANY |

**Phase 3**

| Element | Copy |
|---------|------|
| Headline | COMPANY CREATED |
| Code Instructions | Share this code with your crew so they can join. |
| Copy Button | COPY |
| Copy Confirmation | COPIED |
| Section Header | INVITE YOUR CREW |
| Email Button | Send Email Invite |
| Contacts Button | Choose from Contacts |
| Primary Button | CONTINUE |
| Skip Link | I'll do this later |

**Invite Sheet**

| Element | Copy |
|---------|------|
| Title | INVITE TEAM MEMBER |
| Email Placeholder | Email address |
| Send Button | SEND INVITE |
| Send Button Loading | SENDING |
| Add Another | + Add another |
| Sent Label | SENT |

### Screen 3B: Profile + Join

**Phase 1**

| Element | Copy |
|---------|------|
| Section Header 1 | ABOUT YOU |
| First Name Placeholder | First name |
| Last Name Placeholder | Last name |
| Phone Placeholder | Phone (optional) |
| Section Header 2 | JOIN YOUR COMPANY |
| Code Instructions | Enter the code from your company admin. |
| Code Placeholder | [ Company code ] |
| Primary Button | JOIN COMPANY |
| Primary Button Loading | JOINING |
| Error: Invalid Code | Invalid company code |
| Error: Not Found | Company not found. Check your code. |

**Phase 2**

| Element | Copy |
|---------|------|
| Loading Message | JOINING COMPANY |

### Screen 4: Ready

| Element | Copy |
|---------|------|
| Headline | YOU'RE SET |
| Message | Welcome to OPS, [FirstName]. |
| Primary Button | LET'S GET TO WORK |

### Global Error Messages

| Scenario | Copy |
|----------|------|
| Network Error | No connection. Check your signal. |
| Server Error | Something went wrong. Try again. |
| Session Expired | Session expired. Sign in again. |

---

## OPSStyle Requirements

Claude Code should verify these exist in OPSStyle or create them:

### Colors

- Background color (dark)
- Input field background
- Input border default
- Input border focused (accent)
- Input border error
- Divider color
- Primary button background (accent)
- Primary button text
- Secondary button border (accent)
- Secondary button text (accent)
- Text button color
- Error color

### Typography

- Large headline (screen titles)
- Section header (uppercase, tracked)
- Body text
- Input text
- Button text
- Caption/helper text
- Code display (monospace)

### Layout

- Standard horizontal padding
- Content vertical spacing
- Section header top margin
- Input field height
- Primary button height
- Secondary button height
- Corner radius (minimal)

### Components

- Tactical loader (existing)
- Back button/icon (existing)

---

## File Structure

```
Onboarding/
├── OnboardingCoordinator.swift
├── OnboardingState.swift
├── OnboardingManager.swift
│
├── Layout/
│   ├── OnboardingScaffold.swift
│   ├── OnboardingHeader.swift
│   ├── OnboardingFooter.swift
│   └── OnboardingContentStack.swift
│
├── Inputs/
│   ├── OnboardingTextField.swift
│   ├── OnboardingSecureField.swift
│   ├── OnboardingPhoneField.swift
│   ├── OnboardingAddressField.swift
│   └── OnboardingCodeField.swift
│
├── Buttons/
│   ├── OnboardingPrimaryButton.swift
│   ├── OnboardingSecondaryButton.swift
│   ├── OnboardingTextButton.swift
│   └── OnboardingSocialButton.swift
│
├── Display/
│   ├── OnboardingSectionHeader.swift
│   ├── OnboardingDivider.swift
│   ├── OnboardingCodeDisplay.swift
│   └── OnboardingLoadingOverlay.swift
│
├── Sheets/
│   └── InviteSheet.swift
│
├── Screens/
│   ├── WelcomeScreen.swift
│   ├── CredentialsScreen.swift
│   ├── ProfileCompanyScreen.swift
│   ├── ProfileJoinScreen.swift
│   └── ReadyScreen.swift
│
└── Utilities/
    ├── OnboardingValidation.swift
    └── PhoneNumberFormatter.swift
```

---

## API Integration

Use existing endpoints. No changes required.

| Endpoint | When Used |
|----------|-----------|
| POST /api/1.1/wf/sign_company_up | Credentials screen, company path |
| POST /api/1.1/wf/sign_employee_up | Credentials screen, employee path |
| POST /api/1.1/wf/update_company | ProfileCompany screen, creates company |
| POST /api/1.1/wf/join_company | ProfileJoin screen, joins company |
| POST /api/1.1/wf/send_invite | InviteSheet, sends email invite |

---

## Existing Code Integration

- Use existing DataController for API calls
- Use existing AuthManager for social login
- Use existing SyncManager.syncCompany() after company creation/join
- Use existing OPSStyle for all design tokens
- Use existing tactical loader component

---

## Migration Notes

- New state key: `onboarding_state_v3`
- Users with `onboarding_completed = true` skip onboarding
- Users mid-flow in old onboarding restart with new flow
- Old onboarding files can be deprecated after new flow is stable

---

## Testing Checklist

- [ ] Company flow: Email signup
- [ ] Company flow: Google signup
- [ ] Company flow: Apple signup
- [ ] Employee flow: Email signup
- [ ] Employee flow: Google signup
- [ ] Employee flow: Apple signup
- [ ] Code copy functionality
- [ ] Email invite send
- [ ] Contact picker invite
- [ ] Resume from each screen after app backgrounded
- [ ] Back navigation from each screen
- [ ] All validation states
- [ ] All error states
- [ ] Keyboard handling
- [ ] Offline behavior

---

## Out of Scope (Phase 2)

Interactive tutorial will be specified in a separate document:
- Swipe-to-update-status demo
- Home screen mockup with FAB
- Project creation with example data
- Calendar view with pre-populated tasks
- Employee variant with long-press interaction

---

**End of Specification**
