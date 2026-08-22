# Assigned Client Contact Hydration Implementation Plan

> **Execution note:** Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Make a newly readable client immediately attach to an already-cached assigned project so crew can see and use the client’s contact information.

**Architecture:** Keep Supabase RLS as the authority for whether the client row is readable. After the existing one-row client fetch merges that authorized row into SwiftData, repair every cached `Project.client` relationship whose persisted `clientId` matches it. Apply the same repair to the default DataActor path and its supported legacy fallback; do not broaden server access or mutate customer data.

**Tech Stack:** Swift, SwiftData, XCTest, Supabase Swift client

**Design System:** N/A — no visual or copy changes

**Required Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`, `custom-skills:executing-plans`, `superpowers:verification-before-completion`, `supabase:supabase`

---

### Task 1: Pin the missing relationship regression

**Skills:** `superpowers:test-driven-development`

**Files:**
- Modify: `OPSTests/Sync/ProjectDetailsLocalFirstTests.swift`

**Step 1:** Seed a project with a valid `clientId` but a nil `client` relationship, mirroring a crew phone that learned the project before RLS made its client readable.

**Step 2:** Merge a contact-bearing client snapshot through `DataActor.mergeClientSnapshot`.

**Step 3:** Assert the project now resolves that exact client, email, and phone.

**Step 4:** Run only the new test and verify it fails because `Project.client` remains nil.

### Task 2: Repair relationships in both targeted client paths

**Skills:** `superpowers:systematic-debugging`, `superpowers:test-driven-development`

**Files:**
- Modify: `OPS/Network/Sync/ProjectCacheMerge.swift`
- Modify: `OPS/Utilities/DataActor.swift`
- Modify: `OPS/Network/Sync/InboundProcessor.swift`

**Step 1:** Add one shared SwiftData helper that fetches the authorized client and reconnects cached projects whose `clientId` matches it.

**Step 2:** Call it inside the DataActor snapshot transaction immediately after the client merge.

**Step 3:** Call it in the legacy targeted fetch path and save the repaired relationship.

**Step 4:** Re-run the focused test and the full `ProjectDetailsLocalFirstTests` class serially.

### Task 3: Document and verify the repair

**Skills:** `superpowers:verification-before-completion`

**Files:**
- Modify: the relevant client/project sync section in `../ops-software-bible/`

**Step 1:** Record that assignment-scoped client hydration repairs the local relationship without changing RLS or server rows.

**Step 2:** Run one isolated iOS build/test process with task-owned DerivedData; verify zero failures and that the process exits.

**Step 3:** Review diffs, run `git diff --check`, make atomic local iOS and Bible commits, and leave push/release to Jackson.
