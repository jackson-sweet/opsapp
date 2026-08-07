# iOS Bug Batch Continuation Plan

**Goal:** Close the seven 2026-08-06/07 iOS reports locally without changing production data or claiming device/App Store proof.

## Cluster 1 — Project and lead continuity

- Make project-side lead matching company-wide, with same-address and same-client leads ranked as suggestions instead of filtered gates.
- Make the lead conversion sheet treat every server-authorized unlinked project as selectable.
- Add an unapplied server migration in an isolated OPS-Web worktree so explicit human links are authorized without address equality while automatic duplicate protection remains unchanged.
- Trigger a targeted Phase C lead-summary refresh after the Lead Details activity logger durably saves a lead activity. The report screenshot is Lead Details even though its telemetry screen name is `ProjectDetails`.
- Route Activity composer focus through the real outer project scroll view so the editor clears the keyboard.

## Cluster 2 — Expenses

- Sort Books expenses with approved/reimbursed entries first, then newest expense date, with deterministic timestamp/id fallbacks.
- Put the resolved submitter name directly in each batch row and resolve names from the synced `User` roster before falling back to legacy `TeamMember` rows.

## Cluster 3 — Field surfaces

- Add an edit-and-save path for submitted site-visit note/transcript artifacts that preserves the same artifact identity and marks it for sync.
- Reduce the collapsed Home billable rollup to one compact scan row so it stops consuming the map's control/content band; preserve the complete expanded list.

## Proof boundary

- Add focused pure/unit regression tests before implementation where practical.
- Run the focused tests once per cluster, Swift parse/static checks across touched iOS files, and the relevant web unit/integration tests.
- Do not run repeated full Xcode builds. Run at most one combined build only if source parsing and focused tests leave a material integration question.
- Commit coherent clusters atomically. Do not push, deploy, apply migrations, change bug-report rows, or mutate customer data.
