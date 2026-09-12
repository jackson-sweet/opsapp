# Verified checklist choices and expense authority

Multiple choice is implemented for site-visit checklists. Crews select one answer or clear it; visits retain their original options after a template changes. Historical free text remains visible and recoverable. All eight existing field kinds and released SwiftData schemas remain compatible.

The actual settings and capture controls have tokenized touch areas of at least 44 points. Questions wrap fully at accessibility text sizes. Root inspected four simulator screenshots showing option editing, retained historical text, selection and explicit clearing. The hosted controls exercise real accessibility actions at 320-point capture width and 390-point settings width; full authenticated routes and physical-device interaction were not exercised.

## Verification

- **150 distinct iOS tests passed, zero failures or skips.** The 102-test selection ran on production source `1168058f`; the additional 48 packet/recovery tests ran on `8b290d48`. Only test fixtures changed between those runs. Exact identifiers, source hashes and result paths are in `verification.json`; logs are beside this document.
- All declared schema checksums passed. Independent review confirmed the fixture corrections match existing actor and acknowledgement rules. New coverage proves that declining a send retains its dirty answer and remote alternative; adding another checklist preserves captured answers and avoids duplicate fields.
- **262 PostgreSQL checks passed** for server choice source `7d715b9d4`: 71 existing phone/function checks and 191 choice/recovery checks. Exact hashes and before/after proof are in OPS-Web `docs/artifacts/single-choice/`.
- **66 repaired expense authorization cases and four two-session contention scenarios passed** for source `ed60d7414`, with independent source review clear. Complete failed decisions roll back before retry, including revision and notification effects. These synthetic cases reproduce save lock ordering; they do not invoke the complete save RPC. Proof is in OPS-Web `docs/artifacts/expense-decision-authority/`.

## Release and remaining work

Both new migrations, `20260912004121` and `20260912012607`, remain unapplied. This bug batch performed no push, deployment or iOS distribution. The choice extension changes the Phase 19 contract fingerprint without resealing effects or activating company/host policies. The six existing Phase 19 migration sources and separate release evidence remain intact.

Expense authority is additional progress on the approval investigation. It does not complete accounting provider delivery or establish customer latency. Accounting replacement still requires the founder's decision on personally paid crew expenses: retain the reimbursement owed until Mark paid, or record a provider payment on approval. Lead Details and LeadDeckScreen remain with their existing owner. Travel-aware appointment proposals and other outstanding product decisions are not completed by this batch.
