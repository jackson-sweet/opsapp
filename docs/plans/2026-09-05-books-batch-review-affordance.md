# Books Batch Review Affordance Repair

**Bug:** `299b588b-eea3-4527-9bcb-1d088efb9ac6`
**Scope:** iOS Books expense ledger only; no schema, API, or release changes.

## Root cause

The Books ledger still translates every `submitted` expense line into an urgent `NEEDS OK` filter and row pill. That predates the batch console. The current database contract puts submitted expenses into batches, and the console performs approval at the batch, person, or approve-all level.

The captured report shows the contradiction directly: `NEEDS OK · 14` and repeated line pills sit beside `BATCHES · 4 TO REVIEW`. Live data confirms nine of those fourteen submitted lines are still in open batches and are not review-ready.

## Presentation decision

Four bounded structures were checked against the batch workflow:

1. Keep `NEEDS OK` and route the filter to batches — rejected because a filter must not become navigation and the line count remains false.
2. Add per-line approval — rejected because it breaks the server-authoritative batch workflow.
3. Repeat each batch's review state on every line — rejected because it duplicates the console and keeps the ledger noisy.
4. Remove the line-level review filter, reuse the existing envelope vocabulary (`FILLING` / `WITH OFFICE`) on submitted rows, and keep `BATCHES · n TO REVIEW` as the sole approval cue — selected.

Missing receipts remain rose and continue to override the neutral envelope state. The filtered empty state will describe receipt completeness, not approval.

## Implementation and proof

1. Add regression tests proving the expense filter set is `ALL · NO RECEIPT`, submitted lines use envelope-phase language, and missing receipts still win.
2. Run the focused test first and capture the expected failure.
3. Make the smallest production and snapshot-harness changes.
4. Run the focused tests, snapshot harness, generic iOS build, diff/design audit, and independent review.
5. Commit atomically. Integrate into local `main` only if the primary checkout is clean and unchanged; otherwise retain the verified branch and durable assignment with exact resume evidence.
