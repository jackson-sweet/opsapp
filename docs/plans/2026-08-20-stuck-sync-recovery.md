# Stuck Sync Recovery Implementation Plan

**Goal:** Recover Jackson's four exact Pending Work items without losing field data, then make each confirmed failure mode self-healing.

## 1. Oversized site-visit markup

- Add failing tests proving a file above the 10 MB server ceiling is normalized before upload, stays within a 2048 px longest edge, and does not mutate the durable source file.
- Add a failing test proving a bounded JSON presign error is preserved in the operation's visible error description while arbitrary response bodies are ignored.
- Add one shared raster-image preparation policy to the site-visit media path. Preserve already-safe assets byte-for-byte; downsize and adaptively encode only oversized images.
- Use the same policy when persisting future annotation composites so new files do not start oversized.

## 2. Obsolete deleted-task update

- Add failing settlement tests for the exact safe case: parked `projectTask` update, stable server-row-missing marker, and a matching local soft-delete tombstone.
- Prove active tasks, creates, unrelated errors, and mismatched tenants remain untouched.
- Run the settlement before the outbound drain and mark only proven-obsolete operations completed.

## 3. Restored site-visit custody

- Add failing vault tests proving a `parentDeleted` quarantine is released only after the exact same-company visit is active and server-synced.
- Preserve every local artifact, answer, draft, and media file; requeue only the quarantined operations and remove only the exact encrypted custody entry.
- Run release after inbound merge and before each push so the repaired server parent clears Pending Work on the next normal sync.

## 4. Live recovery and verification

- Guardedly clear `deleted_at` on the exact Olympic View visit only if its known tombstone and completed state still match.
- Independently read back the visit plus artifact and checklist counts.
- Re-copy the phone database without launching the app and verify no unrelated local rows changed.

## 5. Proof and handoff

- Update the OPS Software Bible for media sizing and restored-parent settlement.
- Run the focused XCTest suites and confirm the executed test count from the result bundle.
- Check for active Xcode builds, then run an isolated generic physical-device build using the primary package cache and worktree-local DerivedData.
- Inspect the final diff for line-ending churn, commit atomically, and do not push or install/launch the app.
