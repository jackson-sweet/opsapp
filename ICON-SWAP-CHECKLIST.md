# OPS iOS — SF Symbols → Carbon Icon Swap Checklist

Prerequisite inventory for the iOS migration from Apple SF Symbols to IBM Carbon Design System custom symbols.

The actual code swap is **blocked** until the user authors Carbon custom symbols in the SF Symbols app and adds them to the asset catalog. This checklist tells the user exactly which custom symbols to create, and where in the codebase each swap will land.

**Source of truth for the mapping:** `/Users/jacksonsweet/Projects/OPS/OPS-ICON-SET-BRIEF.md` § CARBON MAPPING.
**Inventory scope:** `ops-ios/.worktrees/ios-design-system-pass/OPS/` — 952 Swift files.

---

## Summary

| Metric | Count |
|---|---|
| **Unique SF Symbol strings in iOS source** | **211** |
| **Total SF Symbol call sites** (`Image(systemName:)` + `Label(... systemImage:)` + `Button(... systemImage:)`) | **~1,640** |
| `Image(systemName:)` only | 1,495 |
| `Label(... systemImage:)` only | 143 |
| `Button(... systemImage:)` and related | 116 |
| Literal-string call sites | 880 |
| OPSStyle.Icons indirection call sites | 496 |
| **OPSStyle.Icons enum concepts** (canonical map) | **92** |
| **Carbon targets covering the inventory** | **~115** unique `@carbon/icons-react` names |
| **Reserved / locked symbols** (do NOT redesign) | 1 (`apple.logo` — 5 sites) |
| **Gaps / weak Carbon matches** | **17** symbols (8 net-new trade gaps + 9 weak/specialized) |

**Read this checklist top-to-bottom in order:**
1. The **OPSStyle.Icons enum mapping** is the highest leverage — 92 enum rows drive 496 of the call sites. Author Carbon targets for every row here first.
2. The **per-tier groups** cover the remaining 119 unique symbols that are referenced as literal strings outside the enum.
3. The **tab bar callout** identifies the 7 root tabs that need new Carbon icons in the asset catalog.
4. The **gaps** flag what Carbon does not cover.

---

## OPSStyle.Icons enum mapping

`OPS/Styles/OPSStyle.swift:594-750` defines the canonical `OPSStyle.Icons` enum — 92 cases. Replacing each enum value with a Carbon custom-symbol asset name automatically migrates every call site that uses `OPSStyle.Icons.X` (~496 sites). Highest-ROI section in the checklist.

### Domain semantic icons (lines 601-649)

| OPSStyle case | Concept | Current SF Symbol | Carbon target (`@carbon/icons-react`) | Fit | Brief slug |
|---|---|---|---|---|---|
| `project` | A project / job record | `folder.fill` | `Folder` (pair `FolderOpen`) | exact | `project` |
| `task` | A task / to-do record | `checklist` | `Task` | exact | `task` |
| `taskType` | A task type / work category | `tag.fill` | `Tag` | exact | `task-type` |
| `client` | A client / customer record | `person.circle.fill` | `User` | exact | `client` |
| `subClient` | A sub-client (client of a client) | `person.2.fill` | `UserMultiple` | close | `sub-client` |
| `teamMember` | A team member | `person.fill` | `UserAvatar` | close | `team-member` |
| `crew` | A crew / field team | `person.3.fill` | `Group` | close | `crew` |
| `schedule` | Scheduling | `calendar.badge.clock` | `Event` | close | `schedule-confirmed` |
| `deadline` | Deadlines | `calendar.badge.exclamationmark` | `Alarm` | close | `deadline` |
| `duration` | Duration / time | `clock.fill` | `TimeFilled` | close | `duration` |
| `jobSite` | Job site location | `location.fill` | `LocationCompany` | close | `job-site` |
| `address` | A street address | `mappin.and.ellipse` | `Location` | exact | `address` |
| `notes` | Note / memo record | `note.text` | `Notebook` | close | `note` |
| `description` | Description field | `text.alignleft` | `TextAlignLeft` | exact | (utility) |
| `photos` | Photos | `photo.on.rectangle` | `Image` | exact | `photo` |
| `documents` | Documents | `doc.text.fill` | `Document` | exact | `document` |
| `add` | Add / create | `plus.circle.fill` | `AddAlt` | exact | `add-circle` |
| `edit` | Edit / rename | `pencil.circle.fill` | `Edit` | exact | `edit` |
| `delete` | Delete | `trash.fill` | `TrashCan` | exact | `delete` |
| `sync` | Sync / refresh | `arrow.triangle.2.circlepath` | `Renew` | exact | `sync` |
| `share` | Share | `square.and.arrow.up` | `Share` | exact | `share` |
| `filter` | Filter | `line.horizontal.3.decrease.circle` | `Filter` | exact | `filter` |
| `sort` | Sort | `arrow.up.arrow.down.circle` | `CaretSort` | exact | `sort` |
| `addContact` | Add from contacts | `person.crop.circle.badge.plus` | `UserFollow` | close | `new-client` |
| `addProject` | Create project | `folder.badge.plus` | `FolderAdd` | exact | `new-project` |
| `complete` | Complete | `checkmark.circle.fill` | `CheckmarkFilled` | exact | `success` |
| `incomplete` | Incomplete / unselected | `circle` | `Incomplete` | exact | `incomplete` |
| `inProgress` | In progress | `clock.arrow.circlepath` | `InProgress` | exact | `in-progress` |
| `alert` | Alerts / warnings | `exclamationmark.triangle.fill` | `WarningFilled` | exact | `warning` |
| `error` | Errors | `xmark.octagon.fill` | `Misuse` | close | `error-critical` |
| `info` | Information | `info.circle.fill` | `InformationFilled` | exact | `info` |
| `settings` | Settings | `gearshape.fill` | `Settings` | exact | `nav-settings` |
| `search` | Search | `magnifyingglass` | `Search` | exact | `search` |
| `menu` | Menu / hamburger | `line.3.horizontal` | `Menu` | exact | `menu` |
| `close` | Close / dismiss | `xmark` | `Close` | exact | `close` |
| `back` | Back navigation | `chevron.left` | `ChevronLeft` | exact | `chevron-left` |
| `forward` | Forward navigation | `chevron.right` | `ChevronRight` | exact | `chevron-right` |

### Legacy SF Symbols block (lines 655-722)

| OPSStyle case | Current SF Symbol | Carbon target | Fit |
|---|---|---|---|
| `calendar` | `calendar` | `Calendar` | exact |
| `calendarFill` | `calendar.fill` | `Calendar` (single weight) | exact |
| `calendarBadgeCheckmark` | `calendar.badge.checkmark` | `CalendarCheck` (closest: `EventSchedule`) | close |
| `person` | `person` | `User` | exact |
| `personFill` | `person.fill` | `User` (single weight) | exact |
| `personTwo` | `person.2` | `UserMultiple` | exact |
| `personTwoFill` | `person.2.fill` | `UserMultiple` | exact |
| `personCircle` | `person.circle` | `UserAvatar` | close |
| `personCircleFill` | `person.circle.fill` | `UserAvatar` | close |
| `location` | `location` | `Location` | exact |
| `locationFill` | `location.fill` | `Location` | exact |
| `phone` | `phone` | `Phone` | exact |
| `phoneFill` | `phone.fill` | `Phone` | exact |
| `envelope` | `envelope` | `Email` | exact |
| `envelopeFill` | `envelope.fill` | `Email` | exact |
| `folder` | `folder` | `Folder` | exact |
| `folderFill` | `folder.fill` | `Folder` | exact |
| `checklist` | `checklist` | `Task` (or `ListChecked`) | close |
| `checkmark` | `checkmark` | `Checkmark` | exact |
| `checkmarkSquare` | `checkmark.square` | `CheckboxChecked` | close |
| `checkmarkSquareFill` | `checkmark.square.fill` | `CheckboxCheckedFilled` | close |
| `checkmarkCircle` | `checkmark.circle` | `Checkmark` (outline circle) | exact |
| `checkmarkCircleFill` | `checkmark.circle.fill` | `CheckmarkFilled` | exact |
| `circle` | `circle` | `CircleDash` (or `RadioButton`) | close |
| `square` | `square` | `Checkbox` (empty box) | close |
| `squareFill` | `square.fill` | `CheckboxIndeterminateFilled` | weak |
| `xmark` | `xmark` | `Close` | exact |
| `xmarkCircle` | `xmark.circle` | `CloseOutline` | exact |
| `xmarkCircleFill` | `xmark.circle.fill` | `CloseFilled` | exact |
| `chevronRight` | `chevron.right` | `ChevronRight` | exact |
| `chevronLeft` | `chevron.left` | `ChevronLeft` | exact |
| `chevronUp` | `chevron.up` | `ChevronUp` | exact |
| `chevronDown` | `chevron.down` | `ChevronDown` | exact |
| `plus` | `plus` | `Add` | exact |
| `plusCircle` | `plus.circle` | `AddAlt` | exact |
| `plusCircleFill` | `plus.circle.fill` | `AddFilled` | exact |
| `minus` | `minus` | `Subtract` | exact |
| `minusCircle` | `minus.circle` | `SubtractAlt` | exact |
| `minusCircleFill` | `minus.circle.fill` | `SubtractFilled` | exact |
| `exclamationmarkTriangle` | `exclamationmark.triangle` | `Warning` | exact |
| `exclamationmarkTriangleFill` | `exclamationmark.triangle.fill` | `WarningFilled` | exact |
| `gearshape` | `gearshape` | `Settings` | exact |
| `gearshapeFill` | `gearshape.fill` | `Settings` | exact |
| `house` | `house` | `Home` | exact |
| `houseFill` | `house.fill` | `Home` | exact |
| `map` | `map` | `Map` | exact |
| `mapFill` | `map.fill` | `Map` | exact |
| `ellipsis` | `ellipsis` | `OverflowMenuHorizontal` | exact |
| `ellipsisCircle` | `ellipsis.circle` | `OverflowMenuHorizontal` | exact |
| `ellipsisCircleFill` | `ellipsis.circle.fill` | `OverflowMenuHorizontal` (filled bg pair) | close |
| `listBullet` | `list.bullet` | `List` | exact |
| `trash` | `trash` | `TrashCan` | exact |
| `trashFill` | `trash.fill` | `TrashCan` | exact |
| `pencil` | `pencil` | `Edit` (or `Pen`) | exact |
| `pencilCircle` | `pencil.circle` | `EditOff` outline variant | close |
| `pencilCircleFill` | `pencil.circle.fill` | `Edit` (filled background) | close |
| `arrowClockwise` | `arrow.clockwise` | `Renew` | exact |
| `arrowCounterclockwise` | `arrow.counterclockwise` | `Reset` | exact |
| `magnifyingglass` | `magnifyingglass` | `Search` | exact |
| `magnifyingglassCircle` | `magnifyingglass.circle` | `Search` | exact |
| `magnifyingglassCircleFill` | `magnifyingglass.circle.fill` | `Search` (filled bg) | close |
| `bellFill` | `bell.fill` | `Notification` | exact |
| `photo` | `photo` | `Image` | exact |
| `photoFill` | `photo.fill` | `Image` | exact |
| `camera` | `camera` | `Camera` | exact |
| `cameraFill` | `camera.fill` | `Camera` | exact |
| `clock` | `clock` | `Time` | exact |
| `copy` | `doc.on.doc` | `Copy` | exact |

### Pipeline & Financial block (lines 724-749)

| OPSStyle case | Concept | Current SF Symbol | Carbon target | Fit |
|---|---|---|---|---|
| `opportunity` | Lead / sales opportunity | `arrow.up.right.circle.fill` | `Growth` | close |
| `pipelineChart` | Pipeline chart | `chart.bar.doc.horizontal.fill` | `ChartBar` (or `Flow`) | close |
| `estimateDoc` | Estimate document | `doc.text.fill` | `DocumentBlank` | close |
| `invoiceReceipt` | Invoice receipt | `receipt` | `Receipt` | exact |
| `paymentDollar` | Payment | `dollarsign.circle.fill` | `Purchase` | close |
| `siteVisitPin` | Site visit | `mappin.circle.fill` | `LocationPerson` | close |
| `activityBubble` | Activity log | `bubble.left.and.text.bubble.right.fill` | `Activity` | exact |
| `followUpAlarm` | Follow-up alarm | `alarm.fill` | `Alarm` | exact |
| `stageAdvance` | Advance stage | `arrow.forward.circle.fill` | `ArrowRight` | close |
| `dealWon` | Deal won | `checkmark.seal.fill` | `Trophy` | exact |
| `dealLost` | Deal lost | `xmark.seal.fill` | `CloseOutline` | weak |
| `accountingChart` | Accounting chart | `chart.bar.fill` | `ChartBar` | exact |
| `productTag` | Product tag | `tag.fill` | `Tag` | exact |
| `stale` | Stale / attention | `exclamationmark.triangle.fill` | `WarningFilled` | exact |
| `expense` | Expense | `dollarsign.circle` | `Money` | close |
| `banknoteFill` | Banknote / payment | `banknote.fill` | `Currency` | exact |
| `undo` | Undo | `arrow.uturn.backward` | `Undo` | exact |
| `sendFill` | Send (filled) | `arrow.up.circle.fill` | `Send` | close |
| `bell` | Notifications | `bell` | `Notification` | exact |
| `mention` | @-mention | `at` | `At` | exact |
| `assignmentNotification` | Assignment notification | `person.badge.plus` | `UserFollow` | close |
| `pencilTip` | Annotate / pencil tip | `pencil.tip` | `Pen` | weak |
| `receipt` | Receipt | `doc.text.viewfinder` | `Receipt` | exact |
| `clockFill` | Clock (filled) | `clock.fill` | `TimeFilled` | exact |
| `exclamationmarkCircleFill` | Error circle filled | `exclamationmark.circle.fill` | `ErrorFilled` | exact |

---

## Per-tier groups (literal-string call sites)

These are SF Symbol strings used directly (`Image(systemName: "...")`) outside the `OPSStyle.Icons` enum. Grouped by tier per the brief, with the Carbon target and a count of literal call sites. The literal call-site count is the number that will need to be touched by the swap PR; once `OPSStyle.Icons` is also migrated, many of these literals should also be folded into `OPSStyle.Icons`.

### Tier 1 — Navigation

| Carbon target | SF Symbol(s) covered | Literal call sites | Notes |
|---|---|---|---|
| `Home` | `house.fill`, `house` | 1+1 | Dashboard tab (also `OPSStyle.Icons.houseFill`) |
| `Portfolio` | `briefcase.fill`, `briefcase` | 1+1 | Jobs tab |
| `Flow` | `point.3.connected.trianglepath.dotted` | (in `MainTabView.swift:223` — string literal in TabItem ctor) | Pipeline tab |
| `Finance` | `chart.line.uptrend.xyaxis` | 1 | Books tab |
| `Calendar` | `calendar` | 7 (also `OPSStyle.Icons.calendar` ×17) | Schedule tab + many date fields |
| `Categories` | `square.stack.3d.up.fill`, `square.stack.3d.up` | (TabItem `MainTabView.swift:238`) + 2 | Catalog tab + product family |
| `Settings` | `gearshape.fill`, `gearshape`, `gear` | (TabItem `MainTabView.swift:244`) + 5 + 1 | Settings tab |
| `Map` | `map.fill`, `map`, `map.slash` | 2+1+2 | Map screens |
| `MailAll` | (none — no inbox tab on iOS) | — | iOS reaches inbox via Job Board |
| `Building` | `building.2`, `building.2.fill` | 5+1 | Settings → Company |
| `UserMultiple` | `person.2`, `person.2.badge.gearshape`, `person.3`, `person.3.sequence.fill` | 5+2+1+2 | Settings → Team |
| `Wallet` | `creditcard` | 1 | Settings → Billing |
| `Tools` | `hammer` | 1 | Settings → Operations |
| `Ai` | `sparkles` | 3 | Settings → AI (also AI features generally) |
| `Connect` | `link.badge.plus` | 2 | Settings → Integrations / unlink |
| `Security` | `lock.shield.fill`, `shield`, `lock.fill` | 1+1+6 | Settings → Security |
| `Code` | (no equivalent yet) | — | Settings → Developer |
| `SettingsAdjust` | `slider.horizontal.3` | 1 | Settings → Preferences |
| `Rocket` | (no equivalent yet) | — | Settings → Setup wizards |
| `DocumentView` | `doc.text.magnifyingglass` | 2 | Settings → Audit log |
| `Datastore` | `cylinder.fill` | 2 | Settings → Storage / database |

### Tier 2 — Data types

| Carbon target | SF Symbol(s) covered | Literal call sites | Notes |
|---|---|---|---|
| `Folder` / `FolderOpen` | `folder.fill`, `folder` | 7+6 (also `OPSStyle.Icons.project` ×8, `.folderFill` ×4) | Project record |
| `Task` | `checklist` | 5 (also `OPSStyle.Icons.task` ×10) | Task record |
| `Tag` | `tag.fill`, `tag` | 3+5 (also `OPSStyle.Icons.productTag` ×4, `.taskType` ×2) | Task type / product tag |
| `Growth` | (literal) — covered via `opportunity` enum | — | Lead / opportunity |
| `LocationPerson` | `mappin.circle`, `mappin.circle.fill`, `mappin` | 8+2+1 (also `OPSStyle.Icons.siteVisitPin`) | Site visit |
| `Activity` | `bubble.left.and.text.bubble.right.fill`, `bubble.left.fill` | 1+1 (also `OPSStyle.Icons.activityBubble`) | Activity log |
| `FlowConnection` | `arrow.triangle.branch` | 4 (Label uses 2 more) | Dependency |
| `User` | `person.circle.fill`, `person.fill`, `person`, `person.crop.circle` | 7+7+1+2 (also `OPSStyle.Icons.client` ×11, `.teamMember`, `.personFill` ×6) | Client / contact / person |
| `UserMultiple` | `person.2`, `person.2.fill`, `person.3.sequence.fill` | 5+ (folded above) | sub-client / crew |
| `UserProfile` | `person.crop.rectangle.stack`, `person.crop.circle.badge.questionmark` | 1+1 | Contact / unknown |
| `Building` | `building.2`, `building.2.fill` | 5+1 | Company |
| `UserAvatar` | `person.crop.circle` | 2 | Team member avatar |
| `IdManagement` | `person.badge.key`, `person.badge.shield.checkmark` | 2+2 | Role |
| `UserAdmin` | (no literal — covered via `crown` if used) | — | Owner |
| `DocumentBlank` | `doc.text` (estimate context), `doc.fill`, `doc.text.fill` | 3+2+1 (also `OPSStyle.Icons.estimateDoc` ×4) | Estimate |
| `Receipt` | `doc.text.viewfinder` | 2 (also `OPSStyle.Icons.receipt`, `.invoiceReceipt` ×3) | Invoice |
| `Money` | `dollarsign.circle`, `dollarsign.circle.fill` | 1+1 (also `OPSStyle.Icons.expense` ×4, `.paymentDollar`) | Expense / money |
| `Purchase` | `dollarsign.circle.fill` | (folded) | Payment |
| `Currency` | (literal not found — covered via `banknoteFill`) | — | Money value |
| `Document` | `doc.text`, `doc.fill` | (folded above) | Generic document |
| `ListBulleted` | `list.bullet.rectangle` | 1 | Line item |
| `Certificate` | `certificate` | 1 | Certification |
| `Product` | (folded — covered via Catalog tab `Categories`) | — | Product record |
| `Categories` | `square.stack.3d.up` | 2 | Product family |
| `Box` | `shippingbox`, `shippingbox.fill` | 6+4 | Inventory item / materials |
| `ShoppingCart` | `cart.fill`, `cart.badge.plus` | 1+1 | Order / cart |
| `Notebook` | `note.text` | 1 (also `OPSStyle.Icons.notes` ×4) | Note |
| `Image` | `photo`, `photo.fill`, `photo.on.rectangle`, `photo.on.rectangle.angled` | 6+1+5+3 (also `OPSStyle.Icons.photo` ×9, `.photos` ×2) | Photo |
| `NoImage` | (use `Image` greyed) | — | Image placeholder |
| `Attachment` | (no literal — pattern uses paperclip elsewhere) | — | Attachment |
| `DocumentBlank` | `doc.fill` | 2 | Generic file |
| `ImageReference` | (no literal) | — | Image file |
| `Csv` / `Xls` | (no literal) | — | Spreadsheet file |
| `Video` | (no literal `video.fill`) | — | Video |
| `Chat` | `message.fill`, `message`, `bubble.left.fill` | 4+2+1 | Message / chat |
| `Email` | `envelope.fill`, `envelope`, `envelope.circle.fill` | 7+3+2 (also `OPSStyle.Icons.envelope` ×9, `.envelopeFill` ×4) | Email |
| `LocationCompany` | `location.fill`, `location`, `location.slash.fill`, `location.slash` | 5+1+1+1 (also `OPSStyle.Icons.location` ×5, `.locationFill` ×2, `.jobSite` ×2) | Job site |
| `Location` | `mappin.and.ellipse`, `mappin.slash.circle` | 3+1 (also `OPSStyle.Icons.address` ×4) | Address |
| `Calendar` | `calendar` | (folded) | Date value |
| `DocumentSigned` | (no literal — would need new) | — | Signed document |

### Tier 3 — Actions

| Carbon target | SF Symbol(s) covered | Literal call sites | Notes |
|---|---|---|---|
| `Add` | `plus` | 32 (also `OPSStyle.Icons.plus` ×15, `.add` ×3) | Highest-volume action — ubiquitous |
| `AddAlt` | `plus.circle`, `plus.circle.fill` | 3+17 (also `OPSStyle.Icons.plusCircleFill` ×3) | Emphasized add |
| `Edit` | `pencil`, `square.and.pencil`, `pencil.and.list.clipboard` | 18+4+1 (also `OPSStyle.Icons.pencil` ×7) | Edit |
| `Pen` | `pencil.tip` | 1 (also `OPSStyle.Icons.pencilTip`) | Annotate |
| `TrashCan` | `trash`, `trash.fill` | 23+1 (also `OPSStyle.Icons.trash` ×9, `.delete` ×6) | Delete |
| `Search` | `magnifyingglass` | 27 (also `OPSStyle.Icons.search` ×22) | Search |
| `Save` | (none — iOS uses checkmark today, per brief) | — | Missing — needs Carbon `Save` |
| `Send` | `paperplane.fill` | 7 | Send |
| `Share` | `square.and.arrow.up` | 6 (also `OPSStyle.Icons.copy` if used) | Share |
| `Copy` | `doc.on.doc`, `doc.on.doc.fill`, `plus.square.on.square` | 4+1+1 (also `OPSStyle.Icons.copy` ×2) | Copy |
| `Download` | `square.and.arrow.down`, `arrow.down.to.line`, `icloud.and.arrow.down` | 8+1+2 | Download |
| `Upload` | `arrow.up.circle`, `arrow.up.circle.fill` | 1+1 | Upload |
| `DocumentImport` | (no literal — `import` covered by `Upload` weak) | — | Import |
| `Renew` | `arrow.triangle.2.circlepath`, `arrow.clockwise` | 7+7 (also `OPSStyle.Icons.sync` ×3) | Refresh / sync |
| `Undo` | `arrow.uturn.backward`, `arrow.uturn.backward.circle.fill` | 7+2 (also `OPSStyle.Icons.undo` ×2) | Undo |
| `Redo` | `arrow.uturn.forward` | 2 | Redo |
| `Reset` | `arrow.counterclockwise` | 1 | Reset |
| `Filter` | `line.3.horizontal.decrease.circle`, `line.3.horizontal.decrease` | 1+1 (also `OPSStyle.Icons.filter` ×3) | Filter |
| `SettingsAdjust` | `slider.horizontal.3` | 1 | Adjust |
| `Archive` | (no literal `archivebox`) | — | Archive |
| `Link` | `link.badge.plus` | 2 | Link |
| `Unlink` | (literal absent) | — | Unlink |
| `Pin` | `pin.fill` | 2 | Pin |
| `ZoomIn` | `arrow.up.left.and.arrow.down.right.magnifyingglass` | 1 | Zoom in |
| `Microphone` | `mic.fill` | 1 | Voice input |
| `Scan` | `camera.viewfinder`, `barcode` (none), `doc.text.viewfinder` | 4+2 | Scan barcode / document |
| `Phone` | `phone.fill`, `phone`, `phone.circle.fill` | 5+2+4 (also `OPSStyle.Icons.phone` ×9, `.phoneFill` ×5) | Call |
| `FolderAdd` | (literal — covered via `OPSStyle.Icons.addProject` ×5) | — | New project |
| `TaskAdd` | (no literal) | — | New task |
| `UserFollow` | `person.badge.plus`, `person.crop.circle.badge.plus` | 2+1 | New client / invite |
| `CategoryNew` | (no literal) | — | New task type |
| `CalendarAdd` | `calendar.badge.plus` | 1 | New event |
| `Subtract` | `person.badge.minus`, `minus` | (Label only)+5 | Remove |
| `AugmentedReality` | `arkit` | 4 | AR scan |
| `Ruler` | `ruler` | 7 (Label only +2) | Measure |
| `RulerAlt` | `antenna.radiowaves.left.and.right` | 6 | Laser meter |
| `Pen` | `pencil.tip` (folded above), `hand.draw.fill` | 1 | Draw / pen |
| `Erase` | (no literal — needs Carbon `Erase`) | — | Eraser |
| `Lasso` | `lasso` | 1 | Lasso |
| `Draw` | `rectangle`, `rectangle.dashed`, `square.dashed` | 2+1+3 | Shape rectangle / region |
| `Cube` | `cube.transparent` | 1 | 3D model |
| `Move` | `arrow.up.and.down.and.arrow.left.and.right`, `arrow.up.and.down`, `arrow.up.arrow.down` | 1+1+2 | Pan / move |
| `Camera` | `camera.rotate`, `camera.metering.unknown` | 1+1 | Camera flip / metering |

### Support A — Status

| Carbon target | SF Symbol(s) covered | Literal call sites | Notes |
|---|---|---|---|
| `CheckmarkFilled` | `checkmark.circle.fill` | 33 (also `OPSStyle.Icons.checkmarkCircleFill` ×23, `.complete` ×6) | Success / complete |
| `Checkmark` | `checkmark`, `checkmark.circle` | 57+6 (also `OPSStyle.Icons.checkmark` ×17) | Checkmark |
| `Incomplete` | `circle` | 2 (also `OPSStyle.Icons.incomplete` if used, `.circle` ×4) | Incomplete |
| `WarningFilled` | `exclamationmark.triangle.fill` | 30 (also `OPSStyle.Icons.alert` ×19, `.exclamationmarkTriangleFill` ×11) | Warning |
| `Warning` | `exclamationmark.triangle` | 9 (also `OPSStyle.Icons.exclamationmarkTriangle` ×2) | Warning outline |
| `ErrorFilled` | `exclamationmark.circle.fill` | 3 (also `OPSStyle.Icons.exclamationmarkCircleFill` ×2) | Error |
| `Error` | `exclamationmark.circle`, `exclamationmark` | 1+1 | Error outline |
| `Misuse` | `xmark.octagon.fill` (no literal — only via `OPSStyle.Icons.error`) | — | Error critical |
| `InformationFilled` | `info.circle.fill` | 2 (also `OPSStyle.Icons.info` ×6) | Info |
| `Information` | `info.circle` | 5 | Info outline |
| `Help` | `questionmark.circle`, `person.fill.questionmark`, `person.crop.circle.badge.questionmark`, `clock.badge.questionmark` | 3+1+1+1 | Help / unknown |
| `Locked` | `lock.fill` | 6 | Locked |
| `Misuse` | (no literal `nosign`) | — | Blocked |
| `FlagFilled` | `flag.fill` | 2 | Flagged |
| `Flag` | (no literal `flag.slash`) | — | Flag off |
| `Trophy` | `checkmark.seal.fill`, `checkmark.seal` | 3+3 (also `OPSStyle.Icons.dealWon`) | Deal won |
| `CloseOutline` | `xmark.seal.fill` (via `dealLost`) | — | Deal lost (weak) |
| `Security` | `person.badge.shield.checkmark`, `shield`, `lock.shield.fill` | 2+1+1 | Shield verified / shield |
| `StarFilled` | `star.fill`, `star.square` | 1+1 | Favorite |
| `DotMark` | (no literal) | — | Status dot |
| `Growth` | `chart.line.uptrend.xyaxis`, `chart.xyaxis.line` | 1+2 | Trending up |
| `Fire` | `flame` | 1 | Hot |
| `Snow` | `flame.slash` | 1 | Cold (slow mover — odd mapping in source) |

### Support B — Wayfinding atoms

| Carbon target | SF Symbol(s) covered | Literal call sites | Notes |
|---|---|---|---|
| `ChevronDown` | `chevron.down` | 26 (also `OPSStyle.Icons.chevronDown` ×15) | |
| `ChevronUp` | `chevron.up` | 4 (also `OPSStyle.Icons.chevronUp` ×6) | |
| `ChevronLeft` | `chevron.left` | 32 (also `OPSStyle.Icons.chevronLeft` ×10, `.back`) | |
| `ChevronRight` | `chevron.right` | 56 (also `OPSStyle.Icons.chevronRight` ×53, `.forward`) | Highest-volume chevron |
| `CaretSort` | `arrow.up.arrow.down`, `chevron.up.chevron.down` | 2+2 | Sort toggle |
| `ArrowLeft` | `arrow.left`, `arrow.backward.square.fill` | 8+1 | Back arrow |
| `ArrowRight` | `arrow.right`, `arrow.right.circle`, `arrow.right.to.line` | 65+2+2 | **Highest-volume symbol overall (65 literals).** Most used CTA arrow |
| `ArrowUp` | `arrow.up` | 1 | Up |
| `ArrowDown` | (no standalone literal) | — | Down |
| `ArrowUpRight` | `arrow.up.right` | 1 | Open / view all |
| `Launch` | `arrow.up.right.square`, `arrow.up.forward.app.fill`, `rectangle.portrait.and.arrow.forward` | 1+1+1 | External link / launch |
| `OverflowMenuHorizontal` | `ellipsis`, `ellipsis.circle` | 8+1 | Overflow |
| `Menu` | `line.3.horizontal` | 2 | Hamburger |
| `Draggable` | (no literal — drag handle pattern uses `line.3.horizontal`) | — | Drag handle |
| `Close` | `xmark`, `xmark.circle`, `xmark.circle.fill` | 44+5+37 (also `OPSStyle.Icons.xmark` ×19, `.close` ×11, `.xmarkCircleFill` ×17) | Close — second highest volume |
| `Maximize` | `arrow.up.left.and.arrow.down.right` | 1 | Expand |
| `Minimize` | `arrow.down.right.and.arrow.up.left` | 1 | Collapse |
| `ArrowRight` (also serves) | `arrow.turn.down.right` | 1 | Sub-flow arrow |

### Support C — Utility

| Carbon target | SF Symbol(s) covered | Literal call sites | Notes |
|---|---|---|---|
| `Renew` | (folded — sync/refresh) | — | Sync animated |
| `Pending` | (no literal) | — | Pending |
| `CloudOffline` | `icloud.slash`, `cloud.slash.fill` | 2+1 | Offline / cloud unavailable |
| `Network_3` / `Wifi` (weak) | `wifi` | 1 | Online (Carbon has no wifi — weak) |
| `CircleDash` | `circle.dotted`, `hourglass` | 1+1 | Loading |
| `Ai` | `sparkles` | 3 (also `OPSStyle.Icons.ai` via Pipeline if added) | AI |
| `Bot` | (no literal) | — | AI agent |
| `Flash` | (no literal `bolt.fill` outside trade pool) | — | Automation |
| `MagicWand` | `wand.and.stars` | 2 | Magic generate |
| `Time` | `clock` | 4 (also `OPSStyle.Icons.clock`) | Clock |
| `TimeFilled` | (folded — `.clockFill`, `.duration`) | — | Duration |
| `Alarm` | (folded — `deadline`, `followUpAlarm`) | — | Deadline |
| `InProgress` | `clock.arrow.circlepath` | 3 (also `OPSStyle.Icons.inProgress`) | In progress |
| `Compass` | (no literal) | — | Directions |
| `LocationCurrent` | (no literal `location.circle`) | — | Use my location |
| `List` | `list.bullet.rectangle` | 1 (also `OPSStyle.Icons.listBullet`) | List view |
| `Grid` | `square.grid.2x2` | 5 | Grid view |
| `DataTable` | (no literal `tablecells`) | — | Table view |
| `Column` | `rectangle.stack.fill` | 1 | Board / column view |
| `Notification` | `bell`, `bell.badge`, `bell.slash`, `bell.slash.fill` | 2+4+1+3 | Notification bell + muted |
| `Chat` | (folded — `message`) | — | Comment |
| `At` | (folded — `mention`) | — | Mention |
| `Logout` | `rectangle.portrait.and.arrow.right` | 3 | Sign out |
| `Idea` | `lightbulb` | 1 | Tip |
| `Education` | `book.fill` | 1 | Learning |
| `Datastore` | `cylinder.fill`, `tray` | 2+1 | Database / storage |
| `Hand` (no Carbon — weak) | `hand.tap` | 1 | Touch gesture hint |
| `View` (alt) | `play.fill` | 1 | Play |
| `TextAlignLeft` | `text.alignleft` | 1 (also `OPSStyle.Icons.description`) | Description / text |
| `TextScale` | `textformat` | 1 | Text format |
| `PlusMinus` (no Carbon) | `plusminus` | 1 | Plus/minus (rare) |
| `ColorPalette` | `paintpalette` | 1 (Label only) | Color picker (weak Carbon match — `ColorPalette`) |
| `Steps` | `stairs` | 1 (Label only) | Steps / multi-level (weak — Carbon has no stairs) |
| `MedicalCharting` | `cross.case.fill` | 1 | Medical case (weak — Carbon `MedicalCharting`) |
| `Star` | (folded — `star.fill`) | — | Star |
| `Stairs` (weak) | `stairs` | (folded) | — |

### Trade pool — `DataModels/TaskType.swift:97-109`

The current trade icon pool (sequential default assignment for task types):

| Index | Current SF Symbol | Concept | Carbon target | Fit |
|---|---|---|---|---|
| 0 | `hammer.fill` | General construction | `Tools` | weak |
| 1 | `wrench.fill` | Service / repair | `Tools` | weak |
| 2 | `paintbrush.fill` | Painting / finishing | `PaintBrush` | exact |
| 3 | `ruler.fill` | Measurement / planning | `Ruler` | exact |
| 4 | `doc.text.fill` | Documentation / quotes | `Document` | exact |
| 5 | `checkmark.circle.fill` | Inspection / completion | `CheckmarkFilled` | exact |
| 6 | `shippingbox.fill` | Materials / delivery | `Box` | close |
| 7 | `bolt.fill` | Electrical | `Lightning` | close |
| 8 | `drop.fill` | Plumbing | **gap** — needs net-new `trade-plumbing` | gap |
| 9 | `house.fill` | General / other | `Home` | exact |

Default task types in `TaskType.createDefaults` use:
- `clipboard.fill` (Site Estimate) → `Document` (exact)
- `doc.text.fill` (Quote/Proposal) → `Document` (exact)
- `shippingbox.fill` (Material Order) → `Box` (close)
- `hammer.fill` (Installation) → `Tools` (weak)
- `magnifyingglass` (Inspection) → `Search` (close)
- `checkmark.circle.fill` (Completion) → `CheckmarkFilled` (exact)

### Expense pool — `Views/Expenses/ExpenseCategorySettingsView.swift:18-23` + `Network/Supabase/Repositories/ExpenseRepository.swift:212-222`

Icon picker pool (`ExpenseCategorySettingsView.iconOptions`):

| Current SF Symbol | Concept | Carbon target | Fit |
|---|---|---|---|
| `tag.fill` | Tag | `Tag` | exact |
| `car.fill` | Vehicle | `Car` | exact |
| `fork.knife` | Meals | `Restaurant` | exact |
| `house.fill` | Property | `Building` | exact |
| `wrench.fill` | Repair / tools | `Tools` | weak |
| `shippingbox.fill` | Materials | `Box` | close |
| `phone.fill` | Phone | `Phone` | exact |
| `laptopcomputer` | Laptop | `Laptop` | exact |
| `airplane` | Travel | `FlightInternational` | exact |
| `fuelpump.fill` | Fuel | `GasStation` | exact |
| `creditcard.fill` | Credit card | `Wallet` | close (no credit-card glyph) |
| `cart.fill` | Cart | `ShoppingCart` | exact |
| `bolt.fill` | Electrical | `Lightning` | close |
| `wifi` | Wifi / online | `Network_3` | weak (no wifi) |
| `printer.fill` | Office / printer | `Printer` | exact |
| `person.fill` | Person | `User` | exact |
| `building.fill` | Building | `Building` | exact |

Seeded default expense categories (`ExpenseRepository.seedDefaultCategories`):
- `shippingbox.fill` → `Box`
- `person.fill` → `User`
- `wrench.and.screwdriver.fill` → `Tools` (weak)
- `fuelpump.fill` → `GasStation`
- `bed.double.fill` → **gap** (no Carbon hotel/bed icon — use `Building` weak, or `Hospitality` per Carbon)
- `person.2.fill` → `UserMultiple`
- `doc.text.fill` → `Document`
- `paperclip` → `Attachment`
- `ellipsis.circle.fill` → `OverflowMenuHorizontal`

### Misc / role badges

| Location | Current SF Symbol | Carbon target |
|---|---|---|
| `Onboarding/Components/InviteRolePicker.swift:42` — office role | `desktopcomputer` | `Laptop` |
| `Views/Settings/Organization/ManageTeamView.swift:357` — office section | `desktopcomputer` | `Laptop` |
| `Views/Settings/IntegrationsSettingsView.swift:55` — banking | `building.columns.fill` | `Bank` |
| `Views/Settings/IntegrationsSettingsView.swift:64` — environment | `leaf.fill` | `Tree` |
| `Onboarding` — Apple sign-in (`apple.logo` ×5) | `apple.logo` | **RESERVED — keep as Apple-supplied** |

---

## Tab bar callout — 7 root tabs (asset-catalog priority)

The 7 iOS tab bar icons live in `Views/MainTabView.swift:215-247`. These are the **first** Carbon custom symbols the user must author and drop into `Assets.xcassets` as SF Symbols custom symbols. Without these, the tab bar cannot render with Carbon.

Per the brief: "The iOS tab bar already signals the active tab with a steel tint (`#6F94B0`) + a 3pt sliding underline; inactive is grey. That treatment is sufficient — use Carbon's single style for all 7 tabs, no filled variants required."

| Tab order | Current SF Symbol | Wizard step ID | Carbon target | Brief slug | Notes |
|---|---|---|---|---|---|
| 1 | `house.fill` | `welcome_home` | `Dashboard` (per brief — decide vs `Home`) | `nav-dashboard` | Open item in brief: house vs layout-grid |
| 2 (conditional) | `point.3.connected.trianglepath.dotted` | `welcome_leads` | `Flow` | `nav-pipeline` | Open item in brief: dotted-triangle vs git-branch — pick `Flow` |
| 3 (conditional) | `chart.line.uptrend.xyaxis` | `welcome_books` | `Finance` | `nav-finance` | |
| 4 | `briefcase.fill` | `welcome_job_board` | `Portfolio` | `nav-jobs` | Split #6 — distinct from `Folder` (project record) |
| 5 (conditional) | `square.stack.3d.up.fill` | `welcome_catalog` | `Categories` | `nav-catalog` | |
| 6 | `calendar` | `welcome_schedule` | `Calendar` | `nav-calendar` | Distinct from `date` data type |
| 7 | `gearshape.fill` | `welcome_settings` | `Settings` | `nav-settings` | |

`Views/Components/Common/CustomTabBar.swift:221-223` also references `house.fill` and `gearshape.fill` in a preview / fallback path — same Carbon swap applies.

**Required iOS deliverable:** 7 SF Symbols custom-symbol `.svg` files (one per Carbon target above), added to `OPS/Assets.xcassets` under a `Symbols/` group, with template variants (`Regular`, optionally `Medium`) authored at the SF Symbols app's 28pt tab-bar reference size.

---

## Gaps / weak matches

Flagged for design action. The brief already calls out the trade-pool gaps; this section also surfaces specialized iOS one-offs (AR / Deck Builder / measurement) that are weakly served by Carbon.

### Net-new draws (per brief — must be designed)

These 8 trade pool glyphs have **no usable Carbon match** and must be drawn fresh (per brief § Residual design work). They will appear in the trade-type picker pool inside `TaskType.swift` and any in-app task-type icon picker.

| Slug | Currently uses | Where in iOS |
|---|---|---|
| `trade-plumbing` | `drop.fill` | `DataModels/TaskType.swift:107` |
| `trade-roofing` | (not yet in pool) | — |
| `trade-flooring` | (not yet in pool) | — |
| `trade-masonry` | (not yet in pool) | — |
| `trade-drywall` | (not yet in pool) | — |
| `trade-concrete` | (not yet in pool) | — |
| `trade-cleaning` | (not yet in pool) | — |
| `trade-windows-doors` | (not yet in pool) | — |

### Weak Carbon matches (acceptable but flag for review)

| SF Symbol | Carbon target | Why weak | Where in iOS |
|---|---|---|---|
| `hammer.fill` / `hammer` / `wrench.fill` | `Tools` | Generic tools, not the specific trade | TaskType pool, expense pool |
| `wrench.and.screwdriver.fill` | `ToolBox` | Generic toolbox | `ExpenseRepository.swift:215` |
| `bed.double.fill` | `Hospitality` (or `Building` weak) | No bed/hotel icon | `ExpenseRepository.swift:217` |
| `wifi` | `Network_3` | Carbon has no wifi glyph | `ExpenseCategorySettingsView.swift:22`; online status |
| `creditcard.fill` / `creditcard` | `Wallet` | Carbon has no credit-card glyph | Expense pool, billing settings |
| `cross.case.fill` | `MedicalCharting` | Medical-case → Carbon's closest is a stethoscope | 1 site |
| `paintpalette` | `ColorPalette` | Generic palette, not paint-specific | 1 site (Label) |
| `stairs` | (no Carbon stairs) | Carbon has no stairs icon | 1 site (Label) |
| `plusminus` | (no Carbon plusminus) | No combined glyph | 1 site |

### Specialized iOS one-offs — Deck Builder / AR / measurement tools

These are iOS-exclusive features (AR perimeter measurement, deck design canvas, photo markup). The brief lists Carbon mappings; flagged here so the user knows which need attention.

| SF Symbol | Concept | Carbon target | Fit | Where |
|---|---|---|---|---|
| `arkit` (×4) | AR scan | `AugmentedReality` | exact | `DeckBuilder/AR/*.swift` |
| `antenna.radiowaves.left.and.right` (×6) | Laser meter / radio device | `RulerAlt` (also `WirelessCheckout`) | close | DeckBuilder, laser meter UI |
| `cube.transparent` (×1) | 3D model preview | `Cube` | close | DeckBuilder |
| `ruler` (×7, Label ×2) | Measure tool | `Ruler` | exact | DeckBuilder, AR measurement |
| `lasso` (×1) | Lasso select | `Lasso` | exact | DeckBuilder canvas |
| `rectangle` / `rectangle.dashed` / `square.dashed` (2+1+3) | Draw shape / region | `Draw` | weak | DeckBuilder canvas |
| `pencil.tip` (×1, plus `OPSStyle.Icons.pencilTip`) | Annotate / fine pencil | `Pen` | weak | Photo markup |
| `pencil.and.list.clipboard` (×1) | Clipboard with edits | `Edit` (or `DocumentTasks`) | weak | DeckBuilder |
| `hand.draw.fill` (×1) | Freehand draw | `Pen` (or `Draw`) | weak | DeckBuilder |
| `hand.tap` (×1) | Touch / tap gesture hint | (no Carbon hand-tap) | gap | Tutorial / hint UI |
| `camera.rotate` (×1) | Flip front/back camera | `Camera` (no flip variant) | weak | Camera UI |
| `camera.metering.unknown` (×1) | Camera metering | `Camera` | weak | Camera UI |
| `arrow.right.and.line.vertical.and.arrow.left` (×4) | Push/pull horizontal | `MoveRight` / `Move` | weak | DeckBuilder transforms |
| `arrow.triangle.merge` (×1, Label) | Merge | `Merge` | exact | (rare) |
| `arrow.triangle.branch` (×4 + Label) | Branch / dependency | `FlowConnection` (or `Branch`) | close | Pipeline / task dependencies |
| `certificate` (×1) | Certification | `Certificate` | exact | Settings |
| `cylinder.fill` (×2) | Database | `Datastore` | exact | Settings → Storage |
| `book.fill` (×1) | Learning | `Education` | exact | Settings |
| `hammer.circle.fill` (×2) | Developer settings | `Code` | close | Settings → Developer |
| `tray` (×1) | Storage | `Datastore` | exact | Settings |
| `chart.bar.doc.horizontal.fill` (via `OPSStyle.Icons.pipelineChart`) | Pipeline chart | `Flow` / `ChartBar` | close | Pipeline UI |

### Reserved — do NOT redesign (per brief)

| SF Symbol | Sites | Why reserved |
|---|---|---|
| `apple.logo` | 5 (`LandingView.swift:619`, `LoginScreen.swift:193`, `SocialAuthButton.swift:65`, `MinimalSignupView.swift:69`, `WelcomeView.swift:351`) | Apple-supplied for Sign in with Apple — legally locked |

(Google "G" sign-in glyph is referenced as an asset elsewhere — not in the SF Symbol inventory.)

---

## File paths — high-leverage targets

The single highest-leverage swap is the OPSStyle.Icons enum at:

- `OPS/Styles/OPSStyle.swift` — lines 594-750 (the entire `enum Icons` block)

The next-highest call-site density is in:

- `Views/MainTabView.swift:217-244` — the 7 root tab bar icons
- `Tutorial/TutorialFlowView.swift` and `Tutorial/V2/TutorialFlowViewV2.swift` — heavy use of `checkmark`, `arrow.right`, `chevron.right`
- `DeckBuilder/Views/*` and `DeckBuilder/AR/*` — most of the specialized one-offs
- `Styles/Components/ButtonStyles.swift`, `FormInputs.swift`, `OPSComponents.swift` — render the bulk of structural chevrons / xmarks
- `Views/JobBoard/*`, `Views/Settings/*` — heavy `chevron.right`, `xmark.circle.fill` usage
- `DataModels/TaskType.swift:97-109` — trade pool array (needs net-new trade glyphs)
- `Views/Expenses/ExpenseCategorySettingsView.swift:18-23` — expense pool array
- `Network/Supabase/Repositories/ExpenseRepository.swift:212-222` — seeded expense category icons

---

## Next steps (post-checklist)

1. **User authors Carbon custom symbols** in the SF Symbols app (one `.svg` per unique Carbon target above) and adds them to `OPS/Assets.xcassets/Symbols/`. Start with the 7 tab bar icons (ship-blocking) + the 35 most-used symbols (`Add`, `Close`, `Checkmark`, `ChevronRight`, `ArrowRight`, etc.).
2. **Engineering swaps the `OPSStyle.Icons` enum values** to point at the new asset names (one-line edits, 92 changes, drives 496 call sites).
3. **Engineering does a search-and-replace pass** for the 119 literal-string call sites that don't yet route through `OPSStyle.Icons`. Recommended: collapse them into `OPSStyle.Icons` cases during the swap so future swaps are one-line.
4. **Design** delivers the 8 net-new trade glyphs as a single bespoke pool, drawn to match Carbon's 24px grid / stroke weight.
5. **Verify** at 16/20/24/28px in iOS — the brief's 12px floor doesn't apply to iOS (web only).
