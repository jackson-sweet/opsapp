# Guided Tour - Content & Messaging

**Status**: Planning Phase
**Created**: January 23, 2025

---

## Overview

All text content for guided tours, following OPS brand voice: direct, practical, field-appropriate.

---

## Writing Guidelines

### OPS Voice Principles
- **Direct**: Get to the point in 1-2 sentences
- **Action-Oriented**: Start with verbs (Tap, Swipe, Create)
- **Practical**: Explain "why" in field terms
- **Respectful**: Assume intelligence, not experience
- **Jargon-Free**: Plain language, no tech terms

### Format Rules
- **Sentence 1**: What to do (action)
- **Sentence 2 (optional)**: Why it matters (benefit)
- **Max Length**: 140 characters ideal, 200 max
- **Font**: OPSStyle.Typography.body

### Examples

**Good:**
> "Tap the + button to create a new project. Projects keep all your work organized in one place."

**Bad:**
> "To initialize a new project object in the database, navigate to the creation interface by tapping the plus icon located in the upper right corner."

---

## Universal Messages

### Tour Introduction
```
Welcome message (varies by role - see below)

This tour takes about [X] seconds.
You can skip anytime by tapping "Skip" in the top right.

[Start Tour Button]  [Skip for Now]
```

### Tour Completion
```
You're all set! 🎯

You can retake this tour anytime from Settings → Help.

[Get Started Button]
```

### Skip Confirmation (if >50% complete)
```
Skip Tour?

You're almost done. Skip now and you can restart from Settings later.

[Continue Tour]  [Skip]
```

---

## Admin First-Time Tour

### Welcome
```
Welcome to OPS!

Let's get you set up. This quick tour shows you how to manage your crew and projects.

Estimated time: 90 seconds
```

### Step 1: Home Screen
```
This is your command center.

See today's active projects and quickly jump to what needs attention.
```

### Step 2: Job Board
```
Tap here to see all your company's work.

The Job Board shows every project, organized by status.
```

### Step 3: Create Project
```
Tap the + button to create a new project.

Every job starts here—add client details, timeline, and team members.
```

### (Additional steps TBD)

---

## Office Crew Tour

### Welcome
```
Welcome to OPS!

Let's show you how to manage projects and coordinate with your team.

Estimated time: 60 seconds
```

### (Steps TBD)

---

## Field Crew Tour

### Welcome
```
Welcome to OPS!

Let's show you how to view your assignments and update your progress.

Estimated time: 45 seconds
```

### Step 1: Home Screen
```
This is where you'll start each day.

See all your assigned tasks and what's coming up.
```

### Step 2: Task Cards
```
Tap any task to see full details.

Location, materials needed, and team members are all here.
```

### Step 3: Status Updates
```
Swipe right on a task to mark it in progress.

Keep everyone informed as you work.
```

### Step 4: Calendar
```
Tap here to see your full schedule.

Plan your week and see upcoming job sites.
```

### Completion
```
You're ready to go! 🎯

Jump in and we'll help you along the way.

[Get Started]
```

---

## Feature-Specific Tours

### Project Management Tour
```
Managing Projects

Learn how to create, organize, and track your projects.

[Start Tour]  [Skip]
```

### Team Management Tour
```
Managing Your Team

Learn how to invite members, assign roles, and manage seats.

[Start Tour]  [Skip]
```

### Calendar Tour
```
Using the Calendar

Learn how to schedule work and track your crew's availability.

[Start Tour]  [Skip]
```

---

## Error Messages

### Tour Interrupted
```
Tour Paused

Return anytime from Settings → Help → "Continue Tour"

[OK]
```

### Tour Unavailable (Offline)
```
Tour Requires Connection

The guided tour needs an internet connection. Try again when online.

[OK]
```

---

## Settings Integration

### Help Menu Item
```
Settings → Help

• Take Tour Again
• View Help Articles
• Contact Support
```

### Tour Option
```
Take Tour Again

Retake the guided tour to refresh your knowledge.

[Start Tour]
```

---

## Placeholder Text Guidelines

During development, use:
```
[Tour Message #X]
Lorem ipsum dolor sit amet, consectetur adipiscing elit.
```

Replace before shipping with actual content from this document.

---

## Localization Notes

### Translation-Ready
- Keep messages simple and direct
- Avoid idioms or cultural references
- Use universal symbols where possible
- Test character length in other languages

### Priority Languages (Future)
- Spanish (high priority for field crews)
- French
- Portuguese

---

## Content Approval Checklist

Before finalizing any tour message:
- [ ] Follows OPS brand voice
- [ ] Under 200 characters
- [ ] Action-oriented
- [ ] Field-appropriate language
- [ ] No jargon or technical terms
- [ ] Tested with target user type
- [ ] Accessible (clear, simple)

---

## Notes

- Content is NOT finalized yet - this is planning phase
- All text should be reviewed with actual users before implementation
- Field crews should review and approve field-focused content
- Keep iterating based on user feedback
