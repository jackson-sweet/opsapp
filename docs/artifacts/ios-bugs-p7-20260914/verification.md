# Crew expense corrections — verified local implementation

Report `c381520d-84fa-40ea-ba66-67de14c717ce`. iOS source `3353ecce` (agent source `ed41a1d0`); OPS-Web source `134be2424`, both integrated locally. No production migration, financial provider write, phone installation or App Store distribution occurred.

## Results

- **115 iOS tests passed, zero failures or skips**, including 27 new correction contract/view-model/render cases and existing approval, expense buckets, notification, submission, receipt-image and feedback-catalog tests.
- **69 correction database assertions, seven concurrent-session checks, 123 existing accounting assertions, and two migration safety rejection checks passed** in an independent disposable PostgreSQL17 run with synthetic data. Exact migration reapplication also passed.
- Root visually inspected the actual crew-history component at 375 and 390 point widths, with long names, amount/tax/project changes, and no optional note. Text wraps without truncation in these fixtures; original and corrected values remain distinct and readable. This is component rendering proof, not a physical-phone interaction recording.
- Added expense UI styling uses existing OPSStyle spacing, typography, text colors and glass/button components. No new styling literals were found in the changed UI lines; monetary feedback uses JetBrains Mono.

Machine-readable result: [test-summary.json](test-summary.json). Exact tested production/test sources: [source-sha256.txt](source-sha256.txt).

## Verified behavior

Office reviewers can correct eligible unapproved crew expenses and return them with immutable before/after feedback and an optional note. Flag-only review remains available. The original receipt can be inspected, but reviewer corrections cannot replace receipt/OCR data. Approved, paid or exported evidence blocks this route.

One command binds the actor/company/submitter/expense and exact revision to the intended fields. The server commits fields, allocations, return status, history and one submitter notification together. Lost responses reuse the same request. Replays return the old receipt without applying it over newer crew edits. Stale reload preserves deliberate reviewer edits, adopts untouched fresh values and identifies overlapping changes. Account and read-generation changes prevent stale publication.

Returned unbatched expenses remain with the crew through automatic placement sweeps. Explicit crew resubmission clears only the exact correction markers; history and any newer independent flag remain. Correction itself creates no approval, payment, accounting event or provider work.

## Retained evidence

- iOS result: `/private/tmp/ops-ios-bugs-p7/focused-2.xcresult`
- iOS log: `/private/tmp/ops-ios-bugs-p7/focused-2.log`
- SQL logs: `/private/tmp/ops-expense-correction-proof.K8C2GU`
- 375pt history: [screenshot](expense-correction-crew-history-375.png)
- 390pt history: [screenshot](expense-correction-crew-history-390.png)
- Optional-note omission: [screenshot](expense-correction-without-note.png)

Simulator: iPhone17, iOS26.5 (23F77), SDK27.0; serial test execution, two build jobs. The first attempt stopped before compilation because copied package metadata still referenced an older cache released for cleanup. All22 binary paths were verified and corrected to existing retained artifacts; no production source changed between attempts. The second run completed successfully.

Pending migration `20260914214748_expense_admin_correction_review.sql`, SHA256 `f5a6d66815c8e9468817fc28d24a5fe1d7caa68dcb671b3b379a1ad227b5f015`, requires the pending P5 expense authority, accounting lifecycle and payroll compatibility migrations. Final live read returned null for both new RPCs and the receipt table. Applying the stack and distributing the app remain separately authorized release steps; the live bug was not closed.

After this successful run, build activity stopped for urgent disk cleanup. Source, logs, result bundles and these exported screenshots are preserved; regenerable package/build caches and the test simulator may be removed by the cleanup owner. A future run may need to restore packages/build caches and choose an available simulator.
