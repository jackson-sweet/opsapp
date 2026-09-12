# iOS checklist choices and expense authority: local verification

Report1995a554-7fb1-4090-96c4-4e20a901c3a4 adds Multiple choice to site-visit checklist settings. Crew select one option or clear it; existing visits retain their captured options after template edits. Unrecognized historical text remains visible and recoverable. Storage remains compatible with all eight existing field kinds, and released SwiftData schemas are unchanged.

The settings/capture controls use OPSStyle tokens and expose at least44-point touch areas. The question and help text wrap fully at accessibility sizes, with the status below the question. Real hosted controls are exercised through accessibility actions at320pt capture width and390pt settings width. The fixture verifies selected/unselected state, explicit clearing, adding an option, enabled/disabled option controls, visible geometry and nonblank rendering. Route loading, production saves and physical-device interaction are not exercised by those controls tests.

## Source and verification

- iOS implementation a8f85dbf, recovery correction833e58c5, touch targets d9ff961d, fixture correction2aebc87c, accessible header1168058f.
- Final iOS runtime at1168058f:102 tests passed,0 failures,0 skips; xcodebuild exit0. This includes all declared schema checksums. Root exported and inspected all four required PNGs and their geometry fromrun6. See focused-tests.log, verification.json and screenshots/.
- Server choice source7d715b9d4;262 PostgreSQL17 checks passed:71 existing phone/function-compatibility checks and191 choice/recovery checks. Exact source/fixture hashes and red/green proof are committed in OPS-Web docs/artifacts/single-choice/.
- Expense authority sourceed60d7414;66 repaired authorization cases and4 two-session contention graphs passed, including rollback with no partial revision/notification/data effects before retry. Independent source review clear. Its synthetic fixture reproduces save lock order; it does not call the complete save RPC.
- The final whole-choice source and critical recovery/expense paths have independent review. No open actionable review findings remain for these prepared repairs.

## Release boundary and remaining work

Both additive migrations20260912004121 and20260912012607 remain unapplied. No push, deployment or iOS distribution was performed by this bug batch. The choice extension changes the Phase19 contract fingerprint; its release must account for pinned effects before activation, and does not reseal/enroll anything itself. Existing six Phase19 migration files and separate release evidence remain intact.

The expense authority repair is additional progress on the approval investigation, not completion of provider syncing or a measured customer-latency result. Accounting replacement still requires the founder's decision on personally paid crew expenses: keep the reimbursement owed until Mark paid, or record a provider payment on approval. Lead Details and LeadDeckScreen remain with their existing owner. Travel-aware appointment proposals and the other feature/product decisions are not completed by this batch.
