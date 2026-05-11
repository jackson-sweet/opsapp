# Settings IA Reorganization — Design

**Bug ID:** 4014b472-062f-4f59-a569-4b8f2e54f642
**Bug screen:** `Settings.Projects`
**Reporter note:** "Need to reorganize settings. Ex project settings is an app setting. Not business setting"

## Problem

The iOS Settings root mixes three concerns inside the `BUSINESS` bucket — company identity (Org, Subscription), commerce-facing config (Catalog, Integrations), and workflow rules (Project Settings → Task Types, Scheduling Type, overdue review thresholds). The reporter flagged that workflow rules don't belong in `BUSINESS`. Several secondary problems compounded the report:

- **Subscription** appears twice (top-level `ACCOUNT` row and inside the Organization drill-in).
- **Manage Team**, **Organization Details**, **Permissions** are admin-frequent screens that today take 2 taps (Settings → Organization → drill-in or Settings → Business → Permissions).
- **Inventory Settings** is unreachable from the live `SettingsView` — it only exists in the legacy `AppSettingsView.swift`, which is dead code (no callers).
- **Task Types** and **Scheduling Type** are siblings inside `ProjectSettingsView`, but `ProjectSettingsView` itself contains semi-unrelated *Project Review* configuration (overdue threshold, reminder cadence, invoice matching). The page name overloads two distinct concerns.

## Goals

1. Move workflow-rule configuration out of `BUSINESS` into its own clearly-named bucket.
2. Flatten admin-frequent paths from 2 taps to 1.
3. Deduplicate `Subscription`.
4. Surface `Inventory Settings` in the live menu.
5. Make the bucket names map cleanly to the user's mental model (trades business owner persona).
6. Keep destination views and their internal logic unchanged — this is an IA pass, not a refactor of individual settings screens.

## Non-Goals

- Renaming/rewriting individual settings screens (e.g. `MapSettingsView`, `NotificationSettingsView`) beyond what's required to retitle `ProjectSettingsView`.
- Touching the field-crew tab structure (this is a Settings-internal change only).
- Changing permission gates that already exist on each destination.
- Migrating data, schema, or analytics history. Analytics screen names are updated where IA changes them; historical data continuity is acceptable as a small breakage.

## New IA

```
[ PROFILE CARD ]                                 → ProfileSettingsView

ORGANIZATION                                     admin/office gated
├ Organization Details                           OrganizationDetailsView
├ Manage Team                                    ManageTeamView
├ Subscription                          admin    ManageSubscriptionView
└ Permissions                           admin    PermissionsManagementView

BUSINESS                                         admin/office, pipeline-gated
├ Products & Services                            CatalogProductsListView
└ Integrations                                   IntegrationsSettingsView

OPERATIONS                                       admin/office gated
├ Task Types                                     TaskSettingsView
├ Project Rules                                  ProjectRulesView  (renamed)
└ Inventory                          catalog.view InventorySettingsView

(Scheduling Type was originally planned for OPERATIONS, but the parallel
 "task-only scheduling migration" deprecated and deleted
 SchedulingTypeExplanationView during this work. With no destination page,
 the row was dropped and any reference to .schedulingType removed.)

APP
├ Notifications                                  NotificationSettingsView
├ Map                                            MapSettingsView
├ Data & Storage                                 DataStorageSettingsView
├ Security & Privacy                             SecuritySettingsView
└ Laser Meter                                    LaserMeterSettingsView

DATA
├ Photos                                         AllPhotosGalleryView
├ My Expenses                       expenses.view MyExpensesView
├ Review Expenses                expenses.approve ExpensesListView
└ Trash                              admin/office TrashView

SUPPORT
├ Setup Guides                                   WizardManagementView
├ What's New                                     WhatsNewView
├ Report Issue                                   ReportIssueView
└ Restart Tutorial                               TutorialFlowViewV2

DEVELOPER  (DEBUG or opted-in)
└ Developer Tools                                DeveloperDashboard

[ LOG OUT ]
```

### Section gate logic

| Section | Visible when |
|---|---|
| ORGANIZATION | `permissionStore.can("team.view")` (admin/office). Subscription row gated on `settings.billing`. Permissions row gated on `settings.company`. |
| BUSINESS | `hasPipelineAccess` OR `isPipelineGated` (shows the "in testing" gated rows). |
| OPERATIONS | `permissionStore.can("team.view")` for the bucket header. Each row may be further gated: Inventory on `catalog.view`. Field crew with only `catalog.view` sees a singleton OPERATIONS bucket containing just Inventory. |
| APP | always |
| DATA | always (rows individually gated) |
| SUPPORT | always |
| DEVELOPER | `#if DEBUG` OR `developerModeEnabled` AND `!developerModeExplicitlyDisabled` |

## What Changes

### Settings root (`SettingsView.swift`)

- Drop the `ACCOUNT` section header entirely. Its two rows (Organization, Subscription) are absorbed into the new `ORGANIZATION` section as top-level rows.
- Promote `Organization Details`, `Manage Team`, `Permissions` from sub-page drill-ins to top-level `ORGANIZATION` rows.
- Move `Project Settings` (renamed `Project Rules`) out of `BUSINESS` into a new `OPERATIONS` section.
- Promote `Task Types`, `Scheduling Type` from inside `ProjectSettingsView` to top-level `OPERATIONS` rows.
- Add `Inventory` to `OPERATIONS` (previously buried).
- `BUSINESS` now contains only `Products & Services` and `Integrations`.
- All other sections unchanged.

### `ProjectSettingsView.swift` → `ProjectRulesView.swift`

- Rename file, struct, and entry point.
- Drop the in-page "PROJECT SETTINGS" sub-section (Task Types row + Scheduling Type row). Those are now siblings in the parent menu.
- Header title changes from "Project Settings" to "Project Rules".
- Page now contains only the "PROJECT REVIEW" section (3 stepper/toggle rows). Anchor IDs updated to drop the now-redundant `projectSettings` anchor; keep `projectReview`.
- `trackScreen("Settings.Projects")` → `trackScreen("Settings.ProjectRules")`.

### `SettingsDestination` enum

The enum gains no new cases — every new menu row maps onto an existing case (e.g. `Manage Team` → `.manageTeam`, `Organization Details` → `.organizationDetails`, `Inventory` → `.inventorySettings`, `Task Types` → `.taskTypes`, `Scheduling Type` → `.schedulingType`). These cases already exist as deep-link targets from search; they're now just used as primary entry points too.

The enum loses no cases — `.organization` and `.projectSettings` are kept for back-compat:
- `.organization` still routes to `OrganizationSettingsView` (which becomes reachable only via wizards/search; not from the new menu). Could be removed in a later pass, but kept now to avoid breaking wizard receivers.
- `.projectSettings` now routes to the renamed `ProjectRulesView`.

### Wizard deep-link chain (`MainTabView.swift`)

Simplification:

- `WizardOpenManageTeam` → previously posted `SettingsOpenOrganization` then `WizardOpenManageTeamFromOrg` with two timed delays. New behavior: post `SettingsOpenManageTeam` once, which `SettingsView` listens for directly.
- Add a new `.onReceive(SettingsOpenManageTeam)` in `SettingsView` that sets `activeDestination = .manageTeam`.
- The legacy `SettingsOpenOrganization` and `WizardOpenManageTeamFromOrg` notifications stay (no caller removal forced) but become quiescent paths. Removing them is out of scope for this pass.

### Search index (`SettingsSearchIndex.swift`)

Breadcrumbs rewritten so search results visibly hang off the new IA. Examples:

| Old breadcrumb | New breadcrumb |
|---|---|
| `[Organization, Manage Team, Crew Code]` | `[Manage Team, Crew Code]` |
| `[Organization, Subscription]` | `[Subscription]` |
| `[Project Settings, Task Types, Set Color]` | `[Task Types, Set Color]` |
| `[Project Settings, Scheduling Type]` | `[Scheduling Type]` |
| `[Project Settings]` *(the page itself)* | `[Project Rules]` |
| `[Inventory Settings]` *(orphan, no menu home)* | `[Inventory]` |

All routes (`SettingsRoute`) unchanged — only the breadcrumb display strings.

### Analytics

- `Settings.Projects` → `Settings.ProjectRules` (the only screen-name change).
- Other `trackScreen` calls are untouched. The IA reorganization shows the same destination views as before; their analytics names stay stable.

### Dead code removal

- Delete `OPS/Views/Settings/AppSettingsView.swift` — 305 lines, no callers, predates the live `SettingsView`. Verified by grep: only self-references.

## Files touched

| File | Action |
|---|---|
| `OPS/Views/SettingsView.swift` | Rewrite the section list. Add `SettingsOpenManageTeam` notification listener. |
| `OPS/Views/Settings/ProjectSettingsView.swift` | Rename to `ProjectRulesView.swift`. Drop in-page nav rows. Update header + analytics name. |
| `OPS/Views/Settings/SettingsSearchIndex.swift` | Rewrite breadcrumbs per table above. |
| `OPS/Views/MainTabView.swift` | Simplify `WizardOpenManageTeam` handler. |
| `OPS/Views/Settings/AppSettingsView.swift` | Delete (dead code). |
| `OPS.xcodeproj/project.pbxproj` | Remove deleted file references; update renamed file references. |

## Risks

1. **Wizard regressions.** Two of the wizard notification chains change. The `WizardOpenManageTeam` path is simplified but the legacy `WizardOpenManageTeamFromOrg` listener stays in `OrganizationSettingsView` — neither chain is fully torn down, so a wizard that still uses the old chain continues to work.
2. **Search breadcrumb cache.** The search index rebuilds on every keystroke (`SettingsSearchIndex.build(...)`), so there's no stale cache to invalidate.
3. **Analytics history split.** `Settings.Projects` events end and `Settings.ProjectRules` events begin. Mixpanel reports straddling the deploy will need to union both names. Acceptable.
4. **iOS Supabase sync constraint.** No schema changes in this pass — IA reorganization is client-only. No risk to App Store-locked users.

## Verification

1. **Build:** `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` (per `ops-ios/CLAUDE.md`, no simulator).
2. **Manual smoke:** Open Settings, confirm each new top-level row navigates to the expected destination. Run the Setup wizard's "Manage Team" step and confirm the simplified chain still lands on `ManageTeamView`. Open Settings search, type "task types" → confirm breadcrumb shows `[Task Types]`, not `[Project Settings, Task Types]`.
3. **Permission gates:** Log in as field crew (no `team.view`) and confirm ORGANIZATION + BUSINESS + OPERATIONS sections are hidden. Then grant `catalog.view` and confirm OPERATIONS appears with only the Inventory row.
4. **Supabase resolution:** Update `bug_reports` row `4014b472-062f-4f59-a569-4b8f2e54f642` with `status='resolved'`, `resolved_at=now()`, `fixed_at=now()`, `fix_notes='Reorganized Settings IA: Project Settings (renamed Project Rules) moved from BUSINESS to new OPERATIONS bucket. Task Types, Scheduling Type, Inventory promoted to top-level Operations rows. Organization Details, Manage Team, Permissions promoted from sub-page drill-ins to top-level Organization rows. Subscription deduplicated.'`.
