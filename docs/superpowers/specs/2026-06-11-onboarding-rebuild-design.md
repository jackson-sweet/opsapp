# Onboarding Rebuild — Design Spec

**Date:** 2026-06-11
**Project codename for spawned tasks:** `ONBOARDING REBUILD`
**Status:** Awaiting user approval (rev 2 — post adversarial review)

## 1. Why

A full audit (UI/UX review, backend hookup trace, iOS↔Web↔DB alignment audit) found the pre-login experience broken at every layer:

- **Structural:** two abandoned onboarding generations (~70 dead/superseded Swift files — full manifest in Appendix A) coexist with the live flow; the live coordinator (`OnboardingABTestCoordinator`) is mounted in TWO places (`ContentView.swift:259` and `LandingView.swift:338`) with divergent completion logic; three drifting login forms; a redundant double-welcome (LandingView → "GET SIGNED UP" → a second near-identical splash).
- **Broken UX:** four dead-end screens (signup and company-name have no Back; invite-picker's Back is a no-op; code-entry's only exit is SIGN OUT); employee profile contradicts its own optional/required contract.
- **Off-brand:** every headline in Mohave instead of Cake Mono; banned spring physics in ~10 sites; Reduce Motion ignored everywhere except `WorkspacePreloadGate`; haptics missing on nearly every commit including the final FINISH; generic SaaS copy ("Enter your credentials").
- **Backend defects:** plaintext password in UserDefaults; `user_type` write queued-not-awaited; client-generated company code with no server uniqueness and a retry path that regenerates a code diverging from the DB; silent `try?` swallows on role/admin writes, notifications, avatar upload; fire-and-forget `firebase_uid` backfill; tutorial flag written to a **non-existent column** (`has_completed_app_tutorial`; real column is `has_completed_tutorial`); a legacy `OnboardingViewModel` path that would write a Firebase UID into the UUID `users.id`.
- **Cross-platform divergence:** iOS and OPS-Web create company owners differently (iOS sets `users.role='owner'` + `user_roles` Owner row; web sets only `is_company_admin=true`), leaving owners in inconsistent permission states. 30+ existing accounts show the mismatch, but **none are real customers** — only *Canpro Deck and Rail* (real) and *MAVERICK PROJECTS LTD* (internal test) matter. **Verified 2026-06-11: both owner records are clean.** Five member-row inconsistencies found (§6.5).

## 2. Decisions (locked with user)

1. **Rebuild clean** — not patch-in-place.
2. **Single flow this version: fastest-into-the-app ("express").** The old A/B/C machinery is removed. The original experiment intent (express vs interactive tutorial vs workflow animation) is preserved as tracked follow-up work — two `bug_reports` rows filed (category `feature_request`, dedupe keys `onboarding-followup-interactive-tutorial`, `onboarding-followup-workflow-animation`, ids `07967be2…`, `7d8327b2…`). The experiment framework is rebuilt properly **when those variants are built**, not now.
3. **Auth provider is Firebase — unchanged.** Supabase is data-only. All flows remain: Firebase sign-in → `POST /api/auth/sync-user` (ops-web, service-role) → `users` row with proper UUID. No Supabase Auth anywhere.
4. **Forward-only data fixes.** Fix both apps so new accounts are correct. No mass migration. Verify (and minimally repair, with sign-off) only the Canpro and Maverick accounts.
5. **OPS-Web is in scope** for the owner-creation unification (forward-only).
6. **Skill use is non-negotiable (Jackson, 2026-06-11).** Any UI work — by the main session or any subagent — must at minimum invoke the OPS design system skill. See §12; it is a hard gate on every UI phase.

## 3. Goals / Non-goals

**Goals**

- One welcome, one login, one onboarding flow, mounted once, with one completion path.
- Every screen: Back wherever a legal back-edge exists (per the §5.2 back map — steps whose predecessor's action is already committed get SIGN OUT as the escape instead, never a dead end), Cake Mono titles, OPS motion curve only, Reduce Motion honored, haptics on arrivals/commits/success, 20pt canvas padding, spec inputs, ≥44pt touch targets.
- Every onboarding write confirmed or **visibly** queued — zero failures that are silent *to the user* on the critical path.
- iOS and Web produce identical owner role/permission records via one shared server path.
- Delete all dead/superseded onboarding code (Appendix A).
- Per-step funnel analytics preserved (baseline for the future experiment).

**Non-goals (this version)**

- The interactive tutorial variant (follow-up `07967be2`).
- The workflow-animation variant (follow-up `7d8327b2`).
- The experiment/variant framework itself (rebuilt with the variants).
- Mass repair of historical broken accounts.
- Any change to Firebase auth architecture, PIN system, `WorkspacePreloadGate`, `OfflineGateView`, or `SplashLoadingView` (kept as-is; the preload gate is the quality template).

## 4. The new flow (user-facing)

All copy below is **intent** — final strings via `ops-copywriter` at implementation. Voice: terse, tactical; the crew-path benchmark is the existing `"Enter the code your boss gave you."`

### 4.1 Route map

```
ContentView
├── isCheckingAuth                                  → SplashLoadingView   (kept)
├── offline fresh-install                           → OfflineGateView     (kept)
├── !authenticated
│   OR (authenticated && shouldShowOnboarding)      → OnboardingGateway   (NEW — the single pre-app mount)
│       ├── !authenticated:  Welcome → Login | OnboardingFlow (from S2)
│       └── authenticated && incomplete: OnboardingFlow resumed at the derived step (§5.3)
└── authenticated && !shouldShowOnboarding          → PINGatedView → MainTabView  (kept)
    └── WorkspacePreloadGate overlay for returning-login sync             (kept)
```

`OnboardingGateway` is the **single pre-app mount**: it owns Welcome, Login, and the one `OnboardingFlow` instance for both anonymous and authenticated-but-incomplete users — so a kill/relaunch mid-onboarding resumes the flow, never lands in the main app. One completion path. `LandingView`, `ABTestSplashView`, the second coordinator mount, and both duplicate login forms are deleted at cutover (§10 P7).

### 4.2 Screens

**Screen-count rule:** counts below = interactive screens requiring user input; auto-advancing transitions (invite check) and the completion gate are excluded. **Owner: 5. Crew: 6 (single invite), 7 (picker or manual code).**

**S1 — Welcome** (replaces LandingView + ABTestSplashView)
Brand line (`BUILT BY TRADES. FOR TRADES.`), one subline, version footer.
CTAs: `GET STARTED` → S2 · `SIGN IN` → Login.
Serves new and returning users identically. Static-first hero (no auto-playing slideshow; any motion honors Reduce Motion).

**Login** (one shared implementation; Back → S1)
Email + password, Apple, Google, forgot-password. Inline field-level errors per MOBILE.md §9. Outcomes:
- Returning complete user → workspace preload gate path (existing ContentView arming logic, kept).
- Returning incomplete user → OnboardingFlow at the derived resume step (§5.3).
- Social sign-in resolving to a brand-new identity (no prior `users` row / no onboarding state): `sync-user` runs, then routes into the flow at S2 with auth already satisfied — S3 is skipped. (Creating an account from the Login path is allowed and lands in the same flow.)

**S2 — Role pick** (Back → S1 pre-auth; when resumed post-auth: no Back, header `SIGN OUT`)
Two tappable cards: `RUN A CREW` / `JOIN A CREW`. One tap advances. Existing role-benefit copy retained. **Role choice is uncommitted until a company is created or joined** — it can be revisited via back-edges below, which kills the wrong-role trap.

**S3 — Create account** (Back → S2)
Apple / Google / email. **Commit point: the Firebase account + `sync-user` row are created on S3 submit** — everything before S3 is uncommitted; everything after is post-account. **Name rule: no path may exit S3 with an empty first or last name.** Email form collects first+last inline; Apple/Google names auto-fill when provided; if the resolved name is empty after ANY auth method (Apple subsequent-auth on fresh install, Google without profile name), the inline name fields appear and are required before continuing. The Apple name cache moves from UserDefaults to Keychain so it survives reinstall. Password: show/hide toggle + inline rule hint before submit. **Existing-account handling:** email already registered → inline error with a one-tap `SIGN IN` handoff (prefilled email); Apple/Google resolving to an existing account → treated as sign-in (complete user → app via the returning path; incomplete user → derived resume, same rule as Login).

**Owner path:**

- **S4o — Company name** (no back-edge to S3 — the account is committed; Back → S2 to re-pick role since no company exists yet; header `SIGN OUT`) — single field + optional primary-trade chips (`companies.industries`).
- **S5o — Crew code** (the payoff; no back-edge — company is committed) — code in JetBrains Mono, bracketed, tracked, **identical render to the entry screen**; COPY with success haptic; INVITE CREW; `You'll find this code in Settings anytime.` CTA: `ENTER OPS →`. No box-shadow (hairline + glass).
- → Completion gate → app.

**Crew path:**

- **S4c — Invite check** (auto transition, unified loading voice). Outcomes: exactly one invite → S5c; 2+ → invite picker; none → S4c-code. **Fetch/decode failure is a user-visible retry state** (`CHECK AGAIN` + `ENTER CODE INSTEAD`), never silently treated as zero invites (R13).
- **Invite picker** (Back → S2; secondary `ENTER A DIFFERENT CODE` → S4c-code) — cards kept; `Capsule` pills → `chipRadius` tags.
- **S4c-code — Crew code entry** (Back → S2 when reached via zero invites; Back → picker when reached from the picker — the back map carries provenance; header `SIGN OUT` secondary, never the sole exit) — bracket-mono input kept.
- **S5c — Confirm company** (Back → its source: picker or S4c-code) — branding/team preview before commit. Headline intent: `CONFIRM YOUR CREW` (the audited `WELCOME TO` is banned, §4.3). Sparse-data fallback gets a deliberate reduced layout.
- **S6c — Profile** (no back-edge — join is committed; header `SIGN OUT`) — first/last (prefilled from S3, editable), phone, photo. **Name + phone required, photo optional** — docs, validation, and coordinator agree; dead `onSkip` removed. Avatar upload shows progress, surfaces failure with retry; a skip-after-failure proceeds knowingly.
- **S7c — Emergency contact** (Back → S6c; visible `SKIP`) — `FINISH` fires a medium-impact commit haptic on tap; the **success notification** fires when the completion gate lands (server ACK or visible queue-accept), so the success signal never precedes the write it celebrates.
- → Completion gate → app.

**Completion gate** (both paths, auto): awaits the server ACK (`POST /api/onboarding/complete` → `users.onboarding_completed.ios = true`) behind a loader built to `WorkspacePreloadGate`'s standard. **Offline/failure contract (designed for poor connectivity):** if the ACK fails or exceeds ~8s, the completion is queued locally with a visible "will finish syncing" state and the user **enters the app**; `shouldShowOnboarding` treats a queued completion as complete; the SyncEngine drains the queued ACK until the server confirms. No blocking, no re-entry loop, no silent failure.

### 4.3 Cross-cutting UI standard (every new screen)

- Titles: Cake Mono Light via `Typography.display`/`pageTitle`/`section`; one consistent title scale across steps.
- **Primary CTAs: steel-blue accent fill** per the design system (accent is for primary CTA and focus ring ONLY — the current white-fill primaries are replaced); verify treatment against `MOBILE.md` §8 at implementation.
- Motion: `OPSStyle.Animation` curves only; zero `.spring`; zero typewriter; every entrance/loop gated on `accessibilityReduceMotion` (150ms crossfade fallback).
- Haptics: light impact on step arrival; medium impact on commits (create account, create company, join, save profile); success notification on crew-code reveal and onboarding completion.
- Layout: 20pt canvas padding; one shared `OPSOnboardingField` input (48pt, 0.04 fill, 5pt radius, inline error state); 52pt bottom CTAs; disabled CTAs use opacity, not gray swap.
- Numbers/codes: JetBrains Mono, tabular, bracketed crew codes — identical render on share and entry screens.
- Back labels name the previous screen (not "Back") per MOBILE.md §2.1.
- Loading voice unified (one "setting up" string family).
- Copy via `ops-copywriter`; **banned strings:** exclamation points, "Welcome back!", "Enter your credentials", "WELCOME TO".

## 5. Architecture (iOS)

### 5.1 New module layout (`OPS/Onboarding/`, rebuilt)

```
Onboarding/
├── Gateway/OnboardingGateway.swift        — single pre-app mount; owns Welcome/Login/Flow
├── Flow/OnboardingFlowCoordinator.swift   — explicit state machine (steps, back map, persistence)
├── Flow/OnboardingFlowStep.swift          — step enum + data-driven back-edge map (§5.2)
├── Screens/ (new screens above, fresh type names — no dead-name reuse)
├── Components/ (OPSOnboardingField, shared header w/ Back+SignOut, CTA button, code display)
├── Manager/OnboardingManager.swift        — kept, hardened (writes layer)
├── Services/OnboardingService.swift       — kept (sync-user, complete endpoints)
└── State/OnboardingFlowState.swift        — single versioned state blob (§5.3)
```

### 5.2 Back map (single source of truth)

Each step declares its back-edge in `OnboardingFlowStep`; the header renders Back only when an edge exists, so a no-op Back is structurally impossible. Edges: `Login→S1`, `S2→S1` (pre-auth only), `S3→S2`, `S4o→S2`, `picker→S2`, `S4c-code→S2|picker` (by provenance), `S5c→source`, `S7c→S6c`. No edge (SIGN OUT escape): post-auth S2, S5o, S6c, completion gate. SIGN OUT fully clears flow state and returns to S1.

### 5.3 State & resume

**One key: `onboarding_state_v4`** — a single versioned blob holding collected form data + step position + provenance. Replaces `onboarding_state_v3` + `ab_test_flow_step`; launch migration folds v3 into v4 then deletes old keys. Local state is an **optimization only** — the server-derived state is the authority:

| Observable server state | Resume target |
|---|---|
| Account exists, no company affiliation (any/no `user_type`) | S2 — role is uncommitted |
| `role='owner'` + company exists, `onboarding_completed.ios` ≠ true | S5o (re-show code) → gate |
| Employee + company, profile incomplete (blank first/last/phone) | S6c |
| Employee + company, profile complete | Completion gate (S7c is optional; not re-offered on resume) |
| Company + role complete AND `onboarding_completed.web = true`, `.ios` ≠ true | Silent auto-complete: gate fires the ACK, zero screens |

### 5.4 Reused as-is

`WorkspacePreloadGate` (quality template), `OfflineGateView`, `SplashLoadingView`, PIN system, the returning-login gate arming logic in ContentView, `ForgotPasswordView`, Apple/Google sign-in managers, `FirebaseAuthService`. `Models/OnboardingModels.swift` + `InviteModels.swift` kept (pruned). `DeferredProfile/DeferredProfilePrompter.swift`: verify references at implementation; delete if orphaned.

### 5.5 ContentView simplification & cutover seam

The `showABTestOnboarding`/`showExistingLogin`/`onboardingManagerInstance` triad and the hardcoded 2.5s auth delay are replaced by signal-driven routing (`isAuthenticated` + `shouldShowOnboarding`, splash holds until the check resolves, with a ceiling timeout). **Cutover:** a single flag `FeatureFlags.useRebuiltOnboarding` (default `false`). The legacy flow remains the live shipping path through P4; the flag flips to `true` at the end of P5 once both paths are complete and verified; P7 deletes the flag and all legacy code. Every commit ships a working flow.

## 6. Backend contracts & hardening

### 6.1 New shared RPC: `create_company_for_owner` (Postgres, SECURITY DEFINER)

One atomic server-side path used by **both clients**, replacing iOS's direct PostgREST insert and web's bespoke insert:

- **Caller identity is derived inside the RPC from the JWT** — `sub` claim (Firebase UID) → `users.firebase_uid` lookup. No caller-supplied user id is accepted (that would let any authenticated user claim a company for anyone). If no `users` row matches (sync-user race), returns a typed `NO_USER_ROW` error; the client retries after `sync-user` completes. Prerequisite: §6.4's `sync-user` amendment guarantees `firebase_uid` is set at row creation.
- Generates the company code server-side with a uniqueness loop. **Pinned scheme:** 8 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (I/O/0/1 excluded). Legacy codes (e.g. web's `PREFIX-XXXXXX`) remain valid forever: code validation is lookup-only; clients perform no format rejection (S4c-code accepts any non-empty input).
- Inserts `companies`: name, optional industries/contact fields, `admin_ids=[owner]`, `seated_employee_ids=[owner]`, `account_holder_id`, **trial pinned:** `subscription_status='trial'`, `subscription_plan='trial'`, `trial_start_date=now()`, `trial_end_date=now()+30d`, `max_seats=10` (the `initialize_company_trial` trigger backfills if null — values kept identical).
- Updates `users`: `company_id`, `role='owner'`, `is_company_admin=true`, `user_type='company'`.
- Upserts `user_roles` → Owner **with `onConflict: user_id`**.
- Calls `initialize_company_defaults`.
- **Idempotent:** if the caller already owns a company, returns the existing company + its real stored code (kills R3 code divergence).
- **Return contract (full):** `{company_id uuid, company_code text, already_existed boolean}` — S5o always displays the DB truth. Called via each platform's Supabase client (`supabase-swift` on iOS, `supabase-js` on web), authenticated by the existing Firebase-bridged session, exactly like `join_user_to_company`.

### 6.2 `join_user_to_company` RPC — amendment

- Sets `user_type='employee'`, `is_company_admin=false` atomically inside the RPC (removes the client-side `try?` writes, R5).
- **Admin rail notifications move into the RPC** via `create_notification_if_new` with the **exact dedupe-key scheme the web route uses today** (`OPS-Web/src/app/api/auth/join-company/route.ts:307-372`); the web route's own rail fan-out is removed **in the same change** so web joins don't double-notify (R6).
- **Push delivery stays client/route-side** (a Postgres RPC cannot call OneSignal): the web route keeps its OneSignal fan-out; iOS keeps `OneSignalService.notifyTeamJoin` (push only — its rail insert is removed, assigned to P5). Result: identical admin rail+push behavior for iOS- and web-originated joins.

### 6.3 iOS write-path hardening

| Defect | Fix |
|---|---|
| `user_type` queued not awaited (R1) | Owner: set by `create_company_for_owner`. Employee: set by amended join RPC. Any signup-time write becomes direct, awaited, error-surfaced. |
| Plaintext `user_password` (R10) | **Resolved by grep 2026-06-11: the only reader is the legacy `OnboardingViewModel` (deleted).** Delete the writes (`OnboardingManager.swift:664`, ViewModel), keep the existing logout removals, add a one-time launch cleanup of the stored key. Nothing moves to Keychain. |
| `firebase_uid` backfill fire-and-forget (R8) | New rows: set server-side by amended `sync-user` (§6.4). Legacy rows: backfill becomes awaited-with-retry; `firebase_uid` added to `SupabaseUserDTO` (R12) so success is verifiable. |
| Tutorial flag → non-existent column | Write key corrected to `has_completed_tutorial` (read side already correct). |
| Avatar upload silent failure (R7) | Progress UI + surfaced failure + retry on S6c. |
| Invite-decode silent `[]` (R13) | User-visible retry state on S4c (§4.2) + diagnostic event distinct from "zero invites". |
| Legacy `OnboardingViewModel` UUID corruption (R9) | Deleted with the legacy tree. |
| Completion retry ambiguity (R11) | Completion gate is its own resumable step; retry/queue re-fires only the ACK (§4.2). |

### 6.4 OPS-Web changes (forward-only)

- `setup/progress` company step calls `create_company_for_owner` (replacing its bespoke insert + `is_company_admin`-only write). Web owners get `users.role='owner'` + `user_roles` Owner — identical to iOS.
- `join-company` route: rail fan-out removed (now in the RPC); OneSignal push fan-out kept (§6.2).
- `auth/sync-user`: **also writes `users.firebase_uid` from the verified `idToken` at row creation** (it already verifies the token; this closes R8 at the source for all new accounts, both platforms).
- Per-platform `onboarding_completed.{ios,web}` keys stay as designed; the §5.3 web-complete auto-finish removes the worst cross-platform seam for iOS-first logins.

### 6.5 Account verification & repair (the only data touch — user sign-off required)

Owner records for Canpro and Maverick verified clean (2026-06-11). Five member-row fixes proposed, pending sign-off, executed in P1:

1. `j4ckson.sweet@gmail.com` (Canpro, operator): `user_type` NULL → `'employee'`.
2. `tkazansky1987@outlook.com` (Maverick, operator): `user_type` NULL → `'employee'`.
3. `vipermike1974@outlook.com` (Maverick, office): `user_type` NULL → `'employee'`.
4. `fourseasonscontracting705@gmail.com` (Canpro): `users.role='operator'` but `user_roles`=Crew → align `user_roles` to Operator (matches the role the app shows).
5. `charliejesse.gatenby@gmail.com` (Canpro, crew): `onboarding_completed = {}` → `{"ios": true}` (active crew member; prevents re-onboarding on next iOS login).

## 7. Deletions

Appendix A is the named manifest (~70 files). Grep-verify zero references before each removal — **transitively, to fixpoint** (e.g. `TypewriterText` only orphans after `UserTypeSelectionContent` is deleted). Stale UserDefaults keys get a one-time launch cleanup: `user_password`, `ab_test_flow_step`, `onboarding_state_v3`, `resume_onboarding`, `pre_signup_tutorial_completed`, `onboarding_variant` (key confirmed at `OnboardingVariantManager.swift:35`).

Verification: device-target `xcodebuild` clean after every deletion phase; full-suite `xcodebuild test` at the end.

## 8. Analytics

Per-step funnel events with clean names: `onboarding_step_viewed` / `onboarding_step_completed` (step id), `onboarding_completed` (path, duration, step count), `onboarding_abandoned` (last step), plus `onboarding_completion_queued` (offline gate) and `onboarding_invite_check_failed` (R13 diagnostic). Existing Google Ads conversion points (account created, company created) preserved.

## 9. Testing

- **Unit:** flow state machine — every forward edge, every back edge (incl. provenance edges), kill/resume restoration from each step, resume-derivation table (§5.3) against mocked server states, completion-queue idempotency. OnboardingManager operations against a mocked service layer (incl. RPC failure surfacing, `NO_USER_ROW` retry).
- **Build:** device-target build per phase (never simulator for plain build).
- **Suite:** `build-for-testing` + `test` on the simulator destination; compare against baseline per known env-launch flakiness.
- **Visual:** SwiftUI snapshot harness (ImageRenderer→XCTAttachment) for each new screen, light/dark + Reduce Motion variants.
- **Manual:** owner signup; crew join via code; crew join via invite; returning login; offline fresh install; **kill app at S4o and at S6c then relaunch (resume)**; **sign out mid-flow, sign back in (derived resume)**; **complete onboarding with network disabled at the gate (queued completion)**; **create account then change role via Back → S2**.
- **DB:** RPCs tested via rolled-back transactions as simulated users before wiring clients.

## 10. Phases

1. **P1 — Server foundation:** `create_company_for_owner` migration + `join_user_to_company` amendment + `sync-user` firebase_uid amendment + rolled-back tests; OPS-Web `setup/progress` + `join-company` switches; **§6.5 row repairs (after sign-off)**.
2. **P2 — iOS skeleton:** Gateway, flow coordinator + step machine + back map + resume derivation (tests first), `FeatureFlags.useRebuiltOnboarding` seam (default false).
3. **P3 — Welcome + Login + Role pick + Create account** (shared components land here).
4. **P4 — Owner path** (company name, crew code, completion gate incl. offline queue).
5. **P5 — Crew path** (invite check/picker/code/confirm/profile/emergency); **remove iOS client rail-insert duplicate** (§6.2); flag flips `true` at end of P5 after full manual pass.
6. **P6 — Hardening sweep:** remaining §6.3 items, key cleanup, analytics events.
7. **P7 — Deletions** (Appendix A + the seam flag) + final build/test/snapshot/manual verification.
8. **P8 — Bible + design-system docs update** (same effort, per CLAUDE.md): onboarding section rewritten to match reality; root-level ONBOARDING_* docs superseded/archived.

Each phase commits atomically as it lands (commit-without-asking authorized; no pushes).

## 11. Follow-ups (tracked, out of scope)

| Work | Tracking |
|---|---|
| Interactive tutorial onboarding variant | `bug_reports` `07967be2-90bf-4c75-8074-138d0e92fe36` |
| OPS-workflow animation onboarding variant | `bug_reports` `7d8327b2-2a9e-4d9f-bd23-140991c15f40` |
| Experiment framework (real split, remote-controlled, funnel readout) | Built alongside the first new variant; §8 funnel analytics are its baseline |

## 12. Mandatory skill & design-source protocol (hard gate — non-negotiable)

Jackson's directive (2026-06-11): skill and plugin use is non-negotiable; UI produced without the design system skill has shipped as "cheap replica" aesthetics in other sessions. Therefore, for **every** UI phase (P2–P5, and any UI touch in P6–P7):

1. **Before any screen is designed or coded**, the implementing session/agent MUST read, in order: `ops-design-system/project/SKILL.md` → `ops-design-system/project/README.md` → `ops-design-system/project/DESIGN.md` → `ops-design-system/project/mobile/MOBILE.md`. iOS token source: `OPS/OPS/Styles/OPSStyle.swift` (+ `Styles/Components/`).
2. **Registry skills invoked where they apply:** `custom-skills:mobile-ux-design` (screen design), `animation-studio:animation-architect` then `animation-studio:ios-animations` (any motion), `ops-copywriter:ops-copywriter` (every user-facing string), `custom-skills:audit-design-system` (compliance check before each phase's commit).
3. **Subagents do not inherit this** — every `Agent`/`Workflow` prompt that touches UI must explicitly embed requirement 1 and name the token sources. Output containing hardcoded colors/spacing/fonts/radii is rejected and redone; every value traces to a token.
4. The §4.3 standard is the acceptance checklist; `custom-skills:wizard-audit` runs against the finished flow before cutover.

---

## Appendix A — Deletion manifest (named set; grep-verified at removal)

**`OPS/Onboarding/Views/` — entire tree, 31 files.** Gen-1 system + the 8 live-but-replaced screens (these die at P7 cutover, after replacements ship): `OnboardingContainerView`, `OnboardingPresenter`, `OnboardingFlowPreview`, `OnboardingPreviewHelpers`; `Components/AnimatedOPSLogo`, `Components/OnboardingComponents`; `Screens/`: `AnimatedWalkthroughView`*, `BillingInfoView`, `CompanyAddressView`, `CompanyBasicInfoView`, `CompanyCodeDisplayView`, `CompanyCodeInputView`, `CompanyContactView`, `CompanyCreationLoadingView`, `CompanyDetailsView`, `CompanyNameView`*, `CompletionView`, `CrewCodeShareView`*, `EmailView`, `EmployeeCodeEntryView`*, `EmployeeCompanyConfirmationView`*, `EmployeeEmergencyContactView`*, `EmployeeProfileView`*, `FieldSetupView`, `MinimalSignupView`*, `OrganizationJoinView`, `PermissionsView`, `TeamInvitesView`, `UserInfoView`, `UserTypeSelectionView`, `WelcomeView`. (* = live today, replaced by new implementations.)

**`OPS/Onboarding/Screens/` — 17 of 19.** All except `WorkspacePreloadGate.swift` (kept) — `InvitePickerScreen.swift` is live today and deleted only after its P5 replacement ships: `AppSetupScreen`, `CodeEntryScreen`, `CompanyCodeScreen`, `CompanyConfirmationScreen`, `CompanyDetailsScreen`, `CompanySetupScreen`, `CredentialsScreen`, `EmergencyContactScreen`, `InvitePickerScreen`*, `LoginScreen`, `PostTutorialCTAScreen`, `ProfileCompanyScreen`, `ProfileJoinScreen`, `ProfileScreen`, `ReadyScreen`, `SignupScreen`, `UserTypeSelectionScreen`, `WelcomeScreen`.

**Coordinators/containers/legacy:** `ABTest/OnboardingABTestCoordinator`, `ABTest/OnboardingVariantManager`, `Container/OnboardingContainer`, `Coordinators/OnboardingCoordinator`, `ViewModels/OnboardingViewModel`, `OnboardingCopy.swift`.

**`OPS/Onboarding/Components/` — all 12** (replaced by new `Components/`): `CompanyCodeDisplay`, `InviteRolePicker`, `OnboardingHeader`, `OnboardingHelpSheet`, `OnboardingLoadingOverlay`, `OnboardingPrimaryButton`, `OnboardingProgressBar`, `OnboardingScaffold`, `PillButtonGroup`, `SocialAuthButton`, `TypewriterText`, `UserTypeSelectionContent`*.

**`OPS/Views/`:** `LandingView.swift` (incl. dead `LoginSuccessView`), `LoginView.swift`, `SplashScreen.swift`, `Debug/OnboardingPreviewView.swift`.

**Kept:** `Manager/OnboardingManager.swift` (hardened), `Services/OnboardingService.swift`, `State/` (rewritten as `OnboardingFlowState`), `Models/OnboardingModels.swift`, `Models/InviteModels.swift`, `Screens/WorkspacePreloadGate.swift`, `DeferredProfile/DeferredProfilePrompter.swift` (pending reference check).
