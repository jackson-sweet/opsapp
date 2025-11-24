# Guided Tour Implementation

**Status**: 📋 Planning Phase
**Priority**: High - User Onboarding & Experience
**Created**: January 23, 2025

---

## Quick Links

- **[PLANNING.md](./PLANNING.md)** - Main planning document, goals, and approach
- **[USER_FLOWS.md](./USER_FLOWS.md)** - Step-by-step tour sequences for each user type
- **[TECHNICAL_SPEC.md](./TECHNICAL_SPEC.md)** - Architecture and implementation details
- **[CONTENT.md](./CONTENT.md)** - All tour text and messaging

---

## Overview

This folder contains planning documentation for implementing a comprehensive guided tour system in the OPS iOS app. The goal is to onboard new users effectively while maintaining OPS's tactical, field-first design philosophy.

---

## Current Phase: Planning

**What We're Doing Now:**
- Defining tour structure and content
- Mapping user flows for different roles
- Designing technical architecture
- Writing tour messaging

**What We're NOT Doing Yet:**
- Writing any code
- Building UI components
- Testing with users
- Implementing in the app

---

## Key Principles

### OPS Brand Alignment
✅ **Tactical Minimalism** - Clean, focused, no fluff
✅ **Field-First Design** - Works with gloves, in sunlight
✅ **Dependable** - Clear, predictable, reliable
✅ **Action-Oriented** - Show users how to do things
✅ **Respectful** - Quick, skippable, non-patronizing

### User Focus
- **Primary**: Field crews (lowest tech literacy, highest need)
- **Secondary**: Office crews and admins
- **Tertiary**: Existing users seeking refreshers

---

## Planning Documents

### 1. PLANNING.md
**Purpose**: High-level strategy and approach
**Contents**:
- Goals and success metrics
- User types and their needs
- Features to include in tours
- Design principles and constraints
- Open questions for decision

### 2. USER_FLOWS.md
**Purpose**: Exact step-by-step tour sequences
**Contents**:
- Tour variants (admin, office, field)
- Step-by-step walkthroughs
- Timing and duration targets
- Navigation patterns
- Entry and exit points

### 3. TECHNICAL_SPEC.md
**Purpose**: Implementation architecture
**Contents**:
- Component structure
- Data models
- State management
- UI components
- Integration points
- Performance considerations

### 4. CONTENT.md
**Purpose**: All tour text and messaging
**Contents**:
- Writing guidelines (OPS voice)
- Tour scripts for each user type
- Universal messages (welcome, completion, errors)
- Localization notes
- Approval checklist

---

## Next Steps

### Phase 1: Complete Planning (Current)
- [x] Define exact tour flows for each user role
- [x] Research all feature implementations
- [x] Define sample mock data for field tour
- [ ] Write all tour content (refine CONTENT.md)
- [ ] Design visual mockups (spotlight, tooltips, animations)
- [ ] Get stakeholder approval on approach

### Phase 2: Technical Foundation
- [ ] Create tour data models
- [ ] Build state management system
- [ ] Implement persistence layer
- [ ] Set up integration points

### Phase 3: UI Implementation
- [ ] Build overlay view component
- [ ] Create tooltip component
- [ ] Implement spotlight highlighting
- [ ] Add animations and transitions

### Phase 4: Content & Polish
- [ ] Integrate tour content
- [ ] Implement tour coordinator
- [ ] Add accessibility features
- [ ] User testing and refinement

---

## Resolved Questions

### Strategic ✅

**1. Should we have one comprehensive tour or multiple mini-tours?**
- **Decision**: Two role-based tours (Office/Admin and Field Crew)
- **Rationale**: Different roles have different needs and tech literacy levels. Field crews need faster, simpler onboarding focused on viewing/updating tasks. Office/admin need comprehensive project management coverage.

**2. Different tours for different user roles or one adaptive tour?**
- **Decision**: Separate tours for each role
- **Rationale**: Simpler implementation, clearer messaging, respects user's time. Field tour is 45s, office tour is 90s.

**3. Should tours be interactive (users perform actions) or observational?**
- **Decision**: Observational with demonstrations
- **Rationale**: More reliable, faster completion, no risk of user getting stuck. Users tap "Next" to progress through steps. Gesture steps (swipe, pinch, long press) show animated demonstrations rather than requiring user to perform them.

### UX ✅

**4. How do we indicate progress? ("Step 3 of 12" vs just "Next")**
- **Decision**: Simple "Next" button with optional progress dots
- **Rationale**: Progress numbers can feel overwhelming ("Step 3 of 12" makes it feel long). Progress dots show position without creating anxiety. Aligns with tactical minimalism.

**5. What happens when users skip? Any features locked?**
- **Decision**: No features locked, show skip confirmation only if >50% complete
- **Rationale**: Never lock features based on tour completion - that's hostile UX. Users can always retake tour from Settings → Help → Take Tour Again.

**6. How do users re-access tours after dismissing?**
- **Decision**: Settings → Help → "Take Tour Again"
- **Rationale**: Standard location for help resources. Tour completion screen explicitly tells users this location.

### Technical ⏳

**7. How to reliably target UI elements across navigation changes?**
- **Decision**: TBD during implementation
- **Options**:
  - View identifiers with `.id()` modifier
  - GeometryReader for coordinate-based targeting
  - Combine both for reliability
- **Preference**: View identifiers where possible, coordinates as fallback

**8. Should tours resume after app backgrounding?**
- **Decision**: No, restart from beginning
- **Rationale**: Tours are short (45-90s). Resuming adds complexity for minimal benefit. If interrupted, users can quickly restart or skip entirely.

**9. What's the spotlight implementation approach?**
- **Decision**: TBD during implementation
- **Options**:
  - SwiftUI overlay with mask (cleaner, native)
  - CoreGraphics compositing (more control)
- **Preference**: SwiftUI overlay with `.mask()` for simplicity, unless performance issues require CoreGraphics

## Open Questions (Remaining)

### Visual Design
1. **Spotlight shape**: Perfect circle, rounded rect, or match target element shape?
2. **Tooltip arrow**: Always pointing to target, or positioned contextually?
3. **Gesture animations**: Use Lottie files, SF Symbols animations, or custom SwiftUI animations?
4. **Dark overlay opacity**: 0.8, 0.85, or 0.9 for optimal visibility?

### Implementation Details
5. **Tour trigger timing**: Immediately on first launch, or after first data sync completes?
6. **Sample data injection**: When/where to inject mock projects for field tour demo?
7. **Analytics**: Track completion rates, drop-off points, skip reasons?

---

## Success Metrics

### Completion Metrics
- Tour completion rate (target: >70%)
- Average time to complete
- Drop-off points
- Skip rate by step

### Impact Metrics
- Time to first project creation (before vs after tour)
- Feature adoption rate (toured vs not toured)
- Support ticket reduction
- User retention at 7/30 days

---

## Brand Guidelines Reference

From CLAUDE.md:

> "OPS speaks with the confident, straightforward voice of an experienced field supervisor who has earned respect through practical knowledge."

**Tour Voice Should Be:**
- Direct and to-the-point
- Practical, not theoretical
- Confident without being condescending
- Action-focused
- Field-appropriate language

**Tour Voice Should NOT Be:**
- Cute or playful
- Overly technical
- Lengthy or verbose
- Assuming high tech literacy
- Corporate or formal

---

## Related OPS Documentation

- `/CLAUDE.md` - OPS brand guidelines and design philosophy
- `/UI_GUIDELINES.md` - UI standards and component patterns
- `/COMPONENTS.md` - Reusable component library

---

## Notes for Implementation

### When Starting Implementation:
1. Review all planning docs thoroughly
2. Verify alignment with OPS brand guidelines
3. Use existing OPS components where possible
4. Follow established code patterns
5. Test extensively with target users

### Remember:
- Field crews are the primary audience
- Simplicity beats completeness
- Every second counts - be concise
- Must work in challenging conditions
- Skippable is not optional

---

## Version History

- **2025-01-23**: Initial planning documents created
- Planning phase in progress

---

## Contact

For questions or suggestions about the guided tour implementation, refer to the planning documents or add notes to the relevant section.
