# Guided Tour Implementation - Planning

**Status**: Planning Phase
**Created**: January 23, 2025
**Priority**: High - Onboarding & User Experience

---

## Overview

Create a comprehensive guided tour system to onboard new users and introduce them to OPS features. The tour should be tactical, minimal, and field-appropriate, matching OPS design philosophy.

---

## Goals

### Primary Goals
- Reduce time to first value for new users
- Introduce core features in logical order
- Build confidence for field crews unfamiliar with digital tools
- Minimize confusion and support requests

### Secondary Goals
- Re-engageable for existing users who want a refresher
- Skippable without penalty
- Non-intrusive for experienced users
- Track completion for analytics

---

## User Types to Consider

1. **Company Admin (First Login)**
   - Setting up organization for the first time
   - Needs: Company setup, team invites, subscription management, project creation

2. **Office Crew Member**
   - Managing projects and scheduling
   - Needs: Project management, client management, task assignment, calendar

3. **Field Crew Member**
   - Executing tasks on job sites
   - Needs: Task viewing, status updates, time tracking, navigation

4. **Existing Users**
   - May want feature refreshers
   - Needs: Access to tour on-demand, individual feature highlights

---

## Core Features to Tour

### Critical Features (Must Include)
- [ ] Home screen navigation
- [ ] Job Board overview
- [ ] Creating/viewing projects
- [ ] Managing tasks
- [ ] Team member assignment
- [ ] Status updates
- [ ] Calendar navigation

### Important Features (Should Include)
- [ ] Client management
- [ ] Task types
- [ ] Project colors/organization
- [ ] Swipe gestures for status changes
- [ ] Filtering and search

### Nice-to-Have Features
- [ ] Settings and preferences
- [ ] Notifications
- [ ] Export/reporting features

---

## Tour Trigger Points

### When to Show Tour

**First-Time Users:**
- After completing authentication
- After company selection/creation
- Immediately before first main screen

**Existing Users:**
- Manual trigger from Settings → Help → "Take Tour"
- After major feature updates (optional)
- When user appears stuck (analytics-based, future)

### When NOT to Show Tour
- During active project/task work
- When user has explicitly dismissed
- During subscription/payment flows
- In offline mode

---

## Design Principles

### OPS Brand Alignment
- **Tactical Minimalism**: Clean, direct instructions without fluff
- **Field-First**: Assume low tech literacy, bright sunlight, gloves
- **Dependable**: Clear next steps, no ambiguity
- **Respectful**: Quick to complete, easy to skip
- **Action-Oriented**: Focus on "how to do X" not "this is X"

### Visual Style
- Dark overlays to focus attention
- Minimal text (1-2 sentences max per step)
- Large touch targets for "Next" buttons
- Clear progress indicators
- OPS color palette and typography

---

## Technical Considerations

### Implementation Approach
- **Overlay-based**: Spotlight specific UI elements
- **Step-by-step**: Linear progression through features
- **Context-aware**: Different tours for different user roles
- **Persistent state**: Remember progress, allow resume
- **Dismissible**: Easy exit at any point

### Data Storage
- UserDefaults for tour completion status
- Track which tours completed
- Track individual step progress
- Don't sync to Bubble (local preference)

### Performance
- No impact on app launch time
- Lightweight overlays
- Minimal animation (tactical, not flashy)
- Works offline

---

## Open Questions

1. **Tour Length**: Single comprehensive tour vs. multiple mini-tours?
2. **Interactivity**: Should users perform actions or just observe?
3. **Role-Based**: Different tours for admin/office/field roles?
4. **Frequency**: One-time only or repeatable?
5. **Skip Consequences**: Any features locked behind tour completion?
6. **Progress Indication**: Show "Step 3 of 12" or just "Next"?
7. **Celebration**: Any completion reward/acknowledgment?

---

## Success Metrics

### Immediate Metrics
- Tour completion rate
- Tour skip rate
- Average time to complete
- Drop-off points (which steps users quit)

### Long-Term Metrics
- Feature adoption rate (toured vs. not toured)
- Support ticket reduction
- Time to first project creation
- User retention after 7/30 days

---

## Competitive Analysis

### What Other Apps Do Well
- TBD: Research competitor onboarding flows

### What to Avoid
- Lengthy tutorials (>2 minutes)
- Too much text
- Blocking critical actions
- No skip option
- Forced re-tours

---

## Next Steps

1. **User Flow Design**: Map out exact tour steps for each user type
2. **Technical Spec**: Define component architecture and state management
3. **Content Writing**: Draft all tooltip text following OPS voice
4. **Visual Mockups**: Design overlay appearance and animations
5. **Implementation Plan**: Break work into phases
6. **Testing Strategy**: Define how to validate effectiveness

---

## Related Documentation

- [USER_FLOWS.md](./USER_FLOWS.md) - Detailed step-by-step tour sequences
- [TECHNICAL_SPEC.md](./TECHNICAL_SPEC.md) - Implementation architecture
- [CONTENT.md](./CONTENT.md) - All tour text and messaging

---

## Notes

- This is a planning document - nothing should be implemented yet
- Prioritize simplicity over completeness
- Focus on field crew experience (most critical, least tech-savvy)
- Align with OPS brand: dependable, straightforward, field-first
