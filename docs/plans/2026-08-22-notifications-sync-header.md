# Notifications Sync Header Repair Plan

**Assigned reports:** `24c07cf9-f3d6-4870-85e2-e863ad051ba1`, `cf07df64-6d64-43f9-aaa2-eca4fc53f91d`

## Outcome

Repair the two screenshot-proven layout defects without changing recovery semantics:

- Notifications gives its existing compact sync card a canonical `PENDING SYNC` section label. The card keeps its operation-specific count and status sentence.
- Home owns the existing recovery indicator inside its measured header so it reserves space before `TODAY / ACTIVE / ALL`. Non-Home roots keep the global below-header fallback; Home project mode yields the top stack to its safety-critical project/navigation controls.

The global `N NEED A LOOK` count remains sourced exclusively from `RecoveryInventory.attentionCount`, including parked work.

## Reproduction evidence

- `24c07cf9`: the assigned Notifications screenshot shows an untitled `2 changes waiting to sync` card immediately above `TODAY (10)`.
- `cf07df64`: the assigned Home screenshot shows `1 NEED A LOOK` occupying the map-filter row and obscuring the `ALL` control.
- Each primary screenshot was fetched once under the nightly screenshot policy; no alternate attachments were needed.

## Implementation

1. Add the tokenized `PENDING SYNC` header inside `SyncStatusSection`'s existing visibility gate; preserve the raw panel, count, expansion, and `VIEW ALL` logic.
2. Add a Home-header placement to `SyncStatusIndicator`, render it only from the active Home `AppHeader`, and suppress MainTab's second copy across Home. Non-Home roots retain the fallback.
3. Add focused copy/snapshot proof for Notifications and geometry/placement-policy proof for Home at 390pt, 320pt, and accessibility sizes. The in-flow Home control expands and wraps at accessibility sizes instead of painting outside its header inset.
4. Run the focused sync tests serially, inspect both snapshots, run a generic iOS build, and run `git diff --check`.
5. Commit only the assigned files, merge the current local `main` safely into the isolated branch, rerun relevant proof, fast-forward local `main`, verify again, and reconcile only the two claimed Supabase rows with local-only evidence.

## Boundaries

- Do not change `RecoveryInventory` counting, attention/parked tone, retry behavior, or pill copy.
- Do not change the proven non-Home search/header collision layout.
- Do not refactor the full recovery screen or change retry/discard behavior.
- Do not push, deploy, release, or claim runtime/customer-live verification.
