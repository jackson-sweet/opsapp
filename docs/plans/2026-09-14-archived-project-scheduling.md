# Archived project scheduling implementation plan

> Execute with custom-skills:executing-plans. Local implementation/integration is authorized; production migration and release remain separate.

**Goal:** Scheduling active work on an archived job reopens it as Accepted for future work, or In progress for work starting now or earlier.

**Architecture:** An explicit project reopen command and its dependent task write commit together to the local outbox. A narrowly authorized server command compares the exact captured archive revision and stores an idempotent receipt. Ordinary task writes never reopen archived jobs implicitly. Current project permissions, task lifecycle guards and lead decision boundaries remain intact.

**Tech stack:** SwiftData/Swift/XCTest, Supabase/PostgreSQL17.
**Design system:** Existing OPS controls/status tokens; no new layout or styling. New failure copy follows ops-copywriter.
**Required skills:** systematic-debugging, custom-skills:writing-plans, custom-skills:executing-plans, test-driven-development, verification-before-completion, supabase:supabase.

## 1. Reproduce
- Add a regression through DataController.updateTaskSchedule with an archived project materialized from a real DTO shape. Assert future work reopens locally and the task waits behind a durable project command. Run it against unchanged production source and retain failure evidence.
- Verify live parent guard, project-edit policy, status CAS/outbox behavior, exact timestamps and receipt permissions before pending SQL.

## 2. Server and transport
- Add private idempotent reopen receipts and public reopen_project_for_task with exact actor/company/project/command/expected timestamp/target validation. Archive state and timestamp must match before mutation. Replay returns original proof without repeating the status change.
- Use existing project authorization and canonical locking. Prove permission failures, stale archive, replay after later rearchive, rollback, and concurrent requests in a disposable database. No production migration.
- Add typed ProjectRepository transport validating returned command/company/project/target identities.

## 3. Local command custody
- Preserve exact raw server revision strings in a scoped metadata cache; do not change SwiftData stored schemas or round timestamps for CAS. Seed from all existing project DTO materialization paths.
- Atomically stage reopening and task schedule/create, set an exact operation dependency, and protect both from coalescing/cleanup. Dispatch the specialized project command in actor and fallback processors.
- Cover central single/generic scheduling, scheduled creation and batch scheduling without widening unrelated lifecycle behavior. Preserve row ownership, rollback, offline work and cache field protection.

## 4. Verify and integrate
- Run focused receipt/SQL tests, scheduling/outbox/rollback tests and both transport paths. Serialize one combined iOS build/test pass with the separately isolated automatic sync-report changes.
- Record source/test proof, update Bible and exact pending migration mirror, commit named files and integrate locally. Do not mark live bug resolved or claim phone acceptance.
