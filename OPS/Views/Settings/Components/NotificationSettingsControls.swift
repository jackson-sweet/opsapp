//
//  NotificationSettingsControls.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-12.
//

import SwiftUI

struct NotificationTimeWindow: View {
    @Binding var startHour: Int
    @Binding var endHour: Int
    var title: String
    var description: String
    
    private let hours = Array(0...23)
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(description)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                // Start time picker
                HStack {
                    Text("From:")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Picker("", selection: $startHour) {
                        ForEach(hours, id: \.self) { hour in
                            Text("\(formatHour(hour))")
                                .tag(hour)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                }

                // End time picker
                HStack {
                    Text("To:")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Picker("", selection: $endHour) {
                        ForEach(hours, id: \.self) { hour in
                            Text("\(formatHour(hour))")
                                .tag(hour)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                }
            }
            
            // Preview of selected time window
            Text("You will receive notifications between \(formatHour(startHour)) and \(formatHour(endHour))")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.top, OPSStyle.Layout.spacing1)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.largeCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func formatHour(_ hour: Int) -> String {
        let hourString = hour == 0 ? "12" : hour > 12 ? "\(hour - 12)" : "\(hour)"
        let amPm = hour >= 12 ? "PM" : "AM"
        return "\(hourString) \(amPm)"
    }
}

struct NotificationPrioritySelector: View {
    @Binding var selectedPriority: NotificationPriority
    
    enum NotificationPriority: String, CaseIterable, Identifiable {
        case all = "All Updates"
        case important = "Important Only"
        case critical = "Critical Only"
        
        var id: String { self.rawValue }
        
        var description: String {
            switch self {
            case .all:
                return "Receive all notifications related to your projects"
            case .important:
                return "Only receive updates about status changes and client messages"
            case .critical:
                return "Only receive notifications about urgent matters requiring attention"
            }
        }
        
        var icon: String {
            switch self {
            case .all:
                return "bell.fill"
            case .important:
                return "exclamationmark.circle.fill"
            case .critical:
                return "exclamationmark.triangle.fill"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text("Notification Priority")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            VStack(spacing: OPSStyle.Layout.spacing2_5) {
                ForEach(NotificationPriority.allCases) { priority in
                    Button(action: {
                        withAnimation {
                            selectedPriority = priority
                        }
                    }) {
                        HStack(spacing: OPSStyle.Layout.spacing3) {
                            // Icon
                            ZStack {
                                Circle()
                                    .fill(selectedPriority == priority ?
                                          OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackground)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: priority.icon)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(selectedPriority == priority ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                            }
                            
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                Text(priority.rawValue)
                                    .font(selectedPriority == priority ? OPSStyle.Typography.bodyEmphasis : OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                
                                Text(priority.description)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                            
                            // Selection indicator
                            if selectedPriority == priority {
                                Image(systemName: OPSStyle.Icons.checkmark)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .bold))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                        }
                        .padding(OPSStyle.Layout.spacing2_5)
                        .background(selectedPriority == priority ?
                                    OPSStyle.Colors.subtleBackground : OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.largeCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

struct TemporaryMuteControl: View {
    @Binding var isMuted: Bool
    @Binding var muteHours: Int
    @State private var muteEndTime: Date?
    
    private let muteOptions = [1, 2, 4, 8, 24]
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            HStack {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("Temporary Mute")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text("Silence notifications for a specific period")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                Toggle("", isOn: $isMuted)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.text))
                    .onChange(of: isMuted) { _, newValue in
                        if newValue {
                            // Set mute end time when enabling
                            muteEndTime = Calendar.current.date(byAdding: .hour, value: muteHours, to: Date())
                        } else {
                            // Clear end time when disabling
                            muteEndTime = nil
                        }
                    }
            }
            
            if isMuted {
                VStack(spacing: OPSStyle.Layout.spacing2_5) {
                    // Mute duration options
                    HStack {
                        Text("Mute for:")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Spacer()
                        
                        // Segmented control for mute duration
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(muteOptions, id: \.self) { hours in
                                Button(action: {
                                    muteHours = hours
                                    muteEndTime = Calendar.current.date(byAdding: .hour, value: hours, to: Date())
                                }) {
                                    Text("\(hours)h")
                                        .font(OPSStyle.Typography.caption)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                                        .background(muteHours == hours ?
                                                    OPSStyle.Colors.primaryText : OPSStyle.Colors.cardBackground)
                                        .foregroundColor(muteHours == hours ? OPSStyle.Colors.invertedText : OPSStyle.Colors.primaryText)
                                        .cornerRadius(OPSStyle.Layout.largeCornerRadius)
                                }
                            }
                        }
                    }
                    
                    // Show when notifications will resume
                    if let endTime = muteEndTime {
                        HStack {
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Text("Notifications will resume at \(formatTime(endTime))")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.largeCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.largeCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}