# Onboarding Rebuild Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the three-generation onboarding swamp with one express flow (one welcome, one login, one mount, one completion path), unify owner creation across iOS and OPS-Web via a shared RPC, harden every onboarding write, and delete ~70 dead files.

**Architecture:** Server-first: a new `create_company_for_owner` SECURITY DEFINER RPC + an amended `join_user_to_company` become the single write paths both clients share. On iOS, a new `OnboardingGateway` (single pre-app mount) hosts Welcome/Login/Flow; an explicit step machine with a data-driven back map and a server-derived resume table replaces the A/B coordinator. Legacy flow stays live behind `FeatureFlags.useRebuiltOnboarding` until P5 cutover; P7 deletes it.

**Tech Stack:** SwiftUI (iOS 17+, SwiftData), Firebase Auth (unchanged — Supabase is data-only), supabase-swift RPC, Postgres (Supabase project `ijeekuhbatykdomumfjx`), Next.js (OPS-Web), XCTest + ImageRenderer snapshot harness.

**Design System:** `ops-design-system/project/` (SKILL.md → README.md → DESIGN.md → mobile/MOBILE.md). iOS tokens: `OPS/Styles/OPSStyle.swift`. No `.interface-design/system.md` in this repo — the OPS design system is the authority.

**Spec:** `docs/superpowers/specs/2026-06-11-onboarding-rebuild-design.md` (rev 2, committed `b6ba11e8`). The spec's §12 skill gate is REQUIRED on every UI task below.

**Required Skills (executing agent MUST load):**
- Every UI task: read `ops-design-system/project/SKILL.md`, `README.md`, `DESIGN.md`, `mobile/MOBILE.md` FIRST (spec §12 — non-negotiable, Jackson directive 2026-06-11)
- `custom-skills:mobile-ux-design` — before each new screen
- `ops-copywriter:ops-copywriter` — every user-facing string (strings below are INTENT, not final copy)
- `animation-studio:animation-architect` + `animation-studio:ios-animations` — any motion work
- `custom-skills:audit-design-system` — before each UI phase's final commit
- `custom-skills:wizard-audit` — against the finished flow before P5 cutover
- `superpowers:test-driven-development` — all logic tasks

**Verified token set (use these exact names; never hardcode):**
`OPSStyle.Typography.pageTitle/.display/.section` (Cake Mono — screen titles/display voice), `.body/.button/.buttonLarge` , `.caption` (JetBrains Mono 14); `OPSStyle.Colors.background` (#000), `.primaryAccent` (#6F94B0 steel blue — primary CTA + focus ONLY), `.primaryText/.secondaryText/.tertiaryText`, `.invertedText`, `.buttonBorder`; `OPSStyle.Layout.touchTargetStandard` (56), `.buttonRadius` (5), `.cornerRadius` (5, inputs), `.panelRadius` (10), `.chipRadius` (4); `OPSStyle.Animation.standard/.panel/.page` (the single 0.22,1,0.36,1 curve — zero `.spring`).

**Branching:** iOS work on a dedicated branch `feat/onboarding-rebuild` (large feature buildout). OPS-Web edits: atomic commits on OPS-Web `main`. DB migrations: `mcp__plugin_supabase_supabase__apply_migration` (additive DDL). NO pushes without explicit permission.

**Global rules:** Device-target build (`xcodebuild -scheme OPS -destination 'generic/platform=iOS'`) at every checkpoint — never simulator for plain build. Atomic commits, stage by name, no AI attribution. New Swift files need no .pbxproj edits (Xcode 16 synchronized groups). Fresh-file "Cannot find type" SourceKit noise → trust xcodebuild.

---

## Phase P1 — Server foundation

### Task 1.1: `create_company_for_owner` RPC

**Skills:** `supabase:supabase-postgres-best-practices`. DB-only, no UI.
**Files:** Migration via `apply_migration`, name `create_company_for_owner_rpc`.

**Step 1 — Write the migration** (complete SQL):

```sql
CREATE OR REPLACE FUNCTION public.create_company_for_owner(
  p_name text,
  p_industries text[] DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_firebase_uid text;
  v_user users%ROWTYPE;
  v_company_id uuid;
  v_code text;
  v_owner_role_id uuid;
  v_attempts int := 0;
BEGIN
  -- Caller identity from JWT ONLY (spec §6.1): sub = Firebase UID
  v_firebase_uid := nullif(current_setting('request.jwt.claims', true)::jsonb->>'sub', '');
  IF v_firebase_uid IS NULL THEN
    RAISE EXCEPTION 'NO_JWT' USING ERRCODE = 'P0001';
  END IF;
  SELECT * INTO v_user FROM users WHERE firebase_uid = v_firebase_uid LIMIT 1;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'NO_USER_ROW' USING ERRCODE = 'P0002';  -- client retries after sync-user
  END IF;

  -- Idempotency: caller already owns a company → return it with its REAL code (kills R3)
  SELECT id INTO v_company_id FROM companies
   WHERE account_holder_id = v_user.id::text AND deleted_at IS NULL LIMIT 1;
  IF v_company_id IS NOT NULL THEN
    SELECT company_code INTO v_code FROM companies WHERE id = v_company_id;
    RETURN jsonb_build_object('company_id', v_company_id, 'company_code', v_code, 'already_existed', true);
  END IF;

  -- Server-side unique code: 8 chars, I/O/0/1 excluded (spec-pinned scheme)
  LOOP
    v_attempts := v_attempts + 1;
    v_code := (SELECT string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                 (floor(random()*32))::int + 1, 1), '') FROM generate_series(1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM companies WHERE upper(company_code) = v_code);
    IF v_attempts > 20 THEN RAISE EXCEPTION 'CODE_GENERATION_EXHAUSTED'; END IF;
  END LOOP;

  INSERT INTO companies (name, email, phone, address, industries, company_code,
    admin_ids, seated_employee_ids, account_holder_id,
    subscription_status, subscription_plan, trial_start_date, trial_end_date, max_seats,
    created_at, updated_at)
  VALUES (p_name, p_email, p_phone, p_address, p_industries, v_code,
    ARRAY[v_user.id::text], ARRAY[v_user.id::text], v_user.id::text,
    'trial', 'trial', now(), now() + interval '30 days', 10, now(), now())
  RETURNING id INTO v_company_id;

  UPDATE users SET company_id = v_company_id, role = 'owner',
    is_company_admin = true, user_type = 'company', updated_at = now()
  WHERE id = v_user.id;

  SELECT id INTO v_owner_role_id FROM roles WHERE name = 'Owner' LIMIT 1;
  IF v_owner_role_id IS NOT NULL THEN
    INSERT INTO user_roles (user_id, role_id) VALUES (v_user.id, v_owner_role_id)
    ON CONFLICT (user_id) DO UPDATE SET role_id = EXCLUDED.role_id;
  END IF;

  PERFORM initialize_company_defaults(v_company_id);

  RETURN jsonb_build_object('company_id', v_company_id, 'company_code', v_code, 'already_existed', false);
END $$;

REVOKE ALL ON FUNCTION public.create_company_for_owner FROM anon;
GRANT EXECUTE ON FUNCTION public.create_company_for_owner TO authenticated;
```

> Before applying: verify `user_roles.user_id` type and the `users.id::text` casts against live schema (`list_tables` verbose) — the audit found `companies.admin_ids`/`account_holder_id` are `text`/`text[]`, `user_roles` has UNIQUE(user_id). Verify `initialize_company_defaults` signature. Adjust casts to match reality, not this draft.

**Step 2 — Test via rolled-back transaction as a simulated user** (memory: `supabase-rls-trigger-safe-test`): BEGIN; `set_config('request.jwt.claims', '{"sub":"<maverick-owner-firebase-uid>"}', true)`; call the RPC twice (idempotency: second call returns `already_existed=true` + same code); verify users/user_roles rows; ROLLBACK. Also test NO_USER_ROW (fake sub) and code uniqueness (insert a colliding code first).
**Step 3 — Apply** via `apply_migration`. Re-run the rolled-back test against the applied function.

### Task 1.2: Amend `join_user_to_company`

**Files:** Migration `join_user_to_company_amendment` — fetch current definition first (`SELECT pg_get_functiondef('public.join_user_to_company'::regproc)`), modify, re-create.
**Changes (spec §6.2):** (a) set `user_type='employee'`, `is_company_admin=false` on the joining user inside the function; (b) insert per-admin rail notifications via `create_notification_if_new` using the EXACT dedupe-key scheme from `OPS-Web/src/app/api/auth/join-company/route.ts:307-372` — read that file first and replicate its key construction verbatim.
**Test:** rolled-back transaction — join a test user to Maverick, assert user fields + notification rows + dedupe (second call inserts no duplicate rail row). ROLLBACK.

### Task 1.3: OPS-Web switches

**Files:** Modify `OPS-Web/src/app/api/setup/progress/route.ts` (company step → RPC call, delete bespoke insert + its `generateCompanyCode`), `OPS-Web/src/app/api/auth/join-company/route.ts` (delete rail fan-out lines ~307-372, KEEP OneSignal push fan-out), `OPS-Web/src/app/api/auth/sync-user/route.ts` (set `firebase_uid` from the verified `idToken` on row creation).
**Steps:** Read each route fully → edit → `npm run build` (or repo's typecheck script) in OPS-Web → commit each route change atomically on OPS-Web main: `feat(api): create companies via shared create_company_for_owner RPC`, `fix(api): move join rail notifications into RPC (keep push)`, `fix(api): set firebase_uid at sync-user creation`.
**Verify:** web owner-signup happy path via OPS-Web dev server if runnable; otherwise typecheck + a rolled-back RPC smoke test with a web-created JWT shape.

### Task 1.4: P1 checkpoint
Bible note (defer full rewrite to P8), commit any test artifacts. **§6.5 row repairs: DONE 2026-06-11 in-session (verified).**

---

## Phase P2 — iOS skeleton (TDD)

> **Branch first:** `git checkout -b feat/onboarding-rebuild` (from main).

### Task 2.1: `OnboardingFlowStep` + back map (pure logic, test-first)

**Skills:** `superpowers:test-driven-development`.
**Files:** Create `OPS/Onboarding/Flow/OnboardingFlowStep.swift`, `OPSTests/OnboardingFlowStepTests.swift`.

**Step 1 — failing tests** (write ALL before implementation):

```swift
final class OnboardingFlowStepTests: XCTestCase {
    func testBackEdges() {
        XCTAssertEqual(OnboardingFlowStep.login.backEdge(context: .preAuth), .welcome)
        XCTAssertEqual(OnboardingFlowStep.rolePick.backEdge(context: .preAuth), .welcome)
        XCTAssertNil(OnboardingFlowStep.rolePick.backEdge(context: .postAuth))      // SIGN OUT escape
        XCTAssertEqual(OnboardingFlowStep.createAccount.backEdge(context: .preAuth), .rolePick)
        XCTAssertEqual(OnboardingFlowStep.companyName.backEdge(context: .postAuth), .rolePick) // role uncommitted
        XCTAssertNil(OnboardingFlowStep.crewCode.backEdge(context: .postAuth))      // company committed
        XCTAssertEqual(OnboardingFlowStep.codeEntry(provenance: .zeroInvites).backEdge(context: .postAuth), .rolePick)
        XCTAssertEqual(OnboardingFlowStep.codeEntry(provenance: .fromPicker).backEdge(context: .postAuth), .invitePicker)
        XCTAssertEqual(OnboardingFlowStep.confirmCompany(source: .picker).backEdge(context: .postAuth), .invitePicker)
        XCTAssertEqual(OnboardingFlowStep.confirmCompany(source: .codeEntry).backEdge(context: .postAuth), .codeEntry(provenance: .zeroInvites))
        XCTAssertNil(OnboardingFlowStep.profile.backEdge(context: .postAuth))        // join committed
        XCTAssertEqual(OnboardingFlowStep.emergencyContact.backEdge(context: .postAuth), .profile)
        XCTAssertNil(OnboardingFlowStep.completionGate.backEdge(context: .postAuth))
    }
    func testResumeDerivation() { // spec §5.3 table — server state is authority
        XCTAssertEqual(OnboardingResume.derive(.init(hasCompany: false, role: nil, userType: nil, profileComplete: false, webComplete: false)), .rolePick)
        XCTAssertEqual(OnboardingResume.derive(.init(hasCompany: false, role: nil, userType: "company", profileComplete: false, webComplete: false)), .rolePick)
        XCTAssertEqual(OnboardingResume.derive(.init(hasCompany: true, role: "owner", userType: "company", profileComplete: false, webComplete: false)), .crewCode)
        XCTAssertEqual(OnboardingResume.derive(.init(hasCompany: true, role: "crew", userType: "employee", profileComplete: false, webComplete: false)), .profile)
        XCTAssertEqual(OnboardingResume.derive(.init(hasCompany: true, role: "crew", userType: "employee", profileComplete: true, webComplete: false)), .completionGate)
        XCTAssertEqual(OnboardingResume.derive(.init(hasCompany: true, role: "owner", userType: "company", profileComplete: true, webComplete: true)), .completionGate) // silent auto-complete
    }
}
```

**Step 2:** `xcodebuild build-for-testing` → expect compile failure (types missing). **Step 3:** implement `OnboardingFlowStep` (enum with associated provenance values, `backEdge(context:)`, Codable for persistence) + `OnboardingResume.derive`. **Step 4:** run the two test classes on the simulator destination → PASS. **Step 5:** commit `feat(onboarding): flow step machine with data-driven back map and resume derivation`.

### Task 2.2: `OnboardingFlowState` v4 persistence + migration

**Files:** Create `OPS/Onboarding/State/OnboardingFlowState.swift`, `OPSTests/OnboardingFlowStateTests.swift`. (Old `OnboardingState.swift` untouched until P7 — legacy flow still uses it.)
**TDD:** round-trip encode/decode of {collected data, step, provenance} under key `onboarding_state_v4`; migration test: seed legacy `onboarding_state_v3` payload → migrate → v4 populated, v3 + `ab_test_flow_step` keys removed; corrupt v3 → discarded cleanly. Commit `feat(onboarding): unified v4 flow state with v3 migration`.

### Task 2.3: Gateway shell + ContentView seam

**Files:** Create `OPS/Onboarding/Gateway/OnboardingGateway.swift` (hosts Welcome/Login/Flow per §4.1, placeholder screens for now). Modify `OPS/Utilities/FeatureFlags.swift` (+`useRebuiltOnboarding`, default `false`). Modify `OPS/ContentView.swift`: behind the flag, replace the `showABTestOnboarding`/`showExistingLogin`/`onboardingManagerInstance` branches with `OnboardingGateway`; route `authenticated && shouldShowOnboarding` into the gateway; keep the legacy path byte-identical when the flag is false. Signal-driven splash (replace the 2.5s timer) goes in the NEW branch only.
**Verify:** device build green; flag-off behavior unchanged (manual: launch sim, legacy flow appears). Commit `feat(onboarding): gateway shell behind useRebuiltOnboarding flag`.

### Task 2.4: Manager hardening (test-first, mocked service)

**Files:** Modify `OPS/Onboarding/Manager/OnboardingManager.swift` + new `OPSTests/OnboardingManagerRebuildTests.swift` (protocol-mock the service/repos).
**Changes:** `createCompanyViaRPC()` calling `create_company_for_owner` (handles `NO_USER_ROW` → re-run sync-user → single retry; surfaces typed errors); `joinCompanyFromOnboarding` — delete the post-RPC `try?` writes (now in RPC) and the client rail-notification insert at `:1145` (keep `OneSignalService.notifyTeamJoin` push); tutorial flag key → `has_completed_tutorial` (`:1732`); delete `user_password` write (`:664`); awaited `backfillFirebaseUID` with retry + add `firebase_uid` to `SupabaseUserDTO` (`CoreEntityDTOs.swift`); completion queue: `markOnboardingCompleteOrQueue()` persisting `onboarding_completion_pending` drained by SyncEngine, `shouldShowOnboarding` treats pending as complete.
**Caution:** `OnboardingManager` is shared with the legacy flow until P7 — additive methods + surgical fixes only; legacy paths must still compile and behave. Commit per logical change (≥4 commits).

---

## Phase P3 — Welcome, Login, Role pick, Create account

> **EVERY task in P3-P5: spec §12 gate first** — read the four design-system sources, invoke `mobile-ux-design` before screen design, `ops-copywriter` for ALL strings, `animation-architect`+`ios-animations` for entrances/transitions. Snapshot-test each screen (light/dark × Reduce Motion on/off) via the ImageRenderer harness. `audit-design-system` before the phase-closing commit.

### Task 3.1: Shared components

**Files:** Create `OPS/Onboarding/Components/OPSOnboardingField.swift` (48pt, fill `Color.white.opacity(0.04)`, radius `OPSStyle.Layout.cornerRadius`, inline error state per MOBILE.md §9), `OnboardingStepHeader.swift` (renders Back ONLY when `step.backEdge(context:) != nil`, label = previous screen name; SIGN OUT slot), `OnboardingPrimaryCTA.swift` (52pt, `OPSStyle.Colors.primaryAccent` fill — accent is primary-CTA-only; disabled = opacity, not gray; medium-impact haptic on tap), `OnboardingCodeDisplay.swift` (JetBrains Mono `OPSStyle.Typography.caption`-family bracketed code, used by BOTH share and entry).
**Tokens:** as listed in header. Snapshot tests for each. Commit per component or one `feat(onboarding): rebuilt shared components to design spec`.

### Task 3.2: Welcome (S1)

**Files:** Create `OPS/Onboarding/Screens/WelcomeStepView.swift` (fresh name — never reuse dead names).
**Spec:** §4.2 S1 — title in `OPSStyle.Typography.pageTitle` (Cake Mono), static-first hero, `GET STARTED` (accent CTA) → rolePick, `SIGN IN` (ghost, `buttonBorder` stroke) → login, version footer in `.caption`. Light arrival haptic. Entrance: 150ms crossfade under Reduce Motion, OPS curve otherwise (`OPSStyle.Animation.standard`).
**Verify:** snapshots; build. Commit.

### Task 3.3: Login

**Files:** Create `OPS/Onboarding/Screens/LoginStepView.swift`; reuse `ForgotPasswordView`, `GoogleSignInManager`/`AppleSignInManager` via DataController login paths.
**Spec:** §4.2 Login — outcomes wired to gateway callbacks: complete → existing `pendingReturningLogin` arming (preserve ContentView contract `onLoginInitiated`/`onLoginAbandoned`); incomplete → `OnboardingResume.derive`; social-new-identity → sync-user → rolePick (skip S3). Inline field errors. Title via ops-copywriter (NOT "Enter your credentials" — banned).
**Tests:** unit-test the outcome routing with mocked DataController results. Snapshots. Commit.

### Task 3.4: Role pick (S2) + Create account (S3)

**Files:** Create `OPS/Onboarding/Screens/RolePickStepView.swift` (two tappable cards `RUN A CREW`/`JOIN A CREW`, one tap advances, `panelRadius` cards, retain existing role-benefit copy as the tonal benchmark, light selection haptic), `CreateAccountStepView.swift`.
**S3 logic (test-first in `OPSTests/CreateAccountLogicTests.swift`):** name-resolution rule — `needsNameEntry(resolved:) == true` whenever first/last empty after ANY auth; email-already-registered → inline error + one-tap SIGN IN handoff (prefilled); social→existing account → sign-in semantics (complete→app / incomplete→derived resume); Apple name cache → Keychain (new tiny `KeychainNameCache`); commit point = S3 submit (Firebase + sync-user, awaited, errors surfaced); password show/hide + inline rule hint. Medium commit haptic on account creation success.
**Close P3:** run `audit-design-system` on the four screens; fix violations; commit `feat(onboarding): welcome, login, role pick, create account (rebuilt)`.

---

## Phase P4 — Owner path

### Task 4.1: Company name (S4o)
**Files:** Create `OPS/Onboarding/Screens/CompanyNameStepView.swift`. Single `OPSOnboardingField` + optional primary-trade chips (`chipRadius` 4, single-select, sub-44pt chip exception per MOBILE.md §4.3) → `companies.industries`. Back → rolePick (per back map). SIGN OUT in header. Calls `createCompanyViaRPC` (Task 2.4); typed-error surfacing inline; medium commit haptic on success.

### Task 4.2: Crew code (S5o)
**Files:** Create `OPS/Onboarding/Screens/CrewCodeStepView.swift` using `OnboardingCodeDisplay` (mono/bracketed — identical to entry screen), COPY w/ success haptic, INVITE CREW (reuse existing invite sheet), `You'll find this code in Settings anytime.`, CTA `ENTER OPS →`. No back-edge. **No shadows** — hairline + glass only. Displays the RPC-returned code (DB truth).

### Task 4.3: Completion gate
**Files:** Create `OPS/Onboarding/Screens/CompletionGateView.swift` — clone `WorkspacePreloadGate`'s structure (`OPS/Onboarding/Screens/WorkspacePreloadGate.swift` is the explicit template: Reduce Motion sweep, OPS curve, reserved layout, watchdog). Wire `markOnboardingCompleteOrQueue` (Task 2.4): ACK ≤8s → success haptic → `onComplete`; failure/timeout → visible "will finish syncing" queued state → enter app. Unit-test gate logic with mocked service (success / timeout→queue / queue-drain idempotency).
**Close P4:** owner happy path on simulator (account → company → code → app), kill-at-S4o resume test, snapshots, `audit-design-system`, commit.

---

## Phase P5 — Crew path + cutover

### Task 5.1: Invite check + picker
**Files:** Create `OPS/Onboarding/Screens/InviteCheckStepView.swift` (auto transition; failure → visible retry state `CHECK AGAIN` / `ENTER CODE INSTEAD` — R13: decode failure ≠ zero invites, fire `onboarding_invite_check_failed`), `InvitePickerStepView.swift` (rebuild of the card list — keep the strong card design, `chipRadius` role tags NOT `Capsule`, Back → rolePick, `ENTER A DIFFERENT CODE` → codeEntry(.fromPicker)).

### Task 5.2: Code entry + confirm
**Files:** Create `CodeEntryStepView.swift` (bracket-mono input via `OnboardingCodeDisplay` style; no client format rejection — legacy `PREFIX-XXXXXX` codes must pass; Back per provenance; keep the benchmark copy register: "Enter the code your boss gave you."), `ConfirmCompanyStepView.swift` (headline intent `CONFIRM YOUR CREW` — "WELCOME TO" banned; immediate medium haptic on JOIN tap, success/error after RPC resolves; sparse-data reduced layout).

### Task 5.3: Profile + emergency contact
**Files:** Create `ProfileStepView.swift` (first/last prefilled from S3, phone; name+phone required, photo optional; avatar upload with progress + surfaced failure + retry — never silent; no back-edge, SIGN OUT header), `EmergencyContactStepView.swift` (visible SKIP; relationship chips `chipRadius`; FINISH = medium commit haptic; success notification fires at gate).

### Task 5.4: Cutover
**Steps:** Full manual pass (spec §9 list, all 9 scenarios incl. kill/resume, sign-out/resume, offline gate, role change via Back). Run `custom-skills:wizard-audit` against the complete flow; fix findings. Run full test suite vs stashed-baseline comparison (memory: env-launch flakiness). Flip `FeatureFlags.useRebuiltOnboarding` default → `true`. Device build. Commit `feat(onboarding): cut over to rebuilt express onboarding`.

---

## Phase P6 — Hardening sweep

**Files:** `OPS/OPSApp.swift` (one-time launch cleanup of `user_password`, `ab_test_flow_step`, `onboarding_state_v3`, `resume_onboarding`, `pre_signup_tutorial_completed`, `onboarding_variant` — note `OPSApp.swift:557` already lists some at logout; this is the launch sweep), analytics events (§8 names: `onboarding_step_viewed/completed`, `onboarding_completed`, `onboarding_abandoned`, `onboarding_completion_queued`, `onboarding_invite_check_failed`) via `AnalyticsService`, preserve Google Ads conversion calls (`AnalyticsManager.trackCreateProject`-style account/company-created hooks). Verify every §6.3 row is landed (checklist commit). `DeferredProfilePrompter` reference check → delete if orphaned.

---

## Phase P7 — Deletions

**Order (transitive, to fixpoint; grep zero references before EACH removal; device build after EACH bullet):**
1. Flip-flag plumbing: remove `useRebuiltOnboarding` checks (rebuilt path becomes the only path), remove legacy branches from `ContentView.swift` incl. the 2.5s timer + triad state, remove `variantManager` plumbing from `OPSApp.swift:36/109`.
2. `OPS/Views/`: `LandingView.swift`, `LoginView.swift`, `SplashScreen.swift`, `Debug/OnboardingPreviewView.swift`.
3. `OPS/Onboarding/ABTest/` (2 files), `Container/` (1), `Coordinators/` (1), `ViewModels/` (1), `OnboardingCopy.swift`.
4. `OPS/Onboarding/Screens/`: the 17 legacy (Appendix A list — keep `WorkspacePreloadGate.swift`; `InvitePickerScreen.swift` dies here, replacement shipped in P5).
5. `OPS/Onboarding/Views/` — entire tree (31 files).
6. `OPS/Onboarding/Components/` — all 12 legacy (replacements live in the new `Components/`); re-grep `TypewriterText` (orphans only after `UserTypeSelectionContent` goes).
7. Old `State/OnboardingState.swift` once nothing references it.
Full suite + snapshots + manual smoke after the sweep. Commits per bullet: `refactor(onboarding): delete <set> (dead post-rebuild)`.

---

## Phase P8 — Docs

Update `ops-software-bible` onboarding + data-model sections (new RPC contracts, flow, completion semantics; same-session mandate). Archive root-level `ONBOARDING_*.md` + `ONBOARDING PLAN/` artifacts as superseded (move under `Archives/`). Update `OPS-ICON-SET-BRIEF`-adjacent docs only if touched. Commit `docs(bible): onboarding rebuild — flow, RPCs, completion contract`.

---

## Execution notes

- **Worktree:** safe to execute in-place on `feat/onboarding-rebuild` (this session owns the repo); parallel sessions must not touch `OPS/Onboarding/**`, `ContentView.swift`, `OPSApp.swift` until P7 lands.
- **Secrets:** if a worktree IS used, copy `OPS/Utilities/Secrets.xcconfig` in before tests.
- **Copy freeze:** ops-copywriter pass happens per-screen during P3-P5; a final whole-flow copy read (one pass, every string in situ) precedes the P5 cutover commit.
- **CRLF:** new files LF; if editing legacy CRLF files (check before editing `ContentView.swift`), restore original endings before commit (memory: CRLF churn).
