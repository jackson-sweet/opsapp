# Onboarding variants + experiment framework (items 7d8327b2 + 07967be2)

**Status:** Spec'd for a dedicated focused sub-session (the largest, coupled build; fully un-gated but multi-phase). Foundation verified live; the experiment framework + both variants are net-new.

## Foundation (verified live)

The 2026-06-11 onboarding **rebuild has shipped**: `OnboardingGateway`, `OnboardingFlowCoordinator`, `OnboardingFlowStep`, `OnboardingFlowState` all exist; `FeatureFlags.useRebuiltOnboarding` defaults **true** and `ContentView` routes on it. The single "express" (fastest-into-the-app) flow is live. The legacy A/B/C machinery (`OnboardingABTestCoordinator`, `OnboardingVariantManager` — Firebase Remote Config A/B/C) survives **only as the `else` fallback** and is slated for deletion at rebuild P7. Per the rebuild spec §2.2 + §11, the two variants and a *real* experiment framework were deferred to be built **together, now**:
- `7d8327b2` — OPS-workflow **animation** variant (replace the old SF-Symbol carousel/`AnimatedWalkthroughView` with real product/field motion per animation-studio standards).
- `07967be2` — **interactive tutorial** variant (guided hands-on walkthrough of core workflows after signup).

There is an existing in-app tutorial engine (`OPS/Tutorial/` + `OPS/Tutorial/V2/`: `TutorialStateManagerV2`, `TutorialFlowViewV2`, `TutorialDataV2`, `TutorialPhaseV2`, `Tutorial/Utilities/TutorialAnimations`, `TutorialHaptics`) — evaluate it as the reusable guided-walkthrough framework for the interactive-tutorial variant rather than building one from scratch.

## What to build

### 1. Experiment framework (net-new, on the rebuilt flow)
- A per-user variant assignment that is **remote-controlled** (Firebase Remote Config, like the old `OnboardingVariantManager` but wired into `OnboardingGateway`/`OnboardingFlowCoordinator`, **not** the soon-deleted legacy machinery), stable per user, cached, with an override for QA.
- Variants: `express` (control) | `animation` | `interactive`. The gateway selects which experience to inject (a pre-flow/explainer animation, or a post-signup interactive tutorial) around the express flow.
- **Per-step funnel analytics** (the rebuild's §8 events are the baseline): `onboarding_step_viewed`/`_completed`, `onboarding_completed` (variant, duration, step count), `onboarding_abandoned`; plus `onboarding_variant_assigned`. Tables: `onboarding_events` / `ab_events`. So each variant is measured against express.

### 2. Animation variant (7d8327b2)
A short OPS-workflow motion sequence (lead → schedule → crew → done, real product/field motion — not SF-Symbol icons), slotted at a defined seam (e.g. an explainer between Welcome and the flow, or post-completion). Per the rebuild §4.3 + §12 standard: Cake Mono titles, single OPS easing curve, **zero spring**, every entrance/loop gated on `accessibilityReduceMotion` (150ms crossfade fallback), haptics on beats, copy via `ops-copywriter`.

### 3. Interactive-tutorial variant (07967be2)
A guided, hands-on walkthrough of the core workflows immediately after signup (reuse the `Tutorial/V2` engine where it fits). Per-step analytics; honors the same motion/skill standard; gated so it only runs for users assigned the `interactive` variant.

## Mandatory skill protocol (rebuild spec §12 — non-negotiable, hard gate per Jackson 2026-06-11)
Every UI screen/agent MUST read, in order: `ops-design-system/project/SKILL.md` → `README.md` → `DESIGN.md` → `mobile/MOBILE.md`; iOS tokens from `OPSStyle.swift`. Invoke `mobile-ux-design`, `animation-studio:animation-architect` → `ios-animations` (all motion), `ops-copywriter` (every string), and pass `audit-design-system` before each phase's commit. **Zero hardcoded color/spacing/font/radius** — every value traces to a token. (UI built without the design system has shipped as "cheap replica" in other sessions.)

## Phasing (focused session)
1. Experiment framework (assignment + analytics) wired to `OnboardingGateway`, behind a flag, with the express path as control — ship working.
2. Animation variant (animation-architect → ios-animations).
3. Interactive-tutorial variant (reuse Tutorial/V2).
4. A/B readout + QA (`wizard-audit` against each variant) + bible/design-doc update.

## Risks
- Do NOT build on `OnboardingVariantManager`/`OnboardingABTestCoordinator` (deleted at rebuild P7) — design fresh on the rebuilt flow.
- Coupled: both variants share the framework — build the framework first.
- Multi-session scale — this is the heaviest item; treat as its own initiative (`ONBOARDING REBUILD` follow-up).

Note: the design workflow for this item stalled under concurrent load; this spec is derived from the 2026-06-11 onboarding-rebuild spec (`docs/superpowers/specs/2026-06-11-onboarding-rebuild-design.md` §2.2, §8, §11, §12) + direct recon of the live onboarding + tutorial code.
