# TOP GUN TUTORIAL DEMO DATABASE

Interactive onboarding sandbox data for OPS App.

---

## STATUS DEFINITIONS

### Project Statuses
- **ACCEPTED** — Project confirmed, no tasks scheduled yet
- **SCHEDULED** — All tasks booked for future dates
- **IN_PROGRESS** — At least one task currently active
- **COMPLETED** — All tasks finished

### Task Statuses
- **BOOKED** — Scheduled for future date
- **IN_PROGRESS** — Currently active (within ±1 day of current date)
- **COMPLETED** — Finished (past current date)

---

## TEAM MEMBERS

| Name | Specialization | Task Types |
|------|----------------|------------|
| Pete Mitchell | Finishes & Coatings Lead | Coating, Sealing, Painting |
| Nick Bradshaw | Structural & Mechanical | Installation, Removal |
| Tom Kazansky | Heavy Work & Prep | Demolition, Pressure Wash |
| Mike Metcalf | Inspection & Detail | Diagnostic, Cleaning |
| Rick Heatherly | Exterior & Grounds | Landscaping, Planting, Paving |

---

## CLIENTS

| Client Name | Type | Address |
|-------------|------|---------|
| Miramar Flight Academy | Military/Aviation | 9800 Anderson St, San Diego, CA 92126 |
| Charlie Blackwood | Residential | 10452 Scripps Lake Dr, San Diego, CA 92131 |
| O'Club Bar & Grill | Commercial/Hospitality | 8680 Miralani Dr, San Diego, CA 92126 |
| Fightertown Hangars LLC | Aviation/Industrial | 5915 Mira Mesa Blvd, San Diego, CA 92121 |
| Miramar Officer Housing | Residential Complex | 11056 Portobelo Dr, San Diego, CA 92124 |

---

## TASK TYPES

| Type | Hex Color | Typical Use |
|------|-----------|-------------|
| CLEANING | #A8D8B9 | Detail work, post-job cleanup |
| DEMOLITION | #E8A87C | Tear-out, removal of existing |
| PAINTING | #89B4E8 | Surface coating, finishing |
| SEALING | #B4C7E8 | Waterproofing, protective coating |
| PAVING | #C4B7D4 | Concrete, asphalt work |
| LANDSCAPING | #8FD4A4 | Grading, hardscape, design |
| INSTALLATION | #D4A8C7 | Mounting, assembly, setup |
| PRESSURE_WASH | #E8D48A | Surface prep, cleaning |
| DIAGNOSTIC | #8AD4D4 | Inspection, assessment |
| REMOVAL | #E8B89A | Extraction, disposal |
| COATING | #7AA8D4 | Epoxy, sealant application |
| PLANTING | #B8E8A8 | Vegetation, turf install |

---

## PROJECTS

### COMPLETED PROJECTS
*All tasks scheduled before current date*

#### 1. MIG Detailing
- **Client:** Fightertown Hangars LLC
- **Address:** 5915 Mira Mesa Blvd, San Diego, CA 92121
- **Status:** COMPLETED

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| CLEANING | Mike Metcalf | current - 14 days | COMPLETED |

---

#### 2. Locker Room Renovation
- **Client:** Miramar Flight Academy
- **Address:** 9800 Anderson St, San Diego, CA 92126
- **Status:** COMPLETED
- **Description:** Full repaint and new lockers in pilot ready room.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| DEMOLITION | Tom Kazansky | current - 21 days | COMPLETED | Old lockers hauled to Miramar Recycling |
| PAINTING | Pete Mitchell | current - 18 days | COMPLETED | SW Naval SW-6244, eggshell finish |
| INSTALLATION | Nick Bradshaw, Tom Kazansky | current - 15 days | COMPLETED | 24 new lockers, bolted to wall |

---

#### 3. Officer Housing Landscape Phase 1
- **Client:** Miramar Officer Housing
- **Address:** 11056 Portobelo Dr, San Diego, CA 92124
- **Status:** COMPLETED

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| REMOVAL | Nick Bradshaw | current - 12 days | COMPLETED |
| PLANTING | Rick Heatherly | current - 10 days | COMPLETED |

---

#### 4. Charlie's Driveway Sealing
- **Client:** Charlie Blackwood
- **Address:** 10452 Scripps Lake Dr, San Diego, CA 92131
- **Status:** COMPLETED
- **Description:** Prep and seal asphalt driveway. Small job, half day.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| PRESSURE_WASH | Tom Kazansky | current - 8 days | COMPLETED | Oil stain near garage needed degreaser |
| SEALING | Pete Mitchell | current - 6 days | COMPLETED | Coal tar emulsion, 24hr cure |

---

#### 5. O'Club Kitchen Hood Cleaning
- **Client:** O'Club Bar & Grill
- **Address:** 8680 Miralani Dr, San Diego, CA 92126
- **Status:** COMPLETED

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| CLEANING | Mike Metcalf | current - 5 days | COMPLETED |

---

### IN PROGRESS PROJECTS
*At least one task within ±1 day of current date*

#### 6. Flight Deck Coating
- **Client:** Miramar Flight Academy
- **Address:** 9800 Anderson St, San Diego, CA 92126
- **Status:** IN_PROGRESS
- **Images:** `flight_deck_before.png`, `flight_deck_progress.png`
- **Description:** Recoat helicopter landing pad. Must meet military slip-resistance spec.
- **Team Notes:** CO signed off on 48hr cure time. No flight ops until Friday.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| REMOVAL | Nick Bradshaw | current - 3 days | COMPLETED | Old coating came up easier than expected |
| COATING | Pete Mitchell | current | IN_PROGRESS | Using MIL-PRF-24667 gray, 2 coats |
| SEALING | Pete Mitchell | current + 2 days | BOOKED | Anti-slip aggregate in final coat |

---

#### 7. O'Club Patio Resurface
- **Client:** O'Club Bar & Grill
- **Address:** 8680 Miralani Dr, San Diego, CA 92126
- **Status:** IN_PROGRESS
- **Images:** `oclub_patio_area.png`, `oclub_patio_demo.png`
- **Description:** Demo old cracked patio, pour new stamped concrete. Pattern: Arizona flagstone.
- **Team Notes:** Bar stays open during work. Keep debris away from entrance. Manager is Carole.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| DEMOLITION | Tom Kazansky | current - 1 day | COMPLETED | Rented 60lb breaker from Sunbelt |
| PAVING | Rick Heatherly | current | IN_PROGRESS | 4" slab, 3000 PSI mix |

---

#### 8. Hangar Siding Repair
- **Client:** Fightertown Hangars LLC
- **Address:** 5915 Mira Mesa Blvd, San Diego, CA 92121
- **Status:** IN_PROGRESS
- **Images:** `hangar_exterior.png`, `hangar_siding_damage.png`
- **Description:** Replace damaged corrugated panels on east wall. Forklift struck building last month.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| REMOVAL | Nick Bradshaw | current - 2 days | COMPLETED | 3 panels removed, saved fasteners |
| INSTALLATION | Nick Bradshaw | current + 1 day | BOOKED | New panels are 26 gauge galvanized. Bring the Hilti |

---

#### 9. Charlie's Home Office Remodel
- **Client:** Charlie Blackwood
- **Address:** 10452 Scripps Lake Dr, San Diego, CA 92131
- **Status:** IN_PROGRESS
- **Images:** `home_office_demo.png`, `home_office_paint_samples.png`
- **Description:** Convert spare bedroom to home office. New paint, built-in shelving unit.
- **Team Notes:** Client works from home - keep noise to reasonable hours. Dog is friendly.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| DEMOLITION | Tom Kazansky | current - 2 days | COMPLETED | Old carpet removed, subfloor is solid |
| PAINTING | Pete Mitchell | current | IN_PROGRESS | Benjamin Moore Hale Navy HC-154 |
| INSTALLATION | Nick Bradshaw | current + 3 days | BOOKED | IKEA BILLY shelves, client purchased |

---

#### 10. Parking Lot Striping
- **Client:** Miramar Flight Academy
- **Address:** 9800 Anderson St, San Diego, CA 92126
- **Status:** IN_PROGRESS
- **Images:** `parking_lot_washed.png`
- **Description:** Repaint faded parking lines and add new handicap stalls near building entrance.
- **Team Notes:** Use federal yellow for standard lines. Blue for handicap. Stencils in truck bed.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| PRESSURE_WASH | Tom Kazansky | current - 1 day | COMPLETED | Started at 0600 before lot got busy |
| PAINTING | Pete Mitchell | current + 1 day | BOOKED | 4" lines, federal spec yellow |

---

### SCHEDULED PROJECTS
*All tasks booked for future dates*

#### 11. Jet Interior Reupholstery
- **Client:** Fightertown Hangars LLC
- **Address:** 5915 Mira Mesa Blvd, San Diego, CA 92121
- **Status:** SCHEDULED
- **Images:** `jet_interior_current.png`
- **Description:** Strip and reupholster 6 cabin seats. Leather provided by client.
- **Team Notes:** Aircraft is Cessna Citation II, tail N429TG. Hangar 3, bay 2.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| REMOVAL | Nick Bradshaw | current + 5 days | BOOKED | Unbolt seats, tag all hardware |
| CLEANING | Mike Metcalf | current + 7 days | BOOKED | Degrease frames, clean trim panels |
| INSTALLATION | Nick Bradshaw | current + 10 days | BOOKED | Torque specs in aircraft manual |

---

#### 12. Runway Crack Repair
- **Client:** Miramar Flight Academy
- **Address:** 9800 Anderson St, San Diego, CA 92126
- **Status:** SCHEDULED
- **Images:** `runway_overview.png`, `runway_cracks.png`
- **Description:** Seal and coat taxiway Charlie cracks. FAA inspection scheduled for end of month.
- **Team Notes:** Work window is 0500-0800 only. Must be off taxiway by 0815 for flight ops.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| DIAGNOSTIC | Mike Metcalf | current + 4 days | BOOKED | Map all cracks over 1/4", photo document |
| SEALING | Pete Mitchell | current + 8 days | BOOKED | Crafco 34864 hot pour sealant |
| COATING | Pete Mitchell | current + 11 days | BOOKED | P-608 coal tar emulsion, 2 coats |

---

#### 13. Briefing Room Tech Install
- **Client:** Miramar Flight Academy
- **Address:** 9800 Anderson St, San Diego, CA 92126
- **Status:** SCHEDULED
- **Images:** `briefing_room_current.png`
- **Description:** Mount two 75" displays and AV rack for new briefing system.
- **Team Notes:** IT will run cables before we arrive. We just mount and secure.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| INSTALLATION | Nick Bradshaw | current + 6 days | BOOKED | Chief large tilting mounts (client provided) |

---

#### 14. Pool Deck Sealing
- **Client:** Miramar Officer Housing
- **Address:** 11056 Portobelo Dr, San Diego, CA 92124
- **Status:** SCHEDULED
- **Description:** Pressure wash and seal community pool deck before summer season.
- **Team Notes:** Pool will be drained and closed. HOA contact is Lt. Davis.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| PRESSURE_WASH | Tom Kazansky | current + 9 days | BOOKED | 3000 PSI, surface cleaner attachment |
| SEALING | Pete Mitchell | current + 12 days | BOOKED | Behr wet-look concrete sealer, 2 coats |

---

#### 15. O'Club Entrance Landscaping
- **Client:** O'Club Bar & Grill
- **Address:** 8680 Miralani Dr, San Diego, CA 92126
- **Status:** SCHEDULED
- **Description:** Remove dead hedges, install drought-tolerant plants and rock mulch.
- **Team Notes:** This is phase 2 after patio job. Same contact - Carole.

| Task Type | Crew | Date | Task Status | Notes |
|-----------|------|------|-------------|-------|
| REMOVAL | Nick Bradshaw | current + 7 days | BOOKED | 12 dead boxwoods, roots and all |
| LANDSCAPING | Rick Heatherly | current + 10 days | BOOKED | Grade for drainage away from building |
| PLANTING | Rick Heatherly | current + 14 days | BOOKED | 8 agave, 6 lavender, desert gold gravel |

---

## SUMMARY

| Metric | Value |
|--------|-------|
| Team Members | 5 |
| Clients | 5 |
| Projects | 15 (5 completed, 5 in progress, 5 scheduled) |
| Tasks | 36 total |
| Task Types | 12 with pastel hex colors |

---

## IMPLEMENTATION NOTES

### Date Calculation
All dates are relative to `current` (the date when demo data is seeded):
- `current - N days` = past date
- `current` = today
- `current + N days` = future date

### Crew Assignment Rules
Each team member stays within their specialization:
- **Pete Mitchell** → Only assigned to COATING, SEALING, PAINTING tasks
- **Nick Bradshaw** → Only assigned to INSTALLATION, REMOVAL tasks
- **Tom Kazansky** → Only assigned to DEMOLITION, PRESSURE_WASH tasks
- **Mike Metcalf** → Only assigned to DIAGNOSTIC, CLEANING tasks
- **Rick Heatherly** → Only assigned to LANDSCAPING, PLANTING, PAVING tasks

### Status Derivation Logic
```
Task Status:
- scheduledDate < current → COMPLETED
- scheduledDate within ±1 day of current → IN_PROGRESS
- scheduledDate > current + 1 day → BOOKED

Project Status:
- All tasks COMPLETED → COMPLETED
- Any task IN_PROGRESS → IN_PROGRESS
- All tasks BOOKED → SCHEDULED
- No tasks scheduled → ACCEPTED
```
