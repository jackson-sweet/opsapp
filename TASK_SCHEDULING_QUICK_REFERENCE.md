# Task Scheduling - Quick Reference Guide

## Key Concepts
- **Projects can now have Tasks** (sub-components like "Site Estimate", "Installation")
- **Each Task gets its own CalendarEvent** for scheduling
- **Simple projects** still work without tasks (direct CalendarEvent on Project)

## Data Flow
```
Company.defaultProjectColor
    ↓
Project (no tasks) → CalendarEvent
    OR
Project → Task → CalendarEvent
          ↑
      TaskType (color, display name)
      
Field Names in Bubble:
- Task: projectID (capital ID), companyId, scheduledDate, completionDate
- CalendarEvent: companyId, projectId, taskId (all lowercase first letter)
- TaskType: Color, Display, isDefault (Option Set)
```

## Permission Rules
| Who | Can Do |
|-----|--------|
| **Field Crew** | View tasks, Update task status |
| **Office Crew** | All above + Create/Edit tasks, Manage TaskTypes |
| **Admin** | Everything |

## Inheritance Chain
- **Color**: TaskType → Task → CalendarEvent (or Company default)
- **Title**: TaskType.Display → CalendarEvent.title
- **Team**: Task.teamMembers → CalendarEvent.teamMembers

## Status Logic
- **Project with tasks**: In Progress if ANY task is In Progress
- **All tasks complete**: Auto-mark project complete
- **No tasks**: Use current project status logic

## Calendar Display
- **Task Event**: Shows task color, task type name
- **Project Event**: Shows default color, project name
- **Visual**: Different colors distinguish event types

## UI Changes
1. **Calendar**: Tap event → Task detail sheet (or project sheet)
2. **Project Details**: New Tasks section above notes
3. **Settings**: New Project Settings for TaskTypes and colors

## Sync Priority
1. CalendarEvents (most time-sensitive)
2. Tasks 
3. Projects
4. TaskTypes (rarely change)

## First Task Behavior
When adding first task to scheduled project:
- Inherits project's calendar dates
- User can modify
- Original project event hidden/removed

## Quick Implementation Checklist
- [ ] Add Task, TaskType, CalendarEvent models
- [ ] Update Project model relationships
- [ ] Calendar view for CalendarEvents
- [ ] Tasks section in ProjectDetailsView
- [ ] Task detail sheet
- [ ] Status update actions
- [ ] Project Settings (Admin/Office)
- [ ] Sync logic for new objects

## Remember
- Tasks are **optional** - simple projects still work
- Backend handles migration - we just sync
- Field crew can update status but not edit
- Colors and icons make tasks visually distinct

---
*This is Version 2.0.0 - The biggest update since launch*