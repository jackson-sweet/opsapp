# Schedule Full-Bleed Viewport Design

## Problem

The Schedule tab's week view stops above the bottom of the screen instead of
continuing behind the floating global tab bar. The result looks like the
calendar has been cut short and gives the operator less usable schedule space.

## Root Cause

`MainTabView` already presents tab content full bleed behind the overlaid
`CustomTabBar`. `DayPageView` also already places tab-bar clearance inside its
vertical scroll content so the final card can scroll above the bar.

`ScheduleView` additionally applies 90 points of bottom padding to the entire
week-view calendar container. That outer padding shortens the scroll viewport
and duplicates the clearance already owned by `DayPageView`.

## Product Decision

- The week-view viewport reaches the physical bottom edge behind the tab bar.
- The final schedule content retains internal tab-bar clearance and remains
  reachable.
- The expanded month retains only its existing wizard-instruction clearance
  while the wizard is active.
- No copy, color, typography, icon, or motion changes are introduced.

## Layout Contract

The viewport and its content have separate responsibilities:

1. `ScheduleView` owns whether the calendar viewport is full height.
2. `DayPageView` owns clearance inside the scrollable day content.
3. The overlaid `CustomTabBar` remains visually and interactively above both.

This follows the OPS mobile navigation model: the tab bar floats over the
canvas, while scroll content includes enough trailing space to remain usable.

## Verification

- A focused unit test covers all Schedule viewport modes and proves week mode
  has zero outer bottom inset.
- Existing internal day-content clearance remains unchanged.
- A focused simulator test build verifies the real target compiles and passes.
- Design-system audit confirms the fix adds no hardcoded visual values.
