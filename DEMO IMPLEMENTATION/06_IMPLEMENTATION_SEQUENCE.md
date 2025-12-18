# IMPLEMENTATION SEQUENCE

Ordered build plan with dependencies, parallelization opportunities, and testing checkpoints.

---

## PHASE 0: MODEL UPDATES (Prerequisite)

### 0.1 Add Tutorial Completion Tracking Field
**Build Order:** Sequential
**Estimated Files:** 3 modifications

| Step | File | Changes |
|------|------|---------|
| 0.1.1 | `OPS/DataModels/User.swift` | Add `hasCompletedAppTutorial: Bool = false` property |
| 0.1.2 | `OPS/Network/API/BubbleFields.swift` | Add `hasCompletedAppTutorial` to `BubbleFields.User` |
| 0.1.3 | `OPS/Network/DTOs/UserDTO.swift` | Add `hasCompletedAppTutorial: Bool?` field + mapping |

**Testing Checkpoint 0:**
- [ ] User model compiles with new field
- [ ] BubbleFields constant exists
- [ ] UserDTO maps field correctly from API
- [ ] Field syncs to Bubble on user update

---

## PHASE 1: FOUNDATION (Must Build First)

### 1.1 Environment & State Core
**Build Order:** Sequential
**Estimated Files:** 3

| Step | File | Dependencies | Description |
|------|------|--------------|-------------|
| 1.1.1 | `TutorialEnvironment.swift` | None | Environment keys for tutorialMode |
| 1.1.2 | `TutorialPhase.swift` | None | Phase enum with tooltip text |
| 1.1.3 | `TutorialStateManager.swift` | 1.1.1, 1.1.2, Phase 0 | State management class |

**Testing Checkpoint 1:**
- [ ] Can compile all three files
- [ ] TutorialStateManager can start/advance/complete
- [ ] Phase tooltips return correct text
- [ ] Stopwatch calculates time correctly

---

### 1.2 Demo Data Constants
**Build Order:** Can parallelize
**Estimated Files:** 5

| Step | File | Dependencies | Description |
|------|------|--------------|-------------|
| 1.2.1 | `DemoIDs.swift` | None | All DEMO_ prefix IDs |
| 1.2.2 | `DemoTeamMembers.swift` | 1.2.1 | Team member data structs |
| 1.2.3 | `DemoClients.swift` | 1.2.1 | Client data structs |
| 1.2.4 | `DemoTaskTypes.swift` | 1.2.1 | Task type data structs |
| 1.2.5 | `DemoProjects.swift` | 1.2.1-1.2.4 | Project + task data structs |

**Testing Checkpoint 2:**
- [ ] All demo data compiles
- [ ] DemoProjects references correct IDs
- [ ] Date calculations work correctly

---

## PHASE 2: DATA LAYER

### 2.1 Demo Data Manager
**Build Order:** Sequential (depends on Phase 1)
**Estimated Files:** 1

| Step | File | Dependencies | Description |
|------|------|--------------|-------------|
| 2.1.1 | `TutorialDemoDataManager.swift` | Phase 1 complete | Seeding and cleanup logic |

**Testing Checkpoint 3:**
- [ ] Can seed all demo data to SwiftData
- [ ] All relationships created correctly
- [ ] Task statuses calculated from dates
- [ ] Project statuses computed from tasks
- [ ] Can cleanup all demo data
- [ ] No orphan entities after cleanup

---

## PHASE 3: UI COMPONENTS

### 3.1 Core Container Views
**Build Order:** Can parallelize
**Estimated Files:** 3

| Step | File | Dependencies | Description |
|------|------|--------------|-------------|
| 3.1.1 | `TutorialContainerView.swift` | None | 80% scaled container |
| 3.1.2 | `TutorialOverlayView.swift` | None | Dark overlay with cutout |
| 3.1.3 | `TutorialTooltipView.swift` | TypewriterText exists | Tooltip using TypewriterText |

**Testing Checkpoint 4:**
- [ ] Container scales content to 80%
- [ ] Container positions content correctly
- [ ] Overlay renders dark mask
- [ ] Overlay cutout reveals target area
- [ ] Cutout animates smoothly
- [ ] Tooltip displays and animates text

---

### 3.2 Animation Components
**Build Order:** Can parallelize
**Estimated Files:** 2

| Step | File | Dependencies | Description |
|------|------|--------------|-------------|
| 3.2.1 | `TutorialSwipeIndicator.swift` | None | Shimmer animation |
| 3.2.2 | `TutorialCompletionView.swift` | 1.1.3 | Completion screen |

**Testing Checkpoint 5:**
- [ ] Swipe indicator animates in all 4 directions
- [ ] Shimmer repeats correctly
- [ ] Completion shows time when < 3 min
- [ ] Completion hides time when >= 3 min
- [ ] "LET'S GO" button triggers callback

---

### 3.3 Utility Components
**Build Order:** Can parallelize
**Estimated Files:** 2

| Step | File | Dependencies | Description |
|------|------|--------------|-------------|
| 3.3.1 | `TutorialHaptics.swift` | None | Haptic feedback helpers |
| 3.3.2 | `PreferenceKeys.swift` | None | Frame capture utilities |

---

## PHASE 4: VIEW MODIFICATIONS

### 4.1 Existing View Updates
**Build Order:** Can parallelize (no dependencies between views)
**Estimated Files:** 9 modifications

| Step | File | Changes |
|------|------|---------|
| 4.1.1 | `JobBoardDashboard.swift` | Add tutorialMode, filter projects |
| 4.1.2 | `ProjectFormSheet.swift` | Add tutorialMode, filter clients/users |
| 4.1.3 | `TaskFormSheet.swift` | Add tutorialMode, filter task types/users |
| 4.1.4 | `FloatingActionMenu.swift` | Add tutorialMode, disable non-project actions |
| 4.1.5 | `JobBoardProjectListView.swift` | Add tutorialMode, filter projects |
| 4.1.6 | `HomeView.swift` | Add tutorialMode, filter projects |
| 4.1.7 | `MonthGridView.swift` | Add tutorialMode, filter events, disable controls |
| 4.1.8 | `ProjectDetailsView.swift` | Add tutorialMode |
| 4.1.9 | `UniversalJobBoardCard.swift` | Add tutorialMode |

**Testing Checkpoint 6:**
- [ ] Each view compiles with tutorialMode
- [ ] Each view filters to DEMO_ data when tutorialMode=true
- [ ] Each view shows all data when tutorialMode=false
- [ ] Disabled controls are visually dimmed
- [ ] Gestures still work in tutorial mode

---

## PHASE 5: FLOW ORCHESTRATION

### 5.1 Tutorial Flows
**Build Order:** Sequential (Company first, Employee extends)
**Estimated Files:** 2

| Step | File | Dependencies | Description |
|------|------|--------------|-------------|
| 5.1.1 | `CompanyTutorialFlow.swift` | Phases 1-4 | Company creator flow |
| 5.1.2 | `EmployeeTutorialFlow.swift` | 5.1.1 | Employee flow (shares calendar steps) |

**Testing Checkpoint 7:**
- [ ] Company flow progresses through all phases
- [ ] Cutout positions update correctly per phase
- [ ] Swipe indicators show at correct phases
- [ ] Phase transitions trigger on correct actions
- [ ] Employee flow progresses correctly
- [ ] Employee flow assigns user to demo tasks

---

### 5.2 Root View
**Build Order:** After flows
**Estimated Files:** 1

| Step | File | Dependencies | Description |
|------|------|--------------|-------------|
| 5.2.1 | `TutorialRootView.swift` | 5.1.1, 5.1.2 | Main orchestrator |

**Testing Checkpoint 8:**
- [ ] Root view seeds demo data on appear
- [ ] Root view starts correct flow for user type
- [ ] Root view shows completion when done
- [ ] Root view cleans up demo data on dismiss
- [ ] onComplete callback fires correctly

---

## PHASE 6: INTEGRATION

### 6.1 Onboarding Integration
**Build Order:** After Phase 5
**Estimated Files:** 2 modifications

| Step | File | Changes |
|------|------|---------|
| 6.1.1 | `OnboardingManager.swift` | Add `.tutorial` screen case |
| 6.1.2 | `OnboardingContainer.swift` | Route to TutorialRootView |

**Testing Checkpoint 9:**
- [ ] Tutorial appears after Ready screen
- [ ] Tutorial appears before Welcome Guide
- [ ] Completing tutorial advances to Welcome Guide
- [ ] Correct flow type based on user type

---

## PARALLELIZATION OPPORTUNITIES

### Can Build in Parallel (Same Sprint)

**Group A:** Foundation
- 1.1.1 TutorialEnvironment
- 1.2.1-1.2.4 Demo data constants (all except DemoProjects)

**Group B:** UI Components (After Phase 1)
- 3.1.1 TutorialContainerView
- 3.1.2 TutorialOverlayView
- 3.1.3 TutorialTooltipView
- 3.2.1 TutorialSwipeIndicator
- 3.2.2 TutorialCompletionView
- 3.3.1 TutorialHaptics
- 3.3.2 PreferenceKeys

**Group C:** View Modifications (After Phase 1)
- All 4.1.x modifications can be done in parallel

---

## TESTING CHECKPOINTS SUMMARY

| Checkpoint | Phase | Verification |
|------------|-------|--------------|
| 1 | Foundation | State management works |
| 2 | Demo Data | Constants compile, dates calculate |
| 3 | Data Layer | Seeding/cleanup works correctly |
| 4 | Container UI | Scaling, overlay, tooltip work |
| 5 | Animations | Swipe indicator, completion view |
| 6 | View Mods | All views support tutorialMode |
| 7 | Flows | Phase progression works |
| 8 | Root View | Full orchestration works |
| 9 | Integration | Onboarding flow complete |

---

## RISK AREAS

### High Risk
1. **Touch mapping in scaled container** - Touches may not map correctly
   - Mitigation: Test early with 80% scale
   - Fallback: Adjust scale factor if needed

2. **Demo data relationships** - SwiftData relationships are complex
   - Mitigation: Test seeding isolated before UI
   - Fallback: Simplify relationships if needed

3. **Calendar view integration** - Calendar is composed of many subviews
   - Mitigation: Identify exact view structure first
   - Fallback: Wrap at higher level if needed

### Medium Risk
1. **Phase timing** - Auto-progression timing may feel off
   - Mitigation: Make delays configurable
   - Fallback: Let user control progression

2. **Overlay cutout positioning** - Frame capture may be tricky
   - Mitigation: Use GeometryReader carefully
   - Fallback: Fixed positions as fallback

### Low Risk
1. **Haptics** - Straightforward implementation
2. **TypewriterText reuse** - Already exists and works
3. **Basic state management** - Standard ObservableObject pattern

---

## MINIMUM VIABLE IMPLEMENTATION

If time constrained, build these in order for MVP:

1. TutorialEnvironment + TutorialPhase + TutorialStateManager
2. DemoIDs + simplified demo data (fewer projects)
3. TutorialDemoDataManager (seed only)
4. TutorialContainerView + TutorialOverlayView + TutorialTooltipView
5. View modifications (at minimum: JobBoardDashboard, ProjectFormSheet)
6. CompanyTutorialFlow (core steps only)
7. TutorialRootView
8. OnboardingManager/Container integration

Skip for MVP (add later):
- TutorialSwipeIndicator (use text hints instead)
- TutorialCompletionView (simple text view)
- EmployeeTutorialFlow (focus on Company first)
- Full demo data (use 3-5 projects instead of 15)
