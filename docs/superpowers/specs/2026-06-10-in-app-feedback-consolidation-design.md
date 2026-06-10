# In-App Feedback Consolidation — Design Spec

- **Date:** 2026-06-10
- **Status:** Draft for review
- **Scope decision:** Total conversion · tiered errors (approved)
- **Architecture:** Central feedback catalog + semantic API + queue (Approach A, approved)

---

## 1. Problem

OPS ships a correct, on-brand toast component — `OPS/Styles/Components/Toast.swift` (`ToastCenter.shared`, glass-dense pill, olive/tan/rose tones, `//` voice, haptics, reduced-motion, optional tap-through action). It is mounted once on `MainTabView` via `.toastHost()`.

**Exactly one feature uses it: Leads** (`LeadsToastSubscriber.swift`, 8 events). Every other feature improvises. A full inventory (15-agent sweep, completeness-verified against ground truth) found:

| Mechanism | Count | Disposition |
|---|---|---|
| `.alert(` sites | 121 | ≈55 → toast (FYI + 3 single-action), remainder stay modal |
| `.confirmationDialog(` sites | 38 | confirms/menus/inputs stay; ~9 fire a success toast on completion |
| **Silent success paths** | **168** | → success toasts (the core gap) |
| Custom feedback surfaces | 48 | 27 fold into toast · 14 stay ambient · 7 stay modal |

The result: a user gets no confirmation for most saves; "syncing/synced" is shown six different ways; and at least **four parallel toast-like systems** exist (DeckBuilder "laser toasts" + estimate/save overlays, a custom Review toast overlay, a JobBoard `customAlert`, and "notes saved" banners in Project/Task views), plus 6 inline Catalog error displays, the measurement chips, `SyncRestoredAlert`, and `BooksSyncBanner`.

## 2. Goals / Non-goals

**Goals**
- Every transient "something happened" moment routes through the canonical `ToastCenter`.
- All feedback copy lives in one auditable place, in OPS voice (one `ops-copywriter` pass).
- Errors are tiered for field safety.
- The parallel toast-like systems are deleted and replaced by `ToastCenter` calls.

**Non-goals (stay as-is, by correctness)**
- Blocking confirmations and 2+ choice decisions (`.confirmationDialog` deletes/voids, "Retry vs Continue offline").
- The Supabase-backed notification **inbox** (`NotificationListView`, bell) — an inbox, not a transient event.
- Ambient persistent status (offline pill, avatar pending-count, `SyncStatusSection`, `ImageSyncProgressView` in-flight progress, `GracePeriodBanner`, AR HUDs, OCR/approval badges).
- Server-driven full-screen notices (`AppMessageView`), wizard chrome (`WizardBanner`), geofence action banner (`GeofenceBannerView`), push/local notifications.

## 3. Feedback policy (decision matrix)

| Situation | Treatment | Tone | Dismiss |
|---|---|---|---|
| Success / completion (currently silent) | Success toast | olive | auto 3s |
| FYI error (nothing to do) | Error toast | rose | auto 3s |
| Error with ONE recoverable action (e.g. Retry) | Error toast + tap-through action | rose | **manual only** |
| Error/decision with 2+ choices | **Stays modal** (`.alert`/sheet) | — | blocking |
| Destructive confirm ("Delete?", "Void?") | **Stays** `.confirmationDialog`; fires success toast on completion | — | blocking |
| Critical / blocking error | **Stays modal** (field visibility) | — | blocking |
| Action menu / input selection | **Stays** `.confirmationDialog` (it's a menu, not feedback) | — | — |
| Transient sync event (restored / failed / upload done) | Toast | varies | auto/manual |
| Ambient/persistent status | **Stays** (not an event) | — | — |

**Non-obvious correctness rules (load-bearing):**

1. **Fire at the user-action boundary, exactly once.** A toast is presented where a *user-initiated* action completes — never inside a loop, never in a low-level VM/data primitive that also runs in batches, and **never on an inbound/background sync merge.** With 168 success paths, this rule is what prevents toast floods and spurious "saved" toasts when server data arrives. When an action mutates N entities (e.g. bulk delete), it emits **one** toast ("// 5 ITEMS DELETED"), not N.
2. **Errors never silently auto-vanish if they're actionable.** Single-action error toasts have `autoDismissAfter: 0` (manual dismiss). Critical/blocking errors stay modal.
3. **One toast per semantic event.** The same user action surfaced in both a View and its ViewModel (the audit found many) gets exactly one call site — at the user-facing boundary.

## 4. Architecture (Approach A)

Three new/changed units, each independently testable:

### 4.1 `Feedback` catalog — `OPS/Styles/Components/Feedback.swift` (new)
The single source of truth for every feedback event. Namespaced by domain so call sites are discoverable and copy is centralized:

```swift
enum Feedback {
    enum Invoice {
        static var sent: Toast        { Toast(label: "// INVOICE SENT", tone: .success) }
        static var voided: Toast      { Toast(label: "// INVOICE VOIDED", tone: .success) }
        static var paymentRecorded: Toast { Toast(label: "// PAYMENT RECORDED", tone: .success) }
    }
    enum Estimate { /* created, sent, converted, lineItemAdded, ... */ }
    enum Sync {
        static var restored: Toast { Toast(label: "// CONNECTION RESTORED", tone: .success) }
        static func failed(retry: @escaping () -> Void) -> Toast {
            Toast(label: "// SYNC FAILED", tone: .error, autoDismissAfter: 0,
                  action: ToastAction(label: "RETRY", handler: retry))
        }
    }
    // ... ~140 events across 14 domains
    static func saved(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) SAVED", tone: .success) }
}
```

- ~140 distinct events; most collapse to `<NOUN> <PAST-VERB>` (CREATED/UPDATED/DELETED/SAVED/SENT). A handful of generic helpers (`saved(_:)`, `deleted(_:)`) cover the long tail; named cases cover the semantically important ones.
- **All labels are provisional in this spec.** Before any wiring, the complete label set goes through `ops-copywriter` in one pass.
- A generic escape hatch remains for genuine one-offs: `ToastCenter.shared.success("// …")`.

### 4.2 `ToastCenter` queue — extend `OPS/Styles/Components/Toast.swift`
Today `present(...)` replaces any in-flight toast ("freshest wins"). Under total conversion, rapid events would clobber each other. Change to a **FIFO queue**:

- Single toast visible at a time; queue depth capped (e.g. 3) — overflow drops oldest *non-error* entries.
- **Coalesce** identical consecutive labels (dedupe by `label`) so a burst reads as one.
- Minimum on-screen time (~1.5s) before advancing the queue, so toasts aren't subliminal.
- Error toasts with `autoDismissAfter: 0` are not auto-advanced; they hold until tapped.
- Semantic entry points: `show(_ toast: Toast)`, plus ergonomic `success(_:)`, `warning(_:)`, `error(_:action:)`.

### 4.3 `View+ErrorToast` modifier — `OPS/Styles/Components/View+ErrorToast.swift` (new)
~50 of the FYI errors share one shape: `.alert("Error", isPresented: <vm.error != nil>) { Button("OK") } message: { Text(vm.error) }`. Standardize the replacement so every domain converts identically:

```swift
.errorToast($viewModel.error)                       // FYI → auto-dismiss error toast
.errorToast($viewModel.error, retry: { await vm.retry() })  // single-action → manual-dismiss error toast + RETRY
```

The modifier observes the optional error string and presents the appropriate error toast via `ToastCenter`, then clears the binding.

### 4.4 Deletions (parallel systems removed)
Replaced by `ToastCenter` calls and deleted: DeckBuilder laser toasts + estimate-created/save-error/undo overlays, the custom Review toast overlay, JobBoard `customAlert` overlay, the Project/Task "notes saved" `saveNotificationOverlay` banners, the 6 Catalog inline `errorMessage` displays, measurement `AnnotationFeedbackToast` (transient states only — the persistent mode-indicator `HelperTextOverlay`/`AnnotationSaveStateBanner` stay), `SyncRestoredAlert`, and `BooksSyncBanner` transient states. In-flight "saving…" spinners stay during the operation but fire a success toast on completion.

## 5. Data flow

```
user action completes (view/sheet handler, or VM public method)
        │  (exactly once, at the action boundary)
        ▼
ToastCenter.shared.show(Feedback.Domain.event)
        │
        ▼
FIFO queue → coalesce/cap → ToastHostView (mounted on MainTabView) renders pill
```

Errors flow through `.errorToast($vm.error)` bound at the view, which calls the same queue. Confirms keep their `.confirmationDialog`; the confirmed action's success path calls `ToastCenter` like any other success.

## 6. Migration approach

Sequenced so shared infrastructure lands before any sweep:

1. **Infra (one commit each):** `Feedback.swift` catalog scaffold → `ToastCenter` queue → `View+ErrorToast` modifier → unit tests for the queue.
2. **Copy pass:** full label set through `ops-copywriter`; lock the catalog strings.
3. **Per-domain sweeps (14 buckets, one commit per domain):** Invoices+Estimates · Expenses · JobBoard core · JobBoard tasks · Catalog · Inventory · Settings A · Settings B/Subscription · Project/Notes/Activity · Common/Client/Images/User · Onboarding+Auth · DeckBuilder+AR · Review+Calendar · Sync/custom/Leads-reference. Each sweep: wire silent successes, convert FYI/single-action error alerts, fire outcome toasts from kept confirms, delete the domain's parallel toast system.
4. **Per-domain build verification:** `xcodebuild -scheme OPS -destination 'generic/platform=iOS' build` after each sweep; `build-for-testing` on the simulator for the queue tests.

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Heavy uncommitted WIP** in the working tree from sibling sessions, overlapping these files | Isolate on a dedicated branch (`feat/feedback-consolidation`); stage strictly by name; never touch pre-existing WIP. Exact safe sequence defined in the implementation plan. Several target files (Catalog, JobBoard) currently have sibling WIP — those sweeps coordinate or wait. |
| **Toast flooding** (168 events) | Action-boundary rule (§3.1) + queue coalescing/cap (§4.2). One toast per user action, never in loops. |
| **Spurious toasts on inbound sync** | Action-boundary rule — never toast from background/merge paths. |
| **Field visibility** — a gloved user in sunlight misses a 3s toast | Critical/blocking errors stay modal; actionable errors are manual-dismiss. |
| **Copy drift** across ~140 labels | Single centralized catalog + one `ops-copywriter` pass; no inline strings. |
| **Double toasts** (View + VM both fire) | Exactly-one call site per semantic event, at the user-facing boundary. |

## 8. Testing

- **Unit:** `ToastCenter` queue — enqueue/coalesce/cap/manual-error-hold/min-display ordering.
- **Snapshot:** the three tones + action variant (existing `#Preview` extended).
- **Per-domain:** build-clean after each sweep; spot-check representative actions per domain.

## 9. Open items
- **Completeness gap-fill — done.** 22 missed sites re-classified (14 alerts: 6 FYI-error→toast, 2 single-action→toast, 6 stay modal incl. text inputs + destructive confirms; 8 dialogs: 5 destructive confirms, 3 menus), plus 1 bonus import-conflict decision (stays modal). Folded into the per-domain sweeps. The exact per-site toast/modal split is pinned in the implementation plan.
- **Catalog copy — pending.** The full ~140-label set goes through `ops-copywriter` in one pass before any wiring (the labels in this spec are provisional).
