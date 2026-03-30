//
//  SchedulingCalendarWizard.swift
//  OPS
//
//  Contextual wizard for the schedule/calendar feature.
//  Triggers on first Calendar tab visit. Walks users through
//  week view, day selection, month view, and task interaction.
//

import Foundation

struct SchedulingCalendarWizard: WizardDefinitionProtocol {
    let wizardId = "scheduling_calendar"
    let displayName = "SCHEDULING & CALENDAR"
    let displayDescription = "See your crew's schedule at a glance. Browse by week or month, filter by team member, and tap any task for details."
    let bulletPoints = [
        "Navigate the week view",
        "Select a day to see scheduled tasks",
        "Switch to month view for the big picture",
        "Tap a task for full details"
    ]
    let iconName = "calendar"
    let triggerType: WizardTriggerType = .contextual
    let minimumTier: WizardAccessTier = .field
    let bannerText = "Want a quick tour of your schedule?"

    let steps: [WizardStepDefinition] = [
        WizardStepDefinition(
            id: "scroll_week",
            instruction: "SWIPE TO BROWSE THE WEEK",
            description: "Swipe left or right on the week strip to see other days.",
            targetScreen: "Schedule",
            completionNotification: "WizardCalendarWeekScrolled"
        ),
        WizardStepDefinition(
            id: "tap_day",
            instruction: "TAP A DAY TO SEE ITS TASKS",
            description: "Select any day on the strip to view what's scheduled.",
            targetScreen: "Schedule",
            completionNotification: "WizardCalendarDayTapped"
        ),
        WizardStepDefinition(
            id: "toggle_month",
            instruction: "SWITCH TO MONTH VIEW",
            description: "Tap the calendar icon in the top-right header.",
            targetScreen: "Schedule",
            completionNotification: "WizardCalendarMonthToggled"
        ),
        WizardStepDefinition(
            id: "explore_month",
            instruction: "EXPLORE THE MONTH",
            description: "Scroll through the month or pinch to resize rows.",
            targetScreen: "Schedule",
            canSkip: true,
            completionNotification: "WizardCalendarMonthExplored"
        ),
        WizardStepDefinition(
            id: "tap_month_day",
            instruction: "TAP A DAY TO SEE ITS EVENTS",
            description: "Tap any day in the month grid to open its event list.",
            targetScreen: "Schedule",
            canSkip: true,
            completionNotification: "WizardCalendarMonthDayTapped"
        ),
        WizardStepDefinition(
            id: "tap_task",
            instruction: "TAP A TASK FOR DETAILS",
            description: "Tap any task card to open the full project view.",
            targetScreen: "Schedule",
            canSkip: true,
            completionNotification: "WizardCalendarTaskTapped"
        )
    ]
}
