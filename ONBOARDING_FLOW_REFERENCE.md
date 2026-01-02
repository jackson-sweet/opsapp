# Onboarding Flow Reference

This document details every screen in both onboarding flows, including screen titles, copy, user actions, and navigation paths.

**Last Updated:** January 1, 2026

---

## Flow Overview

OPS has two distinct onboarding flows based on user type:

1. **Company Creator Flow** - For users creating a new company (admins)
2. **Employee Flow** - For users joining an existing company (field crew)

Both flows share the same entry point (Welcome → Signup) and exit point (Ready → Tutorial).

---

## Shared Entry Screens

### 1. Welcome Screen (`welcome`)

**Purpose:** Hero landing screen - first screen users see when downloading the app.

| Element | Content |
|---------|---------|
| Logo | OPS logo + "OPS" text |
| Tagline | "BUILT BY TRADES. FOR TRADES." |
| Subtitle | "Job management your crew will actually use." |
| Primary Button | "GET STARTED" → Signup Screen |
| Secondary Button | "SIGN IN" → Login Screen |

**Background:** Slideshow of hero images (hero_1 through hero_6) with 4-second transitions.

---

### 2. Signup Screen (`signup`)

**Purpose:** User type selection - choose between "Run a Crew" or "Join a Crew".

| Element | Content |
|---------|---------|
| Title | "HOW WILL YOU USE OPS?" |
| Subtitle | "Pick one to get started." |
| Back Button | → Welcome Screen |

**Segmented Picker Options:**

| Option | Icon | Headline | Description | Features |
|--------|------|----------|-------------|----------|
| **JOIN A CREW** | `person.badge.plus` | "SEE YOUR JOBS. GET TO WORK." | "Your schedule, job details, and directions—all in one place. No more digging through texts for details." | Stay briefed on all your jobs, One-tap directions to the site, No more missed details, Mark complete when done |
| **RUN A CREW** | `building.2.fill` | "REGISTER YOUR COMPANY. RUN YOUR JOBS." | "Create jobs, assign your crew, track progress. No training required—open it and you know what to do." | Create projects in seconds, Assign crew with one tap, See progress from the truck, Works offline, syncs later |

**Continue Button:** Dynamic text based on selection
- JOIN A CREW → "JOIN MY CREW"
- RUN A CREW → "SET UP MY COMPANY"

---

### 3. Credentials Screen (`credentials`)

**Purpose:** Account creation with email/password or social auth.

| Element | Content |
|---------|---------|
| Title | "CREATE YOUR ACCOUNT" |
| Subtitle (Company) | "Let's get you set up. No credit card required." |
| Subtitle (Employee) | "Join your crew on OPS." |
| Back Button | → Signup Screen |

**Form Fields:**
- EMAIL - with validation checkmark/x
- PASSWORD - with show/hide toggle, validation indicator
- Password hint: "8+ characters"

**Buttons:**
- "CREATE ACCOUNT" (primary, white)
- "OR" divider
- "Continue with Google" (social auth)
- "Continue with Apple" (social auth)

---

### 4. Profile Screen (`profile`)

**Purpose:** Personal profile - name, phone, avatar.

| Element | Content |
|---------|---------|
| Title | "YOUR INFO" |
| Subtitle | "Your crew will see this." |
| Sign Out | Available in header |

**Form Fields:**
- Avatar uploader (circular, 120pt) - "ADD PHOTO" (Optional)
- FIRST NAME (required)
- LAST NAME (required)
- PHONE (optional)

**Continue Button:** "CONTINUE" → Company Setup (creator) or Code Entry (employee)

---

## Company Creator Flow

### 5. Company Setup Screen (`companySetup`)

**Purpose:** Company basics - name, logo, contact info.

| Element | Content |
|---------|---------|
| Title | "YOUR COMPANY" |
| Subtitle | "This is how you'll appear to your crew." |
| Back Button | → Profile Screen |
| Sign Out | Available in header |

**Form Fields:**
- Logo uploader (100pt, rounded square) - "COMPANY LOGO" (Optional)
- COMPANY NAME (required)
- OFFICE EMAIL (optional) - "Use mine" quick-fill button
- OFFICE PHONE (optional) - "Use mine" quick-fill button

**Continue Button:** "CONTINUE" → Company Details Screen

---

### 6. Company Details Screen (`companyDetails`)

**Purpose:** Company details - industry, size, age.

| Element | Content |
|---------|---------|
| Title | "ALMOST DONE" |
| Subtitle | "Quick details to set you up right." |
| Back Button | → Company Setup Screen |
| Sign Out | Available in header |

**Form Fields:**

**WHAT DO YOU DO?** (Industry picker sheet)
- Searchable list of trades (Electrical, Plumbing, HVAC, etc.)
- "Other" option with custom text field

**HOW MANY ON YOUR CREW?** (Pill buttons)
- Just Me
- 2-5
- 6-15
- 16-50
- 50+

**HOW LONG IN BUSINESS?** (Pill buttons)
- New
- 1-3 years
- 4-10 years
- 10+ years

**Continue Button:** "CREATE COMPANY" → Company Code Screen

---

### 7. Company Code Screen (`companyCode`)

**Purpose:** Display company code after successful creation.

| Element | Content |
|---------|---------|
| Title | "YOU'RE SET UP." |
| Subtitle | "[Company Name] is ready." |

**Content:**
- CREW CODE label
- Code display: "[CODE]" - full width, tap to copy
- "TAP TO COPY CODE" instruction
- Copies to clipboard, shows "CODE COPIED" in success green
- "Share this with your crew so they can join."

**Actions:**
- "INVITE CREW" button → Invite Team Sheet
- "LET'S GO" button → Ready Screen

**Footer:** "You'll find this code in Settings anytime."

**Invite Team Sheet:**
- Crew code with copy button
- "TEXT IT" → Opens SMS with pre-filled message
- "EMAIL IT" → Expands to email input fields

---

## Employee Flow

### 5. Code Entry Screen (`codeEntry`)

**Purpose:** Enter crew code to join a company.

| Element | Content |
|---------|---------|
| Title | "JOIN YOUR CREW" |
| Subtitle | "Enter the code your boss gave you." |
| Back Button | → Profile Screen |
| Sign Out | Available in header |

**Input:**
- Expanding bracket input: `[ CODE ]`
- Expands to full width when focused
- Contracts to fit text when blurred

**Help:**
- "Where is my code?" link → Help sheet
- Help sheet explains where to get the code
- Option to switch to "Create Company" flow

**Continue Button:** "JOIN CREW" → Ready Screen

---

## Shared Exit Screens

### Ready Screen (`ready`)

**Purpose:** Billing info + Welcome guide pages.

**Page 1: Billing Info**
- Subscription details based on user type
- Trial information
- "START TRIAL" button

**Welcome Guide Pages (Company Creator):**
| Page | Title | Screenshots | Description |
|------|-------|-------------|-------------|
| 1 | [PAGE_TITLE] | screenshot carousel | Feature description |

**Welcome Guide Pages (Employee):**
| Page | Title | Screenshots | Description |
|------|-------|-------------|-------------|
| 1 | [PAGE_TITLE] | screenshot carousel | Feature description |

**Navigation:**
- Page dots for welcome guide pages
- "NEXT" between pages
- "LET'S GO" on final page → Tutorial (if not completed) or Main App

---

### Tutorial Screen (`tutorial`)

**Purpose:** Interactive tutorial teaching app basics.

See [TUTORIAL_FLOW_REFERENCE.md](DEMO%20IMPLEMENTATION/TUTORIAL_FLOW_REFERENCE.md) for complete tutorial documentation.

---

## Navigation Flow Diagram

```
                    ┌─────────────┐
                    │   Welcome   │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │                         │
              ▼                         ▼
        ┌──────────┐              ┌──────────┐
        │  Login   │              │  Signup  │
        └────┬─────┘              └────┬─────┘
             │                         │
             │    (resume)             ▼
             └─────────────►   ┌──────────────┐
                               │ Credentials  │
                               └──────┬───────┘
                                      │
                                      ▼
                               ┌──────────────┐
                               │   Profile    │
                               └──────┬───────┘
                                      │
                    ┌─────────────────┼─────────────────┐
                    │ (Company)       │                 │ (Employee)
                    ▼                 │                 ▼
             ┌─────────────┐          │          ┌─────────────┐
             │ CompanySetup│          │          │  CodeEntry  │
             └──────┬──────┘          │          └──────┬──────┘
                    │                 │                 │
                    ▼                 │                 │
             ┌─────────────┐          │                 │
             │CompanyDetail│          │                 │
             └──────┬──────┘          │                 │
                    │                 │                 │
                    ▼                 │                 │
             ┌─────────────┐          │                 │
             │ CompanyCode │          │                 │
             └──────┬──────┘          │                 │
                    │                 │                 │
                    └─────────────────┴─────────────────┘
                                      │
                                      ▼
                               ┌──────────────┐
                               │    Ready     │
                               └──────┬───────┘
                                      │
                                      ▼
                               ┌──────────────┐
                               │   Tutorial   │
                               └──────┬───────┘
                                      │
                                      ▼
                               ┌──────────────┐
                               │   Main App   │
                               └──────────────┘
```

---

## State Persistence

Onboarding state is persisted to UserDefaults under key `onboarding_state_v3`. This allows:
- Resume from any screen if app is killed
- Pre-fill data from previous sessions
- Track which flow the user is on

**Tracked State:**
- `currentScreen` - Current screen in flow
- `flow` - `.companyCreator` or `.employee`
- `userData` - First name, last name, phone, email, avatar
- `companyData` - Company name, industry, size, age, code, logo
- `isAuthenticated` - Whether user has valid auth
- `hasExistingCompany` - Whether user already has a company

---

## API Calls by Screen

| Screen | API Calls |
|--------|-----------|
| Credentials | `signUpUser()` - Create account |
| Credentials | `loginWithGoogle/Apple()` - Social auth |
| Profile | None (local state only) |
| CompanySetup | None (local state only) |
| CompanyDetails | `updateCompany()` - Create company |
| CompanyCode | `syncCompany()` - Sync company data |
| CodeEntry | `joinCompany()` - Join with code |
| Ready | None |
| Tutorial | See tutorial reference |

---

## Progress Bar

Progress bar appears after Credentials screen:

| Screen | Progress (Company) | Progress (Employee) |
|--------|-------------------|---------------------|
| Profile | 1/4 | 1/3 |
| CompanySetup | 2/4 | - |
| CompanyDetails | 3/4 | - |
| CompanyCode | 4/4 | - |
| CodeEntry | - | 2/3 |
| Ready | Complete | Complete |

---

## Animation System

All screens use the **Phased Animation Coordinator** for entrance effects:

1. **Title Phase** - Title types in with typewriter effect
2. **Subtitle Phase** - Subtitle fades in below title
3. **Content Phase** - Form content fades in upward
4. **Labels Phase** - Field labels type in sequentially
5. **Button Phase** - Continue button slides up

This creates a cohesive, polished entrance animation across all screens.

---

## Files Reference

| File | Purpose |
|------|---------|
| `OnboardingContainer.swift` | Main container, routes between screens |
| `OnboardingManager.swift` | State management, navigation, API calls |
| `OnboardingState.swift` | State model, persistence |
| `WelcomeScreen.swift` | Hero landing screen |
| `SignupScreen.swift` | User type selection |
| `CredentialsScreen.swift` | Account creation |
| `ProfileScreen.swift` | Personal profile |
| `CompanySetupScreen.swift` | Company basics |
| `CompanyDetailsScreen.swift` | Company details |
| `CompanyCodeScreen.swift` | Code display + invite |
| `CodeEntryScreen.swift` | Join with code |
| `ReadyScreen.swift` | Billing + welcome guide |
| `UserTypeSelectionContent.swift` | Segmented picker component |
| `OnboardingScaffold.swift` | Reusable screen layout |
| `OnboardingComponents.swift` | Shared UI components |
