# Project Note Mention Edit — Implementation Plan

**Goal:** Make edited project comments replace their authoritative mention list, remove stale mention-based access, and notify only newly added teammates exactly once across online, offline, and retry paths.

## Scope

- Cover both project Activity notes and photo-comment edits because both share the same broken persistence path.
- Keep the existing editor, picker, styling, animation, and user-facing copy unchanged.
- Update `content` and `mentioned_user_ids` together in every local, queued, and direct fallback write.
- Queue one dependent mention-delivery operation per newly added teammate.
- Give each edit a stable UUID used by a database-backed mention event, the in-app notification dedupe key, and OneSignal idempotency key.
- Preserve the hardened OPS Web rule that clients submit only persisted event proof, never recipient IDs or notification copy.
- Update the software bible with the authoritative edit and delivery contract.

## Test-first sequence

1. Add focused iOS regressions for:
   - resolving exact teammate names and `@All Team`;
   - replacing an old mention with a new mention;
   - clearing all mentions with an explicit empty array;
   - queuing one persisted-event dispatch only when the edit adds recipients;
   - reusing one event ID through outbound retries.
2. Run the focused tests and record the expected failures.
3. Add focused OPS Web tests proving the hardened dispatcher accepts only a mention-edit event UUID, derives recipients from the persisted event, intersects them with the note's current mentions, and reuses the event UUID for push retries.
4. Run the web tests and record the expected failures.

## Implementation

1. Centralize mention resolution and edit-delta planning.
2. Replace `DataController.updateProjectNoteContent` with an atomic content-plus-mentions writer that records both fields, including `mentioned_user_ids: []`.
3. Add an atomic `update_project_note_mentions` RPC that validates the note author and company, replaces content plus mentions, and records only the server-computed newly added recipients in `project_note_mention_events`.
4. Add durable, dependency-ordered mention-event dispatch operations to the existing sync queue.
5. Route the note update and event dispatch operations in both outbound engines through the RPC and hardened OPS Web dispatcher.
6. Extend the server dispatcher to resolve recipients, copy, navigation, rail persistence, and push exclusively from the persisted mention event; reuse the event UUID as OneSignal's idempotency key.
7. Make the direct repository fallback call the same RPC and revert both local fields on failure.
8. Use the same edit plan in Activity and photo-comment view models; request dispatch only when `new - old` is non-empty.

## Verification and landing

1. Run focused iOS tests, focused web tests, Swift build, and web type/build checks.
2. Confirm no design-system, layout, copy, or motion changes.
3. Commit iOS and web changes atomically.
4. Merge both branches into their local `main` branches without touching unrelated work.
5. Apply and verify the migration, deploy the backend-only web change, and verify the production route is healthy.
6. Resolve only bug report `5d9bb427-b39a-478f-a4cc-1f4ea8bfe527` with exact commit evidence and a live readback.
7. Stop for operator verification.
