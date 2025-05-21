//
//  ProjectNotificationPreferences.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-14.
//

import SwiftUI

struct ProjectNotificationPreferences: View {
    @Binding var notifyProjectAssignment: Bool
    @Binding var notifyProjectScheduleChanges: Bool
    @Binding var notifyProjectCompletion: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Notifications")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                NotificationToggleItem(
                    isOn: $notifyProjectAssignment,
                    title: "Project Assignments",
                    description: "When you are assigned to a project"
                )
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                NotificationToggleItem(
                    isOn: $notifyProjectScheduleChanges,
                    title: "Schedule Changes",
                    description: "When a project is scheduled or rescheduled"
                )
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                NotificationToggleItem(
                    isOn: $notifyProjectCompletion,
                    title: "Project Completion",
                    description: "When a project you're assigned to is completed"
                )
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(12)
    }
}

struct AdvanceNoticePreferences: View {
    @Binding var notifyProjectAdvance: Bool
    @Binding var advanceNoticeDays1: Int
    @Binding var advanceNoticeDays2: Int
    @Binding var advanceNoticeDays3: Int
    
    private let dayOptions = [1, 2, 3, 5, 7, 14]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Master toggle with title
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Advance Project Notices")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                    
                    Text("Reminders before project start dates")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                Toggle("", isOn: $notifyProjectAdvance)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.primaryAccent))
            }
            
            if notifyProjectAdvance {
                VStack(spacing: 16) {
                    Text("Send me reminders:")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    // Day selectors
                    HStack(spacing: 8) {
                        reminderDaySelector(dayBinding: $advanceNoticeDays1, label: "1")
                        reminderDaySelector(dayBinding: $advanceNoticeDays2, label: "2")
                        reminderDaySelector(dayBinding: $advanceNoticeDays3, label: "3")
                    }
                    
                    // Preview of selected days
                    Text("You'll be notified \(advanceNoticeDays1), \(advanceNoticeDays2), and \(advanceNoticeDays3) days before project start dates")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(12)
    }
    
    private func reminderDaySelector(dayBinding: Binding<Int>, label: String) -> some View {
        Menu {
            ForEach(dayOptions, id: \.self) { day in
                Button(action: {
                    dayBinding.wrappedValue = day
                }) {
                    if dayBinding.wrappedValue == day {
                        Label("\(day) days", systemImage: "checkmark")
                    } else {
                        Text("\(day) days")
                    }
                }
            }
        } label: {
            HStack {
                Text("\(label):")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text("\(dayBinding.wrappedValue) days")
                    .font(OPSStyle.Typography.captionBold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                
                Image(systemName: "chevron.down")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct NotificationToggleItem: View {
    @Binding var isOn: Bool
    var title: String
    var description: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.primaryAccent))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ProjectNotificationPreferences(
            notifyProjectAssignment: .constant(true),
            notifyProjectScheduleChanges: .constant(true),
            notifyProjectCompletion: .constant(false)
        )
        
        AdvanceNoticePreferences(
            notifyProjectAdvance: .constant(true),
            advanceNoticeDays1: .constant(1),
            advanceNoticeDays2: .constant(3),
            advanceNoticeDays3: .constant(7)
        )
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}