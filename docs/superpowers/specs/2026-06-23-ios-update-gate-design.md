# iOS Update Gate — Design

**Date:** 2026-06-23
**Status:** Approved (direction), ready for implementation plan
**Surfaces:** iOS (`ops-ios`), Web admin (`OPS-Web`), Supabase (`app_messages`)

## Problem

When a blocker bug ships, we need to **force every affected user to update before they can keep using the app** — and do it the moment the fixed build is live on the App Store. Two failures today:

1. **Users don't notice updates exist.** They keep running the buggy build until told directly.
2. **The existing app-message system has no version awareness.** A force-update message walls *everyone* indefinitely, including users who already updated, and must be manually toggled off. It cannot express "block only versions below X."

The app-message mechanism already exists end-to-end (iOS overlay + launch check + web admin + Supabase). This design makes it **version-aware** and **self-resolving**, and adds **automatic update detection**.

## Existing mechanism (baseline)

- **iOS:** `AppMessageService` fetches the active row from `app_messages`; `AppMessageView` renders a full-screen overlay; `ContentView` checks once on cold launch (post-auth) and blocks the whole app for non-dismissable messages.
- **Web:** `/admin/app-messages` CRUD; one message active at a time.
- **DB:** `public.app_messages`, reconciled 2026-06-23 to match the clients and gain `minimum_version`, `maximum_version`, `platform`, `dismissable`, `app_store_url`, `target_user_types[]`, `start_date`, `end_date`.

## Design — "Update Gate"

### 1. Version-aware applicability (the spine)

A message **applies** to a given install only if ALL hold:

- `active == true`
- now ∈ [`start_date`, `end_date`) (null bound = open)
- `platform` is null or matches `"ios"`
- installed `CFBundleShortVersionString` ∈ [`minimum_version`, `maximum_version`)
  - bounds null = open; comparison is **semantic**, not lexical
- user role ∈ `target_user_types` (null/empty = all roles) — only enforced once a role is known (post-auth)

**Self-resolving force-update:** publish `mandatory_update`, `dismissable=false`, `maximum_version="3.1.0"` (the build with the fix), `app_store_url`. Everyone **below** 3.1.0 is in range and hard-walled; the instant a user updates to 3.1.0+ they fall out of the range (`installed >= maximum_version`) and are unblocked — no admin cleanup. Leaving **both** bounds null hard-blocks every version (a deliberate "block all" escape hatch). `minimum_version` is the optional inclusive lower bound for narrow targeting (e.g. a notice only for a specific version band).

**Semantic comparison:** component-wise numeric compare (split on `.`, pad missing components with 0), so `"3.10.0" > "3.9.0"` and `"3.1" == "3.1.0"` (a lexical or naive compare gets the double-digit case wrong). Encapsulated in a pure, unit-tested function.

### 2. Pure evaluator unit

`AppMessageGate` (new): given `(message, installedVersion, platform, now, userRole?)` → `Bool` applies, plus a priority rank. No I/O, fully unit-testable (TDD). Priority order for picking among applicable messages: `mandatory_update > optional_update > maintenance > announcement > info`, then newest `created_at`.

### 3. Automatic update detection (auto-nudge — APPROVED)

`AppStoreVersionService` (new) queries Apple's public **iTunes Lookup API**
`https://itunes.apple.com/lookup?bundleId=<bundleId>&country=<storefront>` → `results[0].version` (live App Store version) and `results[0].trackId` (→ `https://apps.apple.com/app/id<trackId>`).

Uses:
- If installed `< storeVersion` and **no** published message already covers it, synthesize a **dismissable `optional_update` nudge** ("Update available") pointing at the App Store URL. Solves "users don't notice updates" at the source — zero admin action.
- Validates that "UPDATE NOW" actually has a newer build to offer.

Precedence: a published **mandatory** message always wins; else a published message; else the synthetic nudge. Free (Apple public endpoint, no cost). Network-failure → no nudge (silent).

### 4. Lifecycle — check on launch AND on foreground (faster reach)

- Today: cold launch only (`.task`, runs once).
- Add: re-evaluate when the app returns to foreground (`scenePhase` → `.active`), **throttled** (min ~60s between network checks) so a freshly-published wall reaches a user within seconds of reopening, not on their next full relaunch.

### 5. Pre-auth kill-switch (APPROVED)

The **blocking** (version-floor / mandatory) evaluation runs at the app **root, before sign-in**, so it reaches users even when the blocker bug breaks login/sync. The optional nudge and role-targeted messages stay post-auth (role unknown pre-auth → role filter treated as "applies to all" for the blocking floor only).

- Requires the message row to be readable **unauthenticated**. Add an anon `SELECT` policy on `app_messages` (content is non-sensitive broadcast/update copy). Replaces the current authenticated-only SELECT policy with public-read.
- Root gating: a root gate evaluates the floor first; if a non-dismissable message applies, render `AppMessageView` over everything and short-circuit the login/main routing. Otherwise route normally.

### 6. Fail-open & offline (safety)

Every fetch (Supabase + iTunes) **fails open**: on error/timeout/offline the app proceeds unblocked. A wall that bricks the app during a backend outage is worse than the bug it guards. Keep current `nil`-on-error behavior; never block on a failed fetch.

### 7. Force is rare and admin-set

The `minimum_version` floor is set by an admin and bumped **only for blocker bugs**. Routine "please update" is handled by the auto-nudge (§3). The hard wall stays rare and trusted — we never force-update on every release.

### 8. Web admin additions

`/admin/app-messages` form gains:
- `minimum_version`, `maximum_version` (version text inputs, validated `x.y.z`)
- `platform` (iOS / All)
- `start_date` / `end_date` (schedule + auto-expire pickers)
- A one-click **"Force update"** preset: sets `mandatory_update` + `dismissable=false` + prompts for `minimum_version` + `app_store_url`, with an inline explainer ("users below X.Y.Z are hard-blocked until they update"). Reuses the existing non-dismissable warning dialog.

`AppMessage` TypeScript type + `createAppMessage`/`updateAppMessage` already insert/update wholesale, so adding the fields to the type + form is sufficient; add light client validation.

### 9. Copy

All user-facing strings (titles, bodies, button labels, the `[ ACCESS SUSPENDED ]` state, the auto-nudge default copy) go through **ops-copywriter** in OPS voice — terse, tactical, no exclamation points.

## Components

| Unit | Responsibility | Depends on |
|------|----------------|------------|
| `AppMessageGate` (iOS, new) | Pure applicability + priority decision | nothing (pure) — TDD |
| `AppStoreVersionService` (iOS, new) | iTunes Lookup → live store version + URL | URLSession |
| `AppMessageService` (iOS, edit) | Fetch + apply gate + synthesize nudge + pick winner | Supabase, Gate, StoreVersionService |
| `ContentView` / root gate (iOS, edit) | Pre-auth floor gate + foreground re-check + render | AppMessageService |
| `AppMessageView` (iOS, mostly as-is) | Render states (already handles all four) | OPSStyle |
| Web `app-messages` form + type + queries | Author version/platform/schedule + force preset | Supabase |
| Migration: anon SELECT policy | Pre-auth read of `app_messages` | — |

## Error handling

- Supabase fetch fails → no message (fail open).
- iTunes lookup fails → no auto-nudge (fail open).
- Malformed version strings → treated as "does not constrain" (fail open), logged.
- Offline → app proceeds; force-wall cannot be shown (acceptable — can't update offline anyway).

## Testing

- `AppMessageGate`: exhaustive unit tests — below/at/above floor, null bounds, `3.10.0` vs `3.9.0`, platform mismatch, start/end window edges, role filter, priority ordering. TDD.
- `AppStoreVersionService`: parse iTunes Lookup JSON; older/newer/equal store version.
- Integration: pre-auth blocking path; foreground re-check throttle; fail-open on injected errors.
- `xcodebuild` device build green; `build-for-testing` + `test` on simulator.

## Out of scope

- Android (schema is platform-aware via `platform`; client work deferred until/if Android exists).
- In-app update download (iOS has no equivalent; we deep-link to the App Store).
