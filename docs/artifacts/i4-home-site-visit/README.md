# Workstream I4 — Home & site-visit cluster (10 bugs)

Verification artifacts for the iOS Home dashboard + site-visit capture bug fixes.
Branch: `claude/gracious-turing-347d96`. Device build **SUCCEEDED**; **55/55** I4 tests passed.

## Snapshot proof (UIHostingController + drawHierarchy, not ImageRenderer)

| File | Proves |
|------|--------|
| `home_billable_expanded_all_jobs.png` | Bug 5137414e — the BILLABLE THIS WEEK strip expands to show **all** jobs. Four jobs in one section render (972 Lyall St, 3040 Cedar Hill Rd, 88 King St W, **1075 Pandora Ave**); the 4th is the row the old `prefix(3)` cap hid. |
| `home_billable_no_data_emdash.png` | Bug 588b3e19 — jobs with no attached value show **"—"** in the header total and each row's amount slot, never a lying "$0". Count still reflects the 3 real jobs. |
| `home_needs_tasks_strip.png` | Bug 465332fa — the invisible-helpfulness NEEDS TASKS nudge (appears only when accepted/in-progress projects have zero tasks; taps into the review flow; clears itself when handled). |

## Non-snapshot evidence

- **Bug a2af6e8a (lead-conversion notification):** DB `AFTER` trigger verified via a rolled-back simulation against the reporter's company — a `converted_to_project` disposition insert fanned a `lead_converted` notification to the owner with the correct body / action_url / project_id. iOS consumption + routing covered by unit build.
- **Bug bbc2d228 (project name from address):** `ProjectAutoNamerTests` (16 cases) + the DB regex parity check (11 address samples matched the Swift mirror exactly).
- **Bug 70087050 (report-a-bug):** `BugReportPresenterLatchTests` (5 cases) covering the presenter-latch truth table.
- **Bug bbcd58da (task review):** already fixed in-branch by `8da052b8` — all four count sources route through `TaskReviewQuery`. Ships next release.
