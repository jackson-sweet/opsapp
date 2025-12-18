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

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| DEMOLITION | Tom Kazansky | current - 21 days | COMPLETED |
| PAINTING | Pete Mitchell | current - 18 days | COMPLETED |
| INSTALLATION | Nick Bradshaw, Tom Kazansky | current - 15 days | COMPLETED |

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

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| PRESSURE_WASH | Tom Kazansky | current - 8 days | COMPLETED |
| SEALING | Pete Mitchell | current - 6 days | COMPLETED |

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

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| REMOVAL | Nick Bradshaw | current - 3 days | COMPLETED |
| COATING | Pete Mitchell | current | IN_PROGRESS |
| SEALING | Pete Mitchell | current + 2 days | BOOKED |

---

#### 7. O'Club Patio Resurface
- **Client:** O'Club Bar & Grill
- **Address:** 8680 Miralani Dr, San Diego, CA 92126
- **Status:** IN_PROGRESS

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| DEMOLITION | Tom Kazansky | current - 1 day | COMPLETED |
| PAVING | Rick Heatherly | current | IN_PROGRESS |

---

#### 8. Hangar Siding Repair
- **Client:** Fightertown Hangars LLC
- **Address:** 5915 Mira Mesa Blvd, San Diego, CA 92121
- **Status:** IN_PROGRESS

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| REMOVAL | Nick Bradshaw | current - 2 days | COMPLETED |
| INSTALLATION | Nick Bradshaw | current + 1 day | BOOKED |

---

#### 9. Charlie's Home Office Remodel
- **Client:** Charlie Blackwood
- **Address:** 10452 Scripps Lake Dr, San Diego, CA 92131
- **Status:** IN_PROGRESS

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| DEMOLITION | Tom Kazansky | current - 2 days | COMPLETED |
| PAINTING | Pete Mitchell | current | IN_PROGRESS |
| INSTALLATION | Nick Bradshaw | current + 3 days | BOOKED |

---

#### 10. Parking Lot Striping
- **Client:** Miramar Flight Academy
- **Address:** 9800 Anderson St, San Diego, CA 92126
- **Status:** IN_PROGRESS

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| PRESSURE_WASH | Tom Kazansky | current - 1 day | COMPLETED |
| PAINTING | Pete Mitchell | current + 1 day | BOOKED |

---

### SCHEDULED PROJECTS
*All tasks booked for future dates*

#### 11. Jet Interior Reupholstery
- **Client:** Fightertown Hangars LLC
- **Address:** 5915 Mira Mesa Blvd, San Diego, CA 92121
- **Status:** SCHEDULED

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| REMOVAL | Nick Bradshaw | current + 5 days | BOOKED |
| CLEANING | Mike Metcalf | current + 7 days | BOOKED |
| INSTALLATION | Nick Bradshaw | current + 10 days | BOOKED |

---

#### 12. Runway Crack Repair
- **Client:** Miramar Flight Academy
- **Address:** 9800 Anderson St, San Diego, CA 92126
- **Status:** SCHEDULED

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| DIAGNOSTIC | Mike Metcalf | current + 4 days | BOOKED |
| SEALING | Pete Mitchell | current + 8 days | BOOKED |
| COATING | Pete Mitchell | current + 11 days | BOOKED |

---

#### 13. Briefing Room Tech Install
- **Client:** Miramar Flight Academy
- **Address:** 9800 Anderson St, San Diego, CA 92126
- **Status:** SCHEDULED

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| INSTALLATION | Nick Bradshaw | current + 6 days | BOOKED |

---

#### 14. Pool Deck Sealing
- **Client:** Miramar Officer Housing
- **Address:** 11056 Portobelo Dr, San Diego, CA 92124
- **Status:** SCHEDULED

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| PRESSURE_WASH | Tom Kazansky | current + 9 days | BOOKED |
| SEALING | Pete Mitchell | current + 12 days | BOOKED |

---

#### 15. O'Club Entrance Landscaping
- **Client:** O'Club Bar & Grill
- **Address:** 8680 Miralani Dr, San Diego, CA 92126
- **Status:** SCHEDULED

| Task Type | Crew | Date | Task Status |
|-----------|------|------|-------------|
| REMOVAL | Nick Bradshaw | current + 7 days | BOOKED |
| LANDSCAPING | Rick Heatherly | current + 10 days | BOOKED |
| PLANTING | Rick Heatherly | current + 14 days | BOOKED |

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
