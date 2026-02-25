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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(description)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            HStack(spacing: 8) {
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
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(OPSStyle.Colors.cardBackground.opacity(0.6))
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
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                }
            }
            
            // Preview of selected time window
            Text("You will receive notifications between \(formatHour(startHour)) and \(formatHour(endHour))")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.top, 4)
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.largeCornerRadius)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Notification Priority")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            VStack(spacing: 12) {
                ForEach(NotificationPriority.allCases) { priority in
                    Button(action: {
                        withAnimation {
                            selectedPriority = priority
                        }
                    }) {
                        HStack(spacing: 16) {
                            // Icon
                            ZStack {
                                Circle()
                                    .fill(selectedPriority == priority ? 
                                          OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackground)
                                    .frame(width: 36, height: 36)
                                
                                Image(systemName: priority.icon)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(selectedPriority == priority ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
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
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                        }
                        .padding(12)
                        .background(selectedPriority == priority ? 
                                    OPSStyle.Colors.primaryAccent.opacity(0.15) : OPSStyle.Colors.cardBackground.opacity(0.3))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    }
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.largeCornerRadius)
    }
}

struct TemporaryMuteControl: View {
    @Binding var isMuted: Bool
    @Binding var muteHours: Int
    @State private var muteEndTime: Date?
    
    private let muteOptions = [1, 2, 4, 8, 24]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
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
                    .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.primaryAccent))
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
                VStack(spacing: 12) {
                    // Mute duration options
                    HStack {
                        Text("Mute for:")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Spacer()
                        
                        // Segmented control for mute duration
                        HStack(spacing: 8) {
                            ForEach(muteOptions, id: \.self) { hours in
                                Button(action: {
                                    muteHours = hours
                                    muteEndTime = Calendar.current.date(byAdding: .hour, value: hours, to: Date())
                                }) {
                                    Text("\(hours)h")
                                        .font(OPSStyle.Typography.caption)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(muteHours == hours ? 
                                                    OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackground)
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
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            
                            Text("Notifications will resume at \(formatTime(endTime))")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.largeCornerRadius)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}