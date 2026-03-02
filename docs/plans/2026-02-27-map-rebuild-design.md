# Home Screen Map Rebuild — Design Document

**Date:** 2026-02-27
**Scope:** Full replacement of the existing MapKit-based home screen map with Mapbox, custom dark styling, live team tracking, turn-by-turn navigation, geofencing, and speed-adaptive zoom.

---

## SDK

- **Mapbox Maps SDK v11** — map renderer, custom dark tiles, annotations
- **Mapbox Navigation SDK v3** — turn-by-turn routing with voice guidance
- **Supabase Realtime** — live crew location broadcasting
- **CoreLocation** — GPS, heading, geofence region monitoring

Free tier: ~50K MAU (maps), navigation billed per trip (30s grace period).

---

## Map Style

Custom dark style built in Mapbox Studio. Matches the OPS interface design system (`#0A0A0A` near-black).

| Element | Color | Notes |
|---------|-------|-------|
| Land | `#050505` | Near-black |
| Water | `#0D0D0D` | Matches surface dark |
| Primary roads | `#1A1A1A` | Faint lines |
| Secondary roads | `#111111` | Fainter |
| Buildings | `#0D0D0D` fill, `#1A1A1A` stroke | Subtle outlines |
| Road labels | White @ 50% opacity | Font: Mohave > Kosugi > monospace |
| POIs | Hidden | Clean field map |
| Parks/green | `#0A0F0A` | Near-invisible |

No map type switching. One dark style, always. No satellite/hybrid toggle.

---

## Layout

Full-screen map extending behind status bar and tab bar. All UI floats on the map as frosted glass overlays.

```
+-------------------------------------+
| [ OPS HEADER ]       frosted glass  |
|------------------------------------|
| [ TODAY ]  [ ALL PROJECTS ]  chips  |
|                                     |
|           MAPBOX MAP                |
|      o crew    o project            |
|                                     |
|   o crew         o project          |
|                                     |
|                        [+] [O]      |
|------------------------------------|
| [ TAB BAR ]                         |
+-------------------------------------+
```

### All Overlay Surfaces

Every floating element uses the same material:
- Background: `rgba(10, 10, 10, 0.70)`
- Backdrop blur: `20px`, saturate `1.2` (iOS `ultraThinMaterial`)
- Border: 1px white @ 8% opacity
- Radius: 4pt
- No shadows (design system: borders-only depth on dark backgrounds)

### Map Load State

Solid `#0A0A0A` background before tiles load. No spinner, no loading text. Pins render once tiles are ready.

---

## Annotations

### Project Pins

- **Dot**: 12pt circle, solid white fill
- **Ring**: 2px, pipeline status color, 2pt clear gap between ring and dot
- **Label above**: project name, Kosugi ~11pt, white @ 80% opacity
- **Selected state**: ring brightens, label goes full white
- **No icon inside the dot**

Pipeline status colors:
| Status | Color |
|--------|-------|
| RFQ | `#BCBCBC` |
| Estimated | `#B5A381` |
| Accepted | `#9DB582` |
| In Progress | `#8195B5` |
| Completed | `#B58289` |
| Closed | `#E9E9E9` |
| Archived | `#A182B5` |

### Crew Dots

- **Dot**: 10pt circle, solid white fill
- **Ring**: 2px, status color, 2pt clear gap between ring and dot
- **Label above**: first name only, Kosugi ~11pt, white @ 80% opacity
- **No heading indicator** (dot too small)

Crew status colors:
| Status | Color | Condition |
|--------|-------|-----------|
| On-site | `#A5B368` (success) | Within 100m of a job |
| En route / moving | `#C4A868` (alert) | Speed > 2 m/s |
| Idle | `#8E8E93` (inactive) | No update for >5 min |

### Visibility

- All org members see all other org members' dots. No role-based filtering.
- Crew dots always visible regardless of project filter.

---

## Filter Chips

Two mutually exclusive chips below the header, left-aligned:

- `[ TODAY ]` — active by default. Shows only projects with tasks scheduled today.
- `[ ALL PROJECTS ]` — shows full active pipeline.

Styling:
- Inactive: `#141414` fill, 1px white @ 10% border, `#999999` text, Kosugi ALL CAPS
- Active: `#141414` fill, `#597794` accent border, white text, Kosugi ALL CAPS
- Radius: 3pt

---

## Tap Interactions

### Tap Project Pin — Slide-Up Card

Slides up from bottom edge. Frosted glass. Left-aligned content:

```
PROJECT NAME                          Kosugi ALL CAPS, white
123 Main Street, City                 Mohave Light, #999999
----------------------------------------------  1px white @ 10%
TODAY'S TASKS                         Kosugi ALL CAPS, #999999
  * Install electrical panel          Mohave, white, status dot
  * Run conduit to junction box       Mohave, white, status dot
----------------------------------------------  1px white @ 10%
CREW                                  Kosugi ALL CAPS, #999999
  Mike K. / Jake S.                   Mohave, white
----------------------------------------------
[ NAVIGATE ]  [ DETAILS ]            Side by side
```

- NAVIGATE: solid white fill, dark text, Kosugi ALL CAPS, 3pt radius (primary CTA)
- DETAILS: ghost button, 1px white @ 10% border, white text, Kosugi ALL CAPS
- Swipe down or tap empty map to dismiss

### Tap Crew Dot — Tooltip Card

Small frosted card near the tapped dot:

```
MIKE KOWALSKI                         Kosugi ALL CAPS, white
Install electrical panel          >   Mohave, #597794 accent, tappable
  at 123 Main St                      Mohave Light, #999999
Updated 2 min ago                     Mohave Light, #666666
----------------------------------------------
[ CALL ]    [ MESSAGE ]               Ghost buttons, SF Symbol icons
```

- Project line is tappable — right chevron on trailing edge, accent color. Navigates to project detail view.
- If no assignment: "No tasks assigned" in `#666666`, not tappable.
- CALL / MESSAGE: ghost buttons with `phone.fill` / `message.fill` SF Symbol icons.
- Tap outside dismisses.

### Tap Empty Map

Dismisses any open card or tooltip.

---

## Navigation Mode

Triggered by tapping NAVIGATE on a project card.

### Entry Transition

1. Project card dismisses downward
2. Mapbox Navigation SDK calculates route
3. Route line draws on: `#597794` accent, 4pt width, slightly translucent
4. Camera animates to 3D perspective (45deg pitch, heading-locked, 500ms ease-in-out)
5. Navigation header slides down from top

### Navigation Header

Frosted glass bar pinned below status bar:

```
+---------------------------------------------+
|  <- Turn right on Oak Avenue       0.3 MI   |  Mohave / #999999
|---------------------------------------------|
|  12 MIN        4.2 MI        1:45 PM        |  Kosugi ALL CAPS
|  TIME          DISTANCE      ARRIVAL         |  Kosugi, #666666
+---------------------------------------------+
```

- Turn icon: SF Symbol matching maneuver (left turn, right turn, merge, etc.)
- Instruction: Mohave Regular, white
- Distance to turn: Mohave Light, `#999999`, trailing edge
- Bottom row: three equal columns, live-updating values
- Labels below each value: Kosugi `#666666`
- Speaker icon (trailing edge, top row): toggle voice guidance on/off

### Map Controls During Navigation

Right side, vertically stacked, 44pt frosted glass circles:
- **Re-center** (`location.fill`) — appears only when user pans away
- **Route overview** (`arrow.up.left.and.arrow.down.right`) — fits entire route in view
- **End navigation** (`xmark`) — stops navigation, returns to browse mode

### Camera Behavior

3D follow mode: 45deg pitch, heading-locked to GPS course.

Speed-adaptive zoom:
| Speed | Zoom Distance |
|-------|---------------|
| Stationary/walking (<2 m/s) | 500m |
| Urban (2-10 m/s) | 1000m |
| Suburban (10-25 m/s) | 2000m |
| Highway (25+ m/s) | 3500m |

- All zoom transitions: 1.0s ease-in-out
- User pans: follow mode disengages, re-center button appears
- Tap re-center: 600ms animate back to follow

### Arrival

- Within 30m of destination: header transitions to "ARRIVED / Project Name"
- Camera zooms in close, pitch returns to 0deg (top-down)
- After 3 seconds, navigation mode auto-dismisses to browse

---

## Geofencing

### Region Monitoring

- Monitor nearest 18 job sites (iOS limit: 20, reserve 2)
- 100m radius per site
- Recalculate monitored set on app launch and significant location changes
- Requires `Always` location permission for background monitoring

### Arrival Banner

On entering geofence, small frosted banner slides down below header:

```
+---------------------------------------------+
|  * ARRIVED AT 123 Main St                   |
|  [ CLOCK IN ]                   Dismiss >   |
+---------------------------------------------+
```

- CLOCK IN: solid white button (primary CTA)
- Dismiss: text-only, `#999999`
- Auto-dismisses after 15 seconds if no interaction
- Does not block navigation header

### Departure Banner

On exiting geofence (only if clocked in at that site):

```
+---------------------------------------------+
|  * LEAVING 123 Main St                      |
|  [ CLOCK OUT ]                  Dismiss >   |
+---------------------------------------------+
```

Same styling as arrival banner.

### Permission Flow

If `Always` location not granted, show pre-prompt explanation before system dialog:
- Dark background, left-aligned text
- Mohave body copy explaining shift-only tracking
- `ENABLE LOCATION` solid white CTA + `NOT NOW` ghost text

---

## Live Team Tracking — Data Flow

### Broadcasting (crew device, when clocked in)

- Channel: Supabase Realtime broadcast `crew-locations:{orgId}`
- Frequency: every 10s when moving (speed > 1 m/s), every 60s when stationary
- Payload: lat, lng, heading, speed, accuracy, timestamp, battery level
- Persistence: upsert to `crew_locations` table (one row per user)
- When clocked out: stop broadcasting entirely

### Receiving (all org members)

- Subscribe to org broadcast channel on map appear
- Each update: animate crew dot to new position (300ms ease-in-out)
- No update for >5 min: ring transitions to gray (idle)
- On app open: query `crew_locations` for initial state

### Adaptive GPS Accuracy (battery)

| Speed | Distance Filter | Accuracy |
|-------|----------------|----------|
| Driving (>10 m/s) | 10m | nearestTenMeters |
| Walking (1-10 m/s) | 20m | nearestTenMeters |
| Stationary (<1 m/s) | 100m | hundredMeters |

### Noise Rejection

Discard updates where:
- `horizontalAccuracy` > 50m
- Timestamp > 10s stale
- Coordinate identical to previous

### Privacy

- Broadcast only when clocked in (not 24/7)
- In-app Settings toggle to disable tracking entirely
- Crew can view their own location history
- Raw GPS data auto-deleted after 90 days

---

## Map Controls (Browse Mode)

### Buttons

Right side, vertically stacked, 44pt frosted glass circles:
- **Re-center** (`location.fill`) — appears after user pans
- **Orientation toggle** (`location.north.line.fill` / `location.heading.line.fill`) — north-up vs course-up
  - Inactive mode: white icon
  - Active (course-up): `#597794` accent icon

### Gestures

All standard Mapbox gestures:
- Pinch: zoom
- Pan: scroll (disengages auto-center)
- Double tap: zoom in
- Two-finger tap: zoom out
- Rotate: two-finger twist
- Tilt: two-finger drag up/down

### Auto-Center

- On load: center on user, fit today's pins in view
- If no pan for 10 seconds: gently re-center (300ms ease-in-out)
- During navigation: always auto-center unless manually panned

---

## Dead Code to Remove

The rebuild replaces all of the following (delete entirely):

- `Map/Views/MapView.swift` (old SwiftUI Map)
- `Map/Views/MapContainer.swift`
- `Map/Views/SafeMapContainer.swift`
- `Map/Views/MapControlsView.swift`
- `Map/Views/MapViewAlternative.swift`
- `Map/Views/NavigationView.swift` (MapNavigationView)
- `Map/Views/ProjectDetailsCard.swift`
- `Map/Views/ProjectMarkerPopup.swift`
- `Map/Core/MapCoordinator.swift`
- `Map/Core/NavigationEngine.swift`
- `Map/Core/KalmanHeadingFilter.swift`
- `Map/Core/LocationService.swift`
- `Views/Components/Map/ProjectMapView.swift`
- `Views/Components/Map/MiniMapView.swift`
- `Views/Components/Map/ProjectMapAnnotation.swift`
- `Navigation/NavigationBanner.swift`
- `Navigation/PersistentNavigationHeader.swift`
- `Utilities/DeviceHeadingManager.swift`

Keep and refactor:
- `Utilities/LocationManager.swift` — extend with adaptive accuracy and broadcast
- `Utilities/InProgressManager.swift` — replace with new navigation state, or remove if redundant

---

## Database Schema (Supabase)

```sql
-- Current crew positions (one row per member, upserted)
CREATE TABLE crew_locations (
    user_id UUID PRIMARY KEY REFERENCES users(id),
    org_id UUID NOT NULL,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    accuracy DOUBLE PRECISION,
    battery_level REAL,
    is_background BOOLEAN DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Historical location log (append-only, 90-day retention)
CREATE TABLE location_history (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    org_id UUID NOT NULL,
    session_id UUID,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    recorded_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_crew_loc_org ON crew_locations(org_id);
CREATE INDEX idx_loc_history_user_time ON location_history(user_id, recorded_at DESC);
```
