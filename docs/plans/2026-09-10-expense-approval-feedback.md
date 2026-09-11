# Expense approval feedback implementation plan

**Goal:** Show immediate honest approval progress, reject duplicate taps, and refresh only the affected batch after its atomic save.
**Architecture:** Keep the existing permission-checked RPC and serial accounting attempts. A shared view-model operation guard covers list, detail, and bulk approval. A successful RPC receipt survives failed readback; canonical batch/line reads update the shared cache without refetching company settings or every expense. Detail dismissal depends on approval success.
**Tech Stack:** SwiftUI, existing Supabase Swift repository, XCTest.
**Design System:** OPS design-system/project/DESIGN.md + mobile/MOBILE.md; existing OPSStyle tokens.
**Required Skills:** systematic-debugging, test-driven-development, writing-plans, executing-plans, ops-design, mobile-ux-design, interface-design, ui-ux-pro-max, ops-copywriter, audit-design-system.

1. Add controlled repository-boundary tests for pending RPC, delayed accounting, duplicate/reopened detail, partial failure, readback failure, and narrow cache replacement. Financial network methods are replaced by suspended test doubles; no live writes.
2. Add a narrow approval repository protocol, shared operation state, accepted-RPC receipts, and affected-batch refresh. Keep accounting sequential and awaited. Ignore stale console loads crossing a committed approval.
3. Show pending text in existing bottom CTA; lock competing approval/flag actions. Keep failed approvals open. Existing colors, fonts, radii, and spacing use OPSStyle tokens. No new animation.
4. Run syntax and diff checks. Parent owns the build baton and executes XCTest/device verification. Commit only this isolated change. Draft Bible update in artifact handoff.

Constraints: no receipt/OCR/Leads/global-sync edits, builds, financial mutations, production changes, or provider payload correction. Accounting v5 live contract mismatch and absent durable expense queue are separately reported to the parent.
