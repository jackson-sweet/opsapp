# Lead waiting-state correction — implementation plan

**Bug:** `e18d14bd-a628-43f5-858b-51e27ec0760e`

**Outcome:** Any non-new, non-date-priority lead showing `THEIR MOVE` can be
explicitly returned to `YOUR MOVE` from every chase-strip host. The state stays
server-authoritative and later real correspondence or a later `HANDLED` action
supersedes the manual correction.

## Root cause

The chase state is derived from correspondence plus the one-way `handled_at`
override. `handled_at` can move an inbound lead from `YOUR MOVE` to
`THEIR MOVE`, but there is no opposite event. Clearing it would only repair a
previously handled inbound lead; it cannot represent `YOUR MOVE` for a lead
whose last touch was outbound or whose correspondence direction is absent.

## State contract

Add one nullable event timestamp:

- Supabase: `public.opportunities.operator_action_required_at timestamptz null`
- iOS: `Opportunity.operatorActionRequiredAt: Date?`

For non-new leads, compare the newest signals:

- `YOUR MOVE`: `max(last_inbound_at, operator_action_required_at)`
- `THEIR MOVE`: `max(last_outbound_at, handled_at)`

The newer side wins. Preserve the legacy `last_message_direction` fallback when
neither side has a usable timestamp. At an exact timestamp tie, a manual signal
beats correspondence and the explicit operator-action correction beats
`handled_at`. `OVERDUE` and `DUE TODAY` continue to outrank ownership, and
`NEW LEAD` continues to render `FRESH`.

Both manual ownership events are server-stamped. The clients send a non-null
sentinel, and a database trigger replaces it with the server's current time
before returning the authoritative opportunity row. This prevents device clock
skew from corrupting newest-event ordering. Setting `YOUR MOVE` does not rewrite
correspondence facts or erase `handled_at`.

The quick `TEXT` and `EMAIL` actions are outbound ownership events even though
they do not create correspondence records, so a successful quick touch also
advances `handled_at` to `THEIR MOVE`. `UNDO` removes the activity and restores
`YOUR MOVE` in one database transaction only when the touch began in
`YOUR MOVE` and no newer inbound, outbound, handled, or manual correction has
arrived. Otherwise it preserves the newer state.

## Interaction decision

The operator is a trades owner scanning lead cards one-handed. The correction
must be obvious, fast, and quiet without adding a second permanent card control.

Considered structures:

1. Split the chase strip into two buttons — rejected: crowds the highest-value
   scan row and compromises 44pt targets.
2. Put the correction in the long-press menu — rejected: hidden and unrelated
   to chase ownership.
3. Replace `ADJUST` with a direct `YOUR MOVE` button — rejected: removes the
   shipped comeback-date path.
4. Extend the existing `ADJUST` sheet — selected: one 44pt strip remains the
   entry point; waiting leads see `YOUR MOVE` first, then `// NEXT TOUCH` and
   the existing date presets.

All spacing, colors, typography, radii, and motion use existing `OPSStyle`
tokens. The new row is a standard 48pt sheet action, has an explicit
accessibility label, disables while saving, uses the existing save-failure
toast, and dismisses only after the authoritative server row returns.

## Test-first sequence

1. Add failing chase-engine tests for manual takeover of outbound, handled
   inbound, and directionless leads; later outbound/handled/inbound ordering;
   legacy direction fallback; new/date precedence.
2. Add failing DTO tests proving `operator_action_required_at` decodes/maps and the
   PATCH encodes only the new timestamp.
3. Add failing merge/apply coverage and V18-to-V19 SwiftData migration proof.
4. Implement the pure ownership comparison, DTO/model/apply plumbing,
   server-authoritative mutation, quick-touch ownership/guarded undo, and all
   three UI hosts.
5. Add the additive SQL migration and generated database type entry in the
   canonical ops-web repository, then apply it through Supabase migrations.
6. Update the OPS Software Bible chase contract.
7. Run focused tests, migration/fingerprint tests, lead snapshots, broader
   pipeline tests, a generic iOS build, design-token scan, live schema readback,
   and independent review.
8. Commit atomically, merge both repository branches into their local `main`
   branches without sweeping unrelated WIP, resolve the live bug report, and
   stop for manual verification. Do not push.
